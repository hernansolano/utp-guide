# Plan — Quitar el beacon simulado (`SimulatedBleService`) de la app

Estado: **pendiente** (acordado para hacerlo más adelante). El simulador ya no aporta
valor (las pruebas se hacen con balizas/emisores reales). Supera el ADR-0008.

## Se borran (100% simulador)
- `lib/services/simulated_ble_service.dart`
- `lib/services/ble_source_multiplexer.dart`

## Se reconfiguran (sin romper)
- **`lib/main.dart`**: `_bleSource = _bleServiceReal` directo; quitar `_bleServiceSimulado`,
  `modoSimulacionNotifier`, `posicionVirtualNotifier`, los 2 imports, y esos notifiers de
  las llamadas a `MapaScreen` / `ExplorarScreen` / `SettingsScreen`. Ajustar el comentario
  del `configurarUuidObjetivo` (ya no hay multiplexer).
- **`lib/ui/screens/mapa_screen.dart`**: quitar `posicionVirtualNotifier`, el callback de
  *drag-to-position* y los chequeos `BleEstado.simulando`.
- **`lib/ui/screens/explorar_screen.dart`**: quitar `posicionVirtualNotifier` y los
  `BleEstado.simulando`.
- **`lib/ui/widgets/map_view.dart`**: quitar el modo *drag* (cruz roja, `posicionTarget`,
  `panZoomHabilitado`); el pan/zoom queda siempre activo. Ajustar los call-sites.
- **`lib/ui/screens/settings_screen.dart`**: quitar el toggle "Modo simulación".
- **`lib/ui/screens/calibracion_screen.dart`**: quitar el caso/mensajes de `simulando`.
- **`lib/services/ble_service.dart`**: quitar `BleEstado.simulando` del enum.
- **`lib/services/ble_source.dart`**: se **queda** la interfaz (la implementa `BleService`,
  la consume `PositioningService`); solo limpiar comentarios que mencionan el simulador.

## No se toca / no se rompe
`BleService`, `IbeaconCoreLocationService`, `PositioningService`, ruteo, calibración,
traza, Modo Investigador. La interfaz `BleSource` se mantiene (ahora con una sola
implementación real → `PositioningService` no cambia).

## Docs
- Actualizar `docs/architecture.md` (stack de servicios + estructura de carpetas).
- Marcar `docs/adr/0008-simulador-ble-para-testing.md` como **superado** (no borrar).

## Verificación
`flutter analyze` limpio + `flutter run` rápido (entrar a mapa y explorar, confirmar que
pan/zoom y el punto azul real siguen bien).
