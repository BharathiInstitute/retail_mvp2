// Fallback stub for non-web platforms: returns false meaning not handled.
import 'invoice_models.dart';

Future<bool> webFallbackPrintInvoice(InvoiceData invoice) async {
  return false; // Not supported off-web.
}

// Stub types and functions for non-web platforms
class PrintWindowHandle {}
PrintWindowHandle? webPrintPreopen() => null;
Future<bool> webPrintPopulateAndPrint(PrintWindowHandle? handle, InvoiceData invoice) async => false;
void webPrintClose(PrintWindowHandle? handle) {}
