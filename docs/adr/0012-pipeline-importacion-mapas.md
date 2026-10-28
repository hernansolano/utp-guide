# ADR-0012 — Pipeline de importación de mapas desde escaneos (DXF → SVG + grafo)

- **Estado:** aceptado
- **Fecha:** 2026-06-22
- **Autor:** equipo UTP-Guide

## Contexto

Modelar un piso a mano es lento y propenso a error. El [ADR-0006](0006-formato-mapa-svg-metrico.md) define que cada piso necesita un SVG vectorial (muros, puertas) a escala fija 100 px = 1 m, y el [ADR-0005](0005-grafo-editor-cli.md) define que el grafo de navegación se edita con una herramienta dedicada. Pero faltaba el primer eslabón: **cómo se obtiene ese SVG y las coordenadas iniciales** a partir del levantamiento real del piso.

El equipo levanta los pisos con **Polycam** (escaneo LiDAR desde el teléfono), que exporta varios formatos: `DXF` (vectorial), `CSV` (dimensiones/áreas por cuarto), `PNG` (render) y `HTML` (visor 3D). Dibujar el SVG a mano sobre un render, además de tedioso, rompe la escala métrica de la que dependen el posicionamiento y el ruteo.

Se necesita un pipeline que convierta un escaneo en los tres artefactos que consume la app —`assets/maps/<edificio>_<piso>.svg`, `assets/data/grafo.json`, `assets/data/beacon_config.json`— respetando la escala métrica y sin acoplar el proceso a hardware ni a `package:flutter`.

Restricciones del proyecto:

- **Sin dependencias nuevas** sin auditoría ([ADR-0009](0009-pinning-dependencias.md)).
- `grafo.json` / `beacon_config.json` son **archivos protegidos** (ver [arquitectura](../architecture.md#archivos-protegidos)): el pipeline produce archivos para revisar y pegar, no los sobrescribe a ciegas.
- El SVG debe quedar **limpio**: muros y puertas, sin etiquetas ni medidas impresas (decisión de producto del equipo).

## Decisión

Implementar el pipeline en **dos herramientas desacopladas**, separando la **geometría** (qué forma tiene el piso) de la **semántica de navegación** (dónde están los destinos, por dónde se camina, dónde van las balizas):

1. **`tools/mapa_importer.dart`** — CLI en **Dart puro** (sin Flutter), con dos etapas:
   - `parse`: lee el **DXF** y produce un *borrador* JSON intermedio (polígonos de muros y puertas, cuartos, bounding box y dimensiones en metros).
   - `build`: toma el borrador y emite un **SVG limpio** (muros rellenos, huecos de puerta, recorte por bounding box), a escala 100 px = 1 m.

2. **`tools/editor_mapa.html`** — editor **offline en el navegador** (HTML/JS, sin servidor ni dependencias). Carga el borrador/SVG y permite, en tres modos (**Balizas / Nodos / Aristas**), colocar y arrastrar balizas, marcar nodos (con tipo, nombre, accesible) y conectar aristas (la distancia se calcula sola). Exporta `mapa.svg`, `grafo.json` y `beacon_config.json` listos para revisar.

El **DXF es la fuente geométrica de verdad**; el CSV se usa solo como verificación cruzada de medidas; HTML y PNG se descartan como fuente (son visores, no datos estructurados). El cierre del pipeline es la validación con `dart tools/grafo_editor.dart validar-mapa` ([ADR-0007](0007-validacion-cruzada-mapa-grafo.md)).

## Justificación y alternativas

### Por qué dos herramientas y no una

La geometría (muros/puertas) sale del escaneo de forma **determinista**; la semántica de navegación (qué es un salón, qué pasillo conecta con qué, dónde conviene una baliza) requiere **criterio humano** y conocimiento del edificio. Mezclarlas en un solo paso obligaría a inferir cosas no fiables del DXF. Separarlas deja cada parte en la herramienta adecuada: el `mapa_importer` no adivina nada de navegación, y el editor no reparsea geometría.

### Por qué Dart puro + HTML offline, sin dependencias

El DXF es texto tabulado (pares código/valor); extraer `LINE`/`LWPOLYLINE` por capa se hace con Dart stdlib, igual que el `grafo_editor` ([ADR-0005](0005-grafo-editor-cli.md)). El editor es HTML/JS estático que corre en cualquier navegador sin instalar nada. Así el pipeline **no agrega ni una dependencia** al `pubspec.yaml` ni arrastra Flutter a las herramientas.

### Alternativa A — Auto-sugerencia de balizas (heurística de cobertura/GDOP)

El plan inicial incluía que el importer **sugiriera** posiciones de balizas (perímetro, bien separadas, evitando colinealidad, garantizando ≥3 balizas no colineales por nodo). **Descartada por ahora:** el equipo prefirió control manual ("que no sugiera los sitios de beacons, que devuelva solo el SVG con paredes, puertas y poco más"). La heurística queda como trabajo futuro; hoy las balizas se colocan a mano en el editor.

### Alternativa B — Parsear HTML/PNG de Polycam

Descartada: el HTML es un visor 3D y el PNG es un raster; ninguno expone geometría vectorial estructurada con escala. El DXF sí.

### Alternativa C — Editor in-app en Flutter

Descartada por el mismo argumento del [ADR-0005](0005-grafo-editor-cli.md): la herramienta la usa el **desarrollador** al levantar un piso, no el usuario final. Una pantalla in-app gastaría tiempo de desarrollo y espacio en la app de producción sin beneficio para el estudiante.

### Alternativa D — Librería DXF de pub.dev

Descartada: violaría la política de pinning/auditoría ([ADR-0009](0009-pinning-dependencias.md)) para una necesidad acotada (solo extraemos líneas/polilíneas por capa), resoluble con un parser propio pequeño.

## Implementación

### `tools/mapa_importer.dart`

```bash
# 1) DXF de Polycam -> borrador JSON intermedio (revisable)
dart tools/mapa_importer.dart parse  --in escaneo.dxf  --out borrador_mapa.json
# 2) borrador -> SVG limpio (muros + puertas), escala 100 px = 1 m
dart tools/mapa_importer.dart build  --in borrador_mapa.json  --out fisc_piso4.svg
```

- `parse` reconoce las entidades por **capa** del DXF de Polycam (p. ej. `Poly-Walls`, `Poly-Doors`, `Poly-Windows`), extrae sus polígonos, deriva `mapa_ancho_metros`/`mapa_alto_metros` del bounding box y opcionalmente verifica contra el CSV.
- `build` dibuja muros como polígonos rellenos, abre los huecos de puerta, deduplica y recorta al bounding box. **No** escribe etiquetas ni medidas.

### `tools/editor_mapa.html`

Se abre directo en el navegador. Carga `borrador_mapa.json` y el SVG; tres modos:

| Modo | Acción |
|------|--------|
| **Balizas** | Colocar/arrastrar balizas; exporta a `beacon_config.json → beacons[]` |
| **Nodos** | Colocar nodos con tipo (SALON, BANO, ENTRADA, INTERSECCION…), nombre y `accesible` |
| **Aristas** | Click nodo→nodo para conectar; la distancia euclidiana se calcula sola |

Exporta `mapa.svg`, `grafo.json` y `beacon_config.json`. Los nodos se colorean por tipo para revisión visual.

### Cierre

Pegar los archivos generados (tras revisión) y correr `dart tools/grafo_editor.dart validar-mapa` ([ADR-0007](0007-validacion-cruzada-mapa-grafo.md)) para confirmar coherencia SVG ↔ grafo antes de runtime.

## Consecuencias

### Positivas

- **Levantamiento mucho más rápido** y con escala métrica correcta de origen.
- **Sin dependencias nuevas** y sin acoplar las herramientas a Flutter.
- **Geometría reproducible, semántica con criterio humano** — cada cosa en su herramienta.
- Los artefactos van a revisión (no se sobrescriben archivos protegidos a ciegas).

### Negativas

- Depende de la **calidad del escaneo Polycam** y de que las **capas del DXF** estén bien nombradas; un escaneo sucio exige limpieza manual.
- La detección de puertas se basa en la capa de puertas del DXF; si Polycam no la separa bien, hay que ajustar a mano en el editor.
- **No hay auto-sugerencia de balizas** (queda manual) — ver Alternativa A.
- El editor HTML es una herramienta interna sin tests automatizados (se validó con `node --check` la sintaxis JS).

### Mitigaciones

- Documentar el flujo y los nombres de capa esperados en `docs/` (formato de mapas).
- El paso `validar-mapa` atrapa incoherencias métricas antes del runtime.
- La heurística de balizas se puede incorporar luego sin romper el pipeline (es un paso opcional sobre el borrador).

## Referencias

- [ADR-0005](0005-grafo-editor-cli.md) — GrafoEditor como CLI en Dart
- [ADR-0006](0006-formato-mapa-svg-metrico.md) — formato de mapas SVG métrico
- [ADR-0007](0007-validacion-cruzada-mapa-grafo.md) — validación cruzada SVG ↔ grafo
- [ADR-0009](0009-pinning-dependencias.md) — política de dependencias
- Especificación DXF de AutoCAD (entidades `LINE`, `LWPOLYLINE`; agrupación por capa)
