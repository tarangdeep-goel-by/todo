import 'package:flutter/material.dart';

/// Global background and text colors (dark mode only)
class AppColors {
  static const darkBg = Color(0xFF0D0B09); // Warm near-black
  static const darkText = Color(0xFFF0EBE5); // Warm off-white

  // Status / priority indicators (used across task items, filters, badges)
  static const overdue = Color(0xFFFF6B6B); // Soft red
  static const dueSoon = Color(0xFFFFB020); // Amber
  static const priorityHigh = Color(0xFFFF6B6B); // Same as overdue
  static const priorityMedium = Color(0xFFFFA726); // Orange
  static const priorityLow = Color(0xFF66BB6A); // Green
  static const completed = Color(0xFF66BB6A); // Same as priorityLow
  static const deleteAction = Color(0xFFE84878); // Crimson rose
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

  /// Create a copy with a different name
  DomainPalette withName(String newName) => DomainPalette(
        name: newName,
        primary: primary,
        darkShade: darkShade,
        surface: surface,
        textOnPrimary: textOnPrimary,
        glow: glow,
      );
}

/// 8 distinct color palettes for domains (assigned by index, not by name)
class DomainColors {
  // Named aliases for UI accent usage (filter chips, buttons, etc.)
  static const careerDark = DomainPalette(
    name: 'Career',
    primary: Color(0xFFF06030),
    darkShade: Color(0xFF8B2E0E),
    surface: Color(0xFF1F1410),
    textOnPrimary: Color(0xFF0D0B09),
    glow: Color(0x33F06030),
  );
  static const homeDark = DomainPalette(
    name: 'Home',
    primary: Color(0xFFB050E8),
    darkShade: Color(0xFF5A1A82),
    surface: Color(0xFF18101F),
    textOnPrimary: Color(0xFF0D0B09),
    glow: Color(0x33B050E8),
  );
  static const recreationDark = DomainPalette(
    name: 'Recreation',
    primary: Color(0xFFE84878),
    darkShade: Color(0xFF8A1A45),
    surface: Color(0xFF1F0D14),
    textOnPrimary: Color(0xFF0D0B09),
    glow: Color(0x33E84878),
  );
  static const growthDark = DomainPalette(
    name: 'Growth',
    primary: Color(0xFFE8A830),
    darkShade: Color(0xFF825A0D),
    surface: Color(0xFF1A1508),
    textOnPrimary: Color(0xFF0D0B09),
    glow: Color(0x33E8A830),
  );
  static const financeDark = DomainPalette(
    name: 'Finance',
    primary: Color(0xFFD4A017),
    darkShade: Color(0xFF7A5C0E),
    surface: Color(0xFF1A1608),
    textOnPrimary: Color(0xFF0D0B09),
    glow: Color(0x33D4A017),
  );
  static const relationshipsDark = DomainPalette(
    name: 'Relationships',
    primary: Color(0xFFE8608A),
    darkShade: Color(0xFF8A2E50),
    surface: Color(0xFF1F1018),
    textOnPrimary: Color(0xFF0D0B09),
    glow: Color(0x33E8608A),
  );
  static const communityDark = DomainPalette(
    name: 'Community',
    primary: Color(0xFF40C4B0),
    darkShade: Color(0xFF1A6B60),
    surface: Color(0xFF0F1A18),
    textOnPrimary: Color(0xFF0D0B09),
    glow: Color(0x3340C4B0),
  );
  static const defaultPalette = DomainPalette(
    name: 'Default',
    primary: Color(0xFF5ABCB4),
    darkShade: Color(0xFF2A6660),
    surface: Color(0xFF0F1A19),
    textOnPrimary: Color(0xFF0D0B09),
    glow: Color(0x335ABCB4),
  );

  static const palettes = <DomainPalette>[
    // 0 - Burnt vermillion (Career)
    DomainPalette(
      name: '',
      primary: Color(0xFFF06030),
      darkShade: Color(0xFF8B2E0E),
      surface: Color(0xFF1F1410),
      textOnPrimary: Color(0xFF0D0B09),
      glow: Color(0x33F06030),
    ),
    // 1 - Electric purple (Home)
    DomainPalette(
      name: '',
      primary: Color(0xFFB050E8),
      darkShade: Color(0xFF5A1A82),
      surface: Color(0xFF18101F),
      textOnPrimary: Color(0xFF0D0B09),
      glow: Color(0x33B050E8),
    ),
    // 2 - Jade (Health)
    DomainPalette(
      name: '',
      primary: Color(0xFF30D89A),
      darkShade: Color(0xFF0D7050),
      surface: Color(0xFF0D1A15),
      textOnPrimary: Color(0xFF0D0B09),
      glow: Color(0x3330D89A),
    ),
    // 3 - Deep amber (Growth)
    DomainPalette(
      name: '',
      primary: Color(0xFFE8A830),
      darkShade: Color(0xFF825A0D),
      surface: Color(0xFF1A1508),
      textOnPrimary: Color(0xFF0D0B09),
      glow: Color(0x33E8A830),
    ),
    // 4 - Crimson rose (Recreation)
    DomainPalette(
      name: '',
      primary: Color(0xFFE84878),
      darkShade: Color(0xFF8A1A45),
      surface: Color(0xFF1F0D14),
      textOnPrimary: Color(0xFF0D0B09),
      glow: Color(0x33E84878),
    ),
    // 5 - Gold/amber (Finance)
    DomainPalette(
      name: '',
      primary: Color(0xFFD4A017),
      darkShade: Color(0xFF7A5C0E),
      surface: Color(0xFF1A1608),
      textOnPrimary: Color(0xFF0D0B09),
      glow: Color(0x33D4A017),
    ),
    // 6 - Rose/pink (Relationships)
    DomainPalette(
      name: '',
      primary: Color(0xFFE8608A),
      darkShade: Color(0xFF8A2E50),
      surface: Color(0xFF1F1018),
      textOnPrimary: Color(0xFF0D0B09),
      glow: Color(0x33E8608A),
    ),
    // 7 - Teal/cyan (Community)
    DomainPalette(
      name: '',
      primary: Color(0xFF40C4B0),
      darkShade: Color(0xFF1A6B60),
      surface: Color(0xFF0F1A18),
      textOnPrimary: Color(0xFF0D0B09),
      glow: Color(0x3340C4B0),
    ),
  ];

  /// Get palette for a domain by its index in the domain list (0-7)
  static DomainPalette byIndex(int index, String name) {
    return palettes[index % palettes.length].withName(name);
  }

  /// Get palette by category name using hash fallback.
  /// Prefer using domainPalettesProvider for consistent colors.
  static DomainPalette getDomain(String name, bool isDark, [Map<String, DomainPalette>? paletteMap]) {
    if (paletteMap != null) {
      final found = paletteMap[name.toLowerCase()];
      if (found != null) return found;
    }
    final index = name.toLowerCase().hashCode.abs() % palettes.length;
    return palettes[index].withName(name);
  }
}
