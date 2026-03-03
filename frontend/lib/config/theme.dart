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
    primary: Color(0xFFFF9A50),
    darkShade: Color(0xFFCC6020),
    surface: Color(0xFF4A3020),
    textOnPrimary: Color(0xFF1A0E06),
    glow: Color(0x66FF9A50),
  );
  static const homeDark = DomainPalette(
    name: 'Home',
    primary: Color(0xFFBB78FF),
    darkShade: Color(0xFF7838C8),
    surface: Color(0xFF32204A),
    textOnPrimary: Color(0xFF10081A),
    glow: Color(0x66BB78FF),
  );
  static const recreationDark = DomainPalette(
    name: 'Recreation',
    primary: Color(0xFFFF5898),
    darkShade: Color(0xFFCC2860),
    surface: Color(0xFF441C30),
    textOnPrimary: Color(0xFF1A0A12),
    glow: Color(0x66FF5898),
  );
  static const growthDark = DomainPalette(
    name: 'Growth',
    primary: Color(0xFFFFC840),
    darkShade: Color(0xFFCC9010),
    surface: Color(0xFF3E3214),
    textOnPrimary: Color(0xFF1A1408),
    glow: Color(0x66FFC840),
  );
  static const financeDark = DomainPalette(
    name: 'Finance',
    primary: Color(0xFF6890FF),
    darkShade: Color(0xFF3050C0),
    surface: Color(0xFF1E2848),
    textOnPrimary: Color(0xFF080E1A),
    glow: Color(0x666890FF),
  );
  static const relationshipsDark = DomainPalette(
    name: 'Relationships',
    primary: Color(0xFFFF5060),
    darkShade: Color(0xFFCC2030),
    surface: Color(0xFF401C20),
    textOnPrimary: Color(0xFF1A0A0C),
    glow: Color(0x66FF5060),
  );
  static const communityDark = DomainPalette(
    name: 'Community',
    primary: Color(0xFF50E8D8),
    darkShade: Color(0xFF20A898),
    surface: Color(0xFF1E3834),
    textOnPrimary: Color(0xFF081A18),
    glow: Color(0x6650E8D8),
  );
  static const defaultPalette = DomainPalette(
    name: 'Default',
    primary: Color(0xFF50E8D8),
    darkShade: Color(0xFF20A898),
    surface: Color(0xFF1E3834),
    textOnPrimary: Color(0xFF081A18),
    glow: Color(0x6650E8D8),
  );

  static const palettes = <DomainPalette>[
    // 0 - Bright Orange (Career)
    DomainPalette(
      name: '',
      primary: Color(0xFFFF9A50),
      darkShade: Color(0xFFCC6020),
      surface: Color(0xFF4A3020),
      textOnPrimary: Color(0xFF1A0E06),
      glow: Color(0x66FF9A50),
    ),
    // 1 - Bright Purple (Home)
    DomainPalette(
      name: '',
      primary: Color(0xFFBB78FF),
      darkShade: Color(0xFF7838C8),
      surface: Color(0xFF32204A),
      textOnPrimary: Color(0xFF10081A),
      glow: Color(0x66BB78FF),
    ),
    // 2 - Bright Green (Health)
    DomainPalette(
      name: '',
      primary: Color(0xFF50E890),
      darkShade: Color(0xFF20A850),
      surface: Color(0xFF1E3828),
      textOnPrimary: Color(0xFF081A10),
      glow: Color(0x6650E890),
    ),
    // 3 - Bright Gold (Growth)
    DomainPalette(
      name: '',
      primary: Color(0xFFFFC840),
      darkShade: Color(0xFFCC9010),
      surface: Color(0xFF3E3214),
      textOnPrimary: Color(0xFF1A1408),
      glow: Color(0x66FFC840),
    ),
    // 4 - Hot Pink (Recreation)
    DomainPalette(
      name: '',
      primary: Color(0xFFFF5898),
      darkShade: Color(0xFFCC2860),
      surface: Color(0xFF441C30),
      textOnPrimary: Color(0xFF1A0A12),
      glow: Color(0x66FF5898),
    ),
    // 5 - Bright Blue (Finance)
    DomainPalette(
      name: '',
      primary: Color(0xFF6890FF),
      darkShade: Color(0xFF3050C0),
      surface: Color(0xFF1E2848),
      textOnPrimary: Color(0xFF080E1A),
      glow: Color(0x666890FF),
    ),
    // 6 - Bright Red (Relationships)
    DomainPalette(
      name: '',
      primary: Color(0xFFFF5060),
      darkShade: Color(0xFFCC2030),
      surface: Color(0xFF401C20),
      textOnPrimary: Color(0xFF1A0A0C),
      glow: Color(0x66FF5060),
    ),
    // 7 - Bright Cyan (Community)
    DomainPalette(
      name: '',
      primary: Color(0xFF50E8D8),
      darkShade: Color(0xFF20A898),
      surface: Color(0xFF1E3834),
      textOnPrimary: Color(0xFF081A18),
      glow: Color(0x6650E8D8),
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
