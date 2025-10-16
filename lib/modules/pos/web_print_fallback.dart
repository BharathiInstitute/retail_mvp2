// Web-specific fallback printing (Flutter Web only).
// Opens a new window/tab with simple HTML and triggers the browser print dialog.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'invoice_models.dart';
import 'package:flutter/foundation.dart';

/// Opens a new tab/window and injects printable HTML, then triggers browser print.
/// Returns false if popup blocked or any exception occurs.
Future<bool> webFallbackPrintInvoice(InvoiceData invoice) async {
  try {
    final htmlContent = _buildHtml(invoice);
    // Open immediately (synchronous with user gesture) to avoid popup blocker.
    final opened = html.window.open('', '_blank');
    final win = opened is html.Window ? opened : html.window; // ensure correct type
    try {
      final doc = (opened is html.Window) ? opened.document : html.document;
      doc.documentElement?.innerHtml = htmlContent;
    } catch (e) {
      if (kDebugMode) debugPrint('[WEB PRINT] Failed injecting HTML: $e');
      return false;
    }
    Future.delayed(const Duration(milliseconds: 60), () {
      try { win.print(); } catch (e) { if (kDebugMode) debugPrint('[WEB PRINT] print() failed: $e'); }
    });
    return true;
  } catch (e) {
    if (kDebugMode) debugPrint('[WEB PRINT] Unexpected error: $e');
    return false;
  }
}

// Pre-open a print window synchronously (to avoid popup blockers) and return a handle.
class PrintWindowHandle {
  final html.Window win;
  final html.Document doc;
  PrintWindowHandle(this.win, this.doc);
}

PrintWindowHandle? webPrintPreopen() {
  try {
    final opened = html.window.open('', '_blank');
    if (opened is html.Window) {
      return PrintWindowHandle(opened, opened.document);
    }
  } catch (e) {
    if (kDebugMode) debugPrint('[WEB PRINT] preopen failed: $e');
  }
  return null;
}

Future<bool> webPrintPopulateAndPrint(PrintWindowHandle? handle, InvoiceData invoice) async {
  if (handle == null) return webFallbackPrintInvoice(invoice);
  try {
    final htmlContent = _buildHtml(invoice);
    handle.doc.documentElement?.innerHtml = htmlContent;
    Future.delayed(const Duration(milliseconds: 30), () {
      try { handle.win.print(); } catch (e) { if (kDebugMode) debugPrint('[WEB PRINT] print() failed: $e'); }
    });
    return true;
  } catch (e) {
    if (kDebugMode) debugPrint('[WEB PRINT] populate/print failed: $e');
    return false;
  }
}

void webPrintClose(PrintWindowHandle? handle) {
  try { handle?.win.close(); } catch (_) {}
}

String _buildHtml(InvoiceData inv) {
  // We will produce a narrow receipt layout suitable for 58mm / 80mm thermal printers.
  // Approach: generate a pre-formatted block with fixed character widths to avoid table overflow clipping.
  // Fallback to basic ASCII alignment so no font-size scaling truncates columns.
  const maxChars = 32; // typical 58mm @ 12cpi ~ 32 chars; adjust if using 80mm (48 chars) later.
  String money(num v) => v.toStringAsFixed(2);
  final lines = <String>[];

  String center(String text) {
    if (text.length >= maxChars) return text; // no pad if longer (will wrap later)
    final pad = (maxChars - text.length) ~/ 2;
    return ' ' * pad + text;
  }

  String padRight(String text, int width) {
    if (text.length > width) return text.substring(0, width);
    return text + ' ' * (width - text.length);
  }
  String wrapItemName(String name) {
    final chunks = <String>[];
    var remaining = name.trim();
    while (remaining.isNotEmpty) {
      if (remaining.length <= 16) { // 16 char for item column baseline
        chunks.add(remaining);
        break;
      }
      chunks.add(remaining.substring(0, 16));
      remaining = remaining.substring(16);
    }
    return chunks.join('\n');
  }

  lines.add(center('Invoice')); // Title line
  lines.add(center(inv.invoiceNumber));
  lines.add('');
  lines.add('Date: ${inv.timestamp.toLocal().toString().split('.').first}');
  lines.add('Customer: ${inv.customerName}');
  if (inv.customerPhone != null && inv.customerPhone!.isNotEmpty) {
    lines.add('Phone: ${inv.customerPhone}');
  }
  if (inv.customerEmail != null && inv.customerEmail!.isNotEmpty) {
    lines.add('Email: ${inv.customerEmail}');
  }
  lines.add('');

  // Column headers (Item takes up to 16, Qty 3, Price 6, Total 7 = 32)
  lines.add('Item             Qty Price  Total');
  lines.add('-' * maxChars);

  for (final l in inv.lines) {
    final nameWrapped = wrapItemName(l.name);
    final nameLines = nameWrapped.split('\n');
    for (var i = 0; i < nameLines.length; i++) {
      final segment = nameLines[i];
      if (i == 0) {
        final itemCol = padRight(segment, 16);
        final qtyCol = padRight(l.qty.toString(), 3);
        final priceCol = padRight(money(l.unitPrice), 6);
        final totalCol = padRight(money(l.lineTotal), 7);
        lines.add('$itemCol$qtyCol$priceCol$totalCol');
      } else {
        // continuation line for long name
        lines.add(segment);
      }
    }
  }
  lines.add('-' * maxChars);
  lines.add(padRight('Subtotal', 23) + padRight(money(inv.subtotal), 9));
  lines.add(padRight('Discount', 23) + padRight('-${money(inv.discountTotal)}', 9));
  lines.add(padRight('Tax', 23) + padRight(money(inv.taxTotal), 9));
  if (inv.redeemedValue > 0) {
    lines.add(padRight('Redeemed', 23) + padRight('-${money(inv.redeemedValue)}', 9));
  }
  lines.add(padRight('Grand Total', 23) + padRight(money(inv.grandTotal), 9));
  lines.add(padRight('Payment Mode', 23) + padRight(inv.paymentMode, 9));
  lines.add('');
  lines.add('Thank you for your purchase.');

  final plain = lines.map(_esc).join('\n');

  final htmlBuf = StringBuffer();
  htmlBuf.writeln('<!DOCTYPE html><html><head><meta charset="utf-8">');
  htmlBuf.writeln('<meta name="viewport" content="width=device-width,initial-scale=1">');
  htmlBuf.writeln('<title>Invoice ${_esc(inv.invoiceNumber)}</title>');
  htmlBuf.writeln('<style>'
      '@page{margin:2mm 2mm 4mm 2mm;}'
      'body{margin:0;font-family:monospace;font-size:11px;line-height:1.25;}'
      'pre{margin:0;white-space:pre-wrap;word-wrap:break-word;}'
      '@media print { body{width:100%;} }'
      '</style></head><body>');
  htmlBuf.writeln('<pre>$plain</pre>');
  htmlBuf.writeln('<script>window.addEventListener("load",()=>{setTimeout(()=>{try{window.print();}catch(e){}},30);});</script>');
  htmlBuf.writeln('</body></html>');
  return htmlBuf.toString();
}

String _esc(String v) => v.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
