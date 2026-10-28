import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/recinto.dart';
import '../theme/app_theme.dart';
import 'mapa_painter.dart';

/// Colores del plano de recintos, resueltos desde el tema (claro/oscuro).
class ColoresRecintos {
  final Color circulacion;
  final Color servicio;
  final Color balcon;
  final Color resaltado;
  final Color texto;
  final Color textoSuave;
  final Color muros;
  final Map<TipoRecinto, Color> porTipo;

  const ColoresRecintos({
    required this.circulacion,
    required this.servicio,
    required this.balcon,
    required this.resaltado,
    required this.texto,
    required this.textoSuave,
    required this.muros,
    required this.porTipo,
  });

  factory ColoresRecintos.of(BuildContext context) {
    final c = context.colors;
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    // Tinte suave del color del POI sobre la superficie: se distingue el
    // tipo de recinto sin competir con la ruta ni con el punto azul.
    Color tinte(TipoRecinto t) {
      final base = t.tipoNodo == null
          ? c.bgMuted
          : MapaPainter.colorParaTipo(t.tipoNodo!);
      return Color.alphaBlend(
        base.withValues(alpha: oscuro ? 0.24 : 0.13),
        c.surface,
      );
    }

    return ColoresRecintos(
      circulacion: c.corridorFill,
      servicio: c.bgMuted,
      balcon: c.successBg,
      resaltado: c.brand,
      texto: c.fg,
      textoSuave: c.fgMuted,
      muros: c.fgMuted,
      porTipo: {for (final t in TipoRecinto.values) t: tinte(t)},
    );
  }

  Color rellenoDe(TipoRecinto t) => switch (t) {
    TipoRecinto.servicio => servicio,
    TipoRecinto.balcon => balcon,
    _ => porTipo[t]!,
  };

  @override
  bool operator ==(Object other) =>
      other is ColoresRecintos &&
      other.circulacion == circulacion &&
      other.resaltado == resaltado &&
      other.texto == texto &&
      other.muros == muros &&
      other.porTipo[TipoRecinto.salon] == porTipo[TipoRecinto.salon];

  @override
  int get hashCode => Object.hash(circulacion, resaltado, texto, muros);
}

/// Capa de FONDO del plano: pasillos y recintos rellenos por tipo. Va
/// debajo del SVG (que solo trae muros y detalle), así los muros quedan
/// siempre encima de los rellenos.
class RecintosFondoPainter extends CustomPainter {
  final PlanoRecintos plano;
  final Size mapaSize;
  final ColoresRecintos colores;
  final String? resaltadoId;

  RecintosFondoPainter({
    required this.plano,
    required this.mapaSize,
    required this.colores,
    this.resaltadoId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (plano.estaVacio) return;
    canvas.save();
    canvas.scale(size.width / mapaSize.width, size.height / mapaSize.height);

    final paint = Paint()..style = PaintingStyle.fill;
    paint.color = colores.circulacion;
    for (final poli in plano.circulacion) {
      canvas.drawPath(_path(poli), paint);
    }
    for (final r in plano.recintos) {
      if (!r.tienePoligono) continue;
      paint.color = r.id == resaltadoId
          ? Color.alphaBlend(
              colores.resaltado.withValues(alpha: 0.22),
              colores.rellenoDe(r.tipo),
            )
          : colores.rellenoDe(r.tipo);
      canvas.drawPath(_path(r.poligono), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(RecintosFondoPainter old) =>
      old.plano != plano ||
      old.mapaSize != mapaSize ||
      old.colores != colores ||
      old.resaltadoId != resaltadoId;
}

/// Capa de ETIQUETAS y contorno del recinto resaltado. Va encima del SVG.
///
/// Las etiquetas tienen **tamaño constante en pantalla** (se contra-escalan
/// con el zoom de la cámara) y solo se dibujan si caben dentro de su
/// recinto: al alejarse quedan solo las de los salones grandes; al acercarse
/// aparecen todas y, con espacio, el nombre completo debajo del código.
/// Escucha [zoom] directamente para repintarse durante el pinch sin
/// reconstruir el árbol de widgets.
class RecintosEtiquetasPainter extends CustomPainter {
  final PlanoRecintos plano;
  final Size mapaSize;
  final ColoresRecintos colores;
  final String? resaltadoId;
  final ValueListenable<double> zoom;
  final EtiquetasRecintosCache cache;

  RecintosEtiquetasPainter({
    required this.plano,
    required this.mapaSize,
    required this.colores,
    required this.zoom,
    required this.cache,
    this.resaltadoId,
  }) : super(repaint: zoom);

  /// Zoom de pantalla (px por metro) a partir del cual se muestran las
  /// etiquetas de recintos sin polígono (escaleras, ascensor).
  static const double _pxPorMetroEtiquetaSuelta = 14;

  @override
  void paint(Canvas canvas, Size size) {
    if (plano.estaVacio) return;
    final z = zoom.value;
    final pxPorM = size.width / mapaSize.width;
    final pxPorMPantalla = pxPorM * z;
    Offset aBox(Offset m) =>
        Offset(m.dx * pxPorM, m.dy * size.height / mapaSize.height);

    // Contorno del resaltado, con grosor constante en pantalla.
    final res = resaltadoId == null ? null : _buscar(resaltadoId!);
    if (res != null && res.tienePoligono) {
      final path = Path()
        ..addPolygon([for (final p in res.poligono) aBox(p)], true);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 / z
          ..color = colores.resaltado,
      );
    }

    for (final r in plano.recintos) {
      final et = cache.de(r, colores);
      if (et == null) continue;
      final destacado = r.id == resaltadoId;
      final double anchoPantalla;
      final double altoPantalla;
      if (r.tienePoligono) {
        anchoPantalla = r.limites.width * pxPorMPantalla * 0.9;
        altoPantalla = r.limites.height * pxPorMPantalla * 0.8;
      } else {
        // Sin polígono no se sabe cuánto espacio hay: solo se rotulan las
        // escaleras y el ascensor (sirven para orientarse) y con zoom.
        if (r.tipo != TipoRecinto.escalera && r.tipo != TipoRecinto.ascensor) {
          continue;
        }
        if (pxPorMPantalla < _pxPorMetroEtiquetaSuelta) continue;
        anchoPantalla = double.infinity;
        altoPantalla = double.infinity;
      }
      final principal = destacado ? et.principalDestacada : et.principal;
      if (!destacado &&
          (principal.width > anchoPantalla ||
              principal.height > altoPantalla)) {
        continue;
      }
      final secundaria = et.secundaria;
      final conNombre =
          secundaria != null &&
          secundaria.width <= anchoPantalla &&
          principal.height + secundaria.height + 2 <= altoPantalla;

      final alto = principal.height + (conNombre ? secundaria.height + 2 : 0);
      final centro = aBox(r.etiqueta);
      canvas.save();
      canvas.translate(centro.dx, centro.dy);
      canvas.scale(1 / z);
      principal.paint(canvas, Offset(-principal.width / 2, -alto / 2));
      if (conNombre) {
        secundaria.paint(
          canvas,
          Offset(-secundaria.width / 2, -alto / 2 + principal.height + 2),
        );
      }
      canvas.restore();
    }
  }

  Recinto? _buscar(String id) {
    for (final r in plano.recintos) {
      if (r.id == id) return r;
    }
    return null;
  }

  @override
  bool shouldRepaint(RecintosEtiquetasPainter old) =>
      old.plano != plano ||
      old.mapaSize != mapaSize ||
      old.colores != colores ||
      old.resaltadoId != resaltadoId ||
      old.zoom != zoom;
}

/// Textos ya maquetados de cada recinto. Maquetar ~70 textos en cada frame
/// del pinch (o en cada lectura BLE, que reconstruye el mapa) es caro; el
/// [MapView] guarda una instancia y solo la invalida al cambiar el tema.
class EtiquetasRecintosCache {
  final Map<Recinto, EtiquetaRecinto?> _porRecinto = {};
  ColoresRecintos? _colores;

  EtiquetaRecinto? de(Recinto r, ColoresRecintos colores) {
    if (_colores != colores) {
      _porRecinto.clear();
      _colores = colores;
    }
    return _porRecinto.putIfAbsent(r, () => _maquetar(r, colores));
  }

  /// Libera los textos (p. ej. al desmontar el mapa).
  void limpiar() => _porRecinto.clear();

  static EtiquetaRecinto? _maquetar(Recinto r, ColoresRecintos c) {
    final texto = r.etiquetaCorta;
    if (texto == null) return null;
    TextPainter tp(
      String s,
      double tam,
      FontWeight peso,
      Color color, {
      double? ancho,
      int lineas = 1,
    }) => TextPainter(
      text: TextSpan(
        text: s,
        style: GoogleFonts.plusJakartaSans(
          fontSize: tam,
          fontWeight: peso,
          color: color,
          height: 1.1,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: lineas,
      ellipsis: '…',
    )..layout(maxWidth: ancho ?? double.infinity);

    final nombreDistinto = r.nombre != texto && r.tipo != TipoRecinto.bano;
    return EtiquetaRecinto(
      principal: tp(texto, 11, FontWeight.w700, c.texto),
      principalDestacada: tp(texto, 13, FontWeight.w800, c.resaltado),
      secundaria: nombreDistinto
          ? tp(
              r.nombre,
              9.5,
              FontWeight.w500,
              c.textoSuave,
              ancho: 120,
              lineas: 2,
            )
          : null,
    );
  }
}

/// Textos maquetados de un recinto: la etiqueta corta (normal y resaltada) y
/// el nombre completo, que solo se muestra si cabe.
class EtiquetaRecinto {
  final TextPainter principal;
  final TextPainter principalDestacada;
  final TextPainter? secundaria;
  const EtiquetaRecinto({
    required this.principal,
    required this.principalDestacada,
    this.secundaria,
  });
}

Path _path(List<Offset> pts) => Path()..addPolygon(pts, true);
