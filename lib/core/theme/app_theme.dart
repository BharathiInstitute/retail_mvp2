import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retail_mvp2/core/theme/typography.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keys for persisting theme settings.
const _kThemeModeKey = 'app_theme_mode_v1';

/// Theme controller with persistence.
class ThemeController extends StateNotifier<ThemeMode> {
  ThemeController() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kThemeModeKey);
      switch (raw) {
        case 'light':
          state = ThemeMode.light;
          break;
        case 'dark':
          state = ThemeMode.dark;
          break;
        case 'system':
        default:
          state = ThemeMode.system;
      }
    } catch (_) {
      // ignore persistence errors
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = switch (mode) { ThemeMode.light => 'light', ThemeMode.dark => 'dark', ThemeMode.system => 'system' };
      await prefs.setString(_kThemeModeKey, s);
    } catch (_) {}
  }

  Future<void> cycle() async {
    final next = switch (state) { ThemeMode.system => ThemeMode.light, ThemeMode.light => ThemeMode.dark, ThemeMode.dark => ThemeMode.system };
    await set(next);
  }
}

/// Public provider for ThemeController
final themeModeProvider = StateNotifierProvider<ThemeController, ThemeMode>((ref) => ThemeController());

/// Theme tokens via ThemeExtension for easy access to brand/feedback colors.
class AppColors extends ThemeExtension<AppColors> {
  final Color success;
  final Color warning;
  final Color info;
  final Color brand;
  final Color neutral;

  const AppColors({required this.success, required this.warning, required this.info, required this.brand, required this.neutral});

  static AppColors light = const AppColors(
    success: Color(0xFF2E7D32),
    warning: Color(0xFFED6C02),
    info: Color(0xFF0277BD),
    brand: Color(0xFF3F51B5),
    neutral: Color(0xFF607D8B),
  );
  static AppColors dark = const AppColors(
    success: Color(0xFF81C784),
    warning: Color(0xFFFFB74D),
    info: Color(0xFF4FC3F7),
    brand: Color(0xFF9FA8DA),
    neutral: Color(0xFFB0BEC5),
  );

  @override
  AppColors copyWith({Color? success, Color? warning, Color? info, Color? brand, Color? neutral}) => AppColors(
        success: success ?? this.success,
        warning: warning ?? this.warning,
        info: info ?? this.info,
        brand: brand ?? this.brand,
        neutral: neutral ?? this.neutral,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      brand: Color.lerp(brand, other.brand, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
    );
  }
}

class AppTheme {
  AppTheme._();

  // Single place to change brand color
  static const Color seed = Colors.indigo;

  // Delegates to global typography file.
  static TextTheme _textTheme(BuildContext context, {required String fontKey}) => AppTypography.buildTextTheme(context, fontKey: fontKey);

  static ThemeData light(BuildContext context, {required String fontKey}) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: _textTheme(context, fontKey: fontKey),
      extensions: <ThemeExtension<dynamic>>[AppColors.light],
      canvasColor: scheme.surface,
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        textStyle: TextStyle(color: scheme.onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      chipTheme: ChipThemeData(
        labelStyle: _textTheme(context, fontKey: fontKey).labelSmall?.copyWith(color: scheme.onSurface),
        backgroundColor: scheme.surfaceContainerHighest,
        selectedColor: scheme.primaryContainer,
        disabledColor: scheme.surfaceContainerHighest,
        deleteIconColor: scheme.onSurfaceVariant,
        side: BorderSide(color: scheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      checkboxTheme: CheckboxThemeData(
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(color: scheme.outline),
        fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected) && states.contains(WidgetState.disabled)) {
            return scheme.primary.withValues(alpha: 0.6);
          }
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll<Color>(scheme.onPrimary),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(),
        isDense: true,
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        floatingLabelStyle: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: scheme.outlineVariant)),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: scheme.primary, width: 1.2)),
      ),
    );
  }

  static ThemeData dark(BuildContext context, {required String fontKey}) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: _textTheme(context, fontKey: fontKey),
      extensions: <ThemeExtension<dynamic>>[AppColors.dark],
      canvasColor: scheme.surfaceContainerHigh,
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        textStyle: TextStyle(color: scheme.onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      chipTheme: ChipThemeData(
        labelStyle: _textTheme(context, fontKey: fontKey).labelSmall?.copyWith(color: scheme.onSurface),
        backgroundColor: scheme.surfaceContainerHighest,
        selectedColor: scheme.primaryContainer,
        disabledColor: scheme.surfaceContainerHighest,
        deleteIconColor: scheme.onSurfaceVariant,
        side: BorderSide(color: scheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      checkboxTheme: CheckboxThemeData(
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(color: scheme.outline),
        fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
          if (states.contains(WidgetState.selected) && states.contains(WidgetState.disabled)) {
            return scheme.primary.withValues(alpha: 0.8);
          }
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll<Color>(scheme.onPrimary),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(),
        isDense: true,
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        floatingLabelStyle: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: scheme.outlineVariant)),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: scheme.primary, width: 1.2)),
      ),
    );
  }
}
