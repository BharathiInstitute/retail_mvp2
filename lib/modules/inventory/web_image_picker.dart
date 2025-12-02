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
  final completer = Completer<WebPickedImage?>();
  final input = html.FileUploadInputElement()
    ..accept = 'image/*'
    ..multiple = false;
  
  // Set capture attribute for camera
  input.setAttribute('capture', 'environment');
  
  input.onChange.listen((event) async {
    final files = input.files;
    if (files != null && files.isNotEmpty) {
      final file = files.first;
      final reader = html.FileReader();
      reader.onLoadEnd.listen((e) {
        if (reader.readyState == html.FileReader.DONE) {
          final result = reader.result;
          if (result is ByteBuffer) {
            completer.complete(WebPickedImage(
              bytes: Uint8List.view(result),
              name: file.name,
              mimeType: file.type,
            ));
          } else {
            completer.complete(null);
          }
        }
      });
      reader.readAsArrayBuffer(file);
    } else {
      completer.complete(null);
    }
  });
  
  input.click();
  return completer.future;
}

Future<WebPickedImage?> pickImageFromFilesWeb() async {
  final completer = Completer<WebPickedImage?>();
  final input = html.FileUploadInputElement()
    ..accept = 'image/*'
    ..multiple = false;
  
  input.onChange.listen((event) async {
    final files = input.files;
    if (files != null && files.isNotEmpty) {
      final file = files.first;
      final reader = html.FileReader();
      reader.onLoadEnd.listen((e) {
        if (reader.readyState == html.FileReader.DONE) {
          final result = reader.result;
          if (result is ByteBuffer) {
            completer.complete(WebPickedImage(
              bytes: Uint8List.view(result),
              name: file.name,
              mimeType: file.type,
            ));
          } else {
            completer.complete(null);
          }
        }
      });
      reader.readAsArrayBuffer(file);
    } else {
      completer.complete(null);
    }
  });
  
  input.click();
  return completer.future;
}
