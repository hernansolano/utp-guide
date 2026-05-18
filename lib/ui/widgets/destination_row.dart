import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/nodo.dart';
import '../../models/tipo_nodo.dart';
import '../theme/app_theme.dart';

class DestinationRow extends StatelessWidget {
  final Nodo nodo;
  final bool showDivider;
  final VoidCallback onTap;
  final IconData? overrideIcon;

  const DestinationRow({
    super.key,
    required this.nodo,
    required this.onTap,
    this.showDivider = true,
    this.overrideIcon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.brandSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    overrideIcon ?? _iconForTipo(nodo.tipo),
                    color: colors.brand,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nodo.nombre,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colors.fg,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _labelTipo(nodo.tipo),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: colors.fgMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (nodo.accesible) ...[
                  Icon(Icons.accessible_rounded,
                      color: colors.accessible, size: 18),
                  const SizedBox(width: 6),
                ],
                Icon(Icons.chevron_right_rounded,
                    color: colors.fgSoft, size: 20),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 68,
            endIndent: 0,
            color: colors.line,
          ),
      ],
    );
  }

  IconData _iconForTipo(TipoNodo tipo) {
    switch (tipo) {
      case TipoNodo.salon:
        return Icons.school_outlined;
      case TipoNodo.bano:
        return Icons.wc_outlined;
      case TipoNodo.oficina:
        return Icons.business_outlined;
      case TipoNodo.ascensor:
        return Icons.elevator_outlined;
      case TipoNodo.escalera:
        return Icons.stairs_outlined;
      case TipoNodo.bebedero:
        return Icons.water_drop_outlined;
      case TipoNodo.comedor:
        return Icons.restaurant_outlined;
      case TipoNodo.interseccion:
        return Icons.swap_calls_rounded;
      case TipoNodo.entrada:
        return Icons.door_front_door_outlined;
      case TipoNodo.marcadorAr:
        return Icons.view_in_ar_outlined;
    }
  }

  String _labelTipo(TipoNodo tipo) {
    switch (tipo) {
      case TipoNodo.salon:
        return 'Salón';
      case TipoNodo.bano:
        return 'Servicios';
      case TipoNodo.oficina:
        return 'Oficina';
      case TipoNodo.ascensor:
        return 'Ascensor';
      case TipoNodo.escalera:
        return 'Escalera';
      case TipoNodo.bebedero:
        return 'Bebedero';
      case TipoNodo.comedor:
        return 'Comedor';
      case TipoNodo.interseccion:
        return 'Intersección';
      case TipoNodo.entrada:
        return 'Entrada';
      case TipoNodo.marcadorAr:
        return 'Marcador AR';
    }
  }
}
