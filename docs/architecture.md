# Arquitectura — UTP-Guide

## Visión general

UTP-Guide es una aplicación Flutter de navegación interior. La arquitectura sigue un patrón de capas con inyección por constructor, sin contenedor de DI (Provider/GetIt) en Fase 1 para minimizar la superficie de dependencias.

```
┌─────────────────────────────────────────────────────────────┐
│                          UI Layer                           │
│  Screens (HomeScreen, SearchScreen, MapaScreen, Settings)   │
│  Widgets:                                                   │
│   - MapView (+ MapViewController): cámara, pan, zoom, seguir │
│   - MinimapWidget (delegado a MapView en modo compacto)     │
│   - MapaPainter: pintura raw de ruta + dot (usado por MapView)│
│   - BottomNav, PillButton, QuickTile, DestinationRow, ...   │
└───────────────────────────┬─────────────────────────────────┘
                            │ consume vía constructor
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                       Service Layer                         │
│  RoutingService     (A*)                                    │
│  PositioningService (trilateración + filtros + snap)        │
│  TtsService         (text-to-speech en español)             │
│                                                             │
│  BleSource (interfaz)                                       │
│   ├─ BleService          (escaneo iBeacon real)             │
│   ├─ SimulatedBleService (lecturas sintéticas para testing) │
│   └─ BleSourceMultiplexer (conmuta entre las dos)           │
└───────────────────────────┬─────────────────────────────────┘
                            │ consume vía constructor
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    Repository Layer                         │
│  GrafoRepository      (assets/data/grafo.json)              │
│  BeaconRepository     (assets/data/beacon_config.json)      │
└─────────────────────────────────────────────────────────────┘
```

## Principios

### 1. Inversión de dependencias por constructor

Los servicios y repositorios se instancian una sola vez en `main.dart` como singletons de archivo, y se inyectan por constructor a quien los necesite. No hay framework de DI.

**Por qué:** El proyecto tiene 4 servicios y 2 repositorios. Un framework de DI agregaría complejidad sin beneficio. Cuando se llegue a una integración con telemetría remota o backend, se evaluará migrar a Provider o Riverpod.

### 1b. Abstracción `BleSource`

`PositioningService` consume `BleSource` (interfaz), no `BleService` concreto. Tres implementaciones coexisten:

- `BleService` — escaneo iBeacon real con `flutter_blue_plus`
- `SimulatedBleService` — genera lecturas sintéticas a partir de una posición virtual (drag-to-position), útil para testing sin hardware
- `BleSourceMultiplexer` — conmuta entre las dos según `modoSimulacionNotifier`

Esto permite alternar entre BLE real y simulado en runtime sin reiniciar el pipeline de posicionamiento. Ver [ADR-0008](adr/0008-simulador-ble-para-testing.md).

### 2. Datos de dominio en assets/, no en código

`grafo.json` y `beacon_config.json` viven en `assets/` y se cargan al iniciar. Esto permite:

- Calibrar parámetros sin recompilar la app
- Versionar los datos del mapa por separado del código
- Permitir a un futuro `GrafoEditor` modificar el grafo sin tocar Dart

**Regla:** ninguna coordenada de planta, distancia o parámetro de calibración debe vivir en código Dart. Si aparece, es un bug.

### Coherencia entre el SVG del mapa y `grafo.json`

Cada piso se modela con dos archivos que deben permanecer en sincronía:

- `assets/maps/<edificio>_<piso>.svg` — representación visual de paredes, puertas, etiquetas
- `assets/data/grafo.json` — nodos navegables, aristas, dimensiones del piso en metros

La relación es: `viewBox_ancho_px = mapa_ancho_metros × 100`. La escala es fija (100 px = 1 m) y está documentada en [`map-format.md`](map-format.md) y [`adr/0006-formato-mapa-svg-metrico.md`](adr/0006-formato-mapa-svg-metrico.md). El comando `dart tools/grafo_editor.dart validar-mapa` verifica la coherencia.

### 3. Streams sobre callbacks

Toda señal asíncrona (lecturas BLE, posición estimada, eventos del acelerómetro) se expone como `Stream<T>`. Los consumidores usan `StreamSubscription` y los cancelan en `dispose()`.

**Por qué:** los `Stream` componen bien (`map`, `where`, `debounce` con `rxdart`), son fáciles de testear con `StreamController` mock, y los `StreamSubscription` tienen un ciclo de vida claro.

### 4. Errores explícitos, no silenciosos

Cada excepción de dominio tiene su clase: `NodeNotFoundException`, `NoAccessibleRouteException`, `BeaconNotFoundException`. Los `catch (e) {}` vacíos están prohibidos por convención: como mínimo se deja un `debugPrint`.

**Excepción documentada:** `BleService.iniciarEscaneo()` falla silenciosamente si no hay permisos BLE — pero esto se compensa con el stream `BleService.estado` que informa el problema a la UI. Ver [ADR-0004](adr/0004-permisos-runtime.md).

## Flujo de datos: búsqueda → ruta → posicionamiento

```
Usuario en SearchScreen ──tap──▶ MapaScreen(destinoId)
                                       │
                                       ├─▶ RoutingService.calcularRuta()
                                       │       ├─ GrafoRepository.obtenerNodos()
                                       │       ├─ GrafoRepository.obtenerAristas()
                                       │       └─ A* con filtro de accesibilidad
                                       │              │
                                       │              ▼
                                       │       List<Nodo> ruta
                                       │
                                       ├─▶ PositioningService.iniciar()
                                       │       ├─ BleService.iniciarEscaneo()
                                       │       │       │
                                       │       │       ▼
                                       │       │   Stream<BeaconReading>
                                       │       │
                                       │       ├─ Media móvil por beacon (ventana 8)
                                       │       ├─ Distancia = 10^((txPower - rssi) / (10·n))
                                       │       ├─ Centroide ponderado (w = 1/d²)
                                       │       ├─ Limpieza de beacons obsoletos (>3s)
                                       │       └─ Snap-to-graph (proyección en arista)
                                       │              │
                                       │              ▼
                                       │       Stream<Position?>
                                       │
                                       └─▶ MapaPainter (CustomPainter)
                                               ├─ Ruta punteada (azul)
                                               ├─ Pin de destino (rojo con aura)
                                               └─ Punto de usuario (azul con borde blanco)
```

## Archivos protegidos

Estos archivos no se editan a mano sin revisar antes el impacto:

- `assets/data/grafo.json` — modificarlo vía `tools/grafo_editor.dart`
- `assets/data/beacon_config.json` — modificable directamente (no hay editor todavía)
- `lib/ui/theme/app_theme.dart` — design tokens, cambios requieren revisión de UX
- Los tests de `/test/`: no se cambian para que pasen; se arregla el código

## Plataformas soportadas

- **Android 6.0+ (API 23+)** — objetivo principal
- **iOS 13+** — soporte secundario (BLE scanning entre dispositivos iOS tiene restricciones de Core Bluetooth)
- Otras plataformas (Linux, macOS, Web, Windows) compilan pero no son relevantes para el caso de uso
