import 'dart:convert';

/// Very small CSV helper that handles simple cases (no embedded commas/newlines).
/// For production, consider using the `csv` package for robust parsing.
class CsvUtils {
  static const headers = [
    'tenantId',
    'sku',
    'name',
    'barcode',
    'unitPrice',
    'taxPct',
    'mrpPrice',
    'costPrice',
    'variants', // comma-separated
    'description',
    'isActive',
    'storeQty',
    'warehouseQty',
  ];

  static String listToCsv(List<List<String>> rows) {
    final sb = StringBuffer();
    for (final r in rows) {
      sb.writeln(r.map(_escape).join(','));
    }
    return sb.toString();
  }

  static List<List<String>> csvToList(String csv) {
    final lines = const LineSplitter().convert(csv.trim());
    return [
      for (final line in lines)
        line.split(',').map((s) => _unescape(s)).toList(),
    ];
  }

  static String _escape(String v) {
    // Simple escape: wrap values with commas or quotes into quotes and escape inner quotes
    if (v.contains(',') || v.contains('"') || v.contains('\n')) {
      final escaped = v.replaceAll('"', '""');
      return '"$escaped"';
    }
    return v;
  }

  static String _unescape(String v) {
    v = v.trim();
    if (v.startsWith('"') && v.endsWith('"')) {
      v = v.substring(1, v.length - 1).replaceAll('""', '"');
    }
    return v;
  }
}
