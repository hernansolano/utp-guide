# Roadmap

Trabajo pendiente, ordenado por prioridad.

## Mapa del piso 4

- [ ] Grafo de pasillos de `piso4_oficial`: nodos de pasillo, un nodo de puerta por recinto y
      enlace `nodo_id` en el plano de recintos. Con eso se habilitan la búsqueda y "Ir aquí".
- [ ] Ubicar las balizas reales en las coordenadas del plano a escala.
- [ ] Trazar los recintos que todavía no tienen polígono (escaleras, ascensor y 5 recintos menores).
- [ ] Medir el rendimiento del SVG (416 KB) en teléfonos de gama baja.
- [ ] Evitar que la etiqueta del recinto seleccionado se encime con las vecinas.

## Posicionamiento

- [ ] Calibrar el resto del piso: `n ≈ 1,6` se midió solo en el pasillo norte.
- [ ] Android: escaneo continuo en vez de relanzarlo cada 4,2 s (Android limita a 5 inicios de
      escaneo cada 30 s).
- [ ] Android: quitar `neverForLocation` de `BLUETOOTH_SCAN`, que hace que el sistema filtre los
      beacons.
- [ ] Cambio automático de mapa según el `major` detectado.

## Calidad

- [ ] Sacar la fórmula de path-loss a un modelo puro (hoy está repetida en tres lugares).
- [ ] Tests de los algoritmos del modo investigador.
- [ ] Partir `calibracion_screen.dart` y `mapa_screen.dart` en widgets más chicos.
- [ ] Actualizar dependencias con código nativo (`flutter_blue_plus` 2.x, `permission_handler`,
      `go_router`) siguiendo la auditoría de [ADR-0009](adr/0009-pinning-dependencias.md).

## Producto

- [ ] Guardar los ajustes (ruta accesible, modo oscuro, texto grande) entre sesiones.
- [ ] Selector de entorno dentro de la app.
- [ ] Fase 3: guía en realidad aumentada (código conservado, desactivado).
- [ ] Fase 4: retroalimentación háptica y más indicaciones por voz.
