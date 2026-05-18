import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

enum PillVariant { primary, secondary, ghost, soft, danger, dangerSolid }
enum PillSize { sm, md, lg }

class PillButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final PillVariant variant;
  final PillSize size;
  final Widget? leading;

  const PillButton({
    super.key,
    required this.child,
    this.onPressed,
    this.variant = PillVariant.primary,
    this.size = PillSize.md,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final (bg, fg, border) = switch (variant) {
      PillVariant.primary => (colors.brand, Colors.white, null),
      PillVariant.secondary => (
          colors.surface,
          colors.brand,
          Border.all(color: colors.brand, width: 1.5)
        ),
      PillVariant.ghost => (Colors.transparent, colors.brand, null),
      PillVariant.soft => (colors.brandSoft, colors.brand, null),
      PillVariant.danger => (colors.dangerBg, colors.danger, null),
      PillVariant.dangerSolid => (colors.danger, Colors.white, null),
    };

    final (height, hPadding, fontSize) = switch (size) {
      PillSize.sm => (36.0, 16.0, 13.0),
      PillSize.md => (44.0, 22.0, 14.0),
      PillSize.lg => (52.0, 28.0, 16.0),
    };

    return GestureDetector(
      onTap: onPressed,
      child: Opacity(
        opacity: onPressed == null ? 0.45 : 1,
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: hPadding),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: border,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 8)],
              DefaultTextStyle(
                style: GoogleFonts.plusJakartaSans(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                  color: fg,
                  height: 1,
                ),
                child: IconTheme(
                  data: IconThemeData(color: fg, size: fontSize + 2),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
