# ADR-0001 — Centroide ponderado vs trilateración matricial

- **Estado:** aceptado
- **Fecha:** 2026-05-17
- **Autor:** equipo UTP-Guide

## Contexto

El sistema de posicionamiento BLE necesita convertir un conjunto de pares `(beacon, RSSI)` en una posición estimada `(x, y)` del usuario. Hay varias técnicas estándar:

1. **Trilateración matricial (least squares)** — resolver el sistema de ecuaciones cuadráticas que define la intersección de círculos centrados en cada beacon, con radios iguales a las distancias estimadas. Es la técnica más precisa en condiciones ideales.

2. **Centroide ponderado** — promediar las posiciones de los beacons con pesos inversamente proporcionales a la distancia estimada al cuadrado. Heurística, no exacta.

3. **Fingerprinting** — comparar el vector de RSSIs actual contra una base de datos pre-construida de fingerprints en posiciones conocidas. Requiere fase offline de levantamiento.

4. **Filtro de partículas / Kalman** — métodos probabilísticos que mantienen una distribución de probabilidad sobre la posición. Más complejos, pueden combinar con cualquiera de los anteriores.

Para Fase 1 del proyecto, queremos posicionamiento "razonablemente útil" sin construir infraestructura adicional (no hay base de datos de fingerprints, no hay calibración previa de partículas).

## Decisión

Usar **centroide ponderado** con peso `w_i = 1/d_i²` para estimar la posición.

```
x = Σ (x_i · w_i) / Σ w_i
y = Σ (y_i · w_i) / Σ w_i
```

### Alternativas descartadas

**Trilateración matricial (least squares):**

- Requiere exactamente ≥3 beacons visibles para tener solución única
- Falla con configuraciones geométricas degeneradas (3 beacons colineales)
- Sensible a un solo RSSI muy ruidoso — un outlier puede sesgar drásticamente la solución
- Requiere implementar resolución numérica (pseudoinversa de Moore-Penrose o similar) sin paquete de álgebra lineal en Dart

**Fingerprinting:**

- Requiere fase de levantamiento manual: caminar el edificio en una grilla de puntos y registrar el RSSI promedio en cada uno
- 100+ puntos × 5 min de muestreo = 8+ horas por piso
- Necesita mantenimiento si se mueven balizas o se renueva el edificio
- Fuera de alcance para un proyecto estudiantil

**Filtros probabilísticos:**

- Complejidad adicional importante (estado oculto, modelo de movimiento, modelo de observación)
- No tienen sentido sin un estimador base que filtrar — son post-procesamiento sobre las técnicas anteriores
- Fase 2+

## Consecuencias

### Positivas

- Funciona con **cualquier cantidad** de beacons visibles (1, 2, 3+) — no falla por falta de cobertura
- **Robusto a un beacon ruidoso** — su contribución se diluye con los demás
- **O(n) por estimación** — computacionalmente trivial, no impacta batería ni rendimiento
- No requiere infraestructura previa (calibración por punto, etc.)
- Implementación corta y verificable

### Negativas

- **Sesgada hacia el interior del polígono de beacons** — un usuario fuera del triángulo de beacons será reportado en el borde del triángulo, no en su posición real
- **Precisión limitada en condiciones ideales** — least-squares converge a la solución óptima en el sentido de mínimos cuadrados; centroide ponderado no
- No produce **estimación de incertidumbre** — solo un punto, no un círculo de confianza

### Mitigaciones

- El **snap-to-graph** ([ADR-0003](0003-snap-to-graph-aristas.md)) compensa parcialmente la imprecisión proyectando la posición al pasillo más cercano
- La **media móvil de 8 lecturas** suaviza fluctuaciones, mejorando la estabilidad visual
- Para Fase 2+, evaluar agregar un **filtro de Kalman** sobre el centroide ponderado

## Referencias

- Cliff Cocks et al. "Indoor Positioning via Trilateration and Fingerprinting"
- Estimote SDK documentation, secciones de algoritmos de posicionamiento
- "Survey of Wireless Indoor Positioning Techniques and Systems", Liu et al., IEEE Trans. on Systems, Man, and Cybernetics (2007)
