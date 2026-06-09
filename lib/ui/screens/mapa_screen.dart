import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
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
import '../widgets/map_view.dart';
import '../widgets/minimap_widget.dart';

/// Pantalla principal de navegación.
///
/// Renderiza el mapa via [MapView] (que maneja pan, zoom, seguir al
/// usuario, encuadrar la ruta), más los overlays propios: pill con
/// destino, controles laterales, FAB AR, tarjeta inferior con el paso
/// actual, debug overlay opcional.
///
/// Las dimensiones del piso se leen de `GrafoRepository` en `initState`.
/// El cambio mapa↔AR vía acelerómetro respeta `arAutomaticoNotifier`.
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
  int _pasoActualIndice = 0;
  String? _error;
  bool _cargando = true;
  bool _enModoAR = false;
  bool _recalculandoRuta = false;

  late PerfilMovilidad _perfilActual;

  // Dimensiones del piso (null hasta cargar el grafo).
  Size? _mapaSize;

  /// Path del SVG del piso, leído de `grafo.json → mapa_svg`. Null hasta
  /// que termine la carga inicial.
  String? _svgPath;

  // Posición BLE del usuario expuesta como notifier — así el rebuild
  // por cada lectura se aísla al MapView y al chip BLE, en lugar de
  // hacer setState global del Stack entero (6+ widgets de overlay).
  // Crítico para Android: las lecturas pueden llegar a 6-10 Hz.
  final ValueNotifier<Position?> _posicionUsuarioNotifier =
      ValueNotifier<Position?>(null);
  final ValueNotifier<int> _beaconsActivosNotifier = ValueNotifier<int>(0);

  BleEstado _bleEstado = BleEstado.inactivo;
  bool _dialogoBlePendiente = false;

  /// Token que se incrementa con cada recálculo de ruta. Al recibir
  /// el resultado, comparamos contra el token actual: si no coincide,
  /// el resultado es obsoleto y se descarta. Defensa en profundidad
  /// contra carreras (el guard `_recalculandoRuta` previene el caso
  /// inmediato, este token cubre escenarios futuros).
  int _tokenRecalculo = 0;

  StreamSubscription<AccelerometerEvent>? _acelerometroSub;
  StreamSubscription<Position?>? _posicionSub;
  StreamSubscription<BleEstado>? _estadoBleSub;

  /// Controlador imperativo del MapView. Permite invocar recentrar,
  /// encuadrar y activar el modo seguir desde los botones laterales.
  final _mapController = MapViewController();

  @override
  void initState() {
    super.initState();
    _perfilActual = widget.perfil;
    _mapController.addListener(_onMapControllerCambio);
    _cargarRutaYDimensiones();
    _iniciarAcelerometro();
    _iniciarPosicionamiento();
  }

  void _onMapControllerCambio() {
    // Rebuild cuando cambia el estado de seguirUsuario para que el
    // icono del botón se actualice (filled vs outlined).
    if (mounted) setState(() {});
  }

  // ─── Carga inicial: dimensiones + ruta ─────────────────────────────────────

  Future<void> _cargarRutaYDimensiones() async {
    try {
      final futureDims = widget.grafoRepository.obtenerDimensionesMapa();
      final futureSvg = widget.grafoRepository.obtenerMapaSvgPath();
      final futureEntradas =
          widget.routingService.nodosPorTipo(TipoNodo.entrada);

      final dims = await futureDims;
      final svgPath = await futureSvg;
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
          _svgPath = svgPath;
          _ruta = ruta;
          _pasos = PasoNavegacion.generarDesdeRuta(ruta);
          _pasoActualIndice = 0;
          _cargando = false;
        });
        // Tras el primer frame, encuadrar la ruta automáticamente — UX
        // estilo Google Maps que muestra el destino completo al inicio.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _mapController.encuadrarRuta();
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

  Future<void> _alternarPerfilMovilidad() async {
    if (_recalculandoRuta) return;
    final nuevoPerfil = _perfilActual == PerfilMovilidad.estandar
        ? PerfilMovilidad.accesible
        : PerfilMovilidad.estandar;

    // Token local: si otro recálculo arranca después, este queda obsoleto.
    final tokenLocal = ++_tokenRecalculo;
    setState(() => _recalculandoRuta = true);
    try {
      final entradas =
          await widget.routingService.nodosPorTipo(TipoNodo.entrada);
      // Si llegó un recálculo más nuevo, descartar este resultado.
      if (!mounted || tokenLocal != _tokenRecalculo) return;

      final nuevaRuta = await widget.routingService.calcularRuta(
        origenId: entradas.first.id,
        destinoId: widget.destinoId,
        perfil: nuevoPerfil,
      );
      if (!mounted || tokenLocal != _tokenRecalculo) return;

      setState(() {
        _perfilActual = nuevoPerfil;
        _ruta = nuevaRuta;
        _pasos = PasoNavegacion.generarDesdeRuta(nuevaRuta);
        _pasoActualIndice = 0;
        _recalculandoRuta = false;
      });
      // Re-encuadrar la nueva ruta.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.encuadrarRuta();
      });
    } catch (e) {
      if (!mounted || tokenLocal != _tokenRecalculo) return;
      setState(() => _recalculandoRuta = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_mensajeError(e)),
          duration: const Duration(seconds: 3),
        ),
      );
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

  // ─── Acelerómetro ──────────────────────────────────────────────────────────

  void _iniciarAcelerometro() {
    _acelerometroSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 200),
    ).listen((event) {
      if (!widget.arAutomaticoNotifier.value) return;
      final angulo =
          atan2(event.z, sqrt(event.x * event.x + event.y * event.y));
      final grados = angulo * 180 / pi;
      if (!_enModoAR && grados > 35) setState(() => _enModoAR = true);
      if (_enModoAR && grados < 25) setState(() => _enModoAR = false);
    });
  }

  // ─── Posicionamiento BLE ───────────────────────────────────────────────────

  void _iniciarPosicionamiento() {
    _estadoBleSub =
        widget.positioningService.estadoBleStream.listen((estado) {
      if (!mounted) return;
      setState(() {
        _bleEstado = estado;
        // Resetear el flag del diálogo cuando el estado vuelve a uno
        // bueno. Si después el usuario vuelve a apagar el BT, el diálogo
        // reaparecerá. Sin esto, una sola dismissal silenciaba el aviso
        // de por vida en esa pantalla.
        if (estado == BleEstado.escaneando || estado == BleEstado.simulando) {
          _dialogoBlePendiente = false;
        }
      });
    });

    _posicionSub = widget.positioningService.posicionStream.listen((pos) {
      if (!mounted) return;
      // Updates de alta frecuencia van por notifiers — no causan
      // rebuild del Stack completo.
      _posicionUsuarioNotifier.value = pos;
      _beaconsActivosNotifier.value =
          widget.positioningService.beaconsActivos;

      // El paso actual cambia con baja frecuencia (al cruzar un nodo).
      // Solo setState cuando realmente cambia, para que la navigation
      // card se actualice sin rebuild en cada lectura.
      final nuevoIndice = _calcularPasoActual(pos);
      if (nuevoIndice != _pasoActualIndice) {
        setState(() => _pasoActualIndice = nuevoIndice);
        if (widget.vozHabilitadaNotifier.value &&
            _pasos.isNotEmpty &&
            nuevoIndice < _pasos.length) {
          widget.ttsService.hablar(_pasos[nuevoIndice].instruccion);
        }
      }
    });

    widget.positioningService.iniciar();
  }

  Future<void> _mostrarDialogoBleSiAplica() async {
    if (_dialogoBlePendiente) return;
    if (_bleEstado != BleEstado.permisosNegados &&
        _bleEstado != BleEstado.bluetoothApagado) {
      return;
    }

    _dialogoBlePendiente = true;
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

  // ─── Cámara del mapa ──────────────────────────────────────────────────────

  /// Lógica del botón "ubicación" estilo Google Maps:
  /// - Sin posición BLE → encuadrar la ruta completa
  /// - Con posición + no siguiendo → centrar y activar modo seguir
  /// - Con posición + siguiendo → zoom-in adicional (vista cercana)
  void _onTapBotonUbicacion() {
    if (_posicionUsuarioNotifier.value == null) {
      _mapController.encuadrarRuta();
      return;
    }
    if (_mapController.siguiendoUsuario) {
      // Ya siguiendo — acercar la cámara para vista detallada.
      _mapController.recentrarEnUsuario(zoomDeseado: 3.5);
    } else {
      // Activar seguimiento con zoom moderado.
      _mapController.activarSeguirUsuario(zoomDeseado: 2.2);
    }
  }

  // ─── Cálculo del paso actual ─────────────────────────────────────────────

  int _calcularPasoActual(Position? pos) {
    if (pos == null || _ruta.length < 2 || _pasos.isEmpty) return 0;

    final destino = _ruta.last;
    final distAlDestino =
        sqrt(pow(pos.x - destino.x, 2) + pow(pos.y - destino.y, 2));
    if (distAlDestino < 1.0) return _pasos.length - 1;

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
    return mejorSegmento;
  }

  double _distanciaPuntoASegmento(
      double px, double py, double ax, double ay, double bx, double by) {
    final dx = bx - ax;
    final dy = by - ay;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) return sqrt(pow(px - ax, 2) + pow(py - ay, 2));
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _PasosBottomSheet(
        pasos: _pasos,
        indiceActual: _pasoActualIndice,
        distanciaTotal: _distanciaRuta(),
      ),
    );
  }

  // ─── Modo simulación: callback de drag ─────────────────────────────────────

  /// El MapView ya nos da las coordenadas en metros (sistema del grafo).
  /// Solo construimos el Position y lo propagamos al notifier.
  void _onTapPosicionVirtual(Offset metros) {
    widget.posicionVirtualNotifier.value = Position(
      x: metros.dx,
      y: metros.dy,
      piso: 1,
      timestamp: DateTime.now(),
    );
  }

  // ─── Distancia y tiempo de la ruta ─────────────────────────────────────────

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
    _mapController.removeListener(_onMapControllerCambio);
    _mapController.dispose();
    _posicionUsuarioNotifier.dispose();
    _beaconsActivosNotifier.dispose();
    widget.ttsService.detener();
    widget.positioningService.detener();
    super.dispose();
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

    final mapaSize = _mapaSize!;
    final dist = _distanciaRuta();

    return Scaffold(
      backgroundColor: colors.bgMuted,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                // Mapa principal: MapView encapsula SVG + ruta + dot
                // + pan/zoom + animaciones de cámara. Solo rebuilda
                // cuando cambia simulación/posición virtual/dot — no
                // cuando cambia algo del overlay.
                Positioned.fill(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: widget.modoSimulacionNotifier,
                    builder: (_, simulando, _) {
                      return ValueListenableBuilder<Position?>(
                        valueListenable: widget.posicionVirtualNotifier,
                        builder: (_, posVirtual, _) {
                          return ValueListenableBuilder<Position?>(
                            valueListenable: _posicionUsuarioNotifier,
                            builder: (_, posUsuario, _) {
                              return MapView(
                                mapaSize: mapaSize,
                                svgAsset: _svgPath,
                                ruta: _ruta,
                                posicionUsuario: posUsuario,
                                posicionTarget: simulando ? posVirtual : null,
                                panZoomHabilitado: !simulando,
                                onTapMundo: simulando ? _onTapPosicionVirtual : null,
                                controller: _mapController,
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),

                // Pill superior con destino.
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 20,
                  right: 20,
                  child: _buildDestinationPill(
                      context, colors, nombreDestino, dist),
                ),

                // Controles laterales.
                Positioned(
                  right: 20,
                  top: MediaQuery.of(context).padding.top + 80,
                  child: Column(
                    children: [
                      // Botón ubicación: cambia icono según si está siguiendo.
                      _sideButton(
                        context,
                        colors,
                        _mapController.siguiendoUsuario
                            ? Icons.gps_fixed_rounded
                            : Icons.gps_not_fixed_rounded,
                        _onTapBotonUbicacion,
                        activo: _mapController.siguiendoUsuario,
                      ),
                      const SizedBox(height: 10),
                      _sideButton(
                          context,
                          colors,
                          Icons.format_list_bulleted_rounded,
                          _mostrarBottomSheetPasos),
                      const SizedBox(height: 10),
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

                // Chip BLE (esquina inferior izquierda) — escucha los
                // notifiers en lugar de depender de setState global.
                if (!_enModoAR)
                  Positioned(
                    left: 16,
                    bottom: 16,
                    child: ListenableBuilder(
                      listenable: Listenable.merge(
                          [_posicionUsuarioNotifier, _beaconsActivosNotifier]),
                      builder: (_, _) => _buildBleChip(colors),
                    ),
                  ),

                // FAB AR/Mapa.
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

                // Minimapa (modo AR).
                if (_enModoAR)
                  Positioned(
                    left: 16,
                    bottom: 16,
                    child: MinimapWidget(
                      ruta: _ruta,
                      mapaSize: mapaSize,
                    ),
                  ),

                // Debug overlay (solo en debug builds + toggle).
                if (kDebugMode)
                  ValueListenableBuilder<bool>(
                    valueListenable: widget.debugOverlayNotifier,
                    builder: (context, mostrar, _) {
                      if (!mostrar) return const SizedBox.shrink();
                      return Positioned(
                        top: MediaQuery.of(context).padding.top + 80,
                        left: 16,
                        child: ValueListenableBuilder<Position?>(
                          valueListenable: _posicionUsuarioNotifier,
                          builder: (_, pos, _) => _DebugOverlay(
                            positioningService: widget.positioningService,
                            posicionSnapped: pos,
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),

          // La card sigue el notifier de posición para mostrar coords
          // frescas sin requerir setState global del Stack.
          ValueListenableBuilder<Position?>(
            valueListenable: _posicionUsuarioNotifier,
            builder: (_, _, _) =>
                _buildNavigationCard(context, colors, nombreDestino),
          ),

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
    final tienePos = _posicionUsuarioNotifier.value != null;
    final beacons = _beaconsActivosNotifier.value;
    final bgColor = tienePos ? colors.accessible : colors.bgMuted;
    final fgColor = tienePos ? Colors.white : colors.fgSoft;
    final label = tienePos
        ? 'BLE · $beacons baliza${beacons != 1 ? 's' : ''}'
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
    final paso = (_pasos.isNotEmpty && _pasoActualIndice < _pasos.length)
        ? _pasos[_pasoActualIndice]
        : null;
    final esLlegada = paso != null && _pasoActualIndice == _pasos.length - 1;
    final tituloLinea = paso?.instruccion ?? 'Calculando ruta…';
    final iconoPaso = paso?.icono ?? Icons.straight_rounded;

    final posUsuario = _posicionUsuarioNotifier.value;
    final String subtitulo;
    if (esLlegada) {
      subtitulo = '¡Has llegado!';
    } else if (posUsuario != null) {
      subtitulo = 'Paso ${_pasoActualIndice + 1} de ${_pasos.length}'
          ' · (${posUsuario.x.toStringAsFixed(1)} m, '
          '${posUsuario.y.toStringAsFixed(1)} m)';
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

// ─── Overlay de debug (solo en builds de debug) ──────────────────────────────

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
              label: 'snap ',
              pos: posicionSnapped,
              color: Colors.lightGreenAccent),
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
