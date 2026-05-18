class BeaconReading {
  final int minor;
  final double rssi;
  final DateTime timestamp;

  const BeaconReading({
    required this.minor,
    required this.rssi,
    required this.timestamp,
  });

  bool get expirado =>
      DateTime.now().difference(timestamp).inSeconds > 2;

  factory BeaconReading.fromJson(Map<String, dynamic> json) {
    return BeaconReading(
      minor: json['minor'] as int,
      rssi: (json['rssi'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'minor': minor,
        'rssi': rssi,
        'timestamp': timestamp.toIso8601String(),
      };
}
