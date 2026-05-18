import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../data/repositories/grafo_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/quick_tile.dart';

class HomeScreen extends StatefulWidget {
  final GrafoRepository grafoRepository;

  const HomeScreen({super.key, required this.grafoRepository});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.bg,
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _buildHeader(context, colors),
                ),
                SliverToBoxAdapter(
                  child: _buildGreeting(context, colors),
                ),
                SliverToBoxAdapter(
                  child: _buildSearchBar(context, colors),
                ),
                SliverToBoxAdapter(
                  child: _buildMapPreview(context, colors),
                ),
                SliverToBoxAdapter(
                  child: _buildQuickTiles(context, colors),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
              ],
            ),
          ),
          BottomNavWidget(
            activeTab: 'home',
            onTabChanged: _onTabChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppColors colors) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 16, 20, 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.line),
            ),
            padding: const EdgeInsets.all(6),
            child: Image.asset(
              'assets/maps/logo-utp-color.png',
              fit: BoxFit.contain,
              errorBuilder: (ctx, e, s) => Icon(
                Icons.school_rounded,
                color: colors.brand,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FISC · UTP',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.08 * 11,
                    color: colors.fgSoft,
                  ),
                ),
                Text(
                  'UTP-Guide',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.01 * 18,
                    color: colors.fg,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => context.push('/settings'),
            icon: Icon(Icons.settings_outlined, color: colors.fgSoft),
            style: IconButton.styleFrom(
              backgroundColor: colors.bgSoft,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGreeting(BuildContext context, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '¿A dónde\nquieres ir hoy?',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.01 * 26,
              color: colors.fg,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              text: 'Estás en ',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colors.fgMuted,
              ),
              children: [
                TextSpan(
                  text: 'Edificio FISC · Planta baja',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    color: colors.fg,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: GestureDetector(
        onTap: () => context.push('/search'),
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: colors.bgSoft,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, color: colors.fgSoft, size: 20),
              const SizedBox(width: 12),
              Text(
                '¿A dónde quieres ir?',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: colors.fgSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapPreview(BuildContext context, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: colors.bgMuted,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SvgPicture.asset(
              'assets/maps/test_room_5x5.svg',
              fit: BoxFit.cover,
            ),
            // Floor label pill
            Positioned(
              left: 12,
              top: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.surfaceElevated.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'FISC · PILOTO',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.06 * 11,
                    color: colors.brand,
                  ),
                ),
              ),
            ),
            // Open map button
            Positioned(
              right: 12,
              bottom: 12,
              child: GestureDetector(
                onTap: () => context.push('/search'),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.map_outlined,
                          color: colors.brand, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'Abrir mapa',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.brand,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickTiles(BuildContext context, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 1.15,
        children: [
          QuickTile(
            icon: Icons.school_outlined,
            label: 'Salones',
            sub: 'Aulas y laboratorios',
            onTap: () => context.push('/search'),
          ),
          QuickTile(
            icon: Icons.business_outlined,
            label: 'Oficinas',
            sub: 'Decanato, admisión',
            onTap: () => context.push('/search'),
          ),
          QuickTile(
            icon: Icons.wc_outlined,
            label: 'Servicios',
            sub: 'Cada piso',
            onTap: () => context.push('/search'),
          ),
          QuickTile(
            icon: Icons.door_front_door_outlined,
            label: 'Salidas',
            sub: 'Emergencia',
            tone: TileTone.danger,
            onTap: () => context.push('/search'),
          ),
        ],
      ),
    );
  }

  void _onTabChanged(String tab) {
    switch (tab) {
      case 'search':
        context.push('/search');
      case 'settings':
        context.push('/settings');
      case 'map':
        context.push('/search');
      default:
        break;
    }
  }
}
