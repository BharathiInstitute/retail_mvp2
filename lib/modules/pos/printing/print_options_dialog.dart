import 'package:flutter/material.dart';
import 'print_settings.dart';

/// Session (in‑memory) preference: whether to show print settings automatically before web printing.
/// Defaults to true so users see the configuration the first time.
// Default changed to false so Print button acts immediately; user can still open settings via gear.
bool globalShowWebPrintSettingsPref = false; // not persisted yet

/// Opens the print settings dialog. If [showPrintButton] is true, a primary 'Print Now' button
/// is shown and the `Future<bool>` resolves true only when the user chooses to proceed with printing.
/// When invoked with [showPrintButton], a "Don't show again" checkbox lets the user skip
/// future auto display before printing (session only for now).
Future<bool> showPrintSettingsDialog(BuildContext context, {bool showPrintButton = false}) async {
  final ps = globalPrintSettings;
  int tempWidth = ps.receiptCharWidth;
  int tempPaperMm = ps.paperWidthMm;
  int tempFontSize = ps.fontSizePt;
  PaperSize tempSize = ps.paperSize;
  PageOrientation tempOrientation = ps.orientation;
  bool tempScale = ps.scaleToFit;
  bool dontShowAgain = false;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: !showPrintButton, // force explicit choice when printing
    builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setLocal) {
        final scheme = Theme.of(ctx).colorScheme;
        final texts = Theme.of(ctx).textTheme;
        int previewWidth = tempScale && tempSize == PaperSize.receipt
            ? _deriveCharWidth(tempPaperMm)
            : tempWidth;
        return AlertDialog(
          title: Text(
            showPrintButton ? 'Print Settings & Preview' : 'Print Settings',
            style: texts.titleMedium?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w700),
          ),
          content: DefaultTextStyle(
            style: texts.bodyMedium?.copyWith(color: scheme.onSurface) ?? const TextStyle(),
            child: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Text('Paper:'), const SizedBox(width: 8),
                      DropdownButton<PaperSize>(
                        value: tempSize,
                        items: const [
                          DropdownMenuItem(value: PaperSize.receipt, child: Text('Receipt (Thermal)')),
                          DropdownMenuItem(value: PaperSize.a4, child: Text('A4')),
                        ],
                        onChanged: (v) { if (v != null) setLocal(() => tempSize = v); },
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      const Text('Orientation:'), const SizedBox(width: 8),
                      DropdownButton<PageOrientation>(
                        value: tempOrientation,
                        items: const [
                          DropdownMenuItem(value: PageOrientation.portrait, child: Text('Portrait')),
                          DropdownMenuItem(value: PageOrientation.landscape, child: Text('Landscape')),
                        ],
                        onChanged: tempSize == PaperSize.receipt ? null : (v) { if (v != null) setLocal(() => tempOrientation = v); },
                      ),
                    ]),
                    if (tempSize == PaperSize.receipt) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        const Text('Width (mm):'), const SizedBox(width: 8),
                        DropdownButton<int>(
                          value: tempPaperMm,
                          items: const [
                            DropdownMenuItem(value: 48, child: Text('48 mm')),
                            DropdownMenuItem(value: 58, child: Text('58 mm')),
                            DropdownMenuItem(value: 80, child: Text('80 mm')),
                          ],
                          onChanged: (v) { if (v != null) setLocal(() => tempPaperMm = v); },
                        ),
                      ]),
                    ],
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Auto scale to paper width'),
                      value: tempScale,
                      onChanged: (v) => setLocal(() => tempScale = v),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      const Text('Font size:'), const SizedBox(width: 8),
                      Expanded(
                        child: Slider(
                          min: 6,
                          max: 24,
                          divisions: 18,
                          value: tempFontSize.toDouble(),
                          label: '${tempFontSize}pt',
                          onChanged: (v) => setLocal(() => tempFontSize = v.round()),
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(
                          '${tempFontSize}pt',
                          textAlign: TextAlign.right,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ]),
                    if (tempSize == PaperSize.receipt) ...[
                      const SizedBox(height: 8),
                      const Text('Receipt Character Width'),
                      Slider(
                        min: 20,
                        max: 80,
                        divisions: 60,
                        value: tempWidth.toDouble(),
                        label: '$tempWidth',
                        onChanged: (v) => setLocal(() => tempWidth = v.round()),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Preview width: $previewWidth chars • Font ${tempFontSize}pt (${tempSize == PaperSize.receipt ? '${tempPaperMm}mm' : 'A4'})',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(fontStyle: FontStyle.italic),
                    ),
                    if (showPrintButton) ...[
                      const Divider(height: 24),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text("Don't show before printing again"),
                        value: dontShowAgain,
                        onChanged: (v) => setLocal(() => dontShowAgain = v ?? false),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: ()=> Navigator.pop(ctx, false), child: Text(showPrintButton ? 'Cancel' : 'Close')),
            TextButton(
              onPressed: () {
                // Save settings only when explicitly applying changes.
                ps.update(
                  paperSize: tempSize,
                  orientation: tempOrientation,
                  scaleToFit: tempScale,
                  receiptCharWidth: tempWidth,
                  paperWidthMm: tempPaperMm,
                  fontSizePt: tempFontSize,
                );
                if (showPrintButton && dontShowAgain) {
                  globalShowWebPrintSettingsPref = false;
                }
                Navigator.pop(ctx, showPrintButton); // true if printing, false otherwise
              },
              child: Text(showPrintButton ? 'Print Now' : 'Save'),
            )
          ],
        );
      });
    }
  );

  return result == true && showPrintButton; // proceed only when Print Now pressed
}

int _deriveCharWidth(int mm) {
  if (mm <= 50) return 32;
  if (mm <= 60) return 40;
  if (mm <= 72) return 48;
  if (mm <= 86) return 56;
  return 64;
}
