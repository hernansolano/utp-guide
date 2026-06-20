import 'dart:convert';

/// Tipos de experimento del Modo Investigador (JIC 2026).
///
/// El proyecto se eleva a nivel científico para la Jornada de Iniciación
/// Científica. El artículo se ancla en dos preguntas:
/// - **EXP1 (Q1):** caracterización del modelo de path-loss (estimar `n`).
/// - **EXP2 (Q2):** comparación de algoritmos de posicionamiento.
enum ExperimentType {
  exp1Propagacion,
  exp2Comparacion,
}

extension ExperimentTypeX on ExperimentType {
  String get codigo => switch (this) {
        ExperimentType.exp1Propagacion => 'EXP1',
        ExperimentType.exp2Comparacion => 'EXP2',
      };

  String get titulo => switch (this) {
        ExperimentType.exp1Propagacion => 'Caracterización de propagación',
        ExperimentType.exp2Comparacion => 'Comparación de algoritmos',
      };

  static ExperimentType desdeCodigo(String c) => ExperimentType.values
      .firstWhere((e) => e.codigo == c,
          orElse: () => ExperimentType.exp1Propagacion);
}

/// Una muestra individual de un experimento: timestamp + campos libres
/// específicos del experimento (RSSI, posiciones, errores, etc.).
///
/// El mapa flexible [valores] evita modelos rígidos distintos por
/// experimento y facilita el aplanado a CSV. Las claves las definen las
/// pantallas de cada experimento (ej. EXP1: `rssi`, `minor`; EXP2:
/// `estimaciones`, `real_x`).
class MeasurementSample {
  final DateTime timestamp;
  final Map<String, dynamic> valores;

  const MeasurementSample({required this.timestamp, required this.valores});

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'valores': valores,
      };

  factory MeasurementSample.fromJson(Map<String, dynamic> j) =>
      MeasurementSample(
        timestamp: DateTime.parse(j['timestamp'] as String),
        valores: Map<String, dynamic>.from(j['valores'] as Map),
      );
}

/// Una sesión de medición: agrupa las muestras de un experimento con su
/// contexto (tester, metadatos como distancia/punto/layout). Es la unidad
/// que se persiste como un archivo JSON ([MeasurementRepository]).
class MeasurementSession {
  final String id;
  final ExperimentType tipo;
  final String tester;
  final DateTime inicio;
  DateTime? fin;

  /// Condiciones de la sesión: distancia, minor, punto, layout, momento
  /// del día, ocupación, etc. Lo que cada experimento necesite registrar.
  final Map<String, dynamic> metadata;

  final List<MeasurementSample> muestras;

  MeasurementSession({
    required this.id,
    required this.tipo,
    required this.tester,
    required this.inicio,
    this.fin,
    Map<String, dynamic>? metadata,
    List<MeasurementSample>? muestras,
  })  : metadata = metadata ?? {},
        muestras = muestras ?? [];

  /// Crea una sesión nueva con id basado en el timestamp (sin dependencia
  /// de un paquete de UUID).
  factory MeasurementSession.nueva({
    required ExperimentType tipo,
    required String tester,
    Map<String, dynamic>? metadata,
  }) {
    final ahora = DateTime.now();
    return MeasurementSession(
      id: '${ahora.microsecondsSinceEpoch}',
      tipo: tipo,
      tester: tester,
      inicio: ahora,
      metadata: metadata,
    );
  }

  Duration get duracion => (fin ?? DateTime.now()).difference(inicio);
  int get cantidadMuestras => muestras.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'tipo': tipo.codigo,
        'tester': tester,
        'inicio': inicio.toIso8601String(),
        'fin': fin?.toIso8601String(),
        'metadata': metadata,
        'muestras': [for (final m in muestras) m.toJson()],
      };

  factory MeasurementSession.fromJson(Map<String, dynamic> j) =>
      MeasurementSession(
        id: j['id'] as String,
        tipo: ExperimentTypeX.desdeCodigo(j['tipo'] as String),
        tester: j['tester'] as String,
        inicio: DateTime.parse(j['inicio'] as String),
        fin: j['fin'] != null ? DateTime.parse(j['fin'] as String) : null,
        metadata: Map<String, dynamic>.from(j['metadata'] as Map? ?? {}),
        muestras: [
          for (final m in (j['muestras'] as List? ?? []))
            MeasurementSample.fromJson(Map<String, dynamic>.from(m as Map)),
        ],
      );

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}
