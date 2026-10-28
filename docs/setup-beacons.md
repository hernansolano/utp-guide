# Instalación y calibración de balizas BLE

Este documento describe el procedimiento físico para instalar las balizas Minew E2 Max en un piso y calibrar los parámetros del sistema de posicionamiento.

> **Prerrequisito:** el piso debe estar ya modelado en `assets/maps/<edificio>_<piso>.svg` y `assets/data/grafo.json`. Las coordenadas de las balizas que se registran en `beacon_config.json` están en el mismo sistema (metros desde la esquina superior izquierda) que los nodos del grafo. Ver [`map-format.md`](map-format.md) para el procedimiento de autoría del mapa.

## 1. Hardware

### Modelo recomendado

**Minew E2 Max** (BLE 5.0, batería CR2477):

- Vida útil: 5+ años en configuración estándar, 2+ años en potencia máxima
- Alcance: 70 m en LOS, 15-25 m a través de muros de concreto
- TX Power configurable: -40 a +4 dBm (recomendado **-12 dBm para interiores**)
- Intervalo de anuncio configurable: 100 ms - 10 s (recomendado **500 ms**)

### Cantidad mínima

| Área | Balizas mínimas | Distribución recomendada |
|------|----------------|--------------------------|
| Salón individual (≤ 30 m²) | 2 | Esquinas opuestas |
| Pasillo recto (≤ 20 m) | 2 | Cada extremo |
| Pasillo largo (> 20 m) | 3+ | Cada extremo + medio |
| Intersección de pasillos | 1 | Centro de la intersección |
| Piso completo (FISC piso 3) | 8-12 | Ver plano de calibración |

## 2. Configuración de cada baliza

Antes de instalar, configurar cada baliza con la app oficial de Minew (Minew Beacon Plus, iOS/Android):

| Campo | Valor |
|-------|-------|
| **UUID** | `550e8400-e29b-41d4-a716-446655440000` |
| **Major** | Número del piso: **4** para el piloto (debe coincidir con `major` de `beacon_config.json`) |
| **Minor** | ID único de la baliza dentro del piso (1, 2, 3, ...) |
| **TX Power** | **-12 dBm** (potencia reducida interior) |
| **Intervalo de anuncio** | 500 ms |

> **Importante:** todas las balizas del proyecto comparten el mismo UUID. El UUID identifica al sistema UTP-Guide; Major identifica el piso; Minor identifica la baliza individual.
>
> **La app descarta las lecturas cuyo Major no coincide** con el `major` de `beacon_config.json`, y también los Minor que no estén registrados ahí (desde el 2026-10-28). Si una baliza no aparece en el mapa pero sí en el diagnóstico de Calibración, revisa primero su Major.

## 3. Instalación física

### Posicionamiento

- **Altura:** 2.4 - 2.8 m del suelo (arriba de las puertas, debajo del techo)
- **Orientación:** la cara con el sensor BLE hacia el espacio abierto del pasillo o sala
- **Espacio libre:** al menos 30 cm de cualquier objeto metálico grande (extintores, tableros eléctricos, ductos)
- **Fijación:** doble cinta adhesiva 3M de exteriores o anclaje a pared (depende del acabado)

### Plano de instalación

Por cada baliza, anotar en una hoja de campo:

| Minor | Ubicación descriptiva | x (m) | y (m) | TX Power | Fecha |
|-------|----------------------|-------|-------|----------|-------|
| 1 | Pared norte, esquina NO | 0.5 | 0.5 | -12 dBm | 2026-05-20 |
| 2 | Pared sur, esquina SE | 4.5 | 4.5 | -12 dBm | 2026-05-20 |
| ... | | | | | |

Las coordenadas `(x, y)` se miden desde la **esquina superior izquierda** del plano, en **metros**, con cinta métrica o medidor láser.

## 4. Configuración del sistema

Una vez instaladas, registrar todas las balizas en `assets/data/beacon_config.json`:

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
    {"minor": 1, "x": 0.5, "y": 0.5, "txPower_dbm": -65, "descripcion": "Pared norte, esquina NO"},
    {"minor": 2, "x": 4.5, "y": 4.5, "txPower_dbm": -65, "descripcion": "Pared sur, esquina SE"}
  ]
}
```

> **Nota:** el `txPower_dbm` en el archivo es el RSSI **medido a 1 metro de distancia**, no la potencia de transmisión configurada en la baliza. Estos números son diferentes. Ver paso 5.

## 5. Calibración con la pantalla `/calibracion`

Desde la versión actual, el procedimiento de campo se hace dentro de la app. Abrir Ajustes → Desarrollador → "Calibración BLE (campo)". Ahí:

1. **Stats en vivo:** cada baliza detectada muestra RSSI actual y promedio sobre N muestras, con desviación estándar y distancia calculada usando la calibración vigente.
2. **Herramienta "Distancia conocida":** ingresa la distancia real desde donde estás parado y la app sugiere qué valor de `n` o `txPower` haría que el cálculo coincida con la realidad.
3. **Sliders en vivo:** mueve `n`, ventana de media móvil y tolerancia de snap para ver el efecto inmediatamente. Cuando los valores se sientan bien, copia el bloque JSON sugerido en la sección "Aplicar permanentemente" y pégalo en `assets/data/beacon_config.json`.
4. **Export CSV:** botón de copia al portapapeles que produce un CSV listo para pegar en Sheets/Excel.

La pantalla solo aparece en builds de debug (`kDebugMode`). En release no es accesible.

Las secciones 5 y 6 originales (cálculo manual de `txPower` y `n`) se mantienen abajo para referencia teórica y para casos donde la pantalla no esté disponible (por ejemplo, build de release antes de un deploy).

## 5b. Calibración manual del `txPower` por baliza

Para cada baliza, medir el RSSI a 1 metro exacto:

1. Caminar hasta estar a **1.00 m exactos** de la baliza (cinta métrica)
2. Mantener el teléfono a la altura del pecho, sin obstrucciones entre el teléfono y la baliza
3. Esperar 10 segundos para que el promedio se estabilice
4. Anotar el RSSI promedio que reporta la app

El valor anotado es el `txPower_dbm` a registrar en `beacon_config.json` para esa baliza específica.

**Por qué cada baliza puede tener un valor distinto:**

- Tolerancia de fabricación (±2 dBm normal entre unidades del mismo lote)
- Orientación de la antena
- Materiales cercanos (un panel de yeso vs. una pared de concreto detrás de la baliza)

## 6. Calibración del exponente `n`

El parámetro `n` describe qué tan rápido decae la señal con la distancia en el ambiente específico. Procedimiento:

1. Elegir una baliza ya calibrada (con su `txPower_dbm` correcto)
2. Posicionarse a distancias conocidas: 1 m, 2 m, 3 m, 5 m, 8 m
3. Para cada distancia, anotar el RSSI promedio (10 s de muestreo)
4. Resolver `n` con la ecuación:

```
n = (txPower - RSSI) / (10 · log₁₀(d))
```

5. Calcular el promedio de `n` para todas las distancias
6. Registrar en `beacon_config.json → calibracion → n_exponente_perdida`

**Valores esperados para FISC:**

| Distancia (m) | RSSI esperado @ txPower=-65, n=3.5 |
|---------------|------------------------------------|
| 1             | -65 dBm                            |
| 2             | -75.5 dBm                          |
| 3             | -81.7 dBm                          |
| 5             | -89.5 dBm                          |
| 8             | -96.6 dBm                          |

Si tus mediciones reales se desvían más de 3 dBm de la tabla, recalibra `n`.

## 7. Verificación

Con `beacon_config.json` actualizado, abrir la app y validar:

1. **Chip BLE en MapaScreen:** debe mostrar el número correcto de balizas detectadas en cada zona
2. **Coordenadas en la NavigationCard:** caminar a posiciones conocidas y verificar que las coordenadas reportadas coincidan con ±1.5 m
3. **Punto azul en el mapa:** debe estar visible y moverse suavemente cuando caminas, sin saltos bruscos ni parpadeos

Si el sistema reporta consistentemente posiciones lejanas o el punto salta:

- Saltos bruscos → aumentar `ventana_media_movil` a 10-12
- Posición sesgada hacia balizas específicas → calibrar `txPower_dbm` de esas balizas
- Posición fuera del grafo → verificar `tolerancia_snap_metros` y cobertura del grafo

## 8. Mantenimiento

- **Anual:** verificar batería de las balizas (la app de Minew reporta el voltaje)
- **Tras renovación del edificio:** recalibrar todas las balizas en zonas modificadas (las nuevas paredes cambian el patrón de propagación)
- **Tras quejas de usuarios:** revisar la zona reportada como problemática, verificar que las balizas locales siguen funcionando y bien fijadas

## Referencias

- iBeacon Specification (Apple): https://developer.apple.com/ibeacon/
- Minew E2 Max datasheet: https://www.minew.com/product/e2-max/
- Path Loss Models for Indoor Propagation: Rappaport, T.S. "Wireless Communications: Principles and Practice"
