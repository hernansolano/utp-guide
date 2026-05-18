import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class BottomNavWidget extends StatelessWidget {
  final String activeTab;
  final ValueChanged<String> onTabChanged;

  const BottomNavWidget({
    super.key,
    required this.activeTab,
    required this.onTabChanged,
  });

  static const _tabs = [
    _Tab('home', 'Inicio', Icons.home_outlined, Icons.home_rounded),
    _Tab('map', 'Mapa', Icons.map_outlined, Icons.map_rounded),
    _Tab('search', 'Buscar', Icons.search_rounded, Icons.search_rounded),
    _Tab('settings', 'Ajustes', Icons.settings_outlined, Icons.settings_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: _tabs.map((t) {
              final active = activeTab == t.id;
              return Expanded(
                child: InkWell(
                  onTap: () => onTabChanged(t.id),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        active ? t.activeIcon : t.icon,
                        size: 24,
                        color: active ? colors.brand : colors.fgSoft,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        t.label,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: active ? colors.brand : colors.fgSoft,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _Tab {
  final String id;
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _Tab(this.id, this.label, this.icon, this.activeIcon);
}
