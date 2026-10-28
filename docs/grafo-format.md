# Formato del grafo — `grafo.json`

El archivo `assets/data/grafo.json` describe la planta del edificio como un grafo no dirigido: nodos (puntos de interés y intersecciones) y aristas (segmentos navegables que los conectan).

## Estructura del archivo

```json
{
  "version": "1.0",
  "piso": 1,
  "edificio": "FISC",
  "origen_descripcion": "Esquina superior izquierda del SVG, en metros",
  "mapa_svg": "assets/maps/fisc_piso3.svg",
  "mapa_ancho_metros": 32.5,
  "mapa_alto_metros": 18.0,
  "nodos": [...],
  "aristas": [...]
}
```

### Metadatos

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `version` | string | Versión del esquema del grafo |
| `piso` | int | Identificador del piso (1, 2, 3, ...) |
| `edificio` | string | Código del edificio ("FISC", "TEST") |
| `mapa_svg` | string | Ruta al SVG que representa visualmente este grafo (obligatorio: sin él, `GrafoRepository` rechaza el grafo) |
| `recintos_json` | string (opcional) | Ruta al plano de recintos (polígonos de salones, oficinas, baños y pasillos, en metros). Si está, la app pinta y deja tocar los recintos; si no, solo dibuja el SVG. Ver [ADR-0013](adr/0013-plano-oficial-recintos.md) |
| `mapa_ancho_metros` | double | Ancho real del piso en metros |
| `mapa_alto_metros` | double | Alto real del piso en metros |

Las dimensiones se usan para convertir coordenadas del grafo (metros) a píxeles del SVG.

> **Importante:** el SVG referenciado en `mapa_svg` debe seguir el formato definido en [`map-format.md`](map-format.md). Específicamente: viewBox `0 0 (ancho_metros × 100) (alto_metros × 100)`, escala fija 100 px = 1 m, origen top-left. El comando `validar-mapa` del GrafoEditor verifica esta coherencia.

## Nodos

Cada nodo es un punto en el plano (x, y) con un tipo. Los tipos definen cómo aparece el nodo en el buscador y qué icono recibe.

```json
{
  "id": "salon_312",
  "nombre": "Salón 312",
  "tipo": "SALON",
  "x": 12.5,
  "y": 8.0,
  "piso": 3,
  "accesible": true,
  "aruco_id": null
}
```

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | string | Identificador único en todo el grafo |
| `nombre` | string | Nombre humano (se muestra en la UI) |
| `tipo` | string | Uno de: `ENTRADA`, `SALON`, `BANO`, `OFICINA`, `BEBEDERO`, `COMEDOR`, `ASCENSOR`, `ESCALERA`, `INTERSECCION`, `MARCADOR_AR` |
| `x`, `y` | double | Coordenadas en metros desde la esquina superior izquierda |
| `piso` | int | Debe coincidir con el `piso` del archivo |
| `accesible` | bool | Si el nodo es alcanzable para usuarios con movilidad reducida |
| `aruco_id` | int? | Solo para `MARCADOR_AR`: ID del marcador físico ArUco asociado |

### Tipos de nodo

- **`ENTRADA`** — punto de inicio típico de una navegación. El grafo debe tener al menos uno.
- **`INTERSECCION`** — punto interno de pasillo, no aparece en el buscador (es un waypoint).
- **`SALON`, `BANO`, `OFICINA`, `BEBEDERO`, `COMEDOR`** — destinos reales.
- **`ASCENSOR`, `ESCALERA`** — transiciones entre pisos.
- **`MARCADOR_AR`** — marcador ArUco para inicializar coordenadas en Fase 3. Requiere `aruco_id`.

## Aristas

Cada arista conecta dos nodos. El grafo se trata como **no dirigido**: el repositorio agrega automáticamente la arista inversa al cargar.

```json
{
  "origenId": "salon_312",
  "destinoId": "pasillo_norte_3",
  "distancia": 4.2,
  "tipoObstaculo": "NINGUNO",
  "accesible": true
}
```

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `origenId` | string | ID del nodo de origen (debe existir en `nodos[]`) |
| `destinoId` | string | ID del nodo de destino (debe existir en `nodos[]`) |
| `distancia` | double | Distancia en metros — debe ser positiva |
| `tipoObstaculo` | string | Uno de: `NINGUNO`, `ESCALERA`, `RAMPA`, `PUERTA_PESADA` |
| `accesible` | bool | Si la arista es transitable para usuarios con movilidad reducida |

El campo `accesible` se usa por el `RoutingService` para filtrar aristas antes de correr A* cuando el usuario eligió perfil accesible.

## Validación

`GrafoRepository._validar()` se ejecuta al cargar el archivo y rechaza:

1. IDs de nodo duplicados
2. Aristas que referencian nodos inexistentes
3. Aristas con distancia ≤ 0
4. Nodos `MARCADOR_AR` sin `aruco_id`
5. Grafos sin al menos un nodo `ENTRADA`

Si la validación falla, la app lanza `GrafoInvalidoException` con un mensaje descriptivo.

## GrafoEditor (CLI)

Editar `grafo.json` manualmente es propenso a errores: IDs duplicados, distancias inconsistentes, validación rota. Por eso existe el **GrafoEditor**, un script CLI en Dart puro que mantiene la integridad del archivo.

### Uso

Desde la raíz del proyecto:

```bash
# Listar todos los nodos
dart tools/grafo_editor.dart list-nodos

# Listar todas las aristas
dart tools/grafo_editor.dart list-aristas

# Agregar un nodo
dart tools/grafo_editor.dart add-nodo \
  --id=salon_402 \
  --nombre="Salón 402" \
  --tipo=SALON \
  --x=15.3 \
  --y=6.0 \
  --piso=4 \
  --accesible=true

# Agregar una arista
dart tools/grafo_editor.dart add-arista \
  --origen=salon_402 \
  --destino=pasillo_norte_4 \
  --dist=3.5 \
  --accesible=true

# Eliminar un nodo (también elimina sus aristas)
dart tools/grafo_editor.dart remove-nodo --id=salon_402

# Eliminar una arista específica
dart tools/grafo_editor.dart remove-arista --origen=A --destino=B

# Validar el grafo sin modificarlo
dart tools/grafo_editor.dart validar
```

### Reglas de seguridad

- **Backup automático:** antes de cada escritura, el editor copia `grafo.json` a `grafo.backup.json` en la misma carpeta. Solo se mantiene el último backup.
- **Validación antes de guardar:** si la operación resulta en un grafo inválido, no se escribe.
- **Idempotencia:** `add-nodo` con un ID existente rechaza la operación en lugar de duplicar.

Ver [ADR-0005](adr/0005-grafo-editor-cli.md) para por qué se eligió CLI en lugar de pantalla in-app.

## Convenciones de modelado

Cuando se mapea un piso nuevo:

1. **Origen `(0, 0)` en la esquina superior izquierda** del plano (no inferior izquierda — coincide con el sistema de coordenadas SVG)
2. **Unidades en metros reales**, con un decimal de precisión (10 cm es suficiente para navegación humana)
3. **Densidad de nodos `INTERSECCION`** suficiente para que A* genere caminos curvos en pasillos — típicamente uno cada 5-8 metros en pasillos rectos, uno en cada esquina
4. **Distancias de aristas medidas físicamente** o calculadas euclidianamente entre nodos; no estimadas a ojo
5. **`accesible: false` solo cuando hay obstáculo físico real** (escaleras sin rampa, puertas muy pesadas sin botón automático)
