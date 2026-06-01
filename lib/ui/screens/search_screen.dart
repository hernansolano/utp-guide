import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/repositories/grafo_repository.dart';
import '../../models/nodo.dart';
import '../../models/perfil_movilidad.dart';
import '../../models/tipo_nodo.dart';
import '../theme/app_theme.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/destination_row.dart';

class SearchScreen extends StatefulWidget {
  final GrafoRepository grafoRepository;

  /// Si está activo, las rutas calculadas serán accesibles (sin escaleras).
  /// Se inyecta desde `main.dart`; el toggle vive en SettingsScreen.
  final ValueNotifier<bool> accesibleSoloRutasNotifier;

  /// Filtro inicial preseleccionado al abrir la pantalla. Si es `null`,
  /// arranca con "Todos". Usado por los quick tiles de HomeScreen para
  /// llegar directo a la lista filtrada (ej: tap en "Salones" abre
  /// SearchScreen con `TipoNodo.salon` ya activo).
  final TipoNodo? tipoFiltroInicial;

  const SearchScreen({
    super.key,
    required this.grafoRepository,
    required this.accesibleSoloRutasNotifier,
    this.tipoFiltroInicial,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late Future<List<Nodo>> _nodosFuture;
  final _controller = TextEditingController();
  String _query = '';
  TipoNodo? _tipoFiltro;
  bool _soloAccesibles = false;

  @override
  void initState() {
    super.initState();
    _nodosFuture = widget.grafoRepository.obtenerNodos();
    _tipoFiltro = widget.tipoFiltroInicial;
  }

  static const _chips = [
    _Chip('Todos', null),
    _Chip('Salones', TipoNodo.salon),
    _Chip('Servicios', TipoNodo.bano),
    _Chip('Oficinas', TipoNodo.oficina),
    _Chip('Ascensores', TipoNodo.ascensor),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Nodo> _filtrar(List<Nodo> todos) {
    return todos.where((n) {
      if (_soloAccesibles && !n.accesible) return false;
      if (_tipoFiltro != null && n.tipo != _tipoFiltro) return false;
      if (_query.isNotEmpty &&
          !n.nombre.toLowerCase().contains(_query.toLowerCase())) {
        return false;
      }
      // Ocultar intersecciones y marcadores AR del buscador
      if (n.tipo == TipoNodo.interseccion || n.tipo == TipoNodo.marcadorAr) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.bg,
      body: Column(
        children: [
          _buildSearchBar(context, colors),
          _buildFilterChips(context, colors),
          Expanded(
            child: FutureBuilder<List<Nodo>>(
              future: _nodosFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'Error al cargar destinos',
                      style: GoogleFonts.plusJakartaSans(
                          color: colors.fgMuted),
                    ),
                  );
                }
                final todos = snap.data!;
                final filtrados = _filtrar(todos);
                return _buildResults(context, colors, todos, filtrados);
              },
            ),
          ),
          BottomNavWidget(
            activeTab: 'search',
            onTabChanged: (tab) {
              if (tab == 'home') context.go('/');
              if (tab == 'settings') context.push('/settings');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, AppColors colors) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 14, 20, 14),
      child: Row(
        children: [
          IconButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/'),
            icon: Icon(Icons.arrow_back_rounded, color: colors.fg),
            style: IconButton.styleFrom(
              backgroundColor: colors.bgSoft,
              shape: const CircleBorder(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.brand, width: 2),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  Icon(Icons.search_rounded,
                      color: colors.brand, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      onChanged: (v) => setState(() => _query = v),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colors.fg,
                      ),
                      // No usar InputDecoration.collapsed porque solo
                      // suprime `border`, no las variantes (enabledBorder,
                      // focusedBorder, etc.) que se heredan del tema y
                      // pintan una segunda outline brand sobre el Container.
                      // Setear todas explícitamente a InputBorder.none.
                      decoration: InputDecoration(
                        isCollapsed: true,
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        hintText: '¿A dónde quieres ir?',
                        hintStyle: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: colors.fgSoft,
                        ),
                      ),
                    ),
                  ),
                  if (_query.isNotEmpty)
                    IconButton(
                      onPressed: () {
                        _controller.clear();
                        setState(() => _query = '');
                      },
                      icon: Icon(Icons.close_rounded,
                          color: colors.fgSoft, size: 18),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(BuildContext context, AppColors colors) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _buildChip(context, colors, 'Solo accesibles', null,
              isAccessible: true),
          ..._chips.map((c) => _buildChip(context, colors, c.label, c.tipo)),
        ],
      ),
    );
  }

  Widget _buildChip(
    BuildContext context,
    AppColors colors,
    String label,
    TipoNodo? tipo, {
    bool isAccessible = false,
  }) {
    final active = isAccessible ? _soloAccesibles : _tipoFiltro == tipo;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() {
          if (isAccessible) {
            _soloAccesibles = !_soloAccesibles;
          } else {
            _tipoFiltro = active ? null : tipo;
          }
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: active ? colors.brand : colors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? colors.brand : colors.lineStrong,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isAccessible) ...[
                Icon(Icons.accessible_rounded,
                    size: 14,
                    color: active ? Colors.white : colors.fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : colors.fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context, AppColors colors,
      List<Nodo> todos, List<Nodo> filtrados) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      children: [
        if (_query.isEmpty && _tipoFiltro == null && !_soloAccesibles) ...[
          _sectionLabel('Todos los destinos', colors),
        ] else ...[
          _sectionLabel(
              '${filtrados.length} resultado${filtrados.length != 1 ? 's' : ''}',
              colors),
        ],
        if (filtrados.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                'Sin resultados para "$_query".',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: colors.fgMuted,
                ),
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (int i = 0; i < filtrados.length; i++)
                  DestinationRow(
                    nodo: filtrados[i],
                    showDivider: i < filtrados.length - 1,
                    onTap: () => _navegarA(context, filtrados[i]),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _sectionLabel(String text, AppColors colors) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.06 * 12,
            color: colors.fgSoft,
          ),
        ),
      );

  void _navegarA(BuildContext context, Nodo nodo) {
    // El perfil se decide en este momento (no en MapaScreen) para que la
    // navegación quede congelada con el perfil activo al hacer la búsqueda.
    // Si el usuario cambia el toggle después, la ruta actual no se altera;
    // solo afecta búsquedas futuras.
    final perfil = widget.accesibleSoloRutasNotifier.value
        ? PerfilMovilidad.accesible
        : PerfilMovilidad.estandar;

    context.push('/mapa', extra: {
      'destinoId': nodo.id,
      'perfil': perfil.name,
    });
  }
}

class _Chip {
  final String label;
  final TipoNodo? tipo;
  const _Chip(this.label, this.tipo);
}
