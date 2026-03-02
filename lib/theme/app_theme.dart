import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AppTheme — luxury interior studio design system
//
// Palette:  deep charcoal + warm sand-gold + cream whites
// Usage:    import this file everywhere instead of hardcoding colours
// ─────────────────────────────────────────────────────────────────────────────

class AppTheme {
  AppTheme._();

  // ── Core palette ───────────────────────────────────────────────────────────
  static const Color bgDark = Color(0xFF0D0D11);
  static const Color surfaceDark = Color(0xFF17171F);
  static const Color surfaceAlt = Color(0xFF1F1F2B);
  static const Color surfaceHover = Color(0xFF252534);
  static const Color borderDark = Color(0xFF2C2C3E);

  static const Color accent = Color(0xFFC9A96E); // warm gold
  static const Color accentLight = Color(0xFFE8D5B0);
  static const Color accentDark = Color(0xFF9E7A44);
  static const Color accentGlow = Color(0x33C9A96E);

  static const Color textPrimary = Color(0xFFF0EDE8);
  static const Color textSecondary = Color(0xFF8E8A9A);
  static const Color textMuted = Color(0xFF56535F);

  // ── Light panel (login right side, dialogs) ───────────────────────────────
  static const Color lightBg = Color(0xFFF5F2ED);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE0D9D0);
  static const Color lightText = Color(0xFF1A1814);
  static const Color lightMuted = Color(0xFF7A7570);

  // ── Status colours ─────────────────────────────────────────────────────────
  static const Color success = Color(0xFF4CAF7D);
  static const Color warning = Color(0xFFE8A838);
  static const Color error = Color(0xFFE05252);
  static const Color info = Color(0xFF4A9EE8);

  // ── Sidebar ────────────────────────────────────────────────────────────────
  static const double sidebarWidth = 220.0;
  static const double sidebarCollapsed = 64.0;

  // ── Shadows ────────────────────────────────────────────────────────────────
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.35),
      blurRadius: 20,
      offset: const Offset(0, 6),
    ),
  ];

  static List<BoxShadow> get glowShadow => [
    BoxShadow(
      color: accentGlow,
      blurRadius: 24,
      spreadRadius: 0,
      offset: const Offset(0, 4),
    ),
  ];

  // ── Typography ─────────────────────────────────────────────────────────────
  static const TextStyle displayLarge = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.5,
    height: 1.1,
  );

  static const TextStyle displayMedium = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.3,
  );

  static const TextStyle titleLarge = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    letterSpacing: 0,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: textPrimary,
    letterSpacing: 0.1,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: textSecondary,
    height: 1.5,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    color: textMuted,
    letterSpacing: 0.8,
  );

  static const TextStyle accentLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: accent,
    letterSpacing: 1.2,
  );

  // ── MaterialApp ThemeData ──────────────────────────────────────────────────
  static ThemeData get themeData => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bgDark,
    colorScheme: ColorScheme.dark(
      primary: accent,
      secondary: accentLight,
      surface: surfaceDark,
      onPrimary: bgDark,
      onSecondary: bgDark,
      onSurface: textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: surfaceDark,
      foregroundColor: textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: bgDark,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceAlt,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: borderDark),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: borderDark),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: accent, width: 1.5),
      ),
      labelStyle: const TextStyle(color: textSecondary, fontSize: 13),
      hintStyle: const TextStyle(color: textMuted, fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    cardTheme: CardThemeData(
      color: surfaceDark,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: borderDark, width: 1),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: borderDark,
      thickness: 1,
      space: 1,
    ),
    iconTheme: const IconThemeData(color: textSecondary, size: 20),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderDark),
      ),
      textStyle: const TextStyle(color: textPrimary, fontSize: 12),
    ),
  );
}
