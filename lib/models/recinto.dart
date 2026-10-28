import 'dart:ui' show Offset, Rect;
import 'tipo_nodo.dart';

/// Tipo de recinto del plano oficial (salón, oficina, baño…).
///
/// Es distinto de [TipoNodo]: un recinto es un **área** del plano (lo que
/// se pinta y se toca), mientras que un nodo es un punto del grafo de
/// navegación. Los tipos sin equivalente navegable (cuartos técnicos,
/// balcón) devuelven `null` en [tipoNodo].
enum TipoRecinto {
  salon,
  oficina,
  bano,
  escalera,
  ascensor,
  servicio,
  balcon;

  static TipoRecinto fromJson(String value) {
    switch (value.toUpperCase()) {
      case 'SALON':
        return TipoRecinto.salon;
      case 'OFICINA':
        return TipoRecinto.oficina;
      case 'BANO':
        return TipoRecinto.bano;
      case 'ESCALERA':
        return TipoRecinto.escalera;
      case 'ASCENSOR':
        return TipoRecinto.ascensor;
      case 'SERVICIO':
        return TipoRecinto.servicio;
      case 'BALCON':
        return TipoRecinto.balcon;
      default:
        throw ArgumentError('TipoRecinto desconocido: $value');
    }
  }

  /// Tipo de nodo equivalente, para reutilizar colores e íconos de los POIs.
  TipoNodo? get tipoNodo {
    switch (this) {
      case TipoRecinto.salon:
        return TipoNodo.salon;
      case TipoRecinto.oficina:
        return TipoNodo.oficina;
      case TipoRecinto.bano:
        return TipoNodo.bano;
      case TipoRecinto.escalera:
        return TipoNodo.escalera;
      case TipoRecinto.ascensor:
        return TipoNodo.ascensor;
      case TipoRecinto.servicio:
      case TipoRecinto.balcon:
        return null;
    }
  }

  /// Si el público puede ir ahí. Los cuartos técnicos no se ofrecen como
  /// destino aunque se dibujen.
  bool get esPublico => this != TipoRecinto.servicio;
}

/// Área cerrada del plano oficial (salón, oficina, baño…), en metros del
/// sistema de coordenadas del grafo (origen arriba a la izquierda).
///
/// Viene de `assets/data/recintos/*.json`, generado por
/// `tools/plano_oficial/extraer_plano.py` a partir del PDF oficial.
class Recinto {
  /// Id estable dentro del plano (`r36`), derivado del número del cuadro de
  /// áreas oficial.
  final String id;

  /// Código de salón `E-P-NN` (`3-405`) si el plano lo tiene.
  final String? codigo;

  /// Nombre legible para la UI.
  final String nombre;

  /// Nombre tal como aparece en el cuadro de áreas oficial.
  final String nombreOficial;

  final TipoRecinto tipo;

  /// Texto corto para dibujar dentro del recinto (código o tipo). Null =
  /// sin etiqueta (cuartos técnicos).
  final String? etiquetaCorta;

  /// Área según el cuadro oficial, en m².
  final double? areaM2;

  /// Punto donde va la etiqueta (donde está el número en el plano oficial).
  final Offset etiqueta;

  /// Contorno en metros. Vacío si el extractor no obtuvo un polígono
  /// confiable (escaleras, ascensor): se muestra la etiqueta pero no se
  /// puede tocar.
  final List<Offset> poligono;

  /// Nodo del grafo que lleva a este recinto (normalmente su puerta). Null
  /// mientras el grafo no lo enlace: el recinto se ve y se toca, pero no se
  /// puede navegar hacia él.
  final String? nodoId;

  /// Caja envolvente del polígono, precalculada para descartar rápido en
  /// [contiene].
  final Rect limites;

  Recinto({
    required this.id,
    required this.nombre,
    required this.nombreOficial,
    required this.tipo,
    required this.etiqueta,
    required this.poligono,
    this.codigo,
    this.etiquetaCorta,
    this.areaM2,
    this.nodoId,
  }) : limites = _limitesDe(poligono);

  factory Recinto.fromJson(Map<String, dynamic> json) {
    final etq = json['etiqueta'] as List<dynamic>;
    return Recinto(
      id: json['id'] as String,
      codigo: json['codigo'] as String?,
      nombre: json['nombre'] as String,
      nombreOficial:
          json['nombre_oficial'] as String? ?? json['nombre'] as String,
      tipo: TipoRecinto.fromJson(json['tipo'] as String),
      etiquetaCorta: json['etiqueta_corta'] as String?,
      areaM2: (json['area_m2'] as num?)?.toDouble(),
      etiqueta: Offset((etq[0] as num).toDouble(), (etq[1] as num).toDouble()),
      poligono: parsearPoligono(json['poligono'] as List<dynamic>? ?? const []),
      nodoId: json['nodo_id'] as String?,
    );
  }

  /// Si el recinto se puede tocar (tiene contorno).
  bool get tienePoligono => poligono.length >= 3;

  /// Punto en polígono por ray casting (regla par-impar).
  bool contiene(Offset p) {
    if (!tienePoligono || !limites.contains(p)) return false;
    var dentro = false;
    for (var i = 0, j = poligono.length - 1; i < poligono.length; j = i++) {
      final a = poligono[i];
      final b = poligono[j];
      final cruza =
          (a.dy > p.dy) != (b.dy > p.dy) &&
          p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx;
      if (cruza) dentro = !dentro;
    }
    return dentro;
  }

  static Rect _limitesDe(List<Offset> pts) {
    if (pts.isEmpty) return Rect.zero;
    var minX = pts.first.dx, maxX = pts.first.dx;
    var minY = pts.first.dy, maxY = pts.first.dy;
    for (final p in pts) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// `[[x, y], …]` en metros → lista de [Offset].
  static List<Offset> parsearPoligono(List<dynamic> json) => [
    for (final p in json)
      Offset(
        ((p as List<dynamic>)[0] as num).toDouble(),
        (p[1] as num).toDouble(),
      ),
  ];
}

/// Plano de recintos de un piso: los recintos (áreas que se pintan y se
/// tocan) y las áreas de circulación (pasillos y vestíbulos).
class PlanoRecintos {
  final List<Recinto> recintos;
  final List<List<Offset>> circulacion;

  const PlanoRecintos({required this.recintos, required this.circulacion});

  /// Plano vacío: el piso no tiene recintos declarados (entornos de
  /// experimento). El mapa se dibuja solo con el SVG, como antes.
  static const vacio = PlanoRecintos(recintos: [], circulacion: []);

  bool get estaVacio => recintos.isEmpty && circulacion.isEmpty;

  /// Recinto que contiene el punto [p] (metros), o null si cae en un
  /// pasillo o fuera del edificio.
  Recinto? recintoEn(Offset p) {
    for (final r in recintos) {
      if (r.contiene(p)) return r;
    }
    return null;
  }

  /// Recinto enlazado a un nodo del grafo, o null si ninguno lo está.
  Recinto? recintoDeNodo(String nodoId) {
    for (final r in recintos) {
      if (r.nodoId == nodoId) return r;
    }
    return null;
  }
}
