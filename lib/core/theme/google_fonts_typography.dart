import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Global typography utilities.
///
/// Central place to configure your application's font family and
/// any global TextTheme adjustments. Swap fonts here to update
/// everywhere.
class AppTypography {
  AppTypography._();

  /// Supported fonts map (key -> display name)
  static const Map<String, String> supportedFonts = {
    'inter': 'Inter',
    'roboto': 'Roboto',
    'poppins': 'Poppins',
    'montserrat': 'Montserrat',
  };

  /// Build the base text theme using Google Fonts.
  ///
  /// Defaults to Inter, but you can switch to any supported
  /// Google Font (e.g. Roboto, Poppins, Montserrat) by replacing
  /// the call below.
  static TextTheme buildTextTheme(BuildContext context, {String fontKey = 'inter'}) {
    final base = Theme.of(context).textTheme;

    // Choose font by key; fall back to Inter.
    final themed = switch (fontKey.toLowerCase()) {
      'roboto' => GoogleFonts.robotoTextTheme(base),
      'poppins' => GoogleFonts.poppinsTextTheme(base),
      'montserrat' => GoogleFonts.montserratTextTheme(base),
      'inter' => GoogleFonts.interTextTheme(base),
      _ => GoogleFonts.interTextTheme(base),
    };

    // Optional: fine-tune weights/sizes/letter spacing globally.
    return themed.copyWith(
      headlineSmall: themed.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
      titleLarge: themed.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      // Reduce TextField/content size: InputDecorator uses titleMedium by default
      // Lowering to 14 makes text inside input fields smaller without impacting body text.
      titleMedium: themed.titleMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      bodyLarge: themed.bodyLarge?.copyWith(fontSize: 14.5),
      bodyMedium: themed.bodyMedium?.copyWith(fontSize: 13.5),
      labelLarge: themed.labelLarge?.copyWith(letterSpacing: 0.2),
    );
  }
}
