import 'package:flutter/material.dart';

/// Global background and text colors (dark mode only)
class AppColors {
  static const darkBg = Color(0xFF0D0B09); // Warm near-black
  static const darkText = Color(0xFFF0EBE5); // Warm off-white
}

/// Domain color palette for a single domain
class DomainPalette {
  final String name;
  final Color primary;
  final Color darkShade;
  final Color surface;
  final Color textOnPrimary;
  final Color? glow;

  const DomainPalette({
    required this.name,
    required this.primary,
    required this.darkShade,
    required this.surface,
    required this.textOnPrimary,
    this.glow,
  });
}

/// All domain color palettes (dark mode only)
class DomainColors {
  // Work - Burnt vermillion
  static const workDark = DomainPalette(
    name: 'Work',
    primary: Color(0xFFF06030), // oklch(72% 0.22 30)
    darkShade: Color(0xFF8B2E0E),
    surface: Color(0xFF1F1410), // oklch(15% 0.04 30)
    textOnPrimary: Color(0xFF0D0B09),
    glow: Color(0x33F06030), // 20% opacity
  );

  // Personal - Electric purple
  static const personalDark = DomainPalette(
    name: 'Personal',
    primary: Color(0xFFB050E8), // oklch(68% 0.24 300)
    darkShade: Color(0xFF5A1A82),
    surface: Color(0xFF18101F), // oklch(15% 0.04 300)
    textOnPrimary: Color(0xFF0D0B09),
    glow: Color(0x33B050E8),
  );

  // Health - Jade
  static const healthDark = DomainPalette(
    name: 'Health',
    primary: Color(0xFF30D89A), // oklch(78% 0.18 165)
    darkShade: Color(0xFF0D7050),
    surface: Color(0xFF0D1A15), // oklch(15% 0.04 165)
    textOnPrimary: Color(0xFF0D0B09),
    glow: Color(0x3330D89A),
  );

  // Learning - Deep amber
  static const learningDark = DomainPalette(
    name: 'Learning',
    primary: Color(0xFFE8A830), // oklch(75% 0.20 60)
    darkShade: Color(0xFF825A0D),
    surface: Color(0xFF1A1508), // oklch(15% 0.04 60)
    textOnPrimary: Color(0xFF0D0B09),
    glow: Color(0x33E8A830),
  );

  // Projects - Crimson rose
  static const projectsDark = DomainPalette(
    name: 'Projects',
    primary: Color(0xFFE84878), // oklch(70% 0.22 350)
    darkShade: Color(0xFF8A1A45),
    surface: Color(0xFF1F0D14), // oklch(15% 0.04 350)
    textOnPrimary: Color(0xFF0D0B09),
    glow: Color(0x33E84878),
  );

  /// Get all domain palettes (dark mode only)
  static List<DomainPalette> getAllDomains(bool isDark) {
    return [workDark, personalDark, healthDark, learningDark, projectsDark];
  }

  /// Get domain palette by name
  static DomainPalette getDomain(String name, bool isDark) {
    final domains = getAllDomains(isDark);
    return domains.firstWhere(
      (d) => d.name.toLowerCase() == name.toLowerCase(),
      orElse: () => workDark,
    );
  }
}
