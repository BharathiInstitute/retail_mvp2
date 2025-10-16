// Stub for non-Windows or platforms where direct PowerShell printing is unavailable.
// The real implementation lives in windows_print.dart (conditionally imported).
import 'invoice_models.dart';

/// Attempts to print an invoice directly via Windows PowerShell (hidden window).
/// On non-Windows platforms or when unsupported returns false immediately.
Future<bool> directWindowsPrintInvoice(InvoiceData invoice, {String? printerName}) async {
  return false; // Not supported on this platform build.
}
