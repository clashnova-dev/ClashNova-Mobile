import 'package:flutter/material.dart';

/// Design tokens ported from the desktop client (airport-client `app.css`),
/// both light and dark. Colors resolve at runtime against [AppColors.dark],
/// which the app keeps in sync with the active [ThemeData] brightness (see
/// `main.dart`'s MaterialApp builder), so every screen re-colors when the theme
/// mode changes.
class AppColors {
  const AppColors._();

  /// Whether the dark palette is active. Set from the MaterialApp builder
  /// before descendants build, so these getters return the right color.
  static bool dark = false;

  static Color _p(int light, int dark) => Color(AppColors.dark ? dark : light);

  // Accent (--accent / --accent-text).
  static Color get brand => _p(0xFF2F6FDD, 0xFF457BD0);
  static Color get brandText => _p(0xFF2459B8, 0xFF94BBF8);
  static Color get brandDark => _p(0xFF2459B8, 0xFF94BBF8);

  // Text (--text / --strong / --muted).
  static Color get ink => _p(0xFF1C2533, 0xFFE6EDF6);
  static Color get strong => _p(0xFF344760, 0xFFD5E1F1);
  static Color get muted => _p(0xFF5B677A, 0xFFA1B0C5);

  // Surfaces and lines (--surface / --bg / --line / --border).
  static Color get line => _p(0xFFE6EAF0, 0xFF2D3746);
  static Color get border => _p(0xFFD9E0EA, 0xFF3A4658);
  static Color get paper => _p(0xFFF4F6FA, 0xFF121822);
  static Color get card => _p(0xFFFFFFFF, 0xFF171D27);

  // Selected / hover (--selected / --selected-border / --hover).
  static Color get selected => _p(0xFFF1F6FF, 0xFF22344F);
  static Color get selectedBorder => _p(0xFFA9C4EF, 0xFF5076A9);
  static Color get hover => _p(0xFFF2F6FC, 0xFF222D3D);

  // Neutral pill (--pill-bg / --pill-text).
  static Color get pillBg => _p(0xFFEEF1F6, 0xFF263042);
  static Color get pillText => _p(0xFF465366, 0xFFC3CFE0);

  // Status tones (good / fair / bad / idle).
  static Color get good => _p(0xFF18794E, 0xFF8DD7AD);
  static Color get fair => _p(0xFF8A5A00, 0xFFF0C674);
  static Color get bad => _p(0xFFB3403A, 0xFFFFAAA1);
  static Color get idle => _p(0xFF5B677A, 0xFFA1B0C5);

  /// Subtle card shadow (--shadow-card).
  static List<BoxShadow> get shadowCard => [
        BoxShadow(
          color: Color(dark ? 0x4D000000 : 0x0A172033),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
      ];
}

/// Card / control radii and spacing shared across pages.
class AppMetrics {
  const AppMetrics._();

  static const radius = 16.0;
  static const radiusSm = 12.0;
  static const radiusBtn = 10.0;
  static const gap = 16.0;
  static const pad = 20.0;
}

/// Resolve a [ThemeMode] to the concrete light/dark it will paint as. `system`
/// follows the platform brightness; an explicit light or dark choice is kept.
///
/// `main.dart` uses this to set [AppColors.dark] from the *same* value it hands
/// to `MaterialApp.themeMode`, before any page builds — so the runtime palette
/// and the active [ThemeData] can never disagree (dark cards on a light
/// background, or white cards on a dark background).
ThemeMode resolveThemeMode(ThemeMode mode, Brightness platformBrightness) {
  switch (mode) {
    case ThemeMode.light:
      return ThemeMode.light;
    case ThemeMode.dark:
      return ThemeMode.dark;
    case ThemeMode.system:
      return platformBrightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light;
  }
}

ThemeData buildAppTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final brand = Color(isDark ? 0xFF457BD0 : 0xFF2F6FDD);
  final ink = Color(isDark ? 0xFFE6EDF6 : 0xFF1C2533);
  final paper = Color(isDark ? 0xFF121822 : 0xFFF4F6FA);
  final card = Color(isDark ? 0xFF171D27 : 0xFFFFFFFF);
  final border = Color(isDark ? 0xFF3A4658 : 0xFFD9E0EA);
  final line = Color(isDark ? 0xFF2D3746 : 0xFFE6EAF0);
  final strong = Color(isDark ? 0xFFD5E1F1 : 0xFF344760);
  final selectedBorder = Color(isDark ? 0xFF5076A9 : 0xFFA9C4EF);

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: brand,
      brightness: brightness,
    ).copyWith(primary: brand, surface: card),
    scaffoldBackgroundColor: paper,
    splashFactory: InkRipple.splashFactory,
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: paper,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: ink,
        fontSize: 19,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
      ),
    ),
    dividerTheme: DividerThemeData(color: line, space: 1, thickness: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: brand,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 44),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppMetrics.radiusBtn),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: strong,
        minimumSize: const Size(0, 40),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppMetrics.radiusBtn),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppMetrics.radiusSm),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppMetrics.radiusSm),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppMetrics.radiusSm),
        borderSide: BorderSide(color: selectedBorder, width: 1.5),
      ),
    ),
  );
}
