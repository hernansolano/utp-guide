import 'dart:convert';
import 'package:flutter/services.dart';

/// AssetBundle en memoria: sirve el contenido dado por clave en vez de leer
/// los assets reales. Permite probar los repositorios con datos de prueba
/// sin depender del entorno activo.
class BundleFijo extends CachingAssetBundle {
  final Map<String, String> _archivos;

  BundleFijo(this._archivos);

  /// Atajo para un bundle con un `grafo.json` y/o `beacon_config.json`.
  factory BundleFijo.json({
    Map<String, dynamic>? grafo,
    Map<String, dynamic>? beaconConfig,
  }) =>
      BundleFijo({
        if (grafo != null) 'assets/data/grafo.json': jsonEncode(grafo),
        if (beaconConfig != null)
          'assets/data/beacon_config.json': jsonEncode(beaconConfig),
      });

  @override
  Future<ByteData> load(String key) async {
    final contenido = _archivos[key];
    if (contenido == null) throw StateError('Asset no encontrado: $key');
    return ByteData.sublistView(utf8.encode(contenido));
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final contenido = _archivos[key];
    if (contenido == null) throw StateError('Asset no encontrado: $key');
    return contenido;
  }
}

Map<String, dynamic> nodoJson(String id, String tipo, double x, double y,
        {int piso = 4}) =>
    {
      'id': id,
      'nombre': id,
      'tipo': tipo,
      'x': x,
      'y': y,
      'piso': piso,
      'accesible': true,
    };

Map<String, dynamic> aristaJson(String origen, String destino, double distancia,
        {bool accesible = true, String obstaculo = 'NINGUNO'}) =>
    {
      'origenId': origen,
      'destinoId': destino,
      'distancia': distancia,
      'tipoObstaculo': obstaculo,
      'accesible': accesible,
    };

/// Grafo de prueba (piso 4, 60 × 60 m):
///
/// ```
///  entrada(0,0) ──10── p1(10,0) ──10── p2(20,0)
///      \                  |               |   \
///       \ 21 (escalera)   3               5    \ 8 (escalera)
///        \                |               |     \
///         `──────────► salon_a(10,3)   d(20,5)  aislado(28,0)
/// ```
///
/// - `entrada → d` por escalera (21 m) es más corto que el pasillo (25 m),
///   pero no es accesible.
/// - `aislado` solo se alcanza por escalera.
/// - `sotano` no tiene aristas.
/// - `salon_a` queda pegado al pasillo (detrás de una pared).
Map<String, dynamic> grafoDePrueba({bool conMapaSvg = true}) => {
      'version': '1.0',
      'piso': 4,
      'edificio': 'TEST',
      if (conMapaSvg) 'mapa_svg': 'assets/maps/_template.svg',
      'mapa_ancho_metros': 60.0,
      'mapa_alto_metros': 60.0,
      'nodos': [
        nodoJson('entrada', 'ENTRADA', 0, 0),
        nodoJson('p1', 'INTERSECCION', 10, 0),
        nodoJson('p2', 'INTERSECCION', 20, 0),
        nodoJson('salon_a', 'SALON', 10, 3),
        nodoJson('d', 'SALON', 20, 5),
        nodoJson('aislado', 'OFICINA', 28, 0),
        nodoJson('sotano', 'OFICINA', 50, 50),
      ],
      'aristas': [
        aristaJson('entrada', 'p1', 10),
        aristaJson('p1', 'p2', 10),
        aristaJson('p1', 'salon_a', 3),
        aristaJson('p2', 'd', 5),
        aristaJson('entrada', 'd', 21,
            accesible: false, obstaculo: 'ESCALERA'),
        aristaJson('p2', 'aislado', 8,
            accesible: false, obstaculo: 'ESCALERA'),
      ],
    };
