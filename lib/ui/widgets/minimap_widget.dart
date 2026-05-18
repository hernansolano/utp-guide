import 'package:flutter/material.dart';
import '../../models/nodo.dart';
import '../../models/position.dart';
import '../theme/app_theme.dart';
import 'mapa_painter.dart';

class MinimapWidget extends StatelessWidget {
  final List<Nodo> ruta;
  final Position? posicionUsuario;
  final Size mapaSize;

  const MinimapWidget({
    super.key,
    required this.ruta,
    required this.mapaSize,
    this.posicionUsuario,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        color: colors.surfaceElevated.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.5 : 0.14),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: CustomPaint(
          painter: MapaPainter.fromContext(
            context,
            ruta: ruta,
            mapaSize: mapaSize,
            posicionUsuario: posicionUsuario,
          ),
        ),
      ),
    );
  }
}
