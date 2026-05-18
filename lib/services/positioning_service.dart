import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:flutter/painting.dart' show Offset;
import '../data/repositories/beacon_repository.dart';
import '../data/repositories/grafo_repository.dart';
import '../models/beacon_reading.dart';
import '../models/position.dart';
import 'ble_service.dart';

/// Convierte un stream de [BeaconReading] en un stream de [Position]
/// usando centroide ponderado por distancia y snap-to-graph.
///
/// Parámetros del modelo de path-loss:
///   distancia = 10 ^ ((txPower - rssi) / (10 × n))
///   txPower = -59 dBm   (potencia calibrada a 1 m)
///   n = 2.7             (exponente de entorno — ajustar con medición en campo)
///
/// Trilateration: centroide ponderado con w = 1/d².
///   Requiere mínimo 1 beacon activo para emitir una posición.
///   Con 3 beacons activos la precisión es óptima.
class PositioningService {
  final BleService _ble;
  final BeaconRepository _beaconRepo;
  final GrafoRepository _grafoRepo;

  // Parámetros del modelo de path-loss
  static const double _txPower = -59.0;
  static const double _n = 2.7;

  // Media móvil: ventana de 5 lecturas por beacon
  static const int _ventanaSize = 5;

  // Snap-to-graph: tolerancia máxima en metros
  static const double _snapTolerance = 3.0;

  // Dimensiones del mapa (deben coincidir con grafo.json)
  static const double _mapaAncho = 5.0;
  static const double _mapaAlto = 5.0;

  final _lecturas = <int, Queue<double>>{}; // minor → cola de distancias suavizadas
  final _controller = StreamController<Position?>.broadcast();
  StreamSubscription<BeaconReading>? _bleSub;

  /// Stream de posición estimada. Emite null si no hay beacons visibles.
  Stream<Position?> get posicionStream => _controller.stream;

  /// Número de beacons distintos activos en la ventana actual.
  int get beaconsActivos => _lecturas.length;

  PositioningService(this._ble, this._beaconRepo, this._grafoRepo);

  /// Inicia el escaneo BLE y el procesamiento de lecturas.
  void iniciar() {
    _bleSub = _ble.beaconStream.listen(_procesarLectura);
    _ble.iniciarEscaneo(); // fire-and-forget; falla silenciosamente sin permisos
  }

  /// Detiene el escaneo y el procesamiento.
  void detener() {
    _bleSub?.cancel();
    _bleSub = null;
    _ble.detenerEscaneo();
  }

  Future<void> _procesarLectura(BeaconReading lectura) async {
    // 1. Calcular distancia con modelo de path-loss
    final distancia =
        pow(10.0, (_txPower - lectura.rssi) / (10.0 * _n)).toDouble();

    // 2. Actualizar media móvil para este beacon
    _lecturas.putIfAbsent(lectura.minor, () => Queue<double>());
    final ventana = _lecturas[lectura.minor]!;
    ventana.add(distancia);
    if (ventana.length > _ventanaSize) ventana.removeFirst();

    // 3. Calcular posición y emitirla
    final pos = await _trilaterar();
    if (!_controller.isClosed) _controller.add(pos);
  }

  /// Centroide ponderado: w_i = 1/d_i² (más cercano → mayor peso).
  Future<Position?> _trilaterar() async {
    if (_lecturas.isEmpty) return null;

    double sumX = 0, sumY = 0, sumW = 0;

    for (final entry in _lecturas.entries) {
      try {
        final beaconPos = await _beaconRepo.obtenerPosicion(entry.key);
        final avgDist =
            entry.value.reduce((a, b) => a + b) / entry.value.length;
        // Evitar división por cero con distancias muy pequeñas
        final w = 1.0 / max(avgDist * avgDist, 0.01);
        sumX += beaconPos.x * w;
        sumY += beaconPos.y * w;
        sumW += w;
      } catch (_) {
        // Beacon sin posición registrada en beacon_config.json — ignorar
      }
    }

    if (sumW == 0) return null;

    // Clampar al área del mapa
    final x = (sumX / sumW).clamp(0.0, _mapaAncho);
    final y = (sumY / sumW).clamp(0.0, _mapaAlto);

    return await _snapToGraph(x, y);
  }

  /// Proyecta la posición cruda al punto más cercano en cualquier arista
  /// del grafo. Si la distancia al grafo supera [_snapTolerance], retorna
  /// la posición cruda sin modificar.
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

        final closest =
            _puntoEnSegmento(x, y, a.x, a.y, b.x, b.y);
        final dist = sqrt(
            pow(closest.dx - x, 2) + pow(closest.dy - y, 2));
        if (dist < minDist) {
          minDist = dist;
          snapX = closest.dx;
          snapY = closest.dy;
        }
      }

      final finalX = minDist <= _snapTolerance ? snapX : x;
      final finalY = minDist <= _snapTolerance ? snapY : y;

      return Position(x: finalX, y: finalY, piso: 1, timestamp: DateTime.now());
    } catch (_) {
      // Si el grafo falla, devolver posición cruda
      return Position(x: x, y: y, piso: 1, timestamp: DateTime.now());
    }
  }

  /// Punto más cercano en el segmento AB a partir del punto P.
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
