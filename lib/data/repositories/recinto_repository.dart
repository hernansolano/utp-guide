import 'dart:convert';
import 'package:flutter/services.dart';
import '../../models/recinto.dart';
import '../exceptions.dart';
import 'grafo_repository.dart';

/// Carga el plano de recintos (salones, oficinas, baños… como polígonos)
/// del piso activo.
///
/// El archivo lo declara el grafo en el campo opcional `recintos_json`, igual
/// que `mapa_svg`: cada entorno decide si tiene recintos sin tocar código. Si
/// el grafo no lo declara, devuelve [PlanoRecintos.vacio] y el mapa se ve como
/// antes (solo el SVG).
///
/// El JSON lo genera `tools/plano_oficial/extraer_plano.py` desde el plano
/// oficial en PDF. Formato:
/// ```json
/// {
///   "mapa_ancho_metros": 127.24, "mapa_alto_metros": 78.52,
///   "recintos": [{"id": "r36", "codigo": "3-405", "nombre": "…",
///                 "tipo": "SALON", "etiqueta": [x, y],
///                 "poligono": [[x, y], …], "nodo_id": null}],
///   "circulacion": [[[x, y], …]]
/// }
/// ```
class RecintoRepository {
  final GrafoRepository _grafoRepo;
  PlanoRecintos? _cache;

  RecintoRepository(this._grafoRepo);

  Future<PlanoRecintos> obtenerPlano() async {
    if (_cache != null) return _cache!;
    final path = await _grafoRepo.obtenerRecintosPath();
    if (path == null) return _cache = PlanoRecintos.vacio;

    final Map<String, dynamic> data;
    try {
      data =
          jsonDecode(await rootBundle.loadString(path)) as Map<String, dynamic>;
    } catch (e) {
      throw RecintosInvalidosException('No se pudo leer "$path": $e');
    }

    final dims = await _grafoRepo.obtenerDimensionesMapa();
    final ancho = (data['mapa_ancho_metros'] as num?)?.toDouble();
    final alto = (data['mapa_alto_metros'] as num?)?.toDouble();
    // Los polígonos están en el mismo sistema de coordenadas que el grafo:
    // si las dimensiones no coinciden, se dibujarían corridos.
    if (ancho != null &&
        alto != null &&
        ((ancho - dims.anchoMetros).abs() > 0.05 ||
            (alto - dims.altoMetros).abs() > 0.05)) {
      throw RecintosInvalidosException(
        '"$path" es de ${ancho}x$alto m pero el grafo declara '
        '${dims.anchoMetros}x${dims.altoMetros} m',
      );
    }

    final recintos = <Recinto>[];
    final ids = <String>{};
    for (final j in data['recintos'] as List<dynamic>? ?? const []) {
      final r = Recinto.fromJson(j as Map<String, dynamic>);
      if (!ids.add(r.id)) {
        throw RecintosInvalidosException('Id de recinto duplicado: "${r.id}"');
      }
      recintos.add(r);
    }
    final circulacion = [
      for (final p in data['circulacion'] as List<dynamic>? ?? const [])
        Recinto.parsearPoligono(p as List<dynamic>),
    ];
    return _cache = PlanoRecintos(recintos: recintos, circulacion: circulacion);
  }
}
