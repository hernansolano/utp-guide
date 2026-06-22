import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/nodo.dart';
import '../../models/position.dart';
import '../theme/app_theme.dart';
import 'mapa_painter.dart';

/// Widget reutilizable de mapa con comportamiento estilo Google Maps:
/// pan, zoom, recentrar en el usuario, seguir al usuario, encuadrar
/// la ruta. Mantiene coherencia perfecta entre el SVG de fondo y los
/// dots dibujados encima usando un único rectángulo con [AspectRatio].
///
/// El widget es **stateless desde la perspectiva del consumidor**: toda
/// la información que necesita (mapa, ruta, posición del usuario) se
/// pasa por constructor y se reacciona vía `didUpdateWidget`. Para
/// disparar acciones imperativas (recentrar, encuadrar) se usa un
/// [MapViewController] opcional.
///
/// Ver `docs/adr/0010-map-view-widget.md` para el razonamiento de
/// arquitectura.
class MapView extends StatefulWidget {
  /// Dimensiones del piso en metros (debe coincidir con `grafo.json`).
  final Size mapaSize;

  /// Ruta al SVG del piso. Si es null, solo se dibuja la ruta/dot sobre
  /// fondo neutral.
  final String? svgAsset;

  /// Nodos de la ruta a dibujar. Lista vacía = sin ruta.
  final List<Nodo> ruta;

  /// Posición actual del usuario en metros. Null = sin señal BLE.
  final Position? posicionUsuario;

  /// Posición del indicador objetivo (cruz roja). Se usa en modo
  /// simulación para mostrar dónde el usuario "soltó" el dedo. Null
  /// oculta el indicador.
  final Position? posicionTarget;

  /// Lista de POIs a dibujar sobre el mapa (modo exploración).
  /// Cada POI es un dot coloreado según su tipo (salón, baño, etc.).
  /// Si está vacía, no se pinta nada extra.
  final List<Nodo> pois;

  /// ID del POI a destacar visualmente (anillo más grande + halo).
  /// Útil cuando el usuario tocó cerca de un POI específico.
  final String? poiResaltadoId;

  /// Polilínea de posiciones capturadas por [TrazaService]. Si está
  /// vacía o tiene menos de 2 puntos, no se pinta nada.
  final List<Position> traza;

  /// Si true, se pueden hacer pan/zoom con gestos. En modo simulación
  /// se desactiva para que el gesto del dedo coloque la posición
  /// virtual en lugar de mover la cámara.
  final bool panZoomHabilitado;

  /// Nivel mínimo y máximo de zoom (multiplicador sobre el tamaño base).
  final double minZoom;
  final double maxZoom;

  /// Si se pasa, se notifica con las coordenadas en metros cuando el
  /// usuario hace tap o drag sobre el mapa. Solo activo si
  /// [panZoomHabilitado] = false (modo simulación).
  final ValueChanged<Offset>? onTapMundo;

  /// Controlador opcional para invocar operaciones de cámara
  /// imperativamente desde la pantalla padre.
  final MapViewController? controller;

  const MapView({
    super.key,
    required this.mapaSize,
    this.svgAsset,
    this.ruta = const [],
    this.posicionUsuario,
    this.posicionTarget,
    this.panZoomHabilitado = true,
    this.minZoom = 0.8,
    this.maxZoom = 6.0,
    this.onTapMundo,
    this.controller,
    this.pois = const [],
    this.poiResaltadoId,
    this.traza = const [],
  });

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView>
    with SingleTickerProviderStateMixin {
  late final TransformationController _viewerController;
  late final AnimationController _animController;
  Animation<Matrix4>? _animacionMatrix;

  /// Tamaño del rectángulo del AspectRatio (donde realmente se dibuja
  /// el mapa). Se setea cuando el LayoutBuilder mide el espacio.
  Size? _boxSize;

  /// Tamaño del viewport (área disponible para el mapa, antes de
  /// aplicar la transformación). Se setea desde el LayoutBuilder externo.
  Size? _viewportSize;

  /// El encuadre inicial de la ruta se hace UNA sola vez, cuando el layout
  /// entrega por primera vez un tamaño válido. Antes el encuadre se disparaba
  /// durante la carga (MapView aún sin montar, `_boxSize`/`_viewportSize`
  /// null) y se perdía, dejando la cámara en un transform inválido: el mapa
  /// "no aparecía" hasta que un rebuild externo (p. ej. togglear el overlay
  /// de debug) lo forzaba. Esto lo vuelve determinístico.
  bool _encuadreInicialHecho = false;

  @override
  void initState() {
    super.initState();
    _viewerController = TransformationController();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(_aplicarAnimacionMatrix);
    widget.controller?._bind(this);
  }

  @override
  void dispose() {
    widget.controller?._unbind(this);
    _viewerController.dispose();
    _animController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MapView old) {
    super.didUpdateWidget(old);

    // Reasignar controller si cambió la referencia.
    if (widget.controller != old.controller) {
      old.controller?._unbind(this);
      widget.controller?._bind(this);
    }

    // Modo "seguir al usuario": cuando la posición cambia y el modo
    // está activo, animar la cámara hacia la nueva posición.
    if (widget.controller != null &&
        widget.controller!.siguiendoUsuario &&
        widget.posicionUsuario != null &&
        widget.posicionUsuario != old.posicionUsuario) {
      _recentrarEnUsuario(animado: true);
    }
  }

  void _aplicarAnimacionMatrix() {
    if (_animacionMatrix != null) {
      _viewerController.value = _animacionMatrix!.value;
    }
  }

  // ─── Operaciones de cámara (llamadas desde MapViewController) ──────────────

  /// Centra la cámara en la posición del usuario.
  ///
  /// Si [zoomDeseado] se especifica, también ajusta el zoom. Si no, mantiene
  /// el zoom actual. Si no hay posición del usuario disponible, no hace nada.
  void _recentrarEnUsuario({double? zoomDeseado, bool animado = true}) {
    if (widget.posicionUsuario == null) return;
    _moverCamaraA(
      Offset(widget.posicionUsuario!.x, widget.posicionUsuario!.y),
      zoomDeseado: zoomDeseado,
      animado: animado,
    );
  }

  /// Encuadra la cámara para que toda la ruta sea visible, con un
  /// padding cómodo alrededor. Si la ruta está vacía, encuadra todo el mapa.
  void _encuadrarRuta({bool animado = true}) {
    if (widget.ruta.isEmpty) {
      _encuadrarTodo(animado: animado);
      return;
    }

    double minX = widget.ruta.first.x;
    double maxX = widget.ruta.first.x;
    double minY = widget.ruta.first.y;
    double maxY = widget.ruta.first.y;
    for (final n in widget.ruta) {
      minX = min(minX, n.x);
      maxX = max(maxX, n.x);
      minY = min(minY, n.y);
      maxY = max(maxY, n.y);
    }

    _encuadrarBoundingBox(
      minX - _paddingMetros,
      minY - _paddingMetros,
      maxX + _paddingMetros,
      maxY + _paddingMetros,
      animado: animado,
    );
  }

  /// Encuadra para mostrar todo el mapa.
  void _encuadrarTodo({bool animado = true}) {
    _animarMatrix(Matrix4.identity(), animado: animado);
  }

  /// Encuadra una bounding box en coordenadas mundiales (metros).
  void _encuadrarBoundingBox(
      double minX, double minY, double maxX, double maxY,
      {bool animado = true}) {
    final box = _boxSize;
    final viewport = _viewportSize;
    if (box == null || viewport == null) return;

    final bboxW = max(maxX - minX, 0.1);
    final bboxH = max(maxY - minY, 0.1);
    final centerWorld = Offset((minX + maxX) / 2, (minY + maxY) / 2);

    // Convertir tamaño bbox a píxeles del box.
    final bboxBoxW = bboxW * box.width / widget.mapaSize.width;
    final bboxBoxH = bboxH * box.height / widget.mapaSize.height;

    // Escala para que la bbox quepa en el viewport (la menor de las dos).
    // Tope de encuadre por debajo de maxZoom: una ruta corta no debe saltar
    // a 6x (se vería un acercamiento extremo); el usuario igual puede hacer
    // pinch hasta maxZoom manualmente.
    final double zoomMax = min(widget.maxZoom, _zoomMaxEncuadre);
    final escala = min(viewport.width / bboxBoxW, viewport.height / bboxBoxH)
        .clamp(widget.minZoom, zoomMax);

    _moverCamaraA(centerWorld, zoomDeseado: escala, animado: animado);
  }

  /// Mueve la cámara para que el punto mundial dado quede centrado
  /// en el viewport, con el zoom solicitado.
  void _moverCamaraA(Offset puntoMundo,
      {double? zoomDeseado, bool animado = true}) {
    final box = _boxSize;
    final viewport = _viewportSize;
    if (box == null || viewport == null) return;
    // Guard contra layouts degenerados (tamaño 0): sin esto el matrix
    // resultante mandaba el contenido fuera de pantalla.
    if (box.width <= 0 ||
        box.height <= 0 ||
        viewport.width <= 0 ||
        viewport.height <= 0) {
      return;
    }

    // Mundo (metros) → pixel dentro de la ESCENA del InteractiveViewer.
    // El rectángulo del mapa (AspectRatio) está CENTRADO dentro del viewport
    // (Center), así que su origen no coincide con el de la escena: hay que
    // sumar el offset de centrado `(viewport - box) / 2`. Sin esto, el
    // encuadre desplazaba el contenido por `offset * escala` y lo mandaba
    // fuera de pantalla cuando el aspect del mapa difiere del viewport
    // (causa del "mapa en blanco" en la pantalla de navegación).
    final offsetX = (viewport.width - box.width) / 2;
    final offsetY = (viewport.height - box.height) / 2;
    final puntoEscena = Offset(
      puntoMundo.dx * box.width / widget.mapaSize.width + offsetX,
      puntoMundo.dy * box.height / widget.mapaSize.height + offsetY,
    );

    final escala = (zoomDeseado ?? _zoomActual)
        .clamp(widget.minZoom, widget.maxZoom);

    // Matrix = translate(viewportCenter) * scale * translate(-puntoEscena):
    // el punto de la escena queda exactamente en el centro del viewport.
    // Usamos translateByDouble/scaleByDouble (las versiones no-deprecadas).
    final matrix = Matrix4.identity()
      ..translateByDouble(viewport.width / 2, viewport.height / 2, 0, 1)
      ..scaleByDouble(escala, escala, escala, 1)
      ..translateByDouble(-puntoEscena.dx, -puntoEscena.dy, 0, 1);

    _animarMatrix(matrix, animado: animado);
  }

  /// Zoom actual leído del Matrix4 del InteractiveViewer.
  ///
  /// Asume escala uniforme y sin rotación (valido en este widget porque
  /// no exponemos rotación en la API).
  double get _zoomActual {
    final m = _viewerController.value;
    return m.getMaxScaleOnAxis();
  }

  void _animarMatrix(Matrix4 destino, {bool animado = true}) {
    if (!animado) {
      _viewerController.value = destino;
      return;
    }
    _animacionMatrix = Matrix4Tween(
      begin: _viewerController.value,
      end: destino,
    ).animate(CurvedAnimation(
        parent: _animController, curve: Curves.easeOutCubic));
    _animController.forward(from: 0);
  }

  // ─── Gestos ────────────────────────────────────────────────────────────────

  /// Cuando el usuario empieza un pan/zoom manualmente, si estábamos
  /// en modo seguir al usuario, lo desactivamos (UX estilo Google Maps).
  void _onInicioGestoUsuario() {
    final c = widget.controller;
    if (c != null && c.siguiendoUsuario) {
      c._setSiguiendoUsuario(false);
    }
  }

  void _onTap(TapDownDetails d) {
    final pos = _screenToMundo(d.localPosition);
    if (pos != null) widget.onTapMundo!(pos);
  }

  void _onPan(DragUpdateDetails d) {
    final pos = _screenToMundo(d.localPosition);
    if (pos != null) widget.onTapMundo!(pos);
  }

  /// Convierte un punto en coordenadas del box (donde se dibuja el
  /// mapa, antes de la transformación del InteractiveViewer) a metros.
  /// Usado por el callback `onTapMundo`.
  ///
  /// En modo simulación el InteractiveViewer está desactivado, por lo
  /// que la transformación es la identidad y las coordenadas del
  /// GestureDetector coinciden con las del box.
  Offset? _screenToMundo(Offset screenPos) {
    final box = _boxSize;
    if (box == null) return null;
    final x = (screenPos.dx / box.width) * widget.mapaSize.width;
    final y = (screenPos.dy / box.height) * widget.mapaSize.height;
    return Offset(
      x.clamp(0.0, widget.mapaSize.width),
      y.clamp(0.0, widget.mapaSize.height),
    );
  }

  /// Asegura que el mapa se vea COMPLETO (transform identidad) la primera vez
  /// que el layout entrega un tamaño válido. Es el mismo estado de la pantalla
  /// de exploración, que siempre se ve bien. Antes esto encuadraba a la ruta,
  /// y ese encuadre dejaba el mapa fuera de pantalla ("en blanco") en la
  /// pantalla de navegación. El usuario puede acercarse con pinch o con el
  /// botón de ubicación.
  void _quizasEncuadreInicial() {
    if (_encuadreInicialHecho) return;
    final box = _boxSize;
    final vp = _viewportSize;
    if (box == null || vp == null) return;
    if (box.width <= 0 || box.height <= 0 || vp.width <= 0 || vp.height <= 0) {
      return;
    }
    _encuadreInicialHecho = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _encuadrarTodo(animado: false);
    });
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, viewportConstraints) {
        // Capturamos viewport size en cada rebuild — necesario para que
        // las animaciones de cámara funcionen tras un resize.
        final nuevoViewport = Size(
            viewportConstraints.maxWidth, viewportConstraints.maxHeight);
        // Si el viewport cambió de forma notable (rotación de pantalla u
        // otro resize), volver a mostrar el mapa completo tras el frame. Sin
        // esto la cámara conservaba el transform de la orientación anterior y
        // el mapa quedaba descuadrado al rotar.
        final cambioViewport = _viewportSize != null &&
            _encuadreInicialHecho &&
            ((_viewportSize!.width - nuevoViewport.width).abs() > 1 ||
                (_viewportSize!.height - nuevoViewport.height).abs() > 1);
        _viewportSize = nuevoViewport;
        if (cambioViewport) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _encuadrarTodo(animado: false);
          });
        }

        // El AspectRatio garantiza que SVG y CustomPaint compartan el
        // mismo rectángulo. Sin esto, BoxFit.contain del SVG creaba
        // letterboxing que el painter no compensaba, y los dots
        // aparecían fuera del SVG visible.
        final mapaAspect = widget.mapaSize.width / widget.mapaSize.height;

        return InteractiveViewer(
          transformationController: _viewerController,
          panEnabled: widget.panZoomHabilitado,
          scaleEnabled: widget.panZoomHabilitado,
          minScale: widget.minZoom,
          maxScale: widget.maxZoom,
          boundaryMargin: const EdgeInsets.all(80),
          onInteractionStart: (_) => _onInicioGestoUsuario(),
          child: Center(
            child: AspectRatio(
              aspectRatio: mapaAspect,
              child: LayoutBuilder(
                builder: (context, boxConstraints) {
                  _boxSize = Size(
                      boxConstraints.maxWidth, boxConstraints.maxHeight);
                  _quizasEncuadreInicial();
                  return _buildMapaInterno(_boxSize!);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// Construye el contenido del rectángulo del mapa (SVG + ruta + dot +
  /// target indicator). El [GestureDetector] de drag-to-position vive
  /// adentro de este método, así que solo captura taps **dentro del
  /// AspectRatio**. Esto evita el bug previo donde un tap en la zona
  /// letterboxed (fuera del mapa) se convertía en coords clampeadas a
  /// los bordes del piso. Además, `localPosition` del gesto ya viene en
  /// coords del box, lo que simplifica la conversión a metros.
  Widget _buildMapaInterno(Size box) {
    Widget contenido = Stack(
      fit: StackFit.expand,
      children: [
        if (widget.svgAsset != null)
          SvgPicture.asset(widget.svgAsset!, fit: BoxFit.fill),
        CustomPaint(
          painter: MapaPainter.fromContext(
            context,
            ruta: widget.ruta,
            mapaSize: widget.mapaSize,
            posicionUsuario: widget.posicionUsuario,
            pois: widget.pois,
            poiResaltadoId: widget.poiResaltadoId,
            traza: widget.traza,
          ),
          size: box,
        ),
        if (widget.posicionTarget != null)
          _buildTargetIndicator(box, widget.posicionTarget!),
      ],
    );

    if (widget.onTapMundo != null) {
      contenido = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _onTap,
        onPanUpdate: _onPan,
        child: contenido,
      );
    }

    return contenido;
  }

  Widget _buildTargetIndicator(Size box, Position target) {
    final px = target.x * box.width / widget.mapaSize.width;
    final py = target.y * box.height / widget.mapaSize.height;
    // Color del tema (respeta modo oscuro). Antes Colors.red.shade400 hardcoded.
    final color = Theme.of(context)
            .extension<AppColors>()
            ?.danger ??
        Colors.red.shade400;
    return Positioned(
      left: px - 12,
      top: py - 12,
      child: IgnorePointer(
        child: CustomPaint(
          size: const Size(24, 24),
          painter: _TargetCruzPainter(color: color),
        ),
      ),
    );
  }

  /// Padding alrededor de la ruta al encuadrarla, en metros.
  static const double _paddingMetros = 1.5;

  /// Zoom máximo al que llega el encuadre automático de la ruta. Más bajo
  /// que `maxZoom` (el tope del pinch manual) para que una ruta corta no
  /// abra con un acercamiento extremo.
  static const double _zoomMaxEncuadre = 2.5;
}

/// Cruz roja para indicar la posición virtual en modo simulación.
class _TargetCruzPainter extends CustomPainter {
  final Color color;
  const _TargetCruzPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(c, 8, paint);
    canvas.drawLine(Offset(c.dx - 5, c.dy), Offset(c.dx + 5, c.dy), paint);
    canvas.drawLine(Offset(c.dx, c.dy - 5), Offset(c.dx, c.dy + 5), paint);
  }

  @override
  bool shouldRepaint(_TargetCruzPainter old) => old.color != color;
}

/// Controlador imperativo del [MapView].
///
/// Permite que la pantalla padre dispare acciones (recentrar, encuadrar,
/// activar modo seguir) y observe estado (zoom actual, si está siguiendo
/// al usuario) sin acoplarse al internal state del widget.
///
/// Uso:
/// ```dart
/// final _mapController = MapViewController();
///
/// MapView(controller: _mapController, ...);
///
/// // Más adelante:
/// _mapController.recentrarEnUsuario(zoomDeseado: 2.0);
/// _mapController.activarSeguirUsuario();
/// ```
class MapViewController extends ChangeNotifier {
  _MapViewState? _state;
  bool _siguiendoUsuario = false;

  /// Si true, la cámara se mueve automáticamente para seguir al
  /// usuario cuando su posición cambia. Se desactiva automáticamente
  /// cuando el usuario panea manualmente.
  bool get siguiendoUsuario => _siguiendoUsuario;

  /// Zoom actual de la cámara. Útil para mostrar un indicador o
  /// implementar zoom in/out a paso fijo.
  double get zoomActual => _state?._zoomActual ?? 1.0;

  /// Centra la cámara en la posición del usuario y opcionalmente
  /// cambia el zoom. Si no hay posición disponible, no hace nada.
  void recentrarEnUsuario({double? zoomDeseado, bool animado = true}) {
    _state?._recentrarEnUsuario(zoomDeseado: zoomDeseado, animado: animado);
  }

  /// Centra y encuadra la cámara para mostrar toda la ruta con padding.
  void encuadrarRuta({bool animado = true}) {
    _state?._encuadrarRuta(animado: animado);
  }

  /// Vuelve a la vista por defecto (identidad). Útil para "ver todo
  /// el mapa" sin filtrar por ruta.
  void encuadrarTodo({bool animado = true}) {
    _state?._encuadrarTodo(animado: animado);
  }

  /// Activa el modo seguir al usuario. La cámara se moverá
  /// automáticamente con cada cambio de posición.
  void activarSeguirUsuario({double? zoomDeseado}) {
    if (_state == null) return;
    _siguiendoUsuario = true;
    recentrarEnUsuario(zoomDeseado: zoomDeseado);
    notifyListeners();
  }

  /// Desactiva el modo seguir. La cámara se queda donde está.
  void desactivarSeguirUsuario() {
    if (!_siguiendoUsuario) return;
    _siguiendoUsuario = false;
    notifyListeners();
  }

  void _setSiguiendoUsuario(bool valor) {
    if (_siguiendoUsuario == valor) return;
    _siguiendoUsuario = valor;
    notifyListeners();
  }

  void _bind(_MapViewState state) {
    _state = state;
  }

  void _unbind(_MapViewState state) {
    // Solo limpiar si el state coincide (evitar race conditions con
    // hot reload o cambio de widget).
    if (_state == state) _state = null;
  }
}
