import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../models/nodo.dart';
import '../../models/perfil_movilidad.dart';
import '../../models/position.dart';
import '../../models/tipo_nodo.dart';
import '../../services/positioning_service.dart';
import '../../services/routing_service.dart';
import '../theme/app_theme.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/mapa_painter.dart';
import '../widgets/minimap_widget.dart';

class MapaScreen extends StatefulWidget {
  final String destinoId;
  final PerfilMovilidad perfil;
  final RoutingService routingService;
  final PositioningService positioningService;

  const MapaScreen({
    super.key,
    required this.destinoId,
    required this.perfil,
    required this.routingService,
    required this.positioningService,
  });

  @override
  State<MapaScreen> createState() => _MapaScreenState();
}

class _MapaScreenState extends State<MapaScreen> {
  List<Nodo> _ruta = [];
  String? _error;
  bool _cargando = true;
  bool _enModoAR = false;

  // Posición BLE del usuario (null = sin señal)
  Position? _posicionUsuario;
  int _beaconsActivos = 0;

  // Tamaño del mapa en metros — debe coincidir con grafo.json
  static const _mapaSize = Size(5.0, 5.0);

  StreamSubscription<AccelerometerEvent>? _acelerometroSub;
  StreamSubscription<Position?>? _posicionSub;

  @override
  void initState() {
    super.initState();
    _calcularRuta();
    _iniciarAcelerometro();
    _iniciarPosicionamiento();
  }

  // ─── Ruta ──────────────────────────────────────────────────────────────────

  Future<void> _calcularRuta() async {
    try {
      final entradas =
          await widget.routingService.nodosPorTipo(TipoNodo.entrada);
      if (entradas.isEmpty) throw Exception('Sin nodo de entrada');

      final ruta = await widget.routingService.calcularRuta(
        origenId: entradas.first.id,
        destinoId: widget.destinoId,
        perfil: widget.perfil,
      );
      if (mounted) setState(() { _ruta = ruta; _cargando = false; });
    } catch (e) {
      if (mounted) {
        setState(() { _error = _mensajeError(e); _cargando = false; });
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
      final angulo =
          atan2(event.z, sqrt(event.x * event.x + event.y * event.y));
      final grados = angulo * 180 / pi;
      // Histéresis deliberada: >35° activa AR, <25° desactiva
      if (!_enModoAR && grados > 35) setState(() => _enModoAR = true);
      if (_enModoAR && grados < 25) setState(() => _enModoAR = false);
    });
  }

  // ─── Posicionamiento BLE ───────────────────────────────────────────────────

  void _iniciarPosicionamiento() {
    widget.positioningService.iniciar();
    _posicionSub = widget.positioningService.posicionStream.listen((pos) {
      if (mounted) {
        setState(() {
          _posicionUsuario = pos;
          _beaconsActivos = widget.positioningService.beaconsActivos;
        });
      }
    });
  }

  // ─── Distancia real de la ruta ─────────────────────────────────────────────

  /// Suma de distancias euclidianas entre nodos consecutivos de la ruta.
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
    // Velocidad media peatonal: 1.2 m/s
    final segundos = (metros / 1.2).round();
    if (segundos < 60) return '${segundos}s';
    return '${(segundos / 60).ceil()} min';
  }

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _acelerometroSub?.cancel();
    _posicionSub?.cancel();
    widget.positioningService.detener();
    super.dispose();
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final nombreDestino =
        _ruta.isNotEmpty ? _ruta.last.nombre : widget.destinoId;

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
                    fontSize: 16, color: colors.fg, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final dist = _distanciaRuta();

    return Scaffold(
      backgroundColor: colors.bgMuted,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Capa 1: mapa SVG
                SvgPicture.asset(
                  'assets/maps/test_room_5x5.svg',
                  fit: BoxFit.contain,
                ),

                // Capa 2: ruta + punto de usuario
                LayoutBuilder(
                  builder: (ctx, constraints) => CustomPaint(
                    painter: MapaPainter.fromContext(
                      ctx,
                      ruta: _ruta,
                      mapaSize: _mapaSize,
                      posicionUsuario: _posicionUsuario,
                    ),
                    size: Size(constraints.maxWidth, constraints.maxHeight),
                  ),
                ),

                // Capa 3: pill de destino (top)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 20,
                  right: 20,
                  child: _buildDestinationPill(
                      context, colors, nombreDestino, dist),
                ),

                // Controles laterales
                Positioned(
                  right: 20,
                  top: MediaQuery.of(context).padding.top + 80,
                  child: Column(
                    children: [
                      _sideButton(context, colors,
                          Icons.my_location_rounded, () {}),
                      const SizedBox(height: 10),
                      _sideButton(context, colors,
                          Icons.format_list_bulleted_rounded, () {}),
                    ],
                  ),
                ),

                // Indicador BLE (esquina inferior izquierda, solo si no AR)
                if (!_enModoAR)
                  Positioned(
                    left: 16,
                    bottom: 16,
                    child: _buildBleChip(colors),
                  ),

                // FAB AR/Mapa (esquina inferior derecha)
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

                // Minimapa (solo modo AR, esquina inferior izquierda)
                if (_enModoAR)
                  Positioned(
                    left: 16,
                    bottom: 16,
                    child: MinimapWidget(
                      ruta: _ruta,
                      mapaSize: _mapaSize,
                    ),
                  ),
              ],
            ),
          ),

          // Tarjeta de navegación
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
          _pillIconButton(Icons.volume_up_rounded, () {}, Colors.white),
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

  Widget _sideButton(BuildContext context, AppColors colors, IconData icon,
      VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: colors.surfaceElevated.withValues(alpha: 0.92),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
            ),
          ],
        ),
        child: Icon(icon, color: colors.fg, size: 20),
      ),
    );
  }

  /// Chip de estado BLE: muestra cuántos beacons están activos y
  /// si se detectó posición. Útil para calibrar durante las pruebas.
  Widget _buildBleChip(AppColors colors) {
    final tienePos = _posicionUsuario != null;
    final bgColor = tienePos ? colors.accessible : colors.bgMuted;
    final fgColor = tienePos ? Colors.white : colors.fgSoft;
    final label = tienePos
        ? 'BLE · $_beaconsActivos beacon${_beaconsActivos != 1 ? 's' : ''}'
        : 'Sin señal BLE';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 6),
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
              color: colors.brandSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child:
                Icon(Icons.turn_left_rounded, color: colors.brand, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dirígete hacia $nombre',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.fg,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _posicionUsuario != null
                      ? 'Posición: (${_posicionUsuario!.x.toStringAsFixed(1)} m, '
                          '${_posicionUsuario!.y.toStringAsFixed(1)} m)'
                      : 'Esperando señal BLE…',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colors.fgMuted,
                  ),
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
