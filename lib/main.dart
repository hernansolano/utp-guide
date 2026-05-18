import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'data/repositories/beacon_repository.dart';
import 'data/repositories/grafo_repository.dart';
import 'models/perfil_movilidad.dart';
import 'services/ble_service.dart';
import 'services/positioning_service.dart';
import 'services/routing_service.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/mapa_screen.dart';
import 'ui/screens/search_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/theme/app_theme.dart';

// ─── Servicios globales (singleton por app) ───────────────────────────────────
final _grafoRepository   = GrafoRepository();
final _beaconRepository  = BeaconRepository();
final _routingService    = RoutingService(_grafoRepository);
final _bleService        = BleService();
final _positioningService = PositioningService(
  _bleService,
  _beaconRepository,
  _grafoRepository,
);

// ─── Dark mode: ValueNotifier global, persist-able en Fase 4 ─────────────────
final darkModeNotifier = ValueNotifier<bool>(false);

// ─── Router ───────────────────────────────────────────────────────────────────
final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => HomeScreen(grafoRepository: _grafoRepository),
    ),
    GoRoute(
      path: '/search',
      builder: (_, _) => SearchScreen(grafoRepository: _grafoRepository),
    ),
    GoRoute(
      path: '/mapa',
      builder: (_, state) {
        final extra = state.extra as Map<String, dynamic>;
        return MapaScreen(
          destinoId: extra['destinoId'] as String,
          perfil: PerfilMovilidad.values.byName(extra['perfil'] as String),
          routingService: _routingService,
          positioningService: _positioningService,
        );
      },
    ),
    GoRoute(
      path: '/settings',
      builder: (_, _) => SettingsScreen(darkModeNotifier: darkModeNotifier),
    ),
  ],
);

// ─── App ──────────────────────────────────────────────────────────────────────
void main() {
  runApp(const UtpGuideApp());
}

class UtpGuideApp extends StatelessWidget {
  const UtpGuideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: darkModeNotifier,
      builder: (_, isDark, _) => MaterialApp.router(
        title: 'UTP Guide',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
        routerConfig: _router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
