import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import '../models/measurement_session.dart';

/// Persiste las sesiones de experimento como archivos JSON en el
/// directorio de documentos de la app.
///
/// Sin base de datos: para el volumen del piloto (decenas de sesiones,
/// miles de muestras) los archivos JSON son suficientes, portables y
/// re-analizables en Python/R sin reformateo. Cada sesión es un archivo
/// autocontenido `<CODIGO>_<id>.json`.
class MeasurementRepository {
  static const _subdir = 'research_sessions';

  Future<Directory> directorio() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/$_subdir');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// Guarda (o sobrescribe) la sesión en disco. Devuelve el archivo.
  Future<File> guardar(MeasurementSession s) async {
    final d = await directorio();
    final f = File('${d.path}/${s.tipo.codigo}_${s.id}.json');
    await f.writeAsString(s.encode());
    return f;
  }

  /// Carga todas las sesiones (opcionalmente filtradas por tipo),
  /// ordenadas de más reciente a más antigua. Las sesiones corruptas se
  /// saltan en silencio para no romper el listado.
  Future<List<MeasurementSession>> listar({ExperimentType? tipo}) async {
    final d = await directorio();
    final out = <MeasurementSession>[];
    await for (final e in d.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      try {
        final j = jsonDecode(await e.readAsString()) as Map<String, dynamic>;
        final s = MeasurementSession.fromJson(j);
        if (tipo == null || s.tipo == tipo) out.add(s);
      } catch (err) {
        // Archivo corrupto o de otra versión — se ignora.
        debugPrint('[MeasurementRepository] se ignora ${e.path}: $err');
      }
    }
    out.sort((a, b) => b.inicio.compareTo(a.inicio));
    return out;
  }

  /// Cuenta sesiones y muestras totales de un tipo.
  Future<({int sesiones, int muestras})> contar(ExperimentType tipo) async {
    final l = await listar(tipo: tipo);
    return (
      sesiones: l.length,
      muestras: l.fold<int>(0, (acc, s) => acc + s.cantidadMuestras),
    );
  }

  /// Borra una sesión por id+tipo. Devuelve true si existía.
  Future<bool> borrar(MeasurementSession s) async {
    final d = await directorio();
    final f = File('${d.path}/${s.tipo.codigo}_${s.id}.json');
    if (await f.exists()) {
      await f.delete();
      return true;
    }
    return false;
  }
}
