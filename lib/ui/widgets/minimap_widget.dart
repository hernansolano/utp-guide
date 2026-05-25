import 'package:flutter/material.dart';
import '../../models/nodo.dart';
import '../../models/position.dart';
import '../theme/app_theme.dart';
import 'map_view.dart';

/// Minimapa de 140×140 usado en el modo AR.
///
/// Reusa [MapView] en modo compacto (pan/zoom desactivado, sin
/// callbacks de interacción) para garantizar que el dot del usuario
/// se renderice correctamente respecto al SVG. Antes usaba un
/// `CustomPaint` directo, lo que arrastraba el mismo bug de
/// letterboxing que tenía MapaScreen pre-refactor.
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
        child: MapView(
          mapaSize: mapaSize,
          // El minimapa no muestra el SVG de fondo, solo la ruta y el dot.
          // Esto deja claro el "mapa interno" sin distraer con paredes.
          svgAsset: null,
          ruta: ruta,
          posicionUsuario: posicionUsuario,
          // El minimapa es read-only: ni pan, ni zoom, ni taps.
          panZoomHabilitado: false,
        ),
      ),
    );
  }
}
