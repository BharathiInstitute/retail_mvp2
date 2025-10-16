import 'package:flutter/foundation.dart';

/// Supported paper sizes (simplified for POS thermal + A4 scenarios).
enum PaperSize { receipt, a4 }

/// Orientation for larger page formats.
enum PageOrientation { portrait, landscape }

/// User-configurable print formatting options stored in-memory (could later persist via shared_preferences).
class PrintSettings extends ChangeNotifier {
  PaperSize paperSize;
  PageOrientation orientation; // only relevant for A4 currently
  bool scaleToFit; // whether to scale width to selected page width
  int receiptCharWidth; // effective character width for receipt text formatting
  int paperWidthMm; // physical thermal roll width (e.g. 58 / 80)
  int fontSizePt; // monospace font size (points) for direct text printing

  PrintSettings({
    this.paperSize = PaperSize.receipt,
    this.orientation = PageOrientation.portrait,
    this.scaleToFit = false, // default off so explicit char width (24) is respected
  this.receiptCharWidth = 20, // updated default to allow 20-char receipt width
    this.paperWidthMm = 58,
    this.fontSizePt = 9,
  });

  void update({
    PaperSize? paperSize,
    PageOrientation? orientation,
    bool? scaleToFit,
    int? receiptCharWidth,
    int? paperWidthMm,
    int? fontSizePt,
  }) {
    bool changed = false;
    if (paperSize != null && paperSize != this.paperSize) { this.paperSize = paperSize; changed = true; }
    if (orientation != null && orientation != this.orientation) { this.orientation = orientation; changed = true; }
    if (scaleToFit != null && scaleToFit != this.scaleToFit) { this.scaleToFit = scaleToFit; changed = true; }
    if (receiptCharWidth != null && receiptCharWidth != this.receiptCharWidth) { this.receiptCharWidth = receiptCharWidth; changed = true; }
    if (paperWidthMm != null && paperWidthMm != this.paperWidthMm) { this.paperWidthMm = paperWidthMm; changed = true; }
    if (fontSizePt != null && fontSizePt != this.fontSizePt) { this.fontSizePt = fontSizePt.clamp(6, 24); changed = true; }
    if (changed) notifyListeners();
  }

  /// Derive char width from paper width when auto scaling.
  int derivedCharWidth() {
    if (paperSize != PaperSize.receipt) return receiptCharWidth;
    final mm = paperWidthMm;
    if (mm <= 50) return 32; // very narrow
    if (mm <= 60) return 40; // 58mm
    if (mm <= 72) return 48; // mid
    if (mm <= 86) return 56; // 80mm
    return 64; // super wide fallback
  }
}

// Global (simple) singleton for now; could be provided via Riverpod or InheritedWidget later.
final PrintSettings globalPrintSettings = PrintSettings();
