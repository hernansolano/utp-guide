import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../data/repositories/grafo_repository.dart';
import '../../models/nodo.dart';
import '../../models/paso_navegacion.dart';
import '../../models/perfil_movilidad.dart';
import '../../models/position.dart';
import '../../models/tipo_nodo.dart';
import '../../services/ble_service.dart';
import '../../services/positioning_service.dart';
import '../../services/routing_service.dart';
import '../../services/tts_service.dart';
import '../theme/app_theme.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/mapa_painter.dart';
import '../widgets/minimap_widget.dart';

/// Pantalla principal de navegación. Renderiza el mapa SVG, la ruta
/// calculada, el punto del usuario (BLE), y los controles laterales.
///
/// Las dimensiones del piso se leen de `GrafoRepository.obtenerDimensionesMapa()`
/// en `initState`, así que pisos de cualquier tamaño funcionan sin tocar
/// código. El cambio mapa↔AR vía acelerómetro respeta el setting
/// `arAutomaticoNotifier`: si está off, solo el FAB cambia el modo.
class MapaScreen extends StatefulWidget {
  final String destinoId;
  final PerfilMovilidad perfil;
  final RoutingService routingService;
  final PositioningService positioningService;
  final GrafoRepository grafoRepository;
  final TtsService ttsService;
  final ValueNotifier<bool> arAutomaticoNotifier;
  final ValueNotifier<bool> debugOverlayNotifier;
  final ValueNotifier<bool> modoSimulacionNotifier;
  final ValueNotifier<Position?> posicionVirtualNotifier;
  final ValueNotifier<bool> vozHabilitadaNotifier;

  const MapaScreen({
    super.key,
    required this.destinoId,
    required this.perfil,
    required this.routingService,
    required this.positioningService,
    required this.grafoRepository,
    required this.ttsService,
    required this.arAutomaticoNotifier,
    required this.debugOverlayNotifier,
    required this.modoSimulacionNotifier,
    required this.posicionVirtualNotifier,
    required this.vozHabilitadaNotifier,
  });

  @override
  State<MapaScreen> createState() => _MapaScreenState();
}

class _MapaScreenState extends State<MapaScreen> {
  List<Nodo> _ruta = [];
  List<PasoNavegacion> _pasos = [];
  int _pasoActualIndice = 0; // recalculado cuando cambia la posición
  String? _error;
  bool _cargando = true;
  bool _enModoAR = false;
  bool _recalculandoRuta = false;

  // Perfil de movilidad activo. Se inicializa con widget.perfil (el que
  // se eligió al hacer la búsqueda) pero puede cambiar en runtime desde
  // el botón lateral, lo cual dispara un recálculo de la ruta.
  late PerfilMovilidad _perfilActual;

  // Dimensiones del piso, cargadas desde el grafo. `null` hasta que termine
  // la carga inicial (durante ese tiempo se muestra el spinner).
  Size? _mapaSize;

  // Posición BLE del usuario (null = sin señal).
  Position? _posicionUsuario;
  int _beaconsActivos = 0;
  BleEstado _bleEstado = BleEstado.inactivo;
  bool _dialogoMostrado = false;

  StreamSubscription<AccelerometerEvent>? _acelerometroSub;
  StreamSubscription<Position?>? _posicionSub;
  StreamSubscription<BleEstado>? _estadoBleSub;

  /// Controlador para zoom y pan del mapa. Se resetea con el botón
  /// "Recentrar" del lateral. En modo simulación se desactiva el
  /// InteractiveViewer para que los gestos de un dedo coloquen la
  /// posición virtual en lugar de panear el mapa.
  final _viewerController = TransformationController();

  @override
  void initState() {
    super.initState();
    _perfilActual = widget.perfil;
    _cargarRutaYDimensiones();
    _iniciarAcelerometro();
    _iniciarPosicionamiento();
  }

  // ─── Carga inicial: dimensiones + ruta ─────────────────────────────────────

  /// Carga las dimensiones del piso y la ruta en paralelo. Ambas se
  /// necesitan antes de poder renderizar el mapa, así que el spinner
  /// se mantiene hasta que las dos completen.
  Future<void> _cargarRutaYDimensiones() async {
    try {
      final futureDims = widget.grafoRepository.obtenerDimensionesMapa();
      final futureEntradas =
          widget.routingService.nodosPorTipo(TipoNodo.entrada);

      final dims = await futureDims;
      final entradas = await futureEntradas;
      if (entradas.isEmpty) throw Exception('Sin nodo de entrada');

      final ruta = await widget.routingService.calcularRuta(
        origenId: entradas.first.id,
        destinoId: widget.destinoId,
        perfil: _perfilActual,
      );

      if (mounted) {
        setState(() {
          _mapaSize = Size(dims.anchoMetros, dims.altoMetros);
          _ruta = ruta;
          _pasos = PasoNavegacion.generarDesdeRuta(ruta);
          _pasoActualIndice = 0;
          _cargando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _mensajeError(e);
          _cargando = false;
        });
      }
    }
  }

  /// Recalcula la ruta con el perfil de movilidad alternativo. Mantiene
  /// el mismo origen y destino. Si falla (ej: no hay ruta accesible),
  /// revierte el perfil y muestra un mensaje breve.
  Future<void> _alternarPerfilMovilidad() async {
    if (_recalculandoRuta) return;
    final nuevoPerfil = _perfilActual == PerfilMovilidad.estandar
        ? PerfilMovilidad.accesible
        : PerfilMovilidad.estandar;

    setState(() => _recalculandoRuta = true);
    try {
      final entradas =
          await widget.routingService.nodosPorTipo(TipoNodo.entrada);
      final nuevaRuta = await widget.routingService.calcularRuta(
        origenId: entradas.first.id,
        destinoId: widget.destinoId,
        perfil: nuevoPerfil,
      );
      if (mounted) {
        setState(() {
          _perfilActual = nuevoPerfil;
          _ruta = nuevaRuta;
          _pasos = PasoNavegacion.generarDesdeRuta(nuevaRuta);
          _pasoActualIndice = 0;
          _recalculandoRuta = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _recalculandoRuta = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_mensajeError(e)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  String _mensajeError(Object e) {
    final msg = e.toString();
    if (msg.contains('accesible')) {
      return 'No hay ruta accesible disponible.\nPrueba el modo estándar.';
    }
    if (msg.contains('NodeNotFound') || msg.contains('no existe')) {
      return 'No se encontró el destino en el mapa.';
    }
    return 'No se pudo calcular la ruta.\nIntenta de nuevo.';
  }

  // ─── Acelerómetro (cambio mapa ↔ AR) ──────────────────────────────────────

  void _iniciarAcelerometro() {
    _acelerometroSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 200),
    ).listen((event) {
      // Si el usuario desactivó el cambio automático, ignoramos las
      // lecturas del acelerómetro — el modo AR solo cambia con el FAB.
      if (!widget.arAutomaticoNotifier.value) return;

      final angulo =
          atan2(event.z, sqrt(event.x * event.x + event.y * event.y));
      final grados = angulo * 180 / pi;
      // Histéresis deliberada: >35° activa AR, <25° desactiva.
      if (!_enModoAR && grados > 35) setState(() => _enModoAR = true);
      if (_enModoAR && grados < 25) setState(() => _enModoAR = false);
    });
  }

  // ─── Posicionamiento BLE ───────────────────────────────────────────────────

  void _iniciarPosicionamiento() {
    _estadoBleSub =
        widget.positioningService.estadoBleStream.listen((estado) {
      if (mounted) setState(() => _bleEstado = estado);
    });

    _posicionSub = widget.positioningService.posicionStream.listen((pos) {
      if (!mounted) return;
      final nuevoIndice = _calcularPasoActual(pos);
      final indiceCambio = nuevoIndice != _pasoActualIndice;
      setState(() {
        _posicionUsuario = pos;
        _beaconsActivos = widget.positioningService.beaconsActivos;
        _pasoActualIndice = nuevoIndice;
      });
      // Si el paso cambió y la voz está habilitada, leer la nueva
      // instrucción. La interrupción es manejada por TtsService.hablar(),
      // que cancela cualquier locución previa.
      if (indiceCambio &&
          widget.vozHabilitadaNotifier.value &&
          _pasos.isNotEmpty &&
          nuevoIndice < _pasos.length) {
        widget.ttsService.hablar(_pasos[nuevoIndice].instruccion);
      }
    });

    widget.positioningService.iniciar();
  }

  Future<void> _mostrarDialogoBleSiAplica() async {
    if (_dialogoMostrado) return;
    if (_bleEstado != BleEstado.permisosNegados &&
        _bleEstado != BleEstado.bluetoothApagado) {
      return;
    }

    _dialogoMostrado = true;
    final colors = context.colors;
    final esPermisos = _bleEstado == BleEstado.permisosNegados;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          esPermisos ? 'Activa los permisos' : 'Activa Bluetooth',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.fg,
          ),
        ),
        content: Text(
          esPermisos
              ? 'UTP-Guide necesita acceso a Bluetooth para calcular tu '
                  'posición dentro del edificio. Actívalo en Ajustes del '
                  'sistema → Apps → UTP Guide → Permisos.'
              : 'El Bluetooth de tu dispositivo está apagado. Actívalo '
                  'desde el panel de control rápido para ver tu posición '
                  'en el mapa.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: colors.fgMuted,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Entendido',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: colors.brand,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Cálculo del paso actual según posición del usuario ───────────────────

  /// Determina cuál paso de navegación es el "actual" dado dónde está
  /// el usuario. Heurística:
  ///
  /// 1. Si no hay posición o no hay ruta: paso 0 (inicio).
  /// 2. Si el usuario está a menos de 1 m del nodo destino: último paso
  ///    (llegada).
  /// 3. Caso general: encontrar el segmento (par de nodos consecutivos)
  ///    cuya distancia perpendicular al usuario es mínima. El paso actual
  ///    es el que se completa al llegar al final de ese segmento.
  int _calcularPasoActual(Position? pos) {
    if (pos == null || _ruta.length < 2 || _pasos.isEmpty) return 0;

    // Si está muy cerca del destino, marcar como llegada.
    final destino = _ruta.last;
    final distAlDestino =
        sqrt(pow(pos.x - destino.x, 2) + pow(pos.y - destino.y, 2));
    if (distAlDestino < 1.0) return _pasos.length - 1;

    // Encontrar el segmento más cercano al usuario.
    double minDist = double.infinity;
    int mejorSegmento = 0;
    for (int i = 0; i < _ruta.length - 1; i++) {
      final dist = _distanciaPuntoASegmento(
        pos.x, pos.y,
        _ruta[i].x, _ruta[i].y,
        _ruta[i + 1].x, _ruta[i + 1].y,
      );
      if (dist < minDist) {
        minDist = dist;
        mejorSegmento = i;
      }
    }
    // El paso `i` representa caminar de ruta[i] a ruta[i+1].
    return mejorSegmento;
  }

  /// Distancia perpendicular de un punto a un segmento de recta. Misma
  /// lógica que `PositioningService._puntoEnSegmento`, pero solo devuelve
  /// la distancia (no el punto proyectado).
  double _distanciaPuntoASegmento(
      double px, double py, double ax, double ay, double bx, double by) {
    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) {
      return sqrt(pow(px - ax, 2) + pow(py - ay, 2));
    }
    final t = (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0);
    final cx = ax + t * dx;
    final cy = ay + t * dy;
    return sqrt(pow(px - cx, 2) + pow(py - cy, 2));
  }

  // ─── Bottom sheet con la lista de pasos ────────────────────────────────────

  void _mostrarBottomSheetPasos() {
    final colors = context.colors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _PasosBottomSheet(
        pasos: _pasos,
        indiceActual: _pasoActualIndice,
        distanciaTotal: _distanciaRuta(),
      ),
    );
  }

  // ─── Modo simulación: drag-to-position ─────────────────────────────────────

  /// Convierte una posición en píxeles (sobre el Canvas) a metros (sistema
  /// de coordenadas del grafo) y la propaga al [posicionVirtualNotifier]
  /// para que el SimulatedBleService la consuma en el siguiente ciclo.
  ///
  /// La conversión usa escalado simple (sin compensar el letterboxing que
  /// hace `BoxFit.contain` para mapas no cuadrados). Esto coincide con el
  /// comportamiento de `MapaPainter`, así que el target indicator y el dot
  /// calculado quedan en el mismo sistema visual aunque haya distorsión.
  /// Cuando se mejore MapaPainter para soportar aspect ratio arbitrario,
  /// hay que actualizar esta función simultáneamente.
  void _actualizarPosicionVirtual(
      Offset puntoCanvas, Size canvasSize, Size mapaSize) {
    final x = (puntoCanvas.dx / canvasSize.width) * mapaSize.width;
    final y = (puntoCanvas.dy / canvasSize.height) * mapaSize.height;
    widget.posicionVirtualNotifier.value = Position(
      x: x.clamp(0.0, mapaSize.width),
      y: y.clamp(0.0, mapaSize.height),
      piso: 1,
      timestamp: DateTime.now(),
    );
  }

  // ─── Distancia real de la ruta ─────────────────────────────────────────────

  double _distanciaRuta() {
    double total = 0;
    for (int i = 0; i < _ruta.length - 1; i++) {
      final dx = _ruta[i + 1].x - _ruta[i].x;
      final dy = _ruta[i + 1].y - _ruta[i].y;
      total += sqrt(dx * dx + dy * dy);
    }
    return total;
  }

  String _formatearDistancia(double metros) {
    if (metros < 1) return '< 1 m';
    return '${metros.toStringAsFixed(0)} m';
  }

  String _formatearTiempo(double metros) {
    final segundos = (metros / 1.2).round();
    if (segundos < 60) return '${segundos}s';
    return '${(segundos / 60).ceil()} min';
  }

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _acelerometroSub?.cancel();
    _posicionSub?.cancel();
    _estadoBleSub?.cancel();
    _viewerController.dispose();
    widget.ttsService.detener();
    widget.positioningService.detener();
    super.dispose();
  }

  /// Resetea zoom y pan al estado inicial (identidad). Llamado desde
  /// el botón "Recentrar" del lateral.
  void _recentrarMapa() {
    _viewerController.value = Matrix4.identity();
  }

  /// Construye la capa interactiva del mapa: ruta dibujada, indicador de
  /// posición virtual (en modo simulación) y detector de drag para
  /// actualizar esa posición.
  ///
  /// Va adentro del InteractiveViewer cuando NO estamos en simulación
  /// (entonces hereda zoom/pan automáticamente) y también dentro cuando
  /// SÍ estamos en simulación (entonces el InteractiveViewer está
  /// desactivado y este Stack recibe los gestos directamente).
  Widget _buildMapaCapaInteractiva(Size mapaSize, AppColors colors) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final canvasSize =
            Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          children: [
            // Detector de drag — solo activo cuando estamos en simulación.
            ValueListenableBuilder<bool>(
              valueListenable: widget.modoSimulacionNotifier,
              builder: (_, simulando, _) {
                if (!simulando) return const SizedBox.shrink();
                return Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapDown: (d) => _actualizarPosicionVirtual(
                        d.localPosition, canvasSize, mapaSize),
                    onPanUpdate: (d) => _actualizarPosicionVirtual(
                        d.localPosition, canvasSize, mapaSize),
                  ),
                );
              },
            ),
            // Pintura de la ruta y el dot del usuario.
            CustomPaint(
              painter: MapaPainter.fromContext(
                ctx,
                ruta: _ruta,
                mapaSize: mapaSize,
                posicionUsuario: _posicionUsuario,
              ),
              size: canvasSize,
            ),
            // Indicador de "posición virtual deseada" — solo en simulación.
            ValueListenableBuilder<bool>(
              valueListenable: widget.modoSimulacionNotifier,
              builder: (_, simulando, _) {
                if (!simulando) return const SizedBox.shrink();
                return ValueListenableBuilder<Position?>(
                  valueListenable: widget.posicionVirtualNotifier,
                  builder: (_, posVirtual, _) {
                    if (posVirtual == null) {
                      return const SizedBox.shrink();
                    }
                    final px = posVirtual.x *
                        (canvasSize.width / mapaSize.width);
                    final py = posVirtual.y *
                        (canvasSize.height / mapaSize.height);
                    return Positioned(
                      left: px - 10,
                      top: py - 10,
                      child: IgnorePointer(
                        child: _TargetIndicator(color: colors.danger),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        );
      },
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final nombreDestino =
        _ruta.isNotEmpty ? _ruta.last.nombre : widget.destinoId;

    WidgetsBinding.instance
        .addPostFrameCallback((_) => _mostrarDialogoBleSiAplica());

    if (_cargando) {
      return Scaffold(
        backgroundColor: colors.bg,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: colors.bg,
        appBar: AppBar(leading: const BackButton()),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: colors.danger, size: 48),
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    color: colors.fg,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // En este punto _mapaSize está garantizado no-null porque _cargando
    // solo pasa a false cuando ambas (dimensiones + ruta) terminan de cargar.
    final mapaSize = _mapaSize!;
    final dist = _distanciaRuta();

    return Scaffold(
      backgroundColor: colors.bgMuted,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // El mapa (SVG + ruta + target indicator) va dentro de un
                // InteractiveViewer para soportar zoom y pan. En modo
                // simulación se desactiva el viewer y el GestureDetector
                // interno captura el drag para mover la posición virtual.
                ValueListenableBuilder<bool>(
                  valueListenable: widget.modoSimulacionNotifier,
                  builder: (_, simulando, _) => InteractiveViewer(
                    transformationController: _viewerController,
                    panEnabled: !simulando,
                    scaleEnabled: !simulando,
                    minScale: 0.8,
                    maxScale: 5.0,
                    boundaryMargin: const EdgeInsets.all(40),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        SvgPicture.asset(
                          'assets/maps/test_room_5x5.svg',
                          fit: BoxFit.contain,
                        ),
                        _buildMapaCapaInteractiva(mapaSize, colors),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 20,
                  right: 20,
                  child: _buildDestinationPill(
                      context, colors, nombreDestino, dist),
                ),
                Positioned(
                  right: 20,
                  top: MediaQuery.of(context).padding.top + 80,
                  child: Column(
                    children: [
                      _sideButton(context, colors,
                          Icons.my_location_rounded, _recentrarMapa),
                      const SizedBox(height: 10),
                      _sideButton(
                          context,
                          colors,
                          Icons.format_list_bulleted_rounded,
                          _mostrarBottomSheetPasos),
                      const SizedBox(height: 10),
                      // Toggle accesibilidad: cambia color y desencadena recálculo
                      _sideButton(
                        context,
                        colors,
                        Icons.accessible_rounded,
                        _alternarPerfilMovilidad,
                        activo: _perfilActual == PerfilMovilidad.accesible,
                        cargando: _recalculandoRuta,
                      ),
                    ],
                  ),
                ),
                if (!_enModoAR)
                  Positioned(
                    left: 16,
                    bottom: 16,
                    child: _buildBleChip(colors),
                  ),
                Positioned(
                  right: 20,
                  bottom: 20,
                  child: GestureDetector(
                    onTap: () => setState(() => _enModoAR = !_enModoAR),
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: colors.brand,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: colors.brand.withValues(alpha: 0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Icon(
                        _enModoAR
                            ? Icons.map_rounded
                            : Icons.camera_alt_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                ),
                if (_enModoAR)
                  Positioned(
                    left: 16,
                    bottom: 16,
                    child: MinimapWidget(
                      ruta: _ruta,
                      mapaSize: mapaSize,
                    ),
                  ),
                // Overlay de debug — solo en debug mode y si el toggle está on.
                // En release builds este código no se incluye (kDebugMode = false
                // permite que el árbol-shaker elimine el widget).
                if (kDebugMode)
                  ValueListenableBuilder<bool>(
                    valueListenable: widget.debugOverlayNotifier,
                    builder: (context, mostrar, _) {
                      if (!mostrar) return const SizedBox.shrink();
                      return Positioned(
                        top: MediaQuery.of(context).padding.top + 80,
                        left: 16,
                        child: _DebugOverlay(
                          positioningService: widget.positioningService,
                          posicionSnapped: _posicionUsuario,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          _buildNavigationCard(context, colors, nombreDestino),
          BottomNavWidget(
            activeTab: 'map',
            onTabChanged: (tab) {
              if (tab == 'home') context.go('/');
              if (tab == 'search') context.push('/search');
              if (tab == 'settings') context.push('/settings');
            },
          ),
        ],
      ),
    );
  }

  // ─── Widgets auxiliares ────────────────────────────────────────────────────

  Widget _buildDestinationPill(BuildContext context, AppColors colors,
      String nombre, double dist) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colors.brand,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: colors.brand.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _pillIconButton(
              Icons.arrow_back_rounded, () => context.pop(), Colors.white),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${_formatearTiempo(dist)} · ${_formatearDistancia(dist)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
          _pillIconButton(
            Icons.volume_up_rounded,
            // Tap manual: lee el paso actual ignorando el toggle de voz.
            // Esto permite al usuario consultar la instrucción aunque
            // tenga la voz desactivada por defecto.
            () {
              if (_pasos.isNotEmpty && _pasoActualIndice < _pasos.length) {
                widget.ttsService
                    .hablar(_pasos[_pasoActualIndice].instruccion);
              }
            },
            Colors.white,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _pillIconButton(IconData icon, VoidCallback onTap, Color color) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  Widget _sideButton(
    BuildContext context,
    AppColors colors,
    IconData icon,
    VoidCallback onTap, {
    bool activo = false,
    bool cargando = false,
  }) {
    return GestureDetector(
      onTap: cargando ? null : onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: activo
              ? colors.brand
              : colors.surfaceElevated.withValues(alpha: 0.92),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.1), blurRadius: 8),
          ],
        ),
        child: cargando
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      activo ? Colors.white : colors.brand),
                ),
              )
            : Icon(icon,
                color: activo ? Colors.white : colors.fg, size: 20),
      ),
    );
  }

  Widget _buildBleChip(AppColors colors) {
    final tienePos = _posicionUsuario != null;
    final bgColor = tienePos ? colors.accessible : colors.bgMuted;
    final fgColor = tienePos ? Colors.white : colors.fgSoft;
    final label = tienePos
        ? 'BLE · $_beaconsActivos baliza${_beaconsActivos != 1 ? 's' : ''}'
        : 'Sin señal BLE';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08), blurRadius: 6),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: tienePos ? Colors.white : colors.fgSoft,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fgColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationCard(
      BuildContext context, AppColors colors, String nombre) {
    // El paso actual viene calculado por _calcularPasoActual. Si todavía
    // no hay pasos (carga inicial), mostramos un placeholder.
    final paso = (_pasos.isNotEmpty && _pasoActualIndice < _pasos.length)
        ? _pasos[_pasoActualIndice]
        : null;
    final esLlegada = paso != null && _pasoActualIndice == _pasos.length - 1;
    final tituloLinea = paso?.instruccion ?? 'Calculando ruta…';
    final iconoPaso = paso?.icono ?? Icons.straight_rounded;

    // Subtítulo: progreso de la ruta o coordenadas del usuario.
    final String subtitulo;
    if (esLlegada) {
      subtitulo = '¡Has llegado!';
    } else if (_posicionUsuario != null) {
      subtitulo = 'Paso ${_pasoActualIndice + 1} de ${_pasos.length}'
          ' · (${_posicionUsuario!.x.toStringAsFixed(1)} m, '
          '${_posicionUsuario!.y.toStringAsFixed(1)} m)';
    } else {
      subtitulo = paso != null && _pasos.length > 1
          ? 'Paso ${_pasoActualIndice + 1} de ${_pasos.length}'
              ' · esperando señal BLE…'
          : 'Esperando señal BLE…';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        border: Border(top: BorderSide(color: colors.line)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: esLlegada ? colors.success : colors.brandSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              iconoPaso,
              color: esLlegada ? Colors.white : colors.brand,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tituloLinea,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.fg,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitulo,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colors.fgMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () =>
                context.canPop() ? context.pop() : context.go('/'),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: colors.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.close_rounded, color: colors.danger, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'Salir',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.danger,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Bottom sheet con la lista de pasos ──────────────────────────────────────

/// Sheet modal que muestra todos los pasos de la ruta calculada. El paso
/// actual (calculado por proximidad a un segmento) se resalta con un
/// borde de color brand y fondo brandSoft.
class _PasosBottomSheet extends StatelessWidget {
  final List<PasoNavegacion> pasos;
  final int indiceActual;
  final double distanciaTotal;

  const _PasosBottomSheet({
    required this.pasos,
    required this.indiceActual,
    required this.distanciaTotal,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle drag
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: colors.lineStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Pasos de la ruta',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: colors.fg,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${pasos.length} ${pasos.length == 1 ? "paso" : "pasos"} · '
              '${distanciaTotal.toStringAsFixed(0)} m totales',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: colors.fgMuted,
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: pasos.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _FilaPaso(
                  paso: pasos[i],
                  esActual: i == indiceActual,
                  numero: i + 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaPaso extends StatelessWidget {
  final PasoNavegacion paso;
  final bool esActual;
  final int numero;

  const _FilaPaso({
    required this.paso,
    required this.esActual,
    required this.numero,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: esActual ? colors.brandSoft : colors.bgSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: esActual ? colors.brand : colors.line,
          width: esActual ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: esActual ? colors.brand : colors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.line),
            ),
            child: Icon(
              paso.icono,
              color: esActual ? Colors.white : colors.brand,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paso.instruccion,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colors.fg,
                  ),
                ),
                if (paso.distanciaMetros > 0)
                  Text(
                    'hacia ${paso.destino.nombre}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.fgMuted,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            width: 28,
            alignment: Alignment.center,
            child: Text(
              '$numero',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: esActual ? colors.brand : colors.fgSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Indicador de posición virtual (modo simulación) ─────────────────────────

/// Cruz roja que indica dónde el usuario "soltó" la posición virtual.
/// El dot azul real (calculado por trilateración) suele estar cerca pero
/// no exactamente encima — la diferencia es el efecto combinado del
/// ruido en las lecturas sintéticas, la media móvil, y el snap-to-graph.
class _TargetIndicator extends StatelessWidget {
  final Color color;
  const _TargetIndicator({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _TargetPainter(color: color)),
    );
  }
}

class _TargetPainter extends CustomPainter {
  final Color color;
  const _TargetPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final c = Offset(size.width / 2, size.height / 2);

    // Círculo exterior
    canvas.drawCircle(c, 7, paint);
    // Cruz interior
    canvas.drawLine(Offset(c.dx - 4, c.dy), Offset(c.dx + 4, c.dy), paint);
    canvas.drawLine(Offset(c.dx, c.dy - 4), Offset(c.dx, c.dy + 4), paint);
  }

  @override
  bool shouldRepaint(_TargetPainter old) => old.color != color;
}

// ─── Overlay de debug (solo en builds de debug) ──────────────────────────────

/// Panel translúcido que muestra el estado interno del posicionamiento.
///
/// No tiene equivalente visual en builds de release — su único propósito
/// es ayudar a diagnosticar problemas de calibración durante desarrollo y
/// pruebas en campo.
///
/// Para cada baliza activa muestra: minor, RSSI (dBm), distancia estimada
/// (m) y edad de la última lectura (ms con código de color: verde <1s,
/// amarillo <2s, rojo >=2s).
///
/// Para la posición, compara la cruda (centroide ponderado puro) con la
/// proyectada al grafo (snap-to-graph). Si la diferencia es grande, el
/// snap está corrigiendo mucho — útil para detectar problemas de
/// calibración o de modelado del grafo.
class _DebugOverlay extends StatelessWidget {
  final PositioningService positioningService;
  final Position? posicionSnapped;

  const _DebugOverlay({
    required this.positioningService,
    required this.posicionSnapped,
  });

  @override
  Widget build(BuildContext context) {
    final lecturas = positioningService.debugLecturas;
    final posCruda = positioningService.debugPosicionCruda;

    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'DEBUG · POSICIONAMIENTO',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.7),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          if (lecturas.isEmpty)
            const Text(
              'sin balizas',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: Colors.white60,
              ),
            )
          else ...[
            const _LineaDebug(
              'minor   rssi      d       edad',
              isHeader: true,
            ),
            ...lecturas.values.map((b) => _LineaBeacon(info: b)),
          ],
          const SizedBox(height: 8),
          _LineaCoords(label: 'cruda', pos: posCruda, color: Colors.orange),
          _LineaCoords(
              label: 'snap ', pos: posicionSnapped, color: Colors.lightGreenAccent),
          if (posCruda != null && posicionSnapped != null) ...[
            const SizedBox(height: 2),
            _LineaDebug(
              '|Δ| = ${_distancia(posCruda, posicionSnapped!).toStringAsFixed(2)} m',
              color: Colors.white70,
            ),
          ],
        ],
      ),
    );
  }

  double _distancia(Position a, Position b) =>
      sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2));
}

class _LineaDebug extends StatelessWidget {
  final String texto;
  final bool isHeader;
  final Color color;

  const _LineaDebug(this.texto,
      {this.isHeader = false, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return Text(
      texto,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: isHeader ? 9 : 10,
        fontWeight: isHeader ? FontWeight.w700 : FontWeight.w500,
        color: isHeader ? color.withValues(alpha: 0.6) : color,
      ),
    );
  }
}

class _LineaBeacon extends StatelessWidget {
  final BeaconDebugInfo info;
  const _LineaBeacon({required this.info});

  @override
  Widget build(BuildContext context) {
    final edad = info.edadMs;
    final Color colorEdad;
    if (edad < 1000) {
      colorEdad = Colors.lightGreenAccent;
    } else if (edad < 2000) {
      colorEdad = Colors.amberAccent;
    } else {
      colorEdad = Colors.redAccent;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              info.minor.toString().padLeft(3),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: Colors.white,
              ),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              '${info.rssi.toStringAsFixed(0).padLeft(4)}dBm',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: Colors.white,
              ),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
              '${info.distanciaEstimada.toStringAsFixed(1).padLeft(4)}m',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: Colors.white,
              ),
            ),
          ),
          Text(
            '${edad}ms',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: colorEdad,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineaCoords extends StatelessWidget {
  final String label;
  final Position? pos;
  final Color color;

  const _LineaCoords({
    required this.label,
    required this.pos,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final texto = pos == null
        ? '$label  —'
        : '$label  (${pos!.x.toStringAsFixed(2)}, '
            '${pos!.y.toStringAsFixed(2)})';
    return Text(
      texto,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 10,
        color: color,
      ),
    );
  }
}
