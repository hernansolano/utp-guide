import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/repositories/grafo_repository.dart';
import '../../models/nodo.dart';
import '../../models/perfil_movilidad.dart';
import '../../models/position.dart';
import '../../models/tipo_nodo.dart';
import '../../services/ble_service.dart' show BleEstado;
import '../../services/positioning_service.dart';
import '../theme/app_theme.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/map_view.dart';
import '../widgets/mapa_painter.dart';

/// Pantalla de exploración libre del mapa.
///
/// A diferencia de [MapaScreen] (que requiere un destino fijo y muestra
/// la ruta), esta pantalla permite al usuario:
/// - Ver el mapa del piso con pan/zoom libre.
/// - Ver todos los POIs (salones, baños, oficinas, etc.) como dots
///   coloreados sobre el SVG.
/// - Tocar cerca de un POI para que se resalte y aparezca un panel con
///   su info + botón "Ir aquí" que navega a `/mapa` con ese destino.
///
/// El BottomNav `Mapa` apunta a esta pantalla (antes apuntaba a
/// `/search`, lo cual no permitía exploración visual).
class ExplorarScreen extends StatefulWidget {
  final GrafoRepository grafoRepository;
  final PositioningService positioningService;
  final ValueNotifier<bool> accesibleSoloRutasNotifier;
  final ValueNotifier<bool> modoSimulacionNotifier;
  final ValueNotifier<Position?> posicionVirtualNotifier;

  const ExplorarScreen({
    super.key,
    required this.grafoRepository,
    required this.positioningService,
    required this.accesibleSoloRutasNotifier,
    required this.modoSimulacionNotifier,
    required this.posicionVirtualNotifier,
  });

  @override
  State<ExplorarScreen> createState() => _ExplorarScreenState();
}

class _ExplorarScreenState extends State<ExplorarScreen> {
  /// Distancia máxima (en metros del grafo) para considerar que un tap
  /// "cayó sobre" un POI. Vale ~1 m porque el usuario puede tocar al
  /// lado del dot y debería seleccionarse igual.
  static const _toleranciaTapMetros = 1.2;

  /// Tipos de nodo que NO mostramos como POI navegable. `interseccion`
  /// y `marcadorAr` son auxiliares del grafo, no destinos reales.
  static const _tiposOcultos = {
    TipoNodo.interseccion,
    TipoNodo.marcadorAr,
  };

  Size? _mapaSize;
  String? _svgPath;
  List<Nodo> _pois = const [];
  String? _error;
  bool _cargando = true;

  Nodo? _poiSeleccionado;
  BleEstado _bleEstado = BleEstado.inactivo;
  bool _avisoBlePendiente = false;

  // Notifiers para que el dot del usuario y el chip BLE rebuildeen
  // solos sin tocar el resto del Stack (mismo patrón que MapaScreen).
  final ValueNotifier<Position?> _posicionUsuarioNotifier =
      ValueNotifier<Position?>(null);
  final ValueNotifier<int> _beaconsActivosNotifier = ValueNotifier<int>(0);

  StreamSubscription<Position?>? _posSub;
  StreamSubscription<BleEstado>? _estadoSub;

  final _mapController = MapViewController();

  @override
  void initState() {
    super.initState();
    _mapController.addListener(_onControllerCambio);
    _cargar();
    _iniciarPosicionamiento();
  }

  void _onControllerCambio() {
    if (mounted) setState(() {});
  }

  Future<void> _cargar() async {
    try {
      final dims = await widget.grafoRepository.obtenerDimensionesMapa();
      final svg = await widget.grafoRepository.obtenerMapaSvgPath();
      final nodos = await widget.grafoRepository.obtenerNodos();
      final pois = nodos.where((n) => !_tiposOcultos.contains(n.tipo)).toList();
      if (!mounted) return;
      setState(() {
        _mapaSize = Size(dims.anchoMetros, dims.altoMetros);
        _svgPath = svg;
        _pois = pois;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el mapa.';
        _cargando = false;
      });
    }
  }

  void _iniciarPosicionamiento() {
    _estadoSub = widget.positioningService.estadoBleStream.listen((e) {
      if (!mounted) return;
      setState(() {
        _bleEstado = e;
        if (e == BleEstado.escaneando || e == BleEstado.simulando) {
          _avisoBlePendiente = false;
        }
      });
    });
    _posSub = widget.positioningService.posicionStream.listen((pos) {
      if (!mounted) return;
      _posicionUsuarioNotifier.value = pos;
      _beaconsActivosNotifier.value =
          widget.positioningService.beaconsActivos;
    });
    _bleEstado = widget.positioningService.estadoBleActual;
    widget.positioningService.iniciar();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _estadoSub?.cancel();
    _mapController.removeListener(_onControllerCambio);
    _mapController.dispose();
    _posicionUsuarioNotifier.dispose();
    _beaconsActivosNotifier.dispose();
    widget.positioningService.detener();
    super.dispose();
  }

  // ─── Gestos / lógica ──────────────────────────────────────────────────────

  /// El usuario tocó el mapa en estas coords (metros). Buscamos el POI
  /// más cercano dentro de la tolerancia; si hay match, lo seleccionamos
  /// y aparece el bottom sheet con su info. Si no, limpiamos selección.
  void _onTapMapa(Offset metros) {
    Nodo? mejor;
    double mejorDist = double.infinity;
    for (final poi in _pois) {
      final dx = poi.x - metros.dx;
      final dy = poi.y - metros.dy;
      final d = sqrt(dx * dx + dy * dy);
      if (d < mejorDist) {
        mejorDist = d;
        mejor = poi;
      }
    }
    setState(() {
      _poiSeleccionado =
          (mejor != null && mejorDist <= _toleranciaTapMetros) ? mejor : null;
    });
  }

  void _irHaciaPoi(Nodo poi) {
    final perfil = widget.accesibleSoloRutasNotifier.value
        ? PerfilMovilidad.accesible
        : PerfilMovilidad.estandar;
    context.push('/mapa', extra: {
      'destinoId': poi.id,
      'perfil': perfil.name,
    });
  }

  /// Distancia euclidiana entre la posición BLE actual y el POI, en m.
  /// Null si no hay señal BLE.
  double? _distanciaDesdeUsuario(Nodo poi) {
    final pos = _posicionUsuarioNotifier.value;
    if (pos == null) return null;
    final dx = poi.x - pos.x;
    final dy = poi.y - pos.y;
    return sqrt(dx * dx + dy * dy);
  }

  Future<void> _mostrarDialogoBleSiAplica() async {
    if (_avisoBlePendiente) return;
    if (_bleEstado != BleEstado.permisosNegados &&
        _bleEstado != BleEstado.bluetoothApagado) {
      return;
    }
    _avisoBlePendiente = true;
    final colors = context.colors;
    final esPermisos = _bleEstado == BleEstado.permisosNegados;

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          esPermisos ? 'Activá los permisos' : 'Activá el Bluetooth',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.fg,
          ),
        ),
        content: Text(
          esPermisos
              ? 'UTP-Guide necesita acceso a Bluetooth para calcular tu '
                  'posición dentro del edificio. Tocá "Reintentar" o '
                  'activalos en Ajustes del sistema.'
              : 'El Bluetooth está apagado. Activalo desde el panel de '
                  'control rápido para ver tu posición en el mapa.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: colors.fgMuted,
            height: 1.5,
          ),
        ),
        actions: [
          if (esPermisos)
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                final ok =
                    await widget.positioningService.reintentarPermisosBle();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Permisos OK · escaneando'
                        : 'Permisos siguen denegados'),
                    duration: const Duration(seconds: 3),
                  ),
                );
              },
              child: Text(
                'Reintentar',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w600,
                  color: colors.brand,
                ),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Entendido',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w600,
                color: colors.fgMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onTapBotonUbicacion() {
    final tienePos = _posicionUsuarioNotifier.value != null;
    if (!tienePos) {
      _mapController.encuadrarTodo();
      return;
    }
    if (_mapController.siguiendoUsuario) {
      _mapController.recentrarEnUsuario(zoomDeseado: 3.5);
    } else {
      _mapController.activarSeguirUsuario(zoomDeseado: 2.2);
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
          child: Text(
            _error!,
            style: GoogleFonts.plusJakartaSans(color: colors.fg),
          ),
        ),
      );
    }

    final mapaSize = _mapaSize!;
    final poiSel = _poiSeleccionado;

    return Scaffold(
      backgroundColor: colors.bgMuted,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                // Mapa libre con todos los POIs.
                Positioned.fill(
                  child: ValueListenableBuilder<Position?>(
                    valueListenable: _posicionUsuarioNotifier,
                    builder: (_, posUsuario, _) {
                      return MapView(
                        mapaSize: mapaSize,
                        svgAsset: _svgPath,
                        posicionUsuario: posUsuario,
                        pois: _pois,
                        poiResaltadoId: poiSel?.id,
                        panZoomHabilitado: true,
                        onTapMundo: _onTapMapa,
                        controller: _mapController,
                      );
                    },
                  ),
                ),

                // Header con back + título.
                Positioned(
                  top: MediaQuery.of(context).padding.top + 12,
                  left: 20,
                  right: 20,
                  child: _buildHeaderPill(context, colors),
                ),

                // Botón ubicación lateral.
                Positioned(
                  right: 20,
                  top: MediaQuery.of(context).padding.top + 80,
                  child: _sideButton(
                    context,
                    colors,
                    _mapController.siguiendoUsuario
                        ? Icons.gps_fixed_rounded
                        : Icons.gps_not_fixed_rounded,
                    _onTapBotonUbicacion,
                    activo: _mapController.siguiendoUsuario,
                  ),
                ),

                // Leyenda compacta de colores (esquina superior derecha).
                Positioned(
                  right: 20,
                  top: MediaQuery.of(context).padding.top + 140,
                  child: _buildLeyenda(context, colors),
                ),

                // Chip BLE inferior-izquierda.
                Positioned(
                  left: 16,
                  bottom: poiSel != null ? 200 : 16,
                  child: ListenableBuilder(
                    listenable: Listenable.merge(
                        [_posicionUsuarioNotifier, _beaconsActivosNotifier]),
                    builder: (_, _) => _buildBleChip(colors),
                  ),
                ),

                // Panel del POI seleccionado.
                if (poiSel != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: _buildPoiCard(context, colors, poiSel),
                  ),
              ],
            ),
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

  Widget _buildHeaderPill(BuildContext context, AppColors colors) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colors.surfaceElevated.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.canPop() ? context.pop() : context.go('/'),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.bgSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.arrow_back_rounded,
                  color: colors.fg, size: 20),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Explorar mapa',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.fg,
                  ),
                ),
                Text(
                  'Tocá un punto para verlo',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: colors.fgMuted,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => context.push('/search'),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.bgSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.search_rounded,
                  color: colors.fg, size: 20),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  /// Leyenda mínima con los 4 tipos más comunes. Compacta para no
  /// estorbar la vista.
  Widget _buildLeyenda(BuildContext context, AppColors colors) {
    final entradas = <(TipoNodo, String)>[
      (TipoNodo.salon, 'Salón'),
      (TipoNodo.bano, 'Baño'),
      (TipoNodo.oficina, 'Oficina'),
      (TipoNodo.entrada, 'Salida'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceElevated.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in entradas)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: MapaPainter.colorParaTipo(e.$1),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    e.$2,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: colors.fg,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sideButton(
    BuildContext context,
    AppColors colors,
    IconData icon,
    VoidCallback onTap, {
    bool activo = false,
  }) {
    return GestureDetector(
      onTap: onTap,
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
        child: Icon(icon,
            color: activo ? Colors.white : colors.fg, size: 20),
      ),
    );
  }

  Widget _buildBleChip(AppColors colors) {
    final tienePos = _posicionUsuarioNotifier.value != null;
    final beacons = _beaconsActivosNotifier.value;
    final escaneando = _bleEstado == BleEstado.escaneando ||
        _bleEstado == BleEstado.simulando;
    final bgColor = tienePos ? colors.accessible : colors.bgMuted;
    final fgColor = tienePos ? Colors.white : colors.fgSoft;
    final label = tienePos
        ? 'BLE · $beacons baliza${beacons != 1 ? 's' : ''}'
        : (escaneando ? 'Escaneando…' : 'Sin señal BLE');

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

  Widget _buildPoiCard(BuildContext context, AppColors colors, Nodo poi) {
    final dist = _distanciaDesdeUsuario(poi);
    final colorTipo = MapaPainter.colorParaTipo(poi.tipo);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorTipo.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorTipo, width: 1.2),
                ),
                alignment: Alignment.center,
                child: Icon(_iconoParaTipo(poi.tipo),
                    color: colorTipo, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      poi.nombre,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colors.fg,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _etiquetaTipo(poi.tipo) +
                          (dist != null
                              ? ' · ${dist.toStringAsFixed(1)} m de ti'
                              : ''),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colors.fgMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () =>
                    setState(() => _poiSeleccionado = null),
                icon: Icon(Icons.close_rounded, color: colors.fgSoft),
                tooltip: 'Cerrar',
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _irHaciaPoi(poi),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.brand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.navigation_rounded, size: 18),
              label: Text(
                'Ir aquí',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static IconData _iconoParaTipo(TipoNodo tipo) {
    switch (tipo) {
      case TipoNodo.salon:
        return Icons.school_outlined;
      case TipoNodo.bano:
        return Icons.wc_outlined;
      case TipoNodo.oficina:
        return Icons.business_outlined;
      case TipoNodo.entrada:
        return Icons.door_front_door_outlined;
      case TipoNodo.escalera:
        return Icons.stairs_outlined;
      case TipoNodo.ascensor:
        return Icons.elevator_outlined;
      case TipoNodo.bebedero:
        return Icons.water_drop_outlined;
      case TipoNodo.comedor:
        return Icons.restaurant_outlined;
      case TipoNodo.interseccion:
      case TipoNodo.marcadorAr:
        return Icons.place_outlined;
    }
  }

  static String _etiquetaTipo(TipoNodo tipo) {
    switch (tipo) {
      case TipoNodo.salon:
        return 'Salón';
      case TipoNodo.bano:
        return 'Baños';
      case TipoNodo.oficina:
        return 'Oficina';
      case TipoNodo.entrada:
        return 'Entrada / Salida';
      case TipoNodo.escalera:
        return 'Escalera';
      case TipoNodo.ascensor:
        return 'Ascensor';
      case TipoNodo.bebedero:
        return 'Bebedero';
      case TipoNodo.comedor:
        return 'Comedor';
      case TipoNodo.interseccion:
        return 'Punto de paso';
      case TipoNodo.marcadorAr:
        return 'Marcador AR';
    }
  }
}
