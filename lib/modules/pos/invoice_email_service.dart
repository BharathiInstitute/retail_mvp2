import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';

class InvoiceEmailService {
  final FirebaseStorage _storage;
  final FirebaseFunctions _functions;
  InvoiceEmailService({FirebaseStorage? storage, FirebaseFunctions? functions})
      : _storage = storage ?? FirebaseStorage.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  /// Uploads PDF bytes to a temporary Storage path and calls a Cloud Function
  /// named `sendInvoiceEmail` with metadata.
  Future<void> sendInvoiceEmail({
    required String invoiceNumber,
    required Uint8List pdfBytes,
    required String customerEmail,
    required String subject,
    required String body,
  }) async {
    final path = 'invoices/$invoiceNumber.pdf';
    final ref = _storage.ref(path);
    await ref.putData(pdfBytes, SettableMetadata(contentType: 'application/pdf'));
    final url = await ref.getDownloadURL();
    final callable = _functions.httpsCallable('sendInvoiceEmail');
    await callable.call({
      'invoiceNumber': invoiceNumber,
      'downloadUrl': url,
      'to': customerEmail,
      'subject': subject,
      'body': body,
    });
  }
}
