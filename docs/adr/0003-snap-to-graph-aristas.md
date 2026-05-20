# ADR-0003 — Snap-to-graph por aristas en lugar de nodos

- **Estado:** aceptado
- **Fecha:** 2026-05-17
- **Autor:** equipo UTP-Guide

## Contexto

La trilateración BLE produce una posición cruda `(x_raw, y_raw)` que puede caer en cualquier punto del plano: dentro de una pared, fuera del edificio, en una zona desconocida. Mostrar esa posición cruda al usuario sería ruidoso y poco útil — el punto saltaría, se metería en muros, daría la impresión de que el sistema no funciona.

La técnica estándar es **snap-to-graph**: proyectar la posición cruda al punto más cercano del grafo de navegación. Hay dos variantes:

### Variante A — Snap-to-nodo

Encontrar el nodo más cercano a `(x_raw, y_raw)` y reportar la posición de ese nodo.

```
posición_reportada = argmin_{nodo n} distancia((x_raw, y_raw), n)
```

### Variante B — Snap-to-arista

Para cada arista `(a, b)` del grafo, calcular el punto más cercano del segmento `ab` a `(x_raw, y_raw)`. Tomar el de mínima distancia.

```
para cada arista (a, b):
    p_proyectado = punto más cercano en segmento ab a (x_raw, y_raw)
    d = distancia((x_raw, y_raw), p_proyectado)
posición_reportada = p_proyectado con d mínimo
```

## Decisión

Usar **snap-to-arista** (variante B).

## Justificación

### Caso de uso típico

Un usuario camina por un pasillo recto de 20 metros. El pasillo está modelado en el grafo como dos nodos `INTERSECCION` en los extremos, conectados por una sola arista de 20 m de largo.

**Con snap-to-nodo:**
- Si el usuario está a 5 m del nodo A, snap reporta posición de A (5 m de error)
- Si el usuario camina a 10 m, el punto reportado salta súbitamente al nodo B
- El usuario percibe el sistema como "roto" — el dot parpadea entre dos puntos

**Con snap-to-arista:**
- El usuario se desliza visualmente a lo largo de la arista conforme camina
- La posición reportada se actualiza continuamente, no salta
- El usuario percibe el sistema como funcional y preciso

### Casos donde aplica el snap-to-nodo

En intersecciones, el snap-to-arista naturalmente reporta posición en uno de los extremos de las aristas confluyentes, lo que coincide con la posición del nodo de intersección. No hay caso donde snap-to-nodo dé mejor experiencia.

### Tolerancia de snap

Si `(x_raw, y_raw)` está muy lejos del grafo (>3 m de cualquier arista), el snap **no se aplica** y se reporta la posición cruda. Esto cubre escenarios donde:

- El usuario salió temporalmente de un área cubierta por el grafo
- Hay un error grande de trilateración que no debería ocultarse con un snap falso

El parámetro `tolerancia_snap_metros` está en `beacon_config.json`. Default: **3.0 m**.

## Implementación

`PositioningService._snapToGraph(x, y)` itera todas las aristas del grafo y calcula la proyección del punto al segmento usando la fórmula estándar:

```
para segmento ab y punto p:
    t = ((p - a) · (b - a)) / |b - a|²
    t_clamp = max(0, min(1, t))
    proyección = a + t_clamp · (b - a)
```

Si `t < 0` o `t > 1`, el punto más cercano del segmento es uno de los extremos `a` o `b` respectivamente.

## Consecuencias

### Positivas

- Experiencia de usuario fluida — el dot se desliza, no salta
- Comportamiento intuitivo en pasillos largos
- Robusto contra errores de trilateración pequeños (≤ tolerancia)
- O(|aristas|) por estimación — escala bien con grafos de cientos de aristas

### Negativas

- Más cálculos por iteración que snap-to-nodo (5-10 operaciones aritméticas por arista vs 1)
- Requiere modelar el grafo con aristas continuas a lo largo de los pasillos — modelar un pasillo como una secuencia de nodos sueltos sin aristas largas pierde el beneficio

### Implicaciones para el modelado del grafo

Los pasillos deben modelarse como **una arista continua** entre intersecciones, no como una secuencia de nodos densos. Por ejemplo:

- ❌ **Mal:** un pasillo de 20 m modelado como 10 nodos con 9 aristas de 2 m cada una
- ✅ **Bien:** un pasillo de 20 m modelado como 2 nodos `INTERSECCION` con 1 arista de 20 m

La densidad de nodos `INTERSECCION` debe ser solo la necesaria para que A* produzca rutas correctas en bifurcaciones.

## Referencias

- Computational Geometry — algoritmos de proyección punto-segmento
- Real-Time Indoor Positioning Algorithms, IEEE PerCom 2014
