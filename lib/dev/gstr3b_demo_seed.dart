import 'package:cloud_firestore/cloud_firestore.dart';

/// Seeds demo sales and purchase invoices sufficient to compute a sample
/// GSTR-3B. Safe to call multiple times; existing docs are skipped unless
/// [overwrite] is true.
Future<void> seedGstr3bDemoData({
  DateTime? periodStart,
  DateTime? periodEnd,
  bool overwrite = false,
}) async {
  final fs = FirebaseFirestore.instance;
  final now = DateTime.now();
  final start = periodStart ?? DateTime(now.year, now.month, 1);
  final end = periodEnd ?? DateTime(now.year, now.month + 1, 0, 23, 59, 59);
  final startMs = start.millisecondsSinceEpoch;
  final day = Duration(days: 1);

  int dayIndex = 0;
  DateTime nextDay() => start.add(day * (dayIndex++));

  double _grossFrom({required double taxable, required int ratePct}) => taxable * (1 + ratePct / 100.0);
  Map<String, dynamic> _salesLine(String name, double taxable, int ratePct) => {
        'sku': name.replaceAll(' ', '-').toUpperCase(),
        'name': name,
        // store tax inclusive price per unit; we'll just put the gross amount as unitPrice and qty 1
    'unitPrice': _grossFrom(taxable: taxable, ratePct: ratePct),
        'qty': 1,
        'taxPercent': ratePct,
      };

  // ---------------- Sales Invoices ----------------
  final sales = <Map<String, dynamic>>[
    {
      'id': 'INV-001',
      'lines': [_salesLine('Domestic Standard A', 50000, 18)],
      'flags': <String, bool>{},
      'paymentMode': 'Cash',
    },
    {
      'id': 'INV-002',
      'lines': [_salesLine('Domestic Standard B2B', 80000, 18)],
      'flags': <String, bool>{},
      'paymentMode': 'UPI',
    },
    {
      'id': 'INV-003',
      'lines': [_salesLine('Export Zero Rated', 40000, 0)],
      'flags': {'zeroRated': true},
      'paymentMode': 'Card',
    },
    {
      'id': 'INV-004',
      'lines': [_salesLine('Exempt Goods', 10000, 0)],
      'flags': {'exempt': true},
      'paymentMode': 'Cash',
    },
    {
      'id': 'INV-006',
      'lines': [
        _salesLine('Mixed Item 12%', 12000, 12),
        _salesLine('Mixed Item 5%', 18000, 5),
      ],
      'flags': <String, bool>{},
      'paymentMode': 'UPI',
    },
  ];

  for (final inv in sales) {
    final id = inv['id'] as String;
    final doc = fs.collection('invoices').doc(id);
    if (!overwrite && (await doc.get()).exists) continue;
    final lines = (inv['lines'] as List).cast<Map<String, dynamic>>();
    final flags = (inv['flags'] as Map<String, bool>);
    final ts = nextDay();
    await doc.set({
      'invoiceNo': id,
      'timestampMs': ts.millisecondsSinceEpoch.clamp(startMs, end.millisecondsSinceEpoch),
      'lines': lines,
      'customerName': 'Demo Customer',
      'status': 'Paid',
      'paymentMode': inv['paymentMode'],
      ...flags,
    });
  }

  // ---------------- Purchase Invoices ----------------
  Map<String, dynamic> purchaseDoc({
    required String id,
    required double taxable,
    required int rate,
    String supplier = 'Demo Supplier',
    bool zeroRated = false,
    bool exempt = false,
    bool rcm = false,
    bool ineligible = false,
    bool capital = false,
  }) {
    final cgst = zeroRated || exempt ? 0 : (rate == 0 ? 0 : taxable * (rate / 100) / 2);
    final sgst = cgst;
    final igst = 0; // keeping demo all intra-state
    final grand = taxable + cgst + sgst + igst;
    return {
      'invoiceNo': id,
      'supplier': supplier,
      'timestampMs': nextDay().millisecondsSinceEpoch,
      'invoiceDate': DateTime.now().toIso8601String(),
      'type': 'Standard',
      'items': [
        {
          'name': 'Input $rate%',
          'qty': 1,
          'unitPrice': taxable,
          'gstRate': rate,
        }
      ],
      'summary': {
        'cgst': cgst,
        'sgst': sgst,
        'igst': igst,
        'grandTotal': grand,
      },
      'paymentMode': 'Cash',
      'createdAt': DateTime.now().toIso8601String(),
      if (zeroRated) 'zeroRated': true,
      if (exempt) 'exempt': true,
      if (rcm) 'rcm': true,
      if (ineligible) 'ineligibleItc': true,
      if (capital) 'capital': true,
    };
  }

  final purchases = <Map<String, dynamic>>[
    purchaseDoc(id: 'PINV-001', taxable: 60000, rate: 18),
    purchaseDoc(id: 'PINV-002', taxable: 120000, rate: 18, capital: true),
    purchaseDoc(id: 'PINV-003', taxable: 20000, rate: 12),
    purchaseDoc(id: 'PINV-004', taxable: 15000, rate: 0, zeroRated: true),
    purchaseDoc(id: 'PINV-005', taxable: 8000, rate: 0, exempt: true),
    purchaseDoc(id: 'PINV-006', taxable: 25000, rate: 18, rcm: true),
    purchaseDoc(id: 'PINV-007', taxable: 5000, rate: 18, ineligible: true),
  ];

  for (final p in purchases) {
    final id = p['invoiceNo'] as String;
    final doc = fs.collection('purchase_invoices').doc(id);
    if (!overwrite && (await doc.get()).exists) continue;
    await doc.set(p);
  }
}
