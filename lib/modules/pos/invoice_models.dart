import 'dart:convert';

/// Represents a finalized invoice snapshot (immutable) used for PDF/email.
class InvoiceData {
  final String invoiceNumber;
  final DateTime timestamp;
  final String customerName;
  final String? customerEmail;
  final String? customerPhone;
  final String? customerId;
  final List<InvoiceLine> lines;
  final double subtotal;
  final double discountTotal;
  final double taxTotal;
  final double grandTotal;
  final Map<int, double> taxesByRate; // GST% -> amount
  final double customerDiscountPercent; // for reference (applied percent)
  final String paymentMode; // simple label

  const InvoiceData({
    required this.invoiceNumber,
    required this.timestamp,
    required this.customerName,
    required this.customerEmail,
    required this.customerPhone,
    required this.customerId,
    required this.lines,
    required this.subtotal,
    required this.discountTotal,
    required this.taxTotal,
    required this.grandTotal,
    required this.taxesByRate,
    required this.customerDiscountPercent,
    required this.paymentMode,
  });

  Map<String, dynamic> toJson() => {
        'invoiceNumber': invoiceNumber,
        'timestamp': timestamp.toIso8601String(),
        'customerName': customerName,
        'customerEmail': customerEmail,
  'customerPhone': customerPhone,
        'customerId': customerId,
        'lines': lines.map((e) => e.toJson()).toList(),
        'subtotal': subtotal,
        'discountTotal': discountTotal,
        'taxTotal': taxTotal,
        'grandTotal': grandTotal,
        'taxesByRate': taxesByRate.map((k, v) => MapEntry(k.toString(), v)),
        'customerDiscountPercent': customerDiscountPercent,
        'paymentMode': paymentMode,
      };

  String toBase64Json() => base64Encode(utf8.encode(jsonEncode(toJson())));
}

class InvoiceLine {
  final String sku;
  final String name;
  final int qty;
  final double unitPrice;
  final int taxPercent;
  final double lineSubtotal; // unitPrice * qty (pre discount & tax)
  final double discount; // discount allocated to this line
  final double tax; // tax amount on net (after discount)
  final double lineTotal; // (lineSubtotal - discount + tax)

  const InvoiceLine({
    required this.sku,
    required this.name,
    required this.qty,
    required this.unitPrice,
    required this.taxPercent,
    required this.lineSubtotal,
    required this.discount,
    required this.tax,
    required this.lineTotal,
  });

  Map<String, dynamic> toJson() => {
        'sku': sku,
        'name': name,
        'qty': qty,
        'unitPrice': unitPrice,
        'taxPercent': taxPercent,
        'lineSubtotal': lineSubtotal,
        'discount': discount,
        'tax': tax,
        'lineTotal': lineTotal,
      };
}
