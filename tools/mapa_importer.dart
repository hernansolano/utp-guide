// Este archivo es un script CLI: `print` es la forma legítima de
// comunicarse con el usuario. Suprimimos el lint avoid_print solo
// en este archivo, no en el resto del proyecto.
// ignore_for_file: avoid_print

/// MapaImporter — convierte un escaneo de Polycam (DXF) en un SVG limpio
/// del piso (muros + puertas), listo para usar como base del mapa.
///
/// Ejecutar desde la raíz del proyecto:
/// ```bash
/// dart tools/mapa_importer.dart parse "samples/<archivo>.dxf"
/// dart tools/mapa_importer.dart build "samples/borrador_mapa.json"
/// ```
///
/// Solo Dart stdlib (sin Flutter), igual que `grafo_editor.dart` (ADR-0005).
///
/// ── Alcance (a propósito, acotado) ──────────────────────────────────────
///
/// El importador SOLO produce la geometría del piso: muros y puertas. NO
/// inventa balizas ni nodos de navegación — esos los coloca una persona
/// (en el editor o a mano), porque dependen de criterio (cobertura, altura,
/// destinos reales), no de una heurística automática.
///
///   DXF  →  parse  →  borrador_mapa.json  (muros, puertas, cuartos, dims)
///        →  build  →  mapa.svg            (muros rellenos + huecos)
///
/// El borrador es editable entre ambos pasos: sirve para marcar qué cuartos
/// incluir (Polycam etiqueta "ignore" los que no querés) y, a futuro,
/// corregir medidas desde un editor visual.
///
/// ── Formato DXF de Polycam (verificado con el sample 6_10_2026) ──────────
///
/// DXF R2000 ASCII, metros, convención CAD (Y arriba, origen arbitrario).
/// Cada elemento es un polígono cerrado (LWPOLYLINE) en su capa:
///   Poly-Walls      → contorno de cada muro (se RELLENA, no se traza)
///   Poly-Doors      → hueco de puerta (rectángulo fino en el muro)
///   Poly-Windows    → ventanas
///   Poly-Rooms      → polígono de cada cuarto
///   Poly-RoomLabels → nombres (MTEXT: "mapped", "ignore", ...)
///
/// Normalización a coords de la app: voltear Y y trasladar a esquina
/// superior izquierda, metros. El SVG usa 100 px = 1 m (ADR-0006).
library;

import 'dart:convert';
import 'dart:io';

const _capaParedes = 'Poly-Walls';
const _capaPuertas = 'Poly-Doors';
const _capaVentanas = 'Poly-Windows';
const _capaCuartos = 'Poly-Rooms';
const _capaNombresCuarto = 'Poly-RoomLabels';
const _capaCotas = 'Poly-DimensionsInterior';

// Colores del SVG (coherentes con assets/maps/pasillo_aula.svg).
const _colorSuelo = '#F5F0E6';
const _colorMuro = '#2C2C2A';
const _colorGrid = '#D4CFC5';
const _colorVentana = '#5B7FA6';

Future<int> main(List<String> argv) async {
  if (argv.isEmpty || argv.first == '--help' || argv.first == '-h') {
    _printUsage();
    return 0;
  }
  final comando = argv.first;
  try {
    switch (comando) {
      case 'parse':
        if (argv.length < 2) {
          print('Error: falta la ruta del DXF.');
          print('Uso: dart tools/mapa_importer.dart parse <archivo.dxf> [--out <ruta>]');
          return 1;
        }
        final dxfPath = argv[1];
        final outIdx = argv.indexOf('--out');
        final outPath = (outIdx != -1 && outIdx + 1 < argv.length)
            ? argv[outIdx + 1]
            : '${_dirDe(dxfPath)}/borrador_mapa.json';
        return await _parse(dxfPath, outPath);
      case 'build':
        if (argv.length < 2) {
          print('Error: falta la ruta del borrador.');
          print('Uso: dart tools/mapa_importer.dart build <borrador.json> [--out <ruta.svg>]');
          return 1;
        }
        final draftPath = argv[1];
        final outIdx = argv.indexOf('--out');
        final outPath = (outIdx != -1 && outIdx + 1 < argv.length)
            ? argv[outIdx + 1]
            : '${_dirDe(draftPath, 'out')}/mapa.svg';
        return await _build(draftPath, outPath);
      default:
        print('Comando desconocido: $comando');
        _printUsage();
        return 1;
    }
  } catch (e) {
    print('Error: $e');
    return 1;
  }
}

void _printUsage() {
  print('''
MapaImporter — escaneo Polycam (DXF) → SVG limpio del piso

Comandos:
  parse <archivo.dxf> [--out <ruta>]
      Parsea el DXF y escribe un borrador editable (JSON) con la geometría:
      muros, puertas, ventanas, cuartos y dimensiones. Solo extrae datos.

  build <borrador.json> [--out <ruta.svg>]
      Genera un SVG limpio del piso (muros rellenos + huecos de puerta) a
      partir del borrador. Recorta a los cuartos marcados incluir=true.
      No inventa balizas ni nodos — eso se coloca después, a mano o en el
      editor.

  --help, -h
      Muestra esta ayuda.
''');
}

String _dirDe(String ruta, [String? sub]) {
  final i = ruta.replaceAll('\\', '/').lastIndexOf('/');
  final dir = i == -1 ? '.' : ruta.substring(0, i);
  return sub == null ? dir : '$dir/$sub';
}

// ─── parse: DXF → borrador (geometría) ────────────────────────────────────

Future<int> _parse(String dxfPath, String outPath) async {
  final file = File(dxfPath);
  if (!file.existsSync()) {
    print('Error: no se encontró $dxfPath');
    return 1;
  }

  // DWGCODEPAGE ANSI_1252; latin1 evita que el decode falle con el "²".
  final contenido = file.readAsStringSync(encoding: latin1);
  final lineas = contenido.split(RegExp(r'\r\n|\r|\n'));
  final pares = _leerPares(lineas);
  final entidades = _extraerEntidades(pares, 'ENTITIES');

  final poligonosPorCapa = <String, List<List<_P>>>{};
  final textosPorCapa = <String, List<_Texto>>{};
  for (final e in entidades) {
    if (e.tipo == 'LWPOLYLINE' && e.vertices.length >= 2) {
      poligonosPorCapa.putIfAbsent(e.capa, () => []).add(e.vertices);
    } else if ((e.tipo == 'MTEXT' || e.tipo == 'TEXT') && e.texto != null) {
      textosPorCapa
          .putIfAbsent(e.capa, () => [])
          .add(_Texto(_limpiarMText(e.texto!), e.insercion));
    }
  }

  // Bbox con la geometría real (muros + cuartos), no con el título/logo.
  final geometria = <_P>[
    for (final pl in poligonosPorCapa[_capaParedes] ?? const []) ...pl,
    for (final pl in poligonosPorCapa[_capaCuartos] ?? const []) ...pl,
  ];
  if (geometria.isEmpty) {
    print('Error: no se encontraron muros ni cuartos en el DXF.');
    print('Capas detectadas: ${poligonosPorCapa.keys.join(", ")}');
    return 1;
  }
  final bbox = _Bbox.de(geometria);
  _P aApp(_P p) => _P(_r(p.x - bbox.minX), _r(bbox.maxY - p.y));

  List<List<Map<String, double>>> poligonos(List<List<_P>> pls) => [
        for (final pl in pls)
          [for (final p in pl) {'x': aApp(p).x, 'y': aApp(p).y}],
      ];

  // Cuartos: polígono + centroide + área + nombre sugerido + incluir.
  final etiquetas = textosPorCapa[_capaNombresCuarto] ?? const <_Texto>[];
  final cuartos = <Map<String, dynamic>>[];
  var idCuarto = 1;
  for (final pl in poligonosPorCapa[_capaCuartos] ?? const <List<_P>>[]) {
    final ptsApp = pl.map(aApp).toList();
    final c = _centroide(ptsApp);
    final nombre = _nombreCuarto(pl, etiquetas, aApp);
    cuartos.add({
      'id': 'cuarto_${idCuarto++}',
      'nombre_sugerido': nombre ?? 'sin nombre',
      'incluir': !(nombre ?? '').toLowerCase().contains('ignore'),
      'centro': {'x': _r(c.x), 'y': _r(c.y)},
      'area_metros2': _r(_areaShoelace(ptsApp).abs()),
      'poligono': [for (final p in ptsApp) {'x': _r(p.x), 'y': _r(p.y)}],
    });
  }

  final borrador = <String, dynamic>{
    '_meta': {
      'fuente_dxf': dxfPath,
      'generado': DateTime.now().toIso8601String(),
      'unidad': 'metros',
      'escala_px_por_metro': 100,
      'nota': 'Borrador editable. Marcar qué cuartos incluir y corregir '
          'medidas si hace falta; luego `build` genera el SVG. Las balizas '
          'y los nodos NO se generan acá — se colocan a mano o en el editor.',
    },
    'mapa': {'ancho_metros': _r(bbox.ancho), 'alto_metros': _r(bbox.alto)},
    'paredes': poligonos(poligonosPorCapa[_capaParedes] ?? const []),
    'puertas': poligonos(poligonosPorCapa[_capaPuertas] ?? const []),
    'ventanas': poligonos(poligonosPorCapa[_capaVentanas] ?? const []),
    'cuartos': cuartos,
    'cotas_detectadas': [
      for (final t in textosPorCapa[_capaCotas] ?? const <_Texto>[]) t.texto,
    ],
  };

  File(outPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(borrador));

  print('✓ Parseado: $dxfPath');
  print('');
  print('Mapa completo: ${_r(bbox.ancho)} m × ${_r(bbox.alto)} m');
  print('Muros: ${(borrador['paredes'] as List).length}'
      ' · Puertas: ${(borrador['puertas'] as List).length}'
      ' · Ventanas: ${(borrador['ventanas'] as List).length}');
  print('');
  print('Cuartos:');
  for (final c in cuartos) {
    final inc = (c['incluir'] as bool) ? 'incluir' : 'IGNORAR';
    print('  ${(c['nombre_sugerido'] as String).padRight(16)}'
        ' ${(c['area_metros2'] as num).toString().padLeft(6)} m²  [$inc]');
  }
  print('');
  print('→ Borrador: $outPath');
  print('  Luego: dart tools/mapa_importer.dart build "$outPath"');
  return 0;
}

// ─── build: borrador → SVG limpio ─────────────────────────────────────────

Future<int> _build(String draftPath, String outPath) async {
  final f = File(draftPath);
  if (!f.existsSync()) {
    print('Error: no se encontró $draftPath');
    return 1;
  }
  final draft = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  final cuartos = (draft['cuartos'] as List).cast<Map<String, dynamic>>();
  final incluidos = cuartos.where((c) => c['incluir'] == true).toList();

  // Área a emitir: bbox de los cuartos incluidos (recorta los "ignore").
  final ptsInc = <_P>[
    for (final c in incluidos)
      for (final p in (c['poligono'] as List))
        _P((p['x'] as num).toDouble(), (p['y'] as num).toDouble()),
  ];
  final area = ptsInc.isNotEmpty
      ? _Bbox.de(ptsInc)
      : _Bbox(0, 0, (draft['mapa']['ancho_metros'] as num).toDouble(),
          (draft['mapa']['alto_metros'] as num).toDouble());
  const margen = 0.15;
  final minX = area.minX - margen;
  final minY = area.minY - margen;
  final ancho = _r(area.ancho + 2 * margen);
  final alto = _r(area.alto + 2 * margen);

  // Bbox individual de cada cuarto incluido. Recortar contra estos (y no
  // contra el bbox global) evita dejar muros fantasma en el "hueco" de
  // una planta en L: el vacío entre cuartos no pertenece a ninguno.
  const cropMargen = 0.3; // > grosor de muro, para conservar muros medianeros
  final cuartoBboxes = [
    for (final c in incluidos)
      _Bbox.de([
        for (final p in (c['poligono'] as List))
          _P((p['x'] as num).toDouble(), (p['y'] as num).toDouble()),
      ]),
  ];
  bool perteneceAlPiso(_P c) {
    for (final b in cuartoBboxes) {
      if (c.x >= b.minX - cropMargen &&
          c.x <= b.maxX + cropMargen &&
          c.y >= b.minY - cropMargen &&
          c.y <= b.maxY + cropMargen) {
        return true;
      }
    }
    return false;
  }

  // Centroide en coords del borrador → test de pertenencia → traslada.
  List<List<_P>> recortar(List<dynamic> polis) {
    final out = <List<_P>>[];
    for (final poly in polis) {
      final ptsBorr = [
        for (final p in poly as List)
          _P((p['x'] as num).toDouble(), (p['y'] as num).toDouble()),
      ];
      if (!perteneceAlPiso(_centroide(ptsBorr))) continue;
      out.add([for (final p in ptsBorr) _P(_r(p.x - minX), _r(p.y - minY))]);
    }
    return out;
  }

  final muros = _limpiar(recortar(draft['paredes'] as List));
  final puertas = _limpiar(recortar(draft['puertas'] as List));
  final ventanas = _limpiar(recortar(draft['ventanas'] as List));

  Directory(_dirDe(outPath)).createSync(recursive: true);
  File(outPath).writeAsStringSync(_emitirSvg(ancho, alto, muros, puertas, ventanas));

  print('✓ build → $outPath');
  print('  $ancho × $alto m · ${muros.length} muros, '
      '${puertas.length} puertas, ${ventanas.length} ventanas');
  print('');
  print('Revisar el SVG. Cuando esté OK, copiar a assets/maps/ y crear el');
  print('grafo (nodos) + balizas a mano o desde el editor.');
  return 0;
}

String _emitirSvg(double ancho, double alto, List<List<_P>> muros,
    List<List<_P>> puertas, List<List<_P>> ventanas) {
  final w = (ancho * 100).round();
  final h = (alto * 100).round();
  String pts(List<_P> poly) =>
      poly.map((p) => '${(p.x * 100).toStringAsFixed(1)},'
          '${(p.y * 100).toStringAsFixed(1)}').join(' ');

  final sb = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<!-- Generado por tools/mapa_importer.dart desde un escaneo '
        'Polycam. -->')
    ..writeln('<svg xmlns="http://www.w3.org/2000/svg" '
        'viewBox="0 0 $w $h" width="$w" height="$h">')
    ..writeln('  <rect x="0" y="0" width="$w" height="$h" fill="$_colorSuelo"/>')
    // Cuadrícula métrica (1 m), sutil.
    ..writeln('  <g stroke="$_colorGrid" stroke-width="0.5" opacity="0.35">');
  for (var x = 100; x < w; x += 100) {
    sb.writeln('    <line x1="$x" y1="0" x2="$x" y2="$h"/>');
  }
  for (var y = 100; y < h; y += 100) {
    sb.writeln('    <line x1="0" y1="$y" x2="$w" y2="$y"/>');
  }
  sb.writeln('  </g>');

  // Muros: polígonos RELLENOS sólidos (no trazados). Así se ven limpios y
  // con su grosor real, sin los bordes dobles de trazar el contorno.
  sb.writeln('  <g fill="$_colorMuro">');
  for (final m in muros) {
    sb.writeln('    <polygon points="${pts(m)}"/>');
  }
  sb.writeln('  </g>');

  // Puertas: el hueco se pinta del color del suelo ENCIMA del muro, lo que
  // "abre" el vano. Un borde fino lo hace legible como puerta.
  if (puertas.isNotEmpty) {
    sb.writeln('  <g fill="$_colorSuelo" stroke="$_colorMuro" '
        'stroke-width="1.5">');
    for (final p in puertas) {
      sb.writeln('    <polygon points="${pts(p)}"/>');
    }
    sb.writeln('  </g>');
  }

  // Ventanas: línea fina azulada (poco más, para orientación).
  if (ventanas.isNotEmpty) {
    sb.writeln('  <g fill="$_colorSuelo" stroke="$_colorVentana" '
        'stroke-width="2">');
    for (final v in ventanas) {
      sb.writeln('    <polygon points="${pts(v)}"/>');
    }
    sb.writeln('  </g>');
  }

  sb.writeln('</svg>');
  return sb.toString();
}

// ─── Parseo DXF de bajo nivel ─────────────────────────────────────────────

class _Par {
  final int codigo;
  final String valor;
  _Par(this.codigo, this.valor);
}

List<_Par> _leerPares(List<String> lineas) {
  final pares = <_Par>[];
  for (var i = 0; i + 1 < lineas.length; i += 2) {
    final codigo = int.tryParse(lineas[i].trim());
    if (codigo == null) {
      throw 'DXF malformado: se esperaba un código de grupo en la línea '
          '${i + 1}, se encontró "${lineas[i]}".';
    }
    pares.add(_Par(codigo, lineas[i + 1]));
  }
  return pares;
}

class _Entidad {
  String tipo;
  String capa = '0';
  final List<_P> vertices = [];
  String? texto;
  _P? insercion;
  _Entidad(this.tipo);
}

List<_Entidad> _extraerEntidades(List<_Par> pares, String seccion) {
  final entidades = <_Entidad>[];
  var dentro = false;
  _Entidad? actual;
  double? xPendiente;

  for (var i = 0; i < pares.length; i++) {
    final p = pares[i];
    if (p.codigo == 0 && p.valor.trim() == 'SECTION') {
      if (i + 1 < pares.length && pares[i + 1].codigo == 2) {
        dentro = pares[i + 1].valor.trim() == seccion;
      }
      continue;
    }
    if (!dentro) continue;
    if (p.codigo == 0 && p.valor.trim() == 'ENDSEC') {
      if (actual != null) entidades.add(actual);
      break;
    }
    if (p.codigo == 0) {
      if (actual != null) entidades.add(actual);
      actual = _Entidad(p.valor.trim());
      xPendiente = null;
      continue;
    }
    if (actual == null) continue;
    switch (p.codigo) {
      case 8:
        actual.capa = p.valor.trim();
      case 10:
        xPendiente = double.tryParse(p.valor.trim());
      case 20:
        final y = double.tryParse(p.valor.trim());
        if (xPendiente != null && y != null) {
          final punto = _P(xPendiente, y);
          actual.vertices.add(punto);
          actual.insercion ??= punto;
          xPendiente = null;
        }
      case 1:
        actual.texto = p.valor;
    }
  }
  return entidades;
}

// ─── Geometría ────────────────────────────────────────────────────────────

class _P {
  final double x;
  final double y;
  _P(this.x, this.y);
}

class _Texto {
  final String texto;
  final _P? pos;
  _Texto(this.texto, this.pos);
}

class _Bbox {
  final double minX, minY, maxX, maxY;
  _Bbox(this.minX, this.minY, this.maxX, this.maxY);

  factory _Bbox.de(List<_P> pts) {
    var minX = pts.first.x, maxX = pts.first.x;
    var minY = pts.first.y, maxY = pts.first.y;
    for (final p in pts) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }
    return _Bbox(minX, minY, maxX, maxY);
  }

  double get ancho => maxX - minX;
  double get alto => maxY - minY;
}

/// Quita polígonos duplicados (Polycam exporta cada muro dos veces) y los
/// degenerados (marcas de 2-3 puntos como jambas o líneas de cristal, que
/// no son contornos rellenables).
List<List<_P>> _limpiar(List<List<_P>> polis) {
  final vistos = <String>{};
  final out = <List<_P>>[];
  for (final p in polis) {
    if (p.length < 4) continue;
    final sig = p.map((q) => '${q.x},${q.y}').join(';');
    if (vistos.add(sig)) out.add(p);
  }
  return out;
}

double _areaShoelace(List<_P> pts) {
  var area = 0.0;
  for (var i = 0; i < pts.length; i++) {
    final a = pts[i];
    final b = pts[(i + 1) % pts.length];
    area += a.x * b.y - b.x * a.y;
  }
  return area / 2;
}

_P _centroide(List<_P> pts) {
  var sx = 0.0, sy = 0.0;
  for (final p in pts) {
    sx += p.x;
    sy += p.y;
  }
  return _P(sx / pts.length, sy / pts.length);
}

/// Nombre de la etiqueta más cercana al centroide del cuarto (o null).
String? _nombreCuarto(
    List<_P> poligonoDxf, List<_Texto> etiquetas, _P Function(_P) aApp) {
  if (etiquetas.isEmpty) return null;
  final centro = _centroide(poligonoDxf.map(aApp).toList());
  String? mejor;
  var mejorDist = double.infinity;
  for (final e in etiquetas) {
    if (e.pos == null) continue;
    final ep = aApp(e.pos!);
    final d = (ep.x - centro.x) * (ep.x - centro.x) +
        (ep.y - centro.y) * (ep.y - centro.y);
    if (d < mejorDist) {
      mejorDist = d;
      mejor = e.texto;
    }
  }
  return mejor;
}

/// Limpia códigos de formato de MTEXT. Ej: "\A1;mapped" → "mapped".
String _limpiarMText(String raw) {
  var s = raw;
  s = s.replaceAll(RegExp(r'\\[A-Za-z][^;\\]*;'), '');
  s = s.replaceAll(RegExp(r'\\P'), ' ');
  s = s.replaceAll(RegExp(r'[{}]'), '');
  s = s.replaceAll(RegExp(r'\\[A-Za-z]'), '');
  return s.trim();
}

/// Redondea a 3 decimales para quitar ruido de float del DXF.
double _r(double v) => (v * 1000).round() / 1000;
