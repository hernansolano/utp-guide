import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../data/repositories/beacon_repository.dart';
import '../models/advertisement_crudo.dart';
import '../models/beacon_config.dart';
import '../models/beacon_reading.dart';
import '../models/position.dart';
import 'ble_service.dart' show BleEstado;
import 'ble_source.dart';

/// Implementación de [BleSource] que genera lecturas iBeacon sintéticas
/// desde una "posición virtual" del usuario, sin necesidad de hardware.
///
/// Cómo funciona:
///
/// 1. La UI (`MapaScreen` con drag-to-position) actualiza el
///    [posicionVirtualNotifier] cuando el usuario arrastra el dedo.
/// 2. Cada [_intervaloEmisionMs] el servicio recorre todas las balizas
///    registradas en `beacon_config.json` y calcula la distancia
///    euclidiana desde la posición virtual.
/// 3. Convierte cada distancia a RSSI con el inverso del modelo de
///    path-loss: `rssi = txPower - 10·n·log10(d)`.
/// 4. Le agrega ruido gaussiano (σ configurable) para reproducir la
///    variación natural de RSSI en BLE.
/// 5. Emite cada lectura como [BeaconReading] al stream público.
///
/// El pipeline downstream ([PositioningService]) recibe estas lecturas
/// exactamente igual que las reales. Eso permite validar el algoritmo
/// completo (media móvil, trilateración, snap-to-graph) sin un solo
/// beacon físico instalado.
///
/// Ver `docs/adr/0008-simulador-ble-para-testing.md` para el razonamiento.
class SimulatedBleService implements BleSource {
  final BeaconRepository _beaconRepo;
  final ValueNotifier<Position?> _posicionVirtualNotifier;

  /// σ del ruido gaussiano agregado al RSSI sintético, en dBm.
  /// Default 3 dBm reproduce condiciones típicas indoor.
  final double _sigmaRuidoDbm;

  /// Cada cuántos ms se emite un ciclo de lecturas (una por baliza).
  /// 500 ms imita la tasa típica de iBeacon a intervalo estándar.
  static const _intervaloEmisionMs = 500;

  final _beaconCtrl = StreamController<BeaconReading>.broadcast();
  final _estadoCtrl = StreamController<BleEstado>.broadcast();
  final _crudoCtrl = StreamController<AdvertisementCrudo>.broadcast();
  BleEstado _estado = BleEstado.inactivo;

  Timer? _timerEmision;
  List<ConfigBeacon>? _beaconsCache;
  CalibracionPositioning? _calibracion;
  final Random _rng = Random();

  SimulatedBleService(
    this._beaconRepo,
    this._posicionVirtualNotifier, {
    double sigmaRuidoDbm = 3.0,
  }) : _sigmaRuidoDbm = sigmaRuidoDbm;

  @override
  Stream<BeaconReading> get beaconStream => _beaconCtrl.stream;

  @override
  Stream<BleEstado> get estadoStream => _estadoCtrl.stream;

  @override
  Stream<AdvertisementCrudo> get advertisementsCrudosStream => _crudoCtrl.stream;

  @override
  BleEstado get estadoActual => _estado;

  @override
  Future<void> iniciarEscaneo() async {
    if (_timerEmision != null) return;

    // Pre-cargar balizas y calibración una sola vez (no cambian durante runtime).
    final minors = await _beaconRepo.obtenerMinorsRegistrados();
    _beaconsCache = [
      for (final m in minors) await _beaconRepo.obtenerConfigBeacon(m),
    ];
    _calibracion = await _beaconRepo.obtenerCalibracion();

    _timerEmision = Timer.periodic(
      const Duration(milliseconds: _intervaloEmisionMs),
      (_) => _emitirCiclo(),
    );

    _emitir(BleEstado.simulando);
  }

  @override
  Future<void> detenerEscaneo() async {
    _timerEmision?.cancel();
    _timerEmision = null;
    _emitir(BleEstado.inactivo);
  }

  /// En modo simulado no hay permisos del sistema involucrados — el
  /// servicio "siempre acepta". Retorna true.
  @override
  Future<bool> reintentarPermisos() async => true;

  /// El simulador no filtra por UUID — emite lo configurado en
  /// `beacon_config.json` directamente. No-op.
  @override
  void configurarUuidObjetivo(String uuid) {}

  /// Genera y emite una lectura sintética por cada baliza registrada,
  /// basada en la posición virtual actual.
  void _emitirCiclo() {
    final pos = _posicionVirtualNotifier.value;
    final beacons = _beaconsCache;
    final cal = _calibracion;
    if (pos == null || beacons == null || cal == null) return;

    for (final beacon in beacons) {
      final reading = _generarLectura(pos, beacon, cal);
      if (!_beaconCtrl.isClosed) _beaconCtrl.add(reading);
      // Reflejo la lectura como advertisement crudo aceptado para que la
      // pantalla de diagnóstico vea actividad incluso en modo simulación.
      if (kDebugMode && !_crudoCtrl.isClosed) {
        _crudoCtrl.add(AdvertisementCrudo(
          deviceId: 'sim:${beacon.minor}',
          rssi: reading.rssi,
          formato: FormatoBalizaBle.iBeacon,
          uuid: 'simulado',
          major: reading.major,
          minor: reading.minor,
          aceptado: true,
          timestamp: reading.timestamp,
        ));
      }
    }
  }

  BeaconReading _generarLectura(
      Position pos, ConfigBeacon beacon, CalibracionPositioning cal) {
    final dx = pos.x - beacon.x;
    final dy = pos.y - beacon.y;
    // Distancia mínima 10 cm para evitar log(0) cuando el usuario está
    // exactamente sobre la baliza.
    final distancia = max(sqrt(dx * dx + dy * dy), 0.1);

    // Inverso del modelo de path-loss:
    //   rssi = txPower - 10·n·log10(d)
    final txPower = beacon.txPowerDbm ?? cal.txPowerDbmDefault;
    final rssiTeorico =
        txPower - 10.0 * cal.nExponentePerdida * (log(distancia) / ln10);

    // Ruido gaussiano para imitar variación natural del RSSI.
    final ruido = _ruidoGaussiano(_sigmaRuidoDbm);

    return BeaconReading(
      minor: beacon.minor,
      rssi: rssiTeorico + ruido,
      timestamp: DateTime.now(),
    );
  }

  /// Box-Muller: convierte dos uniformes en una muestra gaussiana
  /// estándar (media 0, desviación σ).
  double _ruidoGaussiano(double sigma) {
    final u1 = _rng.nextDouble();
    final u2 = _rng.nextDouble();
    // u1 puede ser 0 en teoría — agregamos epsilon para evitar log(0).
    final z = sqrt(-2.0 * log(u1 + 1e-12)) * cos(2.0 * pi * u2);
    return sigma * z;
  }

  void _emitir(BleEstado nuevo) {
    _estado = nuevo;
    if (!_estadoCtrl.isClosed) _estadoCtrl.add(nuevo);
  }

  @override
  void dispose() {
    detenerEscaneo();
    _beaconCtrl.close();
    _estadoCtrl.close();
    _crudoCtrl.close();
  }
}
