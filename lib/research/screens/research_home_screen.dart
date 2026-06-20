import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../ui/theme/app_theme.dart';
import '../models/measurement_session.dart';
import '../services/measurement_repository.dart';
import '../services/research_exporter.dart';

/// Menú principal del **Modo Investigador** (JIC 2026).
///
/// Separado del modo usuario: aquí vive la infraestructura experimental.
/// UX pensada para campo (botones grandes, alto contraste) — el tester
/// está parado en un pasillo con el teléfono en una mano.
///
/// Se entra con 7 taps sobre el logo en la pantalla de inicio.
class ResearchHomeScreen extends StatefulWidget {
  final MeasurementRepository repository;
  final ResearchExporter exporter;

  const ResearchHomeScreen({
    super.key,
    required this.repository,
    required this.exporter,
  });

  @override
  State<ResearchHomeScreen> createState() => _ResearchHomeScreenState();
}

class _ResearchHomeScreenState extends State<ResearchHomeScreen> {
  static const _testers = ['Hernán', 'Tiphany', 'Paola'];
  String _tester = _testers.first;

  ({int sesiones, int muestras}) _exp1 = (sesiones: 0, muestras: 0);
  ({int sesiones, int muestras}) _exp2 = (sesiones: 0, muestras: 0);
  bool _exportando = false;

  @override
  void initState() {
    super.initState();
    _refrescarConteos();
  }

  Future<void> _refrescarConteos() async {
    final e1 = await widget.repository.contar(ExperimentType.exp1Propagacion);
    final e2 = await widget.repository.contar(ExperimentType.exp2Comparacion);
    if (!mounted) return;
    setState(() {
      _exp1 = e1;
      _exp2 = e2;
    });
  }

  void _abrirExperimento(ExperimentType tipo) {
    final ruta = tipo == ExperimentType.exp1Propagacion
        ? '/research/exp1'
        : '/research/exp2';
    // Al volver, refrescar los conteos (se pudo guardar una sesión).
    context
        .push(ruta, extra: {'tester': _tester})
        .then((_) => _refrescarConteos());
  }

  Future<void> _exportar(ExperimentType tipo) async {
    if (_exportando) return;
    setState(() => _exportando = true);
    try {
      final sesiones = await widget.repository.listar(tipo: tipo);
      if (sesiones.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No hay sesiones de ${tipo.codigo} para exportar.'),
            duration: const Duration(seconds: 2),
          ));
        }
        return;
      }
      final filas = await widget.exporter.exportarYCompartir(sesiones, tipo);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${tipo.codigo}: $filas filas exportadas.'),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al exportar: $e'),
          duration: const Duration(seconds: 3),
        ));
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _header(colors),
            const SizedBox(height: 20),
            _selectorTester(colors),
            const SizedBox(height: 24),
            _botonExperimento(colors, ExperimentType.exp1Propagacion,
                'RSSI vs distancia · estimar n'),
            const SizedBox(height: 14),
            _botonExperimento(colors, ExperimentType.exp2Comparacion,
                'Comparar algoritmos · error de posición'),
            const SizedBox(height: 28),
            Text('EXPORTAR DATOS',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: colors.fgSoft)),
            const SizedBox(height: 12),
            _filaExport(colors, ExperimentType.exp1Propagacion, _exp1),
            const SizedBox(height: 10),
            _filaExport(colors, ExperimentType.exp2Comparacion, _exp2),
          ],
        ),
      ),
    );
  }

  Widget _header(AppColors colors) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('MODO INVESTIGADOR',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: colors.fg)),
              const SizedBox(height: 2),
              Text('UTP-Guide · recolección de datos (JIC 2026)',
                  style: TextStyle(fontSize: 13, color: colors.fgMuted)),
            ],
          ),
        ),
        TextButton.icon(
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          icon: const Icon(Icons.exit_to_app_rounded, size: 18),
          label: const Text('Salir'),
        ),
      ],
    );
  }

  Widget _selectorTester(AppColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.line),
      ),
      child: Row(
        children: [
          Icon(Icons.person_outline_rounded, color: colors.fgMuted, size: 22),
          const SizedBox(width: 12),
          Text('Tester:',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: colors.fg)),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButton<String>(
              value: _tester,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: [
                for (final t in _testers)
                  DropdownMenuItem(value: t, child: Text(t)),
              ],
              onChanged: (v) => setState(() => _tester = v ?? _tester),
            ),
          ),
        ],
      ),
    );
  }

  Widget _botonExperimento(
      AppColors colors, ExperimentType tipo, String subtitulo) {
    return Material(
      color: colors.brand,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _abrirExperimento(tipo),
        child: Container(
          height: 96,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.centerLeft,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${tipo.codigo} · ${tipo.titulo}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(subtitulo,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filaExport(AppColors colors, ExperimentType tipo,
      ({int sesiones, int muestras}) c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tipo.codigo,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: colors.fg)),
                Text('${c.sesiones} sesiones · ${c.muestras} muestras',
                    style: TextStyle(fontSize: 12, color: colors.fgMuted)),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: _exportando ? null : () => _exportar(tipo),
            icon: const Icon(Icons.ios_share_rounded, size: 16),
            label: const Text('CSV'),
          ),
        ],
      ),
    );
  }
}
