import 'package:flutter/material.dart';

/// All app colours, in a light (default) and a dark "case-file noir" version.
/// Read them with `context.k` (e.g. `context.k.text`); painters receive a Palette.
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.dark,
    required this.bg,
    required this.surface,
    required this.card,
    required this.line,
    required this.text,
    required this.muted,
    required this.accent,
    required this.onAccent,
    required this.paper,
    required this.ink,
    required this.string,
    required this.rising,
    required this.falling,
    required this.confirmed,
    required this.likely,
    required this.notProven,
    required this.artifact,
    required this.ocean,
    required this.land,
    required this.coast,
    required this.grid,
  });

  final bool dark;
  final Color bg, surface, card, line, text, muted, accent, onAccent;
  final Color paper, ink; // manila evidence cards (same look in both modes)
  final Color string; // the detective's red string
  final Color rising, falling, confirmed, likely, notProven, artifact;
  final Color ocean, land, coast, grid;

  static const light = Palette(
    dark: false,
    bg: Color(0xFFF5F6FA),
    surface: Color(0xFFEEF1F6),
    card: Color(0xFFFFFFFF),
    line: Color(0xFFD9DEE7),
    text: Color(0xFF1B2433),
    muted: Color(0xFF5F6B7E),
    accent: Color(0xFF9A3412),
    onAccent: Color(0xFFFFFFFF),
    paper: Color(0xFFF6E7BE),
    ink: Color(0xFF2B2118),
    string: Color(0xFFD62839),
    rising: Color(0xFFE8590C),
    falling: Color(0xFF0F8F82),
    confirmed: Color(0xFF2E8B57),
    likely: Color(0xFFC98A00),
    notProven: Color(0xFF6B7385),
    artifact: Color(0xFFD62839),
    ocean: Color(0xFFDCE8F3),
    land: Color(0xFFEFEADF),
    coast: Color(0xFFA9B6C6),
    grid: Color(0xFFC6D4E3),
  );

  static const darkPalette = Palette(
    dark: true,
    bg: Color(0xFF0B1220),
    surface: Color(0xFF121B2D),
    card: Color(0xFF17233A),
    line: Color(0xFF27344D),
    text: Color(0xFFE8EDF5),
    muted: Color(0xFF93A0B8),
    accent: Color(0xFFF2E2B6),
    onAccent: Color(0xFF2B2118),
    paper: Color(0xFFF2E2B6),
    ink: Color(0xFF2B2118),
    string: Color(0xFFE63946),
    rising: Color(0xFFFF8A4C),
    falling: Color(0xFF2EC4B6),
    confirmed: Color(0xFF3BB273),
    likely: Color(0xFFF4B942),
    notProven: Color(0xFF8A94A6),
    artifact: Color(0xFFE63946),
    ocean: Color(0xFF0E2238),
    land: Color(0xFF233752),
    coast: Color(0xFF3E5677),
    grid: Color(0xFF27344D),
  );

  Color verdict(String code) {
    switch (code) {
      case 'confirmed':
        return confirmed;
      case 'likely':
        return likely;
      case 'artifact':
        return artifact;
      case 'not_proven':
        return notProven;
      default:
        return muted;
    }
  }

  Color caseVerdict(String code) {
    switch (code) {
      case 'shared_strong':
        return confirmed;
      case 'shared_weak':
        return likely;
      case 'other_cause':
        return rising;
      default:
        return notProven;
    }
  }

  Color check(String status) {
    switch (status) {
      case 'pass':
        return confirmed;
      case 'warn':
        return likely;
      case 'fail':
        return artifact;
      default:
        return notProven;
    }
  }

  Color signColor(num sign) => sign >= 0 ? rising : falling;

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(ThemeExtension<Palette>? other, double t) {
    if (other is! Palette) return this;
    return t < 0.5 ? this : other;
  }
}

extension PaletteContext on BuildContext {
  Palette get k => Theme.of(this).extension<Palette>() ?? Palette.light;
}

ThemeData buildTheme(Palette p) {
  final brightness = p.dark ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme.fromSeed(seedColor: p.string, brightness: brightness).copyWith(
    surface: p.surface,
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.falling,
    error: p.artifact,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    extensions: [p],
    appBarTheme: AppBarTheme(backgroundColor: p.bg, foregroundColor: p.text, elevation: 0, centerTitle: false),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      indicatorColor: p.string.withValues(alpha: 0.22),
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12, color: p.text)),
    ),
    navigationRailTheme: NavigationRailThemeData(backgroundColor: p.surface),
    chipTheme: ChipThemeData(
      backgroundColor: p.card,
      selectedColor: p.string.withValues(alpha: 0.25),
      labelStyle: TextStyle(color: p.text, fontSize: 13),
      side: BorderSide(color: p.line),
    ),
    dividerTheme: DividerThemeData(color: p.line, space: 24),
    textTheme: TextTheme(
      headlineSmall: TextStyle(fontWeight: FontWeight.w800, color: p.text, letterSpacing: 0.2),
      titleLarge: TextStyle(fontWeight: FontWeight.w800, color: p.text),
      titleMedium: TextStyle(fontWeight: FontWeight.w700, color: p.text),
      bodyMedium: TextStyle(color: p.text, height: 1.35),
      bodySmall: TextStyle(color: p.muted, height: 1.3),
    ),
  );
}
