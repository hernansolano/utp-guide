# ADR-0011 — Pantalla de calibración en campo con ajustes en vivo

- **Estado:** aceptado
- **Fecha:** 2026-05-27
- **Autor:** equipo UTP-Guide

## Contexto

El modelo de path-loss del `PositioningService` tiene parámetros sensibles al entorno físico:

- `n` (exponente de pérdida): depende de muros, mobiliario, presencia de gente
- `txPower` por baliza: depende de fabricación, orientación, materiales cercanos
- `ventana_media_movil`: balance suavizado vs lag
- `tolerancia_snap_metros`: depende del ancho de los pasillos

[ADR-0002](0002-parametros-path-loss.md) eligió defaults razonables para "edificio de concreto" (`n=3.5`, `txPower=-65 dBm`, `ventana=8`, `snap=3.0 m`). En la práctica, estos valores tienen que ajustarse para cada edificio específico — el FISC tiene su propia firma de propagación que solo se conoce midiendo.

El procedimiento de calibración en `docs/setup-beacons.md` (secciones 5–6) describe el método teórico: medir RSSI a distancias conocidas, despejar `n` con la ecuación de path-loss. Pero ese procedimiento requiere:

1. Salir al campo con celular en mano
2. Leer un display de debug improvisado
3. Anotar valores en un cuaderno
4. Volver al escritorio
5. Editar `beacon_config.json`
6. Recompilar y rebootear el app
7. Volver al campo a verificar
8. Repetir varias veces

Iterar así cuesta horas por cada ronda. Y el overlay actual de debug (~debugOverlay) muestra solo la última lectura, sin estadísticas acumuladas, sin sugerencias automáticas, sin facilidad para exportar datos.

## Decisión

Implementar una pantalla dedicada `/calibracion` accesible desde Ajustes → sección Desarrollador (solo `kDebugMode`), con tres capacidades:

### 1. Estadísticas acumuladas en vivo

Mientras la pantalla está abierta, se acumula un `BeaconStats` por baliza con:

- Lista completa de RSSI samples y distancias calculadas
- Media, desviación estándar, min y max del RSSI
- Distancia promedio calculada con la calibración vigente
- Edad de la última lectura

Esto permite al usuario quedarse parado a una distancia conocida durante 30-60 segundos para acumular 100+ muestras y tener stats estables, mucho mejor que mirar una lectura instantánea.

### 2. Herramienta "Distancia conocida"

El usuario selecciona una baliza, ingresa la distancia real en metros, y la app calcula automáticamente:

- RSSI medio actual y desviación
- Distancia que la app calcula con la calibración vigente
- Error (la diferencia entre lo que la app cree y la realidad)
- `n` sugerido si el usuario quiere ajustar solo ese parámetro:
  `n = (txPower - rssi_medio) / (10 · log10(distancia_real))`
- `txPower` sugerido para esa baliza específica si prefiere ajustar solo eso:
  `txPower = rssi_medio + 10 · n · log10(distancia_real)`

La elección entre ajustar `n` (afecta todas las balizas) o `txPower` (afecta solo una) queda explícita en la UI.

### 3. Sliders en vivo

Tres sliders modifican los parámetros del modelo en runtime:

- `n` (rango 2.0–5.0, 60 divisions)
- `ventana_media_movil` (1–20 lecturas)
- `tolerancia_snap_metros` (0.5–10.0 m)

El usuario camina mientras mueve los sliders y observa el efecto sobre el dot azul (en otra pantalla o ventana mental). Cuando los valores se sienten bien, los copia al `beacon_config.json` con el botón "Copiar bloque" (genera JSON listo para pegar).

### 4. Export CSV al portapapeles

Botón que copia un CSV con minor, descripción, samples, rssi_actual, rssi_mean, rssi_std, rssi_min, rssi_max, dist_mean_m. Pegable en Sheets/Excel para análisis offline.

## Arquitectura

### Calibración como `ValueNotifier<CalibracionPositioning>`

Antes: `PositioningService` cacheaba la calibración en `iniciar()`. Cambiar valores requería re-iniciar el servicio.

Ahora: `main.dart` expone `calibracionNotifier`, inicializado en `main()` async desde `BeaconRepository.obtenerCalibracion()` antes de `runApp`. El `PositioningService` recibe ese `ValueListenable` en su constructor y escucha cambios. Los `_procesarLectura` posteriores usan el valor actual del notifier.

`CalibracionScreen` modifica el notifier vía `widget.calibracionNotifier.value = nueva` cada vez que un slider se mueve. El cambio se propaga al `PositioningService` instantáneamente.

### Ventana de media móvil mutable

`_BeaconState.ventanaMax` ahora es mutable. Cuando `_procesarLectura` recibe una nueva lectura, llama `state.ajustarVentanaMax(nuevoMax)` antes de agregarla. Si la ventana se achicó, las muestras viejas se descartan. Si se agrandó, se rellena naturalmente con las próximas lecturas.

### Ref counting en `PositioningService`

`MapaScreen` ya llamaba `iniciar()` en initState y `detener()` en dispose. Ahora `CalibracionScreen` hace lo mismo. Si el usuario está en `/mapa` y abre `/calibracion`, ambos consumidores quieren el servicio activo. Si `detener` en `CalibracionScreen` realmente apagaba el servicio, `/mapa` perdería data.

Solución: `iniciar()` y `detener()` mantienen un contador `_refCount`. La inicialización real ocurre solo en `_refCount: 0→1`, y el shutdown real solo en `1→0`. Pares iniciar/detener intermedios son no-ops.

`dispose()` fuerza shutdown ignorando el contador, para limpieza definitiva al cerrar el app.

### Stream crudo expuesto

`PositioningService` ahora expone `Stream<BeaconReading> get beaconStreamRaw` que reenvía las lecturas del `BleSource` sin procesamiento. La `CalibracionScreen` lo consume para calcular sus propias stats (con sus propios txPower/n configurables), independientes del cálculo interno del servicio.

## Alternativas consideradas

### Editar `beacon_config.json` desde la app

Posible con `path_provider` + escribir a almacenamiento persistente, pero los assets de Flutter son read-only en runtime. Habría que copiar el archivo a documents en primer boot y leer de ahí. Cambio invasivo, riesgo de inconsistencia entre lo que vive en assets/ y lo que se ejecuta. Descartado.

Workflow elegido: la app cambia valores en vivo (en memoria), el desarrollador copia los valores finales al JSON manualmente cuando los confirma. Más fricción pero más auditable.

### Pantalla simplificada sin sliders

Solo mostrar las stats y la herramienta de distancia conocida, sin sliders. El usuario tendría que editar el JSON y reiniciar para probar valores nuevos. Es lo que hacíamos antes y costaba horas por iteración. Decidimos invertir en la complejidad de sliders en vivo porque amortiza rapidísimo.

### Sliders sin ref counting (forzar `/mapa` cerrado para usar `/calibracion`)

Más simple pero peor UX. El usuario en testing real quiere abrir el mapa, ver el dot, abrir /calibracion, ajustar, volver al mapa, repetir. Ref counting hace esto fluido.

## Consecuencias

### Positivas

- **Iteración de calibración 10-20x más rápida**: en lugar de minutos por round-trip, segundos
- **Stats robustas**: media sobre 100+ muestras vs instantánea
- **Sugerencias automáticas**: el usuario no tiene que hacer la matemática mental
- **Export CSV**: análisis offline en Excel/Sheets sin re-instrumentar la app
- **Refactor de PositioningService** quedó más limpio: ref counting + listener pattern son patterns estándar reutilizables

### Negativas

- **~700 líneas nuevas** entre `calibracion_screen.dart` (~770), `beacon_stats.dart` (~70), modificaciones a `positioning_service.dart` (~40), `main.dart` (~20)
- **Cambios cross-cutting** en PositioningService (ref counting, listener) requieren testing para confirmar que no introdujeron regresiones en escenarios existentes (MapaScreen solo, sin /calibracion)
- **Solo en debug**: la pantalla no llega a usuarios finales (correcto: es herramienta de desarrollo), pero el código vive en el bundle de debug. Aceptable.

### Mitigaciones

- Documentación clara en el código de las decisiones (ref counting, ventana mutable, notifier pattern)
- ADR explicando el pattern por si futuros mantenedores se preguntan por qué tanto refactor
- Plan de actualizar `docs/setup-beacons.md` para incorporar la pantalla al procedimiento oficial de calibración (pendiente)

## Referencias

- [ADR-0002](0002-parametros-path-loss.md) — parámetros default y procedimiento teórico de calibración
- [`docs/positioning-ble.md`](../positioning-ble.md) — modelo de path-loss
- [`docs/setup-beacons.md`](../setup-beacons.md) — procedimiento físico (a actualizar)
- Patrón `ChangeNotifier` + `ValueListenable`: estándar de Flutter (`ScrollController`, `TransformationController`, etc.)
