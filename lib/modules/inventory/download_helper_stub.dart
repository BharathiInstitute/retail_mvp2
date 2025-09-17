import 'dart:typed_data';

/// Platform-agnostic download helper.
/// This stub is used on non-web platforms and simply returns false so callers can fallback.
Future<bool> downloadBytes(Uint8List bytes, String fileName, String mimeType) async {
  return false;
}
