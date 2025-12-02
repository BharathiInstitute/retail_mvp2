import 'dart:ui' as ui;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

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

/// Create a thumbnail from image bytes
Future<Uint8List> _createThumbnail(Uint8List imageBytes, {int maxSize = 200}) async {
  try {
    final codec = await ui.instantiateImageCodec(
      imageBytes,
      targetWidth: maxSize,
      targetHeight: maxSize,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) {
      return byteData.buffer.asUint8List();
    }
  } catch (e) {
    debugPrint('Thumbnail creation failed: $e');
  }
  // Return original if thumbnail fails
  return imageBytes;
}

/// Upload product images to Firebase Storage.
/// Path pattern: stores/{storeId}/products/{sku}/image_{index}.jpg
///              stores/{storeId}/products/{sku}/thumb_{index}.jpg (thumbnail)
/// Returns download URLs in same order as input list.
/// Optional [onProgress] callback emits cumulative task progress per index (0..1).
class ProductImageUploadException implements Exception {
  final List<String> errors; // one per failed image (index included in message)
  ProductImageUploadException(this.errors);
  @override
  String toString() => 'ProductImageUploadException(${errors.join('; ')})';
}

/// Result of image upload containing both main and thumbnail URLs
class ProductImageUrls {
  final String mainUrl;
  final String thumbUrl;
  ProductImageUrls({required this.mainUrl, required this.thumbUrl});
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

/// Upload a single file to Firebase Storage
Future<String> _uploadFile({
  required Reference ref,
  required Uint8List data,
  required String mime,
  void Function(double)? onProgress,
}) async {
  final uploadTask = ref.putData(
    data,
    SettableMetadata(contentType: mime),
  );
  
  if (onProgress != null) {
    uploadTask.snapshotEvents.listen((snap) {
      final total = snap.totalBytes == 0 ? 1 : snap.totalBytes;
      final prog = snap.bytesTransferred / total;
      onProgress(prog.clamp(0, 1));
    });
  }
  
  final snap = await uploadTask;
  if (snap.state == TaskState.success) {
    return await ref.getDownloadURL();
  }
  throw Exception('Upload failed with state: ${snap.state.name}');
}

/// Returns list of download URLs (main images only for backward compatibility).
/// Also uploads thumbnails as thumb_{index}.png
/// In case of partial failures throws a [ProductImageUploadException].
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
    
    try {
      // Upload main image
      final mainRef = baseRef.child('image_$i.$ext');
      final mainUrl = await _uploadFile(
        ref: mainRef,
        data: data,
        mime: mime,
        onProgress: (p) => onProgress?.call(i, p * 0.7), // 70% for main
      );
      urls.add(mainUrl);
      
      // Create and upload thumbnail (200px)
      try {
        final thumbData = await _createThumbnail(data, maxSize: 200);
        final thumbRef = baseRef.child('thumb_$i.png');
        await _uploadFile(
          ref: thumbRef,
          data: thumbData,
          mime: 'image/png',
          onProgress: (p) => onProgress?.call(i, 0.7 + p * 0.3), // 30% for thumb
        );
      } catch (e) {
        debugPrint('Thumbnail upload failed for image $i: $e');
        // Continue even if thumbnail fails
      }
      
      onProgress?.call(i, 1.0);
    } on FirebaseException catch (e) {
      errors.add('Image #${i + 1} FirebaseException code=${e.code} message=${e.message ?? ''}');
    } catch (e) {
      errors.add('Image #${i + 1} error: $e');
    }
  }
  
  if (errors.isNotEmpty) {
    throw ProductImageUploadException(errors);
  }
  return urls;
}
