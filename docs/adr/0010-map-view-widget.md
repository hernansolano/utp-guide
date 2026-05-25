# ADR-0010 — MapView: widget de mapa con cámara controlable

- **Estado:** aceptado
- **Fecha:** 2026-05-21
- **Autor:** equipo UTP-Guide
- **Reemplaza:** el código de mapa inline de `MapaScreen` y el `CustomPaint` directo del `MinimapWidget`

## Contexto

La pantalla de mapa (`MapaScreen`) y el minimapa (`MinimapWidget`) compartían un patrón común para renderizar:

```
Stack
├── SvgPicture(fit: BoxFit.contain)
└── CustomPaint(painter: MapaPainter, size: fullCanvas)
```

Este patrón tenía dos defectos serios que aparecieron en pruebas reales en emulador:

1. **Desalineación entre SVG y painter.** El `SvgPicture` con `BoxFit.contain` centra el SVG dentro del Stack y deja letterboxing arriba/abajo (o a los lados). El `CustomPaint` dibuja sobre el Stack completo con escalado lineal `canvas.width / mapaSize.width`, que es **no uniforme** cuando el aspect ratio del Stack difiere del aspect ratio del mapa. Resultado: el punto del usuario y los nodos de la ruta aparecen **fuera del SVG visible**, en posiciones incorrectas.

2. **UX pobre comparada con apps de mapas estándar.** La pantalla envolvía el Stack en un `InteractiveViewer` que daba pan y zoom, pero:
   - El botón "recentrar" solo reseteaba la transformación, no centraba en la posición del usuario.
   - No había modo "seguir al usuario" (la cámara no se movía sola con el usuario).
   - No había encuadre automático de la ruta al cargar — el usuario tenía que panear y hacer zoom manualmente para ver toda la ruta.
   - No había animaciones suaves entre estados de cámara.

Adicionalmente, el `MinimapWidget` tenía el mismo bug latente de desalineación, solo que en el contexto del minimapa (140×140 px) el desplazamiento era menos evidente.

## Decisión

Extraer toda la lógica de renderizado y control de cámara del mapa a un widget reutilizable `MapView` (`lib/ui/widgets/map_view.dart`) con un `MapViewController` opcional para invocaciones imperativas desde el código padre.

### Arquitectura

```dart
class MapView extends StatefulWidget {
  final Size mapaSize;
  final String? svgAsset;
  final List<Nodo> ruta;
  final Position? posicionUsuario;
  final Position? posicionTarget;
  final bool panZoomHabilitado;
  final ValueChanged<Offset>? onTapMundo;
  final MapViewController? controller;
}

class MapViewController extends ChangeNotifier {
  bool get siguiendoUsuario;
  double get zoomActual;

  void recentrarEnUsuario({double? zoomDeseado, bool animado = true});
  void encuadrarRuta({bool animado = true});
  void encuadrarTodo({bool animado = true});
  void activarSeguirUsuario({double? zoomDeseado});
  void desactivarSeguirUsuario();
}
```

### Fix de coordenadas

`MapView` envuelve el SVG y el `CustomPaint` en un `AspectRatio(mapaSize.width / mapaSize.height)`. Como la caja resultante tiene exactamente el aspect ratio del mapa, ambos hijos comparten el mismo rectángulo sin letterboxing, y el escalado del painter (`canvas.width / mapaSize.width`) es uniforme con el escalado en Y. Los dots y la ruta caen exactamente donde el SVG los espera.

El SVG ahora usa `BoxFit.fill` (no `contain`) porque la caja ya respeta su aspect ratio, así que no hay distorsión.

### Cámara estilo Google Maps

`MapView` envuelve el AspectRatio en un `InteractiveViewer` y expone operaciones de cámara a través del controller. La conversión entre operaciones de alto nivel (centrar, encuadrar) y el `Matrix4` del `TransformationController` se hace internamente. Animaciones de 300ms con `Curves.easeOutCubic` entre todos los estados.

**Modo seguir al usuario:** cuando se activa, `MapView` escucha cambios de `posicionUsuario` vía `didUpdateWidget` y recentra automáticamente. Si el usuario panea manualmente, `onInteractionStart` del `InteractiveViewer` detecta el gesto y desactiva el modo (UX idéntica a Google Maps).

**Encuadre automático:** al cargar una ruta nueva, `MapaScreen` llama `_mapController.encuadrarRuta()` en un `addPostFrameCallback`. La cámara se acomoda para mostrar toda la ruta con 1.5 m de padding alrededor.

## Alternativas consideradas

### Mantener InteractiveViewer + compensar letterboxing en MapaPainter

Posible pero feo: el painter necesitaría calcular el rectángulo "fit" del SVG según el aspect ratio y compensarlo. Implica que cada usuario del painter (MapaScreen, MinimapWidget, futuro AR view) duplica esa lógica.

### Usar un paquete de mapas (flutter_map, google_maps_flutter)

`flutter_map` está orientado a mapas geográficos con tiles (OpenStreetMap), no a SVGs indoor. `google_maps_flutter` requiere coordenadas geográficas reales y una clave de API, fuera del alcance del proyecto. Ninguno aporta sobre nuestro caso de uso de un SVG estático con coordenadas locales en metros.

### Custom transform con `Matrix4` puro sin InteractiveViewer

Posible, pero `InteractiveViewer` ya resuelve los gestos pan/zoom correctamente con detección de gesto multi-touch, bounds, y precisión de pixel. Reescribir eso a mano duplicaría código de la SDK con riesgo de bugs. La capa imperativa que necesitábamos (centrar, encuadrar, seguir) se compone sobre `TransformationController.value` sin remplazar `InteractiveViewer`.

## Consecuencias

### Positivas

- **El bug de desalineación queda eliminado** estructuralmente, no por compensación. SVG y painter siempre comparten coordenadas.
- **UX consistente con apps de mapas estándar:** encuadre inicial, modo seguir, animaciones suaves, recentrar inteligente.
- **Reutilizable.** `MinimapWidget` ahora usa `MapView` con `panZoomHabilitado: false` y `svgAsset: null`. El bug que tenía latente desapareció con el refactor.
- **Base para Fase 3 (AR).** Cuando se implemente AR, la vista de cámara con overlay del mapa puede reusar `MapView` o componer con su controller. La separación de responsabilidades ya está hecha.
- **API limpia para futuras features:** mostrar markers de POIs, destacar zonas, animaciones programáticas — todo se puede agregar en `MapView` sin tocar pantallas.

### Negativas

- **+340 líneas de código nuevo** en `map_view.dart`. La pantalla anfitriona se simplifica, pero el código total del proyecto crece.
- **El `MapViewController` introduce acoplamiento State↔Controller** (el controller guarda referencia interna al `_MapViewState`). Es el patrón estándar de Flutter para controladores imperativos (igual que `ScrollController`, `AnimationController`, `TransformationController`), pero requiere disciplina con dispose y unbind para evitar memory leaks.
- **El `MapaPainter` aún no compensa el letterboxing de su propio canvas.** No es un problema porque `MapView` siempre le pasa un canvas con el aspect ratio correcto. Si alguien usa `MapaPainter` directamente sin `MapView` (futuro mantenedor desinformado), el bug viejo vuelve. Mitigación: comentario en `MapaPainter` advirtiendo que debe instanciarse vía `MapView`. Mejor mitigación a futuro: hacer el painter privado al archivo de `MapView`.

### Riesgos

- Hot reload puede dejar el `MapViewController` con state stale si el binding no se re-establece. Mitigamos con la lógica de `_bind` / `_unbind` que verifica identidad del state antes de limpiar.
- Animaciones simultáneas (el usuario panea mientras una animación de recentrar está en curso) podrían dar saltos visuales. El comportamiento actual: la animación termina y luego el pan del usuario empieza desde la posición final. Aceptable por ahora; si se vuelve molesto, agregar cancelación de animación en `_onInicioGestoUsuario`.

## Referencias

- [`docs/positioning-ble.md`](../positioning-ble.md) — explica cómo los dots representan la posición; este ADR explica cómo se renderizan
- [Flutter InteractiveViewer docs](https://api.flutter.dev/flutter/widgets/InteractiveViewer-class.html)
- [Google Maps mobile camera behavior](https://developers.google.com/maps/documentation/android-sdk/views) — referencia de UX
