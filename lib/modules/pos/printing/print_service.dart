// Print Service - Uses local printer backend for one-click printing
// Works on ALL platforms: Web, Windows, Android, iOS
// Requires printer_backend to be running on localhost:5005

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Printer info from the backend
class PrinterInfo {
  final String name;
  final bool isDefault;
  final String? connectionType;
  final String? printerType;
  final String? status;
  
  PrinterInfo({
    required this.name, 
    this.isDefault = false,
    this.connectionType,
    this.printerType,
    this.status,
  });
  
  factory PrinterInfo.fromJson(Map<String, dynamic> json) {
    return PrinterInfo(
      name: json['name'] as String? ?? json.toString(),
      isDefault: json['isDefault'] as bool? ?? false,
      connectionType: json['connectionType'] as String?,
      printerType: json['printerType'] as String?,
      status: json['status'] as String?,
    );
  }
  
  @override
  String toString() => name;
}

/// Print Service that connects to local printer backend
class PrintService {
  // Try multiple URLs - localhost and 127.0.0.1
  // Some browsers/platforms handle them differently
  static const List<String> _possibleUrls = [
    'http://127.0.0.1:5005',
    'http://localhost:5005',
  ];
  
  static String _baseUrl = 'http://127.0.0.1:5005';
  static String? _workingUrl;
  
  /// Set custom backend URL (for mobile devices)
  static void setBackendUrl(String url) {
    _baseUrl = url;
    _workingUrl = url;
  }
  
  /// Get the current backend URL
  static String get backendUrl => _workingUrl ?? _baseUrl;
  
  /// Find a working backend URL
  static Future<String?> _findWorkingUrl() async {
    if (_workingUrl != null) {
      // Verify it still works
      try {
        final response = await http.get(
          Uri.parse('$_workingUrl/health'),
        ).timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) {
          return _workingUrl;
        }
      } catch (_) {}
      _workingUrl = null;
    }
    
    // Try each possible URL
    for (final url in _possibleUrls) {
      try {
        debugPrint('🔍 Trying backend URL: $url');
        final response = await http.get(
          Uri.parse('$url/health'),
        ).timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) {
          debugPrint('✅ Found working backend URL: $url');
          _workingUrl = url;
          return url;
        }
      } catch (e) {
        debugPrint('❌ URL $url failed: $e');
      }
    }
    
    debugPrint('🔴 No working backend URL found');
    return null;
  }
  
  /// Check if printer backend is running
  static Future<bool> isBackendAvailable() async {
    try {
      final url = await _findWorkingUrl();
      return url != null;
    } catch (e) {
      debugPrint('🔴 Printer backend not available: $e');
      return false;
    }
  }
  
  /// Get list of available printers from backend
  static Future<List<PrinterInfo>> getPrinters() async {
    final url = await _findWorkingUrl();
    if (url == null) {
      debugPrint('❌ [getPrinters] No backend available');
      return [];
    }
    
    // Try the fast debug-printers endpoint first, then fall back to /printers
    debugPrint('🖨️ [getPrinters] Starting request to $url/debug-printers');
    try {
      // Try fast endpoint first (no status checks)
      var response = await http.get(
        Uri.parse('$url/debug-printers'),
      ).timeout(const Duration(seconds: 10));
      
      debugPrint('🖨️ [getPrinters] Response status: ${response.statusCode}');
      debugPrint('🖨️ [getPrinters] Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('🖨️ [getPrinters] Decoded data type: ${data.runtimeType}');
        
        final List printers = data['printers'] ?? [];
        debugPrint('✅ [getPrinters] Got ${printers.length} printers from backend');
        
        final result = printers.map((p) {
          debugPrint('🖨️ [getPrinters] Processing printer: $p (${p.runtimeType})');
          if (p is String) {
            return PrinterInfo(name: p);
          } else if (p is Map<String, dynamic>) {
            return PrinterInfo.fromJson(p);
          }
          return PrinterInfo(name: p.toString());
        }).toList();
        
        debugPrint('✅ [getPrinters] Returning ${result.length} PrinterInfo objects');
        return result;
      }
      debugPrint('❌ [getPrinters] Non-200 status: ${response.statusCode}');
      return [];
    } catch (e, stackTrace) {
      debugPrint('❌ [getPrinters] Error: $e');
      debugPrint('❌ [getPrinters] Stack trace: $stackTrace');
      return [];
    }
  }
  
  /// Get the current default printer
  static Future<String?> getDefaultPrinter() async {
    final url = _workingUrl ?? _baseUrl;
    try {
      final response = await http.get(
        Uri.parse('$url/config'),
      ).timeout(const Duration(seconds: 3));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['defaultPrinter'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('Error getting default printer: $e');
      return null;
    }
  }
  
  /// Set the default printer
  static Future<bool> setDefaultPrinter(String printerName) async {
    final url = _workingUrl ?? _baseUrl;
    try {
      final response = await http.post(
        Uri.parse('$url/set-default'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'printer': printerName}),
      ).timeout(const Duration(seconds: 5));
      
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error setting default printer: $e');
      return false;
    }
  }
  
  /// Print PDF bytes to the default printer (one-click!)
  static Future<PrintResult> printPdf(Uint8List pdfBytes, {String? printerName}) async {
    final url = _workingUrl ?? _baseUrl;
    try {
      final uri = Uri.parse('$url/print-pdf');
      final request = http.MultipartRequest('POST', uri);
      
      // Add the PDF file
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        pdfBytes,
        filename: 'receipt.pdf',
      ));
      
      // Add printer name if specified
      if (printerName != null) {
        request.fields['printer'] = printerName;
      }
      
      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return PrintResult(
          success: data['status'] == 'ok',
          message: data['message'] ?? 'Print job sent',
          printer: data['usedPrinter'] as String?,
        );
      } else {
        final data = json.decode(response.body);
        return PrintResult(
          success: false,
          message: data['error'] ?? 'Print failed: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('❌ Print error: $e');
      return PrintResult(
        success: false,
        message: 'Print failed: $e',
      );
    }
  }
  
  /// Print raw ESC/POS commands (for thermal printers)
  static Future<PrintResult> printRaw(List<int> rawBytes, {String? printerName}) async {
    final url = _workingUrl ?? _baseUrl;
    try {
      final response = await http.post(
        Uri.parse('$url/print-raw'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'data': base64Encode(rawBytes),
          if (printerName != null) 'printer': printerName,
        }),
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return PrintResult(
          success: data['status'] == 'ok',
          message: data['message'] ?? 'Print job sent',
          printer: data['usedPrinter'] as String?,
        );
      } else {
        return PrintResult(
          success: false,
          message: 'Print failed: ${response.statusCode}',
        );
      }
    } catch (e) {
      return PrintResult(
        success: false,
        message: 'Print failed: $e',
      );
    }
  }
  
  /// Print invoice directly from JSON data (server builds thermal PDF)
  static Future<PrintResult> printInvoice({
    required String invoiceNumber,
    required String timestamp,
    String? customerName,
    required List<Map<String, dynamic>> lines,
    required double subtotal,
    double? discountTotal,
    required double taxTotal,
    required double grandTotal,
    String? printerName,
  }) async {
    final url = _workingUrl ?? _baseUrl;
    try {
      final response = await http.post(
        Uri.parse('$url/print-invoice'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'invoice': {
            'invoiceNumber': invoiceNumber,
            'timestamp': timestamp,
            'customerName': customerName,
            'lines': lines,
            'subtotal': subtotal,
            'discountTotal': discountTotal,
            'taxTotal': taxTotal,
            'grandTotal': grandTotal,
          },
          if (printerName != null) 'printer': printerName,
        }),
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return PrintResult(
          success: data['status'] == 'ok',
          message: data['message'] ?? 'Invoice printed',
          printer: data['usedPrinter'] as String?,
        );
      } else {
        final data = json.decode(response.body);
        return PrintResult(
          success: false,
          message: data['error'] ?? 'Print failed: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('❌ Invoice print error: $e');
      return PrintResult(
        success: false,
        message: 'Print failed: $e',
      );
    }
  }
}

/// Result of a print operation
class PrintResult {
  final bool success;
  final String message;
  final String? printer;
  
  PrintResult({
    required this.success,
    required this.message,
    this.printer,
  });
}
