import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utp_guide/data/repositories/beacon_repository.dart';
import 'package:utp_guide/data/repositories/grafo_repository.dart';
import 'package:utp_guide/models/advertisement_crudo.dart';
import 'package:utp_guide/models/beacon_config.dart';
import 'package:utp_guide/models/beacon_reading.dart';
import 'package:utp_guide/models/position.dart';
import 'package:utp_guide/services/ble_service.dart' show BleEstado;
import 'package:utp_guide/services/ble_source.dart';
import 'package:utp_guide/services/positioning_service.dart';

import '../helpers/bundle_fijo.dart';

/// BleSource manual: el test empuja lecturas con [emitir].
class _BleFalso implements BleSource {
  final _lecturas = StreamController<BeaconReading>.broadcast();

  void emitir(int major, int minor, double rssi) => _lecturas.add(
      BeaconReading(
          major: major, minor: minor, rssi: rssi, timestamp: DateTime.now()));

  @override
  Stream<BeaconReading> get beaconStream => _lecturas.stream;
  @override
  Stream<BleEstado> get estadoStream => const Stream.empty();
  @override
  Stream<AdvertisementCrudo> get advertisementsCrudosStream =>
      const Stream.empty();
  @override
  BleEstado get estadoActual => BleEstado.escaneando;
  @override
  void configurarUuidObjetivo(String uuid) {}
  @override
  Future<void> iniciarEscaneo() async {}
  @override
  Future<bool> reintentarPermisos() async => true;
  @override
  Future<void> detenerEscaneo() async {}
  @override
  void dispose() => _lecturas.close();
}

void main() {
  late _BleFalso ble;
  late PositioningService servicio;
  late List<Position?> posiciones;
  late StreamSubscription<Position?> sub;

  setUp(() async {
    ble = _BleFalso();
    final bundle = BundleFijo.json(
      grafo: grafoDePrueba(),
      beaconConfig: {
        'uuid': '550e8400-e29b-41d4-a716-446655440000',
        'major': 4,
        'beacons': [
          {'minor': 1, 'x': 10.0, 'y': 0.0, 'descripcion': 'b1'},
          {'minor': 2, 'x': 20.0, 'y': 0.0, 'descripcion': 'b2'},
        ],
      },
    );
    servicio = PositioningService(
      ble,
      BeaconRepository(bundle: bundle),
      GrafoRepository(bundle: bundle),
      ValueNotifier(CalibracionPositioning.defaults),
      // Sin snap ni suavizado: la posición sale tal cual del centroide.
      snapHabilitadoListenable: ValueNotifier(false),
    );
    posiciones = [];
    sub = servicio.posicionStream.listen(posiciones.add);
    await servicio.iniciar();
  });

  tearDown(() async {
    await sub.cancel();
    servicio.dispose();
    ble.dispose();
  });

  Future<void> vaciarCola() => Future<void>.delayed(Duration.zero);

  test('una baliza del piso posiciona sobre ella, con el piso del grafo',
      () async {
    ble.emitir(4, 1, -70);
    await vaciarCola();
    expect(posiciones, hasLength(1));
    expect(posiciones.single!.x, closeTo(10, 1e-9));
    expect(posiciones.single!.y, closeTo(0, 1e-9));
    expect(posiciones.single!.piso, 4);
  });

  test('descarta lecturas de otro major aunque el minor coincida', () async {
    ble.emitir(99, 1, -60); // aula de pruebas
    ble.emitir(3, 2, -60); // otro piso
    await vaciarCola();
    expect(posiciones, isEmpty);
    expect(servicio.beaconsActivos, 0);
  });

  test('descarta minors que no están en beacon_config', () async {
    ble.emitir(4, 7, -60);
    await vaciarCola();
    expect(posiciones, isEmpty);
    expect(servicio.beaconsActivos, 0);
  });

  test('descarta RSSI imposibles (medición fallida de iOS)', () async {
    ble.emitir(4, 1, 0);
    await vaciarCola();
    expect(posiciones, isEmpty);
  });

  test('con dos balizas iguales el centroide cae al medio', () async {
    ble.emitir(4, 1, -70);
    ble.emitir(4, 2, -70);
    await vaciarCola();
    expect(servicio.beaconsActivos, 2);
    expect(posiciones.last!.x, closeTo(15, 1e-9));
  });
}
