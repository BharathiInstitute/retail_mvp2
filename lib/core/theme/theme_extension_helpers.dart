import 'package:flutter/material.dart';
import 'theme_config_and_providers.dart';

extension AppThemeX on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>() ?? AppColors.light;
  AppSizes get sizes => Theme.of(this).extension<AppSizes>() ?? AppSizes.defaults;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get texts => Theme.of(this).textTheme;
}

/// Text style helpers for consistent typography throughout the app.
/// Usage: Text('Hello', style: context.bodyMd) or Text('Title', style: context.heading2)
extension AppTextStyles on BuildContext {
  // ─────────────────────────────────────────────────────────────────
  // Body text (regular weight, default color)
  // ─────────────────────────────────────────────────────────────────
  TextStyle get bodyXs => TextStyle(fontSize: sizes.fontXs, color: colors.onSurface);
  TextStyle get bodySm => TextStyle(fontSize: sizes.fontSm, color: colors.onSurface);
  TextStyle get bodyMd => TextStyle(fontSize: sizes.fontMd, color: colors.onSurface);
  TextStyle get bodyLg => TextStyle(fontSize: sizes.fontLg, color: colors.onSurface);
  
  // ─────────────────────────────────────────────────────────────────
  // Subtle text (secondary/muted color)
  // ─────────────────────────────────────────────────────────────────
  TextStyle get subtleXs => TextStyle(fontSize: sizes.fontXs, color: colors.onSurfaceVariant);
  TextStyle get subtleSm => TextStyle(fontSize: sizes.fontSm, color: colors.onSurfaceVariant);
  TextStyle get subtleMd => TextStyle(fontSize: sizes.fontMd, color: colors.onSurfaceVariant);
  TextStyle get subtleLg => TextStyle(fontSize: sizes.fontLg, color: colors.onSurfaceVariant);

  // ─────────────────────────────────────────────────────────────────
  // Bold text (semibold/bold weight)
  // ─────────────────────────────────────────────────────────────────
  TextStyle get boldXs => TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: colors.onSurface);
  TextStyle get boldSm => TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w600, color: colors.onSurface);
  TextStyle get boldMd => TextStyle(fontSize: sizes.fontMd, fontWeight: FontWeight.w600, color: colors.onSurface);
  TextStyle get boldLg => TextStyle(fontSize: sizes.fontLg, fontWeight: FontWeight.w700, color: colors.onSurface);

  // ─────────────────────────────────────────────────────────────────
  // Headings
  // ─────────────────────────────────────────────────────────────────
  TextStyle get heading1 => TextStyle(fontSize: sizes.fontXxl, fontWeight: FontWeight.w700, color: colors.onSurface);
  TextStyle get heading2 => TextStyle(fontSize: sizes.fontXl, fontWeight: FontWeight.w600, color: colors.onSurface);
  TextStyle get heading3 => TextStyle(fontSize: sizes.fontLg, fontWeight: FontWeight.w600, color: colors.onSurface);

  // ─────────────────────────────────────────────────────────────────
  // Label text (for form labels, captions)
  // ─────────────────────────────────────────────────────────────────
  TextStyle get labelXs => TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant);
  TextStyle get labelSm => TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant);
  TextStyle get labelMd => TextStyle(fontSize: sizes.fontMd, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant);

  // ─────────────────────────────────────────────────────────────────
  // Monospace (for SKU, codes, prices)
  // ─────────────────────────────────────────────────────────────────
  TextStyle get monoXs => TextStyle(fontSize: sizes.fontXs, fontFamily: 'monospace', color: colors.primary, fontWeight: FontWeight.w600);
  TextStyle get monoSm => TextStyle(fontSize: sizes.fontSm, fontFamily: 'monospace', color: colors.primary, fontWeight: FontWeight.w600);
  TextStyle get monoMd => TextStyle(fontSize: sizes.fontMd, fontFamily: 'monospace', color: colors.primary, fontWeight: FontWeight.w600);

  // ─────────────────────────────────────────────────────────────────
  // Primary colored text
  // ─────────────────────────────────────────────────────────────────
  TextStyle get primarySm => TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w600, color: colors.primary);
  TextStyle get primaryMd => TextStyle(fontSize: sizes.fontMd, fontWeight: FontWeight.w600, color: colors.primary);
  TextStyle get primaryLg => TextStyle(fontSize: sizes.fontLg, fontWeight: FontWeight.w700, color: colors.primary);

  // ─────────────────────────────────────────────────────────────────
  // Error/Success/Warning text
  // ─────────────────────────────────────────────────────────────────
  TextStyle get errorSm => TextStyle(fontSize: sizes.fontSm, color: colors.error);
  TextStyle get errorMd => TextStyle(fontSize: sizes.fontMd, color: colors.error);
  TextStyle get successSm => TextStyle(fontSize: sizes.fontSm, color: appColors.success);
  TextStyle get successMd => TextStyle(fontSize: sizes.fontMd, color: appColors.success);
  TextStyle get warningSm => TextStyle(fontSize: sizes.fontSm, color: appColors.warning);
  TextStyle get warningMd => TextStyle(fontSize: sizes.fontMd, color: appColors.warning);
}

/// Border radius helpers
extension AppBorderRadius on BuildContext {
  BorderRadius get radiusXs => BorderRadius.circular(sizes.radiusXs);
  BorderRadius get radiusSm => BorderRadius.circular(sizes.radiusSm);
  BorderRadius get radiusMd => BorderRadius.circular(sizes.radiusMd);
  BorderRadius get radiusLg => BorderRadius.circular(sizes.radiusLg);
  BorderRadius get radiusXl => BorderRadius.circular(sizes.radiusXl);
}

/// Padding/Margin helpers
extension AppEdgeInsets on BuildContext {
  // Symmetric paddings
  EdgeInsets get padXs => EdgeInsets.all(sizes.gapXs);
  EdgeInsets get padSm => EdgeInsets.all(sizes.gapSm);
  EdgeInsets get padMd => EdgeInsets.all(sizes.gapMd);
  EdgeInsets get padLg => EdgeInsets.all(sizes.gapLg);
  EdgeInsets get padXl => EdgeInsets.all(sizes.gapXl);
  
  // Horizontal paddings
  EdgeInsets get padHXs => EdgeInsets.symmetric(horizontal: sizes.gapXs);
  EdgeInsets get padHSm => EdgeInsets.symmetric(horizontal: sizes.gapSm);
  EdgeInsets get padHMd => EdgeInsets.symmetric(horizontal: sizes.gapMd);
  EdgeInsets get padHLg => EdgeInsets.symmetric(horizontal: sizes.gapLg);
  
  // Vertical paddings
  EdgeInsets get padVXs => EdgeInsets.symmetric(vertical: sizes.gapXs);
  EdgeInsets get padVSm => EdgeInsets.symmetric(vertical: sizes.gapSm);
  EdgeInsets get padVMd => EdgeInsets.symmetric(vertical: sizes.gapMd);
  EdgeInsets get padVLg => EdgeInsets.symmetric(vertical: sizes.gapLg);
  
  // Card padding
  EdgeInsets get cardPadSm => EdgeInsets.all(sizes.cardPadSm);
  EdgeInsets get cardPadMd => EdgeInsets.all(sizes.cardPadMd);
  EdgeInsets get cardPadLg => EdgeInsets.all(sizes.cardPadLg);
}

/// Gap/Spacing helpers (for use with SizedBox)
extension AppGaps on BuildContext {
  SizedBox get gapXs => SizedBox(width: sizes.gapXs, height: sizes.gapXs);
  SizedBox get gapSm => SizedBox(width: sizes.gapSm, height: sizes.gapSm);
  SizedBox get gapMd => SizedBox(width: sizes.gapMd, height: sizes.gapMd);
  SizedBox get gapLg => SizedBox(width: sizes.gapLg, height: sizes.gapLg);
  SizedBox get gapXl => SizedBox(width: sizes.gapXl, height: sizes.gapXl);
  
  // Horizontal gaps
  SizedBox get gapHXs => SizedBox(width: sizes.gapXs);
  SizedBox get gapHSm => SizedBox(width: sizes.gapSm);
  SizedBox get gapHMd => SizedBox(width: sizes.gapMd);
  SizedBox get gapHLg => SizedBox(width: sizes.gapLg);
  SizedBox get gapHXl => SizedBox(width: sizes.gapXl);
  
  // Vertical gaps
  SizedBox get gapVXs => SizedBox(height: sizes.gapXs);
  SizedBox get gapVSm => SizedBox(height: sizes.gapSm);
  SizedBox get gapVMd => SizedBox(height: sizes.gapMd);
  SizedBox get gapVLg => SizedBox(height: sizes.gapLg);
  SizedBox get gapVXl => SizedBox(height: sizes.gapXl);
}
