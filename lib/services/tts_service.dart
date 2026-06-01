import 'package:flutter_tts/flutter_tts.dart';

/// Wrapper sobre `flutter_tts` configurado para español.
///
/// El paquete envuelve APIs nativas de TTS (Android `TextToSpeech`,
/// iOS `AVSpeechSynthesizer`). No hace llamadas de red — todo el
/// procesamiento de voz ocurre en el dispositivo. Ver
/// `docs/adr/0009-pinning-dependencias.md` para la auditoría que
/// motivó el pin de versión.
///
/// Uso típico:
/// ```dart
/// final tts = TtsService();
/// await tts.hablar('Gira a la izquierda');
/// // ...
/// tts.dispose();
/// ```
///
/// Las interrupciones se manejan automáticamente: una nueva llamada a
/// `hablar()` cancela cualquier locución previa en curso, evitando que
/// las instrucciones se solapen cuando el usuario pasa rápido entre
/// pasos de navegación.
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _inicializado = false;

  /// True si el motor TTS respondió correctamente en la primera
  /// inicialización. False si lanzó excepción (motor no instalado,
  /// idioma no soportado, etc.). Null antes del primer intento.
  ///
  /// Cuando es false, [hablar] retorna sin lanzar — TTS es un accesorio,
  /// no crítico. La UI puede consultar este getter para ocultar
  /// controles de voz si quiere ser explícita, pero no es obligatorio.
  bool? _disponible;
  bool? get disponible => _disponible;

  /// Idioma BCP-47. `es-ES` se elige sobre `es-419` o `es-MX` porque
  /// es el más universalmente soportado por motores TTS del sistema en
  /// Android e iOS. Si el dispositivo no tiene español instalado, la
  /// locución falla silenciosamente — TtsService no lanza excepción.
  static const _idioma = 'es-ES';

  /// Velocidad de habla. 0.5 (mitad de velocidad normal del motor) suena
  /// natural en español y deja al usuario procesar la indicación mientras
  /// camina. Valores típicos: 0.4-0.6.
  static const _velocidad = 0.5;

  /// Tono. 1.0 es el natural del motor. Subir o bajar suena artificial.
  static const _tono = 1.0;

  /// Volumen relativo dentro del rango del sistema. 1.0 = máximo.
  static const _volumen = 1.0;

  /// Inicializa el motor TTS la primera vez que se necesita. Devuelve
  /// true si todo funcionó, false si el motor no está disponible.
  /// Caches el resultado en [_disponible] para no reintentar.
  Future<bool> _asegurarInicializado() async {
    if (_inicializado) return _disponible ?? false;
    try {
      await _tts.setLanguage(_idioma);
      await _tts.setSpeechRate(_velocidad);
      await _tts.setPitch(_tono);
      await _tts.setVolume(_volumen);
      _inicializado = true;
      _disponible = true;
      return true;
    } catch (_) {
      // Casos típicos: dispositivo sin motor TTS, idioma no soportado,
      // emulador sin Google Play Services. Falla silenciosa — la voz es
      // accesorio, la navegación funciona sin ella.
      _inicializado = true;
      _disponible = false;
      return false;
    }
  }

  /// Lee [texto] en voz alta. Si el motor TTS no está disponible, no
  /// hace nada (sin lanzar). Si ya había una locución en curso, la
  /// interrumpe — útil para navegación donde las instrucciones se
  /// actualizan en tiempo real.
  Future<void> hablar(String texto) async {
    if (texto.trim().isEmpty) return;
    if (!await _asegurarInicializado()) return;
    try {
      await _tts.stop();
      await _tts.speak(texto);
    } catch (_) {
      // Algo cambió en runtime (idioma desinstalado, audio focus perdido).
      // Marcamos como no disponible y dejamos pasar.
      _disponible = false;
    }
  }

  /// Detiene cualquier locución en curso. Útil cuando el usuario sale
  /// de la pantalla de navegación.
  Future<void> detener() async {
    if (_disponible == false) return;
    try {
      await _tts.stop();
    } catch (_) {
      // ignore
    }
  }

  void dispose() {
    _tts.stop();
  }
}
