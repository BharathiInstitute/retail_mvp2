// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class PdfSaver {
  Future<String> savePdf(String filename, List<int> bytes) async {
    final blob = html.Blob([bytes], 'application/pdf');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..download = filename
      ..style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    html.Url.revokeObjectUrl(url);
    return filename; // Not a filesystem path on web
  }

  Future<void> sharePdf(String filename, List<int> bytes) async {
    // On web, just trigger download (same as save) for now.
    await savePdf(filename, bytes);
  }
}
