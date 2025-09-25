import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class PdfSaver {
  Future<String> savePdf(String filename, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$filename';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return path;
  }

  Future<void> sharePdf(String filename, List<int> bytes) async {
    final path = await savePdf(filename, bytes);
    await Share.shareXFiles([
      XFile(path, mimeType: 'application/pdf', name: filename),
    ], subject: 'Invoice $filename', text: 'Please find attached invoice $filename');
  }
}
