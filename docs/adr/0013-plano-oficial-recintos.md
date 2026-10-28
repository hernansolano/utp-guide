# ADR-0013 — Mapa del piso desde el plano oficial + recintos interactivos

- **Estado:** aceptado
- **Fecha:** 2026-10-27
- **Autor:** equipo UTP-Guide
- **Complementa:** [ADR-0006](0006-formato-mapa-svg-metrico.md), [ADR-0010](0010-map-view-widget.md), [ADR-0012](0012-pipeline-importacion-mapas.md)

## Contexto

El mapa del piso 4 (`plano_piso4_app.svg`) era un boceto hecho en draw.io: unos 109,5 × 60,3 m, cuando el edificio real mide alrededor de 125 × 77 m. Además era una imagen estática: no se podía tocar un salón, no se adaptaba al modo oscuro y los nombres no se podían leer.

La Dirección General de Ingeniería y Arquitectura de la UTP entregó el plano oficial del edificio 3, tercer alto (= piso 4), como **PDF vectorial a escala 1:250** (hoja ARCH C de 24 × 18 in), con un cuadro de áreas de los 76 recintos.

## Decisión

1. **El mapa se genera desde el PDF oficial**, no se calca. `tools/plano_oficial/extraer_plano.py` (Python, fuera de la app):
   - clasifica los trazos del PDF por grosor (0,96 pt = muros, 1,44 pt = columnas, 0,72/0,6 pt = puertas y muebles, 0,48 pt = ventanas) y los reescribe en metros a 100 px = 1 m;
   - obtiene el polígono de cada recinto por *flood fill* desde su número en el dibujo, cerrando las puertas. **Solo acepta el recinto si su área queda a ±12 % de la del cuadro oficial**, y si el polígono contiene el número. Así se verifica la escala y se descartan los recintos que se "escapan" al pasillo;
   - calcula la circulación como huella del edificio menos muros y recintos.
2. **El SVG solo trae trazos**: fondo transparente y color `currentColor`. `MapView` lo tiñe con `SvgTheme`, según el tema.
3. **Los rellenos y las etiquetas los dibuja la app** desde `assets/data/recintos/<piso>.json`, que el grafo referencia con el campo opcional `recintos_json`. Las capas, de abajo hacia arriba: `RecintosFondoPainter` (pasillos y recintos por tipo), el SVG (muros), `RecintosEtiquetasPainter` (etiquetas y contorno del resaltado) y `MapaPainter` (ruta y punto azul).
4. **Las etiquetas tienen tamaño constante en pantalla** (se contra-escalan con el zoom) y solo se dibujan si caben en su recinto. Los textos se maquetan una sola vez (`EtiquetasRecintosCache`).
5. **Tocar el mapa** primero busca un POI cercano y, si no hay, el recinto que contiene el punto (`PlanoRecintos.recintoEn`, ray casting). "Ir aquí" solo aparece si el recinto tiene `nodo_id`, es decir, si el grafo lo enlaza.
6. El zoom máximo de `MapView` sube solo para planos grandes, hasta garantizar al menos 30 px por metro.

## Verificación

- **Escala:** en 64 recintos, la diferencia de área contra el cuadro oficial tiene una mediana de alrededor de 1,6 %. Los salones 3-401 a 3-410 dan ±1 %.
- **Contra el campo:** el pasillo norte mide 23,64 × 5,79 m en el plano y 23,19 × 5,72 m con láser (EXP2).
- **Tests:** `test/models/recinto_test.dart` cubre el punto en polígono y la sanidad del JSON: ids únicos, todo dentro del mapa, cada etiqueta dentro de su recinto, sin superposiciones y los salones 3-401 a 3-416 presentes.

## Consecuencias

- **Positivas:**
  - el mapa es fiel a la realidad y legible en claro y oscuro;
  - los salones se pueden tocar;
  - regenerar el plano si cambia el PDF es un solo comando.
- **Negativas:**
  - 9 recintos quedan sin polígono (escaleras, ascensor y cuartitos con muebles dibujados encima); muestran su etiqueta, pero no se pueden tocar;
  - el script necesita pymupdf, scipy y contourpy, que no son dependencias de la app;
  - el PDF oficial no se versiona.
- **Pendiente:** el grafo del entorno `piso4_oficial` es mínimo (solo la llegada al piso). Faltan los nodos de pasillo y de puertas, y enlazar cada recinto con su `nodo_id`.
