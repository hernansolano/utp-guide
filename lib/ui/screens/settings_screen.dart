import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_config.dart';
import '../theme/app_theme.dart';
import '../widgets/bottom_nav.dart';

/// Pantalla de ajustes.
///
/// Recibe todos los `ValueNotifier<bool>` globales por constructor. Cada
/// toggle de la lista está atado a uno de estos notifiers, y el cambio
/// se propaga a toda la app vía rebuild reactivo. Para agregar un
/// setting nuevo: crear el notifier en `main.dart`, pasarlo aquí por
/// constructor, agregar un `_SettingsRow` con `value:` y `onToggle:`
/// apuntando al notifier.
class SettingsScreen extends StatelessWidget {
  final ValueNotifier<bool> darkModeNotifier;
  final ValueNotifier<bool> accesibleSoloRutasNotifier;
  final ValueNotifier<bool> vozHabilitadaNotifier;
  final ValueNotifier<bool> textoGrandeNotifier;
  final ValueNotifier<bool> arAutomaticoNotifier;
  final ValueNotifier<bool> debugOverlayNotifier;
  final ValueNotifier<bool> modoSimulacionNotifier;
  final ValueNotifier<bool> snapHabilitadoNotifier;
  final ValueNotifier<bool> trazaActivaNotifier;

  const SettingsScreen({
    super.key,
    required this.darkModeNotifier,
    required this.accesibleSoloRutasNotifier,
    required this.vozHabilitadaNotifier,
    required this.textoGrandeNotifier,
    required this.arAutomaticoNotifier,
    required this.debugOverlayNotifier,
    required this.modoSimulacionNotifier,
    required this.snapHabilitadoNotifier,
    required this.trazaActivaNotifier,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Listenable.merge nos permite reconstruir la lista entera cuando
    // cualquier notifier cambia, sin anidar ValueListenableBuilders.
    return Scaffold(
      backgroundColor: colors.bgSoft,
      body: Column(
        children: [
          _buildHeader(context, colors),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge([
                darkModeNotifier,
                accesibleSoloRutasNotifier,
                vozHabilitadaNotifier,
                textoGrandeNotifier,
                arAutomaticoNotifier,
                debugOverlayNotifier,
                modoSimulacionNotifier,
                snapHabilitadoNotifier,
                trazaActivaNotifier,
              ]),
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  _SettingsGroup(
                    label: 'Apariencia',
                    children: [
                      _SettingsRow(
                        icon: darkModeNotifier.value
                            ? Icons.dark_mode_rounded
                            : Icons.light_mode_rounded,
                        title: 'Modo oscuro',
                        sub:
                            'Mejor para usar de noche o en interiores con poca luz.',
                        toggle: true,
                        value: darkModeNotifier.value,
                        onToggle: () =>
                            darkModeNotifier.value = !darkModeNotifier.value,
                        isLast: true,
                      ),
                      _SettingsRow(
                        icon: Icons.format_size_rounded,
                        title: 'Texto grande',
                        sub: 'Aumenta el tamaño en un 15 %.',
                        toggle: true,
                        value: textoGrandeNotifier.value,
                        onToggle: () => textoGrandeNotifier.value =
                            !textoGrandeNotifier.value,
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
                        value: accesibleSoloRutasNotifier.value,
                        onToggle: () => accesibleSoloRutasNotifier.value =
                            !accesibleSoloRutasNotifier.value,
                        isLast: true,
                      ),
                      _SettingsRow(
                        icon: Icons.volume_up_rounded,
                        title: 'Indicaciones por voz',
                        sub: 'Lee el siguiente paso en voz alta.',
                        toggle: true,
                        value: vozHabilitadaNotifier.value,
                        onToggle: () => vozHabilitadaNotifier.value =
                            !vozHabilitadaNotifier.value,
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
                        isLast: !kArHabilitado,
                      ),
                      // AR desactivada (ver app_config.dart). El toggle se
                      // oculta; el código se conserva para reactivarla.
                      if (kArHabilitado)
                        _SettingsRow(
                          icon: Icons.camera_alt_outlined,
                          title: 'AR automático con teléfono vertical',
                          sub: 'Cambia de modo según la orientación.',
                          toggle: true,
                          value: arAutomaticoNotifier.value,
                          onToggle: () => arAutomaticoNotifier.value =
                              !arAutomaticoNotifier.value,
                          isLast: true,
                        ),
                    ],
                  ),
                  // Sección "Desarrollador" solo visible en builds de debug.
                  // En release, los usuarios nunca ven estos toggles.
                  if (kDebugMode)
                    _SettingsGroup(
                      label: 'Desarrollador',
                      children: [
                        _SettingsRow(
                          icon: Icons.science_outlined,
                          title: 'Modo simulación',
                          sub:
                              'Genera lecturas BLE sintéticas desde el dedo sobre el mapa, '
                              'sin necesidad de balizas reales.',
                          toggle: true,
                          value: modoSimulacionNotifier.value,
                          onToggle: () => modoSimulacionNotifier.value =
                              !modoSimulacionNotifier.value,
                        ),
                        _SettingsRow(
                          icon: Icons.bug_report_outlined,
                          title: 'Mostrar overlay de debug',
                          sub:
                              'Métricas en vivo de BLE y posicionamiento sobre el mapa.',
                          toggle: true,
                          value: debugOverlayNotifier.value,
                          onToggle: () => debugOverlayNotifier.value =
                              !debugOverlayNotifier.value,
                        ),
                        _SettingsRow(
                          icon: Icons.alt_route_rounded,
                          title: 'Snap-to-graph',
                          sub:
                              'Si está OFF, el punto azul muestra la '
                              'posición cruda del centroide sin pegarse '
                              'a los pasillos del grafo.',
                          toggle: true,
                          value: snapHabilitadoNotifier.value,
                          onToggle: () => snapHabilitadoNotifier.value =
                              !snapHabilitadoNotifier.value,
                        ),
                        _SettingsRow(
                          icon: Icons.gesture_rounded,
                          title: 'Capturar traza',
                          sub:
                              'Dibuja una polilínea ámbar con todas las '
                              'posiciones que el sistema marca mientras '
                              'esté activo.',
                          toggle: true,
                          value: trazaActivaNotifier.value,
                          onToggle: () => trazaActivaNotifier.value =
                              !trazaActivaNotifier.value,
                        ),
                        _SettingsRow(
                          icon: Icons.tune_rounded,
                          title: 'Calibración BLE (campo)',
                          sub:
                              'Ver lecturas en vivo, ajustar n y txPower, '
                              'exportar muestras como CSV.',
                          onTap: () => context.push('/calibracion'),
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
              if (tab == 'map') context.push('/explorar');
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
        20,
        MediaQuery.of(context).padding.top + 14,
        20,
        14,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.canPop() ? context.pop() : context.go('/'),
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
  final VoidCallback? onTap;
  final bool isLast;

  const _SettingsRow({
    required this.icon,
    required this.title,
    this.sub,
    this.trailing,
    this.toggle = false,
    this.value = false,
    this.onToggle,
    this.onTap,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fila = Column(
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
                      alignment: value
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
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
              if (!toggle && trailing == null && onTap != null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.fgSoft,
                  size: 20,
                ),
            ],
          ),
        ),
        if (!isLast) Divider(height: 1, color: colors.line),
      ],
    );

    // Si la fila es navegable (tiene onTap pero no es un toggle), la
    // envolvemos en InkWell para el feedback de tap.
    if (onTap != null && !toggle) {
      return InkWell(onTap: onTap, child: fila);
    }
    return fila;
  }
}
