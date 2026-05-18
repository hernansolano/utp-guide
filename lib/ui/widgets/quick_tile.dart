import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

enum TileTone { brand, danger, success }

class QuickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;
  final TileTone tone;

  const QuickTile({
    super.key,
    required this.icon,
    required this.label,
    required this.sub,
    required this.onTap,
    this.tone = TileTone.brand,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (iconBg, iconFg) = switch (tone) {
      TileTone.brand => (colors.brandSoft, colors.brand),
      TileTone.danger => (colors.dangerBg, colors.danger),
      TileTone.success => (colors.successBg, colors.success),
    };

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: colors.line),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconFg, size: 22),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colors.fg,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sub,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colors.fgMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
