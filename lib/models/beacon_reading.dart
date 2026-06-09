/// Una lectura individual de baliza, después del parseo iBeacon/Eddystone
/// pero **antes** de aplicar path-loss, media móvil o trilateración.
///
/// El `PositioningService` consume estos para construir el stream de
/// `Position`. Las herramientas de calibración los consumen directos
/// (via `beaconStreamRaw`) para calcular sus propias estadísticas.
class BeaconReading {
  /// iBeacon Minor (16 bits). En multi-piso, identifica la baliza dentro
  /// del piso.
  final int minor;

  /// iBeacon Major (16 bits). En el esquema multi-piso, equivale al
  /// piso de la baliza. Default `1` por compatibilidad con configs
  /// mono-piso de Fase 1.
  final int major;

  /// RSSI medido al recibir el anuncio (dBm, valor negativo).
  final double rssi;

  final DateTime timestamp;

  const BeaconReading({
    required this.minor,
    required this.rssi,
    required this.timestamp,
    this.major = 1,
  });

  bool get expirado =>
      DateTime.now().difference(timestamp).inSeconds > 2;

  factory BeaconReading.fromJson(Map<String, dynamic> json) {
    return BeaconReading(
      minor: json['minor'] as int,
      major: json['major'] as int? ?? 1,
      rssi: (json['rssi'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'minor': minor,
        'major': major,
        'rssi': rssi,
        'timestamp': timestamp.toIso8601String(),
      };
}
