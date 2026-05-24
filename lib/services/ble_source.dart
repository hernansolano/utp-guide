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

  /// Snapshot sincrónico del estado actual.
  BleEstado get estadoActual;

  /// Arranca la emisión de lecturas. Async porque puede requerir
  /// permisos del sistema o inicialización de Bluetooth.
  Future<void> iniciarEscaneo();

  /// Detiene la emisión y libera recursos.
  Future<void> detenerEscaneo();

  /// Cierra los streams y libera recursos permanentes. Después de
  /// `dispose()`, el servicio no se puede reutilizar.
  void dispose();
}
