import 'dart:io';
import 'dart:ui' show Rect;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/measurement_session.dart';

/// Genera un CSV de las sesiones y lo comparte vía el share del sistema
/// operativo (WhatsApp, Drive, email, copiar por USB). Un formato de CSV
/// por tipo de experimento, listo para pandas/R/Excel sin reformateo.
class ResearchExporter {
  /// Escribe el CSV del [tipo] a un archivo temporal y abre el share.
  /// Devuelve la cantidad de filas de datos exportadas.
  ///
  /// [sharePositionOrigin]: rect ancla del share sheet. En iOS/iPad es
  /// **obligatorio** y debe ser no-cero; sin él, `Share` lanza
  /// `PlatformException(sharePositionOrigin: argument must be set...)`. El
  /// llamador lo calcula desde el `RenderBox` del contexto del botón.
  Future<int> exportarYCompartir(
      List<MeasurementSession> sesiones, ExperimentType tipo,
      {Rect? sharePositionOrigin}) async {
    final (csv, filas) = tipo == ExperimentType.exp1Propagacion
        ? _csvExp1(sesiones)
        : _csvExp2(sesiones);

    final dir = await getTemporaryDirectory();
    final nombre = '${tipo.codigo.toLowerCase()}_utpguide_jic.csv';
    final f = File('${dir.path}/$nombre');
    await f.writeAsString(csv);

    await Share.shareXFiles(
      [XFile(f.path, mimeType: 'text/csv')],
      text: 'Datos ${tipo.codigo} — UTP-Guide (JIC 2026)',
      subject: nombre,
      sharePositionOrigin: sharePositionOrigin,
    );
    return filas;
  }

  /// EXP1: una fila por muestra de RSSI a una distancia conocida.
  (String, int) _csvExp1(List<MeasurementSession> sesiones) {
    final sb = StringBuffer(
        'session_id,tester,distancia_m,beacon_minor,momento,sample_num,rssi_dbm,timestamp\n');
    var filas = 0;
    for (final s in sesiones.where((s) => s.tipo == ExperimentType.exp1Propagacion)) {
      final dist = s.metadata['distancia_m'] ?? '';
      final minor = s.metadata['beacon_minor'] ?? '';
      final momento = s.metadata['momento'] ?? '';
      for (var i = 0; i < s.muestras.length; i++) {
        final m = s.muestras[i];
        sb.writeln('${s.id},${_csv(s.tester)},$dist,$minor,$momento,'
            '${i + 1},${m.valores['rssi'] ?? ''},${m.timestamp.toIso8601String()}');
        filas++;
      }
    }
    return (sb.toString(), filas);
  }

  /// EXP2: una fila por (muestra × algoritmo) con su error de posición.
  (String, int) _csvExp2(List<MeasurementSession> sesiones) {
    final sb = StringBuffer(
        'session_id,tester,punto_id,real_x,real_y,layout,sample_num,'
        'algoritmo,est_x,est_y,error_m,timestamp\n');
    var filas = 0;
    for (final s in sesiones.where((s) => s.tipo == ExperimentType.exp2Comparacion)) {
      final p = s.metadata['punto_id'] ?? '';
      final rx = s.metadata['real_x'] ?? '';
      final ry = s.metadata['real_y'] ?? '';
      final layout = s.metadata['layout'] ?? '';
      for (var i = 0; i < s.muestras.length; i++) {
        final m = s.muestras[i];
        final estimaciones = (m.valores['estimaciones'] as Map?) ?? const {};
        estimaciones.forEach((algo, e) {
          final em = e as Map;
          sb.writeln('${s.id},${_csv(s.tester)},$p,$rx,$ry,${_csv('$layout')},'
              '${i + 1},${_csv('$algo')},${em['x'] ?? ''},${em['y'] ?? ''},'
              '${em['error'] ?? ''},${m.timestamp.toIso8601String()}');
          filas++;
        });
      }
    }
    return (sb.toString(), filas);
  }

  /// Escapa un campo de texto para CSV (comillas si tiene coma/comilla).
  String _csv(String v) {
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }
}
