import 'dart:math';

/// Estadísticas acumuladas por baliza durante una sesión de calibración.
///
/// Se alimenta de las lecturas crudas de BLE conforme llegan, manteniendo
/// historial completo de RSSI y distancias calculadas. Permite calcular
/// media, desviación estándar, min y max para guiar la calibración del
/// modelo de path-loss.
///
/// Los samples se acumulan hasta llamar [reset]. Para sesiones largas,
/// considerar bound del historial (no implementado — para sesiones de
/// 10-15 minutos con 3-5 balizas a 2-5 Hz, son ~5000 samples por baliza
/// = ~80 KB, aceptable).
class BeaconStats {
  final int minor;
  String? descripcion;

  final List<double> _rssi = [];
  final List<double> _distancia = [];
  DateTime? ultimoTimestamp;

  BeaconStats({required this.minor, this.descripcion});

  /// Agrega una muestra de RSSI con su distancia calculada.
  void agregar(double rssi, double distanciaCalculada, DateTime timestamp) {
    _rssi.add(rssi);
    _distancia.add(distanciaCalculada);
    ultimoTimestamp = timestamp;
  }

  /// Limpia todas las muestras acumuladas. Útil para empezar una nueva
  /// sesión de medición en otra posición física.
  void reset() {
    _rssi.clear();
    _distancia.clear();
    ultimoTimestamp = null;
  }

  int get samples => _rssi.length;
  bool get tieneMuestras => _rssi.isNotEmpty;

  /// Última lectura cruda recibida.
  double get rssiActual => _rssi.isEmpty ? 0 : _rssi.last;

  /// Media aritmética del RSSI sobre todas las muestras.
  double get rssiMean {
    if (_rssi.isEmpty) return 0;
    return _rssi.reduce((a, b) => a + b) / _rssi.length;
  }

  /// Desviación estándar poblacional del RSSI. Para n=1 devuelve 0.
  /// Valores típicos en BLE indoor: 2-5 dBm. Valores >7 dBm indican
  /// señal muy ruidosa o ambiente cambiante.
  double get rssiStdDev {
    if (_rssi.length < 2) return 0;
    final m = rssiMean;
    final variance =
        _rssi.map((r) => pow(r - m, 2)).reduce((a, b) => a + b) / _rssi.length;
    return sqrt(variance);
  }

  double get rssiMin => _rssi.isEmpty ? 0 : _rssi.reduce(min);
  double get rssiMax => _rssi.isEmpty ? 0 : _rssi.reduce(max);

  /// Media de las distancias calculadas usando la calibración vigente
  /// al momento de cada muestra. Si cambió la calibración durante la
  /// sesión, este valor mezcla resultados con parámetros distintos.
  double get distanciaMean {
    if (_distancia.isEmpty) return 0;
    return _distancia.reduce((a, b) => a + b) / _distancia.length;
  }

  /// Edad de la última lectura en milisegundos, o null si no hay muestras.
  int? get edadMs {
    if (ultimoTimestamp == null) return null;
    return DateTime.now().difference(ultimoTimestamp!).inMilliseconds;
  }
}
