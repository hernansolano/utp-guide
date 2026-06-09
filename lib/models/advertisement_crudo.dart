/// Formato del payload de una baliza BLE detectada.
///
/// El sistema soporta dos formatos estándar para Fase 1:
/// - [iBeacon]: Apple Company ID 0x004C. Lo que emite el "Beacon Simulator"
///   del App Store iOS y la mayoría de balizas comerciales (Minew, Estimote).
/// - [eddystoneUid]: Google. Lo que emiten algunas apps simuladoras en
///   Android cuando se les configura "Eddystone" como formato.
///
/// [desconocido] cubre cualquier otro advertisement BLE que llegue al
/// escáner: BLE genérico sin manufacturer/service data reconocible. Útil
/// solo para diagnóstico — el `PositioningService` no los procesa.
enum FormatoBalizaBle {
  iBeacon,
  eddystoneUid,
  desconocido,
}

/// Snapshot de un advertisement BLE recibido, **sin filtrar**.
///
/// Se usa en la herramienta de diagnóstico en `CalibracionScreen` para que
/// el dev pueda ver qué emite cualquier simulador o baliza física, aunque
/// no coincida con el UUID del proyecto o sea de otro formato.
///
/// No se persiste — vive en memoria mientras la pantalla esté abierta.
class AdvertisementCrudo {
  /// MAC o identificador del dispositivo emisor (según plataforma).
  final String deviceId;

  /// RSSI medido al recibir el paquete (dBm, valor negativo).
  final double rssi;

  /// Formato detectado.
  final FormatoBalizaBle formato;

  /// UUID parseado del payload, o `null` si el formato no lo tiene
  /// (ej. BLE genérico) o no se pudo parsear.
  final String? uuid;

  /// Major (iBeacon) o Namespace truncado (Eddystone). Null si no aplica.
  final int? major;

  /// Minor (iBeacon) o Instance (Eddystone). Null si no aplica.
  final int? minor;

  /// `true` si el `PositioningService` aceptó este paquete y lo procesó.
  /// `false` si fue descartado (UUID distinto, formato desconocido, etc.).
  final bool aceptado;

  /// Razón humanamente legible de por qué se descartó (si `aceptado` es
  /// `false`). Vacío si fue aceptado.
  final String motivoDescarte;

  final DateTime timestamp;

  const AdvertisementCrudo({
    required this.deviceId,
    required this.rssi,
    required this.formato,
    required this.aceptado,
    required this.timestamp,
    this.uuid,
    this.major,
    this.minor,
    this.motivoDescarte = '',
  });

  /// Etiqueta corta del formato para listas (3-4 chars).
  String get formatoCorto {
    switch (formato) {
      case FormatoBalizaBle.iBeacon:
        return 'iBcn';
      case FormatoBalizaBle.eddystoneUid:
        return 'EdSt';
      case FormatoBalizaBle.desconocido:
        return 'BLE';
    }
  }
}
