import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography configuration with exact fonts from design brief
class AppTypography {
  // Fluid type scale based on viewport width
  static double domainFocus(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return (width * 0.08).clamp(56.0, 72.0);
  }

  static double taskFocus(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return (width * 0.04).clamp(28.0, 32.0);
  }

  static const double metadata = 11.0;
  static const double ctaLabel = 14.0;
  static const double domainPill = 11.0;
  static const double navLabelSize = 10.0;
  static const double sectionHeader = 20.0;
  static const double bodyLg = 16.0;
  static const double bodySm = 15.0;
  static const double bodyBase = 13.0;
  static const double emptyStateDisplay = 48.0;

  // Text styles
  static TextStyle domainTitle(BuildContext context, {Color? color}) =>
      GoogleFonts.bricolageGrotesque(
        fontSize: domainFocus(context),
        fontWeight: FontWeight.w700,
        height: 0.9,
        color: color,
      );

  static TextStyle taskTitle(BuildContext context, {Color? color}) =>
      GoogleFonts.dmSans(
        fontSize: taskFocus(context),
        fontWeight: FontWeight.w500,
        height: 1.2,
        color: color,
      );

  static TextStyle metadataText({Color? color}) => GoogleFonts.dmSans(
        fontSize: metadata,
        fontWeight: FontWeight.w400,
        color: color,
      );

  static TextStyle ctaLabelText({Color? color}) => GoogleFonts.dmSans(
        fontSize: ctaLabel,
        fontWeight: FontWeight.w500,
        color: color,
      );

  static TextStyle domainPillText({Color? color}) => GoogleFonts.dmSans(
        fontSize: domainPill,
        fontWeight: FontWeight.w600,
        color: color,
      );

  static TextStyle navLabel({Color? color}) => GoogleFonts.dmSans(
        fontSize: navLabelSize,
        fontWeight: FontWeight.w600,
        color: color,
      );

  static TextStyle taskPreview(BuildContext context, {Color? color}) =>
      GoogleFonts.dmSans(
        fontSize: 16.0,
        fontWeight: FontWeight.w400,
        height: 1.4,
        color: color,
      );
}
