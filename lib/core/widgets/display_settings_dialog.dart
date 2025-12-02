import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/theme_config_and_providers.dart';
import '../theme/theme_extension_helpers.dart';
import '../theme/font_preference_controller.dart';

/// A settings dialog for theme, density, and font preferences
class SettingsDialog extends ConsumerWidget {
  const SettingsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (_) => const SettingsDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final density = ref.watch(uiDensityProvider);
    final fontKey = ref.watch(fontProvider);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.settings_outlined, color: cs.primary),
          context.gapHMd,
          const Text('Display Settings'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Theme Mode Section
              _SectionHeader(icon: Icons.palette_outlined, title: 'Theme'),
              context.gapVSm,
              _ThemeModeSelector(
                value: themeMode,
                onChanged: (mode) => ref.read(themeModeProvider.notifier).set(mode),
              ),
              
              context.gapVMd,
              const Divider(),
              context.gapVMd,
              
              // Density Section
              _SectionHeader(icon: Icons.view_compact_outlined, title: 'UI Density'),
              context.gapVXs,
              Text(
                'Adjust spacing and sizing across the app',
                style: context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              context.gapVSm,
              _DensitySelector(
                value: density,
                onChanged: (d) => ref.read(uiDensityProvider.notifier).set(d),
              ),
              
              context.gapVMd,
              const Divider(),
              context.gapVMd,
              
              // Font Section
              _SectionHeader(icon: Icons.text_fields_outlined, title: 'Font'),
              context.gapVSm,
              _FontSelector(
                value: fontKey,
                onChanged: (f) => ref.read(fontProvider.notifier).set(f),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        context.gapHSm,
        Text(
          title,
          style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _ThemeModeSelector extends StatelessWidget {
  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  const _ThemeModeSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(
          value: ThemeMode.system,
          icon: Icon(Icons.brightness_auto),
          label: Text('System'),
        ),
        ButtonSegment(
          value: ThemeMode.light,
          icon: Icon(Icons.light_mode),
          label: Text('Light'),
        ),
        ButtonSegment(
          value: ThemeMode.dark,
          icon: Icon(Icons.dark_mode),
          label: Text('Dark'),
        ),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
      showSelectedIcon: false,
    );
  }
}

class _DensitySelector extends StatelessWidget {
  final UIDensity value;
  final ValueChanged<UIDensity> onChanged;

  const _DensitySelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Column(
      children: UIDensity.values.map((d) {
        final isSelected = d == value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: isSelected ? cs.primaryContainer : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => onChanged(d),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      d.icon,
                      color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                    ),
                    context.gapHMd,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.label,
                            style: context.texts.titleSmall?.copyWith(
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                              color: isSelected ? cs.onPrimaryContainer : cs.onSurface,
                            ),
                          ),
                          Text(
                            d.description,
                            style: context.texts.bodySmall?.copyWith(
                              color: isSelected ? cs.onPrimaryContainer.withOpacity(0.8) : cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_circle, color: cs.primary),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _FontSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _FontSelector({required this.value, required this.onChanged});

  static const _fonts = {
    'system': 'System Default',
    'inter': 'Inter',
    'roboto': 'Roboto',
    'poppins': 'Poppins',
    'opensans': 'Open Sans',
    'lato': 'Lato',
    'nunito': 'Nunito',
  };

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      items: _fonts.entries.map((e) {
        return DropdownMenuItem(
          value: e.key,
          child: Text(e.value),
        );
      }).toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
