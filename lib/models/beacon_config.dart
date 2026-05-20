/// Configuración de una baliza BLE individual y de los parámetros
/// globales de calibración del sistema de posicionamiento.
///
/// Ambos modelos se cargan desde `assets/data/beacon_config.json` y son
/// inmutables después de la carga. Para modificarlos, editar el archivo
/// JSON y reiniciar la app (no requiere recompilar).
///
/// Ver `docs/positioning-ble.md` para el contexto físico y
/// `docs/adr/0002-parametros-path-loss.md` para la justificación de los
/// valores por defecto.
library;

/// Configuración de una baliza física individual.
///
/// El campo [txPowerDbm] sobreescribe el `txPower_dbm_default` global
/// para esta baliza específica. Esto permite calibrar cada baliza por
/// separado, lo que es necesario porque dos balizas del mismo modelo y
/// configuración pueden tener un RSSI a 1 m que varía ±3 dBm debido a
/// tolerancia de fabricación y orientación.
class ConfigBeacon {
  /// Identificador iBeacon Minor (16 bits). Único dentro del UUID/Major.
  final int minor;

  /// Posición física de la baliza en metros, sistema de coordenadas del
  /// grafo (origen en esquina superior izquierda).
  final double x;
  final double y;

  /// RSSI medido a exactamente 1 metro de la baliza.
  ///
  /// Si es `null`, se usa el `txPowerDbmDefault` de [CalibracionPositioning].
  /// El valor debe ser negativo (típicamente entre -45 y -80).
  final double? txPowerDbm;

  /// Texto humano para identificar la baliza en logs y herramientas de
  /// debugging. No se muestra al usuario final.
  final String descripcion;

  const ConfigBeacon({
    required this.minor,
    required this.x,
    required this.y,
    required this.descripcion,
    this.txPowerDbm,
  });

  factory ConfigBeacon.fromJson(Map<String, dynamic> json) {
    return ConfigBeacon(
      minor: json['minor'] as int,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      // El campo es opcional — si no está, queda en null y se usa el global.
      txPowerDbm: (json['txPower_dbm'] as num?)?.toDouble(),
      descripcion: json['descripcion'] as String? ?? '',
    );
  }
}

/// Parámetros globales del modelo de path-loss y filtros del
/// `PositioningService`.
///
/// Los valores por defecto corresponden a un entorno interior con muros
/// de concreto (caso FISC). Para otros edificios, recalibrar siguiendo
/// el procedimiento en `docs/setup-beacons.md`.
class CalibracionPositioning {
  /// RSSI medido a 1 m, usado cuando una baliza no tiene su propio
  /// `txPowerDbm`. Valor típico: -65 dBm para Minew E2 Max a -12 dBm
  /// de potencia de transmisión.
  final double txPowerDbmDefault;

  /// Exponente del modelo de path-loss log-normal. Determina la tasa
  /// de decaimiento de la señal con la distancia.
  ///
  /// Rangos típicos:
  /// - 2.0    espacio libre
  /// - 2.5-3.0 oficinas con paredes ligeras
  /// - 3.0-4.0 edificios con muros de concreto (este es el caso FISC)
  /// - 4.0+   propagación a través de muros densos
  final double nExponentePerdida;

  /// Cantidad de lecturas RSSI que se promedian por baliza antes de
  /// usarlas en la trilateración.
  ///
  /// Más lecturas = más suavizado pero más lag. Default: 8.
  final int ventanaMediaMovil;

  /// Distancia máxima (en metros) a una arista del grafo para considerar
  /// válido el snap-to-graph. Más allá de este umbral, se reporta la
  /// posición cruda sin proyectar.
  final double toleranciaSnapMetros;

  /// Segundos que una baliza puede no ser detectada antes de
  /// considerarse fuera de rango y excluirse de la trilateración.
  ///
  /// Beacon Simulator emite cada 500 ms; 3 s = 6 anuncios consecutivos
  /// perdidos antes de descartar.
  final int expiracionLecturaSegundos;

  const CalibracionPositioning({
    required this.txPowerDbmDefault,
    required this.nExponentePerdida,
    required this.ventanaMediaMovil,
    required this.toleranciaSnapMetros,
    required this.expiracionLecturaSegundos,
  });

  /// Valores por defecto para edificio FISC (muros de concreto).
  ///
  /// Se usan cuando `beacon_config.json` no incluye el bloque
  /// `calibracion`. Ver `docs/adr/0002-parametros-path-loss.md`.
  static const defaults = CalibracionPositioning(
    txPowerDbmDefault: -65.0,
    nExponentePerdida: 3.5,
    ventanaMediaMovil: 8,
    toleranciaSnapMetros: 3.0,
    expiracionLecturaSegundos: 3,
  );

  /// Parsea desde JSON aplicando defaults si faltan campos.
  ///
  /// Aplica defaults silenciosamente (sin lanzar excepción) para que el
  /// archivo pueda evolucionar agregando campos sin romper apps viejas.
  factory CalibracionPositioning.fromJson(Map<String, dynamic> json) {
    return CalibracionPositioning(
      txPowerDbmDefault: (json['txPower_dbm_default'] as num?)?.toDouble() ??
          defaults.txPowerDbmDefault,
      nExponentePerdida: (json['n_exponente_perdida'] as num?)?.toDouble() ??
          defaults.nExponentePerdida,
      ventanaMediaMovil:
          json['ventana_media_movil'] as int? ?? defaults.ventanaMediaMovil,
      toleranciaSnapMetros:
          (json['tolerancia_snap_metros'] as num?)?.toDouble() ??
              defaults.toleranciaSnapMetros,
      expiracionLecturaSegundos: json['expiracion_lectura_segundos'] as int? ??
          defaults.expiracionLecturaSegundos,
    );
  }
}
