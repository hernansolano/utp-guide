import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/repositories/beacon_repository.dart';
import '../../data/repositories/grafo_repository.dart';
import '../../models/beacon_config.dart';
import '../../models/beacon_reading.dart';
import '../../models/beacon_stats.dart';
import '../../models/position.dart';
import '../../services/ble_service.dart' show BleEstado;
import '../../services/positioning_service.dart';
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

  const CalibracionScreen({
    super.key,
    required this.positioningService,
    required this.beaconRepository,
    required this.grafoRepository,
    required this.calibracionNotifier,
  });

  @override
  State<CalibracionScreen> createState() => _CalibracionScreenState();
}

class _CalibracionScreenState extends State<CalibracionScreen> {
  /// Stats acumuladas por baliza desde que se abrió la pantalla.
  final Map<int, BeaconStats> _stats = {};

  /// txPower por baliza, cacheado de `beacon_config.json` para no hacer
  /// I/O por cada lectura.
  final Map<int, double> _txPowerPorMinor = {};

  /// Valor de calibración como vino del archivo, para poder restaurarlo.
  late CalibracionPositioning _calibracionOriginal;

  /// Estado de BLE para mostrar warnings.
  BleEstado _bleEstado = BleEstado.inactivo;

  StreamSubscription<BeaconReading>? _readingsSub;
  StreamSubscription<BleEstado>? _estadoSub;
  StreamSubscription<Position?>? _posSub;

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
      if (mounted) setState(() => _bleEstado = e);
    });
    _bleEstado = widget.positioningService.estadoBleActual;
  }

  Future<void> _cargarConfigs() async {
    final cal = await widget.beaconRepository.obtenerCalibracion();
    final minors = await widget.beaconRepository.obtenerMinorsRegistrados();
    for (final m in minors) {
      try {
        final config = await widget.beaconRepository.obtenerConfigBeacon(m);
        _stats.putIfAbsent(
          m,
          () => BeaconStats(minor: m, descripcion: config.descripcion),
        );
        _txPowerPorMinor[m] = config.txPowerDbm ?? cal.txPowerDbmDefault;
      } catch (_) {
        // ignore
      }
    }
    // Cargar mapa para la sección de validación end-to-end.
    final dims = await widget.grafoRepository.obtenerDimensionesMapa();
    final svg = await widget.grafoRepository.obtenerMapaSvgPath();
    if (mounted) {
      setState(() {
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
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.calibracionNotifier.removeListener(_onCalibracionCambio);
    _readingsSub?.cancel();
    _estadoSub?.cancel();
    _posSub?.cancel();
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

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
                  _buildSeccionValidacionPosicion(context, colors),
                  const SizedBox(height: 16),
                  _buildSeccionBalizas(context, colors),
                  const SizedBox(height: 16),
                  _buildSeccionDistanciaConocida(context, colors),
                  const SizedBox(height: 16),
                  _buildSeccionSliders(context, colors),
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
        mensaje = 'Bluetooth apagado · activalo para recibir lecturas';
        color = colors.danger;
        icono = Icons.bluetooth_disabled_rounded;
      case BleEstado.permisosNegados:
        mensaje = 'Permisos BLE negados · revisá Ajustes del sistema';
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

  Widget _buildSeccionValidacionPosicion(BuildContext context, AppColors colors) {
    final mapaSize = _dimensionesMapa;
    final svg = _svgPath;

    return _Card(
      title: 'Validación de posición',
      subtitle:
          'Tocá el mapa donde estás parado de verdad. La app compara contra '
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
                child: MapView(
                  mapaSize: mapaSize,
                  svgAsset: svg,
                  posicionUsuario: _posicionCalculada, // dot azul
                  posicionTarget: _posicionReal, // cruz roja
                  panZoomHabilitado: false,
                  onTapMundo: _onTapPosicionReal,
                ),
              ),
            ),
          const SizedBox(height: 12),

          if (_posicionReal == null)
            Text(
              'Tocá tu posición real en el mapa para empezar a medir.',
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
                'Sobre ${_errorStats.samples} muestras (mantené la posición):',
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
      subtitle: 'Calculá qué valores harían que la app coincida con la realidad',
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
              'Seleccioná una baliza con lecturas para calcular sugerencias.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: colors.fgMuted,
              ),
            )
          else if (distReal == null || distReal <= 0)
            Text(
              'Ingresá una distancia real válida.',
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
                    'Ajustá el txPower de esta baliza al RSSI medio: '
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
    final cal = widget.calibracionNotifier.value;
    return _Card(
      title: 'Aplicar permanentemente',
      subtitle: 'Pegá estos valores en assets/data/beacon_config.json',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.bgMuted,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              '"calibracion": {\n'
              '  "txPower_dbm_default": ${cal.txPowerDbmDefault.toStringAsFixed(0)},\n'
              '  "n_exponente_perdida": ${cal.nExponentePerdida.toStringAsFixed(2)},\n'
              '  "ventana_media_movil": ${cal.ventanaMediaMovil},\n'
              '  "tolerancia_snap_metros": ${cal.toleranciaSnapMetros.toStringAsFixed(1)},\n'
              '  "expiracion_lectura_segundos": ${cal.expiracionLecturaSegundos}\n'
              '}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text:
                    '"calibracion": {\n'
                    '  "txPower_dbm_default": ${cal.txPowerDbmDefault.toStringAsFixed(0)},\n'
                    '  "n_exponente_perdida": ${cal.nExponentePerdida.toStringAsFixed(2)},\n'
                    '  "ventana_media_movil": ${cal.ventanaMediaMovil},\n'
                    '  "tolerancia_snap_metros": ${cal.toleranciaSnapMetros.toStringAsFixed(1)},\n'
                    '  "expiracion_lectura_segundos": ${cal.expiracionLecturaSegundos}\n'
                    '}'));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Bloque copiado al portapapeles'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: Text(
                'Copiar bloque',
                style: GoogleFonts.plusJakartaSans(fontSize: 12),
              ),
            ),
          ],
        ),
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
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
