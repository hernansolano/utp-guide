# ADR-0007 — Validación cruzada entre el SVG del mapa y el `grafo.json`

- **Estado:** aceptado
- **Fecha:** 2026-05-19
- **Autor:** equipo UTP-Guide

## Contexto

[ADR-0006](0006-formato-mapa-svg-metrico.md) define que cada piso se modela con dos archivos:

1. Un SVG vectorial en `assets/maps/<edificio>_<piso>.svg`
2. Un archivo `assets/data/grafo.json` con los nodos y aristas, más las dimensiones del piso en metros (`mapa_ancho_metros`, `mapa_alto_metros`)

El SVG y el JSON **deben permanecer coherentes**:

- El viewBox del SVG debe coincidir con `mapa_ancho_metros × 100` y `mapa_alto_metros × 100`
- Todas las coordenadas `(x, y)` de los nodos del grafo deben estar dentro de las dimensiones declaradas
- La ruta del SVG declarada en `mapa_svg` debe existir como archivo

Si estas condiciones no se cumplen, la app no falla con una excepción clara — falla **silenciosamente**: los nodos quedan desplazados respecto a las paredes, el punto del usuario aparece fuera del piso, o el SVG simplemente no se renderiza. Estos errores son fáciles de introducir (alguien edita el grafo sin actualizar el SVG, o viceversa) y difíciles de diagnosticar visualmente porque "casi funciona".

## Decisión

Agregar un comando `validar-mapa` al `GrafoEditor` (`tools/grafo_editor.dart`) que verifique la coherencia entre el SVG declarado en `grafo.json` y los datos del grafo, antes de que esos errores lleguen a runtime.

El comando se corre desde la raíz del proyecto:

```bash
dart tools/grafo_editor.dart validar-mapa
```

Reporta cada inconsistencia detectada con un mensaje accionable. Si todo está bien, imprime un resumen del piso modelado.

### Qué verifica

1. **Existencia del SVG.** El archivo declarado en `mapa_svg` debe existir en disco.
2. **Estructura del viewBox.** Debe parsear como cuatro números con `min-x = 0` y `min-y = 0`.
3. **Coherencia de dimensiones.** `viewBox_ancho` debe ser igual a `mapa_ancho_metros × 100`, con tolerancia de ±1 px (para absorber redondeos en SVG editors). Idem alto.
4. **Nodos dentro del piso.** Cada nodo del grafo debe tener `0 ≤ x ≤ mapa_ancho_metros` y `0 ≤ y ≤ mapa_alto_metros`.

### Qué NO verifica

- La geometría interna del SVG (paredes, puertas). Validar eso requeriría parsear todos los paths y reconocer formas arquitectónicas, lo cual está fuera de alcance.
- Que las aristas del grafo correspondan a pasillos reales del SVG. Eso solo se puede verificar visualmente abriendo la app.
- Las propiedades visuales del SVG (paleta de colores, estilos). Esas son convención documental, no validables automáticamente.

## Alternativas consideradas

### Alternativa A — Validación en runtime al cargar el repositorio

Hacer que `GrafoRepository` valide la coherencia al cargar el JSON y lance una excepción si falla.

**Descartada porque:**

- El SVG se carga en otro punto del código (`SvgPicture.asset` en `MapaScreen`), no en el repositorio
- Parsear el SVG con `flutter_svg` solo para extraer el viewBox es ineficiente
- La validación correcta es **antes** del runtime: al editar el grafo o el SVG, no cuando un usuario abre la app

### Alternativa B — Test unitario en `test/`

Escribir un test que cargue el SVG y el grafo y compare. Correr como parte de `flutter test`.

**Parcialmente válida.** El test debería existir además del comando CLI (Fase 1+). Pero el CLI tiene ventajas adicionales:

- Se puede correr durante el levantamiento del piso, no requiere SDK de Flutter
- Da feedback inmediato al editar el grafo con `add-nodo`
- Sirve como precondición de CI/CD eventual

Decisión: ambos. El CLI ahora, el test cuando se escriban los tests unitarios de Fase 1.

### Alternativa C — Hook de git pre-commit

Correr `validar-mapa` automáticamente antes de cada commit, rechazando commits con grafos inválidos.

**No descartada, postergada.** Es una mejora razonable cuando el proyecto tenga más colaboradores. Por ahora, ejecutar el comando manualmente es suficiente porque el equipo es pequeño.

## Consecuencias

### Positivas

- **Detecta inconsistencias antes del runtime**, donde son baratas de corregir
- **Mensajes accionables:** "El viewBox dice 3200 px pero `mapa_ancho_metros: 32.5` implica 3250 px. Diferencia: 50 px" — el desarrollador sabe exactamente qué arreglar.
- **No requiere abrir la app** para verificar que un cambio al grafo está bien
- **Reproducible y scriptable.** Se puede integrar en CI/CD en el futuro

### Negativas

- **Falsos sentido de seguridad.** El comando valida coherencia métrica pero no que las aristas correspondan a pasillos reales del SVG. Un grafo "validado" puede aún tener errores semánticos.
- **Duplicación de lógica.** El parser de SVG en `grafo_editor.dart` no usa `flutter_svg` (requeriría arrastrar Flutter al tool). Usa regex para extraer el viewBox. Esto funciona porque solo necesitamos un atributo, pero si en algún momento queremos validar más cosas del SVG hay que reconsiderar.

### Mitigaciones

- Para el primer punto: documentar explícitamente en `docs/map-format.md` que `validar-mapa` no reemplaza la verificación visual de abrir la app.
- Para el segundo: el regex está concentrado en una función con comentario explicativo. Si el día de mañana necesitamos parsear más, refactorizar a un mini-parser XML o evaluar mover el comando a un tool separado que sí dependa de Flutter.

## Referencias

- [`docs/map-format.md`](../map-format.md) — spec del formato de mapas, sección de validación
- [ADR-0005](0005-grafo-editor-cli.md) — decisión original del GrafoEditor como CLI
- [ADR-0006](0006-formato-mapa-svg-metrico.md) — decisión del formato SVG métrico
