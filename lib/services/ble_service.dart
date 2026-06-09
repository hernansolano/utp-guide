import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/advertisement_crudo.dart';
import '../models/beacon_reading.dart';
import 'ble_source.dart';

/// Estado del servicio de escaneo BLE.
///
/// La UI se suscribe a [BleService.estadoStream] para mostrar el mensaje
/// apropiado al usuario en cada caso. Ver
/// `docs/adr/0004-permisos-runtime.md` para el contexto completo.
enum BleEstado {
  /// El servicio no está activo (estado inicial o tras `detenerEscaneo`).
  inactivo,

  /// Se están solicitando permisos al usuario.
  solicitandoPermisos,

  /// El usuario denegó algún permiso requerido. La UI debe mostrar
  /// instrucciones para activar los permisos manualmente.
  permisosNegados,

  /// El adaptador Bluetooth del dispositivo está apagado. La UI debe
  /// pedir al usuario que lo encienda.
  bluetoothApagado,

  /// El escaneo está activo y se están recibiendo (o no) anuncios.
  escaneando,

  /// El servicio está emitiendo lecturas sintéticas desde una posición
  /// virtual (modo simulación). No hay hardware real involucrado.
  simulando,

  /// Error inesperado. La UI puede mostrar un mensaje genérico.
  error,
}

/// Escanea anuncios iBeacon continuamente y emite [BeaconReading] por
/// cada paquete que coincide con el UUID del proyecto.
///
/// Antes de iniciar el escaneo, el servicio:
///
/// 1. Solicita los permisos requeridos en runtime (Android 12+ necesita
///    `BLUETOOTH_SCAN` y `BLUETOOTH_CONNECT`; versiones anteriores
///    necesitan `ACCESS_FINE_LOCATION`; iOS necesita Bluetooth)
/// 2. Verifica que el adaptador BT esté encendido
/// 3. Si ambas condiciones se cumplen, arranca el ciclo de escaneo
///
/// Si alguna condición falla, el servicio emite el estado correspondiente
/// vía [estadoStream] y la UI puede reaccionar.
///
/// **UUID configurable:** el UUID que filtra se setea con
/// [configurarUuidObjetivo]. Si no se llama, se usa el default histórico
/// del proyecto. `main()` lo llama después de cargar `beacon_config.json`.
///
/// **Diagnóstico:** en `kDebugMode`, todo advertisement BLE recibido se
/// emite también por [advertisementsCrudosStream], incluyendo los
/// descartados por UUID distinto o formato no iBeacon. La pantalla de
/// calibración lo consume para mostrar al dev qué emite el simulador.
class BleService implements BleSource {
  /// UUID por defecto si nadie llama [configurarUuidObjetivo]. Coincide
  /// con el valor histórico del beacon_config.json del proyecto.
  static const _uuidDefault = '550e8400-e29b-41d4-a716-446655440000';

  /// UUID del proyecto (lowercase). Mutable para permitir cargar desde
  /// JSON después de construir el servicio.
  String _uuidObjetivo;

  final _beaconController = StreamController<BeaconReading>.broadcast();
  final _estadoController = StreamController<BleEstado>.broadcast();
  final _crudoController = StreamController<AdvertisementCrudo>.broadcast();
  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _restartTimer;
  bool _activo = false;
  BleEstado _estadoActual = BleEstado.inactivo;

  BleService({String? uuidObjetivo})
      : _uuidObjetivo = (uuidObjetivo ?? _uuidDefault).toLowerCase();

  /// Cambia el UUID que se acepta como válido. Útil para cargar el
  /// valor real desde `beacon_config.json` después de construir el
  /// servicio (el constructor corre antes que async I/O en main).
  void configurarUuidObjetivo(String uuid) {
    _uuidObjetivo = uuid.toLowerCase();
  }

  /// UUID activo (lowercase, formato canónico 8-4-4-4-12).
  String get uuidObjetivo => _uuidObjetivo;

  /// Stream de lecturas de balizas que coinciden con el UUID del proyecto.
  @override
  Stream<BeaconReading> get beaconStream => _beaconController.stream;

  /// Stream del estado del servicio. Útil para UI que necesita mostrar
  /// diálogos o mensajes de error específicos al usuario.
  @override
  Stream<BleEstado> get estadoStream => _estadoController.stream;

  /// Stream de TODOS los advertisements BLE recibidos, sin filtrar.
  /// Solo emite en kDebugMode. Ver [BleSource.advertisementsCrudosStream].
  @override
  Stream<AdvertisementCrudo> get advertisementsCrudosStream =>
      _crudoController.stream;

  /// Último estado emitido. Útil para inicializar UI sin esperar el
  /// primer evento del stream.
  @override
  BleEstado get estadoActual => _estadoActual;

  /// Inicia el ciclo completo: solicita permisos, verifica BT, escanea.
  ///
  /// Si los permisos se deniegan o BT está apagado, el servicio emite
  /// el estado correspondiente y retorna sin lanzar excepción.
  @override
  Future<void> iniciarEscaneo() async {
    if (_activo) return;

    // Paso 1 — permisos
    _emitir(BleEstado.solicitandoPermisos);
    final permisosOk = await _solicitarPermisos();
    if (!permisosOk) {
      _emitir(BleEstado.permisosNegados);
      return;
    }

    // Paso 2 — adaptador BT encendido
    final adapter = await FlutterBluePlus.adapterState.first
        .timeout(const Duration(seconds: 2), onTimeout: () => BluetoothAdapterState.unknown);
    if (adapter != BluetoothAdapterState.on) {
      _emitir(BleEstado.bluetoothApagado);
      return;
    }

    // Paso 3 — arrancar ciclo de escaneo
    _activo = true;
    _scanSub = FlutterBluePlus.scanResults.listen(_procesarResultados);
    _emitir(BleEstado.escaneando);
    await _iniciarCiclo();
  }

  /// Solicita los permisos requeridos según la plataforma y versión.
  ///
  /// Android 12+ (API 31+):
  ///   - `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`
  /// Android < 12:
  ///   - `ACCESS_FINE_LOCATION` (Bluetooth requiere ubicación por
  ///     razones históricas en Google Play Services)
  /// iOS:
  ///   - Bluetooth (manejado por NSBluetoothAlwaysUsageDescription en
  ///     Info.plist; la solicitud aparece automáticamente al iniciar BT)
  Future<bool> _solicitarPermisos() async {
    try {
      if (Platform.isAndroid) {
        // Solicitar los permisos modernos primero; en versiones viejas
        // Android los acepta silenciosamente (no hay efecto adverso).
        final resultados = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse,
        ].request();

        // Suficiente con tener scan + connect (en Android 12+) o
        // location (en Android < 12). El paquete maneja esto bien.
        final scanOk =
            resultados[Permission.bluetoothScan]?.isGranted ?? false;
        final connectOk =
            resultados[Permission.bluetoothConnect]?.isGranted ?? false;
        final locationOk =
            resultados[Permission.locationWhenInUse]?.isGranted ?? false;

        return (scanOk && connectOk) || locationOk;
      } else if (Platform.isIOS) {
        // iOS pide el permiso automáticamente al primer uso de Bluetooth
        // siempre que NSBluetoothAlwaysUsageDescription esté en Info.plist.
        final result = await Permission.bluetooth.request();
        return result.isGranted || result.isLimited;
      }
      return true; // otras plataformas: asumir OK
    } catch (_) {
      return false;
    }
  }

  Future<void> _iniciarCiclo() async {
    if (!_activo) return;
    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 4),
        continuousUpdates: true,
      );
    } catch (_) {
      _emitir(BleEstado.error);
    }
    _restartTimer =
        Timer(const Duration(milliseconds: 4200), _iniciarCiclo);
  }

  /// Detiene el escaneo y libera recursos.
  @override
  Future<void> detenerEscaneo() async {
    if (!_activo) {
      _emitir(BleEstado.inactivo);
      return;
    }
    _activo = false;
    _restartTimer?.cancel();
    _restartTimer = null;
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
    _emitir(BleEstado.inactivo);
  }

  void _procesarResultados(List<ScanResult> results) {
    for (final r in results) {
      _procesarUnResultado(r);
    }
  }

  /// Intenta parsear como iBeacon. Si lo es, valida UUID y o bien emite
  /// un [BeaconReading] (UUID match) o un [AdvertisementCrudo] descartado
  /// (UUID distinto). Si no es iBeacon, intenta detectar Eddystone y
  /// reporta como crudo. Si nada match, emite "BLE genérico" en debug.
  void _procesarUnResultado(ScanResult result) {
    final mfData = result.advertisementData.manufacturerData[0x004C];
    final esIBeaconValido =
        mfData != null && mfData.length >= 23 && mfData[0] == 0x02 && mfData[1] == 0x15;

    if (esIBeaconValido) {
      _manejarIBeacon(result, mfData);
      return;
    }

    // No es iBeacon — chequear Eddystone para informar al usuario que
    // está usando un formato no soportado.
    if (_pareceEddystone(result)) {
      _emitirCrudo(AdvertisementCrudo(
        deviceId: result.device.remoteId.str,
        rssi: result.rssi.toDouble(),
        formato: FormatoBalizaBle.eddystoneUid,
        aceptado: false,
        timestamp: DateTime.now(),
        motivoDescarte: 'Eddystone no soportado · use iBeacon en el simulador',
      ));
      return;
    }

    // BLE genérico — solo emitir en debug para no inundar UI con
    // dispositivos cercanos (audífonos, teléfonos, etc.).
    if (kDebugMode) {
      _emitirCrudo(AdvertisementCrudo(
        deviceId: result.device.remoteId.str,
        rssi: result.rssi.toDouble(),
        formato: FormatoBalizaBle.desconocido,
        aceptado: false,
        timestamp: DateTime.now(),
        motivoDescarte: 'No es iBeacon ni Eddystone',
      ));
    }
  }

  /// Parsea un paquete iBeacon ya validado. Si el UUID coincide con el
  /// objetivo, emite [BeaconReading]; si no, lo reporta como descartado.
  void _manejarIBeacon(ScanResult result, List<int> mfData) {
    final uuid = _parsearUuid(mfData.sublist(2, 18));
    final major = (mfData[18] << 8) | mfData[19];
    final minor = (mfData[20] << 8) | mfData[21];
    final uuidLower = uuid.toLowerCase();
    final uuidMatch = uuidLower == _uuidObjetivo;

    if (uuidMatch) {
      if (!_beaconController.isClosed) {
        _beaconController.add(BeaconReading(
          minor: minor,
          major: major,
          rssi: result.rssi.toDouble(),
          timestamp: DateTime.now(),
        ));
      }
      _emitirCrudo(AdvertisementCrudo(
        deviceId: result.device.remoteId.str,
        rssi: result.rssi.toDouble(),
        formato: FormatoBalizaBle.iBeacon,
        uuid: uuidLower,
        major: major,
        minor: minor,
        aceptado: true,
        timestamp: DateTime.now(),
      ));
    } else {
      _emitirCrudo(AdvertisementCrudo(
        deviceId: result.device.remoteId.str,
        rssi: result.rssi.toDouble(),
        formato: FormatoBalizaBle.iBeacon,
        uuid: uuidLower,
        major: major,
        minor: minor,
        aceptado: false,
        timestamp: DateTime.now(),
        motivoDescarte: 'UUID distinto al del proyecto',
      ));
    }
  }

  /// Detecta si el advertisement parece ser Eddystone, buscando el UUID
  /// de servicio 0xFEAA en cualquier formato (16-bit o 128-bit canónico).
  bool _pareceEddystone(ScanResult result) {
    for (final guid in result.advertisementData.serviceData.keys) {
      final s = guid.str.toLowerCase();
      if (s.startsWith('feaa') || s.contains('0000feaa-')) return true;
    }
    for (final guid in result.advertisementData.serviceUuids) {
      final s = guid.str.toLowerCase();
      if (s.startsWith('feaa') || s.contains('0000feaa-')) return true;
    }
    return false;
  }

  /// Convierte 16 bytes a formato UUID estándar.
  String _parsearUuid(List<int> bytes) {
    final hex =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  void _emitirCrudo(AdvertisementCrudo a) {
    if (!_crudoController.isClosed) _crudoController.add(a);
  }

  void _emitir(BleEstado nuevo) {
    _estadoActual = nuevo;
    if (!_estadoController.isClosed) _estadoController.add(nuevo);
  }

  @override
  void dispose() {
    detenerEscaneo();
    _beaconController.close();
    _estadoController.close();
    _crudoController.close();
  }
}
