import 'package:flutter/material.dart';

/// Global background and text colors (dark mode only)
class AppColors {
  static const darkBg = Color(0xFF141210); // Warm near-black (lifted)
  static const darkText = Color(0xFFF0EBE5); // Warm off-white

  // Status / priority indicators (used across task items, filters, badges)
  static const overdue = Color(0xFFFF6B6B); // Soft red
  static const dueSoon = Color(0xFFFFB020); // Amber
  static const priorityHigh = Color(0xFFFF6B6B); // Same as overdue
  static const priorityMedium = Color(0xFFFFA726); // Orange
  static const priorityLow = Color(0xFF66BB6A); // Green
  static const completed = Color(0xFF66BB6A); // Same as priorityLow
  static const deleteAction = Color(0xFFE84878); // Crimson rose

  // Structural colors
  static const navBg = Color(0xFF1A1816);
  static const cardInset = Color(0xFF080604);

  // Text hierarchy (WCAG-aware alphas on darkText)
  static const secondaryText = Color(0x99F0EBE5); // 0.6 alpha — WCAG AA floor
  static const tertiaryText = Color(0x80F0EBE5);  // 0.5 alpha — decorative only

  // Snackbar palettes
  static const snackbarError = DomainPalette(
    name: 'Error',
    primary: Color(0xFFE84878),
    darkShade: Color(0xFF8A1A45),
    surface: Color(0xFF1F0D14),
    textOnPrimary: darkBg,
  );
  static const snackbarInfo = DomainPalette(
    name: 'Info',
    primary: Color(0xFFB0A99E),
    darkShade: Color(0xFF3A3530),
    surface: Color(0xFF1A1815),
    textOnPrimary: darkBg,
  );
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
    primary: Color(0xFFC4845A),
    darkShade: Color(0xFF8A5E3E),
    surface: Color(0xFF2E2218),
    textOnPrimary: Color(0xFF140E08),
    glow: Color(0x4DC4845A),
  );
  static const homeDark = DomainPalette(
    name: 'Home',
    primary: Color(0xFF9878B0),
    darkShade: Color(0xFF6A5480),
    surface: Color(0xFF241E30),
    textOnPrimary: Color(0xFF0E0A16),
    glow: Color(0x4D9878B0),
  );
  static const recreationDark = DomainPalette(
    name: 'Recreation',
    primary: Color(0xFFC46A80),
    darkShade: Color(0xFF8A4A5A),
    surface: Color(0xFF2A1A20),
    textOnPrimary: Color(0xFF140A0E),
    glow: Color(0x4DC46A80),
  );
  static const growthDark = DomainPalette(
    name: 'Growth',
    primary: Color(0xFFC4A455),
    darkShade: Color(0xFF8A7438),
    surface: Color(0xFF2A2414),
    textOnPrimary: Color(0xFF14100A),
    glow: Color(0x4DC4A455),
  );
  static const financeDark = DomainPalette(
    name: 'Finance',
    primary: Color(0xFF6A80B0),
    darkShade: Color(0xFF4A5A80),
    surface: Color(0xFF1A2028),
    textOnPrimary: Color(0xFF0A0E14),
    glow: Color(0x4D6A80B0),
  );
  static const relationshipsDark = DomainPalette(
    name: 'Relationships',
    primary: Color(0xFFC46A6E),
    darkShade: Color(0xFF8A4A4E),
    surface: Color(0xFF2A1A1C),
    textOnPrimary: Color(0xFF140A0C),
    glow: Color(0x4DC46A6E),
  );
  static const communityDark = DomainPalette(
    name: 'Community',
    primary: Color(0xFF6AAFA4),
    darkShade: Color(0xFF487A72),
    surface: Color(0xFF1A2826),
    textOnPrimary: Color(0xFF0A1412),
    glow: Color(0x4D6AAFA4),
  );
  static const defaultPalette = DomainPalette(
    name: 'Default',
    primary: Color(0xFF6AAFA4),
    darkShade: Color(0xFF487A72),
    surface: Color(0xFF1A2826),
    textOnPrimary: Color(0xFF0A1412),
    glow: Color(0x4D6AAFA4),
  );

  static const palettes = <DomainPalette>[
    // 0 - Warm Clay (Career)
    DomainPalette(
      name: '',
      primary: Color(0xFFC4845A),
      darkShade: Color(0xFF8A5E3E),
      surface: Color(0xFF2E2218),
      textOnPrimary: Color(0xFF140E08),
      glow: Color(0x4DC4845A),
    ),
    // 1 - Dusty Lavender (Home)
    DomainPalette(
      name: '',
      primary: Color(0xFF9878B0),
      darkShade: Color(0xFF6A5480),
      surface: Color(0xFF241E30),
      textOnPrimary: Color(0xFF0E0A16),
      glow: Color(0x4D9878B0),
    ),
    // 2 - Sage Green (Health)
    DomainPalette(
      name: '',
      primary: Color(0xFF6AAF7A),
      darkShade: Color(0xFF487A54),
      surface: Color(0xFF1A2A1E),
      textOnPrimary: Color(0xFF0A140E),
      glow: Color(0x4D6AAF7A),
    ),
    // 3 - Ochre Gold (Growth)
    DomainPalette(
      name: '',
      primary: Color(0xFFC4A455),
      darkShade: Color(0xFF8A7438),
      surface: Color(0xFF2A2414),
      textOnPrimary: Color(0xFF14100A),
      glow: Color(0x4DC4A455),
    ),
    // 4 - Muted Rose (Recreation)
    DomainPalette(
      name: '',
      primary: Color(0xFFC46A80),
      darkShade: Color(0xFF8A4A5A),
      surface: Color(0xFF2A1A20),
      textOnPrimary: Color(0xFF140A0E),
      glow: Color(0x4DC46A80),
    ),
    // 5 - Slate Blue (Finance)
    DomainPalette(
      name: '',
      primary: Color(0xFF6A80B0),
      darkShade: Color(0xFF4A5A80),
      surface: Color(0xFF1A2028),
      textOnPrimary: Color(0xFF0A0E14),
      glow: Color(0x4D6A80B0),
    ),
    // 6 - Terracotta (Relationships)
    DomainPalette(
      name: '',
      primary: Color(0xFFC46A6E),
      darkShade: Color(0xFF8A4A4E),
      surface: Color(0xFF2A1A1C),
      textOnPrimary: Color(0xFF140A0C),
      glow: Color(0x4DC46A6E),
    ),
    // 7 - Teal Sage (Community)
    DomainPalette(
      name: '',
      primary: Color(0xFF6AAFA4),
      darkShade: Color(0xFF487A72),
      surface: Color(0xFF1A2826),
      textOnPrimary: Color(0xFF0A1412),
      glow: Color(0x4D6AAFA4),
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
