# ADR-0002 — Parámetros del modelo de path-loss para edificio FISC

- **Estado:** aceptado
- **Fecha:** 2026-05-19
- **Autor:** equipo UTP-Guide
- **Supersede:** parcialmente — los valores iniciales en código eran `n=2.7, txPower=-59` (hardcoded). Este ADR los reemplaza y los mueve a configuración.
- **Actualización 2026-06-24:** EXP1 midió en el pasillo del piso 4 `n ≈ 1.6`, `txPower ≈ -59` (guía de onda). Los defaults de código (3.5 / -65) se mantienen como punto de partida para zonas sin medir; los entornos del pasillo usan los valores medidos. Ver `docs/positioning-ble.md`.

## Contexto

El modelo de path-loss usado por `PositioningService` para convertir RSSI en distancia es:

```
d = 10 ^ ((txPower - RSSI) / (10 · n))
```

Los parámetros `txPower` y `n` afectan directamente la precisión del posicionamiento, y son **dependientes del entorno físico**:

- `txPower` depende del modelo de la baliza, su orientación y la tolerancia de fabricación
- `n` depende del material de muros, mobiliario, presencia de personas, humedad

Los valores iniciales del proyecto (`n=2.7, txPower=-59`) son aceptables para un entorno de prueba abierto (la sala 5×5 con Beacon Simulator iOS), pero no son los correctos para el edificio FISC real.

Adicionalmente, los parámetros estaban **hardcoded como constantes en código Dart**, lo que requería recompilar la app para ajustarlos. Esto es inaceptable para un piloto en campo donde la calibración puede necesitar ajustes diarios.

## Decisión

### Parte 1: mover parámetros a `beacon_config.json`

Los parámetros de calibración se leen de `assets/data/beacon_config.json` bajo la clave `calibracion`:

```json
"calibracion": {
  "txPower_dbm_default": -65,
  "n_exponente_perdida": 3.5,
  "ventana_media_movil": 8,
  "tolerancia_snap_metros": 3.0,
  "expiracion_lectura_segundos": 3
}
```

Adicionalmente, cada baliza puede tener su propio `txPower_dbm` que sobrescribe el global:

```json
"beacons": [
  {"minor": 1, "x": 0.5, "y": 0.5, "txPower_dbm": -67, "descripcion": "..."},
  ...
]
```

`BeaconRepository` expone los parámetros vía `obtenerCalibracion()` y `obtenerBeaconConfig(minor)`. `PositioningService` los lee al inicializarse.

### Parte 2: valores por defecto para FISC

Los valores escogidos están basados en literatura de propagación BLE en entornos universitarios y oficinas con paredes de concreto:

| Parámetro | Valor | Justificación |
|-----------|-------|---------------|
| `n_exponente_perdida` | **3.5** | Literatura típica para edificios con muros de concreto en LOS. Rango general: 3.0-4.0. |
| `txPower_dbm_default` | **-65** | Minew E2 Max configurado a -12 dBm de potencia de transmisión emite ~-65 dBm RSSI a 1 m. |
| `ventana_media_movil` | **8** | 2-4 segundos de historia a la tasa típica de scan iBeacon. Suficiente para suavizar ruido sin agregar lag perceptible. |
| `tolerancia_snap_metros` | **3.0** | Permite snap en pasillos normales (1-2 m de ancho típico) sin "pegar" posiciones lejanas del grafo. |
| `expiracion_lectura_segundos` | **3** | Beacon Simulator iOS emite cada 500 ms; 3 segundos = 6 anuncios perdidos consecutivos antes de considerar la baliza fuera de rango. |

## Consecuencias

### Positivas

- Calibración **sin recompilar** la app — solo editar el JSON y reiniciar
- Soporte para **calibración por baliza** — cada Minew E2 Max puede tener su propio `txPower` medido
- Valores **documentados con justificación física** — un futuro reviewer puede entender de dónde viene cada número
- Permite **experimentar** con `n` en campo (3.0 vs 3.5 vs 4.0) para encontrar el mejor para el edificio específico

### Negativas

- Más complejidad en el código — `BeaconRepository` ahora expone modelos de configuración, no solo posiciones
- Si el archivo JSON tiene un valor faltante, hay que decidir si fallar o usar default. Decisión: **usar default con warning en consola**, para que la app no se rompa si alguien edita el archivo y omite un campo

### Riesgos

- Si los valores escogidos resultan incorrectos en campo, hay que **recalibrar** siguiendo el procedimiento en `docs/setup-beacons.md`. No bloquea desarrollo pero requiere acceso físico al edificio.

## Procedimiento de calibración

Documentado en detalle en [`docs/setup-beacons.md`](../setup-beacons.md), secciones 5 (calibración de `txPower`) y 6 (calibración de `n`).

## Referencias

- Rappaport, T.S. *Wireless Communications: Principles and Practice* (2nd ed.), Prentice Hall, capítulo 4 (propagación indoor)
- Bluetooth SIG. *Bluetooth Core Specification* 5.0, secciones relevantes a transmisión BLE
- Datasheet Minew E2 Max (TX Power vs RSSI a 1m)
