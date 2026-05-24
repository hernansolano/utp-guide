import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/beacon_reading.dart';
import 'ble_service.dart' show BleEstado;
import 'ble_source.dart';

/// Implementación de [BleSource] que reenvía a una de dos fuentes
/// internas según el valor de un [ValueNotifier<bool>].
///
/// Permite a `PositioningService` consumir una sola fuente lógica,
/// mientras la UI puede alternar entre BLE real y simulado con un
/// toggle de Settings, sin reiniciar el pipeline de posicionamiento.
///
/// Comportamiento del switch:
/// 1. Al alternar el notifier, se llama `detenerEscaneo()` sobre la
///    fuente que estaba activa.
/// 2. Se re-engancha el listener interno a la nueva fuente.
/// 3. Se llama `iniciarEscaneo()` sobre la nueva fuente.
///
/// Los streams expuestos al consumidor (`beaconStream`, `estadoStream`)
/// son `StreamController`s del multiplexer; los listeners externos no
/// se desuscriben durante el switch — solo cambia de dónde provienen
/// los eventos.
class BleSourceMultiplexer implements BleSource {
  final BleSource _real;
  final BleSource _simulado;
  final ValueNotifier<bool> _modoSimulacionNotifier;

  final _beaconCtrl = StreamController<BeaconReading>.broadcast();
  final _estadoCtrl = StreamController<BleEstado>.broadcast();

  StreamSubscription<BeaconReading>? _beaconSub;
  StreamSubscription<BleEstado>? _estadoSub;
  BleEstado _estadoActual = BleEstado.inactivo;
  bool _activo = false;

  BleSourceMultiplexer(
    this._real,
    this._simulado,
    this._modoSimulacionNotifier,
  );

  /// Fuente actualmente activa según el notifier.
  BleSource get _fuenteActiva =>
      _modoSimulacionNotifier.value ? _simulado : _real;

  @override
  Stream<BeaconReading> get beaconStream => _beaconCtrl.stream;

  @override
  Stream<BleEstado> get estadoStream => _estadoCtrl.stream;

  @override
  BleEstado get estadoActual => _estadoActual;

  @override
  Future<void> iniciarEscaneo() async {
    if (_activo) return;
    _activo = true;

    _modoSimulacionNotifier.addListener(_onCambioModo);
    await _engancharAFuenteActiva();
    await _fuenteActiva.iniciarEscaneo();
  }

  @override
  Future<void> detenerEscaneo() async {
    if (!_activo) return;
    _activo = false;
    _modoSimulacionNotifier.removeListener(_onCambioModo);
    await _fuenteActiva.detenerEscaneo();
    await _beaconSub?.cancel();
    await _estadoSub?.cancel();
    _beaconSub = null;
    _estadoSub = null;
    _setEstado(BleEstado.inactivo);
  }

  /// Cuando el toggle cambia, apagamos la fuente vieja, re-enganchamos
  /// los listeners a la nueva, y la arrancamos. El consumidor externo
  /// (PositioningService) no nota nada — sus suscripciones siguen
  /// vivas, simplemente reciben eventos de otra fuente.
  Future<void> _onCambioModo() async {
    if (!_activo) return;

    // En el momento que se dispara este callback, _fuenteActiva ya
    // devuelve la fuente NUEVA (porque el notifier ya cambió).
    final nueva = _fuenteActiva;
    final vieja = nueva == _real ? _simulado : _real;

    await vieja.detenerEscaneo();
    await _engancharAFuenteActiva();
    await nueva.iniciarEscaneo();
  }

  Future<void> _engancharAFuenteActiva() async {
    await _beaconSub?.cancel();
    await _estadoSub?.cancel();
    _beaconSub = _fuenteActiva.beaconStream.listen((r) {
      if (!_beaconCtrl.isClosed) _beaconCtrl.add(r);
    });
    _estadoSub = _fuenteActiva.estadoStream.listen(_setEstado);
  }

  void _setEstado(BleEstado nuevo) {
    _estadoActual = nuevo;
    if (!_estadoCtrl.isClosed) _estadoCtrl.add(nuevo);
  }

  @override
  void dispose() {
    detenerEscaneo();
    _beaconCtrl.close();
    _estadoCtrl.close();
    _real.dispose();
    _simulado.dispose();
  }
}
