# ADR-0006 — Formato de mapas: SVG vectorial con escala métrica fija

- **Estado:** aceptado
- **Fecha:** 2026-05-19
- **Autor:** equipo UTP-Guide

## Contexto

UTP-Guide necesita renderizar la planta de cada piso del edificio como fondo del mapa de navegación. Sobre ese fondo se dibujan: la ruta calculada por A*, el punto del usuario en tiempo real, el pin del destino, y eventualmente etiquetas dinámicas.

Las decisiones a tomar son:

1. **Formato del archivo de planta** (vector vs raster, qué tipo de vector)
2. **Sistema de coordenadas** (lat/lon real, coordenadas locales, píxeles)
3. **Escala** (cómo se relacionan las unidades del archivo con metros reales)
4. **Relación con el grafo de navegación** (`grafo.json`)

Estas decisiones afectan: tamaño del APK, calidad visual al hacer zoom, facilidad para agregar pisos nuevos, costo de mantenimiento, compatibilidad con Flutter.

## Opciones consideradas

### Opción A — Raster (PNG/JPG) con matriz de transformación

Guardar la planta como imagen rasterizada y mantener una matriz `pixel → metro` en JSON.

- **Pros:** simple de producir (foto del plano arquitectónico, recortar)
- **Contras:**
  - Pixelado en zoom sobre un teléfono
  - Tamaño del archivo crece con la resolución (un PNG de calidad razonable para un piso completo: 2-5 MB)
  - Editar paredes requiere repetir el levantamiento o usar editor de mapas de bits

### Opción B — SVG vectorial con coordenadas métricas

Guardar la planta como SVG, con la escala fija a `100 px = 1 m` y el origen en `(0, 0)` en la esquina superior izquierda. Las coordenadas del grafo (`grafo.json`) están en metros y la app las convierte a píxeles del SVG en runtime.

- **Pros:** vector escala sin pérdida; editable con Inkscape/Figma; archivos pequeños; capas selectivamente renderizables; compatible con `flutter_svg`
- **Contras:** requiere dibujar las paredes (no se puede "fotografiar" como un PNG); requiere que el equipo aprenda Inkscape o equivalente

### Opción C — Estándar industrial (IMDF / IndoorGML)

Usar un formato pensado específicamente para mapas indoor.

- **IMDF** (Apple): GeoJSON con WGS84, separa venue/building/level/unit. Soportado por Apple Maps. Open standard.
- **IndoorGML** (OGC): XML con capas topológicas y geométricas. Spec de ~50 páginas.
- **Pros:** estándar reconocido, interoperabilidad con otras herramientas
- **Contras:**
  - Diseñados para venues comerciales grandes (aeropuertos, malls) con flujos de personas masivos
  - Requieren coordenadas geográficas reales (lat/lon), no locales
  - Herramientas de autoría escasas o de pago
  - Curva de aprendizaje significativa
  - Funcionalidad muy superior a lo que necesitamos en Fase 1-3

### Opción D — OpenStreetMap Simple Indoor Tagging

Extender el grafo de OSM con etiquetas como `level=*` e `indoor=room`. La planta vive en OSM, no en el proyecto.

- **Pros:** datos públicos, herramientas existentes (iD editor, JOSM), comunidad
- **Contras:**
  - Requiere subir el edificio a OSM (proceso lento, requiere licencia compatible)
  - Trae todo el stack OSM en el cliente (tileserver, librerías de renderizado)
  - Dependencia externa permanente

## Decisión

Adoptar la **Opción B: SVG vectorial con escala métrica fija de 100 px = 1 m**, con origen en `(0, 0)` en la esquina superior izquierda y eje Y hacia abajo.

Spec completa documentada en [`docs/map-format.md`](../map-format.md).

## Justificación

El proyecto modela **un solo edificio** en Fase 1 (FISC), con un solo piso piloto, y eventualmente más pisos del mismo edificio. No es un sistema multi-venue. No interopera con sistemas externos. No requiere geocoding ni búsqueda global de venues.

Para ese alcance, IMDF y IndoorGML son sobre-ingeniería: agregan complejidad, dependencias y curva de aprendizaje sin beneficio funcional concreto. OSM agrega una dependencia externa permanente innecesaria.

Por otro lado, raster (PNG) pixelaría al zoom y haría imposible iterar el dibujo del piso conforme se descubren detalles durante el levantamiento.

SVG vectorial con escala fija es el approach pragmático que adoptan proyectos universitarios similares (MIT Mobile, Stanford Maps, varios europeos): editable con herramientas libres, ligero, integrable directamente con Flutter sin librerías adicionales, y suficientemente preciso para guiar a un humano caminando.

### Por qué escala fija (100 px = 1 m)

Una alternativa habría sido permitir cualquier escala y registrar el factor en `grafo.json`. Se descartó porque:

- Cualquier escala arbitraria invita errores: alguien podría exportar un SVG a 72 dpi pensando que vale como `1 px = 1 mm` y romper todo
- Una escala única simplifica la conversión en `MapaPainter`
- 100 px/m da resolución suficiente para detalles arquitectónicos (10 cm de precisión visual) sin inflar el SVG

## Consecuencias

### Positivas

- **Calidad visual constante** en cualquier zoom o resolución de pantalla
- **Editabilidad** con herramientas libres (Inkscape, Figma free tier)
- **Coherencia entre pisos:** un SVG del piso 3 y otro del piso 4 tienen la misma escala visual
- **Diff-able:** los cambios al SVG se ven en git diff (es XML)
- **Decoupling claro:** SVG = visual, `grafo.json` = lógica de navegación. Cada uno se mantiene independiente

### Negativas

- **Curva de aprendizaje** para colaboradores que no conocen Inkscape/Figma
- **Sin interoperabilidad** con sistemas IMDF/OSM. Si en algún momento futuro el proyecto se integra con Apple Maps Indoor o similar, hay que convertir el formato.
- **Validación necesaria:** el SVG y `grafo.json` pueden divergir silenciosamente si alguien edita uno y olvida el otro. Se mitiga con el comando `validar-mapa` (ver [ADR-0007](0007-validacion-cruzada-mapa-grafo.md)).

### Mitigaciones

- Plantilla `assets/maps/_template.svg` con la estructura correcta ya armada — el primer SVG se hace copiando esto.
- Documentación de autoría paso a paso en [`docs/map-format.md`](../map-format.md).
- Comando `validar-mapa` que rechaza incoherencias antes de que lleguen a runtime.

## Referencias

- W3C SVG 1.1 specification: https://www.w3.org/TR/SVG11/
- `flutter_svg` package docs: https://pub.dev/packages/flutter_svg
- Apple IMDF spec: https://register.apple.com/resources/imdf/
- OGC IndoorGML 1.1: https://www.ogc.org/standards/indoorgml
- "Mobile Indoor Navigation" — Mautz, ETH Zürich (2012), revisión académica de approaches
