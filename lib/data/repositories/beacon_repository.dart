import 'dart:convert';
import 'package:flutter/services.dart';
import '../../models/beacon_config.dart';
import '../../models/position.dart';
import '../exceptions.dart';

/// Carga y expone la configuración de balizas BLE y los parámetros
/// globales de calibración del sistema de posicionamiento.
///
/// La fuente de verdad es `assets/data/beacon_config.json`. El
/// repositorio cachea el contenido tras la primera lectura — no recarga
/// el archivo durante la ejecución. Para aplicar cambios al JSON, hay
/// que reiniciar la app.
///
/// Modelo de datos esperado en el JSON:
/// ```json
/// {
///   "uuid": "550e8400-...",
///   "major": 1,
///   "calibracion": {
///     "txPower_dbm_default": -65,
///     "n_exponente_perdida": 3.5,
///     "ventana_media_movil": 8,
///     "tolerancia_snap_metros": 3.0,
///     "expiracion_lectura_segundos": 3
///   },
///   "beacons": [
///     {"minor": 1, "x": 0.5, "y": 0.5, "txPower_dbm": -65, "descripcion": "..."}
///   ]
/// }
/// ```
///
/// Si el bloque `calibracion` está ausente, se usan valores por defecto
/// definidos en [CalibracionPositioning.defaults]. Ver
/// `docs/adr/0002-parametros-path-loss.md`.
class BeaconRepository {
  Map<String, dynamic>? _cachedData;
  List<ConfigBeacon>? _cachedBeacons;
  CalibracionPositioning? _cachedCalibracion;

  Future<Map<String, dynamic>> _load() async {
    if (_cachedData != null) return _cachedData!;
    try {
      final raw =
          await rootBundle.loadString('assets/data/beacon_config.json');
      _cachedData = jsonDecode(raw) as Map<String, dynamic>;
      return _cachedData!;
    } catch (e) {
      throw Exception('Error al parsear beacon_config.json: $e');
    }
  }

  /// Devuelve la configuración completa de una baliza por su `minor`.
  ///
  /// Lanza [BeaconNotFoundException] si no existe en el archivo.
  Future<ConfigBeacon> obtenerConfigBeacon(int minor) async {
    final beacons = await obtenerTodosLosBeacons();
    final match = beacons.where((b) => b.minor == minor).firstOrNull;
    if (match == null) throw BeaconNotFoundException(minor);
    return match;
  }

  /// Devuelve solo la posición de la baliza (atajo legacy).
  ///
  /// Internamente delega a [obtenerConfigBeacon]. Se mantiene por
  /// compatibilidad con código que solo necesita la posición.
  Future<Position> obtenerPosicion(int minor) async {
    final config = await obtenerConfigBeacon(minor);
    final data = await _load();
    return Position(
      x: config.x,
      y: config.y,
      piso: data['major'] as int,
      timestamp: DateTime.now(),
    );
  }

  /// Devuelve el `txPower_dbm` calibrado para esta baliza, o el global
  /// si la baliza no tiene su propio valor.
  ///
  /// Lanza [BeaconNotFoundException] si el `minor` no existe.
  Future<double> obtenerTxPower(int minor) async {
    final config = await obtenerConfigBeacon(minor);
    if (config.txPowerDbm != null) return config.txPowerDbm!;
    final calibracion = await obtenerCalibracion();
    return calibracion.txPowerDbmDefault;
  }

  /// Devuelve los parámetros globales de calibración.
  ///
  /// Si el archivo no incluye el bloque `calibracion`, devuelve
  /// [CalibracionPositioning.defaults] silenciosamente (sin warning).
  Future<CalibracionPositioning> obtenerCalibracion() async {
    if (_cachedCalibracion != null) return _cachedCalibracion!;
    final data = await _load();
    final calibracionJson = data['calibracion'] as Map<String, dynamic>?;
    _cachedCalibracion = calibracionJson != null
        ? CalibracionPositioning.fromJson(calibracionJson)
        : CalibracionPositioning.defaults;
    return _cachedCalibracion!;
  }

  /// Lista de `minor` de todas las balizas registradas.
  ///
  /// Útil para validar en logs que las balizas detectadas estén en el
  /// catálogo, y para herramientas de debugging.
  Future<List<int>> obtenerMinorsRegistrados() async {
    final beacons = await obtenerTodosLosBeacons();
    return beacons.map((b) => b.minor).toList();
  }

  /// UUID del proyecto, leído del campo `uuid` de `beacon_config.json`.
  ///
  /// Es el UUID que el `BleService` filtra al escanear advertisements
  /// iBeacon. Si la persona que instala balizas quiere usar otro UUID,
  /// basta con cambiarlo aquí — no requiere recompilar.
  Future<String> obtenerUuid() async {
    final data = await _load();
    return data['uuid'] as String;
  }

  /// `major` iBeacon del proyecto (en el piloto = piso), leído del campo
  /// `major` de `beacon_config.json`. Necesario para reconstruir el
  /// archivo completo desde la pantalla de calibración.
  Future<int> obtenerMajor() async {
    final data = await _load();
    return data['major'] as int;
  }

  /// Lista completa de balizas registradas (con x/y/txPower/descripcion).
  ///
  /// Lee del cache ya cargado. La usa la pantalla de calibración para
  /// generar el `beacon_config.json` completo listo para pegar.
  Future<List<ConfigBeacon>> obtenerTodosLosBeacons() async {
    if (_cachedBeacons != null) return _cachedBeacons!;
    final data = await _load();
    final list = data['beacons'] as List<dynamic>;
    _cachedBeacons = list
        .map((j) => ConfigBeacon.fromJson(j as Map<String, dynamic>))
        .toList();
    return _cachedBeacons!;
  }
}
