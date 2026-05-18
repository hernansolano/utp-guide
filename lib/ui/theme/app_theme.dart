import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Design Tokens ────────────────────────────────────────────────────────────
// Source: utp-guide-design-system / colors_and_type.css
// Primary: UTP Wayfinding Blue #003087 (brand-600)
// Font: Plus Jakarta Sans (Google Fonts)
// ──────────────────────────────────────────────────────────────────────────────

class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.brand,
    required this.brandSoft,
    required this.bg,
    required this.bgSoft,
    required this.bgMuted,
    required this.surface,
    required this.surfaceElevated,
    required this.line,
    required this.lineStrong,
    required this.fg,
    required this.fgMuted,
    required this.fgSoft,
    required this.fgDisabled,
    required this.route,
    required this.destination,
    required this.accessible,
    required this.danger,
    required this.dangerBg,
    required this.success,
    required this.successBg,
    required this.floorFill,
    required this.corridorFill,
  });

  final Color brand;
  final Color brandSoft;
  final Color bg;
  final Color bgSoft;
  final Color bgMuted;
  final Color surface;
  final Color surfaceElevated;
  final Color line;
  final Color lineStrong;
  final Color fg;
  final Color fgMuted;
  final Color fgSoft;
  final Color fgDisabled;
  final Color route;
  final Color destination;
  final Color accessible;
  final Color danger;
  final Color dangerBg;
  final Color success;
  final Color successBg;
  final Color floorFill;
  final Color corridorFill;

  static const light = AppColors(
    brand: Color(0xFF003087),
    brandSoft: Color(0xFFEAF0FB),
    bg: Color(0xFFFFFFFF),
    bgSoft: Color(0xFFF6F7FB),
    bgMuted: Color(0xFFECEFF6),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFFFFFFF),
    line: Color(0xFFE3E7F0),
    lineStrong: Color(0xFFC8D0DE),
    fg: Color(0xFF0E1530),
    fgMuted: Color(0xFF4B5573),
    fgSoft: Color(0xFF7B8499),
    fgDisabled: Color(0xFFB7BECC),
    route: Color(0xFF003087),
    destination: Color(0xFFE52713),
    accessible: Color(0xFF1B7F4D),
    danger: Color(0xFFE52713),
    dangerBg: Color(0xFFFCE6E3),
    success: Color(0xFF1B7F4D),
    successBg: Color(0xFFE6F4EC),
    floorFill: Color(0xFFDCE2EE),
    corridorFill: Color(0xFFF6F7FB),
  );

  static const dark = AppColors(
    brand: Color(0xFF7AA0F5),
    brandSoft: Color(0x1F7AA0F5),
    bg: Color(0xFF0B1024),
    bgSoft: Color(0xFF131A33),
    bgMuted: Color(0xFF0E1428),
    surface: Color(0xFF161E3B),
    surfaceElevated: Color(0xFF1C2547),
    line: Color(0xFF28315A),
    lineStrong: Color(0xFF3A4576),
    fg: Color(0xFFECF0FA),
    fgMuted: Color(0xFFA8B2CF),
    fgSoft: Color(0xFF6F7B9C),
    fgDisabled: Color(0xFF4A5478),
    route: Color(0xFF7AA0F5),
    destination: Color(0xFFFF6B57),
    accessible: Color(0xFF34C77B),
    danger: Color(0xFFFF6B57),
    dangerBg: Color(0x2EFF6B57),
    success: Color(0xFF34C77B),
    successBg: Color(0x2134C77B),
    floorFill: Color(0xFF1F2A4C),
    corridorFill: Color(0xFF131B36),
  );

  @override
  AppColors copyWith({
    Color? brand,
    Color? brandSoft,
    Color? bg,
    Color? bgSoft,
    Color? bgMuted,
    Color? surface,
    Color? surfaceElevated,
    Color? line,
    Color? lineStrong,
    Color? fg,
    Color? fgMuted,
    Color? fgSoft,
    Color? fgDisabled,
    Color? route,
    Color? destination,
    Color? accessible,
    Color? danger,
    Color? dangerBg,
    Color? success,
    Color? successBg,
    Color? floorFill,
    Color? corridorFill,
  }) =>
      AppColors(
        brand: brand ?? this.brand,
        brandSoft: brandSoft ?? this.brandSoft,
        bg: bg ?? this.bg,
        bgSoft: bgSoft ?? this.bgSoft,
        bgMuted: bgMuted ?? this.bgMuted,
        surface: surface ?? this.surface,
        surfaceElevated: surfaceElevated ?? this.surfaceElevated,
        line: line ?? this.line,
        lineStrong: lineStrong ?? this.lineStrong,
        fg: fg ?? this.fg,
        fgMuted: fgMuted ?? this.fgMuted,
        fgSoft: fgSoft ?? this.fgSoft,
        fgDisabled: fgDisabled ?? this.fgDisabled,
        route: route ?? this.route,
        destination: destination ?? this.destination,
        accessible: accessible ?? this.accessible,
        danger: danger ?? this.danger,
        dangerBg: dangerBg ?? this.dangerBg,
        success: success ?? this.success,
        successBg: successBg ?? this.successBg,
        floorFill: floorFill ?? this.floorFill,
        corridorFill: corridorFill ?? this.corridorFill,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      brand: Color.lerp(brand, other.brand, t)!,
      brandSoft: Color.lerp(brandSoft, other.brandSoft, t)!,
      bg: Color.lerp(bg, other.bg, t)!,
      bgSoft: Color.lerp(bgSoft, other.bgSoft, t)!,
      bgMuted: Color.lerp(bgMuted, other.bgMuted, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated:
          Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      line: Color.lerp(line, other.line, t)!,
      lineStrong: Color.lerp(lineStrong, other.lineStrong, t)!,
      fg: Color.lerp(fg, other.fg, t)!,
      fgMuted: Color.lerp(fgMuted, other.fgMuted, t)!,
      fgSoft: Color.lerp(fgSoft, other.fgSoft, t)!,
      fgDisabled: Color.lerp(fgDisabled, other.fgDisabled, t)!,
      route: Color.lerp(route, other.route, t)!,
      destination: Color.lerp(destination, other.destination, t)!,
      accessible: Color.lerp(accessible, other.accessible, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerBg: Color.lerp(dangerBg, other.dangerBg, t)!,
      success: Color.lerp(success, other.success, t)!,
      successBg: Color.lerp(successBg, other.successBg, t)!,
      floorFill: Color.lerp(floorFill, other.floorFill, t)!,
      corridorFill: Color.lerp(corridorFill, other.corridorFill, t)!,
    );
  }
}

// ─── AppTheme ─────────────────────────────────────────────────────────────────

class AppTheme {
  static TextTheme get _textTheme => GoogleFonts.plusJakartaSansTextTheme();

  static ThemeData get light => _build(
        colors: AppColors.light,
        brightness: Brightness.light,
      );

  static ThemeData get dark => _build(
        colors: AppColors.dark,
        brightness: Brightness.dark,
      );

  static ThemeData _build({
    required AppColors colors,
    required Brightness brightness,
  }) =>
      ThemeData(
        useMaterial3: true,
        brightness: brightness,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF003087),
          brightness: brightness,
          primary: colors.brand,
          onPrimary: Colors.white,
          surface: colors.surface,
          onSurface: colors.fg,
          surfaceContainerHighest: colors.bgSoft,
          outline: colors.line,
        ),
        scaffoldBackgroundColor: colors.bg,
        textTheme: _textTheme.apply(
          bodyColor: colors.fg,
          displayColor: colors.fg,
        ),
        extensions: [colors],
        appBarTheme: AppBarTheme(
          backgroundColor: colors.surface,
          foregroundColor: colors.fg,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: GoogleFonts.plusJakartaSans(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.fg,
            letterSpacing: -0.01 * 18,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.brand,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: const StadiumBorder(),
            textStyle: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: colors.bgSoft,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: colors.brand, width: 2),
          ),
          hintStyle: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: colors.fgSoft,
          ),
        ),
        dividerColor: colors.line,
        dividerTheme: DividerThemeData(color: colors.line, space: 1),
      );
}

// ─── Convenience extension ────────────────────────────────────────────────────

extension AppColorsX on BuildContext {
  AppColors get colors =>
      Theme.of(this).extension<AppColors>() ?? AppColors.light;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
