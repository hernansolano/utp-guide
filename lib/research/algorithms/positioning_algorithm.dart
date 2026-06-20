import 'dart:collection';
import 'dart:math';
import '../../models/beacon_config.dart';
import '../../models/beacon_reading.dart';
import '../../models/position.dart';

/// Posición conocida de una baliza, para los algoritmos del modo
/// investigador (cargada de `beacon_config.json`).
class BeaconPos {
  final double x;
  final double y;
  final double? txPowerDbm;
  const BeaconPos(this.x, this.y, [this.txPowerDbm]);
}

/// Estimador de posición que procesa lecturas BLE una a una y mantiene
/// estado interno.
///
/// La clave del EXP2 (Q2): varios algoritmos corren en **paralelo sobre
/// las mismas lecturas**, así la comparación es justa (mismas condiciones
/// físicas exactas). Esta capa es independiente del `PositioningService`
/// de producción — no se toca el posicionamiento del modo usuario.
abstract class PositioningAlgorithm {
  /// Nombre estable para CSV/columnas (ej. `centroide_movil`).
  String get nombre;

  /// Etiqueta legible para la UI.
  String get etiqueta;

  /// Procesa una lectura y devuelve la posición estimada actual, o null
  /// si aún no hay balizas suficientes.
  Position? procesar(BeaconReading lectura);

  void reset();
}

/// Filtro de Kalman 1D para suavizar una señal escalar (RSSI).
class Kalman1D {
  double _x;
  double _p = 1.0;
  final double q; // ruido de proceso
  final double r; // ruido de medición

  Kalman1D(this._x, {this.q = 0.01, this.r = 4.0});

  double update(double z) {
    _p += q;
    final k = _p / (_p + r);
    _x += k * (z - _x);
    _p *= (1 - k);
    return _x;
  }
}

/// Estado por baliza: distancia filtrada vigente + último timestamp.
class _EstadoBaliza {
  double distancia = 0;
  DateTime ultimo = DateTime.now();
}

/// Base con la trilateración por **centroide ponderado** (w = 1/d²) +
/// expiración de balizas. Las subclases solo definen cómo se filtra la
/// distancia a partir del RSSI (media móvil vs Kalman) — todo lo demás es
/// idéntico, para que la comparación aísle el efecto del filtro.
abstract class _CentroideBase implements PositioningAlgorithm {
  final Map<int, BeaconPos> balizas;
  final CalibracionPositioning cal;
  final Map<int, _EstadoBaliza> _estados = {};

  _CentroideBase(this.balizas, this.cal);

  double _txPower(int minor) =>
      balizas[minor]?.txPowerDbm ?? cal.txPowerDbmDefault;

  /// Modelo de path-loss: RSSI → distancia (metros).
  double distanciaDe(double rssi, int minor) => pow(10.0,
          (_txPower(minor) - rssi) / (10.0 * cal.nExponentePerdida))
      .toDouble();

  /// La subclase devuelve la distancia filtrada para esta baliza dada la
  /// nueva lectura de RSSI.
  double filtrar(int minor, double rssi);

  @override
  Position? procesar(BeaconReading r) {
    if (!balizas.containsKey(r.minor)) return null;
    final e = _estados.putIfAbsent(r.minor, () => _EstadoBaliza());
    e.distancia = filtrar(r.minor, r.rssi);
    e.ultimo = r.timestamp;
    return _centroide();
  }

  Position? _centroide() {
    final ahora = DateTime.now();
    final umbral = Duration(seconds: cal.expiracionLecturaSegundos);
    double sx = 0, sy = 0, sw = 0;
    _estados.forEach((minor, e) {
      if (ahora.difference(e.ultimo) > umbral) return;
      final b = balizas[minor];
      if (b == null) return;
      final w = 1.0 / max(e.distancia * e.distancia, 0.01);
      sx += b.x * w;
      sy += b.y * w;
      sw += w;
    });
    if (sw == 0) return null;
    return Position(
        x: sx / sw, y: sy / sw, piso: 1, timestamp: DateTime.now());
  }

  @override
  void reset() => _estados.clear();
}

/// **Centroide + media móvil** — el algoritmo ACTUAL de la app: promedia
/// las últimas N distancias por baliza antes de trilaterar.
class CentroideMovil extends _CentroideBase {
  final Map<int, Queue<double>> _ventanas = {};

  CentroideMovil(super.balizas, super.cal);

  @override
  String get nombre => 'centroide_movil';
  @override
  String get etiqueta => 'Media móvil';

  @override
  double filtrar(int minor, double rssi) {
    final d = distanciaDe(rssi, minor);
    final q = _ventanas.putIfAbsent(minor, () => Queue<double>());
    q.add(d);
    while (q.length > cal.ventanaMediaMovil) {
      q.removeFirst();
    }
    return q.reduce((a, b) => a + b) / q.length;
  }

  @override
  void reset() {
    super.reset();
    _ventanas.clear();
  }
}

/// **Centroide + Kalman** — suaviza el RSSI de cada baliza con un filtro
/// de Kalman 1D antes de convertir a distancia y trilaterar. Aísla el
/// efecto del filtro frente a la media móvil (Q2).
class CentroideKalman extends _CentroideBase {
  final double q;
  final double r;
  final Map<int, Kalman1D> _filtros = {};

  CentroideKalman(super.balizas, super.cal, {this.q = 0.01, this.r = 4.0});

  @override
  String get nombre => 'centroide_kalman';
  @override
  String get etiqueta => 'Kalman';

  @override
  double filtrar(int minor, double rssi) {
    final f = _filtros.putIfAbsent(minor, () => Kalman1D(rssi, q: q, r: r));
    final rssiFiltrado = f.update(rssi);
    return distanciaDe(rssiFiltrado, minor);
  }

  @override
  void reset() {
    super.reset();
    _filtros.clear();
  }
}
