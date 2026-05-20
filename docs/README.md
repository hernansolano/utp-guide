# Documentación técnica — UTP-Guide

Esta carpeta contiene la documentación técnica del proyecto. El `README.md` raíz es la presentación pública; estos documentos son la referencia interna para desarrolladores que mantienen o extienden el sistema.

## Índice

| Documento | Propósito |
|-----------|-----------|
| [`architecture.md`](architecture.md) | Visión general de la arquitectura del sistema, capas, flujos de datos y decisiones estructurales |
| [`positioning-ble.md`](positioning-ble.md) | Cómo funciona el posicionamiento BLE: modelo de path-loss, trilateración, filtros, snap-to-graph |
| [`grafo-format.md`](grafo-format.md) | Especificación del formato `grafo.json` + uso del GrafoEditor CLI |
| [`setup-beacons.md`](setup-beacons.md) | Procedimiento de instalación física de balizas y calibración en campo |
| [`adr/`](adr/README.md) | Architecture Decision Records — decisiones técnicas con contexto y justificación |

## Convención

Los ADRs (Architecture Decision Records) siguen el formato propuesto por Michael Nygard. Cada decisión técnica relevante se documenta con:

1. **Contexto** — el problema o la situación que motivó la decisión
2. **Decisión** — qué se decidió hacer
3. **Consecuencias** — implicaciones positivas y negativas

Los ADRs son inmutables una vez aceptados. Si una decisión se revierte, se crea un nuevo ADR que supersede al anterior, no se edita el original.

## Para reviewers académicos / industriales

- La arquitectura general está en [`architecture.md`](architecture.md)
- El algoritmo de posicionamiento (lo más técnico del proyecto) está en [`positioning-ble.md`](positioning-ble.md)
- Los trade-offs y por qués están en [`adr/`](adr/README.md)
- El procedimiento experimental para calibrar el sistema está en [`setup-beacons.md`](setup-beacons.md)
