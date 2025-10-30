import 'package:flutter/material.dart';
import 'app_theme.dart';

extension AppThemeX on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>() ?? AppColors.light;
  AppSizes get sizes => Theme.of(this).extension<AppSizes>() ?? AppSizes.defaults;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get texts => Theme.of(this).textTheme;
}
