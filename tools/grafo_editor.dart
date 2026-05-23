// Este archivo es un script CLI: `print` es la forma legítima de
// comunicarse con el usuario. Suprimimos el lint avoid_print sólo
// en este archivo, no en el resto del proyecto.
// ignore_for_file: avoid_print

/// GrafoEditor — herramienta CLI para modificar `assets/data/grafo.json`
/// con seguridad: validación previa, backup automático, idempotencia.
///
/// Ejecutar desde la raíz del proyecto:
/// ```bash
/// dart tools/grafo_editor.dart <comando> [argumentos...]
/// ```
///
/// Ver `docs/grafo-format.md` para la lista completa de comandos y
/// `docs/adr/0005-grafo-editor-cli.md` para la justificación del diseño.
///
/// Esta herramienta NO depende de Flutter — solo Dart stdlib — para
/// que pueda correr en CI/CD o en máquinas sin SDK de Flutter instalado.
library;

import 'dart:convert';
import 'dart:io';

const _grafoPath = 'assets/data/grafo.json';
const _backupPath = 'assets/data/grafo.backup.json';

const _tiposValidos = [
  'ENTRADA',
  'SALON',
  'BANO',
  'OFICINA',
  'BEBEDERO',
  'COMEDOR',
  'ASCENSOR',
  'ESCALERA',
  'INTERSECCION',
  'MARCADOR_AR',
];

const _obstaculosValidos = ['NINGUNO', 'ESCALERA', 'RAMPA', 'PUERTA_PESADA'];

Future<int> main(List<String> argv) async {
  if (argv.isEmpty || argv.first == '--help' || argv.first == '-h') {
    _printUsage();
    return 0;
  }

  final comando = argv.first;
  final args = _parsearArgs(argv.skip(1).toList());

  try {
    switch (comando) {
      case 'list-nodos':
        return await _listNodos();
      case 'list-aristas':
        return await _listAristas();
      case 'add-nodo':
        return await _addNodo(args);
      case 'remove-nodo':
        return await _removeNodo(args);
      case 'add-arista':
        return await _addArista(args);
      case 'remove-arista':
        return await _removeArista(args);
      case 'validar':
        return await _validar();
      case 'validar-mapa':
        return await _validarMapa();
      default:
        stderr.writeln('Comando desconocido: "$comando"');
        _printUsage();
        return 1;
    }
  } catch (e) {
    stderr.writeln('Error: $e');
    return 1;
  }
}

// ─── Comandos ────────────────────────────────────────────────────────────────

Future<int> _listNodos() async {
  final grafo = await _cargar();
  final nodos = grafo['nodos'] as List<dynamic>;

  if (nodos.isEmpty) {
    print('(sin nodos)');
    return 0;
  }

  // Formato de tabla simple, alineado.
  print('${_pad('ID', 18)} ${_pad('Tipo', 14)} ${_pad('Nombre', 28)}'
      '  x       y     Piso  Acc');
  print('─' * 80);
  for (final n in nodos) {
    final id = _pad('${n['id']}', 18);
    final tipo = _pad('${n['tipo']}', 14);
    final nombre = _pad('${n['nombre']}', 28);
    final x = (n['x'] as num).toStringAsFixed(2).padLeft(6);
    final y = (n['y'] as num).toStringAsFixed(2).padLeft(6);
    final piso = '${n['piso']}'.padLeft(4);
    final acc = (n['accesible'] == true) ? ' ✓ ' : '   ';
    print('$id $tipo $nombre  $x  $y  $piso  $acc');
  }
  print('\nTotal: ${nodos.length} nodos');
  return 0;
}

Future<int> _listAristas() async {
  final grafo = await _cargar();
  final aristas = grafo['aristas'] as List<dynamic>;

  if (aristas.isEmpty) {
    print('(sin aristas)');
    return 0;
  }

  print('${_pad('Origen', 18)} → ${_pad('Destino', 18)}  Dist    '
      'Obstáculo       Acc');
  print('─' * 80);
  for (final a in aristas) {
    final origen = _pad('${a['origenId']}', 18);
    final destino = _pad('${a['destinoId']}', 18);
    final dist = (a['distancia'] as num).toStringAsFixed(2).padLeft(6);
    final obst = _pad('${a['tipoObstaculo']}', 15);
    final acc = (a['accesible'] == true) ? ' ✓ ' : '   ';
    print('$origen → $destino  $dist  $obst  $acc');
  }
  print('\nTotal: ${aristas.length} aristas');
  return 0;
}

Future<int> _addNodo(Map<String, String> args) async {
  // Validar campos requeridos
  final id = args['id'] ?? (throw 'Falta --id');
  final nombre = args['nombre'] ?? (throw 'Falta --nombre');
  final tipo = args['tipo'] ?? (throw 'Falta --tipo');
  final x = double.tryParse(args['x'] ?? '') ??
      (throw 'Falta --x o no es un número');
  final y = double.tryParse(args['y'] ?? '') ??
      (throw 'Falta --y o no es un número');
  final piso = int.tryParse(args['piso'] ?? '') ??
      (throw 'Falta --piso o no es un entero');
  final accesible = args['accesible']?.toLowerCase() != 'false';
  final arucoId = args['aruco-id'] != null
      ? int.tryParse(args['aruco-id']!) ??
          (throw '--aruco-id no es un entero')
      : null;

  if (!_tiposValidos.contains(tipo)) {
    throw 'Tipo inválido. Opciones: ${_tiposValidos.join(", ")}';
  }
  if (tipo == 'MARCADOR_AR' && arucoId == null) {
    throw 'Nodo MARCADOR_AR requiere --aruco-id';
  }

  final grafo = await _cargar();
  final nodos = grafo['nodos'] as List<dynamic>;

  if (nodos.any((n) => n['id'] == id)) {
    throw 'Ya existe un nodo con id "$id". Usa otro ID o remove-nodo primero.';
  }

  final nuevoNodo = <String, dynamic>{
    'id': id,
    'nombre': nombre,
    'tipo': tipo,
    'x': x,
    'y': y,
    'piso': piso,
    'accesible': accesible,
    'aruco_id': ?arucoId,
  };

  nodos.add(nuevoNodo);
  await _validarYGuardar(grafo);
  print('✓ Nodo "$id" agregado (${nodos.length} nodos en total).');
  return 0;
}

Future<int> _removeNodo(Map<String, String> args) async {
  final id = args['id'] ?? (throw 'Falta --id');
  final grafo = await _cargar();
  final nodos = grafo['nodos'] as List<dynamic>;
  final aristas = grafo['aristas'] as List<dynamic>;

  final antesNodos = nodos.length;
  nodos.removeWhere((n) => n['id'] == id);
  if (nodos.length == antesNodos) {
    throw 'No existe el nodo "$id".';
  }

  // Eliminar todas las aristas que referencian al nodo.
  final antesAristas = aristas.length;
  aristas.removeWhere(
      (a) => a['origenId'] == id || a['destinoId'] == id);
  final aristasEliminadas = antesAristas - aristas.length;

  await _validarYGuardar(grafo);
  print('✓ Nodo "$id" eliminado.');
  if (aristasEliminadas > 0) {
    print('  ($aristasEliminadas arista${aristasEliminadas != 1 ? "s" : ""} '
        'asociada${aristasEliminadas != 1 ? "s" : ""} eliminada'
        '${aristasEliminadas != 1 ? "s" : ""} también)');
  }
  return 0;
}

Future<int> _addArista(Map<String, String> args) async {
  final origen = args['origen'] ?? (throw 'Falta --origen');
  final destino = args['destino'] ?? (throw 'Falta --destino');
  final dist = double.tryParse(args['dist'] ?? '') ??
      (throw 'Falta --dist o no es un número');
  final obstaculo = args['obstaculo'] ?? 'NINGUNO';
  final accesible = args['accesible']?.toLowerCase() != 'false';

  if (dist <= 0) throw 'Distancia debe ser positiva';
  if (!_obstaculosValidos.contains(obstaculo)) {
    throw 'Obstáculo inválido. Opciones: ${_obstaculosValidos.join(", ")}';
  }

  final grafo = await _cargar();
  final nodos = grafo['nodos'] as List<dynamic>;
  final aristas = grafo['aristas'] as List<dynamic>;

  if (!nodos.any((n) => n['id'] == origen)) {
    throw 'Nodo origen "$origen" no existe';
  }
  if (!nodos.any((n) => n['id'] == destino)) {
    throw 'Nodo destino "$destino" no existe';
  }
  if (origen == destino) {
    throw 'Origen y destino no pueden ser el mismo nodo';
  }

  // Verificar que no exista ya esta arista en la misma dirección.
  if (aristas.any((a) =>
      a['origenId'] == origen && a['destinoId'] == destino)) {
    throw 'Ya existe arista "$origen" → "$destino"';
  }

  aristas.add({
    'origenId': origen,
    'destinoId': destino,
    'distancia': dist,
    'tipoObstaculo': obstaculo,
    'accesible': accesible,
  });

  await _validarYGuardar(grafo);
  print('✓ Arista "$origen" → "$destino" agregada (${dist}m, $obstaculo).');
  return 0;
}

Future<int> _removeArista(Map<String, String> args) async {
  final origen = args['origen'] ?? (throw 'Falta --origen');
  final destino = args['destino'] ?? (throw 'Falta --destino');

  final grafo = await _cargar();
  final aristas = grafo['aristas'] as List<dynamic>;

  final antes = aristas.length;
  aristas.removeWhere(
      (a) => a['origenId'] == origen && a['destinoId'] == destino);

  if (aristas.length == antes) {
    throw 'No existe arista "$origen" → "$destino"';
  }

  await _validarYGuardar(grafo);
  print('✓ Arista "$origen" → "$destino" eliminada.');
  return 0;
}

Future<int> _validar() async {
  final grafo = await _cargar();
  _validarGrafo(grafo);
  final nodos = (grafo['nodos'] as List<dynamic>).length;
  final aristas = (grafo['aristas'] as List<dynamic>).length;
  print('✓ Grafo válido: $nodos nodos, $aristas aristas.');
  return 0;
}

/// Verifica que el SVG declarado en `mapa_svg` exista y que sus
/// dimensiones (viewBox) coincidan con las del grafo.
///
/// Reglas verificadas (ver docs/adr/0007-validacion-cruzada-mapa-grafo.md):
/// 1. El archivo SVG existe en disco
/// 2. El viewBox parsea como cuatro números
/// 3. min-x y min-y son 0
/// 4. viewBox_ancho = mapa_ancho_metros × 100 (±1 px de tolerancia)
/// 5. viewBox_alto  = mapa_alto_metros  × 100 (±1 px de tolerancia)
/// 6. Cada nodo está dentro de las dimensiones declaradas
///
/// No verifica geometría interna del SVG ni correspondencia entre
/// aristas y pasillos reales — eso requiere verificación visual.
Future<int> _validarMapa() async {
  final grafo = await _cargar();
  _validarGrafo(grafo);

  final svgPath = grafo['mapa_svg'] as String?;
  final anchoMetros = (grafo['mapa_ancho_metros'] as num?)?.toDouble();
  final altoMetros = (grafo['mapa_alto_metros'] as num?)?.toDouble();

  if (svgPath == null) throw 'grafo.json no declara "mapa_svg"';
  if (anchoMetros == null) {
    throw 'grafo.json no declara "mapa_ancho_metros"';
  }
  if (altoMetros == null) {
    throw 'grafo.json no declara "mapa_alto_metros"';
  }

  // Regla 1: SVG existe
  final svgFile = File(svgPath);
  if (!await svgFile.exists()) {
    throw 'SVG no encontrado en "$svgPath" (declarado en grafo.json)';
  }

  // Reglas 2-5: viewBox coherente con dimensiones
  final svgContent = await svgFile.readAsString();
  final viewBox = _extraerViewBox(svgContent);
  if (viewBox == null) {
    throw 'No se pudo extraer viewBox del SVG. Verificar que el archivo '
        'tenga un atributo viewBox válido en el elemento <svg>.';
  }

  final esperadoAncho = anchoMetros * 100;
  final esperadoAlto = altoMetros * 100;

  if (viewBox.minX != 0 || viewBox.minY != 0) {
    throw 'El viewBox del SVG debe empezar en "0 0", pero empieza en '
        '"${viewBox.minX} ${viewBox.minY}". Ver docs/map-format.md.';
  }

  if ((viewBox.width - esperadoAncho).abs() > 1) {
    throw 'Discrepancia de ancho:\n'
        '  - viewBox del SVG: ${viewBox.width} px\n'
        '  - mapa_ancho_metros × 100: ${esperadoAncho.toStringAsFixed(0)} px\n'
        '  Diferencia: ${(viewBox.width - esperadoAncho).abs().toStringAsFixed(1)} px.\n'
        '  Ajustar el viewBox del SVG o el "mapa_ancho_metros" en grafo.json.';
  }

  if ((viewBox.height - esperadoAlto).abs() > 1) {
    throw 'Discrepancia de alto:\n'
        '  - viewBox del SVG: ${viewBox.height} px\n'
        '  - mapa_alto_metros × 100: ${esperadoAlto.toStringAsFixed(0)} px\n'
        '  Diferencia: ${(viewBox.height - esperadoAlto).abs().toStringAsFixed(1)} px.\n'
        '  Ajustar el viewBox del SVG o el "mapa_alto_metros" en grafo.json.';
  }

  // Regla 6: nodos dentro del piso
  final nodos = grafo['nodos'] as List<dynamic>;
  final nodosFuera = <String>[];
  for (final n in nodos) {
    final x = (n['x'] as num).toDouble();
    final y = (n['y'] as num).toDouble();
    if (x < 0 || x > anchoMetros || y < 0 || y > altoMetros) {
      nodosFuera.add(
          '  - "${n['id']}" en (${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})');
    }
  }
  if (nodosFuera.isNotEmpty) {
    throw 'Nodos fuera del piso (dimensiones declaradas: '
        '$anchoMetros×$altoMetros m):\n${nodosFuera.join("\n")}';
  }

  print('✓ Mapa y grafo coherentes:');
  print('  - Piso: ${grafo['piso']} de ${grafo['edificio']}');
  print('  - SVG: $svgPath');
  print('  - Dimensiones: ${anchoMetros}m × ${altoMetros}m '
      '(viewBox ${viewBox.width.toInt()}×${viewBox.height.toInt()} px)');
  print('  - Escala: 100 px = 1 m');
  print('  - Nodos: ${nodos.length}, todos dentro del piso');
  return 0;
}

/// Datos del viewBox del SVG (los 4 números del atributo).
class _ViewBox {
  final double minX, minY, width, height;
  const _ViewBox(this.minX, this.minY, this.width, this.height);
}

/// Extrae el viewBox de un SVG con un regex.
///
/// No usamos un parser XML completo porque solo necesitamos un atributo
/// y queremos mantener cero dependencias en el tool. El regex tolera
/// espacios y comas como separadores (ambos son válidos en SVG).
_ViewBox? _extraerViewBox(String svgContent) {
  final match = RegExp(r'viewBox\s*=\s*"([^"]+)"').firstMatch(svgContent);
  if (match == null) return null;

  final partes = match.group(1)!
      .split(RegExp(r'[\s,]+'))
      .where((s) => s.isNotEmpty)
      .map(double.tryParse)
      .toList();
  if (partes.length != 4 || partes.any((p) => p == null)) return null;

  return _ViewBox(partes[0]!, partes[1]!, partes[2]!, partes[3]!);
}

// ─── IO y utilidades ─────────────────────────────────────────────────────────

Future<Map<String, dynamic>> _cargar() async {
  final file = File(_grafoPath);
  if (!await file.exists()) {
    throw 'No se encontró $_grafoPath. ¿Estás corriendo el script desde la raíz del proyecto?';
  }
  final raw = await file.readAsString();
  return jsonDecode(raw) as Map<String, dynamic>;
}

Future<void> _validarYGuardar(Map<String, dynamic> grafo) async {
  // Backup antes de cualquier escritura.
  final original = File(_grafoPath);
  await original.copy(_backupPath);

  // Validar — si falla, no escribir.
  _validarGrafo(grafo);

  // Escribir con indentación de 2 espacios (formato consistente).
  final encoder = const JsonEncoder.withIndent('  ');
  await original.writeAsString('${encoder.convert(grafo)}\n');
}

/// Misma lógica que `GrafoRepository._validar()` en `lib/data/`, pero
/// duplicada aquí porque el tool no puede importar código de `lib/`
/// sin pull in todo el SDK de Flutter.
///
/// Si alguna vez se cambia la lógica de validación en uno de los dos
/// lugares, hay que actualizar el otro.
void _validarGrafo(Map<String, dynamic> grafo) {
  final nodos = (grafo['nodos'] as List<dynamic>? ?? []);
  final aristas = (grafo['aristas'] as List<dynamic>? ?? []);

  // IDs únicos
  final ids = <String>{};
  for (final n in nodos) {
    final id = n['id'] as String;
    if (!ids.add(id)) {
      throw 'Validación falló: ID de nodo duplicado: "$id"';
    }
  }

  // Aristas referencian nodos existentes
  for (final a in aristas) {
    final origen = a['origenId'] as String;
    final destino = a['destinoId'] as String;
    final distancia = (a['distancia'] as num).toDouble();
    if (!ids.contains(origen)) {
      throw 'Validación falló: arista referencia nodo inexistente: "$origen"';
    }
    if (!ids.contains(destino)) {
      throw 'Validación falló: arista referencia nodo inexistente: "$destino"';
    }
    if (distancia <= 0) {
      throw 'Validación falló: arista "$origen → $destino" con distancia no positiva';
    }
  }

  // MARCADOR_AR requiere aruco_id
  for (final n in nodos) {
    if (n['tipo'] == 'MARCADOR_AR' && n['aruco_id'] == null) {
      throw 'Validación falló: nodo MARCADOR_AR "${n['id']}" sin aruco_id';
    }
  }

  // Debe haber al menos un nodo ENTRADA
  if (!nodos.any((n) => n['tipo'] == 'ENTRADA')) {
    throw 'Validación falló: el grafo debe tener al menos un nodo ENTRADA';
  }
}

/// Parseo simple de argumentos tipo `--clave=valor` o `--clave valor`.
/// No usa el paquete `args` para mantener cero dependencias.
Map<String, String> _parsearArgs(List<String> argv) {
  final result = <String, String>{};
  for (int i = 0; i < argv.length; i++) {
    final arg = argv[i];
    if (!arg.startsWith('--')) continue;
    final sinGuiones = arg.substring(2);
    if (sinGuiones.contains('=')) {
      final idx = sinGuiones.indexOf('=');
      result[sinGuiones.substring(0, idx)] = sinGuiones.substring(idx + 1);
    } else if (i + 1 < argv.length && !argv[i + 1].startsWith('--')) {
      result[sinGuiones] = argv[i + 1];
      i++;
    } else {
      // Flag booleana sin valor — tratar como "true"
      result[sinGuiones] = 'true';
    }
  }
  return result;
}

String _pad(String s, int n) {
  if (s.length >= n) return s.substring(0, n);
  return s.padRight(n);
}

void _printUsage() {
  print('''
GrafoEditor — Editor CLI para assets/data/grafo.json

USO:
  dart tools/grafo_editor.dart <comando> [argumentos...]

COMANDOS:
  list-nodos                    Lista todos los nodos
  list-aristas                  Lista todas las aristas
  add-nodo --id=X --nombre="..." --tipo=SALON --x=N --y=N --piso=N
                                [--accesible=true|false] [--aruco-id=N]
                                Agrega un nodo
  remove-nodo --id=X            Elimina un nodo y todas sus aristas
  add-arista --origen=X --destino=Y --dist=N
                                [--obstaculo=NINGUNO] [--accesible=true|false]
                                Agrega una arista
  remove-arista --origen=X --destino=Y
                                Elimina una arista
  validar                       Valida el grafo sin modificarlo
  validar-mapa                  Valida coherencia entre el SVG y el grafo
                                (viewBox, dimensiones, nodos dentro del piso)

TIPOS DE NODO:
  ${_tiposValidos.join(", ")}

TIPOS DE OBSTÁCULO:
  ${_obstaculosValidos.join(", ")}

EJEMPLOS:
  dart tools/grafo_editor.dart list-nodos
  dart tools/grafo_editor.dart add-nodo --id=salon_403 --nombre="Salón 403" \\
       --tipo=SALON --x=12.5 --y=8.0 --piso=4
  dart tools/grafo_editor.dart add-arista --origen=salon_403 \\
       --destino=pasillo_norte_4 --dist=3.5
  dart tools/grafo_editor.dart validar

SEGURIDAD:
  - Cada modificación crea un backup en assets/data/grafo.backup.json
  - La validación se ejecuta antes de cada escritura
  - Si la validación falla, no se escribe nada y se preserva el original

Ver docs/grafo-format.md para el formato completo.
''');
}
