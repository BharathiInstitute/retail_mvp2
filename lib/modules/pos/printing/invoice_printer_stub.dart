// Stub implementation for platforms that don't support printing
// This file is used when neither dart:html nor dart:io is available

import 'dart:async';
import '../pos_invoices/invoice_models.dart';
import 'invoice_printer.dart';
import 'cloud_printer_settings.dart';
import 'receipt_settings.dart';

/// Stub for setCloudPrinterSettings (web-only)
void setCloudPrinterSettings(CloudPrinterSettings? settings) {
  // No-op on non-web platforms
}

/// Stub for setReceiptSettings
void setReceiptSettings(ReceiptSettings? settings) {
  // No-op on stub platform
}

/// Stub printer that returns not supported for all platforms
class InvoicePrinter implements InvoicePrinterBase {
  @override
  bool get isSupported => false;
  
  @override
  PrintMethod get defaultMethod => PrintMethod.notSupported;
  
  @override
  Future<PrintResult> printInvoice(InvoiceData invoice, {String? printerName}) async {
    return PrintResult.failure('Printing not supported on this platform');
  }
}
