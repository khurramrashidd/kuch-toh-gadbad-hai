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
    bg: Color(0xFFF0F5FC),
    surface: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    line: Color(0xFFD3DFEE),
    text: Color(0xFF0B1F3A),
    muted: Color(0xFF52647D),
    accent: Color(0xFF1A56DB),
    onAccent: Color(0xFFFFFFFF),
    paper: Color(0xFFF6E7BE),
    ink: Color(0xFF2B2118),
    string: Color(0xFFE5484D),
    rising: Color(0xFFF2711C),
    falling: Color(0xFF0E9F8E),
    confirmed: Color(0xFF1F9D55),
    likely: Color(0xFFD99A00),
    notProven: Color(0xFFC27C00),
    artifact: Color(0xFFE5484D),
    ocean: Color(0xFFCFE6F7),
    land: Color(0xFFE6EEDD),
    coast: Color(0xFF8FA9B8),
    grid: Color(0xFFB9D3E8),
  );

  static const darkPalette = Palette(
    dark: true,
    bg: Color(0xFF081226),
    surface: Color(0xFF0D1A33),
    card: Color(0xFF13233F),
    line: Color(0xFF24385A),
    text: Color(0xFFE8EFF9),
    muted: Color(0xFF9AAAC4),
    accent: Color(0xFF6FA8FF),
    onAccent: Color(0xFF07122A),
    paper: Color(0xFFF2E2B6),
    ink: Color(0xFF2B2118),
    string: Color(0xFFFF6B6B),
    rising: Color(0xFFFF9A52),
    falling: Color(0xFF2DD4BF),
    confirmed: Color(0xFF34C77B),
    likely: Color(0xFFF4B942),
    notProven: Color(0xFFE9A43A),
    artifact: Color(0xFFFF6B6B),
    ocean: Color(0xFF0C2A4A),
    land: Color(0xFF244A45),
    coast: Color(0xFF4C7C8C),
    grid: Color(0xFF1F3B5C),
  );

  // ---- Earth & Space brand colours -------------------------------------------------------
  /// Header / hero gradient: deep space blue into ocean teal.
  List<Color> get brand => dark ? const [Color(0xFF0A1A44), Color(0xFF0B4F5E)] : const [Color(0xFF0B2A6F), Color(0xFF0E7490)];
  Color get sun => dark ? const Color(0xFFFFB454) : const Color(0xFFF59E0B);
  Color get violet => dark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED);
  Color get probable => dark ? const Color(0xFFA3D139) : const Color(0xFF5C9A0F);

  /// One colour per Earth sphere, used on chips, cards and filters everywhere.
  Color sphere(String s) {
    switch (s) {
      case 'atmosphere':
        return dark ? const Color(0xFF5CB8FF) : const Color(0xFF2F8FE0);
      case 'hydrosphere':
        return falling;
      case 'cryosphere':
        return dark ? const Color(0xFF67E8F9) : const Color(0xFF0FA5C2);
      case 'biosphere':
        return dark ? const Color(0xFFA3D139) : const Color(0xFF5C9A0F);
      case 'anthroposphere':
        return violet;
      case 'ocean':
        return accent;
      default: // land, lithosphere, geosphere
        return dark ? const Color(0xFF4ADE80) : const Color(0xFF2E8B57);
    }
  }

  /// One colour per main tab: Investigate, Cases, My place, Explore, Lab.
  Color tab(int i) => [accent, rising, confirmed, falling, violet][i.clamp(0, 4)];

  /// The same palette for content drawn on the brand gradient (white text and icons).
  Palette onBrand() => Palette(
        dark: true,
        bg: bg,
        surface: surface,
        card: card,
        line: Colors.white.withValues(alpha: 0.25),
        text: Colors.white,
        muted: Colors.white.withValues(alpha: 0.82),
        accent: Colors.white,
        onAccent: brand.first,
        paper: paper,
        ink: ink,
        string: string,
        rising: const Color(0xFFFFC078),
        falling: falling,
        confirmed: confirmed,
        likely: likely,
        notProven: notProven,
        artifact: artifact,
        ocean: ocean,
        land: land,
        coast: coast,
        grid: grid,
      );

  Color verdict(String code) {
    switch (code) {
      case 'confirmed':
        return confirmed;
      case 'likely':
        return probable;
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
        return probable;
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

/// Spacing scale (use these instead of ad-hoc numbers in new code).
class Sp {
  static const double xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32, xxxl = 48;
}

/// Corner radius scale: controls 10, cards 12, large containers 16.
class Rd {
  static const double control = 12, card = 16, large = 20;
}

/// Rounded, friendly heading font (bundled, SIL Open Font License).
const kHeadFont = 'Nunito';

ThemeData buildTheme(Palette p) {
  final brightness = p.dark ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme.fromSeed(seedColor: p.accent, brightness: brightness).copyWith(
    surface: p.surface,
    onSurface: p.text,
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.falling,
    error: p.artifact,
    outline: p.line,
    outlineVariant: p.line,
    surfaceContainerHighest: p.bg,
  );
  final control = RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rd.control));
  const minTouch = Size(48, 46);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    extensions: [p],
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: p.surface,
      foregroundColor: p.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(color: p.text, fontSize: 19, fontWeight: FontWeight.w800, fontFamily: kHeadFont),
      shape: Border(bottom: BorderSide(color: p.line)),
    ),
    cardTheme: CardThemeData(
      color: p.card,
      elevation: p.dark ? 0 : 2,
      shadowColor: const Color(0xFF1A56DB).withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rd.card), side: BorderSide(color: p.line.withValues(alpha: p.dark ? 1 : 0.7))),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: minTouch, shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, fontFamily: kHeadFont)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: minTouch, shape: const StadiumBorder(), side: BorderSide(color: p.accent.withValues(alpha: 0.55), width: 1.4), foregroundColor: p.accent, textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, fontFamily: kHeadFont)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(44, 44), shape: control, foregroundColor: p.accent, textStyle: const TextStyle(fontWeight: FontWeight.w700)),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(44, 44))),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(control),
        side: WidgetStatePropertyAll(BorderSide(color: p.line)),
        backgroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? p.accent : p.card),
        foregroundColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? p.onAccent : p.text),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: p.accent,
      iconTheme: WidgetStateProperty.resolveWith((st) => IconThemeData(color: st.contains(WidgetState.selected) ? p.onAccent : p.muted)),
      labelTextStyle: WidgetStateProperty.resolveWith(
          (st) => TextStyle(fontSize: 11.5, fontWeight: st.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600, color: st.contains(WidgetState.selected) ? p.accent : p.muted)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: p.surface,
      indicatorColor: p.accent,
      selectedIconTheme: IconThemeData(color: p.onAccent),
      unselectedIconTheme: IconThemeData(color: p.muted),
      selectedLabelTextStyle: TextStyle(color: p.accent, fontWeight: FontWeight.w800, fontSize: 12),
      unselectedLabelTextStyle: TextStyle(color: p.muted, fontWeight: FontWeight.w600, fontSize: 12),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.card,
      selectedColor: p.accent.withValues(alpha: 0.18),
      checkmarkColor: p.accent,
      labelStyle: TextStyle(color: p.text, fontSize: 13, fontWeight: FontWeight.w600),
      side: BorderSide(color: p.line),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Rd.control), borderSide: BorderSide(color: p.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Rd.control), borderSide: BorderSide(color: p.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Rd.control), borderSide: BorderSide(color: p.accent, width: 1.6)),
    ),
    sliderTheme: SliderThemeData(activeTrackColor: p.accent, thumbColor: p.accent, inactiveTrackColor: p.line, overlayColor: p.accent.withValues(alpha: 0.12)),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent, linearTrackColor: p.line),
    switchTheme: SwitchThemeData(trackColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? p.accent : p.line)),
    dialogTheme: DialogThemeData(backgroundColor: p.card, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rd.large))),
    popupMenuTheme: PopupMenuThemeData(color: p.card, surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Rd.card), side: BorderSide(color: p.line))),
    snackBarTheme: SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: control, backgroundColor: p.dark ? p.card : const Color(0xFF0F1B2D), contentTextStyle: const TextStyle(color: Colors.white)),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: p.dark ? const Color(0xFF26324A) : const Color(0xFF0F1B2D), borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12.5),
      waitDuration: const Duration(milliseconds: 400),
    ),
    listTileTheme: ListTileThemeData(iconColor: p.muted, textColor: p.text),
    expansionTileTheme: ExpansionTileThemeData(iconColor: p.accent, collapsedIconColor: p.muted, textColor: p.text, collapsedTextColor: p.text),
    dividerTheme: DividerThemeData(color: p.line, space: 24, thickness: 1),
    focusColor: p.accent.withValues(alpha: 0.16),
    textTheme: TextTheme(
      headlineMedium: TextStyle(fontFamily: kHeadFont, fontWeight: FontWeight.w800, color: p.text, fontSize: 28, height: 1.15, letterSpacing: -0.4),
      headlineSmall: TextStyle(fontFamily: kHeadFont, fontWeight: FontWeight.w800, color: p.text, fontSize: 22, height: 1.2, letterSpacing: -0.2),
      titleLarge: TextStyle(fontFamily: kHeadFont, fontWeight: FontWeight.w800, color: p.text, fontSize: 19, height: 1.25),
      titleMedium: TextStyle(fontFamily: kHeadFont, fontWeight: FontWeight.w700, color: p.text, fontSize: 16, height: 1.3),
      titleSmall: TextStyle(fontFamily: kHeadFont, fontWeight: FontWeight.w700, color: p.text, fontSize: 14),
      bodyLarge: TextStyle(color: p.text, fontSize: 16, height: 1.45),
      bodyMedium: TextStyle(color: p.text, fontSize: 14, height: 1.4),
      bodySmall: TextStyle(color: p.muted, fontSize: 12.5, height: 1.4),
      labelLarge: TextStyle(color: p.text, fontSize: 14, fontWeight: FontWeight.w700),
      labelSmall: TextStyle(color: p.muted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6),
    ),
  );
}
