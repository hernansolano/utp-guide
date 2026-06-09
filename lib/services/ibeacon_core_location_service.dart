import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter_beacon/flutter_beacon.dart';
import '../models/advertisement_crudo.dart';
import '../models/beacon_reading.dart';
import 'ble_service.dart' show BleEstado;
import 'ble_source.dart';

/// Implementación de [BleSource] para iOS que detecta iBeacons vía
/// **Core Location** en lugar de Core Bluetooth.
///
/// **Por qué este servicio existe:** Apple bloquea los iBeacons (Company
/// ID Apple `0x004C`) en cualquier app que escanee via `CBCentralManager`.
/// Por eso `flutter_blue_plus` no los detecta en iPhone — los recibe el
/// SO y los filtra antes de pasárselos a la app. La única forma soportada
/// para apps de tercer party es `CLLocationManager` + ranging de regiones.
/// `flutter_beacon` envuelve esa API.
///
/// En Android, este servicio también funcionaría, pero seguimos usando
/// `BleService` (flutter_blue_plus) porque ahí sí tenemos el stream
/// crudo de TODOS los advertisements BLE — útil para el diagnóstico.
/// Core Location en iOS solo expone los iBeacons que matchean la región
/// monitoreada, no advertisements crudos.
///
/// **Cómo funciona:**
/// 1. `configurarUuidObjetivo(uuid)` o el default define la región a
///    monitorear (una sola región por iOS limit).
/// 2. `iniciarEscaneo()` pide permisos de location vía
///    `flutterBeacon.requestAuthorization`, verifica BT y location
///    services, e inicia el stream de `ranging`.
/// 3. Cada `RangingResult` trae 0..N `Beacon`s detectados con su UUID,
///    major, minor, RSSI y distancia estimada por iOS. Los convertimos
///    a [BeaconReading] y los re-emitimos.
class IbeaconCoreLocationService implements BleSource {
  static const _uuidDefault = '550e8400-e29b-41d4-a716-446655440000';

  String _uuidObjetivo;

  final _beaconController = StreamController<BeaconReading>.broadcast();
  final _estadoController = StreamController<BleEstado>.broadcast();
  final _crudoController = StreamController<AdvertisementCrudo>.broadcast();

  StreamSubscription<RangingResult>? _rangingSub;
  StreamSubscription<BluetoothState>? _btSub;
  BleEstado _estadoActual = BleEstado.inactivo;
  bool _activo = false;

  IbeaconCoreLocationService({String? uuidObjetivo})
      : _uuidObjetivo = (uuidObjetivo ?? _uuidDefault).toLowerCase();

  // ─── BleSource interface ──────────────────────────────────────────────────

  @override
  Stream<BeaconReading> get beaconStream => _beaconController.stream;

  @override
  Stream<BleEstado> get estadoStream => _estadoController.stream;

  @override
  Stream<AdvertisementCrudo> get advertisementsCrudosStream =>
      _crudoController.stream;

  @override
  BleEstado get estadoActual => _estadoActual;

  @override
  void configurarUuidObjetivo(String uuid) {
    final nuevo = uuid.toLowerCase();
    if (nuevo == _uuidObjetivo) return;
    _uuidObjetivo = nuevo;
    if (_activo) {
      // Reiniciar el ranging con la nueva región para que iOS empiece
      // a buscar el UUID nuevo. detener()/iniciar() es idempotente.
      detenerEscaneo().then((_) => iniciarEscaneo());
    }
  }

  @override
  Future<void> iniciarEscaneo() async {
    if (_activo) return;

    if (kDebugMode) {
      debugPrint('[IbeaconCoreLocation] iniciarEscaneo() — uuid=$_uuidObjetivo');
    }

    _emitir(BleEstado.solicitandoPermisos);

    // Paso 1 — inicializar el bridge nativo.
    try {
      await flutterBeacon.initializeScanning;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[IbeaconCoreLocation] initializeScanning falló: $e');
      }
      _emitir(BleEstado.error);
      return;
    }

    // Paso 2 — solicitar permisos de location. En iOS este método
    // dispara el diálogo nativo "Allow X to use your location".
    try {
      final auth = await flutterBeacon.authorizationStatus;
      if (kDebugMode) {
        debugPrint('[IbeaconCoreLocation] auth inicial: $auth');
      }
      if (auth != AuthorizationStatus.allowed &&
          auth != AuthorizationStatus.always &&
          auth != AuthorizationStatus.whenInUse) {
        await flutterBeacon.requestAuthorization;
        final tras = await flutterBeacon.authorizationStatus;
        if (kDebugMode) {
          debugPrint('[IbeaconCoreLocation] auth tras request: $tras');
        }
        if (tras != AuthorizationStatus.allowed &&
            tras != AuthorizationStatus.always &&
            tras != AuthorizationStatus.whenInUse) {
          _emitir(BleEstado.permisosNegados);
          return;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[IbeaconCoreLocation] auth error: $e');
      }
      _emitir(BleEstado.permisosNegados);
      return;
    }

    // Paso 3 — verificar BT encendido. En iOS, Core Location ranging
    // todavía requiere BT activo aunque use otra API.
    try {
      final btState = await flutterBeacon.bluetoothState;
      if (kDebugMode) {
        debugPrint('[IbeaconCoreLocation] btState: $btState');
      }
      if (btState != BluetoothState.stateOn) {
        _emitir(BleEstado.bluetoothApagado);
      }
    } catch (_) {
      // Si el chequeo falla, intentamos arrancar igual — el ranging
      // dará error si BT no está.
    }

    // Paso 4 — arrancar ranging de la región objetivo.
    final regions = <Region>[
      Region(identifier: 'utp-guide', proximityUUID: _uuidObjetivo),
    ];

    _rangingSub = flutterBeacon.ranging(regions).listen(
      _onRangingResult,
      onError: (e) {
        if (kDebugMode) {
          debugPrint('[IbeaconCoreLocation] ranging error: $e');
        }
        _emitir(BleEstado.error);
      },
    );

    // Escuchar cambios del estado de BT para reflejarlos en la UI.
    _btSub = flutterBeacon.bluetoothStateChanged().listen((BluetoothState s) {
      if (kDebugMode) {
        debugPrint('[IbeaconCoreLocation] bluetoothStateChanged: $s');
      }
      if (s == BluetoothState.stateOn) {
        if (_activo) _emitir(BleEstado.escaneando);
      } else {
        _emitir(BleEstado.bluetoothApagado);
      }
    });

    _activo = true;
    _emitir(BleEstado.escaneando);
  }

  @override
  Future<void> detenerEscaneo() async {
    if (!_activo) {
      _emitir(BleEstado.inactivo);
      return;
    }
    _activo = false;
    await _rangingSub?.cancel();
    await _btSub?.cancel();
    _rangingSub = null;
    _btSub = null;
    _emitir(BleEstado.inactivo);
  }

  @override
  Future<bool> reintentarPermisos() async {
    if (kDebugMode) {
      debugPrint('[IbeaconCoreLocation] reintentarPermisos()');
    }
    try {
      await flutterBeacon.requestAuthorization;
      final tras = await flutterBeacon.authorizationStatus;
      final ok = tras == AuthorizationStatus.allowed ||
          tras == AuthorizationStatus.always ||
          tras == AuthorizationStatus.whenInUse;
      if (ok && !_activo) {
        await iniciarEscaneo();
      }
      return ok;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[IbeaconCoreLocation] reintentarPermisos error: $e');
      }
      return false;
    }
  }

  // ─── Procesamiento de ranging ─────────────────────────────────────────────

  /// Cada vez que iOS reporta una región rangeada, recibimos 0..N
  /// `Beacon`s con su distancia estimada. Los convertimos a
  /// [BeaconReading] y los emitimos por los streams.
  void _onRangingResult(RangingResult result) {
    for (final b in result.beacons) {
      final reading = BeaconReading(
        minor: b.minor,
        major: b.major,
        rssi: b.rssi.toDouble(),
        timestamp: DateTime.now(),
      );
      if (!_beaconController.isClosed) _beaconController.add(reading);

      // Espejo en el stream crudo para que la pantalla de diagnóstico
      // muestre actividad. Acá todo está "aceptado" porque iOS solo
      // entrega beacons que matchean la región (UUID objetivo).
      if (kDebugMode && !_crudoController.isClosed) {
        _crudoController.add(AdvertisementCrudo(
          deviceId: 'ios:${b.major}.${b.minor}',
          rssi: b.rssi.toDouble(),
          formato: FormatoBalizaBle.iBeacon,
          uuid: b.proximityUUID.toLowerCase(),
          major: b.major,
          minor: b.minor,
          aceptado: true,
          timestamp: DateTime.now(),
        ));
      }
    }
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
