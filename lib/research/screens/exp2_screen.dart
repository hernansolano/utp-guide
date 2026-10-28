import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/repositories/beacon_repository.dart';
import '../../data/repositories/grafo_repository.dart';
import '../../models/beacon_config.dart';
import '../../models/beacon_reading.dart';
import '../../models/beacon_stats.dart';
import '../../models/position.dart';
import '../../services/positioning_service.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/widgets/map_view.dart';
import '../algorithms/positioning_algorithm.dart';
import '../models/measurement_session.dart';
import '../services/measurement_repository.dart';

/// **EXP2 — Comparación de algoritmos (Q2).**
///
/// En un punto de posición real conocida (tocado en el mapa), corre los
/// algoritmos en paralelo sobre las MISMAS lecturas durante T segundos y
/// mide el error de cada uno contra la posición real. Reusa
/// [ErrorPosicionStats] (motor de error existente).
class Exp2Screen extends StatefulWidget {
  final PositioningService positioningService;
  final BeaconRepository beaconRepository;
  final GrafoRepository grafoRepository;
  final MeasurementRepository repository;
  final String tester;

  const Exp2Screen({
    super.key,
    required this.positioningService,
    required this.beaconRepository,
    required this.grafoRepository,
    required this.repository,
    required this.tester,
  });

  @override
  State<Exp2Screen> createState() => _Exp2ScreenState();
}

enum _Fase { config, capturando, hecho }

class _Exp2ScreenState extends State<Exp2Screen> {
  static const _duracionSeg = 60;
  static const _layouts = ['triangular', 'lineal'];

  _Fase _fase = _Fase.config;
  Size? _dims;
  String? _svg;
  int _piso = 1;

  /// `major` del entorno: las lecturas de balizas de otro piso (o del aula,
  /// major 99) con el mismo minor no deben entrar a los algoritmos.
  int? _major;
  List<PositioningAlgorithm> _algos = [];

  Position? _real;
  String _layout = _layouts.first;
  final _puntoCtrl = TextEditingController(text: 'P1');

  final Map<String, ErrorPosicionStats> _err = {};
  final Map<String, Position?> _estActual = {};
  final List<MeasurementSample> _muestras = [];

  StreamSubscription<BeaconReading>? _sub;
  Timer? _timer;
  int _restante = _duracionSeg;
  bool _guardando = false;

  // Throttle de UI: las lecturas llegan a varios Hz; reconstruir el mapa
  // en cada una causa jank. Los datos SÍ se registran en cada lectura.
  DateTime _ultimoUi = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    widget.positioningService.iniciar();
    _cargar();
  }

  Future<void> _cargar() async {
    final dims = await widget.grafoRepository.obtenerDimensionesMapa();
    final svg = await widget.grafoRepository.obtenerMapaSvgPath();
    final piso = await widget.grafoRepository.obtenerPiso();
    final cal = await widget.beaconRepository.obtenerCalibracion();
    final beacons = await widget.beaconRepository.obtenerTodosLosBeacons();
    final major = await widget.beaconRepository.obtenerMajor();
    final mapa = <int, BeaconPos>{
      for (final b in beacons) b.minor: BeaconPos(b.x, b.y, b.txPowerDbm),
    };
    if (!mounted) return;
    setState(() {
      _dims = Size(dims.anchoMetros, dims.altoMetros);
      _svg = svg;
      _piso = piso;
      _major = major;
      _algos = _construirAlgos(mapa, cal, piso);
    });
  }

  List<PositioningAlgorithm> _construirAlgos(
          Map<int, BeaconPos> mapa, CalibracionPositioning cal, int piso) =>
      [CentroideMovil(mapa, cal, piso), CentroideKalman(mapa, cal, piso)];

  @override
  void dispose() {
    _sub?.cancel();
    _timer?.cancel();
    _puntoCtrl.dispose();
    widget.positioningService.detener();
    super.dispose();
  }

  void _empezar() {
    if (_real == null) return;
    for (final a in _algos) {
      a.reset();
      _err[a.nombre] = ErrorPosicionStats();
      _estActual[a.nombre] = null;
    }
    _muestras.clear();
    _restante = _duracionSeg;
    setState(() => _fase = _Fase.capturando);

    _sub = widget.positioningService.beaconStreamRaw.listen(_onReading);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (--_restante <= 0) {
        _detener();
      } else if (mounted) {
        setState(() {});
      }
    });
  }

  void _onReading(BeaconReading r) {
    final real = _real;
    if (real == null) return;
    if (_major != null && r.major != _major) return;
    final estimaciones = <String, dynamic>{};
    for (final a in _algos) {
      final pos = a.procesar(r);
      _estActual[a.nombre] = pos;
      if (pos != null) {
        final error = sqrt(pow(pos.x - real.x, 2) + pow(pos.y - real.y, 2));
        _err[a.nombre]!.agregar(error);
        estimaciones[a.nombre] = {
          'x': double.parse(pos.x.toStringAsFixed(3)),
          'y': double.parse(pos.y.toStringAsFixed(3)),
          'error': double.parse(error.toStringAsFixed(3)),
        };
      }
    }
    _muestras.add(MeasurementSample(
      timestamp: r.timestamp,
      valores: {'minor': r.minor, 'rssi': r.rssi, 'estimaciones': estimaciones},
    ));
    final ahora = DateTime.now();
    if (mounted && ahora.difference(_ultimoUi).inMilliseconds >= 150) {
      _ultimoUi = ahora;
      setState(() {});
    }
  }

  void _detener() {
    _sub?.cancel();
    _sub = null;
    _timer?.cancel();
    _timer = null;
    if (mounted) setState(() => _fase = _Fase.hecho);
  }

  Future<void> _guardar() async {
    if (_guardando || _real == null) return;
    setState(() => _guardando = true);
    try {
      final sesion = MeasurementSession.nueva(
        tipo: ExperimentType.exp2Comparacion,
        tester: widget.tester,
        metadata: {
          'punto_id': _puntoCtrl.text.trim(),
          'real_x': double.parse(_real!.x.toStringAsFixed(3)),
          'real_y': double.parse(_real!.y.toStringAsFixed(3)),
          'layout': _layout,
          'duracion_s': _duracionSeg,
          for (final a in _algos)
            'error_medio_${a.nombre}': _err[a.nombre]?.errorMedio,
        },
      )..muestras.addAll(_muestras)
        ..fin = DateTime.now();
      await widget.repository.guardar(sesion);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Guardado: ${_puntoCtrl.text.trim()} · '
            '${_muestras.length} muestras'),
        duration: const Duration(seconds: 2),
      ));
      if (context.canPop()) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al guardar: $e'),
          duration: const Duration(seconds: 3),
        ));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        title: const Text('EXP2 · Algoritmos'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/research'),
        ),
      ),
      body: SafeArea(
        child: _dims == null
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(20),
                child: switch (_fase) {
                  _Fase.config => _vistaConfig(colors),
                  _Fase.capturando => _vistaCaptura(colors),
                  _Fase.hecho => _vistaHecho(colors),
                },
              ),
      ),
    );
  }

  Widget _mapa({bool tap = false}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 260,
        child: MapView(
          mapaSize: _dims!,
          svgAsset: _svg,
          posicionUsuario: _estActual['centroide_kalman'],
          posicionTarget: _real,
          panZoomHabilitado: false,
          onTapMundo: tap
              ? (m) => setState(() => _real = Position(
                  x: m.dx, y: m.dy, piso: _piso, timestamp: DateTime.now()))
              : null,
        ),
      ),
    );
  }

  Widget _vistaConfig(AppColors colors) {
    return ListView(
      children: [
        Text('Toca el mapa en tu posición real conocida.',
            style: TextStyle(color: colors.fgMuted, fontSize: 14)),
        const SizedBox(height: 12),
        _mapa(tap: true),
        const SizedBox(height: 16),
        Row(
          children: [
            SizedBox(
              width: 110,
              child: TextField(
                controller: _puntoCtrl,
                decoration: const InputDecoration(
                    labelText: 'Punto', isDense: true),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                _real == null
                    ? 'Sin posición'
                    : '(${_real!.x.toStringAsFixed(2)}, '
                        '${_real!.y.toStringAsFixed(2)}) m',
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    color: _real == null ? colors.danger : colors.fg),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('DISPOSICIÓN DE BALIZAS',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: colors.fgSoft)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final l in _layouts)
              ChoiceChip(
                label: Text(l),
                selected: l == _layout,
                onSelected: (_) => setState(() => _layout = l),
              ),
          ],
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 72,
          child: FilledButton.icon(
            onPressed: _real == null ? null : _empezar,
            icon: const Icon(Icons.play_arrow_rounded, size: 24),
            label: const Text('EMPEZAR ($_duracionSeg s)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            style: FilledButton.styleFrom(backgroundColor: colors.brand),
          ),
        ),
      ],
    );
  }

  Widget _vistaCaptura(AppColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${_puntoCtrl.text.trim()} · $_layout',
                style: TextStyle(color: colors.fgMuted, fontSize: 14)),
            Text('00:${_restante.toString().padLeft(2, '0')}',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: colors.brand)),
          ],
        ),
        const SizedBox(height: 12),
        _mapa(),
        const SizedBox(height: 16),
        Text('Muestras: ${_muestras.length}',
            style: TextStyle(color: colors.fgMuted)),
        const SizedBox(height: 12),
        for (final a in _algos) _filaError(colors, a),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: _detener,
          icon: const Icon(Icons.stop_rounded),
          label: const Text('TERMINAR ANTES'),
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16)),
        ),
      ],
    );
  }

  Widget _vistaHecho(AppColors colors) {
    return ListView(
      children: [
        Icon(Icons.check_circle_rounded, color: colors.success, size: 56),
        const SizedBox(height: 8),
        Center(
          child: Text('${_puntoCtrl.text.trim()} · ${_muestras.length} muestras',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: colors.fg)),
        ),
        const SizedBox(height: 20),
        for (final a in _algos) ...[
          _filaResumen(colors, a),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 20),
        SizedBox(
          height: 64,
          child: FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: const Icon(Icons.save_rounded),
            label: const Text('GUARDAR SESIÓN',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            style: FilledButton.styleFrom(backgroundColor: colors.brand),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _guardando ? null : () => setState(() => _fase = _Fase.config),
          child: const Text('Descartar y repetir'),
        ),
      ],
    );
  }

  Widget _filaError(AppColors colors, PositioningAlgorithm a) {
    final e = _err[a.nombre];
    final actual = e != null && e.tieneMuestras
        ? '${e.errorActual.toStringAsFixed(2)} m'
        : '—';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(a.etiqueta, style: TextStyle(fontSize: 15, color: colors.fg)),
          Text(actual,
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.brand)),
        ],
      ),
    );
  }

  Widget _filaResumen(AppColors colors, PositioningAlgorithm a) {
    final e = _err[a.nombre];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(a.etiqueta,
              style: TextStyle(fontWeight: FontWeight.w800, color: colors.fg)),
          const SizedBox(height: 6),
          Text(
            e == null || !e.tieneMuestras
                ? 'sin datos'
                : 'medio ${e.errorMedio.toStringAsFixed(2)} m · '
                    'p95 ${e.errorP95.toStringAsFixed(2)} m · '
                    'máx ${e.errorMaximo.toStringAsFixed(2)} m · '
                    'n=${e.samples}',
            style: TextStyle(
                fontFamily: 'monospace', fontSize: 13, color: colors.fgMuted),
          ),
        ],
      ),
    );
  }
}
