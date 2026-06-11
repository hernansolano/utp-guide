import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/position.dart';
import 'positioning_service.dart';

/// Acumula las posiciones emitidas por [PositioningService] mientras
/// [activaNotifier] esté en `true`. La lista se expone como
/// `ValueListenable` para que el painter del mapa la consuma sin tener
/// que escuchar el stream completo.
///
/// **Cap de memoria:** mantiene un máximo de [_maxPuntos] entradas
/// (~500 ≈ 4-8 min de captura a 1-2 Hz). Cuando se llena, descarta el
/// más antiguo. Suficiente para una sesión de calibración real sin
/// preocuparse por OOM.
///
/// **Uso típico:** activar desde un botón en el debug overlay,
/// caminar el trayecto que quieres evaluar, desactivar, mirar la
/// polilínea sobre el mapa. "Limpiar" resetea la captura.
class TrazaService {
  static const int _maxPuntos = 500;

  final PositioningService _positioning;
  final ValueListenable<bool> _activaNotifier;

  /// Lista observable de puntos capturados. El painter del mapa la
  /// escucha — cada vez que llega una posición nueva, repinta.
  final ValueNotifier<List<Position>> puntos = ValueNotifier(const []);

  StreamSubscription<Position?>? _sub;

  TrazaService(this._positioning, this._activaNotifier) {
    _activaNotifier.addListener(_onCambioActiva);
    if (_activaNotifier.value) _suscribir();
  }

  void _onCambioActiva() {
    if (_activaNotifier.value) {
      _suscribir();
    } else {
      _desuscribir();
    }
  }

  void _suscribir() {
    if (_sub != null) return;
    _sub = _positioning.posicionStream.listen((pos) {
      if (pos == null) return;
      // Lista inmutable nueva para que ValueNotifier dispare listeners
      // (mutar in-place no notifica).
      final lista = [...puntos.value, pos];
      while (lista.length > _maxPuntos) {
        lista.removeAt(0);
      }
      puntos.value = lista;
    });
  }

  void _desuscribir() {
    _sub?.cancel();
    _sub = null;
  }

  /// Vacía la captura sin tocar el flag de activa. Útil para empezar
  /// una nueva medición sin desactivar primero.
  void limpiar() {
    puntos.value = const [];
  }

  /// Cantidad de puntos capturados — útil para mostrar contador en UI.
  int get cantidad => puntos.value.length;

  void dispose() {
    _activaNotifier.removeListener(_onCambioActiva);
    _sub?.cancel();
    puntos.dispose();
  }
}
