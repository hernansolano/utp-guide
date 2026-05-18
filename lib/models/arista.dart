import 'tipo_obstaculo.dart';

class Arista {
  final String origenId;
  final String destinoId;
  final double distancia;
  final TipoObstaculo tipoObstaculo;
  final bool accesible;

  const Arista({
    required this.origenId,
    required this.destinoId,
    required this.distancia,
    required this.tipoObstaculo,
    required this.accesible,
  });

  factory Arista.fromJson(Map<String, dynamic> json) {
    return Arista(
      origenId: json['origenId'] as String,
      destinoId: json['destinoId'] as String,
      distancia: (json['distancia'] as num).toDouble(),
      tipoObstaculo: TipoObstaculo.fromJson(json['tipoObstaculo'] as String),
      accesible: json['accesible'] as bool,
    );
  }

  Map<String, dynamic> toJson() => {
        'origenId': origenId,
        'destinoId': destinoId,
        'distancia': distancia,
        'tipoObstaculo': tipoObstaculo.toJson(),
        'accesible': accesible,
      };

  Arista invertida() => Arista(
        origenId: destinoId,
        destinoId: origenId,
        distancia: distancia,
        tipoObstaculo: tipoObstaculo,
        accesible: accesible,
      );
}
