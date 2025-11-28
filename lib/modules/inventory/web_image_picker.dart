// Web-only camera/file picker using HTML input with capture attribute.
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

class WebPickedImage {
  final Uint8List bytes;
  final String name;
  final String mimeType;
  WebPickedImage({required this.bytes, required this.name, required this.mimeType});
}

Future<WebPickedImage?> pickImageFromCameraWeb() async {
  final input = html.FileUploadInputElement();
  input.accept = 'image/*';
  // Hint to use rear camera on mobile browsers supporting it.
  // Not all browsers honor this attribute.
  (input as dynamic).capture = 'environment';
  input.multiple = false;
  final completer = Completer<WebPickedImage?>();
  input.onChange.first.then((_) async {
    final files = input.files;
    if (files == null || files.isEmpty) {
      completer.complete(null);
      return;
    }
    final file = files.first;
    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    await reader.onLoad.first;
    final data = reader.result as ByteBuffer;
    completer.complete(WebPickedImage(
      bytes: Uint8List.view(data),
      name: file.name,
      mimeType: file.type,
    ));
  });
  input.click();
  return completer.future;
}

Future<WebPickedImage?> pickImageFromFilesWeb() async {
  final input = html.FileUploadInputElement();
  input.accept = 'image/*';
  input.multiple = false;
  final completer = Completer<WebPickedImage?>();
  input.onChange.first.then((_) async {
    final files = input.files;
    if (files == null || files.isEmpty) {
      completer.complete(null);
      return;
    }
    final file = files.first;
    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    await reader.onLoad.first;
    final data = reader.result as ByteBuffer;
    completer.complete(WebPickedImage(
      bytes: Uint8List.view(data),
      name: file.name,
      mimeType: file.type,
    ));
  });
  input.click();
  return completer.future;
}
