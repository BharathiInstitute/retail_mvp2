import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PdfTheme {
  // Colors
  static const PdfColor border = PdfColors.grey300;
  static const PdfColor headerBg = PdfColor.fromInt(0xFFE0E0E0);
  static const PdfColor textMuted = PdfColors.grey600;
  static const PdfColor accent = PdfColors.blueGrey;

  // Text sizes
  static const double h1 = 18;
  static const double h2 = 12;
  static const double body = 10;
  static const double small = 9;

  // Text styles
  static pw.TextStyle get h1Bold => pw.TextStyle(fontSize: h1, fontWeight: pw.FontWeight.bold);
  static pw.TextStyle get headerCell => pw.TextStyle(fontSize: body, fontWeight: pw.FontWeight.bold);
  static pw.TextStyle get cell => pw.TextStyle(fontSize: small);
  static pw.TextStyle get note => pw.TextStyle(fontSize: small, color: textMuted);
  static pw.TextStyle get accentSmall => pw.TextStyle(fontSize: small, color: accent);
}
