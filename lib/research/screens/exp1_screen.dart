import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/beacon_reading.dart';
import '../../models/beacon_stats.dart';
import '../../services/positioning_service.dart';
import '../../ui/theme/app_theme.dart';
import '../models/measurement_session.dart';
import '../services/measurement_repository.dart';

/// **EXP1 — Caracterización de propagación (Q1).**
///
/// Mide RSSI a una distancia conocida para estimar el exponente de
/// path-loss `n`. Flujo de campo: elegir distancia + minor + momento →
/// EMPEZAR → captura N muestras con auto-stop → guardar → siguiente
/// distancia. Reusa [BeaconStats] para media/σ/mín/máx en vivo.
///
/// El transmisor es la app **Beacon Simulator** configurada con el UUID
/// del proyecto. Lo capturado es RSSI real (radio real), válido para
/// caracterizar el canal.
class Exp1Screen extends StatefulWidget {
  final PositioningService positioningService;
  final MeasurementRepository repository;
  final String tester;

  const Exp1Screen({
    super.key,
    required this.positioningService,
    required this.repository,
    required this.tester,
  });

  @override
  State<Exp1Screen> createState() => _Exp1ScreenState();
}

enum _Fase { config, capturando, hecho }

class _Exp1ScreenState extends State<Exp1Screen> {
  static const _distancias = [1.0, 2.0, 3.0, 4.0, 5.0, 7.0, 10.0, 15.0];
  static const _momentos = ['Mañana', 'Mediodía', 'Tarde'];
  static const _objetivoMuestras = 30;

  _Fase _fase = _Fase.config;
  int _distIdx = 0;
  int _minor = 1;
  String _momento = _momentos.first;

  BeaconStats _stats = BeaconStats(minor: 1);
  final List<MeasurementSample> _muestras = [];
  StreamSubscription<BeaconReading>? _sub;
  bool _guardando = false;

  double get _distancia => _distancias[_distIdx];

  @override
  void initState() {
    super.initState();
    widget.positioningService.iniciar();
  }

  @override
  void dispose() {
    _sub?.cancel();
    widget.positioningService.detener();
    super.dispose();
  }

  void _empezar() {
    _stats = BeaconStats(minor: _minor);
    _muestras.clear();
    setState(() => _fase = _Fase.capturando);
    _sub = widget.positioningService.beaconStreamRaw.listen((r) {
      if (r.minor != _minor) return;
      _stats.agregar(r.rssi, 0, r.timestamp);
      _muestras.add(MeasurementSample(
        timestamp: r.timestamp,
        valores: {'rssi': r.rssi},
      ));
      if (_stats.samples >= _objetivoMuestras) {
        _detener();
      } else {
        setState(() {});
      }
    });
  }

  void _detener() {
    _sub?.cancel();
    _sub = null;
    if (mounted) setState(() => _fase = _Fase.hecho);
  }

  Future<void> _guardar({required bool siguiente}) async {
    if (_guardando) return;
    setState(() => _guardando = true);
    try {
      final sesion = MeasurementSession.nueva(
        tipo: ExperimentType.exp1Propagacion,
        tester: widget.tester,
        metadata: {
          'distancia_m': _distancia,
          'beacon_minor': _minor,
          'momento': _momento,
          'rssi_mean': _stats.rssiMean,
          'rssi_std': _stats.rssiStdDev,
          'rssi_min': _stats.rssiMin,
          'rssi_max': _stats.rssiMax,
          'tasa_hz': _stats.tasaHz,
        },
      )..muestras.addAll(_muestras)
        ..fin = DateTime.now();
      await widget.repository.guardar(sesion);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Guardado: ${_distancia.toStringAsFixed(0)} m · '
            'minor $_minor · ${_stats.samples} muestras'),
        duration: const Duration(seconds: 2),
      ));
      if (siguiente && _distIdx < _distancias.length - 1) {
        setState(() {
          _distIdx++;
          _fase = _Fase.config;
        });
      } else {
        if (context.canPop()) context.pop();
      }
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
        title: const Text('EXP1 · Propagación'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/research'),
        ),
      ),
      body: SafeArea(
        child: Padding(
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

  // ─── Configuración ──────────────────────────────────────────────────────

  Widget _vistaConfig(AppColors colors) {
    return ListView(
      children: [
        _label(colors, 'DISTANCIA REAL A LA BALIZA'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _distancias.length; i++)
              ChoiceChip(
                label: Text('${_distancias[i].toStringAsFixed(0)} m'),
                selected: i == _distIdx,
                onSelected: (_) => setState(() => _distIdx = i),
              ),
          ],
        ),
        const SizedBox(height: 24),
        _label(colors, 'BALIZA (MINOR)'),
        Row(
          children: [
            _stepperBtn(colors, Icons.remove_rounded,
                () => setState(() => _minor = (_minor - 1).clamp(1, 999))),
            Container(
              width: 80,
              alignment: Alignment.center,
              child: Text('$_minor',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: colors.fg)),
            ),
            _stepperBtn(colors, Icons.add_rounded,
                () => setState(() => _minor = (_minor + 1).clamp(1, 999))),
          ],
        ),
        const SizedBox(height: 24),
        _label(colors, 'MOMENTO DEL DÍA'),
        Wrap(
          spacing: 8,
          children: [
            for (final m in _momentos)
              ChoiceChip(
                label: Text(m),
                selected: m == _momento,
                onSelected: (_) => setState(() => _momento = m),
              ),
          ],
        ),
        const SizedBox(height: 36),
        _botonGrande(colors, 'EMPEZAR MEDICIÓN', Icons.play_arrow_rounded,
            _empezar),
        const SizedBox(height: 12),
        Center(
          child: Text('Captura $_objetivoMuestras muestras y se detiene sola.',
              style: TextStyle(color: colors.fgMuted, fontSize: 13)),
        ),
      ],
    );
  }

  // ─── Captura ────────────────────────────────────────────────────────────

  Widget _vistaCaptura(AppColors colors) {
    final progreso = _stats.samples / _objetivoMuestras;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${_distancia.toStringAsFixed(0)} m · minor $_minor · $_momento',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.fgMuted, fontSize: 15)),
        const SizedBox(height: 32),
        Center(
          child: Text('${_stats.samples} / $_objetivoMuestras',
              style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w900,
                  color: colors.brand)),
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
              value: progreso.clamp(0.0, 1.0), minHeight: 12),
        ),
        const SizedBox(height: 36),
        _statLinea(colors, 'RSSI actual',
            '${_stats.rssiActual.toStringAsFixed(1)} dBm'),
        _statLinea(colors, 'RSSI promedio',
            '${_stats.rssiMean.toStringAsFixed(1)} dBm'),
        _statLinea(colors, 'Desv. estándar (σ)',
            '${_stats.rssiStdDev.toStringAsFixed(1)} dBm'),
        _statLinea(colors, 'Tasa', '${_stats.tasaHz.toStringAsFixed(1)} Hz'),
        const Spacer(),
        if (_stats.samples == 0)
          Center(
            child: Text('Esperando lecturas del minor $_minor…\n'
                'Verifica que Beacon Simulator transmita ese minor con el '
                'UUID del proyecto.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.fgMuted, fontSize: 13)),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _detener,
          icon: const Icon(Icons.stop_rounded),
          label: const Text('DETENER ANTES'),
          style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16)),
        ),
      ],
    );
  }

  // ─── Resumen ────────────────────────────────────────────────────────────

  Widget _vistaHecho(AppColors colors) {
    return ListView(
      children: [
        Icon(Icons.check_circle_rounded, color: colors.success, size: 56),
        const SizedBox(height: 12),
        Center(
          child: Text('${_distancia.toStringAsFixed(0)} m · minor $_minor',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: colors.fg)),
        ),
        const SizedBox(height: 24),
        _statLinea(colors, 'Muestras', '${_stats.samples}'),
        _statLinea(colors, 'RSSI medio',
            '${_stats.rssiMean.toStringAsFixed(2)} dBm'),
        _statLinea(colors, 'Mediana',
            '${_stats.rssiMediana.toStringAsFixed(2)} dBm'),
        _statLinea(colors, 'σ', '${_stats.rssiStdDev.toStringAsFixed(2)} dBm'),
        _statLinea(colors, 'Mín / Máx',
            '${_stats.rssiMin.toStringAsFixed(0)} / ${_stats.rssiMax.toStringAsFixed(0)} dBm'),
        const SizedBox(height: 32),
        _botonGrande(
          colors,
          _distIdx < _distancias.length - 1
              ? 'GUARDAR Y SIGUIENTE (${_distancias[_distIdx + 1].toStringAsFixed(0)} m)'
              : 'GUARDAR Y TERMINAR',
          Icons.save_rounded,
          _guardando ? null : () => _guardar(siguiente: true),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _guardando ? null : () => setState(() => _fase = _Fase.config),
          child: const Text('Descartar y repetir'),
        ),
      ],
    );
  }

  // ─── Helpers de UI ──────────────────────────────────────────────────────

  Widget _label(AppColors colors, String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: colors.fgSoft)),
      );

  Widget _statLinea(AppColors colors, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: TextStyle(fontSize: 15, color: colors.fgMuted)),
            Text(v,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: colors.fg)),
          ],
        ),
      );

  Widget _stepperBtn(AppColors colors, IconData icon, VoidCallback onTap) =>
      Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colors.line)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(width: 56, height: 56, child: Icon(icon, color: colors.fg)),
        ),
      );

  Widget _botonGrande(
          AppColors colors, String texto, IconData icon, VoidCallback? onTap) =>
      SizedBox(
        height: 72,
        child: FilledButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 24),
          label: Text(texto,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          style: FilledButton.styleFrom(backgroundColor: colors.brand),
        ),
      );
}
