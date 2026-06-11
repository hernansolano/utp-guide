import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/repositories/beacon_repository.dart';
import '../../data/repositories/grafo_repository.dart';
import '../../models/advertisement_crudo.dart';
import '../../models/beacon_config.dart';
import '../../models/beacon_reading.dart';
import '../../models/beacon_stats.dart';
import '../../models/position.dart';
import '../../services/ble_service.dart' show BleEstado;
import '../../services/positioning_service.dart';
import '../../services/traza_service.dart';
import '../theme/app_theme.dart';
import '../widgets/map_view.dart';

/// Pantalla de calibración en campo (solo visible en debug builds).
///
/// Herramienta para ajustar los parámetros del modelo de path-loss
/// (`n`, `txPower`, ventana de media móvil, tolerancia snap) sin
/// recompilar la app. Útil al instalar las balizas Minew en el edificio
/// real y validar que los valores teóricos coinciden con la propagación
/// medida.
///
/// Flujo típico:
/// 1. Abrir la pantalla parado a una distancia conocida de una baliza
/// 2. Esperar 50-100 muestras (10-20 segundos)
/// 3. Usar la herramienta "Distancia conocida" para que la app sugiera
///    valores de `n` o `txPower` que harían coincidir el cálculo
/// 4. Mover los sliders para aplicar los valores y ver el efecto en vivo
/// 5. Cuando los valores funcionen bien, copiarlos a
///    `assets/data/beacon_config.json` y reiniciar la app
///
/// Ver `docs/adr/0011-calibracion-en-campo.md`.
class CalibracionScreen extends StatefulWidget {
  final PositioningService positioningService;
  final BeaconRepository beaconRepository;
  final GrafoRepository grafoRepository;
  final ValueNotifier<CalibracionPositioning> calibracionNotifier;
  final TrazaService trazaService;
  final ValueNotifier<bool> snapHabilitadoNotifier;
  final ValueNotifier<bool> trazaActivaNotifier;

  const CalibracionScreen({
    super.key,
    required this.positioningService,
    required this.beaconRepository,
    required this.grafoRepository,
    required this.calibracionNotifier,
    required this.trazaService,
    required this.snapHabilitadoNotifier,
    required this.trazaActivaNotifier,
  });

  @override
  State<CalibracionScreen> createState() => _CalibracionScreenState();
}

class _CalibracionScreenState extends State<CalibracionScreen> {
  /// Stats acumuladas por baliza desde que se abrió la pantalla.
  final Map<int, BeaconStats> _stats = {};

  /// txPower por baliza, cacheado de `beacon_config.json` para no hacer
  /// I/O por cada lectura. Incluye los overrides aplicados en vivo, así
  /// el cálculo de distancia de esta pantalla refleja la calibración.
  final Map<int, double> _txPowerPorMinor = {};

  /// txPower que el usuario aplicó manualmente por baliza desde la
  /// herramienta "Distancia conocida". Solo estos se escriben como
  /// `txPower_dbm` en el archivo generado; el resto conserva su valor
  /// original. Vacío = ninguna baliza recalibrada todavía.
  final Map<int, double> _txPowerOverrides = {};

  /// Config completa de las balizas (x/y/descripcion), uuid y major,
  /// leídos al abrir. Necesarios para reconstruir el `beacon_config.json`
  /// completo en la sección "Aplicar permanentemente".
  List<ConfigBeacon> _beaconsConfig = const [];
  String? _uuid;
  int? _major;

  /// Valor de calibración como vino del archivo, para poder restaurarlo.
  late CalibracionPositioning _calibracionOriginal;

  /// Estado de BLE para mostrar warnings.
  BleEstado _bleEstado = BleEstado.inactivo;

  StreamSubscription<BeaconReading>? _readingsSub;
  StreamSubscription<BleEstado>? _estadoSub;
  StreamSubscription<Position?>? _posSub;
  StreamSubscription<AdvertisementCrudo>? _crudoSub;

  /// Si ya se mostró el aviso de "permisos negados" o "BT apagado".
  /// Se resetea al volver a un estado bueno para que reaparezca si el
  /// usuario apaga BT después de cerrarlo.
  bool _avisoBlePendiente = false;

  /// Throttling de rebuilds: las lecturas BLE pueden llegar a 6-10 Hz,
  /// pero la UI no necesita rebuilds tan frecuentes. Acumulamos cambios
  /// y hacemos `setState` máximo cada 250 ms (4 Hz visual). Esto reduce
  /// drásticamente el costo en Android.
  Timer? _throttleTimer;
  bool _hayCambiosPendientes = false;

  /// Últimos advertisements crudos por deviceId (LRU: máximo
  /// [_maxAdvertisementsListados] entries). Se muestra en la sección
  /// "Diagnóstico BLE" para que el dev vea qué emite el simulador o las
  /// balizas físicas, incluso si no son aceptadas por el pipeline.
  static const _maxAdvertisementsListados = 20;
  final LinkedHashMap<String, AdvertisementCrudo> _advertisements =
      LinkedHashMap<String, AdvertisementCrudo>();

  /// Inputs de la herramienta "Distancia conocida".
  int? _minorSeleccionado;
  final _distanciaController = TextEditingController(text: '1.0');

  // ─── Validación end-to-end (A1) ────────────────────────────────────────────

  /// Posición real marcada por el usuario tocando el mini-mapa.
  Position? _posicionReal;

  /// Última posición calculada por el PositioningService.
  Position? _posicionCalculada;

  /// Errores de posición acumulados mientras [_posicionReal] esté marcada.
  final ErrorPosicionStats _errorStats = ErrorPosicionStats();

  /// Dimensiones y SVG del piso, para el mini-mapa de validación.
  Size? _dimensionesMapa;
  String? _svgPath;

  @override
  void initState() {
    super.initState();
    _calibracionOriginal = widget.calibracionNotifier.value;
    widget.calibracionNotifier.addListener(_onCalibracionCambio);
    _cargarConfigs();
    widget.positioningService.iniciar();
    _readingsSub = widget.positioningService.beaconStreamRaw.listen(_onReading);
    _posSub = widget.positioningService.posicionStream.listen(_onPosicion);
    _estadoSub = widget.positioningService.estadoBleStream.listen((e) {
      if (!mounted) return;
      setState(() {
        _bleEstado = e;
        // Si vuelve a estado bueno, permitir que el aviso reaparezca
        // si después el usuario apaga BT/niega permisos otra vez.
        if (e == BleEstado.escaneando || e == BleEstado.simulando) {
          _avisoBlePendiente = false;
        }
      });
    });
    _crudoSub = widget.positioningService.advertisementsCrudosStream
        .listen(_onAdvertisementCrudo);
    _bleEstado = widget.positioningService.estadoBleActual;

    // Timer único que coalesce todos los updates de balizas y advertisements
    // a una sola llamada a setState cada 250 ms.
    _throttleTimer =
        Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_hayCambiosPendientes && mounted) {
        _hayCambiosPendientes = false;
        setState(() {});
      }
    });
  }

  Future<void> _cargarConfigs() async {
    final cal = await widget.beaconRepository.obtenerCalibracion();
    final beacons = await widget.beaconRepository.obtenerTodosLosBeacons();
    final uuid = await widget.beaconRepository.obtenerUuid();
    final major = await widget.beaconRepository.obtenerMajor();
    for (final config in beacons) {
      _stats.putIfAbsent(
        config.minor,
        () => BeaconStats(minor: config.minor, descripcion: config.descripcion),
      );
      _txPowerPorMinor[config.minor] =
          config.txPowerDbm ?? cal.txPowerDbmDefault;
    }
    // Cargar mapa para la sección de validación end-to-end.
    final dims = await widget.grafoRepository.obtenerDimensionesMapa();
    final svg = await widget.grafoRepository.obtenerMapaSvgPath();
    if (mounted) {
      setState(() {
        _beaconsConfig = beacons;
        _uuid = uuid;
        _major = major;
        _dimensionesMapa = Size(dims.anchoMetros, dims.altoMetros);
        _svgPath = svg;
      });
    }
  }

  /// Cada nueva posición calculada: si hay una posición real marcada,
  /// acumular el error (distancia euclidiana entre ambas).
  void _onPosicion(Position? pos) {
    if (!mounted) return;
    setState(() {
      _posicionCalculada = pos;
      if (_posicionReal != null && pos != null) {
        final error = sqrt(
          pow(pos.x - _posicionReal!.x, 2) + pow(pos.y - _posicionReal!.y, 2),
        );
        _errorStats.agregar(error);
      }
    });
  }

  /// El usuario tocó el mini-mapa: ahí está parado realmente. Reseteamos
  /// los errores acumulados para empezar a medir desde esta posición.
  void _onTapPosicionReal(Offset metros) {
    setState(() {
      _posicionReal = Position(
        x: metros.dx,
        y: metros.dy,
        piso: 1,
        timestamp: DateTime.now(),
      );
      _errorStats.reset();
    });
  }

  void _onCalibracionCambio() {
    if (mounted) setState(() {});
  }

  void _onReading(BeaconReading r) {
    final cal = widget.calibracionNotifier.value;
    final txPower = _txPowerPorMinor[r.minor] ?? cal.txPowerDbmDefault;
    final distancia = pow(10.0,
            (txPower - r.rssi) / (10.0 * cal.nExponentePerdida))
        .toDouble();

    final stats = _stats.putIfAbsent(
        r.minor, () => BeaconStats(minor: r.minor));
    stats.agregar(r.rssi, distancia, r.timestamp);
    // Marcar para que el timer haga setState — evita rebuilds por lectura.
    _hayCambiosPendientes = true;
  }

  /// Cada advertisement BLE recibido (filtrado o no). Mantenemos solo el
  /// último por deviceId con cap [_maxAdvertisementsListados] para no
  /// crecer indefinidamente en sesiones largas.
  void _onAdvertisementCrudo(AdvertisementCrudo a) {
    // Si ya existe, lo quitamos antes de re-insertar para que pase al
    // final (LinkedHashMap mantiene orden de inserción).
    _advertisements.remove(a.deviceId);
    _advertisements[a.deviceId] = a;
    while (_advertisements.length > _maxAdvertisementsListados) {
      _advertisements.remove(_advertisements.keys.first);
    }
    _hayCambiosPendientes = true;
  }

  @override
  void dispose() {
    widget.calibracionNotifier.removeListener(_onCalibracionCambio);
    _readingsSub?.cancel();
    _estadoSub?.cancel();
    _posSub?.cancel();
    _crudoSub?.cancel();
    _throttleTimer?.cancel();
    _distanciaController.dispose();
    widget.positioningService.detener();
    super.dispose();
  }

  // ─── Operaciones ───────────────────────────────────────────────────────────

  void _resetearStats() {
    setState(() {
      for (final s in _stats.values) {
        s.reset();
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Estadísticas reseteadas'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _exportarCsv() async {
    final cal = widget.calibracionNotifier.value;
    final buffer = StringBuffer();
    buffer.writeln('# Calibración BLE — UTP-Guide');
    buffer.writeln('# Generado: ${DateTime.now().toIso8601String()}');
    buffer.writeln('# n_exponente_perdida=${cal.nExponentePerdida}, '
        'txPower_default=${cal.txPowerDbmDefault}, '
        'ventana=${cal.ventanaMediaMovil}');
    buffer.writeln(
        'minor,descripcion,samples,rssi_actual,rssi_mean,rssi_std,rssi_min,rssi_max,dist_mean_m');
    for (final s in _stats.values) {
      if (!s.tieneMuestras) continue;
      buffer.writeln(
        '${s.minor},'
        '"${s.descripcion ?? ""}",'
        '${s.samples},'
        '${s.rssiActual.toStringAsFixed(1)},'
        '${s.rssiMean.toStringAsFixed(2)},'
        '${s.rssiStdDev.toStringAsFixed(2)},'
        '${s.rssiMin.toStringAsFixed(1)},'
        '${s.rssiMax.toStringAsFixed(1)},'
        '${s.distanciaMean.toStringAsFixed(2)}',
      );
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('CSV copiado al portapapeles'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _restaurarValoresOriginales() {
    widget.calibracionNotifier.value = _calibracionOriginal;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Valores restaurados del JSON'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _aplicarNuevaCalibracion(CalibracionPositioning nueva) {
    widget.calibracionNotifier.value = nueva;
  }

  /// Aplica el txPower sugerido a una baliza: lo guarda como override
  /// (para el archivo generado) y actualiza el cache vivo para que el
  /// cálculo de distancia de esta pantalla lo refleje de inmediato. No
  /// toca el PositioningService — el efecto en el dot real llega al pegar
  /// el archivo y reiniciar.
  void _aplicarTxPower(int minor, double txPower) {
    setState(() {
      _txPowerOverrides[minor] = txPower;
      _txPowerPorMinor[minor] = txPower;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('txPower de Minor $minor → '
            '${txPower.toStringAsFixed(1)} dBm · afinando…'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Redondea a [decimales] y devuelve `int` cuando el resultado es
  /// entero, para que el JSON muestre `-65` en vez de `-65.0`.
  num _numLimpio(double v, int decimales) {
    final r = double.parse(v.toStringAsFixed(decimales));
    return r == r.roundToDouble() ? r.toInt() : r;
  }

  /// Genera el `beacon_config.json` **completo** listo para pegar: uuid,
  /// major, bloque de calibración (valores vivos) y todas las balizas con
  /// su txPower calibrado (override si se aplicó, original si no).
  String _generarConfigCompleto() {
    final cal = widget.calibracionNotifier.value;
    final mapa = <String, dynamic>{
      '_descripcion':
          'Configuración de balizas BLE y parámetros de calibración del '
              'posicionamiento. Editar en campo no requiere recompilar la app.',
      'uuid': _uuid ?? '',
      'major': _major ?? 1,
      'calibracion': {
        'txPower_dbm_default': _numLimpio(cal.txPowerDbmDefault, 0),
        'n_exponente_perdida': _numLimpio(cal.nExponentePerdida, 2),
        'ventana_media_movil': cal.ventanaMediaMovil,
        'tolerancia_snap_metros': _numLimpio(cal.toleranciaSnapMetros, 1),
        'expiracion_lectura_segundos': cal.expiracionLecturaSegundos,
      },
      'beacons': [
        for (final b in _beaconsConfig)
          {
            'minor': b.minor,
            'x': _numLimpio(b.x, 2),
            'y': _numLimpio(b.y, 2),
            'txPower_dbm': _numLimpio(
              _txPowerOverrides[b.minor] ?? b.txPowerDbm ?? cal.txPowerDbmDefault,
              1,
            ),
            'descripcion': b.descripcion,
          },
      ],
    };
    return const JsonEncoder.withIndent('  ').convert(mapa);
  }

  /// Fragmento de solo calibración — atajo para cambios rápidos sin
  /// reemplazar todo el archivo.
  String _generarSoloCalibracion() {
    final cal = widget.calibracionNotifier.value;
    return '"calibracion": {\n'
        '  "txPower_dbm_default": ${cal.txPowerDbmDefault.toStringAsFixed(0)},\n'
        '  "n_exponente_perdida": ${cal.nExponentePerdida.toStringAsFixed(2)},\n'
        '  "ventana_media_movil": ${cal.ventanaMediaMovil},\n'
        '  "tolerancia_snap_metros": ${cal.toleranciaSnapMetros.toStringAsFixed(1)},\n'
        '  "expiracion_lectura_segundos": ${cal.expiracionLecturaSegundos}\n'
        '}';
  }

  /// Calcula `n` que haría que la distancia medida coincida con la real.
  /// Fórmula despejada de path-loss: n = (txPower - rssi) / (10 · log10(d))
  double? _calcularNSugerido() {
    final stats = _statsBeaconSeleccionado;
    final distReal = double.tryParse(_distanciaController.text);
    if (stats == null || !stats.tieneMuestras || distReal == null || distReal <= 0) {
      return null;
    }
    if (distReal == 1.0) return null; // log10(1) = 0, indefinido
    final txPower =
        _txPowerPorMinor[stats.minor] ?? widget.calibracionNotifier.value.txPowerDbmDefault;
    return (txPower - stats.rssiMean) / (10.0 * (log(distReal) / ln10));
  }

  /// Calcula `txPower` que haría coincidir, manteniendo `n` actual.
  /// Fórmula: txPower = rssi + 10·n·log10(d)
  double? _calcularTxPowerSugerido() {
    final stats = _statsBeaconSeleccionado;
    final distReal = double.tryParse(_distanciaController.text);
    if (stats == null || !stats.tieneMuestras || distReal == null || distReal <= 0) {
      return null;
    }
    final n = widget.calibracionNotifier.value.nExponentePerdida;
    return stats.rssiMean + 10.0 * n * (log(distReal) / ln10);
  }

  BeaconStats? get _statsBeaconSeleccionado {
    if (_minorSeleccionado == null) return null;
    return _stats[_minorSeleccionado];
  }

  // ─── Diálogo BLE (permisos / BT apagado) ──────────────────────────────────

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
          esPermisos ? 'Activa los permisos' : 'Activa el Bluetooth',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.fg,
          ),
        ),
        content: Text(
          esPermisos
              ? 'La calibración necesita acceso a Bluetooth para recibir '
                  'lecturas de las balizas. Toca "Reintentar" para volver '
                  'a pedirlos, o actívalos en Ajustes del sistema → Apps → '
                  'UTP Guide → Permisos.'
              : 'El Bluetooth de tu dispositivo está apagado. Actívalo '
                  'desde el panel de control rápido para empezar a recibir '
                  'lecturas.',
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
                        ? 'Permisos concedidos · escaneando…'
                        : 'Permisos siguen denegados · revisa Ajustes del sistema'),
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

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Mostrar el diálogo si aplica, después del primer frame.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _mostrarDialogoBleSiAplica());

    return Scaffold(
      backgroundColor: colors.bgSoft,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, colors),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  _buildAvisoEstadoBle(context, colors),
                  const SizedBox(height: 16),
                  // Diagnóstico arriba — primera cosa al abrir es ver si
                  // llegan paquetes BLE y de qué formato.
                  _buildSeccionDiagnosticoBle(context, colors),
                  const SizedBox(height: 16),
                  // Controles de modo crudo + traza para validar la
                  // calibración visualmente.
                  _buildSeccionModoCrudo(context, colors),
                  const SizedBox(height: 16),
                  // Sliders subidos — son la herramienta principal de la
                  // pantalla y antes estaban casi al final del scroll.
                  _buildSeccionSliders(context, colors),
                  const SizedBox(height: 16),
                  _buildSeccionBalizas(context, colors),
                  const SizedBox(height: 16),
                  _buildSeccionValidacionPosicion(context, colors),
                  const SizedBox(height: 16),
                  _buildSeccionDistanciaConocida(context, colors),
                  const SizedBox(height: 16),
                  _buildSeccionValoresJson(context, colors),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Row(
        children: [
          IconButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/'),
            icon: Icon(Icons.arrow_back_rounded, color: colors.fg),
            style: IconButton.styleFrom(
              backgroundColor: colors.surface,
              shape: const CircleBorder(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Calibración BLE',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: colors.fg,
                  ),
                ),
                Text(
                  'Herramienta de campo (solo debug)',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: colors.fgMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Resetear estadísticas',
            onPressed: _resetearStats,
            icon: Icon(Icons.restart_alt_rounded, color: colors.fgSoft),
          ),
          IconButton(
            tooltip: 'Copiar CSV',
            onPressed: _exportarCsv,
            icon: Icon(Icons.content_copy_rounded, color: colors.fgSoft),
          ),
        ],
      ),
    );
  }

  Widget _buildAvisoEstadoBle(BuildContext context, AppColors colors) {
    String mensaje;
    Color color;
    IconData icono;
    switch (_bleEstado) {
      case BleEstado.escaneando:
        mensaje = 'Escaneando BLE real…';
        color = colors.success;
        icono = Icons.bluetooth_searching_rounded;
      case BleEstado.simulando:
        mensaje = 'Modo simulación activo · datos sintéticos';
        color = colors.brand;
        icono = Icons.science_outlined;
      case BleEstado.bluetoothApagado:
        mensaje = 'Bluetooth apagado · actívalo para recibir lecturas';
        color = colors.danger;
        icono = Icons.bluetooth_disabled_rounded;
      case BleEstado.permisosNegados:
        mensaje = 'Permisos BLE negados · revisa Ajustes del sistema';
        color = colors.danger;
        icono = Icons.lock_outline_rounded;
      default:
        mensaje = 'Iniciando…';
        color = colors.fgMuted;
        icono = Icons.hourglass_empty_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icono, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mensaje,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionDiagnosticoBle(BuildContext context, AppColors colors) {
    final items = _advertisements.values.toList().reversed.toList();
    final aceptados = items.where((a) => a.aceptado).length;
    final descartados = items.length - aceptados;

    return _Card(
      title: 'Diagnóstico BLE',
      subtitle: items.isEmpty
          ? 'Sin paquetes recibidos · si tu simulador está activo, '
              'revisa Bluetooth y permisos'
          : '${items.length} dispositivos · $aceptados aceptados · '
              '$descartados descartados',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Botón siempre visible: forzar solicitud de permisos. Útil
          // cuando el usuario abre la pantalla y nunca le pidió nada
          // (caso iOS o permisos ya negados antes).
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                final ok =
                    await widget.positioningService.reintentarPermisosBle();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Permisos OK · escaneando'
                        : 'Permisos siguen denegados · revisa Ajustes del sistema'),
                    duration: const Duration(seconds: 3),
                  ),
                );
              },
              icon: const Icon(Icons.lock_open_rounded, size: 16),
              label: Text(
                'Solicitar permisos',
                style: GoogleFonts.plusJakartaSans(fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 4),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  'Esperando advertisements BLE…',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: colors.fgMuted,
                  ),
                ),
              ),
            )
          else
            Column(
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  _FilaAdvertisement(item: items[i]),
                  if (i < items.length - 1)
                    Divider(height: 12, color: colors.line),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSeccionModoCrudo(BuildContext context, AppColors colors) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.snapHabilitadoNotifier,
        widget.trazaActivaNotifier,
        widget.trazaService.puntos,
      ]),
      builder: (_, _) {
        final snapOn = widget.snapHabilitadoNotifier.value;
        final trazaOn = widget.trazaActivaNotifier.value;
        final cantidad = widget.trazaService.puntos.value.length;

        return _Card(
          title: 'Modo crudo & traza',
          subtitle:
              'Para comparar el cálculo del sistema con la realidad sin '
              'que el snap-to-graph maquille los errores.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ToggleRow(
                titulo: 'Snap-to-graph',
                detalle: snapOn
                    ? 'El dot se pega al pasillo más cercano (modo normal).'
                    : 'El dot muestra la posición cruda del centroide.',
                value: snapOn,
                onChanged: (v) => widget.snapHabilitadoNotifier.value = v,
              ),
              const SizedBox(height: 10),
              _ToggleRow(
                titulo: 'Capturar traza',
                detalle: trazaOn
                    ? 'Acumulando posiciones · $cantidad puntos'
                    : 'OFF — actívalo para empezar a dibujar el trayecto.',
                value: trazaOn,
                onChanged: (v) => widget.trazaActivaNotifier.value = v,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: cantidad == 0
                          ? null
                          : () {
                              widget.trazaService.limpiar();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Traza limpiada'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: Text(
                        'Limpiar traza',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSeccionValidacionPosicion(BuildContext context, AppColors colors) {
    final mapaSize = _dimensionesMapa;
    final svg = _svgPath;

    return _Card(
      title: 'Validación de posición',
      subtitle:
          'Toca el mapa donde estás parado de verdad. La app compara contra '
          'su posición calculada y mide el error real en metros.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mini-mapa interactivo
          if (mapaSize == null)
            const SizedBox(
              height: 240,
              child: Center(child: CircularProgressIndicator()),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 240,
                color: colors.bgMuted,
                child: ValueListenableBuilder<List<Position>>(
                  valueListenable: widget.trazaService.puntos,
                  builder: (_, traza, _) => MapView(
                    mapaSize: mapaSize,
                    svgAsset: svg,
                    posicionUsuario: _posicionCalculada, // dot azul
                    posicionTarget: _posicionReal, // cruz roja
                    traza: traza,
                    panZoomHabilitado: false,
                    onTapMundo: _onTapPosicionReal,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),

          if (_posicionReal == null)
            Text(
              'Toca tu posición real en el mapa para empezar a medir.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: colors.fgMuted,
                fontStyle: FontStyle.italic,
              ),
            )
          else ...[
            _ResultadoCalcRow(
              label: 'Pos. real',
              valor: '(${_posicionReal!.x.toStringAsFixed(2)}, '
                  '${_posicionReal!.y.toStringAsFixed(2)}) m',
            ),
            _ResultadoCalcRow(
              label: 'App calcula',
              valor: _posicionCalculada == null
                  ? 'sin señal'
                  : '(${_posicionCalculada!.x.toStringAsFixed(2)}, '
                      '${_posicionCalculada!.y.toStringAsFixed(2)}) m',
            ),
            if (_errorStats.tieneMuestras) ...[
              _ResultadoCalcRow(
                label: 'Error actual',
                valor: '${_errorStats.errorActual.toStringAsFixed(2)} m',
                colorValor: _errorStats.errorActual > 2.0
                    ? colors.danger
                    : (_errorStats.errorActual > 1.0
                        ? Colors.orange.shade700
                        : colors.success),
              ),
              const SizedBox(height: 8),
              Text(
                'Sobre ${_errorStats.samples} muestras (mantén la posición):',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.fgSoft,
                ),
              ),
              const SizedBox(height: 4),
              _ResultadoCalcRow(
                label: 'Error medio',
                valor: '${_errorStats.errorMedio.toStringAsFixed(2)} m',
              ),
              _ResultadoCalcRow(
                label: 'Error máx',
                valor: '${_errorStats.errorMaximo.toStringAsFixed(2)} m',
              ),
              _ResultadoCalcRow(
                label: 'p95',
                valor: '${_errorStats.errorP95.toStringAsFixed(2)} m',
                detalle: '95% del tiempo el error es menor a esto',
              ),
            ] else
              Text(
                'Esperando posición calculada…',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: colors.fgMuted,
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSeccionBalizas(BuildContext context, AppColors colors) {
    final lista = _stats.values.toList()..sort((a, b) => a.minor.compareTo(b.minor));

    return _Card(
      title: 'Balizas detectadas',
      subtitle: '${lista.where((s) => s.tieneMuestras).length} con muestras · '
          '${_stats.values.fold<int>(0, (acc, s) => acc + s.samples)} lecturas totales',
      child: lista.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Esperando lecturas BLE…',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: colors.fgMuted,
                  ),
                ),
              ),
            )
          : Column(
              children: [
                for (int i = 0; i < lista.length; i++) ...[
                  _FilaBeacon(stats: lista[i]),
                  if (i < lista.length - 1)
                    Divider(height: 16, color: colors.line),
                ],
              ],
            ),
    );
  }

  Widget _buildSeccionDistanciaConocida(BuildContext context, AppColors colors) {
    final balizasConMuestras =
        _stats.values.where((s) => s.tieneMuestras).toList()
          ..sort((a, b) => a.minor.compareTo(b.minor));

    // Auto-seleccionar la primera baliza con muestras si no hay nada elegido.
    if (_minorSeleccionado == null && balizasConMuestras.isNotEmpty) {
      _minorSeleccionado = balizasConMuestras.first.minor;
    }

    final stats = _statsBeaconSeleccionado;
    final distReal = double.tryParse(_distanciaController.text);
    final nSugerido = _calcularNSugerido();
    final txPowerSugerido = _calcularTxPowerSugerido();

    return _Card(
      title: 'Distancia conocida',
      subtitle: 'Calcula qué valores harían que la app coincida con la realidad',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Selector de baliza
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _minorSeleccionado,
                  decoration: const InputDecoration(
                    labelText: 'Baliza',
                    isDense: true,
                  ),
                  items: balizasConMuestras
                      .map((s) => DropdownMenuItem(
                            value: s.minor,
                            child: Text(
                              'Minor ${s.minor}'
                              '${s.descripcion != null ? " · ${s.descripcion}" : ""}',
                              style: GoogleFonts.plusJakartaSans(fontSize: 13),
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _minorSeleccionado = v),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _distanciaController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Real (m)',
                    isDense: true,
                  ),
                  style: GoogleFonts.plusJakartaSans(fontSize: 13),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Resultado
          if (stats == null || !stats.tieneMuestras)
            Text(
              'Selecciona una baliza con lecturas para calcular sugerencias.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: colors.fgMuted,
              ),
            )
          else if (distReal == null || distReal <= 0)
            Text(
              'Ingresa una distancia real válida.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: colors.fgMuted,
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ResultadoCalcRow(
                  label: 'RSSI medio',
                  valor: '${stats.rssiMean.toStringAsFixed(1)} dBm',
                  detalle: '(${stats.samples} muestras, σ=${stats.rssiStdDev.toStringAsFixed(1)})',
                ),
                _ResultadoCalcRow(
                  label: 'App calcula',
                  valor: '${stats.distanciaMean.toStringAsFixed(2)} m',
                  detalle:
                      'error: ${(stats.distanciaMean - distReal).toStringAsFixed(2)} m',
                  colorValor: (stats.distanciaMean - distReal).abs() > 1.0
                      ? colors.danger
                      : colors.success,
                ),
                const SizedBox(height: 14),
                Text(
                  'Sugerencias para que coincida con $distReal m:',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.fgSoft,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 6),
                if (distReal == 1.0)
                  Text(
                    'A 1 m, RSSI medido = txPower por definición. '
                    'Ajusta el txPower de esta baliza al RSSI medio: '
                    '${stats.rssiMean.toStringAsFixed(1)} dBm.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: colors.fg,
                      height: 1.5,
                    ),
                  )
                else ...[
                  _SugerenciaRow(
                    label: 'Cambiar n',
                    valorActual:
                        widget.calibracionNotifier.value.nExponentePerdida.toStringAsFixed(2),
                    valorSugerido: nSugerido?.toStringAsFixed(2) ?? '—',
                    explicacion:
                        'afecta TODAS las balizas',
                  ),
                  const SizedBox(height: 4),
                  _SugerenciaRow(
                    label: 'Cambiar txPower de Minor ${stats.minor}',
                    valorActual:
                        (_txPowerPorMinor[stats.minor] ?? widget.calibracionNotifier.value.txPowerDbmDefault)
                            .toStringAsFixed(1),
                    valorSugerido:
                        txPowerSugerido?.toStringAsFixed(1) ?? '—',
                    explicacion: 'solo afecta a esta baliza',
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: txPowerSugerido == null
                          ? null
                          : () => _aplicarTxPower(stats.minor, txPowerSugerido),
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: Text(
                        'Aplicar txPower a Minor ${stats.minor}',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12),
                      ),
                    ),
                  ),
                  if (_txPowerOverrides.containsKey(stats.minor))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '✓ Aplicado: ${_txPowerOverrides[stats.minor]!.toStringAsFixed(1)} dBm '
                        '· queda en el archivo generado abajo',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: colors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSeccionSliders(BuildContext context, AppColors colors) {
    final cal = widget.calibracionNotifier.value;
    return _Card(
      title: 'Ajustes en vivo',
      subtitle: 'Los cambios se aplican a las próximas lecturas en ~${cal.ventanaMediaMovil} samples',
      child: Column(
        children: [
          _SliderCalibracion(
            label: 'n (exponente de pérdida)',
            valor: cal.nExponentePerdida,
            min: 2.0,
            max: 5.0,
            divisions: 60,
            format: (v) => v.toStringAsFixed(2),
            valorOriginal: _calibracionOriginal.nExponentePerdida,
            onChanged: (v) {
              _aplicarNuevaCalibracion(
                CalibracionPositioning(
                  txPowerDbmDefault: cal.txPowerDbmDefault,
                  nExponentePerdida: v,
                  ventanaMediaMovil: cal.ventanaMediaMovil,
                  toleranciaSnapMetros: cal.toleranciaSnapMetros,
                  expiracionLecturaSegundos: cal.expiracionLecturaSegundos,
                ),
              );
            },
            ayuda:
                'Más alto = la app cree que la señal se debilita más rápido (muros gruesos)',
          ),
          const SizedBox(height: 12),
          _SliderCalibracion(
            label: 'Ventana media móvil',
            valor: cal.ventanaMediaMovil.toDouble(),
            min: 1,
            max: 20,
            divisions: 19,
            format: (v) => '${v.toInt()} lecturas',
            valorOriginal: _calibracionOriginal.ventanaMediaMovil.toDouble(),
            onChanged: (v) {
              _aplicarNuevaCalibracion(
                CalibracionPositioning(
                  txPowerDbmDefault: cal.txPowerDbmDefault,
                  nExponentePerdida: cal.nExponentePerdida,
                  ventanaMediaMovil: v.toInt(),
                  toleranciaSnapMetros: cal.toleranciaSnapMetros,
                  expiracionLecturaSegundos: cal.expiracionLecturaSegundos,
                ),
              );
            },
            ayuda: 'Más alto = más suavizado pero más lag',
          ),
          const SizedBox(height: 12),
          _SliderCalibracion(
            label: 'Tolerancia snap-to-graph',
            valor: cal.toleranciaSnapMetros,
            min: 0.5,
            max: 10.0,
            divisions: 19,
            format: (v) => '${v.toStringAsFixed(1)} m',
            valorOriginal: _calibracionOriginal.toleranciaSnapMetros,
            onChanged: (v) {
              _aplicarNuevaCalibracion(
                CalibracionPositioning(
                  txPowerDbmDefault: cal.txPowerDbmDefault,
                  nExponentePerdida: cal.nExponentePerdida,
                  ventanaMediaMovil: cal.ventanaMediaMovil,
                  toleranciaSnapMetros: v,
                  expiracionLecturaSegundos: cal.expiracionLecturaSegundos,
                ),
              );
            },
            ayuda:
                'Distancia máxima al grafo para pegar la posición a un pasillo',
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // A3: aplicar cambios de slider instantáneamente limpiando
              // las ventanas de media móvil (que aún tienen valores
              // calculados con la calibración anterior).
              TextButton.icon(
                onPressed: () {
                  widget.positioningService.resetearVentanas();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ventanas limpiadas — efecto inmediato'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.bolt_rounded, size: 16),
                label: Text(
                  'Limpiar ventana',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12),
                ),
              ),
              TextButton.icon(
                onPressed: _restaurarValoresOriginales,
                icon: const Icon(Icons.undo_rounded, size: 16),
                label: Text(
                  'Restaurar JSON',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSeccionValoresJson(BuildContext context, AppColors colors) {
    final cargando = _uuid == null || _beaconsConfig.isEmpty;
    final overrides = _txPowerOverrides.length;
    final subtitulo = cargando
        ? 'Cargando configuración…'
        : overrides == 0
            ? 'Reemplaza todo assets/data/beacon_config.json con esto.'
            : 'Reemplaza todo assets/data/beacon_config.json · '
                '$overrides ${overrides == 1 ? "baliza recalibrada" : "balizas recalibradas"}.';

    return _Card(
      title: 'Aplicar permanentemente',
      subtitle: subtitulo,
      child: cargando
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.bgMuted,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    _generarConfigCompleto(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: _generarConfigCompleto()));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Archivo completo copiado · '
                                  'pégalo en beacon_config.json y reinicia'),
                              duration: Duration(seconds: 3),
                            ),
                          );
                        },
                        icon: const Icon(Icons.description_rounded, size: 16),
                        label: Text(
                          'Copiar archivo completo',
                          style: GoogleFonts.plusJakartaSans(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: _generarSoloCalibracion()));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Solo el bloque de calibración copiado'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.tune_rounded, size: 16),
                      label: Text(
                        'Solo calibración',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

// ─── Sub-componentes ──────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _Card({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colors.fg,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: colors.fgMuted,
                height: 1.3,
              ),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _FilaBeacon extends StatelessWidget {
  final BeaconStats stats;
  const _FilaBeacon({required this.stats});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final edad = stats.edadMs;
    final Color colorEdad;
    final String etiquetaEdad;
    if (edad == null) {
      colorEdad = colors.fgSoft;
      etiquetaEdad = 'sin datos';
    } else if (edad < 1500) {
      colorEdad = colors.success;
      etiquetaEdad = '${edad}ms';
    } else if (edad < 3000) {
      colorEdad = Colors.orange.shade700;
      etiquetaEdad = '${edad}ms';
    } else {
      colorEdad = colors.danger;
      etiquetaEdad = '${edad}ms';
    }

    // Dot de salud — color según la evaluación de tasa/σ/edad.
    final Color colorSalud;
    switch (stats.salud) {
      case SaludBaliza.ok:
        colorSalud = colors.success;
      case SaludBaliza.warning:
        colorSalud = Colors.orange.shade700;
      case SaludBaliza.problema:
        colorSalud = colors.danger;
      case SaludBaliza.midiendo:
        colorSalud = colors.brand;
      case SaludBaliza.sinDatos:
        colorSalud = colors.fgSoft;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.brandSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${stats.minor}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: colors.brand,
                ),
              ),
            ),
            // Indicador de salud (esquina superior derecha del minor).
            // Tooltip explica la razón en lenguaje humano.
            Positioned(
              right: -3,
              top: -3,
              child: Tooltip(
                message: stats.razonSalud,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: colorSalud,
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: colors.surface, width: 1.5),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stats.descripcion ?? 'Sin descripción',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.fg,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              if (!stats.tieneMuestras)
                Text(
                  'Sin lecturas todavía',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: colors.fgSoft,
                  ),
                )
              else
                Text(
                  'RSSI ${stats.rssiActual.toStringAsFixed(0)} dBm\n'
                  'media ${stats.rssiMean.toStringAsFixed(1)}  ·  '
                  'mediana ${stats.rssiMediana.toStringAsFixed(1)}  ·  '
                  'σ ${stats.rssiStdDev.toStringAsFixed(1)}\n'
                  'd ≈ ${stats.distanciaMean.toStringAsFixed(2)} m',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${stats.samples}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: colors.fg,
              ),
            ),
            Text(
              etiquetaEdad,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: colorEdad,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Fila compacta para mostrar un advertisement BLE en la sección de
/// diagnóstico. Distingue visualmente aceptados (verde) vs descartados
/// (gris/naranja según motivo).
class _FilaAdvertisement extends StatelessWidget {
  final AdvertisementCrudo item;
  const _FilaAdvertisement({required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final esAceptado = item.aceptado;
    final colorPrincipal = esAceptado
        ? colors.success
        : (item.formato == FormatoBalizaBle.iBeacon
            ? Colors.orange.shade700
            : colors.fgSoft);

    final uuidCorto =
        item.uuid == null ? '—' : '${item.uuid!.substring(0, 8)}…';
    final tagPrincipal = item.major != null && item.minor != null
        ? '${item.major}.${item.minor}'
        : item.deviceId.length > 12
            ? '${item.deviceId.substring(0, 12)}…'
            : item.deviceId;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 6, right: 10),
          decoration: BoxDecoration(
            color: colorPrincipal,
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorPrincipal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.formatoCorto,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: colorPrincipal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tagPrincipal,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.fg,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${item.rssi.toStringAsFixed(0)} dBm',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: colors.fgMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                esAceptado
                    ? 'UUID $uuidCorto · aceptado'
                    : 'UUID $uuidCorto · ${item.motivoDescarte}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: colors.fgSoft,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Fila compacta con título + descripción + switch a la derecha. Usada
/// en la sección "Modo crudo & traza" para los dos toggles principales.
class _ToggleRow extends StatelessWidget {
  final String titulo;
  final String detalle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.titulo,
    required this.detalle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titulo,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.fg,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detalle,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: colors.fgMuted,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SliderCalibracion extends StatelessWidget {
  final String label;
  final double valor;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) format;
  final double valorOriginal;
  final ValueChanged<double> onChanged;
  final String? ayuda;

  const _SliderCalibracion({
    required this.label,
    required this.valor,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.valorOriginal,
    required this.onChanged,
    this.ayuda,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final modificado = (valor - valorOriginal).abs() > 0.001;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.fg,
                ),
              ),
            ),
            Text(
              format(valor),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: modificado ? colors.brand : colors.fg,
              ),
            ),
          ],
        ),
        Slider(
          value: valor.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
        Row(
          children: [
            if (ayuda != null)
              Expanded(
                child: Text(
                  ayuda!,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: colors.fgSoft,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            if (modificado)
              Text(
                'orig: ${format(valorOriginal)}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: colors.fgSoft,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ResultadoCalcRow extends StatelessWidget {
  final String label;
  final String valor;
  final String? detalle;
  final Color? colorValor;

  const _ResultadoCalcRow({
    required this.label,
    required this.valor,
    this.detalle,
    this.colorValor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: colors.fgMuted,
              ),
            ),
          ),
          Text(
            valor,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colorValor ?? colors.fg,
            ),
          ),
          if (detalle != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                detalle!,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: colors.fgSoft,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SugerenciaRow extends StatelessWidget {
  final String label;
  final String valorActual;
  final String valorSugerido;
  final String explicacion;

  const _SugerenciaRow({
    required this.label,
    required this.valorActual,
    required this.valorSugerido,
    required this.explicacion,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.fg,
                  ),
                ),
              ),
              Text(
                '$valorActual → ',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
              Text(
                valorSugerido,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.brand,
                ),
              ),
            ],
          ),
          Text(
            explicacion,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              color: colors.fgSoft,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
