// Stub for non-web builds
import 'dart:typed_data';

class WebPickedImage {
  final Uint8List bytes;
  final String name;
  final String mimeType;
  WebPickedImage({required this.bytes, required this.name, required this.mimeType});
}

Future<WebPickedImage?> pickImageFromCameraWeb() async => null;
Future<WebPickedImage?> pickImageFromFilesWeb() async => null;
