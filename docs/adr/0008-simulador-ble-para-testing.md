# ADR-0008 — Simulador BLE para testing sin hardware

- **Estado:** aceptado
- **Fecha:** 2026-05-20
- **Autor:** equipo UTP-Guide

## Contexto

El sistema de posicionamiento BLE requiere balizas físicas instaladas en el edificio para funcionar. Antes de la Fase 2 (despliegue de Minew E2 Max en FISC), el equipo necesita poder:

1. Iterar sobre la lógica del `PositioningService` (path-loss, media móvil, centroide ponderado, snap-to-graph) sin esperar a que lleguen las balizas
2. Reproducir condiciones de prueba específicas (ej: "qué pasa si el usuario está exactamente sobre un beacon", "qué pasa si solo un beacon es visible")
3. Verificar visualmente que el dot azul responde correctamente al movimiento

La opción cómoda de usar la app de iOS "Beacon Simulator" tiene un límite fundamental: simula transmisión desde **una sola posición física** (la del dispositivo iOS). Para probar trilateración con tres balizas en posiciones distintas se necesitarían tres iPhones, lo cual no es realista.

## Opciones consideradas

### Opción A — Continuar usando Beacon Simulator iOS

Esperar hasta tener varios dispositivos o las balizas físicas reales.

- **Pros:** trabajo cero
- **Contras:** bloquea toda iteración sobre el pipeline de posicionamiento durante semanas/meses

### Opción B — Mocks de unit testing

Usar `Stream<BeaconReading>` falsos en tests unitarios.

- **Pros:** valida lógica en aislamiento
- **Contras:** no permite ver el resultado visualmente en la app real; no ayuda con iteración de UX

### Opción C — Servicio simulador integrado en la app

Implementar un `SimulatedBleService` que generate lecturas sintéticas a partir de una "posición virtual" del usuario. La UI permite arrastrar el dedo sobre el mapa para mover esa posición virtual, y el simulador calcula qué RSSI debería medir cada baliza si el usuario estuviera realmente ahí.

- **Pros:** testing end-to-end visual sin hardware; reproducible; cambiar entre simulado y real es un toggle
- **Contras:** código adicional que debe mantenerse; riesgo de divergencia entre el simulador y la física real

## Decisión

Implementar la **opción C**.

### Arquitectura

```
                              ┌──────────────────┐
                              │ PositioningService│
                              └────────▲─────────┘
                                       │ consume
                              ┌────────┴─────────┐
                              │   BleSource      │ ← interfaz
                              └────────▲─────────┘
                                       │
                  ┌────────────────────┼────────────────────┐
                  │                    │                    │
        ┌─────────┴────────┐  ┌────────┴────────┐  ┌────────┴──────────┐
        │ BleSource        │  │   BleService    │  │ SimulatedBleService│
        │ Multiplexer      │  │   (real, FBP)   │  │   (sintético)      │
        └──────────────────┘  └─────────────────┘  └────────────────────┘
              ▲                                              ▲
              │ alterna según modoSimulacionNotifier         │
              │                                              │ lee
              └──────────────────────────────────────────────┘
                                  posicionVirtualNotifier
                                              ▲
                                              │ actualiza
                                  ┌───────────┴───────────┐
                                  │ MapaScreen drag-to-pos│
                                  └───────────────────────┘
```

### Modelo físico del simulador

Para cada baliza registrada en `beacon_config.json`, cada ciclo (500 ms):

1. Calcula distancia euclidiana `d = sqrt((x_user − x_beacon)² + (y_user − y_beacon)²)` desde la posición virtual
2. Aplica el **inverso del modelo de path-loss**:
   `rssi = txPower − 10·n·log10(d)`
3. Agrega ruido gaussiano con σ = 3 dBm para imitar la variación natural del RSSI en BLE
4. Emite la lectura como `BeaconReading` al stream

El pipeline downstream (PositioningService) recibe estas lecturas igual que las reales. Si el modelo de path-loss del simulador coincide con el del PositioningService (mismo `txPower`, mismo `n`), el punto calculado debería estar muy cerca de la posición virtual — con la diferencia atribuible al ruido y al snap-to-graph. Esto es **deliberadamente útil**: si el algoritmo está calibrado, el dot calculado sigue al target. Si el algoritmo está mal, la diferencia revela el bug.

### Indicador visual

Cuando el modo simulación está activo, una **cruz roja** aparece en el mapa donde el usuario tocó/arrastró por última vez. El **dot azul** sigue siendo lo que reporta el PositioningService. Comparar visualmente cruz roja vs dot azul es la forma rápida de evaluar la precisión.

### Toggle de activación

El toggle "Modo simulación" vive en la sección "Desarrollador" de SettingsScreen, **visible solo en builds de debug** (`kDebugMode`). En release la sección entera está oculta y el simulador es inalcanzable desde la UI.

## Consecuencias

### Positivas

- **Desbloquea iteración del pipeline de posicionamiento** sin esperar hardware
- **Reproducibilidad:** mover el dedo a una posición exacta, ver el resultado, repetir
- **Casos de borde testeables:** posición sobre un beacon, posición fuera del grafo, transición entre zonas
- **Útil para demos sin hardware**, ej: pitch de Erasmus+ donde explicar el sistema
- **El switch real ↔ simulado es transparente para PositioningService** — el día que lleguen los beacons, solo se apaga el toggle

### Negativas

- **Más código que mantener** (~250 líneas nuevas entre los 3 archivos)
- **Riesgo de "calibrar contra el simulador"** — si σ del simulador no refleja el ruido real, los parámetros que funcionan en simulación pueden no funcionar en campo
- **El modelo del simulador es exactamente el mismo modelo del PositioningService** — esto no valida el modelo, solo valida la implementación del pipeline alrededor del modelo

### Mitigaciones

- σ del ruido (3 dBm default) es configurable en el constructor; se puede ajustar cuando lleguen mediciones reales del FISC
- La calibración final de `n` y `txPower` se hará en campo con balizas reales (procedimiento documentado en `docs/setup-beacons.md`). El simulador sirve para desarrollo, no para certificación.
- El simulador y el modelo del PositioningService viven en módulos separados; si en el futuro queremos un simulador independiente para tests (ej: usando una distribución empírica de RSSI medida en campo) la abstracción `BleSource` lo permite sin refactorizar el resto.

## Referencias

- [`docs/positioning-ble.md`](../positioning-ble.md) — modelo físico que el simulador implementa al inverso
- [ADR-0001](0001-centroide-ponderado.md) — algoritmo de trilateración que se valida con el simulador
- [ADR-0002](0002-parametros-path-loss.md) — parámetros `n` y `txPower` que el simulador comparte con el PositioningService
- Box-Muller transform for Gaussian noise: Knuth, *The Art of Computer Programming*, Vol. 2 §3.4.1
