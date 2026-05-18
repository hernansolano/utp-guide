import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/bottom_nav.dart';

class SettingsScreen extends StatelessWidget {
  final ValueNotifier<bool> darkModeNotifier;

  const SettingsScreen({super.key, required this.darkModeNotifier});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.bgSoft,
      body: Column(
        children: [
          _buildHeader(context, colors),
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: darkModeNotifier,
              builder: (context, isDark, _) => ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  _SettingsGroup(
                    label: 'Apariencia',
                    children: [
                      _SettingsRow(
                        icon: isDark
                            ? Icons.dark_mode_rounded
                            : Icons.light_mode_rounded,
                        title: 'Modo oscuro',
                        sub:
                            'Mejor para usar de noche o en interiores con poca luz.',
                        toggle: true,
                        value: isDark,
                        onToggle: () =>
                            darkModeNotifier.value = !darkModeNotifier.value,
                      ),
                    ],
                  ),
                  _SettingsGroup(
                    label: 'Accesibilidad',
                    children: [
                      _SettingsRow(
                        icon: Icons.accessible_rounded,
                        title: 'Solo rutas accesibles',
                        sub: 'Sin escaleras, con rampas y ascensor.',
                        toggle: true,
                        value: false,
                        onToggle: () {},
                        isLast: true,
                      ),
                      _SettingsRow(
                        icon: Icons.volume_up_rounded,
                        title: 'Indicaciones por voz',
                        sub: 'Lee el siguiente paso en voz alta.',
                        toggle: true,
                        value: false,
                        onToggle: () {},
                      ),
                      _SettingsRow(
                        icon: Icons.format_size_rounded,
                        title: 'Texto grande',
                        sub: 'Aumenta el tamaño en un 15 %.',
                        toggle: true,
                        value: false,
                        onToggle: () {},
                        isLast: true,
                      ),
                    ],
                  ),
                  _SettingsGroup(
                    label: 'Mapa',
                    children: [
                      _SettingsRow(
                        icon: Icons.map_outlined,
                        title: 'Mapa por defecto al abrir',
                        trailing: '2D',
                      ),
                      _SettingsRow(
                        icon: Icons.camera_alt_outlined,
                        title: 'AR automático con teléfono vertical',
                        sub: 'Cambia de modo según la orientación.',
                        toggle: true,
                        value: true,
                        onToggle: () {},
                        isLast: true,
                      ),
                    ],
                  ),
                  _SettingsGroup(
                    label: 'Acerca de',
                    children: [
                      _SettingsRow(
                        icon: Icons.info_outline_rounded,
                        title: 'Versión',
                        trailing: '0.1.0',
                      ),
                      _SettingsRow(
                        icon: Icons.school_outlined,
                        title: 'Una iniciativa de FISC · UTP',
                        sub: 'Universidad Tecnológica de Panamá',
                        isLast: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          BottomNavWidget(
            activeTab: 'settings',
            onTabChanged: (tab) {
              if (tab == 'home') context.go('/');
              if (tab == 'search') context.push('/search');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppColors colors) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 14, 20, 14),
      child: Row(
        children: [
          IconButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/'),
            icon: Icon(Icons.arrow_back_rounded, color: colors.fg),
            style: IconButton.styleFrom(
              backgroundColor: colors.bgSoft,
              shape: const CircleBorder(),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Ajustes',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.01 * 22,
              color: colors.fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final String label;
  final List<Widget> children;

  const _SettingsGroup({required this.label, required this.children});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 8),
            child: Text(
              label.toUpperCase(),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.06 * 11,
                color: colors.fgSoft,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? sub;
  final String? trailing;
  final bool toggle;
  final bool value;
  final VoidCallback? onToggle;
  final bool isLast;

  const _SettingsRow({
    required this.icon,
    required this.title,
    this.sub,
    this.trailing,
    this.toggle = false,
    this.value = false,
    this.onToggle,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.brandSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: colors.brand, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.fg,
                      ),
                    ),
                    if (sub != null)
                      Text(
                        sub!,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colors.fgMuted,
                          height: 1.4,
                        ),
                      ),
                  ],
                ),
              ),
              if (toggle)
                GestureDetector(
                  onTap: onToggle,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 46,
                    height: 28,
                    decoration: BoxDecoration(
                      color: value ? colors.brand : colors.lineStrong,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 200),
                      alignment:
                          value ? Alignment.centerRight : Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 3,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (!toggle && trailing != null)
                Text(
                  trailing!,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colors.fgMuted,
                  ),
                ),
            ],
          ),
        ),
        if (!isLast) Divider(height: 1, color: colors.line),
      ],
    );
  }
}
