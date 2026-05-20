# Arquitectura — UTP-Guide

## Visión general

UTP-Guide es una aplicación Flutter de navegación interior. La arquitectura sigue un patrón de capas con inyección por constructor, sin contenedor de DI (Provider/GetIt) en Fase 1 para minimizar la superficie de dependencias.

```
┌─────────────────────────────────────────────────────────────┐
│                          UI Layer                           │
│  Screens (HomeScreen, SearchScreen, MapaScreen, Settings)   │
│  Widgets (MapaPainter, BottomNav, PillButton, etc.)         │
└───────────────────────────┬─────────────────────────────────┘
                            │ consume vía constructor
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                       Service Layer                         │
│  RoutingService (A*)                                        │
│  BleService (escaneo iBeacon)                               │
│  PositioningService (trilateración + filtros + snap)        │
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

**Por qué:** En Fase 1 el proyecto tiene 3 servicios y 2 repositorios. Un framework de DI agregaría complejidad sin beneficio. Cuando se llegue a Fase 4 con TTS, sensores adicionales y servicios de telemetría, se evaluará migrar a Provider o Riverpod (ver [ADR-0004](adr/0004-permisos-runtime.md) para precedente similar).

### 2. Datos de dominio en assets/, no en código

`grafo.json` y `beacon_config.json` viven en `assets/` y se cargan al iniciar. Esto permite:

- Calibrar parámetros sin recompilar la app
- Versionar los datos del mapa por separado del código
- Permitir a un futuro `GrafoEditor` modificar el grafo sin tocar Dart

**Regla:** ninguna coordenada de planta, distancia o parámetro de calibración debe vivir en código Dart. Si aparece, es un bug.

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
