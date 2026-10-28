import 'package:flutter_test/flutter_test.dart';
import 'package:utp_guide/data/exceptions.dart';
import 'package:utp_guide/data/repositories/grafo_repository.dart';

import '../helpers/bundle_fijo.dart';

GrafoRepository _repo(Map<String, dynamic> grafo) =>
    GrafoRepository(bundle: BundleFijo.json(grafo: grafo));

void main() {
  group('GrafoRepository', () {
    test('carga metadatos del grafo', () async {
      final repo = _repo(grafoDePrueba());
      expect(await repo.obtenerPiso(), 4);
      expect(await repo.obtenerMapaSvgPath(), 'assets/maps/_template.svg');
      final dims = await repo.obtenerDimensionesMapa();
      expect(dims.anchoMetros, 60);
      expect(dims.altoMetros, 60);
    });

    test('duplica cada arista en ambos sentidos', () async {
      final repo = _repo(grafoDePrueba());
      final aristas = await repo.obtenerAristas();
      expect(aristas.length, 2 * 6);
      expect(
          aristas.any((a) => a.origenId == 'p1' && a.destinoId == 'entrada'),
          isTrue);
    });

    test('rechaza un grafo sin mapa_svg', () {
      final repo = _repo(grafoDePrueba(conMapaSvg: false));
      expect(repo.obtenerNodos(), throwsA(isA<GrafoInvalidoException>()));
    });

    test('rechaza ids de nodo duplicados', () {
      final g = grafoDePrueba();
      (g['nodos'] as List).add(nodoJson('p1', 'INTERSECCION', 1, 1));
      expect(_repo(g).obtenerNodos(),
          throwsA(isA<GrafoInvalidoException>()));
    });

    test('rechaza aristas hacia nodos inexistentes', () {
      final g = grafoDePrueba();
      (g['aristas'] as List).add(aristaJson('p1', 'fantasma', 3));
      expect(_repo(g).obtenerNodos(),
          throwsA(isA<GrafoInvalidoException>()));
    });

    test('rechaza distancias no positivas', () {
      final g = grafoDePrueba();
      (g['aristas'] as List).add(aristaJson('p2', 'salon_a', 0));
      expect(_repo(g).obtenerNodos(),
          throwsA(isA<GrafoInvalidoException>()));
    });

    test('rechaza un grafo sin nodo ENTRADA', () {
      final g = grafoDePrueba();
      (g['nodos'] as List).removeWhere((n) => n['tipo'] == 'ENTRADA');
      (g['aristas'] as List).removeWhere(
          (a) => a['origenId'] == 'entrada' || a['destinoId'] == 'entrada');
      expect(_repo(g).obtenerNodos(),
          throwsA(isA<GrafoInvalidoException>()));
    });
  });
}
