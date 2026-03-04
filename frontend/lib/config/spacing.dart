/// Spacing constants for consistent layout
class AppSpacing {
  // Base spacing unit (8px)
  static const double unit = 8.0;

  // Common spacing values
  static const double xs = 4.0; // 0.5 unit
  static const double sm = 8.0; // 1 unit
  static const double md = 16.0; // 2 units
  static const double lg = 24.0; // 3 units
  static const double xl = 32.0; // 4 units
  static const double xxl = 48.0; // 6 units

  // Component-specific spacing
  static const double cardMargin = 2.0; // Edge-to-edge bleed with minimal margin
  static const double compressedCardInset = 16.0; // Horizontal inset for compressed cards
  static const double focusedCardInset = 32.0; // Horizontal inset at edges
  static const double leftAccentBar = 4.0; // Compressed card left bar

  // CTA button
  static const double ctaBottomMargin = 32.0; // Distance from bottom safe area
  static const double ctaIdleWidth = 200.0;
  static const double ctaIdleHeight = 56.0;
  static const double ctaActiveWidth = 280.0;
  static const double ctaActiveHeight = 72.0;

  // Top bar
  static const double topBarHeight = 48.0;

  // Bottom nav
  static const double bottomNavHeight = 72.0;
  static const double bottomNavMarginH = 16.0;
  static const double bottomNavMarginBottom = 12.0;
  static const double bottomNavRadius = 24.0;

  // Border radius
  static const double radiusNone = 0.0;
  static const double radiusSm = 12.0;
  static const double radiusMd = 16.0;
  static const double radiusLg = 18.0; // Full pill for toggle
  static const double radiusPill = 100.0; // Full pill for CTA

  // Touch targets
  static const double pttButtonHeight = 46.0;
  static const double sendButtonSize = 44.0;
  static const double minTouchTarget = 44.0;
}
