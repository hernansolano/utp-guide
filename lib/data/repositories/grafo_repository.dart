import 'dart:convert';
import 'package:flutter/services.dart';
import '../../models/nodo.dart';
import '../../models/arista.dart';
import '../../models/tipo_nodo.dart';
import '../exceptions.dart';

/// Dimensiones físicas del mapa de un piso, en metros.
///
/// Se usan para convertir entre el sistema de coordenadas del grafo
/// (metros) y el SVG (píxeles), y para clampar la posición estimada
/// dentro de los límites del piso.
class DimensionesMapa {
  final double anchoMetros;
  final double altoMetros;

  const DimensionesMapa(this.anchoMetros, this.altoMetros);
}

/// Carga, valida y expone el grafo de navegación de un piso.
///
/// La fuente de verdad es `assets/data/grafo.json`. Ver
/// `docs/grafo-format.md` para el formato completo.
///
/// El grafo se modela como **no dirigido**: el repositorio agrega
/// automáticamente la arista inversa de cada arista del archivo. Por
/// ejemplo, si el JSON define `A → B con distancia=5`, este repositorio
/// devuelve dos aristas: `A → B` y `B → A`, ambas con distancia 5.
///
/// La validación ([_validar]) se ejecuta al cargar el archivo y rechaza
/// grafos con IDs duplicados, aristas a nodos inexistentes, distancias
/// no positivas, o sin nodo `ENTRADA`. Lanza [GrafoInvalidoException]
/// con un mensaje descriptivo.
class GrafoRepository {
  Map<String, dynamic>? _cachedData;

  Future<Map<String, dynamic>> _load() async {
    if (_cachedData != null) return _cachedData!;
    try {
      final raw = await rootBundle.loadString('assets/data/grafo.json');
      _cachedData = jsonDecode(raw) as Map<String, dynamic>;
      _validar(_cachedData!);
      return _cachedData!;
    } on GrafoInvalidoException {
      rethrow;
    } catch (e) {
      throw GrafoParseException('Error al parsear grafo.json: $e');
    }
  }

  void _validar(Map<String, dynamic> data) {
    final nodosList = (data['nodos'] as List<dynamic>? ?? []);
    final aristasList = (data['aristas'] as List<dynamic>? ?? []);

    final ids = <String>{};
    for (final n in nodosList) {
      final id = n['id'] as String;
      if (!ids.add(id)) {
        throw GrafoInvalidoException('ID de nodo duplicado: "$id"');
      }
    }

    for (final a in aristasList) {
      final origen = a['origenId'] as String;
      final destino = a['destinoId'] as String;
      final distancia = (a['distancia'] as num).toDouble();

      if (!ids.contains(origen)) {
        throw GrafoInvalidoException(
            'Arista referencia nodo inexistente: "$origen"');
      }
      if (!ids.contains(destino)) {
        throw GrafoInvalidoException(
            'Arista referencia nodo inexistente: "$destino"');
      }
      if (distancia <= 0) {
        throw GrafoInvalidoException(
            'Arista con distancia no positiva entre "$origen" y "$destino"');
      }
    }

    for (final n in nodosList) {
      if (n['tipo'] == 'MARCADOR_AR' && n['aruco_id'] == null) {
        throw GrafoInvalidoException(
            'Nodo marcador_ar "${n['id']}" sin aruco_id');
      }
    }

    final tieneEntrada = nodosList.any((n) => n['tipo'] == 'ENTRADA');
    if (!tieneEntrada) {
      throw GrafoInvalidoException(
          'El grafo debe tener al menos un nodo ENTRADA');
    }
  }

  /// Devuelve todos los nodos del piso.
  Future<List<Nodo>> obtenerNodos() async {
    final data = await _load();
    return (data['nodos'] as List<dynamic>)
        .map((j) => Nodo.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  /// Devuelve todas las aristas del grafo en ambas direcciones.
  ///
  /// El grafo del JSON es no dirigido — este método agrega la arista
  /// inversa de cada entrada del archivo, lo que es necesario para que
  /// el algoritmo A* pueda recorrer aristas en cualquier dirección.
  Future<List<Arista>> obtenerAristas() async {
    final data = await _load();
    final directas = (data['aristas'] as List<dynamic>)
        .map((j) => Arista.fromJson(j as Map<String, dynamic>))
        .toList();
    final inversas = directas.map((a) => a.invertida()).toList();
    return [...directas, ...inversas];
  }

  /// Devuelve un nodo por su `id`. Lanza [NodeNotFoundException] si no existe.
  Future<Nodo> obtenerNodoPorId(String id) async {
    final nodos = await obtenerNodos();
    final nodo = nodos.where((n) => n.id == id).firstOrNull;
    if (nodo == null) throw NodeNotFoundException(id);
    return nodo;
  }

  /// Devuelve todos los nodos de un tipo específico (Salones, Baños, etc.).
  Future<List<Nodo>> obtenerNodosPorTipo(TipoNodo tipo) async {
    final nodos = await obtenerNodos();
    return nodos.where((n) => n.tipo == tipo).toList();
  }

  /// Dimensiones físicas del piso modelado, en metros.
  ///
  /// Se leen de `mapa_ancho_metros` y `mapa_alto_metros` en el JSON.
  /// Si faltan, se usan 5×5 m como default (compatibilidad con el cuarto
  /// de prueba inicial).
  Future<DimensionesMapa> obtenerDimensionesMapa() async {
    final data = await _load();
    return DimensionesMapa(
      (data['mapa_ancho_metros'] as num?)?.toDouble() ?? 5.0,
      (data['mapa_alto_metros'] as num?)?.toDouble() ?? 5.0,
    );
  }

  /// Código del edificio modelado, según `edificio` en el JSON. Default
  /// "FISC" si no está definido.
  Future<String> obtenerEdificio() async {
    final data = await _load();
    return data['edificio'] as String? ?? 'FISC';
  }

  /// Número del piso modelado, según `piso` en el JSON. Default 1.
  Future<int> obtenerPiso() async {
    final data = await _load();
    return data['piso'] as int? ?? 1;
  }

  /// Ruta del SVG del piso, leída del campo `mapa_svg` del JSON. Si falta,
  /// usa el SVG de prueba como fallback.
  ///
  /// Que viva en el grafo (y no hardcodeada en las pantallas) permite que
  /// cada piso declare su propio SVG sin tocar código. Ver formato en
  /// `docs/grafo-format.md`.
  Future<String> obtenerMapaSvgPath() async {
    final data = await _load();
    return data['mapa_svg'] as String? ?? 'assets/maps/test_room_5x5.svg';
  }
}
