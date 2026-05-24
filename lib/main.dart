import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'data/repositories/beacon_repository.dart';
import 'data/repositories/grafo_repository.dart';
import 'models/perfil_movilidad.dart';
import 'models/position.dart';
import 'services/ble_service.dart';
import 'services/ble_source_multiplexer.dart';
import 'services/positioning_service.dart';
import 'services/routing_service.dart';
import 'services/simulated_ble_service.dart';
import 'services/tts_service.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/mapa_screen.dart';
import 'ui/screens/search_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/theme/app_theme.dart';

// ─── Repositorios (singleton por app) ─────────────────────────────────────────
final _grafoRepository  = GrafoRepository();
final _beaconRepository = BeaconRepository();

// ─── Preferencias globales (ValueNotifier<bool>) ──────────────────────────────
// Cada toggle de SettingsScreen está atado a uno de estos notifiers. En
// Fase 4 se persistirán a disco; por ahora son in-memory.

final darkModeNotifier              = ValueNotifier<bool>(false);
final accesibleSoloRutasNotifier    = ValueNotifier<bool>(false);
final vozHabilitadaNotifier         = ValueNotifier<bool>(false);
final textoGrandeNotifier           = ValueNotifier<bool>(false);
final arAutomaticoNotifier          = ValueNotifier<bool>(true);
final debugOverlayNotifier          = ValueNotifier<bool>(kDebugMode);

/// Si true, el sistema usa el simulador BLE en lugar del escaneo real.
/// Solo visible en builds de debug. Ver
/// `docs/adr/0008-simulador-ble-para-testing.md`.
final modoSimulacionNotifier        = ValueNotifier<bool>(false);

/// Posición virtual del usuario en modo simulación. Se actualiza desde
/// MapaScreen via drag-to-position. SimulatedBleService la lee cada
/// ciclo para generar lecturas sintéticas como si el usuario estuviera
/// realmente ahí.
final posicionVirtualNotifier       = ValueNotifier<Position?>(null);

// ─── Servicios de posicionamiento ────────────────────────────────────────────
//
// El BleService real y el SimulatedBleService viven simultáneamente; el
// BleSourceMultiplexer reenvía al que esté activo según
// modoSimulacionNotifier. PositioningService consume solo la abstracción
// BleSource y no sabe (ni le importa) si los datos son reales o sintéticos.

final _bleServiceReal     = BleService();
final _bleServiceSimulado = SimulatedBleService(
  _beaconRepository,
  posicionVirtualNotifier,
);
final _bleSource = BleSourceMultiplexer(
  _bleServiceReal,
  _bleServiceSimulado,
  modoSimulacionNotifier,
);

final _routingService     = RoutingService(_grafoRepository);
final _positioningService = PositioningService(
  _bleSource,
  _beaconRepository,
  _grafoRepository,
);
final _ttsService         = TtsService();

// ─── Router ───────────────────────────────────────────────────────────────────
final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => HomeScreen(grafoRepository: _grafoRepository),
    ),
    GoRoute(
      path: '/search',
      builder: (_, _) => SearchScreen(
        grafoRepository: _grafoRepository,
        accesibleSoloRutasNotifier: accesibleSoloRutasNotifier,
      ),
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
          grafoRepository: _grafoRepository,
          ttsService: _ttsService,
          arAutomaticoNotifier: arAutomaticoNotifier,
          debugOverlayNotifier: debugOverlayNotifier,
          modoSimulacionNotifier: modoSimulacionNotifier,
          posicionVirtualNotifier: posicionVirtualNotifier,
          vozHabilitadaNotifier: vozHabilitadaNotifier,
        );
      },
    ),
    GoRoute(
      path: '/settings',
      builder: (_, _) => SettingsScreen(
        darkModeNotifier: darkModeNotifier,
        accesibleSoloRutasNotifier: accesibleSoloRutasNotifier,
        vozHabilitadaNotifier: vozHabilitadaNotifier,
        textoGrandeNotifier: textoGrandeNotifier,
        arAutomaticoNotifier: arAutomaticoNotifier,
        debugOverlayNotifier: debugOverlayNotifier,
        modoSimulacionNotifier: modoSimulacionNotifier,
      ),
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
    return ListenableBuilder(
      listenable: Listenable.merge([darkModeNotifier, textoGrandeNotifier]),
      builder: (_, _) => MaterialApp.router(
        title: 'UTP Guide',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: darkModeNotifier.value ? ThemeMode.dark : ThemeMode.light,
        routerConfig: _router,
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
                textoGrandeNotifier.value ? 1.15 : 1.0),
          ),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
