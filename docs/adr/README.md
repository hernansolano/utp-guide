# Architecture Decision Records (ADRs)

Esta carpeta contiene el registro inmutable de decisiones técnicas relevantes del proyecto.

## ¿Qué es un ADR?

Un Architecture Decision Record documenta una decisión técnica con tres elementos:

1. **Contexto** — qué situación o problema motivó la decisión
2. **Decisión** — qué se decidió hacer (y opcionalmente qué alternativas se descartaron)
3. **Consecuencias** — implicaciones positivas y negativas de la decisión

Los ADRs son **inmutables**. Si una decisión se revierte o evoluciona, se crea un nuevo ADR que supersede al anterior, indicándolo en el frontmatter de ambos.

## Estados

- `aceptado` — vigente
- `superseded por ADR-XXXX` — reemplazado
- `obsoleto` — ya no aplica (sin reemplazo)

## Índice

| # | Título | Estado | Fecha |
|---|--------|--------|-------|
| [0001](0001-centroide-ponderado.md) | Centroide ponderado vs trilateración matricial | aceptado | 2026-05-17 |
| [0002](0002-parametros-path-loss.md) | Parámetros de path-loss para edificio FISC | aceptado | 2026-05-19 |
| [0003](0003-snap-to-graph-aristas.md) | Snap-to-graph por aristas en lugar de nodos | aceptado | 2026-05-17 |
| [0004](0004-permisos-runtime.md) | Uso de `permission_handler` para permisos BLE en runtime | aceptado | 2026-05-19 |
| [0005](0005-grafo-editor-cli.md) | GrafoEditor como CLI en Dart en lugar de pantalla in-app | aceptado | 2026-05-19 |
| [0006](0006-formato-mapa-svg-metrico.md) | Formato de mapas: SVG vectorial con escala métrica fija | aceptado | 2026-05-19 |
| [0007](0007-validacion-cruzada-mapa-grafo.md) | Validación cruzada entre el SVG del mapa y `grafo.json` | aceptado | 2026-05-19 |
| [0008](0008-simulador-ble-para-testing.md) | Simulador BLE para testing sin hardware físico | aceptado | 2026-05-20 |
| [0009](0009-pinning-dependencias.md) | Política de pinning de dependencias y auditoría de seguridad | aceptado | 2026-05-20 |

## Cómo crear un nuevo ADR

1. Copiar el formato de un ADR existente
2. Numerar secuencialmente (el siguiente sería `0006-...`)
3. Usar nombres en kebab-case descriptivos
4. Agregarlo a la tabla de arriba
5. Commit con mensaje `[ADR-XXXX] título de la decisión`
