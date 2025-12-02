// Web-specific implementation using dart:html
// This file is only imported when running on web platforms
//
// Strategy:
// 1. Try PrintNode cloud printing first (if configured)
// 2. Try local backend service for silent printing
// 3. Fall back to browser print dialog

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js' as js;
import 'package:http/http.dart' as http;
import '../pos_invoices/invoice_models.dart';
import 'invoice_printer.dart';
import 'printnode_service.dart';
import 'cloud_printer_settings.dart';
import 'receipt_settings.dart';

/// Cached cloud printer settings
CloudPrinterSettings? _cachedSettings;

/// Cached receipt settings (includes selected printer name)
ReceiptSettings? _cachedReceiptSettings;

/// Set the current store's printer settings (called from POS UI)
void setCloudPrinterSettings(CloudPrinterSettings? settings) {
  _cachedSettings = settings;
}

/// Set receipt settings including selected printer (called from POS UI)
void setReceiptSettings(ReceiptSettings? settings) {
  _cachedReceiptSettings = settings;
}

/// Web-based printer - uses PrintNode, backend service, or browser dialog
class InvoicePrinter implements InvoicePrinterBase {
  html.IFrameElement? _printFrame;
  
  /// Get backend URLs to try - includes auto-detected host-based URL
  List<String> get _backendUrls {
    final urls = <String>[];
    
    // First, try same host as current page (for network access)
    try {
      final uri = html.window.location;
      final host = uri.host; // Gets host without port
      final hostname = uri.hostname ?? host;
      
      // If we're not on localhost, add the current host with port 5005
      if (hostname.isNotEmpty && 
          hostname != 'localhost' && 
          hostname != '127.0.0.1') {
        urls.add('http://$hostname:5005');
      }
    } catch (_) {}
    
    // Then try standard localhost URLs
    urls.add('http://localhost:5005');
    urls.add('http://127.0.0.1:5005');
    
    return urls;
  }
  
  @override
  bool get isSupported => true;
  
  @override
  PrintMethod get defaultMethod => PrintMethod.backendService;
  
  @override
  Future<PrintResult> printInvoice(InvoiceData invoice, {String? printerName}) async {
    // Get selected printer from settings if not provided
    final selectedPrinter = printerName ?? _cachedReceiptSettings?.selectedPrinterName;
    
    // 1. Try PrintNode cloud printing first (if configured)
    if (_cachedSettings?.isConfigured == true) {
      final result = await _printNodePrint(invoice);
      if (result.success) return result;
      // If PrintNode fails, continue to fallbacks
    }
    
    // 2. Try local backend service for silent printing
    for (final baseUrl in _backendUrls) {
      try {
        // Quick health check
        final healthResp = await http.get(Uri.parse('$baseUrl/health'))
            .timeout(const Duration(seconds: 2));
        if (healthResp.statusCode != 200) continue;
        
        // Send print request to backend WITH selected printer
        final requestBody = <String, dynamic>{
          'invoice': invoice.toJson(),
        };
        if (selectedPrinter != null && selectedPrinter.isNotEmpty) {
          requestBody['printer'] = selectedPrinter;
        }
        
        final printResp = await http.post(
          Uri.parse('$baseUrl/print-invoice'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(requestBody),
        ).timeout(const Duration(seconds: 10));
        
        if (printResp.statusCode == 200) {
          return PrintResult.success(PrintMethod.backendService);
        }
      } catch (e) {
        // Backend not available, continue to next URL or fallback
      }
    }
    
    // 3. Fallback: Use browser print dialog
    return _browserPrint(invoice);
  }
  
  /// PrintNode cloud printing
  Future<PrintResult> _printNodePrint(InvoiceData invoice) async {
    try {
      final settings = _cachedSettings;
      if (settings == null || !settings.isConfigured) {
        return PrintResult.failure('PrintNode not configured');
      }
      
      final service = PrintNodeService(apiKey: settings.printNodeApiKey!);
      final width = getReceiptWidth();
      final receiptText = formatInvoiceReceipt(invoice, width: width);
      
      final result = await service.printReceipt(
        printerId: settings.printNodePrinterId!,
        content: receiptText,
        title: 'Invoice ${invoice.invoiceNumber}',
      );
      
      if (result.success) {
        return PrintResult.success(PrintMethod.backendService);
      } else {
        return PrintResult.failure(result.message ?? 'PrintNode print failed');
      }
    } catch (e) {
      return PrintResult.failure('PrintNode error: $e');
    }
  }
  
  /// Browser-based printing (shows print dialog)
  Future<PrintResult> _browserPrint(InvoiceData invoice) async {
    try {
      _cleanup();
      
      final width = getReceiptWidth();
      final htmlContent = buildPrintableHtml(invoice, width: width);
      
      // Create hidden iframe
      _printFrame = html.IFrameElement()
        ..style.position = 'fixed'
        ..style.right = '0'
        ..style.bottom = '0'
        ..style.width = '0'
        ..style.height = '0'
        ..style.border = 'none'
        ..srcdoc = htmlContent;
      
      html.document.body?.append(_printFrame!);
      
      // Wait for load
      await _printFrame!.onLoad.first.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('Print frame load timeout'),
      );
      
      await Future.delayed(const Duration(milliseconds: 100));
      
      // Trigger print via JS interop
      final contentWindow = _printFrame!.contentWindow;
      if (contentWindow != null) {
        final jsWindow = js.JsObject.fromBrowserObject(contentWindow);
        jsWindow.callMethod('print', []);
      }
      
      Future.delayed(const Duration(seconds: 30), _cleanup);
      
      return PrintResult.success(PrintMethod.webBrowserDialog);
    } catch (e) {
      _cleanup();
      return PrintResult.failure('Browser print error: $e');
    }
  }
  
  void _cleanup() {
    try {
      _printFrame?.remove();
    } catch (_) {}
    _printFrame = null;
  }
  
  void cleanup() => _cleanup();
}
