import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:flutter/painting.dart' show Offset;
import '../data/repositories/beacon_repository.dart';
import '../data/repositories/grafo_repository.dart';
import '../models/beacon_config.dart';
import '../models/beacon_reading.dart';
import '../models/position.dart';
import 'ble_service.dart';

/// Convierte un stream de [BeaconReading] (lecturas crudas de BLE) en
/// un stream de [Position] (posición estimada del usuario en el plano).
///
/// El pipeline tiene 5 etapas, todas configurables vía
/// `beacon_config.json` sin recompilar:
///
/// 1. **Path-loss:** RSSI → distancia, usando el modelo
///    `d = 10^((txPower - RSSI) / (10·n))`. El `txPower` puede venir
///    por baliza individual o del default global. Ver
///    `docs/adr/0002-parametros-path-loss.md`.
///
/// 2. **Media móvil:** se mantiene una cola FIFO de las últimas N
///    distancias por baliza (default N=8). La distancia que se usa para
///    trilateración es el promedio de la cola.
///
/// 3. **Limpieza de balizas obsoletas:** balizas no detectadas en los
///    últimos M segundos (default M=3) se eliminan del cálculo. Esto
///    evita que una baliza fantasma siga sesgando la posición.
///
/// 4. **Trilateración por centroide ponderado:** posición = promedio
///    ponderado de las posiciones de las balizas activas, con peso
///    `w_i = 1/d_i²`. Ver `docs/adr/0001-centroide-ponderado.md`.
///
/// 5. **Snap-to-graph:** proyecta la posición al punto más cercano de
///    cualquier arista del grafo, si está dentro de la tolerancia
///    configurada. Ver `docs/adr/0003-snap-to-graph-aristas.md`.
///
/// El servicio emite la posición estimada cada vez que llega una nueva
/// lectura BLE. La frecuencia efectiva depende del intervalo de anuncio
/// de las balizas (típicamente 2-5 Hz por baliza con iBeacon estándar).
class PositioningService {
  final BleService _ble;
  final BeaconRepository _beaconRepo;
  final GrafoRepository _grafoRepo;

  // Calibración cargada al iniciar (cacheada para el ciclo de vida del servicio).
  CalibracionPositioning _calibracion = CalibracionPositioning.defaults;

  // Dimensiones del mapa cargadas del grafo (default = cuarto de prueba 5x5).
  DimensionesMapa _dimensiones = const DimensionesMapa(5.0, 5.0);

  /// Lecturas suavizadas por baliza:
  ///   minor → (cola de distancias FIFO, timestamp de última lectura)
  final _lecturas = <int, _BeaconState>{};

  final _controller = StreamController<Position?>.broadcast();
  StreamSubscription<BeaconReading>? _bleSub;

  /// Stream de posición estimada del usuario. Emite `null` cuando no
  /// hay balizas visibles o todas están expiradas.
  Stream<Position?> get posicionStream => _controller.stream;

  /// Cantidad de balizas distintas con lecturas no expiradas.
  ///
  /// Útil para mostrar en la UI un indicador de "cobertura BLE actual".
  int get beaconsActivos {
    _limpiarObsoletos();
    return _lecturas.length;
  }

  /// Stream del estado del escaneo BLE subyacente.
  ///
  /// Re-expuesto desde [BleService] para que la UI pueda mostrar
  /// diálogos de "Activa Bluetooth" o "Permisos negados" sin depender
  /// directamente del servicio BLE de bajo nivel.
  Stream<BleEstado> get estadoBleStream => _ble.estadoStream;

  /// Estado actual del escaneo BLE.
  BleEstado get estadoBleActual => _ble.estadoActual;

  PositioningService(this._ble, this._beaconRepo, this._grafoRepo);

  /// Carga la configuración y arranca el escaneo BLE.
  ///
  /// La calibración se lee una sola vez al iniciar. Si cambian los
  /// parámetros en `beacon_config.json`, llamar `detener()` y `iniciar()`
  /// para recargar.
  Future<void> iniciar() async {
    // Cargar parámetros desde los repositorios antes de empezar a recibir lecturas.
    _calibracion = await _beaconRepo.obtenerCalibracion();
    _dimensiones = await _grafoRepo.obtenerDimensionesMapa();

    _bleSub = _ble.beaconStream.listen(_procesarLectura);
    await _ble.iniciarEscaneo();
  }

  /// Detiene el escaneo y limpia el estado interno.
  Future<void> detener() async {
    await _bleSub?.cancel();
    _bleSub = null;
    _lecturas.clear();
    await _ble.detenerEscaneo();
  }

  Future<void> _procesarLectura(BeaconReading lectura) async {
    // 1. Modelo de path-loss → distancia
    final txPower = await _txPowerPara(lectura.minor);
    final distancia = pow(10.0,
            (txPower - lectura.rssi) / (10.0 * _calibracion.nExponentePerdida))
        .toDouble();

    // 2. Actualizar media móvil de esta baliza
    final state = _lecturas.putIfAbsent(
        lectura.minor, () => _BeaconState(ventanaMax: _calibracion.ventanaMediaMovil));
    state.agregar(distancia, lectura.timestamp);

    // 3. Limpiar balizas obsoletas (>expiracionLecturaSegundos sin nueva lectura)
    _limpiarObsoletos();

    // 4 + 5. Trilateración + snap-to-graph
    final pos = await _trilaterar();
    if (!_controller.isClosed) _controller.add(pos);
  }

  Future<double> _txPowerPara(int minor) async {
    try {
      return await _beaconRepo.obtenerTxPower(minor);
    } catch (_) {
      // Si el minor no está registrado, asumir default y seguir.
      return _calibracion.txPowerDbmDefault;
    }
  }

  /// Elimina del mapa las balizas cuya última lectura es más vieja que
  /// `expiracionLecturaSegundos`. Mantener una baliza fantasma con
  /// lecturas viejas sesga la trilateración.
  void _limpiarObsoletos() {
    final ahora = DateTime.now();
    final umbral = Duration(seconds: _calibracion.expiracionLecturaSegundos);
    _lecturas.removeWhere((_, state) =>
        ahora.difference(state.ultimoTimestamp) > umbral);
  }

  /// Centroide ponderado de todas las balizas activas, con peso 1/d².
  Future<Position?> _trilaterar() async {
    if (_lecturas.isEmpty) return null;

    double sumX = 0, sumY = 0, sumW = 0;

    for (final entry in _lecturas.entries) {
      try {
        final config = await _beaconRepo.obtenerConfigBeacon(entry.key);
        final avgDist = entry.value.promedio;
        // Evitar división por cero con distancias muy pequeñas.
        // 0.01 m² = 10 cm como mínimo, conservador.
        final w = 1.0 / max(avgDist * avgDist, 0.01);
        sumX += config.x * w;
        sumY += config.y * w;
        sumW += w;
      } catch (_) {
        // Baliza no registrada en beacon_config.json — ignorar.
      }
    }

    if (sumW == 0) return null;

    // Clampar a los límites del piso (no permitir posiciones fuera del mapa).
    final x = (sumX / sumW).clamp(0.0, _dimensiones.anchoMetros);
    final y = (sumY / sumW).clamp(0.0, _dimensiones.altoMetros);

    return await _snapToGraph(x, y);
  }

  /// Proyecta la posición cruda al punto más cercano de cualquier
  /// arista del grafo, si está dentro de la tolerancia configurada.
  Future<Position> _snapToGraph(double x, double y) async {
    try {
      final nodos = await _grafoRepo.obtenerNodos();
      final aristas = await _grafoRepo.obtenerAristas();
      final mapaDeNodos = {for (final n in nodos) n.id: n};

      double minDist = double.infinity;
      double snapX = x, snapY = y;

      for (final arista in aristas) {
        final a = mapaDeNodos[arista.origenId];
        final b = mapaDeNodos[arista.destinoId];
        if (a == null || b == null) continue;

        final closest = _puntoEnSegmento(x, y, a.x, a.y, b.x, b.y);
        final dist =
            sqrt(pow(closest.dx - x, 2) + pow(closest.dy - y, 2));
        if (dist < minDist) {
          minDist = dist;
          snapX = closest.dx;
          snapY = closest.dy;
        }
      }

      // Si está demasiado lejos del grafo, reportar posición cruda.
      // Esto cubre casos donde el usuario salió de la zona modelada.
      final dentroDeTolerancia =
          minDist <= _calibracion.toleranciaSnapMetros;
      final finalX = dentroDeTolerancia ? snapX : x;
      final finalY = dentroDeTolerancia ? snapY : y;

      return Position(
        x: finalX,
        y: finalY,
        piso: 1, // TODO Fase 2: leer del Major del iBeacon
        timestamp: DateTime.now(),
      );
    } catch (_) {
      // Si el grafo falla por alguna razón, devolver la posición cruda
      // en lugar de no devolver nada — degradación graceful.
      return Position(x: x, y: y, piso: 1, timestamp: DateTime.now());
    }
  }

  /// Punto más cercano del segmento `[ab]` al punto `(px, py)`.
  ///
  /// Si el pie de perpendicular cae fuera del segmento, se devuelve el
  /// extremo más cercano. Algoritmo estándar de geometría computacional.
  Offset _puntoEnSegmento(
      double px, double py, double ax, double ay, double bx, double by) {
    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) return Offset(ax, ay);
    final t = ((px - ax) * dx + (py - ay) * dy) / len2;
    final tc = t.clamp(0.0, 1.0);
    return Offset(ax + tc * dx, ay + tc * dy);
  }

  void dispose() {
    detener();
    _controller.close();
  }
}

/// Estado interno por baliza: ventana FIFO de distancias suavizadas y
/// timestamp de la última lectura.
class _BeaconState {
  final Queue<double> _ventana = Queue<double>();
  final int ventanaMax;
  DateTime ultimoTimestamp;

  _BeaconState({required this.ventanaMax})
      : ultimoTimestamp = DateTime.now();

  void agregar(double distancia, DateTime timestamp) {
    _ventana.add(distancia);
    if (_ventana.length > ventanaMax) _ventana.removeFirst();
    ultimoTimestamp = timestamp;
  }

  double get promedio =>
      _ventana.isEmpty ? 0 : _ventana.reduce((a, b) => a + b) / _ventana.length;
}
