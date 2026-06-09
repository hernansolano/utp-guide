import '../models/advertisement_crudo.dart';
import '../models/beacon_reading.dart';
import 'ble_service.dart' show BleEstado;

/// Interfaz común para cualquier fuente de lecturas iBeacon.
///
/// El `PositioningService` consume `BleSource` (no `BleService` concreto)
/// para poder intercambiar la fuente real por una simulada en tiempo de
/// ejecución sin alterar el resto del pipeline. Ver
/// `docs/adr/0008-simulador-ble-para-testing.md`.
///
/// Implementaciones actuales:
/// - `BleService` — escaneo real con `flutter_blue_plus`
/// - `SimulatedBleService` — genera lecturas sintéticas desde una
///   posición virtual del usuario, útil para testing sin hardware
/// - `BleSourceMultiplexer` — conmuta entre las dos según un toggle
abstract interface class BleSource {
  /// Stream de lecturas iBeacon que coinciden con el UUID del proyecto.
  Stream<BeaconReading> get beaconStream;

  /// Stream del estado del servicio (escaneando, permisos, BT apagado,
  /// simulando, error). La UI lo consume para mostrar mensajes.
  Stream<BleEstado> get estadoStream;

  /// Stream de advertisements BLE crudos para herramientas de diagnóstico.
  ///
  /// Emite **todos** los paquetes recibidos, incluso los descartados por
  /// no coincidir con el UUID del proyecto o por usar formato desconocido.
  /// Cada [AdvertisementCrudo] incluye el motivo del descarte cuando
  /// aplica. Solo se emite si la fuente está corriendo en `kDebugMode` —
  /// en release el stream existe pero no recibe eventos, evitando overhead.
  Stream<AdvertisementCrudo> get advertisementsCrudosStream;

  /// Snapshot sincrónico del estado actual.
  BleEstado get estadoActual;

  /// Arranca la emisión de lecturas. Async porque puede requerir
  /// permisos del sistema o inicialización de Bluetooth.
  Future<void> iniciarEscaneo();

  /// Fuerza una nueva solicitud de permisos. Útil cuando el primer
  /// intento falló (estado `permisosNegados`) y el usuario quiere
  /// reintentar manualmente desde la UI. Retorna `true` si los
  /// permisos quedan concedidos.
  Future<bool> reintentarPermisos();

  /// Detiene la emisión y libera recursos.
  Future<void> detenerEscaneo();

  /// Cierra los streams y libera recursos permanentes. Después de
  /// `dispose()`, el servicio no se puede reutilizar.
  void dispose();
}
