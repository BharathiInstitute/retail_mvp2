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

/// Global size and spacing tokens accessible via ThemeExtension.
class AppSizes extends ThemeExtension<AppSizes> {
  // Radii
  final double radiusSm;
  final double radiusMd;
  final double radiusLg;

  // Gaps (spacing scale)
  final double gapXs;
  final double gapSm;
  final double gapMd;
  final double gapLg;

  // Field paddings
  final double fieldVPad;
  final double fieldHPad;

  // Button paddings
  final double buttonVPad;
  final double buttonHPad;

  // Table row sizes
  final double tableHeadingRowHeight;
  final double tableDataRowMinHeight;
  final double tableDataRowMaxHeight;

  const AppSizes({
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusLg,
    required this.gapXs,
    required this.gapSm,
    required this.gapMd,
    required this.gapLg,
    required this.fieldVPad,
    required this.fieldHPad,
    required this.buttonVPad,
    required this.buttonHPad,
    required this.tableHeadingRowHeight,
    required this.tableDataRowMinHeight,
    required this.tableDataRowMaxHeight,
  });

  static AppSizes defaults = const AppSizes(
    radiusSm: 8,
    radiusMd: 12,
    radiusLg: 16,
    gapXs: 4,
    gapSm: 8,
    gapMd: 12,
    gapLg: 16,
    fieldVPad: 8,
    fieldHPad: 12,
    buttonVPad: 10,
    buttonHPad: 14,
    tableHeadingRowHeight: 44,
    tableDataRowMinHeight: 40,
    tableDataRowMaxHeight: 44,
  );

  @override
  AppSizes copyWith({
    double? radiusSm,
    double? radiusMd,
    double? radiusLg,
    double? gapXs,
    double? gapSm,
    double? gapMd,
    double? gapLg,
    double? fieldVPad,
    double? fieldHPad,
    double? buttonVPad,
    double? buttonHPad,
    double? tableHeadingRowHeight,
    double? tableDataRowMinHeight,
    double? tableDataRowMaxHeight,
  }) => AppSizes(
        radiusSm: radiusSm ?? this.radiusSm,
        radiusMd: radiusMd ?? this.radiusMd,
        radiusLg: radiusLg ?? this.radiusLg,
        gapXs: gapXs ?? this.gapXs,
        gapSm: gapSm ?? this.gapSm,
        gapMd: gapMd ?? this.gapMd,
        gapLg: gapLg ?? this.gapLg,
        fieldVPad: fieldVPad ?? this.fieldVPad,
        fieldHPad: fieldHPad ?? this.fieldHPad,
        buttonVPad: buttonVPad ?? this.buttonVPad,
        buttonHPad: buttonHPad ?? this.buttonHPad,
        tableHeadingRowHeight: tableHeadingRowHeight ?? this.tableHeadingRowHeight,
        tableDataRowMinHeight: tableDataRowMinHeight ?? this.tableDataRowMinHeight,
        tableDataRowMaxHeight: tableDataRowMaxHeight ?? this.tableDataRowMaxHeight,
      );

  @override
  AppSizes lerp(ThemeExtension<AppSizes>? other, double t) {
    if (other is! AppSizes) return this;
    double l(double a, double b) => a + (b - a) * t;
    return AppSizes(
      radiusSm: l(radiusSm, other.radiusSm),
      radiusMd: l(radiusMd, other.radiusMd),
      radiusLg: l(radiusLg, other.radiusLg),
      gapXs: l(gapXs, other.gapXs),
      gapSm: l(gapSm, other.gapSm),
      gapMd: l(gapMd, other.gapMd),
      gapLg: l(gapLg, other.gapLg),
      fieldVPad: l(fieldVPad, other.fieldVPad),
      fieldHPad: l(fieldHPad, other.fieldHPad),
      buttonVPad: l(buttonVPad, other.buttonVPad),
      buttonHPad: l(buttonHPad, other.buttonHPad),
      tableHeadingRowHeight: l(tableHeadingRowHeight, other.tableHeadingRowHeight),
      tableDataRowMinHeight: l(tableDataRowMinHeight, other.tableDataRowMinHeight),
      tableDataRowMaxHeight: l(tableDataRowMaxHeight, other.tableDataRowMaxHeight),
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
    final sizes = AppSizes.defaults;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: _textTheme(context, fontKey: fontKey),
      extensions: <ThemeExtension<dynamic>>[AppColors.light, sizes],
      canvasColor: scheme.surface,
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 1,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(sizes.radiusMd)),
        margin: EdgeInsets.all(sizes.gapSm),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        textStyle: TextStyle(color: scheme.onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(sizes.radiusSm)),
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
            return scheme.primary.withOpacity(0.6);
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
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: sizes.buttonHPad, vertical: sizes.buttonVPad),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(sizes.radiusMd)),
      )),
      elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: sizes.buttonHPad, vertical: sizes.buttonVPad),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(sizes.radiusMd)),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: sizes.buttonHPad, vertical: sizes.buttonVPad),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(sizes.radiusMd)),
        side: BorderSide(color: scheme.outline),
      )),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: sizes.buttonHPad, vertical: sizes.buttonVPad),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(sizes.radiusSm)),
      )),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(sizes.radiusMd)),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: sizes.fieldHPad, vertical: sizes.fieldVPad),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
        floatingLabelStyle: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600, fontSize: 12.5),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(sizes.radiusMd),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(sizes.radiusMd),
          borderSide: BorderSide(color: scheme.primary, width: 1.2),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowHeight: sizes.tableHeadingRowHeight,
        dataRowMinHeight: sizes.tableDataRowMinHeight,
        dataRowMaxHeight: sizes.tableDataRowMaxHeight,
        dividerThickness: 1,
        headingTextStyle: _textTheme(context, fontKey: fontKey).labelLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        dataTextStyle: _textTheme(context, fontKey: fontKey).bodyMedium?.copyWith(color: scheme.onSurface),
      ),
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHighest),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(sizes.radiusMd))),
        hintStyle: WidgetStatePropertyAll(TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
        textStyle: WidgetStatePropertyAll(TextStyle(color: scheme.onSurface, fontSize: 14)),
      ),
    );
  }

  static ThemeData dark(BuildContext context, {required String fontKey}) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
    final sizes = AppSizes.defaults;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: _textTheme(context, fontKey: fontKey),
      extensions: <ThemeExtension<dynamic>>[AppColors.dark, sizes],
      canvasColor: scheme.surfaceContainerHigh,
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerHigh,
        elevation: 1,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(sizes.radiusMd)),
        margin: EdgeInsets.all(sizes.gapSm),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        textStyle: TextStyle(color: scheme.onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(sizes.radiusSm)),
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
            return scheme.primary.withOpacity(0.8);
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
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: sizes.buttonHPad, vertical: sizes.buttonVPad),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(sizes.radiusMd)),
      )),
      elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: sizes.buttonHPad, vertical: sizes.buttonVPad),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(sizes.radiusMd)),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: sizes.buttonHPad, vertical: sizes.buttonVPad),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(sizes.radiusMd)),
        side: BorderSide(color: scheme.outline),
      )),
      textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: sizes.buttonHPad, vertical: sizes.buttonVPad),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(sizes.radiusSm)),
      )),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(sizes.radiusMd)),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: sizes.fieldHPad, vertical: sizes.fieldVPad),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
        floatingLabelStyle: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600, fontSize: 12.5),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(sizes.radiusMd),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(sizes.radiusMd),
          borderSide: BorderSide(color: scheme.primary, width: 1.2),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowHeight: sizes.tableHeadingRowHeight,
        dataRowMinHeight: sizes.tableDataRowMinHeight,
        dataRowMaxHeight: sizes.tableDataRowMaxHeight,
        dividerThickness: 1,
        headingTextStyle: _textTheme(context, fontKey: fontKey).labelLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        dataTextStyle: _textTheme(context, fontKey: fontKey).bodyMedium?.copyWith(color: scheme.onSurface),
      ),
      searchBarTheme: SearchBarThemeData(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(sizes.radiusMd))),
        hintStyle: WidgetStatePropertyAll(TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
        textStyle: WidgetStatePropertyAll(TextStyle(color: scheme.onSurface, fontSize: 14)),
      ),
    );
  }
}
