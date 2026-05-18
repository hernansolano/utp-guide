import 'dart:math';

class Position {
  final double x;
  final double y;
  final int piso;
  final DateTime timestamp;

  const Position({
    required this.x,
    required this.y,
    required this.piso,
    required this.timestamp,
  });

  double distanciaA(double ox, double oy) =>
      sqrt(pow(x - ox, 2) + pow(y - oy, 2));

  factory Position.fromJson(Map<String, dynamic> json) {
    return Position(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      piso: json['piso'] as int,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'piso': piso,
        'timestamp': timestamp.toIso8601String(),
      };
}
