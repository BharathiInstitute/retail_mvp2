// Windows-specific direct printing using a hidden PowerShell process launched via VBScript.
// This avoids popping a console window in front of the Flutter POS UI.
//
// Strategy:
// 1. Build a plain-text receipt from the InvoiceData (thermal-friendly, 42 cols target).
// 2. Base64 encode the receipt to simplify escaping & pass to a transient PowerShell script.
// 3. Create a temporary .ps1 and a .vbs launcher (wscript hidden, window style 0).
// 4. Launch via wscript.exe detached so it runs fully in background.
// 5. Return true if we managed to spawn the process (fire-and-forget), false on failure.
//
// NOTE: This is a best-effort local fallback when the Node backend is unavailable / undesired.
//       For richer formatting (logos, QR, ESC/POS commands) keep using the backend pipeline.

import 'dart:io';
import 'dart:convert';
import 'invoice_models.dart';
import 'print_settings.dart';

/// Public entry used by POS UI (conditionally imported).
Future<bool> directWindowsPrintInvoice(InvoiceData invoice, {String? printerName}) async {
  if (!Platform.isWindows) return false;
  try {
    final settings = globalPrintSettings;
    int width;
    if (settings.paperSize == PaperSize.receipt) {
      width = settings.scaleToFit ? settings.derivedCharWidth() : settings.receiptCharWidth;
    } else {
      width = 80; // A4 text fallback width
    }
  width = width.clamp(20, 120);
    final text = _formatInvoicePlain(invoice, width: width);
    final b64 = base64Encode(utf8.encode(text));

    final tmpDir = Directory.systemTemp;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ps1 = File('${tmpDir.path}\\print_invoice_$ts.ps1');
    final vbs = File('${tmpDir.path}\\launch_print_invoice_$ts.vbs');

    final sanitizedPrinter = (printerName ?? '').replaceAll('"', '');

  final script = _buildPowerShellScript(b64, sanitizedPrinter, settings.fontSizePt.clamp(6,24));
    await ps1.writeAsString(script, flush: true);

    final psPathEsc = ps1.path.replaceAll('"', '""');
    final vbsContent = '''
Set sh = CreateObject("WScript.Shell")
cmd = "powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$psPathEsc"""
sh.Run cmd, 0, False
''';
    await vbs.writeAsString(vbsContent, flush: true);

    await Process.start('wscript.exe', [vbs.path], mode: ProcessStartMode.detached);
    return true;
  } catch (_) {
    return false;
  }
}

String _buildPowerShellScript(String base64Body, String printerName, int fontSize) {
  // Minimalistic PS1 that prints a simple text block using .NET PrintDocument API.
  final printerAssign = printerName.isEmpty
    ? ''
    : 'try { ' r'$doc' '.PrinterSettings.PrinterName = "${_escapePs(printerName)}" } catch {}';
  return """
\$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Drawing
\$b64 = '${_escapePs(base64Body)}'
\$bytes = [Convert]::FromBase64String(\$b64)
\$text = [System.Text.Encoding]::UTF8.GetString(\$bytes)
if (-not \$text) { return }
\$doc = New-Object System.Drawing.Printing.PrintDocument
$printerAssign
\$docOrigin = New-Object System.Drawing.PointF 0,0
\$font = New-Object System.Drawing.Font 'Consolas',$fontSize
\$brush = [System.Drawing.Brushes]::Black
\$doc.add_PrintPage({ param(\$sender,\$e) \$e.Graphics.DrawString(\$text,\$font,\$brush,\$docOrigin); \$e.HasMorePages = \$false })
\$doc.Print()
""";
}

String _formatInvoicePlain(InvoiceData inv, {int width = 40}) {
  // Thermal printers often ~42 chars width default. Width is adjustable from settings.
  String line([String ch = '-']) => ''.padRight(width, ch);
  String money(num v) => v.toStringAsFixed(2);
  final b = StringBuffer();
  void writeWrapped(String text) {
    if (text.isEmpty) return;
    int i = 0;
    while (i < text.length) {
      final end = (i + width) > text.length ? text.length : i + width;
      b.writeln(text.substring(i, end));
      i = end;
    }
  }
  // Header & meta info with wrapping to prevent truncation on narrow receipts (e.g. 20 cols)
  writeWrapped('*** INVOICE ${inv.invoiceNumber} ***');
  final dt = inv.timestamp.toLocal();
  final dateStr = '${dt.year.toString().padLeft(4,'0')}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}';
  final timeStr = '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}:${dt.second.toString().padLeft(2,'0')}';
  writeWrapped('Date: $dateStr $timeStr');
  writeWrapped('Customer: ${inv.customerName}');
  if ((inv.customerPhone ?? '').isNotEmpty) writeWrapped('Phone: ${inv.customerPhone}');
  if ((inv.customerEmail ?? '').isNotEmpty) writeWrapped('Email: ${inv.customerEmail}');
  b.writeln(line());
  final itemHeader = width >= 34 ? '${'Item'.padRight(width - 13)}Qty   Total' : 'Item  Qty  Total';
  b.writeln(itemHeader);
  b.writeln(line());
  for (final ln in inv.lines) {
    final availNameWidth = width - 13; // leave space for qty + total columns
    final truncated = ln.name.length > availNameWidth ? ln.name.substring(0, availNameWidth) : ln.name;
    final name = truncated.padRight(availNameWidth);
    final qty = ln.qty.toString().padLeft(3);
    final total = money(ln.lineTotal).padLeft(8);
    if (width >= 28) {
      b.writeln('$name $qty $total');
    } else {
      b.writeln(truncated);
      b.writeln(' x${ln.qty}  ${money(ln.lineTotal)}');
    }
  }
  b.writeln(line());
  b.writeln(_kv('Subtotal', inv.subtotal, width: width));
  b.writeln(_kv('Discount', -inv.discountTotal, width: width));
  b.writeln(_kv('Tax', inv.taxTotal, width: width));
  if (inv.redeemedValue > 0) b.writeln(_kv('Redeemed', -inv.redeemedValue, width: width));
  b.writeln(line('='));
  b.writeln(_kv('TOTAL', inv.grandTotal - inv.redeemedValue, bold: true, width: width));
  b.writeln(line());
  b.writeln('Paid via: ${inv.paymentMode}');
  b.writeln('Thank you!');
  return b.toString();
}

String _kv(String k, num v, {bool bold = false, int width = 40}) {
  final label = bold ? k.toUpperCase() : k;
  final value = (v >= 0 ? ' ' : '') + v.toStringAsFixed(2);
  final space = width - label.length - value.length;
  final pad = space > 0 ? ''.padRight(space) : ' ';
  return '$label$pad$value';
}

String _escapePs(String input) => input.replaceAll("'", "''").replaceAll('`', '``');
