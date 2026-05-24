import 'dart:math';
import 'package:flutter/material.dart' show IconData, Icons;
import 'nodo.dart';

/// Un paso de navegación es una instrucción atómica que el usuario debe
/// seguir: "camina N metros", o "gira a la izquierda y camina N metros",
/// o "llegaste".
///
/// Se construye a partir de la lista de nodos que conforman la ruta
/// (output de [RoutingService.calcularRuta]) usando [generarDesdeRuta].
/// Cada paso describe **un segmento de la ruta más el giro que lo precede**
/// (excepto el primero, que no tiene giro, y el último, que es la llegada).
///
/// Ejemplo: ruta de 4 nodos `[A, B, C, D]` produce 4 pasos:
///   - Paso 0: caminar de A a B (sin giro previo)
///   - Paso 1: girar en B según ángulo AB→BC, luego caminar a C
///   - Paso 2: girar en C según ángulo BC→CD, luego caminar a D
///   - Paso 3: "Llegaste a [nombre del destino]"
class PasoNavegacion {
  /// Texto humano de la instrucción.
  ///   "Camina 8 m"
  ///   "Gira a la izquierda, camina 5 m"
  ///   "Llegaste al Salón 101"
  final String instruccion;

  /// Texto corto del giro, sin la parte de distancia.
  ///   "Sigue recto", "Gira a la derecha", "Media vuelta", null si es el
  ///   paso inicial (sin giro previo) o final (llegada).
  final String? giro;

  /// Icono apropiado para mostrar en la UI (flecha de giro, recta, llegada).
  final IconData icono;

  /// Metros que el usuario debe caminar en este segmento. 0 para el paso
  /// de llegada.
  final double distanciaMetros;

  /// Nodo al que se llega tras completar este paso.
  final Nodo destino;

  /// Posición del paso dentro de la ruta (0 = primer paso, last = llegada).
  final int indice;

  const PasoNavegacion({
    required this.instruccion,
    required this.giro,
    required this.icono,
    required this.distanciaMetros,
    required this.destino,
    required this.indice,
  });

  /// Construye la lista completa de pasos de navegación a partir de una
  /// ruta (lista ordenada de nodos desde origen a destino).
  ///
  /// Si la ruta tiene menos de 2 nodos (caso degenerado: origen == destino),
  /// devuelve un solo paso de "Ya estás en el destino".
  static List<PasoNavegacion> generarDesdeRuta(List<Nodo> ruta) {
    if (ruta.isEmpty) return [];
    if (ruta.length == 1) {
      return [
        PasoNavegacion(
          instruccion: 'Ya estás en ${ruta.first.nombre}',
          giro: null,
          icono: Icons.flag_rounded,
          distanciaMetros: 0,
          destino: ruta.first,
          indice: 0,
        ),
      ];
    }

    final pasos = <PasoNavegacion>[];

    // Paso inicial: avanzar desde el origen hasta el segundo nodo, sin giro.
    final distInicial = _distancia(ruta[0], ruta[1]);
    pasos.add(PasoNavegacion(
      instruccion: 'Camina ${_formatearMetros(distInicial)}',
      giro: null,
      icono: Icons.straight_rounded,
      distanciaMetros: distInicial,
      destino: ruta[1],
      indice: 0,
    ));

    // Pasos intermedios: cada uno empieza con un giro y termina caminando
    // al siguiente nodo.
    for (int i = 1; i < ruta.length - 1; i++) {
      final giro = _clasificarGiro(ruta[i - 1], ruta[i], ruta[i + 1]);
      final dist = _distancia(ruta[i], ruta[i + 1]);
      final instruccion = giro.esRecto
          ? 'Sigue recto, camina ${_formatearMetros(dist)}'
          : '${giro.texto}, camina ${_formatearMetros(dist)}';
      pasos.add(PasoNavegacion(
        instruccion: instruccion,
        giro: giro.texto,
        icono: giro.icono,
        distanciaMetros: dist,
        destino: ruta[i + 1],
        indice: i,
      ));
    }

    // Paso final: llegada al destino.
    pasos.add(PasoNavegacion(
      instruccion: 'Llegaste a ${ruta.last.nombre}',
      giro: null,
      icono: Icons.flag_rounded,
      distanciaMetros: 0,
      destino: ruta.last,
      indice: ruta.length - 1,
    ));

    return pasos;
  }

  static double _distancia(Nodo a, Nodo b) =>
      sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2));

  static String _formatearMetros(double m) {
    if (m < 1) return '< 1 m';
    return '${m.toStringAsFixed(0)} m';
  }

  /// Calcula el giro en el nodo `b` cuando se llega desde `a` y se va a `c`.
  ///
  /// Sistema de coordenadas: X→derecha, Y→abajo (convención SVG/Flutter).
  /// El producto cruz `AB × BC` da el sentido del giro:
  ///   - cross > 0 → giro a la derecha (en pantalla, sentido horario)
  ///   - cross < 0 → giro a la izquierda (sentido antihorario)
  ///   - cross ≈ 0 → línea recta
  ///
  /// El ángulo absoluto (`atan2(cross, dot)`) determina la severidad:
  ///   < 20°    sigue recto
  ///   20-60°   ligeramente a la izq/der
  ///   60-120°  gira a la izq/der
  ///   120-160° giro pronunciado a la izq/der
  ///   > 160°   media vuelta
  static _ClasificacionGiro _clasificarGiro(Nodo a, Nodo b, Nodo c) {
    final abx = b.x - a.x, aby = b.y - a.y;
    final bcx = c.x - b.x, bcy = c.y - b.y;
    final dot = abx * bcx + aby * bcy;
    final cross = abx * bcy - aby * bcx;
    final anguloGrados = atan2(cross, dot) * 180 / pi;
    final abs = anguloGrados.abs();
    final esDerecha = anguloGrados > 0;

    if (abs < 20) {
      return const _ClasificacionGiro(
          texto: 'Sigue recto', icono: Icons.straight_rounded, esRecto: true);
    }
    if (abs > 160) {
      return _ClasificacionGiro(
          texto: 'Da media vuelta',
          icono: esDerecha ? Icons.u_turn_right_rounded : Icons.u_turn_left_rounded);
    }
    if (abs > 120) {
      return _ClasificacionGiro(
          texto: esDerecha
              ? 'Giro pronunciado a la derecha'
              : 'Giro pronunciado a la izquierda',
          icono: esDerecha
              ? Icons.turn_sharp_right_rounded
              : Icons.turn_sharp_left_rounded);
    }
    if (abs > 60) {
      return _ClasificacionGiro(
          texto:
              esDerecha ? 'Gira a la derecha' : 'Gira a la izquierda',
          icono: esDerecha
              ? Icons.turn_right_rounded
              : Icons.turn_left_rounded);
    }
    return _ClasificacionGiro(
        texto: esDerecha
            ? 'Ligeramente a la derecha'
            : 'Ligeramente a la izquierda',
        icono: esDerecha
            ? Icons.subdirectory_arrow_right_rounded
            : Icons.subdirectory_arrow_left_rounded);
  }
}

class _ClasificacionGiro {
  final String texto;
  final IconData icono;
  final bool esRecto;
  const _ClasificacionGiro({
    required this.texto,
    required this.icono,
    this.esRecto = false,
  });
}
