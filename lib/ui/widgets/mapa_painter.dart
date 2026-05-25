import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/nodo.dart';
import '../../models/position.dart';
import '../theme/app_theme.dart';

class MapaPainter extends CustomPainter {
  final List<Nodo> ruta;
  final Position? posicionUsuario;
  final Size mapaSize;
  final Color routeColor;
  final Color destinationColor;
  final Color userColor;

  const MapaPainter({
    required this.ruta,
    required this.mapaSize,
    required this.routeColor,
    required this.destinationColor,
    required this.userColor,
    this.posicionUsuario,
  });

  factory MapaPainter.fromContext(
    BuildContext context, {
    required List<Nodo> ruta,
    required Size mapaSize,
    Position? posicionUsuario,
  }) {
    final c = context.colors;
    return MapaPainter(
      ruta: ruta,
      mapaSize: mapaSize,
      routeColor: c.route,
      destinationColor: c.destination,
      userColor: c.brand,
      posicionUsuario: posicionUsuario,
    );
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
    if (ruta.isEmpty) return;

    final paintLinea = Paint()
      ..color = routeColor
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Línea punteada entre nodos consecutivos
    for (int i = 0; i < ruta.length - 1; i++) {
      final a = _toScreen(ruta[i].x, ruta[i].y, size);
      final b = _toScreen(ruta[i + 1].x, ruta[i + 1].y, size);
      _drawDashedLine(canvas, a, b, paintLinea);
    }

    // Nodos intermedios — puntos pequeños
    for (int i = 0; i < ruta.length - 1; i++) {
      final p = _toScreen(ruta[i].x, ruta[i].y, size);
      canvas.drawCircle(p, 4.0,
          Paint()
            ..color = routeColor.withValues(alpha: 0.7)
            ..style = PaintingStyle.fill);
    }

    // Destino — pin con aura
    final dest = _toScreen(ruta.last.x, ruta.last.y, size);
    canvas.drawCircle(dest, 13.0,
        Paint()
          ..color = destinationColor.withValues(alpha: 0.18)
          ..style = PaintingStyle.fill);
    canvas.drawCircle(dest, 8.0,
        Paint()
          ..color = destinationColor
          ..style = PaintingStyle.fill);
    canvas.drawCircle(dest, 8.0,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);

    // Punto del usuario (Fase 2+)
    if (posicionUsuario != null) {
      final pu = _toScreen(posicionUsuario!.x, posicionUsuario!.y, size);
      canvas.drawCircle(pu, 11.0,
          Paint()
            ..color = userColor.withValues(alpha: 0.22)
            ..style = PaintingStyle.fill);
      canvas.drawCircle(pu, 7.0,
          Paint()
            ..color = userColor
            ..style = PaintingStyle.fill);
      canvas.drawCircle(pu, 4.0,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(MapaPainter old) =>
      old.ruta != ruta ||
      old.posicionUsuario != posicionUsuario ||
      old.routeColor != routeColor ||
      old.destinationColor != destinationColor ||
      old.userColor != userColor ||
      old.mapaSize != mapaSize;
}
