import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/nodo.dart';
import '../../models/position.dart';
import '../../models/tipo_nodo.dart';
import '../theme/app_theme.dart';

class MapaPainter extends CustomPainter {
  final List<Nodo> ruta;
  final Position? posicionUsuario;
  final Size mapaSize;
  final Color routeColor;
  final Color destinationColor;
  final Color userColor;

  /// POIs a dibujar sobre el mapa como dots de colores. Usado en la
  /// pantalla de exploración (sin ruta activa) para que el usuario
  /// pueda ver dónde están salones, baños, oficinas, etc. Si está
  /// vacía, no se pinta nada.
  final List<Nodo> pois;

  /// ID del POI que está siendo "highlighted" — se dibuja con un anillo
  /// distintivo. Útil cuando el usuario tocó cerca de un POI.
  final String? poiResaltadoId;

  // Paints cacheados como instance vars: antes se creaban dentro de
  // paint() en cada frame (5+ objetos), forzando GC en Android.
  // Como los colores se resuelven en el factory y el painter es nuevo
  // cuando cambia el tema, los paints viven el ciclo de vida del painter.
  late final Paint _paintLinea = Paint()
    ..color = routeColor
    ..strokeWidth = 3.0
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;

  late final Paint _paintNodo = Paint()
    ..color = routeColor.withValues(alpha: 0.7)
    ..style = PaintingStyle.fill;

  late final Paint _paintAuraDestino = Paint()
    ..color = destinationColor.withValues(alpha: 0.18)
    ..style = PaintingStyle.fill;

  late final Paint _paintDestino = Paint()
    ..color = destinationColor
    ..style = PaintingStyle.fill;

  late final Paint _paintBordeDestino = Paint()
    ..color = Colors.white.withValues(alpha: 0.25)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;

  late final Paint _paintAuraUsuario = Paint()
    ..color = userColor.withValues(alpha: 0.22)
    ..style = PaintingStyle.fill;

  late final Paint _paintUsuario = Paint()
    ..color = userColor
    ..style = PaintingStyle.fill;

  late final Paint _paintCentroUsuario = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;

  MapaPainter({
    required this.ruta,
    required this.mapaSize,
    required this.routeColor,
    required this.destinationColor,
    required this.userColor,
    this.posicionUsuario,
    this.pois = const [],
    this.poiResaltadoId,
  });

  factory MapaPainter.fromContext(
    BuildContext context, {
    required List<Nodo> ruta,
    required Size mapaSize,
    Position? posicionUsuario,
    List<Nodo> pois = const [],
    String? poiResaltadoId,
  }) {
    final c = context.colors;
    return MapaPainter(
      ruta: ruta,
      mapaSize: mapaSize,
      routeColor: c.route,
      destinationColor: c.destination,
      userColor: c.brand,
      posicionUsuario: posicionUsuario,
      pois: pois,
      poiResaltadoId: poiResaltadoId,
    );
  }

  /// Color del dot del POI según su tipo. Pensado para que sean
  /// distinguibles a primera vista en modo exploración.
  static Color colorParaTipo(TipoNodo tipo) {
    switch (tipo) {
      case TipoNodo.salon:
        return const Color(0xFF3B82F6); // azul
      case TipoNodo.bano:
        return const Color(0xFF06B6D4); // cyan
      case TipoNodo.oficina:
        return const Color(0xFF8B5CF6); // morado
      case TipoNodo.entrada:
        return const Color(0xFF22C55E); // verde
      case TipoNodo.escalera:
      case TipoNodo.ascensor:
        return const Color(0xFFF59E0B); // ámbar
      case TipoNodo.bebedero:
        return const Color(0xFF14B8A6); // teal
      case TipoNodo.comedor:
        return const Color(0xFFEF4444); // rojo
      case TipoNodo.interseccion:
      case TipoNodo.marcadorAr:
        return const Color(0xFF94A3B8); // gris
    }
  }

  Offset _toScreen(double x, double y, Size size) {
    final scaleX = size.width / mapaSize.width;
    final scaleY = size.height / mapaSize.height;
    return Offset(x * scaleX, y * scaleY);
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint,
      {double dashLen = 8, double gapLen = 6}) {
    final total = (b - a).distance;
    if (total < 1) return;
    final dir = (b - a) / total;
    double pos = 0;
    bool drawing = true;
    while (pos < total) {
      final segLen = min(drawing ? dashLen : gapLen, total - pos);
      final start = a + dir * pos;
      if (drawing) {
        final end = a + dir * (pos + segLen);
        canvas.drawLine(start, end, paint);
      }
      pos += segLen;
      drawing = !drawing;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (ruta.isEmpty && posicionUsuario == null && pois.isEmpty) return;

    // POIs (modo exploración) — se dibujan primero para que la ruta y el
    // dot del usuario queden encima.
    if (pois.isNotEmpty) {
      _paintPois(canvas, size);
    }

    // Línea punteada entre nodos consecutivos
    for (int i = 0; i < ruta.length - 1; i++) {
      final a = _toScreen(ruta[i].x, ruta[i].y, size);
      final b = _toScreen(ruta[i + 1].x, ruta[i + 1].y, size);
      _drawDashedLine(canvas, a, b, _paintLinea);
    }

    // Nodos intermedios — puntos pequeños
    for (int i = 0; i < ruta.length - 1; i++) {
      final p = _toScreen(ruta[i].x, ruta[i].y, size);
      canvas.drawCircle(p, 4.0, _paintNodo);
    }

    // Destino — pin con aura
    if (ruta.isNotEmpty) {
      final dest = _toScreen(ruta.last.x, ruta.last.y, size);
      canvas.drawCircle(dest, 13.0, _paintAuraDestino);
      canvas.drawCircle(dest, 8.0, _paintDestino);
      canvas.drawCircle(dest, 8.0, _paintBordeDestino);
    }

    // Punto del usuario (Fase 2+)
    if (posicionUsuario != null) {
      final pu = _toScreen(posicionUsuario!.x, posicionUsuario!.y, size);
      canvas.drawCircle(pu, 11.0, _paintAuraUsuario);
      canvas.drawCircle(pu, 7.0, _paintUsuario);
      canvas.drawCircle(pu, 4.0, _paintCentroUsuario);
    }
  }

  /// Dibuja cada POI como un disco coloreado por tipo, con un anillo
  /// blanco para que se destaque del SVG. Si [poiResaltadoId] coincide,
  /// el POI se dibuja un poco más grande con un halo.
  void _paintPois(Canvas canvas, Size size) {
    final paintHaloResaltado = Paint()
      ..color = userColor.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;
    final paintBordeBlanco = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final poi in pois) {
      final p = _toScreen(poi.x, poi.y, size);
      final color = colorParaTipo(poi.tipo);
      final esResaltado = poi.id == poiResaltadoId;
      final radio = esResaltado ? 7.5 : 5.5;

      if (esResaltado) {
        canvas.drawCircle(p, 13.0, paintHaloResaltado);
      }
      canvas.drawCircle(
        p,
        radio,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(p, radio, paintBordeBlanco);
    }
  }

  @override
  bool shouldRepaint(MapaPainter old) =>
      old.ruta != ruta ||
      old.posicionUsuario != posicionUsuario ||
      old.routeColor != routeColor ||
      old.destinationColor != destinationColor ||
      old.userColor != userColor ||
      old.mapaSize != mapaSize ||
      old.pois != pois ||
      old.poiResaltadoId != poiResaltadoId;
}
