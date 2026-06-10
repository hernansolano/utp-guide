import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Offset;
import '../data/repositories/beacon_repository.dart';
import '../data/repositories/grafo_repository.dart';
import '../models/advertisement_crudo.dart';
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

  /// Listenable opcional para deshabilitar snap-to-graph en runtime.
  /// Si es null (default), el snap siempre se aplica. Si está conectado
  /// y emite `false`, las posiciones salen crudas del centroide.
  final ValueListenable<bool>? _snapHabilitadoListenable;

  /// Cache local de la calibración. Se actualiza vía listener del
  /// [_calibracionListenable], permitiendo cambios en runtime sin
  /// reiniciar el servicio.
  CalibracionPositioning _calibracion;

  // Dimensiones del mapa cargadas del grafo (default = cuarto de prueba 5x5).
  DimensionesMapa _dimensiones = const DimensionesMapa(5.0, 5.0);

  /// Configuración de las balizas cargada al iniciar.
  /// **Cache crítico para performance:** evita un await por cada lectura
  /// BLE. Las balizas no cambian durante runtime (la calibración sí, pero
  /// es otro path). Si el `beacon_config.json` se modificase en vivo —
  /// hoy no soportado — habría que invalidar este map.
  final Map<int, _ConfigBeaconCache> _configsBeacon = {};

  /// Snapshot inmutable de los nodos y aristas del grafo, cacheado al
  /// iniciar para que `_snapToGraph` no haga I/O por cada lectura.
  List<_AristaConNodos> _aristasCache = const [];

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

  /// Stream de advertisements BLE crudos, sin filtrar por UUID ni formato.
  /// Solo emite en `kDebugMode`. Útil para la pantalla de diagnóstico que
  /// muestra al dev qué emite el simulador o las balizas físicas, incluso
  /// si no son aceptadas por el pipeline.
  Stream<AdvertisementCrudo> get advertisementsCrudosStream =>
      _ble.advertisementsCrudosStream;

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

  /// Reintenta la solicitud de permisos del BleSource activo. Útil
  /// cuando la primera solicitud falló (estado `permisosNegados`) y la
  /// UI quiere ofrecer un botón de reintento.
  Future<bool> reintentarPermisosBle() => _ble.reintentarPermisos();

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
    this._calibracionListenable, {
    ValueListenable<bool>? snapHabilitadoListenable,
  })  : _snapHabilitadoListenable = snapHabilitadoListenable,
        _calibracion = _calibracionListenable.value {
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
  ///
  /// Pre-carga en memoria: dimensiones del mapa, configs de balizas,
  /// nodos y aristas del grafo. Eso elimina los `await` del hot path de
  /// lecturas BLE (antes había 1 await por txPower y N awaits por
  /// trilateración por baliza activa) — costo crítico en Android.
  Future<void> iniciar() async {
    _refCount++;
    if (_refCount > 1) return; // ya inicializado por otro consumidor

    _dimensiones = await _grafoRepo.obtenerDimensionesMapa();
    await _precargarBeacons();
    await _precargarGrafo();
    _bleSub = _ble.beaconStream.listen(_procesarLectura);
    await _ble.iniciarEscaneo();
  }

  /// Snapshot inmutable de las balizas + txPower efectivo (cae al global
  /// de la calibración si la baliza no tiene su propio override).
  Future<void> _precargarBeacons() async {
    _configsBeacon.clear();
    final minors = await _beaconRepo.obtenerMinorsRegistrados();
    for (final m in minors) {
      try {
        final c = await _beaconRepo.obtenerConfigBeacon(m);
        _configsBeacon[m] = _ConfigBeaconCache(
          minor: c.minor,
          x: c.x,
          y: c.y,
          txPowerDbm: c.txPowerDbm,
        );
      } catch (_) {
        // baliza inválida — saltar
      }
    }
  }

  /// Snapshot inmutable de las aristas con coordenadas pre-resueltas de
  /// origen y destino (en vez de hacer lookup por id en cada snap).
  Future<void> _precargarGrafo() async {
    final nodos = await _grafoRepo.obtenerNodos();
    final aristas = await _grafoRepo.obtenerAristas();
    final byId = {for (final n in nodos) n.id: n};
    final lista = <_AristaConNodos>[];
    for (final a in aristas) {
      final origen = byId[a.origenId];
      final destino = byId[a.destinoId];
      if (origen != null && destino != null) {
        lista.add(_AristaConNodos(
          origenX: origen.x,
          origenY: origen.y,
          destinoX: destino.x,
          destinoY: destino.y,
        ));
      }
    }
    _aristasCache = lista;
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
    _configsBeacon.clear();
    _aristasCache = const [];
    await _ble.detenerEscaneo();
  }

  /// Limpia las ventanas de media móvil de todas las balizas. Útil para
  /// aplicar inmediatamente cambios de calibración sin esperar que la
  /// media móvil converja.
  void resetearVentanas() {
    _lecturas.clear();
    _debugPosicionCruda = null;
  }

  /// Hot path: se ejecuta hasta varias veces por segundo. **Cero awaits**
  /// — toda la información (txPower, posición de balizas, grafo) está en
  /// memoria gracias a [_precargarBeacons] y [_precargarGrafo].
  void _procesarLectura(BeaconReading lectura) {
    // Guard de sanidad: un RSSI >= -20 dBm no es físicamente plausible
    // (ni tocando la antena). iOS reporta rssi=0 cuando la medición
    // falla; si entrara al path-loss daría distancia ~1 cm y el peso
    // 1/d² del centroide dispararía la posición hacia esa baliza. La
    // fuente iOS ya filtra, esto cubre cualquier otra fuente futura.
    if (lectura.rssi >= -20.0) return;

    // 1. Modelo de path-loss → distancia
    final txPower = _txPowerSync(lectura.minor);
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
    final pos = _trilaterarSync();
    if (!_controller.isClosed) _controller.add(pos);
  }

  double _txPowerSync(int minor) {
    final c = _configsBeacon[minor];
    return c?.txPowerDbm ?? _calibracion.txPowerDbmDefault;
  }

  void _limpiarObsoletos() {
    final ahora = DateTime.now();
    final umbral = Duration(seconds: _calibracion.expiracionLecturaSegundos);
    _lecturas.removeWhere((_, state) =>
        ahora.difference(state.ultimoTimestamp) > umbral);
  }

  Position? _trilaterarSync() {
    if (_lecturas.isEmpty) return null;

    double sumX = 0, sumY = 0, sumW = 0;

    for (final entry in _lecturas.entries) {
      final config = _configsBeacon[entry.key];
      if (config == null) continue;
      final avgDist = entry.value.promedio;
      final w = 1.0 / max(avgDist * avgDist, 0.01);
      sumX += config.x * w;
      sumY += config.y * w;
      sumW += w;
    }

    if (sumW == 0) return null;

    final x = (sumX / sumW).clamp(0.0, _dimensiones.anchoMetros);
    final y = (sumY / sumW).clamp(0.0, _dimensiones.altoMetros);

    _debugPosicionCruda =
        Position(x: x, y: y, piso: 1, timestamp: DateTime.now());

    return _snapToGraphSync(x, y);
  }

  Position _snapToGraphSync(double x, double y) {
    // Cuando el toggle de calibración pide snap off, devolvemos la
    // posición cruda directamente — útil para que el dev vea dónde
    // "cae" el centroide ponderado sin la corrección de aristas.
    if (_snapHabilitadoListenable != null &&
        !_snapHabilitadoListenable.value) {
      return Position(
        x: x,
        y: y,
        piso: 1,
        timestamp: DateTime.now(),
      );
    }

    double minDist = double.infinity;
    double snapX = x, snapY = y;

    for (final arista in _aristasCache) {
      final closest = _puntoEnSegmento(
          x, y, arista.origenX, arista.origenY, arista.destinoX, arista.destinoY);
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

/// Snapshot inmutable de la config de una baliza, cacheado para que el
/// hot path de `_procesarLectura` no haga lookups asincrónicos al repo.
class _ConfigBeaconCache {
  final int minor;
  final double x;
  final double y;
  final double? txPowerDbm;

  const _ConfigBeaconCache({
    required this.minor,
    required this.x,
    required this.y,
    required this.txPowerDbm,
  });
}

/// Snapshot inmutable de una arista con coordenadas pre-resueltas.
/// Evita los lookups `id → Nodo` que antes se hacían en cada snap.
class _AristaConNodos {
  final double origenX;
  final double origenY;
  final double destinoX;
  final double destinoY;

  const _AristaConNodos({
    required this.origenX,
    required this.origenY,
    required this.destinoX,
    required this.destinoY,
  });
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
