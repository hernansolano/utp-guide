import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/beacon_reading.dart';

/// Escanea continuamente anuncios iBeacon y emite un [BeaconReading]
/// por cada paquete que coincida con el UUID del proyecto.
///
/// Uso:
///   final ble = BleService();
///   ble.iniciarEscaneo();
///   ble.beaconStream.listen((r) { ... });
///   ble.detenerEscaneo();
class BleService {
  // UUID del proyecto definido en beacon_config.json
  static const _targetUuid = '550e8400-e29b-41d4-a716-446655440000';

  final _controller = StreamController<BeaconReading>.broadcast();
  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _restartTimer;
  bool _activo = false;

  /// Stream de lecturas de beacons que coinciden con el UUID del proyecto.
  Stream<BeaconReading> get beaconStream => _controller.stream;

  /// Estado del adaptador Bluetooth del dispositivo.
  Stream<BluetoothAdapterState> get adapterState =>
      FlutterBluePlus.adapterState;

  /// Inicia el ciclo de escaneo BLE (4 s scan / 0.5 s pausa / repetir).
  Future<void> iniciarEscaneo() async {
    if (_activo) return;
    _activo = true;

    // Suscribirse a resultados antes de iniciar el primer scan
    _scanSub = FlutterBluePlus.scanResults.listen(_procesarResultados);

    await _iniciarCiclo();
  }

  Future<void> _iniciarCiclo() async {
    if (!_activo) return;
    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 4),
        continuousUpdates: true,
      );
    } catch (_) {
      // BLE no disponible o permiso denegado — falla silenciosamente
    }
    // Programar el próximo ciclo 200ms después de que termine el scan
    _restartTimer =
        Timer(const Duration(milliseconds: 4200), _iniciarCiclo);
  }

  /// Detiene el escaneo y libera recursos.
  Future<void> detenerEscaneo() async {
    if (!_activo) return;
    _activo = false;
    _restartTimer?.cancel();
    _restartTimer = null;
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
  }

  void _procesarResultados(List<ScanResult> results) {
    for (final r in results) {
      final reading = _parsearIBeacon(r);
      if (reading != null && !_controller.isClosed) {
        _controller.add(reading);
      }
    }
  }

  /// Intenta parsear un resultado de escaneo como iBeacon.
  /// Retorna null si el paquete no es un iBeacon con el UUID del proyecto.
  BeaconReading? _parsearIBeacon(ScanResult result) {
    // El Company ID de Apple es 0x004C (little-endian en el wire: 0x4C 0x00)
    final mfData = result.advertisementData.manufacturerData[0x004C];
    if (mfData == null || mfData.length < 23) return null;

    // Verificar tipo iBeacon: byte[0]=0x02, byte[1]=0x15 (longitud 21)
    if (mfData[0] != 0x02 || mfData[1] != 0x15) return null;

    // UUID: bytes 2–17 (16 bytes big-endian)
    final uuid = _parsearUuid(mfData.sublist(2, 18));
    if (uuid.toLowerCase() != _targetUuid) return null;

    // Major: bytes 18–19 (big-endian) — se usa para identificar el piso
    // final major = (mfData[18] << 8) | mfData[19]; // no usado aún

    // Minor: bytes 20–21 (big-endian) — identifica el beacon individual
    final minor = (mfData[20] << 8) | mfData[21];

    return BeaconReading(
      minor: minor,
      rssi: result.rssi.toDouble(),
      timestamp: DateTime.now(),
    );
  }

  /// Convierte 16 bytes a formato UUID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  String _parsearUuid(List<int> bytes) {
    final hex =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  void dispose() {
    detenerEscaneo();
    _controller.close();
  }
}
