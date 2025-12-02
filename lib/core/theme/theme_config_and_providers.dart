import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retail_mvp2/core/theme/google_fonts_typography.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keys for persisting theme settings.
const _kThemeModeKey = 'app_theme_mode_v1';
const _kUIDensityKey = 'app_ui_density_v1';

// ═══════════════════════════════════════════════════════════════════════════
// UI DENSITY - User-selectable sizing (Small / Medium / Large)
// ═══════════════════════════════════════════════════════════════════════════

/// UI density levels - affects font sizes, spacing, component heights
enum UIDensity {
  compact,   // Small - tighter spacing, smaller fonts
  normal,    // Medium - default balanced
  comfortable, // Large - more spacing, larger fonts
}

extension UIDensityX on UIDensity {
  String get label => switch (this) {
    UIDensity.compact => 'Compact',
    UIDensity.normal => 'Normal',
    UIDensity.comfortable => 'Comfortable',
  };
  
  String get description => switch (this) {
    UIDensity.compact => 'Smaller text, tighter spacing',
    UIDensity.normal => 'Balanced default layout',
    UIDensity.comfortable => 'Larger text, more spacing',
  };
  
  IconData get icon => switch (this) {
    UIDensity.compact => Icons.density_small,
    UIDensity.normal => Icons.density_medium,
    UIDensity.comfortable => Icons.density_large,
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// SCREEN TYPE - Responsive breakpoints
// ═══════════════════════════════════════════════════════════════════════════

/// Screen types for responsive design
enum ScreenType { mobile, tablet, desktop }

/// Breakpoints for responsive design
class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 1024;
  // Anything >= tablet is desktop
  
  /// Get screen type from width
  static ScreenType fromWidth(double width) {
    if (width < mobile) return ScreenType.mobile;
    if (width < tablet) return ScreenType.tablet;
    return ScreenType.desktop;
  }
  
  /// Get screen type from context
  static ScreenType of(BuildContext context) {
    return fromWidth(MediaQuery.of(context).size.width);
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DENSITY CONTROLLER - Persists user's density preference
// ═══════════════════════════════════════════════════════════════════════════

class DensityController extends StateNotifier<UIDensity> {
  DensityController() : super(UIDensity.normal) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kUIDensityKey);
      state = switch (raw) {
        'compact' => UIDensity.compact,
        'comfortable' => UIDensity.comfortable,
        _ => UIDensity.normal,
      };
    } catch (_) {}
  }

  Future<void> set(UIDensity density) async {
    state = density;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kUIDensityKey, density.name);
    } catch (_) {}
  }
}

/// Provider for UIDensity
final uiDensityProvider = StateNotifierProvider<DensityController, UIDensity>((ref) => DensityController());

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
  final double radiusXs;
  final double radiusSm;
  final double radiusMd;
  final double radiusLg;
  final double radiusXl;

  // Gaps (spacing scale)
  final double gapXs;
  final double gapSm;
  final double gapMd;
  final double gapLg;
  final double gapXl;

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

  // Font sizes
  final double fontXs;
  final double fontSm;
  final double fontMd;
  final double fontLg;
  final double fontXl;
  final double fontXxl;

  // Icon sizes
  final double iconXs;
  final double iconSm;
  final double iconMd;
  final double iconLg;
  final double iconXl;

  // Component heights
  final double buttonHeightSm;
  final double buttonHeightMd;
  final double buttonHeightLg;
  final double inputHeightSm;
  final double inputHeightMd;
  final double inputHeightLg;

  // Card paddings
  final double cardPadSm;
  final double cardPadMd;
  final double cardPadLg;

  // Dialog sizes
  final double dialogWidthSm;
  final double dialogWidthMd;
  final double dialogWidthLg;

  const AppSizes({
    required this.radiusXs,
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusLg,
    required this.radiusXl,
    required this.gapXs,
    required this.gapSm,
    required this.gapMd,
    required this.gapLg,
    required this.gapXl,
    required this.fieldVPad,
    required this.fieldHPad,
    required this.buttonVPad,
    required this.buttonHPad,
    required this.tableHeadingRowHeight,
    required this.tableDataRowMinHeight,
    required this.tableDataRowMaxHeight,
    required this.fontXs,
    required this.fontSm,
    required this.fontMd,
    required this.fontLg,
    required this.fontXl,
    required this.fontXxl,
    required this.iconXs,
    required this.iconSm,
    required this.iconMd,
    required this.iconLg,
    required this.iconXl,
    required this.buttonHeightSm,
    required this.buttonHeightMd,
    required this.buttonHeightLg,
    required this.inputHeightSm,
    required this.inputHeightMd,
    required this.inputHeightLg,
    required this.cardPadSm,
    required this.cardPadMd,
    required this.cardPadLg,
    required this.dialogWidthSm,
    required this.dialogWidthMd,
    required this.dialogWidthLg,
  });

  static AppSizes defaults = const AppSizes(
    // Radii
    radiusXs: 4,
    radiusSm: 8,
    radiusMd: 12,
    radiusLg: 16,
    radiusXl: 24,
    // Gaps
    gapXs: 4,
    gapSm: 8,
    gapMd: 12,
    gapLg: 16,
    gapXl: 24,
    // Field paddings
    fieldVPad: 8,
    fieldHPad: 12,
    // Button paddings
    buttonVPad: 10,
    buttonHPad: 14,
    // Table sizes
    tableHeadingRowHeight: 44,
    tableDataRowMinHeight: 40,
    tableDataRowMaxHeight: 44,
    // Font sizes (based on common usage in codebase)
    fontXs: 9,
    fontSm: 11,
    fontMd: 13,
    fontLg: 16,
    fontXl: 20,
    fontXxl: 24,
    // Icon sizes
    iconXs: 14,
    iconSm: 18,
    iconMd: 22,
    iconLg: 28,
    iconXl: 36,
    // Button heights
    buttonHeightSm: 32,
    buttonHeightMd: 40,
    buttonHeightLg: 48,
    // Input heights
    inputHeightSm: 36,
    inputHeightMd: 44,
    inputHeightLg: 52,
    // Card paddings
    cardPadSm: 8,
    cardPadMd: 12,
    cardPadLg: 16,
    // Dialog widths
    dialogWidthSm: 320,
    dialogWidthMd: 480,
    dialogWidthLg: 640,
  );

  @override
  AppSizes copyWith({
    double? radiusXs,
    double? radiusSm,
    double? radiusMd,
    double? radiusLg,
    double? radiusXl,
    double? gapXs,
    double? gapSm,
    double? gapMd,
    double? gapLg,
    double? gapXl,
    double? fieldVPad,
    double? fieldHPad,
    double? buttonVPad,
    double? buttonHPad,
    double? tableHeadingRowHeight,
    double? tableDataRowMinHeight,
    double? tableDataRowMaxHeight,
    double? fontXs,
    double? fontSm,
    double? fontMd,
    double? fontLg,
    double? fontXl,
    double? fontXxl,
    double? iconXs,
    double? iconSm,
    double? iconMd,
    double? iconLg,
    double? iconXl,
    double? buttonHeightSm,
    double? buttonHeightMd,
    double? buttonHeightLg,
    double? inputHeightSm,
    double? inputHeightMd,
    double? inputHeightLg,
    double? cardPadSm,
    double? cardPadMd,
    double? cardPadLg,
    double? dialogWidthSm,
    double? dialogWidthMd,
    double? dialogWidthLg,
  }) => AppSizes(
        radiusXs: radiusXs ?? this.radiusXs,
        radiusSm: radiusSm ?? this.radiusSm,
        radiusMd: radiusMd ?? this.radiusMd,
        radiusLg: radiusLg ?? this.radiusLg,
        radiusXl: radiusXl ?? this.radiusXl,
        gapXs: gapXs ?? this.gapXs,
        gapSm: gapSm ?? this.gapSm,
        gapMd: gapMd ?? this.gapMd,
        gapLg: gapLg ?? this.gapLg,
        gapXl: gapXl ?? this.gapXl,
        fieldVPad: fieldVPad ?? this.fieldVPad,
        fieldHPad: fieldHPad ?? this.fieldHPad,
        buttonVPad: buttonVPad ?? this.buttonVPad,
        buttonHPad: buttonHPad ?? this.buttonHPad,
        tableHeadingRowHeight: tableHeadingRowHeight ?? this.tableHeadingRowHeight,
        tableDataRowMinHeight: tableDataRowMinHeight ?? this.tableDataRowMinHeight,
        tableDataRowMaxHeight: tableDataRowMaxHeight ?? this.tableDataRowMaxHeight,
        fontXs: fontXs ?? this.fontXs,
        fontSm: fontSm ?? this.fontSm,
        fontMd: fontMd ?? this.fontMd,
        fontLg: fontLg ?? this.fontLg,
        fontXl: fontXl ?? this.fontXl,
        fontXxl: fontXxl ?? this.fontXxl,
        iconXs: iconXs ?? this.iconXs,
        iconSm: iconSm ?? this.iconSm,
        iconMd: iconMd ?? this.iconMd,
        iconLg: iconLg ?? this.iconLg,
        iconXl: iconXl ?? this.iconXl,
        buttonHeightSm: buttonHeightSm ?? this.buttonHeightSm,
        buttonHeightMd: buttonHeightMd ?? this.buttonHeightMd,
        buttonHeightLg: buttonHeightLg ?? this.buttonHeightLg,
        inputHeightSm: inputHeightSm ?? this.inputHeightSm,
        inputHeightMd: inputHeightMd ?? this.inputHeightMd,
        inputHeightLg: inputHeightLg ?? this.inputHeightLg,
        cardPadSm: cardPadSm ?? this.cardPadSm,
        cardPadMd: cardPadMd ?? this.cardPadMd,
        cardPadLg: cardPadLg ?? this.cardPadLg,
        dialogWidthSm: dialogWidthSm ?? this.dialogWidthSm,
        dialogWidthMd: dialogWidthMd ?? this.dialogWidthMd,
        dialogWidthLg: dialogWidthLg ?? this.dialogWidthLg,
      );

  @override
  AppSizes lerp(ThemeExtension<AppSizes>? other, double t) {
    if (other is! AppSizes) return this;
    double l(double a, double b) => a + (b - a) * t;
    return AppSizes(
      radiusXs: l(radiusXs, other.radiusXs),
      radiusSm: l(radiusSm, other.radiusSm),
      radiusMd: l(radiusMd, other.radiusMd),
      radiusLg: l(radiusLg, other.radiusLg),
      radiusXl: l(radiusXl, other.radiusXl),
      gapXs: l(gapXs, other.gapXs),
      gapSm: l(gapSm, other.gapSm),
      gapMd: l(gapMd, other.gapMd),
      gapLg: l(gapLg, other.gapLg),
      gapXl: l(gapXl, other.gapXl),
      fieldVPad: l(fieldVPad, other.fieldVPad),
      fieldHPad: l(fieldHPad, other.fieldHPad),
      buttonVPad: l(buttonVPad, other.buttonVPad),
      buttonHPad: l(buttonHPad, other.buttonHPad),
      tableHeadingRowHeight: l(tableHeadingRowHeight, other.tableHeadingRowHeight),
      tableDataRowMinHeight: l(tableDataRowMinHeight, other.tableDataRowMinHeight),
      tableDataRowMaxHeight: l(tableDataRowMaxHeight, other.tableDataRowMaxHeight),
      fontXs: l(fontXs, other.fontXs),
      fontSm: l(fontSm, other.fontSm),
      fontMd: l(fontMd, other.fontMd),
      fontLg: l(fontLg, other.fontLg),
      fontXl: l(fontXl, other.fontXl),
      fontXxl: l(fontXxl, other.fontXxl),
      iconXs: l(iconXs, other.iconXs),
      iconSm: l(iconSm, other.iconSm),
      iconMd: l(iconMd, other.iconMd),
      iconLg: l(iconLg, other.iconLg),
      iconXl: l(iconXl, other.iconXl),
      buttonHeightSm: l(buttonHeightSm, other.buttonHeightSm),
      buttonHeightMd: l(buttonHeightMd, other.buttonHeightMd),
      buttonHeightLg: l(buttonHeightLg, other.buttonHeightLg),
      inputHeightSm: l(inputHeightSm, other.inputHeightSm),
      inputHeightMd: l(inputHeightMd, other.inputHeightMd),
      inputHeightLg: l(inputHeightLg, other.inputHeightLg),
      cardPadSm: l(cardPadSm, other.cardPadSm),
      cardPadMd: l(cardPadMd, other.cardPadMd),
      cardPadLg: l(cardPadLg, other.cardPadLg),
      dialogWidthSm: l(dialogWidthSm, other.dialogWidthSm),
      dialogWidthMd: l(dialogWidthMd, other.dialogWidthMd),
      dialogWidthLg: l(dialogWidthLg, other.dialogWidthLg),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RESPONSIVE FACTORY - Creates sizes based on screen type + user density
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get multiplier for density
  static double _densityMultiplier(UIDensity density) => switch (density) {
    UIDensity.compact => 0.85,
    UIDensity.normal => 1.0,
    UIDensity.comfortable => 1.15,
  };

  /// Get multiplier for screen type
  static double _screenMultiplier(ScreenType screen) => switch (screen) {
    ScreenType.mobile => 0.9,
    ScreenType.tablet => 1.0,
    ScreenType.desktop => 1.0,
  };

  /// Factory: Create AppSizes for given density and screen type
  static AppSizes forDensityAndScreen({
    required UIDensity density,
    required ScreenType screen,
  }) {
    final d = _densityMultiplier(density);
    final s = _screenMultiplier(screen);
    final m = d * s; // Combined multiplier
    
    return AppSizes(
      // Radii - don't scale much
      radiusXs: 4,
      radiusSm: 8,
      radiusMd: 12,
      radiusLg: 16,
      radiusXl: 24,
      // Gaps - scale with density
      gapXs: (4 * d).roundToDouble(),
      gapSm: (8 * d).roundToDouble(),
      gapMd: (12 * d).roundToDouble(),
      gapLg: (16 * d).roundToDouble(),
      gapXl: (24 * d).roundToDouble(),
      // Field paddings
      fieldVPad: (8 * d).roundToDouble(),
      fieldHPad: (12 * d).roundToDouble(),
      // Button paddings
      buttonVPad: (10 * d).roundToDouble(),
      buttonHPad: (14 * d).roundToDouble(),
      // Table sizes
      tableHeadingRowHeight: (44 * d).roundToDouble(),
      tableDataRowMinHeight: (40 * d).roundToDouble(),
      tableDataRowMaxHeight: (44 * d).roundToDouble(),
      // Font sizes - scale with both density and screen
      fontXs: (9 * m).roundToDouble(),
      fontSm: (11 * m).roundToDouble(),
      fontMd: (13 * m).roundToDouble(),
      fontLg: (16 * m).roundToDouble(),
      fontXl: (20 * m).roundToDouble(),
      fontXxl: (24 * m).roundToDouble(),
      // Icon sizes - scale with density
      iconXs: (14 * d).roundToDouble(),
      iconSm: (18 * d).roundToDouble(),
      iconMd: (22 * d).roundToDouble(),
      iconLg: (28 * d).roundToDouble(),
      iconXl: (36 * d).roundToDouble(),
      // Button heights - scale with density
      buttonHeightSm: (32 * d).roundToDouble(),
      buttonHeightMd: (40 * d).roundToDouble(),
      buttonHeightLg: (48 * d).roundToDouble(),
      // Input heights - scale with density
      inputHeightSm: (36 * d).roundToDouble(),
      inputHeightMd: (44 * d).roundToDouble(),
      inputHeightLg: (52 * d).roundToDouble(),
      // Card paddings - scale with density
      cardPadSm: (8 * d).roundToDouble(),
      cardPadMd: (12 * d).roundToDouble(),
      cardPadLg: (16 * d).roundToDouble(),
      // Dialog widths - scale with screen
      dialogWidthSm: switch (screen) {
        ScreenType.mobile => 280,
        ScreenType.tablet => 320,
        ScreenType.desktop => 360,
      },
      dialogWidthMd: switch (screen) {
        ScreenType.mobile => 340,
        ScreenType.tablet => 480,
        ScreenType.desktop => 520,
      },
      dialogWidthLg: switch (screen) {
        ScreenType.mobile => 400,
        ScreenType.tablet => 600,
        ScreenType.desktop => 700,
      },
    );
  }

  /// Convenience: Get sizes from context (auto-detects screen type)
  static AppSizes responsive(BuildContext context, UIDensity density) {
    final screen = Breakpoints.of(context);
    return forDensityAndScreen(density: density, screen: screen);
  }
}

class AppTheme {
  AppTheme._();

  // Single place to change brand color
  static const Color seed = Colors.indigo;

  // Delegates to global typography file.
  static TextTheme _textTheme(BuildContext context, {required String fontKey}) => AppTypography.buildTextTheme(context, fontKey: fontKey);

  static ThemeData light(BuildContext context, {required String fontKey, UIDensity density = UIDensity.normal}) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
    final sizes = AppSizes.responsive(context, density);
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

  static ThemeData dark(BuildContext context, {required String fontKey, UIDensity density = UIDensity.normal}) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
    final sizes = AppSizes.responsive(context, density);
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
