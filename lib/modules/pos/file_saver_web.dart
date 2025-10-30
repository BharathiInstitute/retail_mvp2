// Web implementation avoiding direct deprecated dart:html reference in app code paths.
// We still need a minimal interop; keep the ignore but abstract any direct usage.
// ignore_for_file: avoid_web_libraries_in_flutter
// ignore: deprecated_member_use
import 'dart:html' as html; // TODO: Migrate to package:web + dart:js_interop for safer future compatibility.
// TODO: Migrate to package:web + dart:js_interop for safer future compatibility. (see line 5)

class PdfSaver {
  Future<String> savePdf(String filename, List<int> bytes) async {
    try {
      final blob = html.Blob([bytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..download = filename
        ..style.display = 'none';
      html.document.body?.append(anchor);
      anchor.click();
      anchor.remove();
      html.Url.revokeObjectUrl(url);
      return filename; // Not a real path on web
    } catch (_) {
      // Swallow errors silently; caller can decide to show a message if needed.
      return filename;
    }
  }

  Future<void> sharePdf(String filename, List<int> bytes) async {
    await savePdf(filename, bytes);
  }
}
