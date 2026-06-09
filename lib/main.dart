import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'data/repositories/beacon_repository.dart';
import 'data/repositories/grafo_repository.dart';
import 'models/beacon_config.dart';
import 'models/perfil_movilidad.dart';
import 'models/position.dart';
import 'models/tipo_nodo.dart';
import 'services/ble_service.dart';
import 'services/ble_source.dart';
import 'services/ble_source_multiplexer.dart';
import 'services/ibeacon_core_location_service.dart';
import 'services/positioning_service.dart';
import 'services/routing_service.dart';
import 'services/simulated_ble_service.dart';
import 'services/traza_service.dart';
import 'services/tts_service.dart';
import 'ui/screens/calibracion_screen.dart';
import 'ui/screens/explorar_screen.dart';
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

/// Si false, `PositioningService` no aplica snap-to-graph y emite la
/// posición cruda del centroide ponderado. Útil para calibrar: ver el
/// dot saltando "donde el sistema cree" sin que las aristas del grafo
/// lo enmascaren. Default true (snap activo, comportamiento normal).
final snapHabilitadoNotifier        = ValueNotifier<bool>(true);

/// Cuando true, [TrazaService] acumula cada posición emitida en una
/// polilínea visible sobre el mapa. Útil para ver el trayecto que el
/// sistema marca mientras te movés, y compararlo con la realidad.
final trazaActivaNotifier           = ValueNotifier<bool>(false);

/// Si true, el sistema usa el simulador BLE en lugar del escaneo real.
final modoSimulacionNotifier        = ValueNotifier<bool>(false);

/// Posición virtual del usuario en modo simulación.
final posicionVirtualNotifier       = ValueNotifier<Position?>(null);

/// Calibración activa del sistema de posicionamiento.
///
/// Se inicializa con los valores de `beacon_config.json` al arrancar la
/// app y se puede modificar en runtime desde `CalibracionScreen`. El
/// `PositioningService` escucha este notifier y aplica los cambios
/// inmediatamente a las próximas lecturas. Ver
/// `docs/adr/0011-calibracion-en-campo.md`.
final calibracionNotifier =
    ValueNotifier<CalibracionPositioning>(CalibracionPositioning.defaults);

// ─── Servicios de posicionamiento ────────────────────────────────────────────

/// Fuente real de iBeacons. Elegida según plataforma:
/// - **iOS** → [IbeaconCoreLocationService] (Core Location). Apple
///   bloquea iBeacons en Core Bluetooth; flutter_blue_plus no los ve
///   en iPhone. Core Location es la única vía soportada.
/// - **Android** → [BleService] (flutter_blue_plus). Detecta iBeacons
///   sin problemas y nos da el stream crudo de advertisements para el
///   diagnóstico de la pantalla de calibración.
final BleSource _bleServiceReal = Platform.isIOS
    ? IbeaconCoreLocationService()
    : BleService();
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
  calibracionNotifier,
  snapHabilitadoListenable: snapHabilitadoNotifier,
);
final _ttsService         = TtsService();
final _trazaService       = TrazaService(_positioningService, trazaActivaNotifier);

// ─── Router ───────────────────────────────────────────────────────────────────
final _router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => HomeScreen(grafoRepository: _grafoRepository),
    ),
    GoRoute(
      path: '/search',
      builder: (_, state) {
        // Filtro inicial opcional: HomeScreen lo manda desde sus quick
        // tiles (ej: tap en "Salones" → tipoFiltro = TipoNodo.salon).
        final extra = state.extra as Map<String, dynamic>?;
        final tipoFiltro = extra?['tipoFiltro'] as TipoNodo?;
        return SearchScreen(
          grafoRepository: _grafoRepository,
          accesibleSoloRutasNotifier: accesibleSoloRutasNotifier,
          tipoFiltroInicial: tipoFiltro,
        );
      },
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
          trazaService: _trazaService,
          arAutomaticoNotifier: arAutomaticoNotifier,
          debugOverlayNotifier: debugOverlayNotifier,
          modoSimulacionNotifier: modoSimulacionNotifier,
          posicionVirtualNotifier: posicionVirtualNotifier,
          vozHabilitadaNotifier: vozHabilitadaNotifier,
        );
      },
    ),
    GoRoute(
      path: '/explorar',
      builder: (_, _) => ExplorarScreen(
        grafoRepository: _grafoRepository,
        positioningService: _positioningService,
        trazaService: _trazaService,
        accesibleSoloRutasNotifier: accesibleSoloRutasNotifier,
        modoSimulacionNotifier: modoSimulacionNotifier,
        posicionVirtualNotifier: posicionVirtualNotifier,
      ),
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
        snapHabilitadoNotifier: snapHabilitadoNotifier,
        trazaActivaNotifier: trazaActivaNotifier,
      ),
    ),
    GoRoute(
      path: '/calibracion',
      builder: (_, _) => CalibracionScreen(
        positioningService: _positioningService,
        beaconRepository: _beaconRepository,
        grafoRepository: _grafoRepository,
        calibracionNotifier: calibracionNotifier,
        trazaService: _trazaService,
        snapHabilitadoNotifier: snapHabilitadoNotifier,
        trazaActivaNotifier: trazaActivaNotifier,
      ),
    ),
  ],
);

// ─── App ──────────────────────────────────────────────────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Cargar calibración + UUID desde beacon_config.json antes de levantar
  // la UI. Si falla, los defaults aplican y el BleService usa el UUID
  // histórico hardcoded.
  try {
    calibracionNotifier.value = await _beaconRepository.obtenerCalibracion();
    final uuid = await _beaconRepository.obtenerUuid();
    // El multiplexer propaga al real (BleService o IbeaconCoreLocation)
    // y al simulado (no-op). No requiere cast por plataforma.
    _bleSource.configurarUuidObjetivo(uuid);
  } catch (_) {
    // Defaults ya están seteados — log opcional aquí en el futuro.
  }
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
