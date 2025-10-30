import 'package:flutter/material.dart';

/// Tiny non-interactive badge indicating the current device class
/// based on available width. Safe to overlay anywhere.
class DeviceClassIcon extends StatelessWidget {
  final EdgeInsets padding;
  const DeviceClassIcon({super.key, this.padding = const EdgeInsets.all(6)});

  @override
  Widget build(BuildContext context) {
    // Hidden as per request: remove labels and icons entirely
    return const SizedBox.shrink();
  }

  // Helper removed since badge is hidden
}
