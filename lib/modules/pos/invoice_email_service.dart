import 'package:cloud_functions/cloud_functions.dart';
import 'dart:convert';

class InvoiceEmailService {
  final FirebaseFunctions _functions;
  InvoiceEmailService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  /// Sends structured invoice JSON (server builds HTML)
  Future<void> sendInvoiceJson({
    required Map<String, dynamic> invoiceJson,
    required String customerEmail,
    required String subject,
    required String body,
  }) async {
    final callable = _functions.httpsCallable('sendInvoiceEmail');
    await callable.call({
      'invoiceNumber': invoiceJson['invoiceNumber'],
      'invoiceData': invoiceJson,
      'to': customerEmail,
      'subject': subject,
      'body': body,
    });
  }

  /// Sends pre-built HTML only (no JSON required).
  Future<void> sendInvoiceHtml({
    required String customerEmail,
    required String invoiceHtml,
    String? invoiceNumber,
    String? subject,
  }) async {
    final callable = _functions.httpsCallable('sendInvoiceEmail');
    await callable.call({
      if (invoiceNumber != null) 'invoiceNumber': invoiceNumber,
      'customerEmail': customerEmail,
      'invoiceHtml': invoiceHtml,
      if (subject != null) 'subject': subject,
    });
  }

  /// Sends a PDF (base64) plus optional HTML or JSON for fallback.
  Future<void> sendInvoicePdf({
    required String customerEmail,
    required String invoiceNumber,
    required List<int> pdfBytes,
    Map<String, dynamic>? invoiceJson,
    String? subject,
    String? body,
    String? filename,
    String? invoiceHtml,
  }) async {
    final callable = _functions.httpsCallable('sendInvoiceEmail');
    await callable.call({
      'customerEmail': customerEmail,
      'invoiceNumber': invoiceNumber,
      if (invoiceJson != null) 'invoiceData': invoiceJson,
      if (subject != null) 'subject': subject,
      if (body != null) 'body': body,
      'pdfBase64': base64Encode(pdfBytes),
      if (filename != null) 'pdfFilename': filename,
      if (invoiceHtml != null) 'invoiceHtml': invoiceHtml,
    });
  }
}
