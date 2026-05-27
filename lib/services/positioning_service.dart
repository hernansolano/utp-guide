import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Offset;
import '../data/repositories/beacon_repository.dart';
import '../data/repositories/grafo_repository.dart';
import '../models/beacon_config.dart';
import '../models/beacon_reading.dart';
import '../models/position.dart';
import 'ble_service.dart' show BleEstado;
import 'ble_source.dart';

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
/// **Calibración en vivo (ADR-0011):** la calibración se recibe vía
/// `ValueListenable<CalibracionPositioning>`. Cuando el listenable
/// notifica un cambio, los nuevos valores aplican inmediatamente a las
/// próximas lecturas. La ventana de media móvil contiene valores ya
/// convertidos a distancia, así que un cambio brusco de `n` tarda
/// `ventanaMediaMovil` lecturas en converger. Para efecto instantáneo,
/// el consumidor puede llamar [resetearVentanas].
///
/// **Ref counting (lifecycle):** [iniciar] y [detener] usan ref counting.
/// Múltiples consumidores (ej: MapaScreen y CalibracionScreen) pueden
/// llamar `iniciar()` y el servicio solo se levanta una vez. Solo cuando
/// el último consumidor llama `detener()`, el servicio se apaga de verdad.
class PositioningService {
  final BleSource _ble;
  final BeaconRepository _beaconRepo;
  final GrafoRepository _grafoRepo;
  final ValueListenable<CalibracionPositioning> _calibracionListenable;

  /// Cache local de la calibración. Se actualiza vía listener del
  /// [_calibracionListenable], permitiendo cambios en runtime sin
  /// reiniciar el servicio.
  CalibracionPositioning _calibracion;

  // Dimensiones del mapa cargadas del grafo (default = cuarto de prueba 5x5).
  DimensionesMapa _dimensiones = const DimensionesMapa(5.0, 5.0);

  /// Lecturas suavizadas por baliza:
  ///   minor → (cola de distancias FIFO, timestamp de última lectura)
  final _lecturas = <int, _BeaconState>{};

  /// Última posición calculada antes de aplicar snap-to-graph.
  /// Se expone vía [debugPosicionCruda] para herramientas de debug.
  Position? _debugPosicionCruda;

  final _controller = StreamController<Position?>.broadcast();
  StreamSubscription<BeaconReading>? _bleSub;

  /// Cantidad de consumidores que llamaron `iniciar()` sin un
  /// `detener()` correspondiente. El servicio se mantiene activo
  /// mientras este contador > 0.
  int _refCount = 0;

  /// Stream de posición estimada del usuario. Emite `null` cuando no
  /// hay balizas visibles o todas están expiradas.
  Stream<Position?> get posicionStream => _controller.stream;

  /// Stream de lecturas crudas de BLE (mismas que recibe el servicio
  /// antes de aplicarles path-loss y media móvil).
  ///
  /// Útil para herramientas de calibración que necesitan los RSSI
  /// originales para calcular estadísticas propias. No procesado por
  /// el servicio — el consumidor recibe la misma data que llega del
  /// `BleSource`.
  Stream<BeaconReading> get beaconStreamRaw => _ble.beaconStream;

  /// Cantidad de balizas distintas con lecturas no expiradas.
  ///
  /// Útil para mostrar en la UI un indicador de "cobertura BLE actual".
  int get beaconsActivos {
    _limpiarObsoletos();
    return _lecturas.length;
  }

  /// Stream del estado del escaneo BLE subyacente.
  Stream<BleEstado> get estadoBleStream => _ble.estadoStream;

  /// Estado actual del escaneo BLE.
  BleEstado get estadoBleActual => _ble.estadoActual;

  // ─── API de debug ────────────────────────────────────────────────────────

  /// Última posición calculada antes del snap-to-graph.
  /// Útil para visualizar cuánto desplazó el snap a la posición reportada.
  Position? get debugPosicionCruda => _debugPosicionCruda;

  /// Información detallada de la última lectura de cada baliza activa.
  Map<int, BeaconDebugInfo> get debugLecturas {
    _limpiarObsoletos();
    return Map.unmodifiable({
      for (final e in _lecturas.entries)
        e.key: BeaconDebugInfo(
          minor: e.key,
          rssi: e.value.ultimaRssi ?? 0,
          distanciaEstimada: e.value.promedio,
          ultimaLectura: e.value.ultimoTimestamp,
        ),
    });
  }

  PositioningService(
    this._ble,
    this._beaconRepo,
    this._grafoRepo,
    this._calibracionListenable,
  ) : _calibracion = _calibracionListenable.value {
    _calibracionListenable.addListener(_onCalibracionCambio);
  }

  void _onCalibracionCambio() {
    _calibracion = _calibracionListenable.value;
  }

  /// Arranca el escaneo BLE y la subscripción a lecturas.
  ///
  /// Idempotente con ref counting: si ya hay otros consumidores activos,
  /// solo incrementa el contador. La inicialización real solo ocurre la
  /// primera vez.
  Future<void> iniciar() async {
    _refCount++;
    if (_refCount > 1) return; // ya inicializado por otro consumidor

    _dimensiones = await _grafoRepo.obtenerDimensionesMapa();
    _bleSub = _ble.beaconStream.listen(_procesarLectura);
    await _ble.iniciarEscaneo();
  }

  /// Decrementa el ref count. Solo apaga el servicio cuando el contador
  /// llega a cero (último consumidor cerró).
  Future<void> detener() async {
    if (_refCount <= 0) return; // ya detenido
    _refCount--;
    if (_refCount > 0) return; // otros consumidores siguen usando

    await _bleSub?.cancel();
    _bleSub = null;
    _lecturas.clear();
    await _ble.detenerEscaneo();
  }

  /// Limpia las ventanas de media móvil de todas las balizas. Útil para
  /// aplicar inmediatamente cambios de calibración sin esperar que la
  /// media móvil converja.
  void resetearVentanas() {
    _lecturas.clear();
    _debugPosicionCruda = null;
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
    // Ajustar la ventana si el setting cambió en vivo.
    state.ajustarVentanaMax(_calibracion.ventanaMediaMovil);
    state.agregar(distancia, lectura.rssi, lectura.timestamp);

    // 3. Limpiar balizas obsoletas
    _limpiarObsoletos();

    // 4 + 5. Trilateración + snap-to-graph
    final pos = await _trilaterar();
    if (!_controller.isClosed) _controller.add(pos);
  }

  Future<double> _txPowerPara(int minor) async {
    try {
      return await _beaconRepo.obtenerTxPower(minor);
    } catch (_) {
      return _calibracion.txPowerDbmDefault;
    }
  }

  void _limpiarObsoletos() {
    final ahora = DateTime.now();
    final umbral = Duration(seconds: _calibracion.expiracionLecturaSegundos);
    _lecturas.removeWhere((_, state) =>
        ahora.difference(state.ultimoTimestamp) > umbral);
  }

  Future<Position?> _trilaterar() async {
    if (_lecturas.isEmpty) return null;

    double sumX = 0, sumY = 0, sumW = 0;

    for (final entry in _lecturas.entries) {
      try {
        final config = await _beaconRepo.obtenerConfigBeacon(entry.key);
        final avgDist = entry.value.promedio;
        final w = 1.0 / max(avgDist * avgDist, 0.01);
        sumX += config.x * w;
        sumY += config.y * w;
        sumW += w;
      } catch (_) {
        // ignore
      }
    }

    if (sumW == 0) return null;

    final x = (sumX / sumW).clamp(0.0, _dimensiones.anchoMetros);
    final y = (sumY / sumW).clamp(0.0, _dimensiones.altoMetros);

    _debugPosicionCruda =
        Position(x: x, y: y, piso: 1, timestamp: DateTime.now());

    return await _snapToGraph(x, y);
  }

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

      final dentroDeTolerancia =
          minDist <= _calibracion.toleranciaSnapMetros;
      final finalX = dentroDeTolerancia ? snapX : x;
      final finalY = dentroDeTolerancia ? snapY : y;

      return Position(
        x: finalX,
        y: finalY,
        piso: 1,
        timestamp: DateTime.now(),
      );
    } catch (_) {
      return Position(x: x, y: y, piso: 1, timestamp: DateTime.now());
    }
  }

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
    _calibracionListenable.removeListener(_onCalibracionCambio);
    // Forzar shutdown sin importar el ref count.
    _refCount = 0;
    _bleSub?.cancel();
    _bleSub = null;
    _lecturas.clear();
    _ble.detenerEscaneo();
    _controller.close();
  }
}

/// Estado interno por baliza: ventana FIFO de distancias suavizadas,
/// último RSSI crudo y timestamp de la última lectura.
class _BeaconState {
  final Queue<double> _ventana = Queue<double>();
  int ventanaMax;
  DateTime ultimoTimestamp;
  double? ultimaRssi;

  _BeaconState({required this.ventanaMax})
      : ultimoTimestamp = DateTime.now();

  /// Ajusta la capacidad de la ventana en runtime. Si la nueva capacidad
  /// es menor, recorta las muestras más viejas. Permite cambiar la
  /// ventana de media móvil en vivo desde la calibración.
  void ajustarVentanaMax(int nuevoMax) {
    if (nuevoMax == ventanaMax) return;
    ventanaMax = nuevoMax;
    while (_ventana.length > ventanaMax) {
      _ventana.removeFirst();
    }
  }

  void agregar(double distancia, double rssi, DateTime timestamp) {
    _ventana.add(distancia);
    if (_ventana.length > ventanaMax) _ventana.removeFirst();
    ultimaRssi = rssi;
    ultimoTimestamp = timestamp;
  }

  double get promedio =>
      _ventana.isEmpty ? 0 : _ventana.reduce((a, b) => a + b) / _ventana.length;
}

/// Snapshot inmutable de la última lectura de una baliza.
class BeaconDebugInfo {
  final int minor;
  final double rssi;
  final double distanciaEstimada;
  final DateTime ultimaLectura;

  const BeaconDebugInfo({
    required this.minor,
    required this.rssi,
    required this.distanciaEstimada,
    required this.ultimaLectura,
  });

  int get edadMs => DateTime.now().difference(ultimaLectura).inMilliseconds;
}
