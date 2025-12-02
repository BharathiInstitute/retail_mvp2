import 'package:flutter/material.dart';
import 'package:retail_mvp2/core/theme/theme_extension_helpers.dart';

/// Button size variants
enum ButtonSize { sm, md, lg }

/// Button style variants
enum ButtonVariant { primary, secondary, outlined, ghost, danger }

/// A themed button widget with consistent styling and variants.
/// 
/// Usage:
/// ```dart
/// AppButton(
///   label: 'Save',
///   onPressed: () => save(),
///   variant: ButtonVariant.primary,
///   size: ButtonSize.md,
///   icon: Icons.save,
/// )
/// ```
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = ButtonVariant.primary,
    this.size = ButtonSize.md,
    this.icon,
    this.iconPosition = IconPosition.leading,
    this.isLoading = false,
    this.isExpanded = false,
    this.tooltip,
  });

  /// Button label text
  final String label;
  
  /// Press callback (null = disabled)
  final VoidCallback? onPressed;
  
  /// Visual style variant
  final ButtonVariant variant;
  
  /// Size variant
  final ButtonSize size;
  
  /// Optional icon
  final IconData? icon;
  
  /// Icon position (leading or trailing)
  final IconPosition iconPosition;
  
  /// Show loading indicator
  final bool isLoading;
  
  /// Expand to fill available width
  final bool isExpanded;
  
  /// Tooltip text
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final sizes = context.sizes;
    final cs = context.colors;
    
    // Size-based dimensions
    final (height, fontSize, iconSize, hPadding) = switch (size) {
      ButtonSize.sm => (sizes.buttonHeightSm, sizes.fontSm, sizes.iconSm, sizes.gapSm),
      ButtonSize.md => (sizes.buttonHeightMd, sizes.fontMd, sizes.iconMd, sizes.gapMd),
      ButtonSize.lg => (sizes.buttonHeightLg, sizes.fontLg, sizes.iconLg, sizes.gapLg),
    };
    
    // Variant-based colors
    final (bgColor, fgColor, borderColor) = switch (variant) {
      ButtonVariant.primary => (cs.primary, cs.onPrimary, Colors.transparent),
      ButtonVariant.secondary => (cs.secondaryContainer, cs.onSecondaryContainer, Colors.transparent),
      ButtonVariant.outlined => (Colors.transparent, cs.primary, cs.outline),
      ButtonVariant.ghost => (Colors.transparent, cs.primary, Colors.transparent),
      ButtonVariant.danger => (cs.error, cs.onError, Colors.transparent),
    };
    
    final buttonStyle = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, height)),
      maximumSize: WidgetStatePropertyAll(Size(double.infinity, height)),
      padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: hPadding)),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return bgColor.withOpacity(0.5);
        }
        if (states.contains(WidgetState.hovered)) {
          return variant == ButtonVariant.ghost || variant == ButtonVariant.outlined
            ? cs.primary.withOpacity(0.08)
            : bgColor.withOpacity(0.9);
        }
        return bgColor;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return fgColor.withOpacity(0.5);
        }
        return fgColor;
      }),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(sizes.radiusMd),
          side: borderColor != Colors.transparent 
            ? BorderSide(color: borderColor, width: 1)
            : BorderSide.none,
        ),
      ),
      elevation: const WidgetStatePropertyAll(0),
      textStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
      ),
    );
    
    // Build content
    Widget content;
    if (isLoading) {
      content = SizedBox(
        width: iconSize,
        height: iconSize,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(fgColor),
        ),
      );
    } else if (icon != null) {
      final iconWidget = Icon(icon, size: iconSize);
      final textWidget = Text(label);
      final gap = SizedBox(width: sizes.gapSm);
      
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: iconPosition == IconPosition.leading
          ? [iconWidget, gap, textWidget]
          : [textWidget, gap, iconWidget],
      );
    } else {
      content = Text(label);
    }
    
    Widget button = ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      style: buttonStyle,
      child: content,
    );
    
    if (isExpanded) {
      button = SizedBox(width: double.infinity, child: button);
    }
    
    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    
    return button;
  }
}

/// Icon position in button
enum IconPosition { leading, trailing }

/// Icon-only button variant
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.variant = ButtonVariant.ghost,
    this.size = ButtonSize.md,
    this.tooltip,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final ButtonVariant variant;
  final ButtonSize size;
  final String? tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final sizes = context.sizes;
    final cs = context.colors;
    
    final (buttonSize, iconSize) = switch (size) {
      ButtonSize.sm => (sizes.buttonHeightSm, sizes.iconSm),
      ButtonSize.md => (sizes.buttonHeightMd, sizes.iconMd),
      ButtonSize.lg => (sizes.buttonHeightLg, sizes.iconLg),
    };
    
    final effectiveColor = color ?? switch (variant) {
      ButtonVariant.primary => cs.onPrimary,
      ButtonVariant.secondary => cs.onSecondaryContainer,
      ButtonVariant.outlined => cs.primary,
      ButtonVariant.ghost => cs.onSurfaceVariant,
      ButtonVariant.danger => cs.error,
    };
    
    final bgColor = switch (variant) {
      ButtonVariant.primary => cs.primary,
      ButtonVariant.secondary => cs.secondaryContainer,
      ButtonVariant.outlined => Colors.transparent,
      ButtonVariant.ghost => Colors.transparent,
      ButtonVariant.danger => cs.errorContainer,
    };
    
    Widget button = Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(sizes.radiusMd),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(sizes.radiusMd),
        child: SizedBox(
          width: buttonSize,
          height: buttonSize,
          child: Icon(icon, size: iconSize, color: effectiveColor),
        ),
      ),
    );
    
    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    
    return button;
  }
}

/// Text button (minimal styling)
class AppTextButton extends StatelessWidget {
  const AppTextButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.size = ButtonSize.md,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ButtonSize size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final sizes = context.sizes;
    final cs = context.colors;
    
    final fontSize = switch (size) {
      ButtonSize.sm => sizes.fontSm,
      ButtonSize.md => sizes.fontMd,
      ButtonSize.lg => sizes.fontLg,
    };
    
    final iconSize = switch (size) {
      ButtonSize.sm => sizes.iconSm,
      ButtonSize.md => sizes.iconMd,
      ButtonSize.lg => sizes.iconLg,
    };
    
    final effectiveColor = color ?? cs.primary;
    
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: effectiveColor,
        textStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
        padding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapXs),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: iconSize),
            SizedBox(width: sizes.gapXs),
          ],
          Text(label),
        ],
      ),
    );
  }
}
