import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:retail_mvp2/core/theme/theme_utils.dart';

/// Field size variants
enum FieldSize { sm, md, lg }

/// A themed text field widget with consistent styling.
/// 
/// Usage:
/// ```dart
/// AppTextField(
///   label: 'Email',
///   hint: 'Enter your email',
///   controller: emailController,
///   prefixIcon: Icons.email,
///   size: FieldSize.md,
/// )
/// ```
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.errorText,
    this.helperText,
    this.prefixIcon,
    this.suffixIcon,
    this.prefix,
    this.suffix,
    this.size = FieldSize.md,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.focusNode,
    this.textAlign = TextAlign.start,
    this.textCapitalization = TextCapitalization.none,
    this.filled = true,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final String? helperText;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final Widget? prefix;
  final Widget? suffix;
  final FieldSize size;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final TextAlign textAlign;
  final TextCapitalization textCapitalization;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final sizes = context.sizes;
    final cs = context.colors;
    
    // Size-based dimensions
    final (contentPadding, fontSize, iconSize) = switch (size) {
      FieldSize.sm => (
        EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapXs),
        sizes.fontSm,
        sizes.iconSm,
      ),
      FieldSize.md => (
        EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapSm),
        sizes.fontMd,
        sizes.iconMd,
      ),
      FieldSize.lg => (
        EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapMd),
        sizes.fontLg,
        sizes.iconLg,
      ),
    };
    
    final decoration = InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: errorText,
      helperText: helperText,
      filled: filled,
      fillColor: cs.surfaceContainerLow,
      contentPadding: contentPadding,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: iconSize) : null,
      suffixIcon: suffixIcon != null ? Icon(suffixIcon, size: iconSize) : null,
      prefix: prefix,
      suffix: suffix,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(sizes.radiusMd),
        borderSide: BorderSide(color: cs.outline.withOpacity(0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(sizes.radiusMd),
        borderSide: BorderSide(color: cs.outline.withOpacity(0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(sizes.radiusMd),
        borderSide: BorderSide(color: cs.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(sizes.radiusMd),
        borderSide: BorderSide(color: cs.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(sizes.radiusMd),
        borderSide: BorderSide(color: cs.error, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(sizes.radiusMd),
        borderSide: BorderSide(color: cs.outline.withOpacity(0.2)),
      ),
      labelStyle: TextStyle(fontSize: fontSize, color: cs.onSurfaceVariant),
      hintStyle: TextStyle(fontSize: fontSize, color: cs.onSurfaceVariant.withOpacity(0.6)),
      errorStyle: TextStyle(fontSize: sizes.fontXs, color: cs.error),
      helperStyle: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant),
    );
    
    return TextField(
      controller: controller,
      focusNode: focusNode,
      decoration: decoration,
      style: TextStyle(fontSize: fontSize, color: cs.onSurface),
      obscureText: obscureText,
      enabled: enabled,
      readOnly: readOnly,
      autofocus: autofocus,
      maxLines: obscureText ? 1 : maxLines,
      minLines: minLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTap: onTap,
      textAlign: textAlign,
      textCapitalization: textCapitalization,
    );
  }
}

/// A themed search field with clear button
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    this.controller,
    this.hint = 'Search...',
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.size = FieldSize.md,
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final FieldSize size;
  final bool autofocus;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late TextEditingController _controller;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _hasText = _controller.text.isNotEmpty;
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final hasText = _controller.text.isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
    widget.onClear?.call();
  }

  @override
  Widget build(BuildContext context) {
    final sizes = context.sizes;
    
    final iconSize = switch (widget.size) {
      FieldSize.sm => sizes.iconSm,
      FieldSize.md => sizes.iconMd,
      FieldSize.lg => sizes.iconLg,
    };
    
    return AppTextField(
      controller: _controller,
      hint: widget.hint,
      prefixIcon: Icons.search,
      size: widget.size,
      autofocus: widget.autofocus,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      suffix: _hasText 
        ? GestureDetector(
            onTap: _clear,
            child: Icon(Icons.clear, size: iconSize, color: context.colors.onSurfaceVariant),
          )
        : null,
    );
  }
}

/// A themed dropdown field
class AppDropdownField<T> extends StatelessWidget {
  const AppDropdownField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.hint,
    this.errorText,
    this.size = FieldSize.md,
    this.enabled = true,
    this.isExpanded = true,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? label;
  final String? hint;
  final String? errorText;
  final FieldSize size;
  final bool enabled;
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final sizes = context.sizes;
    final cs = context.colors;
    
    final (contentPadding, fontSize) = switch (size) {
      FieldSize.sm => (
        EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapXs),
        sizes.fontSm,
      ),
      FieldSize.md => (
        EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapSm),
        sizes.fontMd,
      ),
      FieldSize.lg => (
        EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapMd),
        sizes.fontLg,
      ),
    };
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(label!, style: context.labelSm),
          SizedBox(height: sizes.gapXs),
        ],
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(sizes.radiusMd),
            border: Border.all(
              color: errorText != null ? cs.error : cs.outline.withOpacity(0.3),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              items: items,
              onChanged: enabled ? onChanged : null,
              hint: hint != null ? Text(hint!, style: TextStyle(fontSize: fontSize, color: cs.onSurfaceVariant.withOpacity(0.6))) : null,
              isExpanded: isExpanded,
              padding: contentPadding,
              borderRadius: BorderRadius.circular(sizes.radiusMd),
              style: TextStyle(fontSize: fontSize, color: cs.onSurface),
              icon: Icon(Icons.keyboard_arrow_down, size: sizes.iconMd, color: cs.onSurfaceVariant),
            ),
          ),
        ),
        if (errorText != null) ...[
          SizedBox(height: sizes.gapXs),
          Text(errorText!, style: TextStyle(fontSize: sizes.fontXs, color: cs.error)),
        ],
      ],
    );
  }
}
