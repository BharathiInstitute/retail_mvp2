import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Global typography utilities.
///
/// Central place to configure your application's font family and
/// any global TextTheme adjustments. Swap fonts here to update
/// everywhere.
class AppTypography {
  AppTypography._();

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
      titleMedium: themed.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      bodyLarge: themed.bodyLarge?.copyWith(fontSize: 14.5),
      bodyMedium: themed.bodyMedium?.copyWith(fontSize: 13.5),
      labelLarge: themed.labelLarge?.copyWith(letterSpacing: 0.2),
    );
  }
}
