// IO-based implementation for Windows, macOS, Linux
// This file is imported when dart:io is available (desktop and mobile platforms)

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import '../pos_invoices/invoice_models.dart';
import 'invoice_printer.dart';
import 'cloud_printer_settings.dart';
import 'receipt_settings.dart';
import 'print_service.dart' hide PrintResult;

/// Cached receipt settings
ReceiptSettings? _cachedReceiptSettings;

/// Stub for setCloudPrinterSettings (web-only feature)
void setCloudPrinterSettings(CloudPrinterSettings? settings) {
  // No-op on desktop - PrintNode is handled via web or direct USB
}

/// Set receipt settings including selected printer
void setReceiptSettings(ReceiptSettings? settings) {
  _cachedReceiptSettings = settings;
  // Also update PrintService URL
  if (settings != null) {
    PrintService.setBackendUrl(settings.printServerUrl);
  }
}

/// Desktop/Mobile printer implementation
class InvoicePrinter implements InvoicePrinterBase {
  @override
  bool get isSupported => Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  
  @override
  PrintMethod get defaultMethod {
    if (Platform.isWindows) return PrintMethod.windowsPowerShell;
    // For macOS and Linux, we could add lpr support in the future
    return PrintMethod.notSupported;
  }
  
  @override
  Future<PrintResult> printInvoice(InvoiceData invoice, {String? printerName}) async {
    // Use cached printer name if not explicitly provided
    final selectedPrinter = printerName ?? _cachedReceiptSettings?.selectedPrinterName;
    
    if (Platform.isWindows) {
      return _printWindows(invoice, printerName: selectedPrinter);
    } else if (Platform.isMacOS) {
      return _printMacOS(invoice, printerName: selectedPrinter);
    } else if (Platform.isLinux) {
      return _printLinux(invoice, printerName: selectedPrinter);
    }
    
    return PrintResult.failure('Printing not supported on ${Platform.operatingSystem}');
  }
  
  // =========================================================================
  // Windows Printing via PowerShell (hidden window)
  // =========================================================================
  
  Future<PrintResult> _printWindows(InvoiceData invoice, {String? printerName}) async {
    try {
      // Format the receipt text
      final width = getReceiptWidth();
      final text = formatInvoiceReceipt(invoice, width: width);
      
      // Create temp file
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}\\invoice_${invoice.invoiceNumber}_${DateTime.now().millisecondsSinceEpoch}.txt');
      await tempFile.writeAsString(text, encoding: utf8);
      
      final filePath = tempFile.path.replaceAll('/', '\\');
      
      // Build PowerShell command
      final psCommand = _buildWindowsPrintCommand(filePath, printerName);
      
      // Create VBScript to run PowerShell hidden (no console window)
      final vbsLauncher = '''
Set objShell = CreateObject("WScript.Shell")
objShell.Run "$psCommand", 0, True
''';
      
      final vbsFile = File('${tempDir.path}\\print_launcher_${DateTime.now().millisecondsSinceEpoch}.vbs');
      await vbsFile.writeAsString(vbsLauncher);
      
      // Execute VBScript silently
      final result = await Process.run('wscript.exe', ['/nologo', vbsFile.path]);
      
      // Cleanup temp files after a delay
      _scheduleCleanup([tempFile, vbsFile]);
      
      if (result.exitCode != 0) {
        return PrintResult.failure('Windows print failed: ${result.stderr}');
      }
      
      return PrintResult.success(PrintMethod.windowsPowerShell);
    } catch (e) {
      return PrintResult.failure('Windows print error: $e');
    }
  }
  
  String _buildWindowsPrintCommand(String filePath, String? printerName) {
    final escapedPath = filePath.replaceAll("'", "''");
    
    if (printerName != null && printerName.isNotEmpty) {
      final escapedPrinter = printerName.replaceAll("'", "''");
      return 'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -Raw -Path \'$escapedPath\' | Out-Printer -Name \'$escapedPrinter\'"';
    }
    
    return 'powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -Raw -Path \'$escapedPath\' | Out-Printer"';
  }
  
  // =========================================================================
  // macOS Printing via lpr
  // =========================================================================
  
  Future<PrintResult> _printMacOS(InvoiceData invoice, {String? printerName}) async {
    try {
      final width = getReceiptWidth();
      final text = formatInvoiceReceipt(invoice, width: width);
      
      // Create temp file
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/invoice_${invoice.invoiceNumber}_${DateTime.now().millisecondsSinceEpoch}.txt');
      await tempFile.writeAsString(text, encoding: utf8);
      
      // Build lpr command arguments
      final args = <String>[];
      if (printerName != null && printerName.isNotEmpty) {
        args.addAll(['-P', printerName]);
      }
      args.add(tempFile.path);
      
      // Execute lpr
      final result = await Process.run('lpr', args);
      
      _scheduleCleanup([tempFile]);
      
      if (result.exitCode != 0) {
        return PrintResult.failure('macOS print failed: ${result.stderr}');
      }
      
      return PrintResult.success(PrintMethod.backendService); // Using system lpr
    } catch (e) {
      return PrintResult.failure('macOS print error: $e');
    }
  }
  
  // =========================================================================
  // Linux Printing via lpr
  // =========================================================================
  
  Future<PrintResult> _printLinux(InvoiceData invoice, {String? printerName}) async {
    try {
      final width = getReceiptWidth();
      final text = formatInvoiceReceipt(invoice, width: width);
      
      // Create temp file
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/invoice_${invoice.invoiceNumber}_${DateTime.now().millisecondsSinceEpoch}.txt');
      await tempFile.writeAsString(text, encoding: utf8);
      
      // Build lpr command arguments
      final args = <String>[];
      if (printerName != null && printerName.isNotEmpty) {
        args.addAll(['-P', printerName]);
      }
      args.add(tempFile.path);
      
      // Execute lpr
      final result = await Process.run('lpr', args);
      
      _scheduleCleanup([tempFile]);
      
      if (result.exitCode != 0) {
        return PrintResult.failure('Linux print failed: ${result.stderr}');
      }
      
      return PrintResult.success(PrintMethod.backendService); // Using system lpr
    } catch (e) {
      return PrintResult.failure('Linux print error: $e');
    }
  }
  
  // =========================================================================
  // Utilities
  // =========================================================================
  
  void _scheduleCleanup(List<File> files) {
    // Clean up temp files after 30 seconds
    Future.delayed(const Duration(seconds: 30), () async {
      for (final file in files) {
        try {
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
    });
  }
}
