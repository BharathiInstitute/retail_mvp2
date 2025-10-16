import 'package:flutter/material.dart';

/// Legacy printing demo removed. This placeholder kept only so existing routes don't break.
/// All printing is now handled through the POS screen which sends a PDF to the backend
/// and prints directly to the system default printer (configured outside the app).
class PrintDemoPage extends StatelessWidget {
  const PrintDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Printing demo removed. Use the POS screen for one-click invoice printing to the default printer.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
