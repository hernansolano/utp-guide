# Posicionamiento BLE — Modelo y algoritmo

Este documento explica en detalle cómo UTP-Guide estima la posición del usuario dentro del edificio usando balizas Bluetooth Low Energy (BLE).

## El problema

Las técnicas tradicionales de localización (GPS) no funcionan en interiores. Los muros, el techo y las estructuras de concreto bloquean la señal de los satélites. Para guiar a un usuario dentro de un edificio necesitamos una técnica alternativa.

Las balizas BLE (iBeacon, Eddystone) emiten un anuncio periódico que cualquier dispositivo cercano puede recibir. Midiendo la **intensidad de la señal recibida (RSSI)** podemos estimar la **distancia** entre el dispositivo y la baliza. Con suficientes balizas en posiciones conocidas, podemos triangular la posición del usuario.

## El modelo de path-loss

La intensidad de una señal de radio decae con la distancia siguiendo una **ley de potencia** llamada modelo de path-loss log-normal. La ecuación es:

```
RSSI(d) = txPower - 10 · n · log₁₀(d)
```

Despejando `d`:

```
d = 10 ^ ((txPower - RSSI) / (10 · n))
```

Donde:

| Símbolo   | Significado |
|-----------|-------------|
| `d`       | Distancia entre el dispositivo y la baliza, en metros |
| `RSSI`    | Intensidad de la señal recibida, en dBm (negativo) |
| `txPower` | RSSI medido a 1 metro de la baliza, en dBm (calibrado) |
| `n`       | Exponente de pérdida del entorno (sin unidades) |

### El parámetro `n` (exponente de pérdida)

Es el parámetro más sensible al entorno. Determina qué tan rápido decae la señal con la distancia:

| Entorno                                  | Rango de `n` |
|------------------------------------------|--------------|
| Espacio libre (ideal, vacío)             | 2.0          |
| Oficinas con paredes ligeras (drywall)   | 2.5–3.0      |
| **Edificios con muros de concreto (FISC)** | **3.0–3.5**  |
| A través de muros densos (NLOS severo)   | 4.0–5.0      |

UTP-Guide usa **`n = 3.5`** por defecto, calibrado para el edificio FISC. Este valor puede ajustarse en `assets/data/beacon_config.json` sin recompilar.

Ver [ADR-0002](adr/0002-parametros-path-loss.md) para la justificación detallada.

### El parámetro `txPower`

Es la potencia de señal medida a exactamente 1 metro de la baliza. Cada modelo de baliza tiene un valor distinto:

| Modelo            | txPower típico |
|-------------------|----------------|
| iBeacon iOS (Beacon Simulator) | -59 dBm |
| **Minew E2 Max (potencia reducida interior)** | **-65 dBm** |
| Minew E2 Max (potencia estándar) | -59 dBm |
| Estimote LTE Beacon | -77 dBm |

UTP-Guide soporta un `txPower_dbm_default` global y un `txPower_dbm` por baliza individual. Si una baliza tiene su propio campo, se usa ese; si no, el global.

## Trilateración por centroide ponderado

Con la distancia estimada a cada baliza y la posición conocida de cada baliza, queremos estimar la posición del usuario `(x, y)`.

UTP-Guide usa **centroide ponderado** en lugar de trilateración matricial clásica. El cálculo es:

```
x_usuario = Σ (xᵢ · wᵢ) / Σ wᵢ
y_usuario = Σ (yᵢ · wᵢ) / Σ wᵢ

donde wᵢ = 1 / dᵢ²
```

Es decir, cada baliza vota por su propia posición, y su voto pesa proporcionalmente al inverso del cuadrado de la distancia. Las balizas más cercanas tienen mucho más peso que las lejanas.

**Ventajas sobre trilateración matricial:**

1. Funciona con cualquier cantidad de balizas visibles (1, 2, 3+), no requiere exactamente 3
2. Robusto a una sola baliza con RSSI muy ruidosa (sus contribuciones se diluyen)
3. No falla con configuraciones geométricas degeneradas (balizas colineales)
4. Computacionalmente trivial — O(n) por estimación

**Desventajas:**

1. Sesgada hacia el interior del polígono de balizas — un usuario fuera del triángulo de balizas será reportado en el borde
2. Menos precisa que least-squares en condiciones ideales

Ver [ADR-0001](adr/0001-centroide-ponderado.md) para la decisión completa.

## Filtros de ruido

El RSSI de BLE es ruidoso. Una lectura cruda puede variar ±5 dBm de un instante al siguiente para una baliza estacionaria — eso se traduce en variaciones de 1-2 metros en la distancia estimada. Aplicamos dos filtros:

### Filtro 1: Media móvil por baliza

Mantenemos una **cola circular de 8 lecturas recientes** por baliza. Cada lectura se convierte a distancia usando el modelo de path-loss, y la distancia que usamos para trilateración es el promedio de la cola.

```
ventana[minor] = Queue<double>  // FIFO, max 8 entradas
distancia_suavizada = mean(ventana[minor])
```

**Por qué 8 lecturas:** flutter_blue_plus emite resultados ~2-5 veces por segundo por baliza durante un scan activo. 8 lecturas representan ~2-4 segundos de historia, suficiente para suavizar fluctuaciones rápidas sin agregar lag perceptible.

### Filtro 2: Limpieza de balizas obsoletas

Si una baliza deja de estar en rango, sus últimas 8 lecturas siguen en memoria. Para evitar que una baliza "fantasma" siga sesgando la posición:

- Cada `BeaconReading` lleva un timestamp
- Antes de cada estimación de posición, eliminamos balizas cuya última lectura tenga más de **3 segundos**
- El umbral está en `beacon_config.json → calibracion → expiracion_lectura_segundos`

Esto se hace al ritmo de cada nueva lectura entrante, sin timers separados.

## Snap-to-graph

La posición cruda de la trilateración puede estar en cualquier lado: dentro de una pared, fuera del edificio, en una zona inaccesible. El **snap-to-graph** proyecta la posición al punto más cercano de cualquier **arista** del grafo de navegación.

Algoritmo:

```
1. Calcular (x_raw, y_raw) por centroide ponderado
2. Para cada arista (a, b) del grafo:
   - p* = punto más cercano a (x_raw, y_raw) en el segmento ab
   - d  = distancia euclidiana de (x_raw, y_raw) a p*
3. Tomar p* con d mínima
4. Si d_min ≤ tolerancia_snap (default 3m):
     → reportar p* como posición
   Si no:
     → reportar (x_raw, y_raw) sin modificar (el usuario está fuera del grafo)
```

**Por qué proyectar a aristas y no solo a nodos:**

Si un usuario está caminando por un pasillo de 20 m, el nodo más cercano puede estar a 10 m de distancia (en el extremo del pasillo). Snap-a-nodo lo mostraría parpadeando entre los dos extremos. Snap-a-arista lo muestra exactamente sobre el pasillo, deslizándose a lo largo del segmento conforme camina. Es lo que el usuario espera ver.

Ver [ADR-0003](adr/0003-snap-to-graph-aristas.md) para más detalle.

## Configuración

Todos los parámetros viven en `assets/data/beacon_config.json`:

```json
{
  "uuid": "550e8400-e29b-41d4-a716-446655440000",
  "major": 1,
  "calibracion": {
    "txPower_dbm_default": -65,
    "n_exponente_perdida": 3.5,
    "ventana_media_movil": 8,
    "tolerancia_snap_metros": 3.0,
    "expiracion_lectura_segundos": 3
  },
  "beacons": [
    {"minor": 1, "x": 0.5, "y": 0.5, "txPower_dbm": -65, "descripcion": "..."},
    ...
  ]
}
```

Si estos parámetros cambian, **no hace falta recompilar** la app: solo reemplazar el archivo en `assets/data/` y reiniciar.

## Modo simulación (sin hardware)

Para iterar el pipeline sin balizas físicas, la app incluye `SimulatedBleService`. Cuando el toggle "Modo simulación" en Settings está activo, el `BleSourceMultiplexer` reemplaza el escaneo real por uno sintético:

1. El usuario arrastra el dedo sobre el mapa de `MapaScreen` para definir una "posición virtual"
2. Cada 500 ms, el simulador recorre las balizas registradas en `beacon_config.json` y calcula la distancia desde la posición virtual a cada una
3. Aplica el **inverso del modelo de path-loss** (`rssi = txPower − 10·n·log10(d)`) para producir un RSSI teórico
4. Le agrega ruido gaussiano con σ = 3 dBm para imitar la variación natural
5. Emite la lectura como `BeaconReading`, indistinguible de una real para el resto del pipeline

El dot azul que aparece en el mapa es el resultado de procesar esas lecturas sintéticas con el mismo algoritmo de trilateración + snap-to-graph que se usa en producción. Una cruz roja marca la posición virtual donde el usuario soltó el dedo — comparar dot azul vs cruz roja es el indicador visual de qué tan bien calibrado está el sistema.

Ver [ADR-0008](adr/0008-simulador-ble-para-testing.md) para el razonamiento completo.

## Pasos siguientes (Fase 2+)

- **Filtro de Kalman** para suavizado temporal entre estimaciones consecutivas
- **Calibración automática** del parámetro `n` usando posiciones conocidas (puntos de referencia ArUco)
- **Manejo de pisos** usando el campo `major` del iBeacon como identificador de piso
- **Persistencia local** del historial de RSSI para análisis offline

Las mejoras pendientes se registran como ADRs.
