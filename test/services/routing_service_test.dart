import 'package:flutter_test/flutter_test.dart';
import 'package:utp_guide/data/exceptions.dart';
import 'package:utp_guide/data/repositories/grafo_repository.dart';
import 'package:utp_guide/models/perfil_movilidad.dart';
import 'package:utp_guide/services/routing_service.dart';

import '../helpers/bundle_fijo.dart';

void main() {
  late RoutingService routing;

  setUp(() {
    final repo = GrafoRepository(
        bundle: BundleFijo.json(grafo: grafoDePrueba()));
    routing = RoutingService(repo);
  });

  Future<List<String>> ruta(String o, String d, PerfilMovilidad p) async =>
      (await routing.calcularRuta(origenId: o, destinoId: d, perfil: p))
          .map((n) => n.id)
          .toList();

  group('RoutingService.calcularRuta', () {
    test('estándar toma el atajo por escalera (más corto)', () async {
      expect(await ruta('entrada', 'd', PerfilMovilidad.estandar),
          ['entrada', 'd']);
    });

    test('accesible evita la escalera y va por el pasillo', () async {
      expect(await ruta('entrada', 'd', PerfilMovilidad.accesible),
          ['entrada', 'p1', 'p2', 'd']);
    });

    test('recorre las aristas en ambos sentidos', () async {
      expect(await ruta('d', 'salon_a', PerfilMovilidad.accesible),
          ['d', 'p2', 'p1', 'salon_a']);
    });

    test('origen == destino devuelve solo ese nodo', () async {
      expect(await ruta('p1', 'p1', PerfilMovilidad.estandar), ['p1']);
    });

    test('sin ruta accesible lanza NoAccessibleRouteException', () {
      expect(ruta('entrada', 'aislado', PerfilMovilidad.accesible),
          throwsA(isA<NoAccessibleRouteException>()));
    });

    test('nodo sin aristas lanza RouteNotFoundException', () {
      expect(ruta('entrada', 'sotano', PerfilMovilidad.estandar),
          throwsA(isA<RouteNotFoundException>()));
    });

    test('nodo inexistente lanza NodeNotFoundException', () {
      expect(ruta('entrada', 'no_existe', PerfilMovilidad.estandar),
          throwsA(isA<NodeNotFoundException>()));
    });
  });

  group('RoutingService.nodoMasCercano', () {
    test('ignora salones aunque estén más cerca (detrás de la pared)',
        () async {
      // salon_a está a 0,5 m; p1 a 2,5 m. El origen de la ruta debe ser
      // el pasillo, no el salón vecino.
      final nodo = await routing.nodoMasCercano(10, 2.5);
      expect(nodo.id, 'p1');
    });

    test('elige el nodo de circulación más cercano', () async {
      expect((await routing.nodoMasCercano(18, 1)).id, 'p2');
      expect((await routing.nodoMasCercano(2, 0)).id, 'entrada');
    });
  });
}
