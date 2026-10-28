"""Plano oficial de la UTP (PDF vectorial, esc. 1:250) → mapa de la app.

Genera en <dir_salida>:
  - fisc_piso4_oficial.svg          muros/puertas/detalle a 100 px = 1 m (ADR-0006),
                                    fondo transparente y trazos en `currentColor`.
  - fisc_piso4_oficial.json         recintos (polígono en metros, nombre, tipo,
                                    código) + áreas de circulación. Lo lee
                                    `RecintoRepository`.
  - fisc_piso4_oficial_preview.svg  vista previa a color, solo para revisar.

Cómo funciona:
  1. Los trazos del PDF se clasifican por grosor: 0,96 pt = muros, 1,44 pt =
     columnas, 0,72/0,6 pt = puertas y muebles, 0,48 pt = ventanas. Se
     reescriben en metros y se agrupan en un <path> por clase.
  2. Cada número de recinto del dibujo se rellena por flood fill sobre un
     raster de muros (cerrando puertas de hasta 1-2 m). El recinto se acepta
     solo si su área queda a ±12 % del cuadro de áreas oficial; así se verifica
     la escala (1:250) y se descartan los recintos que se "escapan".
  3. La circulación es la huella del edificio menos muros y recintos.

Requiere: pymupdf, numpy, scipy, contourpy, pillow (no son dependencias de la app).

Uso:  py tools/plano_oficial/extraer_plano.py "<plano.pdf>" <dir_salida>
"""
import sys, re, json, math
import numpy as np
import pymupdf
import contourpy
from scipy import ndimage
from PIL import Image, ImageDraw

PDF, OUT = sys.argv[1], sys.argv[2]
M_POR_PT = 0.0254 / 72 * 250          # 1:250
PX_M = 100                            # escala del SVG de la app (ADR-0006)
K = M_POR_PT * PX_M                   # px de SVG por pt de papel
# Región del dibujo en pt (excluye cuadros de áreas, nomenclatura y rótulo).
BX0, BY0, BX1, BY1 = 120, 40, 1550, 920
EXCLUIR = [(1275, 678, 1730, 1300),    # cuadro de áreas derecho (el ala este baja hasta y≈673)
           (340, 845, 640, 935),       # nomenclatura
           (850, 918, 1240, 970)]      # título
MARGEN_M = 1.0

p = pymupdf.open(PDF)[0]
dibujos = p.get_drawings()
words = p.get_text('words')

def dentro(r):
    if r.x0 < BX0 or r.y0 < BY0 or r.x1 > BX1 or r.y1 > BY1:
        return False
    for x0, y0, x1, y1 in EXCLUIR:
        if r.x0 >= x0 and r.y0 >= y0 and r.x1 <= x1 and r.y1 <= y1:
            return False
    return True

def es_negro(c):
    return c is None or max(c) < 0.5

# ── Huella real del edificio (bbox de muros) para fijar el origen ─────────────
muros_d = [d for d in dibujos if dentro(d['rect']) and es_negro(d.get('color'))]
ox = min(d['rect'].x0 for d in muros_d) - MARGEN_M / M_POR_PT
oy = min(d['rect'].y0 for d in muros_d) - MARGEN_M / M_POR_PT
mx = max(d['rect'].x1 for d in muros_d) + MARGEN_M / M_POR_PT
my = max(d['rect'].y1 for d in muros_d) + MARGEN_M / M_POR_PT
ANCHO_M = round((mx - ox) * M_POR_PT, 2)
ALTO_M = round((my - oy) * M_POR_PT, 2)

def T(pt):
    return ((pt.x - ox) * K, (pt.y - oy) * K)

def fmt(v):
    return f'{v:.0f}'

# ── 1. SVG vectorial por clase de trazo ───────────────────────────────────────
CLASES = {'muro': {0.96, 1.08}, 'columna': {1.44}, 'detalle': {0.72, 0.6, 0.24, 0.12, 0.0},
          'ventana': {0.48}}
paths = {k: [] for k in CLASES}
rellenos = []
for d in muros_d:
    w = round(d.get('width') or 0, 2)
    if d.get('fill') is not None:
        if es_negro(d['fill']) and d['rect'].width < 20 and d['rect'].height < 20:
            clase = 'relleno'
        else:
            continue
    else:
        clase = next((k for k, s in CLASES.items() if w in s), None)
        if clase is None:
            continue
    seg = []
    for it in d['items']:
        if it[0] == 'l':
            a, b = T(it[1]), T(it[2])
            seg.append(f'M{fmt(a[0])} {fmt(a[1])}L{fmt(b[0])} {fmt(b[1])}')
        elif it[0] == 'c':
            a, c1, c2, b = (T(q) for q in it[1:5])
            seg.append(f'M{fmt(a[0])} {fmt(a[1])}C{fmt(c1[0])} {fmt(c1[1])} {fmt(c2[0])} {fmt(c2[1])} {fmt(b[0])} {fmt(b[1])}')
        elif it[0] == 'qu':
            q = it[1]
            pts = [T(q.ul), T(q.ur), T(q.lr), T(q.ll)]
            seg.append('M' + 'L'.join(f'{fmt(x)} {fmt(y)}' for x, y in pts) + 'Z')
        elif it[0] == 're':
            r = it[1]
            pts = [T(r.tl), T(r.tr), T(r.br), T(r.bl)]
            seg.append('M' + 'L'.join(f'{fmt(x)} {fmt(y)}' for x, y in pts) + 'Z')
    (rellenos if clase == 'relleno' else paths[clase]).extend(seg)

# ── 2. Recintos: raster de MUROS (solo trazos gruesos) + flood fill ───────────
Z = 3.0                                  # px raster por pt
M_POR_PX = M_POR_PT / Z
W = int((mx - ox) * Z) + 1
H = int((my - oy) * Z) + 1
def R(pt):
    return ((pt.x - ox) * Z, (pt.y - oy) * Z)

def rasterizar(incluir):
    im = Image.new('L', (W, H), 0)
    dr = ImageDraw.Draw(im)
    for d in muros_d:
        for it in d['items']:
            if not incluir(d, it):
                continue
            if it[0] == 'l':
                dr.line([R(it[1]), R(it[2])], fill=255, width=3)
            elif it[0] == 'c':
                # Bézier muestreada (la fachada curva del vestíbulo es una 'c').
                p0, p1, p2, p3 = it[1:5]
                pts = []
                for i in range(17):
                    t = i / 16
                    a, b, c, e = (1 - t) ** 3, 3 * t * (1 - t) ** 2, 3 * t * t * (1 - t), t ** 3
                    pts.append(R(pymupdf.Point(a * p0.x + b * p1.x + c * p2.x + e * p3.x,
                                               a * p0.y + b * p1.y + c * p2.y + e * p3.y)))
                dr.line(pts, fill=255, width=3)
            elif it[0] == 'qu':
                q = it[1]
                dr.polygon([R(q.ul), R(q.ur), R(q.lr), R(q.ll)], fill=255)
            elif it[0] == 're':
                dr.rectangle([R(it[1].tl), R(it[1].br)], fill=255)
    return np.array(im) > 0

def grueso(d, it):
    w = round(d.get('width') or 0, 2)
    return w in CLASES['muro'] | CLASES['columna'] or d.get('fill') is not None

def largo(it):
    if it[0] != 'l':
        return 0
    return math.hypot(it[2].x - it[1].x, it[2].y - it[1].y) * M_POR_PT

# Tres máscaras de muros, de más limpia a más completa: (A) solo muros gruesos;
# (B) + tabiques finos largos (≥ 1,2 m, descarta muebles y artefactos);
# (C) todo el dibujo (como el render del PDF).
RASTERS = [rasterizar(grueso),
           rasterizar(lambda d, it: grueso(d, it) or (it[0] == 'l' and largo(it) >= 1.2
                      and round(d.get('width') or 0, 2) in (0.6, 0.72))),
           rasterizar(lambda d, it: round(d.get('width') or 0, 2) != 0.48 or True)]
muros = RASTERS[0]

# Cuadro de áreas oficial.
tablas = {}
for x0, y0, x1, y1, w, *_ in words:
    if (y1 - y0) <= 9.5 and (x0 > 1290 or y0 > 975):
        t = 0 if x0 > 1290 else (1 if x0 < 750 else 2)
        tablas.setdefault(t, []).append(((y0 + y1) / 2, x0, w))
oficial = {}
for ws in tablas.values():
    ws.sort()
    filas, act, ult = [], [], None
    for yc, x0, w in ws:
        if ult is not None and yc - ult > 4:
            filas.append(act); act = []
        act.append((x0, w)); ult = yc
    filas.append(act)
    for f in filas:
        f.sort()
        toks = [w for _, w in f]
        if len(toks) >= 2 and re.fullmatch(r'\d{1,2}', toks[0]) and re.fullmatch(r'\d+\.\d\d', toks[-1]):
            oficial[int(toks[0])] = (' '.join(toks[1:-1]), float(toks[-1]))

etiquetas = []
for x0, y0, x1, y1, w, *_ in words:
    if (re.fullmatch(r'\d{1,2}', w) and (y1 - y0) > 9.5 and y1 < 975
            and not (x0 > 1275 and y0 > 678)):
        etiquetas.append((int(w), ((x0 + x1) / 2 - ox) * Z, ((y0 + y1) / 2 - oy) * Z))

CUADRADO = np.ones((3, 3), bool)
cache = {}
def etiquetado(ri, cierre_m):
    if (ri, cierre_m) not in cache:
        it = int(round(cierre_m / 2 / M_POR_PX))
        # Elemento CUADRADO: con la cruz por defecto de scipy las esquinas
        # de los recintos salían achaflanadas en diagonal.
        m = ndimage.binary_dilation(RASTERS[ri], structure=CUADRADO, iterations=it) if it else RASTERS[ri]
        cache[(ri, cierre_m)] = (ndimage.label(~m)[0], it)
    return cache[(ri, cierre_m)]

def region(px, py, cierre_m, ri=0):
    muros = RASTERS[ri]
    lab, it = etiquetado(ri, cierre_m)
    # Con el cierre de puertas los muros engordan y el número puede quedar
    # "dentro" del muro dilatado: se busca una semilla libre alrededor, pero
    # la región resultante debe contener el punto del número (si no, es el
    # cubículo vecino y se descarta).
    probados = set()
    for r in range(0, 90, 3):
        for dx, dy in ((r, 0), (-r, 0), (0, r), (0, -r), (r, r), (-r, -r)):
            yy, xx = int(py + dy), int(px + dx)
            if not (0 <= yy < H and 0 <= xx < W) or not lab[yy, xx] or lab[yy, xx] in probados:
                continue
            probados.add(lab[yy, xx])
            m = lab == lab[yy, xx]
            if it:
                m = ndimage.binary_dilation(m, structure=CUADRADO, iterations=it) & ~muros
                m = sin_tapones(m)
            if m[int(py), int(px)]:
                return m
    return None

def sin_tapones(m):
    """Quita el "tapón" que deja el cierre de puertas: al re-dilatar el
    recinto, en cada vano de puerta se mete ~0,4 m hacia el pasillo. Una
    apertura morfológica con un cuadrado de 0,6 m elimina esas lengüetas
    (más delgadas que el cuadrado) sin redondear las esquinas."""
    k = int(round(0.6 / M_POR_PX))
    ys, xs = np.nonzero(m)
    if len(ys) == 0:
        return m
    y0, y1 = max(ys.min() - k, 0), min(ys.max() + k + 1, H)
    x0, x1 = max(xs.min() - k, 0), min(xs.max() + k + 1, W)
    out = np.zeros_like(m)
    out[y0:y1, x0:x1] = ndimage.binary_opening(m[y0:y1, x0:x1], structure=np.ones((k, k), bool))
    return out

def rdp(pts, eps):
    if len(pts) < 3:
        return pts
    a, b = np.array(pts[0]), np.array(pts[-1])
    ab = b - a
    n = np.hypot(*ab) or 1e-9
    d = [abs(ab[0] * (q[1] - a[1]) - ab[1] * (q[0] - a[0])) / n for q in pts[1:-1]]
    i = int(np.argmax(d)) + 1
    if d[i - 1] > eps:
        return rdp(pts[:i + 1], eps)[:-1] + rdp(pts[i:], eps)
    return [pts[0], pts[-1]]

def poligono(mask):
    ys, xs = np.nonzero(mask)
    y0, y1, x0, x1 = ys.min() - 2, ys.max() + 3, xs.min() - 2, xs.max() + 3
    sub = np.pad(mask[max(y0, 0):y1, max(x0, 0):x1], 2).astype(float)
    y0, x0 = max(y0, 0) - 2, max(x0, 0) - 2
    lineas = contourpy.contour_generator(z=sub, line_type='Separate').lines(0.5)
    anillo = max(lineas, key=len)
    pts = [((x + x0) * M_POR_PX, (y + y0) * M_POR_PX) for x, y in anillo]
    # Anillo cerrado: RDP necesita extremos distintos, así que se parte en el
    # punto más lejano al inicio y se simplifica cada mitad.
    if pts[0] == pts[-1]:
        pts = pts[:-1]
    a = np.array(pts[0])
    k = int(np.argmax([np.hypot(*(np.array(q) - a)) for q in pts]))
    pts = rdp(pts[:k + 1], 0.12)[:-1] + rdp(pts[k:] + [pts[0]], 0.12)[:-1]
    return [[round(x, 2), round(y, 2)] for x, y in pts]

def tipo_de(nombre):
    n = nombre.upper()
    if 'SANIT' in n: return 'BANO'
    if 'ESCALERA' in n and 'VESTIBULO' not in n: return 'ESCALERA'
    if 'ELEVADOR' in n: return 'ASCENSOR'
    if 'PASILLO' in n or 'VESTIBULO' in n: return 'CIRCULACION'
    if 'LAB' in n or 'AULA' in n or 'INGENIERIA' in n: return 'SALON'
    if any(k in n for k in ('CUARTO', 'CTO.', 'PANELES', 'SERVIDORES', 'UPS')): return 'SERVICIO'
    if 'BALCON' in n: return 'BALCON'
    return 'OFICINA'

recintos, fallos, mascaras, pois_circ = [], [], [], []
for num, px, py in sorted(etiquetas):
    nombre, area_of = oficial.get(num, ('?', None))
    tipo = tipo_de(nombre)
    if tipo == 'CIRCULACION':
        # Pasillos y vestíbulos son abiertos (se escapan al exterior): se
        # resuelven abajo como huella del edificio menos recintos.
        pois_circ.append(dict(num=num, nombre=nombre, area_oficial_m2=area_of,
                              etiqueta=[round(px * M_POR_PX, 2), round(py * M_POR_PX, 2)]))
        continue
    mejor = None
    for ri in range(len(RASTERS)):
        for cierre in (1.0, 1.4, 2.0):
            m = region(px, py, cierre, ri)
            if m is None:
                continue
            area = m.sum() * M_POR_PX ** 2
            if area_of and abs(area / area_of - 1) <= 0.12:
                mejor = (m, area, cierre, ri); break
        if mejor:
            break
    if mejor is None:
        fallos.append((num, nombre, area_of, tipo,
                       [round(px * M_POR_PX, 2), round(py * M_POR_PX, 2)]))
        continue
    m, area, cierre, ri = mejor
    mascaras.append(m)
    cod =re.search(r'\b(\d-\d{3})\b', nombre) or re.search(r'\b(\d{3})\b', nombre)
    recintos.append(dict(num=num, codigo=cod.group(1) if cod else None, nombre=nombre,
                         tipo=tipo, area_oficial_m2=area_of, area_medida_m2=round(area, 2),
                         cierre_puertas_m=cierre, mascara='ABC'[ri],
                         etiqueta=[round(px * M_POR_PX, 2), round(py * M_POR_PX, 2)],
                         poligono=poligono(m)))

# Circulación = huella del edificio (cierre morfológico de 2,5 m sobre los
# muros, con huecos rellenos) − muros − recintos. Incluye las escaleras sin
# polígono propio, que quedan como áreas de circulación.
R_CIERRE = 2.5 / M_POR_PX
dil = ndimage.distance_transform_edt(~RASTERS[2]) < R_CIERRE   # incluye fachadas de vidrio
lleno = ndimage.binary_fill_holes(dil)
huella = ndimage.distance_transform_edt(lleno) >= R_CIERRE
ocupado = RASTERS[0].copy()
for m in mascaras:
    ocupado |= ndimage.binary_dilation(m, iterations=2)
# Exterior: lo conectado al borde del lienzo sobre el dibujo COMPLETO (incluye
# fachadas de vidrio y ventanas, que son trazos finos), con aberturas ≤ 1,2 m
# cerradas. Lo que toca el exterior no es circulación.
cerr = ndimage.distance_transform_edt(~RASTERS[2]) < (0.6 / M_POR_PX)
lab_e, _ = ndimage.label(~cerr)
bordes = set(np.unique(np.concatenate([lab_e[0], lab_e[-1], lab_e[:, 0], lab_e[:, -1]]))) - {0}
exterior = ndimage.binary_dilation(np.isin(lab_e, list(bordes)), iterations=int(0.6 / M_POR_PX) + 1)
circ = huella & ~ocupado & ~exterior
circ = ndimage.binary_opening(circ, iterations=4)   # quita astillas entre muros
lab_c, n_c = ndimage.label(circ)
tam_c = ndimage.sum(circ, lab_c, index=range(1, n_c + 1))
circulacion = []
for i, t in enumerate(tam_c, start=1):
    if t * M_POR_PX ** 2 < 2.0:
        continue
    mc = lab_c == i
    circulacion.append(dict(area_medida_m2=round(float(t) * M_POR_PX ** 2, 2),
                            poligono=poligono(mc)))

# ── 3. Nombres legibles ───────────────────────────────────────────────────────
# El cuadro oficial viene en MAYÚSCULAS y sin tildes; para la app se pasa a
# tipo oración restaurando las tildes de las palabras que aparecen.
TILDES = {'ROBOTICA': 'Robótica', 'PROGRAMACION': 'Programación', 'INGENIERIA': 'Ingeniería',
          'COMPUTACION': 'Computación', 'MOVIL': 'Móvil', 'DIRECCION': 'Dirección',
          'SECRETARIA': 'Secretaría', 'RECEPCION': 'Recepción', 'COMISION': 'Comisión',
          'RECTORIA': 'Rectoría', 'VICE-RECTORIA': 'Vicerrectoría', 'TECNICO': 'Técnico',
          'ELECTRICO': 'Eléctrico', 'BALCON': 'Balcón', 'MAESTRIAS': 'Maestrías',
          'PRODUCCION': 'Producción', 'COMPUTO': 'Cómputo', 'TECN.': 'Técn.',
          'INALAM.': 'Inalám.', 'VESTIBULO': 'Vestíbulo'}
MINUSCULAS = {'DE', 'LA', 'Y', 'DEL', 'EL', 'LOS', 'LAS'}
SIGLAS = {'A/A', 'UPS', 'CIDITIC', 'DIGITED', 'DIGITEC', 'DICOMES'}

def legible(texto):
    out = []
    for i, w in enumerate(texto.replace(',', '.').split()):
        # Separar paréntesis pegados: "(FAC." → "(" + "FAC."
        pre = re.match(r'^[(\[]*', w).group(0)
        post = re.search(r'[)\]]*$', w).group(0)
        core = w[len(pre):len(w) - len(post)] if post else w[len(pre):]
        if core in TILDES:
            t = TILDES[core]
        elif core.upper() in MINUSCULAS and i > 0:
            t = core.lower()
        elif re.fullmatch(r'[\d\-#°]+', core) or core in SIGLAS or core.startswith('N°'):
            t = core
        else:
            t = core.capitalize()
        out.append(pre + t + post)
    s = ' '.join(out)
    return s[:1].upper() + s[1:]

def presentar(num, nombre, tipo):
    """(codigo, nombre, etiqueta_corta) para la app a partir del nombre oficial."""
    n = nombre.strip()
    m = re.match(r'^(\d-\d{3})\s*(.*)$', n)
    codigo = None
    if m:
        codigo, n = m.group(1), m.group(2)
    m = re.match(r'^AULA\s*-\s*(\d{3})\s*(.*)$', n)
    if m:
        # "AULA - 429" del plano = salón 3-429 (nomenclatura E-P-NN, edificio 3).
        codigo, n = f'3-{m.group(1)}', ('Aula ' + m.group(2)).strip()
    n = n.strip()
    if n.startswith('(') and n.endswith(')'):
        n = n[1:-1].strip()
    if tipo == 'BANO':
        n = 'Baño de ' + ('damas' if 'DAMAS' in n.upper() else 'caballeros')
    nombre_app = legible(n) if tipo != 'BANO' else n
    if tipo == 'SALON' and codigo and nombre_app.lower() == 'aula':
        nombre_app = f'Aula {codigo}'
    corta = codigo
    if not corta:
        corta = {'BANO': 'Damas' if 'damas' in n else 'Caballeros', 'ESCALERA': 'Escalera',
                 'ASCENSOR': 'Ascensor', 'BALCON': 'Balcón', 'SERVICIO': None,
                 'SALON': 'Aula', 'OFICINA': 'Oficina'}[tipo]
        if tipo == 'SALON' and 'INTERACTIVA' in nombre.upper():
            corta = 'Aula interactiva'
    return codigo, nombre_app, corta

# ── 4. Escribir salidas ───────────────────────────────────────────────────────
Wpx, Hpx = int(ANCHO_M * PX_M), int(ALTO_M * PX_M)

def svg_trazos(con_rellenos):
    """SVG de la app: SOLO trazos, fondo transparente, color = currentColor
    (la app lo fija con SvgTheme según el tema claro/oscuro). Los rellenos de
    recintos y pasillos los dibuja la app desde el JSON. Con `con_rellenos`
    se genera la vista previa a color (solo para revisar, no va a la app)."""
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{Wpx}" height="{Hpx}" viewBox="0 0 {Wpx} {Hpx}">',
         f'<!-- FISC Edificio 3, piso 4 (tercer alto). Fuente: plano oficial UTP DGIA, 05 jun 2025, '
         f'1:250. Generado por tools/plano_oficial/extraer_plano.py. 100 px = 1 m. {ANCHO_M} x {ALTO_M} m. -->']
    if con_rellenos:
        COLOR = {'SALON': '#DCE8F5', 'OFICINA': '#E8E1F3', 'BANO': '#D7F0EA', 'ESCALERA': '#F6E3C8',
                 'ASCENSOR': '#F6E3C8', 'SERVICIO': '#E6E6E6', 'BALCON': '#EEF3E2'}
        s.append(f'<rect width="{Wpx}" height="{Hpx}" fill="#F4F1EA"/>')
        for c in circulacion:
            s.append('<polygon fill="#FFFFFF" points="' +
                     ' '.join(f'{x * PX_M:.0f},{y * PX_M:.0f}' for x, y in c['poligono']) + '"/>')
        for r in recintos:
            s.append(f'<polygon fill="{COLOR[r["tipo"]]}" points="' +
                     ' '.join(f'{x * PX_M:.0f},{y * PX_M:.0f}' for x, y in r['poligono']) + '"/>')
    color = '#2E3440' if con_rellenos else 'currentColor'
    s.append(f'<path id="ventanas" fill="none" stroke="{color}" stroke-opacity="0.28" stroke-width="3" '
             f'd="{"".join(paths["ventana"])}"/>')
    s.append(f'<path id="detalle" fill="none" stroke="{color}" stroke-opacity="0.45" stroke-width="3" '
             f'd="{"".join(paths["detalle"])}"/>')
    s.append(f'<path id="muros" fill="none" stroke="{color}" stroke-width="12" stroke-linecap="square" '
             f'd="{"".join(paths["muro"])}"/>')
    s.append(f'<path id="columnas" fill="{color}" stroke="{color}" stroke-width="6" '
             f'd="{"".join(paths["columna"] + rellenos)}"/>')
    s.append('</svg>')
    return '\n'.join(s)

open(f'{OUT}/fisc_piso4_oficial.svg', 'w', encoding='utf-8').write(svg_trazos(False))
open(f'{OUT}/fisc_piso4_oficial_preview.svg', 'w', encoding='utf-8').write(svg_trazos(True))

ids_usados = {}
def id_unico(num):
    ids_usados[num] = ids_usados.get(num, 0) + 1
    return f'r{num}' if ids_usados[num] == 1 else f'r{num}-{ids_usados[num]}'

salida = []
for r in recintos:
    codigo, nombre_app, corta = presentar(r['num'], r['nombre'], r['tipo'])
    salida.append(dict(id=id_unico(r['num']), codigo=codigo, nombre=nombre_app,
                       nombre_oficial=r['nombre'], tipo=r['tipo'], etiqueta_corta=corta,
                       area_m2=r['area_oficial_m2'], etiqueta=r['etiqueta'],
                       poligono=r['poligono'], nodo_id=None))
for num, nombre, area_of, tipo, etq in fallos:
    # Sin polígono confiable (escaleras, ascensor, cuartitos con muebles): se
    # publican igual para que la app muestre su etiqueta; no se pueden tocar.
    codigo, nombre_app, corta = presentar(num, nombre, tipo)
    salida.append(dict(id=id_unico(num), codigo=codigo, nombre=nombre_app, nombre_oficial=nombre,
                       tipo=tipo, etiqueta_corta=corta, area_m2=area_of, etiqueta=etq,
                       poligono=[], nodo_id=None))
salida.sort(key=lambda r: int(re.match(r'r(\d+)', r['id']).group(1)))

json.dump(dict(version='1.0',
               fuente='Plano oficial UTP DGIA - CVLS Edificio #3 Tercer Alto (05 jun 2025), esc. 1:250',
               generado_por='tools/plano_oficial/extraer_plano.py',
               mapa_ancho_metros=ANCHO_M, mapa_alto_metros=ALTO_M,
               recintos=salida,
               circulacion=[c['poligono'] for c in circulacion]),
          open(f'{OUT}/fisc_piso4_oficial.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)

# ── 5. Reporte de verificación ────────────────────────────────────────────────
print('mapa', ANCHO_M, 'x', ALTO_M, 'm  (', Wpx, 'x', Hpx, 'px)')
print('recintos con polígono', len(recintos), ' sin polígono', len(fallos))
for f in fallos:
    print('  sin polígono:', f[0], f[1])
area_circ_of = sum({p['num']: p['area_oficial_m2'] or 0 for p in pois_circ}.values())
print('circulación medida', round(sum(c['area_medida_m2'] for c in circulacion), 1),
      'm²  (oficial pasillo + vestíbulos:', area_circ_of, ')')
desv = [abs(r['area_medida_m2'] / r['area_oficial_m2'] - 1) for r in recintos if r['area_oficial_m2']]
print('desviación de área vs. cuadro oficial: mediana', round(float(np.median(desv)) * 100, 2),
      '%  máx', round(max(desv) * 100, 2), '%')
