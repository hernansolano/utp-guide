import 'dart:math';
import '../data/exceptions.dart';
import '../data/repositories/grafo_repository.dart';
import '../models/arista.dart';
import '../models/nodo.dart';
import '../models/perfil_movilidad.dart';
import '../models/tipo_nodo.dart';

class RoutingService {
  final GrafoRepository _repo;

  RoutingService(this._repo);

  Future<List<Nodo>> calcularRuta({
    required String origenId,
    required String destinoId,
    required PerfilMovilidad perfil,
  }) async {
    final nodos = await _repo.obtenerNodos();
    final todasAristas = await _repo.obtenerAristas();

    final mapaDeNodos = {for (final n in nodos) n.id: n};

    if (!mapaDeNodos.containsKey(origenId)) {
      throw NodeNotFoundException(origenId);
    }
    if (!mapaDeNodos.containsKey(destinoId)) {
      throw NodeNotFoundException(destinoId);
    }

    if (origenId == destinoId) return [mapaDeNodos[origenId]!];

    // Filtrar aristas según perfil antes de correr A*
    final aristas = perfil == PerfilMovilidad.accesible
        ? todasAristas.where((a) => a.accesible).toList()
        : todasAristas;

    // Construir mapa de adyacencia
    final adyacencia = <String, List<Arista>>{};
    for (final n in nodos) {
      adyacencia[n.id] = [];
    }
    for (final a in aristas) {
      adyacencia[a.origenId]!.add(a);
    }

    final origen = mapaDeNodos[origenId]!;
    final destino = mapaDeNodos[destinoId]!;

    double h(Nodo a, Nodo b) =>
        sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2));

    final gScore = <String, double>{origenId: 0.0};
    final fScore = <String, double>{origenId: h(origen, destino)};
    final cameFrom = <String, String>{};
    final openSet = <String>{origenId};
    final closedSet = <String>{};

    while (openSet.isNotEmpty) {
      final current = openSet.reduce(
        (a, b) => (fScore[a] ?? double.infinity) <= (fScore[b] ?? double.infinity) ? a : b,
      );

      if (current == destinoId) {
        return _reconstruirRuta(cameFrom, current, mapaDeNodos);
      }

      openSet.remove(current);
      closedSet.add(current);

      for (final arista in adyacencia[current] ?? []) {
        final vecino = arista.destinoId;
        if (closedSet.contains(vecino)) continue;

        final tentativeG =
            (gScore[current] ?? double.infinity) + arista.distancia;
        if (tentativeG < (gScore[vecino] ?? double.infinity)) {
          cameFrom[vecino] = current;
          gScore[vecino] = tentativeG;
          fScore[vecino] =
              tentativeG + h(mapaDeNodos[vecino]!, destino);
          openSet.add(vecino);
        }
      }
    }

    if (perfil == PerfilMovilidad.accesible) {
      throw NoAccessibleRouteException();
    }
    throw RouteNotFoundException(
        'No existe ruta entre "$origenId" y "$destinoId"');
  }

  List<Nodo> _reconstruirRuta(
    Map<String, String> cameFrom,
    String current,
    Map<String, Nodo> nodos,
  ) {
    final ruta = <Nodo>[nodos[current]!];
    var node = current;
    while (cameFrom.containsKey(node)) {
      node = cameFrom[node]!;
      ruta.insert(0, nodos[node]!);
    }
    return ruta;
  }

  Future<List<Nodo>> nodosPorTipo(TipoNodo tipo) =>
      _repo.obtenerNodosPorTipo(tipo);

  Future<Nodo> nodoMasCercano(double x, double y) async {
    final nodos = await _repo.obtenerNodos();
    return nodos.reduce((a, b) {
      final da = sqrt(pow(a.x - x, 2) + pow(a.y - y, 2));
      final db = sqrt(pow(b.x - x, 2) + pow(b.y - y, 2));
      return da <= db ? a : b;
    });
  }

  Future<bool> existeNodo(String id) async {
    final nodos = await _repo.obtenerNodos();
    return nodos.any((n) => n.id == id);
  }
}
