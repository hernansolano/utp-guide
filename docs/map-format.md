# Formato de mapas — Spec técnica

Este documento define el formato exacto en que se modela cada piso del edificio. Es **obligatorio** para todos los SVG de planta que se agreguen al proyecto.

El objetivo es que cualquier persona pueda agregar un piso nuevo en `assets/maps/` sin que la app se rompa visualmente y sin que los nodos del grafo queden desalineados con respecto a las paredes.

## Por qué SVG vectorial y no PNG

Razonado en detalle en [`adr/0006-formato-mapa-svg-metrico.md`](adr/0006-formato-mapa-svg-metrico.md). Resumen:

- **Vector escala sin pérdida.** En la pantalla del teléfono el mapa puede zoom in/out sin pixelar.
- **Editable.** Un colaborador con Inkscape o Figma puede mover una pared, agregar una puerta, ajustar una etiqueta. Un PNG requiere repetir todo el levantamiento.
- **Selectivamente renderizable.** Podemos esconder o mostrar capas (números de salones, mobiliario, etc.) sin recompilar el SVG.
- **Compatible con Flutter** vía `flutter_svg`, ya en el `pubspec.yaml`.

## Convenciones obligatorias

Todas estas son **requeridas**, no recomendadas. El comando `validar-mapa` del GrafoEditor las verifica automáticamente.

### Escala

```
100 píxeles SVG = 1 metro real
```

Esta es la única escala aceptada en el proyecto. Mantenerla constante simplifica la lógica de conversión en `MapaPainter` y permite intercambiar SVGs entre pisos sin recalibrar.

### Sistema de coordenadas

```
Origen:  esquina superior izquierda del piso = (0, 0)
Eje X:   positivo hacia la derecha (este)
Eje Y:   positivo hacia abajo (sur)
Unidad:  metros en grafo.json, píxeles en SVG (relacionados por la escala)
```

El eje Y hacia abajo es la convención SVG estándar y coincide con la convención de coordenadas de pantalla de Flutter. No invertir.

### ViewBox

El SVG **debe** tener un viewBox de la forma:

```xml
<svg viewBox="0 0 (ancho_metros × 100) (alto_metros × 100)" ...>
```

Por ejemplo, para un piso de 32.5 × 18.0 metros:

```xml
<svg viewBox="0 0 3250 1800" width="3250" height="1800" ...>
```

- `min-x` y `min-y` siempre **0**. Nunca usar offsets.
- `width` y `height` en píxeles, coincidentes con el viewBox.

### Coherencia con `grafo.json`

El JSON del piso debe declarar las mismas dimensiones:

```json
{
  "mapa_svg": "assets/maps/fisc_piso3.svg",
  "mapa_ancho_metros": 32.5,
  "mapa_alto_metros": 18.0,
  ...
}
```

Si el viewBox del SVG dice `0 0 3250 1800` pero el JSON dice `mapa_ancho_metros: 30.0`, los nodos quedan en posiciones incorrectas. **El comando `validar-mapa` rechaza esto.**

## Anatomía de un SVG de planta

Un SVG de piso bien estructurado tiene **capas** (`<g>` con `id`) en este orden, de fondo a frente:

```
1. Fondo del piso              — relleno claro, ocupa todo el viewBox
2. Paredes externas            — el perímetro del edificio o sección
3. Paredes internas            — divisiones entre cuartos
4. Puertas                     — aperturas con arco indicador
5. Escaleras / ascensores      — íconos o áreas marcadas
6. Etiquetas de cuartos        — texto con número de salón, baño, etc.
7. (Opcional) Mobiliario       — si aporta orientación
8. (Opcional) Grid de metros   — para autoría, oculta en producción
```

Capa 8 (grid) es útil mientras se dibuja pero **debe eliminarse** del archivo final que se commitea. Los nodos de navegación **no se dibujan en el SVG** — los pinta `MapaPainter` en runtime.

Ver `assets/maps/_template.svg` para una plantilla con estas capas ya estructuradas.

## Paleta visual recomendada

Todos los pisos deben verse coherentes. Si alguien dibuja un SVG con paredes púrpura, rompe la identidad de la app.

| Elemento | Color hex | Notas |
|----------|-----------|-------|
| Fondo del piso | `#F5F5F0` | Crema neutro, no compite con la ruta |
| Paredes | `#2C2C2A` | Casi negro, máxima legibilidad |
| Puertas (línea) | `#888780` | Gris medio |
| Arco de apertura | `#2C2C2A` dashed | Indicador estándar arquitectónico |
| Texto de etiquetas | `#444441` | Casi negro, no compite con la ruta |
| Grid (solo autoría) | `#CCCCCC` dashed | Se elimina al exportar |

Los colores de la **ruta** y el **punto de usuario** los aporta `MapaPainter` desde el tema (`app_theme.dart`) y no van en el SVG.

## Workflow de autoría de un piso nuevo

### 1. Levantamiento físico

Antes de dibujar, hay que tener las medidas reales:

- Longitudes externas del piso (largo × ancho) con cinta métrica o medidor láser
- Ubicación de cada cuarto relevante: número, posición de la puerta, dimensiones aproximadas
- Identificar entradas principales, salidas de emergencia, escaleras, ascensores
- Si hay planos arquitectónicos del edificio en formato CAD/PDF, pedirlos al departamento — ahorra horas

Salida del paso: una hoja Excel o libreta con todas las medidas.

### 2. Preparación del template

Copia `assets/maps/_template.svg` a `assets/maps/<edificio>_<piso>.svg`. Por ejemplo:

```
assets/maps/fisc_piso3.svg
```

### 3. Ajustar el viewBox

Abrir el SVG en un editor de texto y reemplazar el viewBox por las dimensiones reales del piso × 100:

```xml
<svg viewBox="0 0 3250 1800" width="3250" height="1800" ...>
```

### 4. Dibujar las paredes

Abrir el SVG en **Inkscape** (recomendado) o Figma. Configurar:

- Unidades del documento: píxeles
- Snap a grid cada 50 px (= 0.5 m)
- Mostrar el grid de referencia (capa 8 del template)

Dibujar:

1. Paredes externas (rectángulo del perímetro)
2. Paredes internas
3. Puertas (líneas + arco indicador)

Usar el grosor estándar: `8 px` para paredes externas, `6 px` para internas.

### 5. Agregar etiquetas

Con la herramienta de texto, marcar el número/nombre de cada cuarto en su centro aproximado.

### 6. Limpiar el archivo

Antes de exportar:

- Eliminar la capa de grid (`#grid-referencia`)
- Eliminar cualquier objeto fuera del viewBox
- En Inkscape: **Archivo → Guardar como → SVG plano** (no SVG de Inkscape, que agrega metadata innecesaria)

### 7. Crear el `grafo.json` correspondiente

Si es un piso nuevo, copiar la estructura del `grafo.json` actual y ajustar:

```json
{
  "version": "1.0",
  "piso": 3,
  "edificio": "FISC",
  "mapa_svg": "assets/maps/fisc_piso3.svg",
  "mapa_ancho_metros": 32.5,
  "mapa_alto_metros": 18.0,
  "nodos": [],
  "aristas": []
}
```

### 8. Agregar nodos con el GrafoEditor

Desde la terminal, en la raíz del proyecto:

```bash
dart tools/grafo_editor.dart add-nodo \
  --id=entrada_principal \
  --nombre="Entrada principal" \
  --tipo=ENTRADA \
  --x=16.2 \
  --y=0.5 \
  --piso=3
```

Las coordenadas se sacan del SVG: abrirlo en Inkscape, mover el cursor al punto de interés, leer las coordenadas (en píxeles) y dividir entre 100 para obtener metros.

### 9. Validar

```bash
dart tools/grafo_editor.dart validar-mapa
```

Este comando verifica:

- Que el SVG existe en la ruta declarada
- Que el viewBox coincide con `mapa_ancho_metros × 100 × mapa_alto_metros × 100`
- Que todos los nodos del grafo están dentro de las dimensiones declaradas
- Que el viewBox empieza en `0 0`

Si hay inconsistencias, reporta exactamente qué corregir.

### 10. Verificación visual

Correr la app (`flutter run`), navegar a la pantalla de mapa, y confirmar que las paredes se ven bien y los nodos caen donde corresponden.

## Errores comunes

### viewBox que no empieza en 0,0

```xml
<!-- mal -->
<svg viewBox="-100 -50 500 500" ...>
```

`MapaPainter` asume que el origen es `(0, 0)`. Un viewBox con offset desplaza todos los nodos visualmente.

### SVG con `width` y `height` distintos al viewBox

```xml
<!-- mal -->
<svg viewBox="0 0 500 500" width="100" height="100" ...>
```

Algunos renderers respetan `width`/`height` y otros el viewBox. Para evitar ambigüedad: que coincidan exactamente.

### Coordenadas del grafo en píxeles

Las coordenadas en `grafo.json` están **en metros**. Un error común es poner `x: 250, y: 250` cuando se quería decir `x: 2.5, y: 2.5`. El validador no puede detectar esto porque 250 m podría ser legítimo en un edificio grande — siempre verificar visualmente.

### Inkscape SVG en lugar de Plain SVG

Inkscape SVG incluye metadata propietaria (`inkscape:label`, `sodipodi:namedview`) que `flutter_svg` puede no parsear correctamente. Siempre exportar como **Plain SVG**.

### Texto convertido a paths innecesariamente

Convertir texto a paths (Inkscape: Camino → Objeto a camino) infla el SVG y rompe accesibilidad. Solo hacerlo si la app va a renderizar en un dispositivo sin la fuente. Por defecto, dejar el texto como `<text>`.

### Capas con `display: none` o `visibility: hidden`

`flutter_svg` puede o no respetar estas propiedades según la versión. Mejor eliminar las capas que no se quieren mostrar.

## Referencias

Para entender el contexto técnico de las decisiones aquí documentadas:

- [ADR-0006: Formato SVG métrico fijo](adr/0006-formato-mapa-svg-metrico.md) — por qué SVG y no IMDF, IndoorGML, o raster
- [ADR-0007: Validación cruzada mapa/grafo](adr/0007-validacion-cruzada-mapa-grafo.md) — por qué el GrafoEditor verifica coherencia entre SVG y JSON
- [`grafo-format.md`](grafo-format.md) — formato de `grafo.json`
- [`positioning-ble.md`](positioning-ble.md) — cómo `MapaPainter` usa estas dimensiones para dibujar la ruta

## Comparación con la industria

Para reviewers que quieran contexto:

- **Apple IMDF**: GeoJSON con coordenadas WGS84 (lat/lon). Pensado para venues comerciales (aeropuertos, malls) con miles de unidades. Sobre-ingeniería para 1 edificio universitario.
- **OGC IndoorGML**: XML con capas topológicas. Spec de ~50 páginas, herramientas escasas. Académico.
- **OpenStreetMap SIT** (Simple Indoor Tagging): extiende OSM con `level=*`, `indoor=room`. Requiere subir el edificio a OSM y traer todo el stack OSM en el cliente.
- **Mapbox Indoor / Esri Indoor**: comercial, requiere licencia o cuenta en su plataforma.
- **MIT Mobile, Stanford Maps, varios proyectos universitarios**: SVG + grafo en JSON aparte. **Este es exactamente el approach que adoptamos.**

La conclusión es que para 1 edificio en un proyecto estudiantil, el approach SVG + JSON con escala fija es la ingeniería correcta: ligero, editable con herramientas libres, sin dependencias externas.
