import 'tipo_nodo.dart';

class Nodo {
  final String id;
  final String nombre;
  final TipoNodo tipo;
  final double x;
  final double y;
  final int piso;
  final bool accesible;
  final int? arucoId;

  const Nodo({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.x,
    required this.y,
    required this.piso,
    required this.accesible,
    this.arucoId,
  });

  factory Nodo.fromJson(Map<String, dynamic> json) {
    return Nodo(
      id: json['id'] as String,
      nombre: json['nombre'] as String,
      tipo: TipoNodo.fromJson(json['tipo'] as String),
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      piso: json['piso'] as int,
      accesible: json['accesible'] as bool,
      arucoId: json['aruco_id'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'tipo': tipo.toJson(),
        'x': x,
        'y': y,
        'piso': piso,
        'accesible': accesible,
        if (arucoId != null) 'aruco_id': arucoId,
      };
}
