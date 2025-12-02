// Unified Invoice Printer Service
// Handles printing on all platforms: Web, Windows, macOS, Linux, iOS, Android
// 
// Usage:
//   final result = await unifiedPrintInvoice(invoiceData);
//   if (result.success) { /* printed */ }
//
// Or use the singleton:
//   final result = await invoicePrinter.printInvoice(invoiceData);
//
// The service automatically detects the platform and uses the appropriate method:
// - Web: Opens browser print dialog with formatted HTML
// - Windows: Silent printing via PowerShell (hidden window)
// - macOS/Linux: Uses lpr command
// - Other platforms: Returns not supported

import 'dart:async';
import '../pos_invoices/invoice_models.dart';
import 'print_settings.dart';

// Conditional imports for platform-specific implementations
import 'invoice_printer_stub.dart'
    if (dart.library.html) 'invoice_printer_web.dart'
    if (dart.library.io) 'invoice_printer_io.dart';

// Re-export setCloudPrinterSettings and setReceiptSettings for use from POS screens
export 'invoice_printer_stub.dart'
    if (dart.library.html) 'invoice_printer_web.dart'
    if (dart.library.io) 'invoice_printer_io.dart'
    show setCloudPrinterSettings, setReceiptSettings;

// ============================================================================
// Simplified top-level API - Use these for easy integration
// ============================================================================

/// Simple function to print an invoice on any platform.
/// Returns true if printing was successful.
Future<bool> unifiedPrintInvoice(InvoiceData invoice, {String? printerName}) async {
  final result = await invoicePrinter.printInvoice(invoice, printerName: printerName);
  return result.success;
}

/// Check if printing is available on this platform
bool get isPrintingSupported => invoicePrinter.isSupported;

/// Result of a print operation
class PrintResult {
  final bool success;
  final String? message;
  final PrintMethod? methodUsed;
  
  const PrintResult({
    required this.success,
    this.message,
    this.methodUsed,
  });
  
  factory PrintResult.success([PrintMethod? method]) => PrintResult(
    success: true,
    methodUsed: method,
  );
  
  factory PrintResult.failure(String message) => PrintResult(
    success: false,
    message: message,
  );
}

/// Available print methods
enum PrintMethod {
  webBrowserDialog,    // Web: browser's print dialog
  windowsPowerShell,   // Windows: hidden PowerShell printing
  backendService,      // Any: send to backend print service
  notSupported,        // Platform doesn't support printing
}

/// Unified printer interface
abstract class InvoicePrinterBase {
  /// Print an invoice using the best available method for the platform
  Future<PrintResult> printInvoice(InvoiceData invoice, {String? printerName});
  
  /// Check if printing is supported on this platform
  bool get isSupported;
  
  /// Get the default print method for this platform
  PrintMethod get defaultMethod;
}

/// Global invoice printer instance
final InvoicePrinter invoicePrinter = InvoicePrinter();

// ============================================================================
// Shared Receipt Formatting Utilities
// ============================================================================

/// Format an invoice as plain text for thermal receipt printing
String formatInvoiceReceipt(InvoiceData inv, {int width = 42}) {
  String line([String ch = '-']) => ''.padRight(width, ch);
  String money(num v) => v.toStringAsFixed(2);
  String padRight(String text, int w) {
    if (text.length > w) return text.substring(0, w);
    return text + ' ' * (w - text.length);
  }
  String padLeft(String text, int w) {
    if (text.length >= w) return text;
    return ' ' * (w - text.length) + text;
  }
  String center(String text) {
    if (text.length >= width) return text;
    final pad = (width - text.length) ~/ 2;
    return ' ' * pad + text;
  }
  
  final b = StringBuffer();
  
  // Header
  b.writeln(center('Invoice'));
  b.writeln(center(inv.invoiceNumber));
  b.writeln('');
  
  // Date and customer info
  final dt = inv.timestamp.toLocal();
  final dateStr = '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')} '
      '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}:${dt.second.toString().padLeft(2,'0')}';
  b.writeln('Date: $dateStr');
  b.writeln('Customer: ${inv.customerName}');
  if ((inv.customerPhone ?? '').isNotEmpty) {
    b.writeln('Phone: ${inv.customerPhone}');
  }
  if ((inv.customerEmail ?? '').isNotEmpty) {
    b.writeln('Email: ${inv.customerEmail}');
  }
  b.writeln('');
  
  // Column header based on width
  // Item: 18, Qty: 4, Price: 10, Total: 10 = 42 for standard width
  final itemWidth = (width * 0.43).floor(); // ~43% for item name
  final qtyWidth = 4;
  final priceWidth = ((width - itemWidth - qtyWidth) / 2).floor();
  final totalWidth = width - itemWidth - qtyWidth - priceWidth;
  
  b.writeln(padRight('Item', itemWidth) + 
            padLeft('Qty', qtyWidth) + 
            padLeft('Price', priceWidth) + 
            padLeft('Total', totalWidth));
  b.writeln(line());
  
  // Line items
  for (final l in inv.lines) {
    // Wrap long item names
    var name = l.name.trim();
    if (name.length > itemWidth) {
      // First line with values
      b.writeln(padRight(name.substring(0, itemWidth), itemWidth) +
                padLeft(l.qty.toString(), qtyWidth) +
                padLeft(money(l.unitPrice), priceWidth) +
                padLeft(money(l.lineTotal), totalWidth));
      // Continuation lines
      name = name.substring(itemWidth);
      while (name.isNotEmpty) {
        final chunk = name.length > itemWidth ? name.substring(0, itemWidth) : name;
        b.writeln(chunk);
        name = name.length > itemWidth ? name.substring(itemWidth) : '';
      }
    } else {
      b.writeln(padRight(name, itemWidth) +
                padLeft(l.qty.toString(), qtyWidth) +
                padLeft(money(l.unitPrice), priceWidth) +
                padLeft(money(l.lineTotal), totalWidth));
    }
  }
  
  b.writeln(line());
  
  // Summary
  final labelWidth = (width * 0.55).floor();
  final valueWidth = width - labelWidth;
  
  b.writeln(padRight('Subtotal', labelWidth) + padLeft(money(inv.subtotal), valueWidth));
  b.writeln(padRight('Discount', labelWidth) + padLeft('-${money(inv.discountTotal)}', valueWidth));
  b.writeln(padRight('Tax', labelWidth) + padLeft(money(inv.taxTotal), valueWidth));
  if (inv.redeemedValue > 0) {
    b.writeln(padRight('Redeemed', labelWidth) + padLeft('-${money(inv.redeemedValue)}', valueWidth));
  }
  b.writeln(line('='));
  b.writeln(padRight('Grand Total', labelWidth) + padLeft(money(inv.grandTotal), valueWidth));
  b.writeln(padRight('Payment Mode', labelWidth) + padLeft(inv.paymentMode, valueWidth));
  b.writeln('');
  b.writeln(center('Thank you for your purchase!'));
  
  return b.toString();
}

/// Build HTML for browser printing
String buildPrintableHtml(InvoiceData inv, {int width = 42}) {
  final plain = formatInvoiceReceipt(inv, width: width);
  final escaped = plain
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  
  final htmlBuf = StringBuffer();
  htmlBuf.writeln('<!DOCTYPE html><html><head><meta charset="utf-8">');
  htmlBuf.writeln('<meta name="viewport" content="width=device-width,initial-scale=1">');
  htmlBuf.writeln('<title>Invoice ${inv.invoiceNumber.replaceAll('<', '').replaceAll('>', '')}</title>');
  htmlBuf.writeln('<style>');
  htmlBuf.writeln('@page { margin: 2mm 2mm 4mm 2mm; }');
  htmlBuf.writeln('body { margin: 0; font-family: "Courier New", Consolas, monospace; font-size: 11px; line-height: 1.3; }');
  htmlBuf.writeln('pre { margin: 0; white-space: pre-wrap; word-wrap: break-word; }');
  htmlBuf.writeln('@media print { body { width: 100%; } }');
  htmlBuf.writeln('</style></head><body>');
  htmlBuf.writeln('<pre>$escaped</pre>');
  htmlBuf.writeln('<script>');
  htmlBuf.writeln('window.addEventListener("load", function() {');
  htmlBuf.writeln('  setTimeout(function() { try { window.print(); } catch(e) {} }, 50);');
  htmlBuf.writeln('});');
  htmlBuf.writeln('</script>');
  htmlBuf.writeln('</body></html>');
  
  return htmlBuf.toString();
}

/// Get receipt width from settings
int getReceiptWidth() {
  final settings = globalPrintSettings;
  if (settings.paperSize == PaperSize.receipt) {
    return settings.scaleToFit ? settings.derivedCharWidth() : settings.receiptCharWidth;
  }
  return 80; // A4 fallback
}
