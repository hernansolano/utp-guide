# ADR-0005 — GrafoEditor como CLI en Dart en lugar de pantalla in-app

- **Estado:** aceptado
- **Fecha:** 2026-05-19
- **Autor:** equipo UTP-Guide

## Contexto

Las convenciones del proyecto establecen una regla absoluta:

> NO modificar `grafo.json` directamente. Existe un `GrafoEditor` para eso.

Sin embargo, el GrafoEditor nunca se implementó. Cada vez que ha sido necesario agregar o modificar nodos, se ha editado el JSON manualmente — violando la regla y exponiendo al proyecto a errores: IDs duplicados, aristas que referencian nodos inexistentes, distancias incorrectas o cero, formato JSON inválido.

Hay dos formas razonables de implementar el GrafoEditor:

### Opción A — Pantalla in-app

Una pantalla en Flutter que muestra el grafo, permite agregar/mover/eliminar nodos y aristas con tap y drag, y guarda los cambios.

### Opción B — CLI en Dart puro

Un script que se corre desde terminal, con comandos como `add-nodo`, `add-arista`, `validar`.

## Decisión

Implementar la **opción B: CLI en Dart** (`tools/grafo_editor.dart`).

## Justificación

### El editor lo usa el desarrollador, no el usuario final

UTP-Guide es una app de **navegación** para estudiantes. El grafo se modela una vez (por el equipo de desarrollo) y se actualiza ocasionalmente cuando cambia el edificio. **Ningún usuario final necesita editar el grafo.**

Una pantalla in-app desperdiciaría:

- Tiempo de desarrollo significativo (estimado: 2-3 días para una pantalla decente)
- Pixel real estate en la app de producción
- Complejidad adicional en el ciclo de vida (permisos de escritura en assets en runtime, etc.)

### Workflow real de modelado del grafo

El levantamiento de un piso nuevo es:

1. Equipo con cinta métrica camina el piso
2. Anota nodos en una libreta o hoja Excel
3. Calcula distancias entre nodos
4. Carga la información al grafo

El paso 4 con CLI:

```bash
dart tools/grafo_editor.dart add-nodo --id=sala_310 --nombre="Salón 310" --tipo=SALON --x=12.5 --y=8.0 --piso=3
dart tools/grafo_editor.dart add-arista --origen=sala_310 --destino=pasillo_norte_3 --dist=3.5
```

Esto es:

- **Reproducible** — se puede guardar el script de comandos y rehacer todo el levantamiento si algo falla
- **Diffable** — el JSON resultante va a git, los cambios son revisables en PR
- **Testeable** — el script se puede unit-test con datos de entrada/salida conocidos
- **Sin acoplamiento con Flutter** — el script no depende de `package:flutter`, solo de Dart stdlib

### Validación = misma que la app

El editor reusa `lib/data/repositories/grafo_repository.dart` para validar el grafo después de cada operación. Esto garantiza que la lógica de validación **no diverge** entre el editor y la app.

## Implementación

`tools/grafo_editor.dart` es un script Dart estándar que se ejecuta como:

```bash
dart tools/grafo_editor.dart <comando> [argumentos...]
```

Comandos disponibles:

| Comando | Descripción |
|---------|-------------|
| `list-nodos` | Imprime una tabla de todos los nodos |
| `list-aristas` | Imprime una tabla de todas las aristas |
| `add-nodo` | Agrega un nodo con los argumentos dados |
| `remove-nodo` | Elimina un nodo y todas sus aristas |
| `add-arista` | Agrega una arista entre dos nodos existentes |
| `remove-arista` | Elimina una arista específica |
| `validar` | Corre las validaciones sin modificar el archivo |
| `--help` | Muestra esta lista de comandos |

### Reglas de seguridad implementadas

1. **Backup automático antes de escribir:** `grafo.json` se copia a `grafo.backup.json` antes de cualquier modificación. El último backup se sobrescribe en cada operación.
2. **Validación antes de escribir:** si la operación deja el grafo inválido, no se escribe nada.
3. **Idempotencia:** `add-nodo` con un ID existente rechaza la operación.
4. **Mensajes claros:** errores describen el problema concreto, no stack traces.

## Consecuencias

### Positivas

- Cumple la regla del proyecto sin construir UI compleja
- Workflow reproducible y versionable
- Validación consistente con la lógica de la app
- Documentable como parte del procedimiento operativo (en `docs/grafo-format.md`)

### Negativas

- Aún requiere que el desarrollador esté familiarizado con la línea de comandos
- No tiene visualización del grafo — para verificar visualmente hay que correr la app o abrir el SVG aparte

### Mitigaciones

- El comando `list-nodos` imprime una tabla formateada que es legible y diffable
- Para visualización, el SVG del mapa muestra los nodos manualmente (en el caso de prueba 5×5)

## Referencias

- 12-Factor App, factor III (Config): https://12factor.net/config — argumento general por configuración vía archivo en lugar de UI
- Migrations en Django/Rails — patrón similar de scripts versionables para datos de dominio
