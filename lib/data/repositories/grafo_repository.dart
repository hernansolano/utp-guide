import 'dart:convert';
import 'package:flutter/services.dart';
import '../../models/nodo.dart';
import '../../models/arista.dart';
import '../../models/tipo_nodo.dart';
import '../exceptions.dart';

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

    final tieneEntrada =
        nodosList.any((n) => n['tipo'] == 'ENTRADA');
    if (!tieneEntrada) {
      throw GrafoInvalidoException('El grafo debe tener al menos un nodo ENTRADA');
    }
  }

  Future<List<Nodo>> obtenerNodos() async {
    final data = await _load();
    return (data['nodos'] as List<dynamic>)
        .map((j) => Nodo.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<List<Arista>> obtenerAristas() async {
    final data = await _load();
    final directas = (data['aristas'] as List<dynamic>)
        .map((j) => Arista.fromJson(j as Map<String, dynamic>))
        .toList();
    final inversas = directas.map((a) => a.invertida()).toList();
    return [...directas, ...inversas];
  }

  Future<Nodo> obtenerNodoPorId(String id) async {
    final nodos = await obtenerNodos();
    final nodo = nodos.where((n) => n.id == id).firstOrNull;
    if (nodo == null) throw NodeNotFoundException(id);
    return nodo;
  }

  Future<List<Nodo>> obtenerNodosPorTipo(TipoNodo tipo) async {
    final nodos = await obtenerNodos();
    return nodos.where((n) => n.tipo == tipo).toList();
  }
}
