import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:utp_guide/models/recinto.dart';
import 'package:utp_guide/models/tipo_nodo.dart';

Recinto _recinto(String id, List<List<double>> pts, {String? nodoId}) =>
    Recinto.fromJson({
      'id': id,
      'nombre': 'Recinto $id',
      'tipo': 'SALON',
      'etiqueta': [0, 0],
      'poligono': pts,
      'nodo_id': nodoId,
    });

void main() {
  group('Recinto.contiene', () {
    // Forma de L: un cuadrado de 4x4 al que le falta la esquina (2..4, 0..2).
    final ele = _recinto('L', [
      [0, 0],
      [2, 0],
      [2, 2],
      [4, 2],
      [4, 4],
      [0, 4],
    ]);

    test('punto adentro', () {
      expect(ele.contiene(const Offset(1, 1)), isTrue);
      expect(ele.contiene(const Offset(3, 3)), isTrue);
    });

    test('punto en la muesca de la L queda afuera', () {
      expect(ele.contiene(const Offset(3, 1)), isFalse);
    });

    test('punto fuera de la caja envolvente', () {
      expect(ele.contiene(const Offset(5, 5)), isFalse);
      expect(ele.contiene(const Offset(-1, 2)), isFalse);
    });

    test('sin polígono nunca contiene', () {
      final sinPoli = _recinto('vacio', []);
      expect(sinPoli.tienePoligono, isFalse);
      expect(sinPoli.contiene(Offset.zero), isFalse);
    });
  });

  group('PlanoRecintos', () {
    final a = _recinto('a', [
      [0, 0],
      [2, 0],
      [2, 2],
      [0, 2],
    ], nodoId: 'n_a');
    final b = _recinto('b', [
      [3, 0],
      [5, 0],
      [5, 2],
      [3, 2],
    ]);
    final plano = PlanoRecintos(recintos: [a, b], circulacion: const []);

    test('recintoEn devuelve el recinto tocado o null en el pasillo', () {
      expect(plano.recintoEn(const Offset(1, 1))?.id, 'a');
      expect(plano.recintoEn(const Offset(4, 1))?.id, 'b');
      expect(plano.recintoEn(const Offset(2.5, 1)), isNull);
    });

    test('recintoDeNodo usa el enlace al grafo', () {
      expect(plano.recintoDeNodo('n_a')?.id, 'a');
      expect(plano.recintoDeNodo('otro'), isNull);
    });

    test('el plano vacío no tiene recintos', () {
      expect(PlanoRecintos.vacio.estaVacio, isTrue);
      expect(PlanoRecintos.vacio.recintoEn(Offset.zero), isNull);
    });
  });

  test('TipoRecinto mapea a TipoNodo y marca lo no público', () {
    expect(TipoRecinto.fromJson('BANO').tipoNodo, TipoNodo.bano);
    expect(TipoRecinto.fromJson('servicio').tipoNodo, isNull);
    expect(TipoRecinto.servicio.esPublico, isFalse);
    expect(TipoRecinto.salon.esPublico, isTrue);
    expect(() => TipoRecinto.fromJson('GARAJE'), throwsArgumentError);
  });

  // Sanidad del plano generado desde el PDF oficial: si el extractor cambia
  // y rompe algo (ids repetidos, polígonos fuera del mapa, etiquetas que no
  // caen en su recinto), este test lo detecta antes de llegar a la app.
  group('Plano oficial del piso 4 (assets)', () {
    final data =
        jsonDecode(
              File(
                'assets/data/recintos/fisc_piso4_oficial.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final ancho = (data['mapa_ancho_metros'] as num).toDouble();
    final alto = (data['mapa_alto_metros'] as num).toDouble();
    final recintos = [
      for (final j in data['recintos'] as List<dynamic>)
        Recinto.fromJson(j as Map<String, dynamic>),
    ];

    test('coincide con las dimensiones del grafo del entorno', () {
      final grafo =
          jsonDecode(
                File(
                  'assets/data/entornos/piso4_oficial/grafo.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(grafo['mapa_ancho_metros'], ancho);
      expect(grafo['mapa_alto_metros'], alto);
      expect(
        grafo['recintos_json'],
        'assets/data/recintos/fisc_piso4_oficial.json',
      );
    });

    test('ids únicos y la mayoría con polígono', () {
      expect(recintos.map((r) => r.id).toSet().length, recintos.length);
      expect(
        recintos.where((r) => r.tienePoligono).length,
        greaterThanOrEqualTo(60),
      );
    });

    test('todos los puntos caen dentro del mapa', () {
      for (final r in recintos) {
        for (final p in [...r.poligono, r.etiqueta]) {
          expect(p.dx, inInclusiveRange(0, ancho), reason: r.id);
          expect(p.dy, inInclusiveRange(0, alto), reason: r.id);
        }
      }
    });

    test('la etiqueta de cada recinto cae dentro de su propio polígono', () {
      for (final r in recintos.where((r) => r.tienePoligono)) {
        expect(r.contiene(r.etiqueta), isTrue, reason: '${r.id} ${r.nombre}');
      }
    });

    test('los salones 3-401 a 3-416 están y no se superponen', () {
      final codigos = recintos.map((r) => r.codigo).whereType<String>().toSet();
      for (var n = 401; n <= 416; n++) {
        expect(codigos, contains('3-$n'));
      }
      final plano = PlanoRecintos(recintos: recintos, circulacion: const []);
      for (final r in recintos.where((r) => r.tienePoligono)) {
        expect(plano.recintoEn(r.etiqueta)?.id, r.id, reason: r.id);
      }
    });
  });
}
