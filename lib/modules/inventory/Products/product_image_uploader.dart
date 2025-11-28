import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

/// Simple MIME type guess from leading bytes. Defaults to image/jpeg.
String _guessMime(Uint8List bytes) {
  if (bytes.length >= 4) {
    // PNG
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      return 'image/png';
    }
    // JPEG (FF D8)
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return 'image/jpeg';
    }
    // GIF (GIF87a / GIF89a)
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
      return 'image/gif';
    }
    // WEBP (RIFF....WEBP)
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      return 'image/webp';
    }
  }
  return 'image/jpeg';
}

/// Upload product images to Firebase Storage.
/// Path pattern: stores/{storeId}/products/{sku}/image_{index}.jpg
/// Returns download URLs in same order as input list.
/// Optional [onProgress] callback emits cumulative task progress per index (0..1).
class ProductImageUploadException implements Exception {
  final List<String> errors; // one per failed image (index included in message)
  ProductImageUploadException(this.errors);
  @override
  String toString() => 'ProductImageUploadException(${errors.join('; ')})';
}

String _mimeExt(String mime) {
  switch (mime) {
    case 'image/png': return 'png';
    case 'image/gif': return 'gif';
    case 'image/webp': return 'webp';
    case 'image/jpeg':
    default: return 'jpg';
  }
}

/// Returns list of download URLs. In case of partial failures throws a
/// [ProductImageUploadException] containing per-image error messages.
Future<List<String>> uploadProductImages({
  required String storeId,
  required String sku,
  required List<Uint8List> images,
  void Function(int index, double progress)? onProgress,
}) async {
  if (images.isEmpty) return const <String>[];
  final storage = FirebaseStorage.instance;
  final baseRef = storage.ref().child('stores/$storeId/products/$sku');
  final urls = <String>[];
  final errors = <String>[];
  for (int i = 0; i < images.length; i++) {
    final data = images[i];
    final mime = _guessMime(data);
    final ext = _mimeExt(mime);
    final ref = baseRef.child('image_$i.$ext');
    final uploadTask = ref.putData(
      data,
      SettableMetadata(contentType: mime),
    );
    if (onProgress != null) {
      uploadTask.snapshotEvents.listen((snap) {
        final total = snap.totalBytes == 0 ? 1 : snap.totalBytes;
        final prog = snap.bytesTransferred / total;
        onProgress(i, prog.clamp(0, 1));
      });
    }
    try {
      final snap = await uploadTask;
      if (snap.state == TaskState.success) {
        final url = await ref.getDownloadURL();
        urls.add(url);
        if (onProgress != null) onProgress(i, 1.0);
      } else {
        errors.add('Image #${i + 1} upload did not succeed (state=${snap.state.name})');
      }
    } on FirebaseException catch (e) {
      errors.add('Image #${i + 1} FirebaseException code=${e.code} message=${e.message ?? ''}');
    } catch (e) {
      errors.add('Image #${i + 1} unexpected error: $e');
    }
  }
  if (errors.isNotEmpty) {
    throw ProductImageUploadException(errors);
  }
  return urls;
}
