import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stream of aggregate sales totals for current day, week, and month.
/// Uses latest up to 500 invoices ordered by timestamp descending.
final salesAggregateProvider = StreamProvider<Map<String, double>>((ref) {
  final col = FirebaseFirestore.instance
      .collection('invoices')
      .orderBy('timestampMs', descending: true)
      .limit(500);
  return col.snapshots().map((snap) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(Duration(days: todayStart.weekday - 1)); // Monday
    final monthStart = DateTime(now.year, now.month, 1);
    double today = 0, week = 0, month = 0;
    for (final d in snap.docs) {
      final data = d.data();
      final raw = data['timestampMs'];
      int tsMs;
      if (raw is int) {
        tsMs = raw;
      } else {
        tsMs = int.tryParse(raw?.toString() ?? '') ?? 0;
      }
      if (tsMs == 0) continue;
      final dt = DateTime.fromMillisecondsSinceEpoch(tsMs);
      if (dt.isBefore(monthStart)) break; // because list is descending
      final lines = (data['lines'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
      double total = 0;
      for (final l in lines) {
        final unit = (l['unitPrice'] is num)
            ? (l['unitPrice'] as num).toDouble()
            : double.tryParse('${l['unitPrice']}') ?? 0;
        final qty = (l['qty'] is num)
            ? (l['qty'] as num).toDouble()
            : double.tryParse('${l['qty']}') ?? 1;
        total += unit * qty;
      }
      if (!dt.isBefore(monthStart)) month += total;
      if (!dt.isBefore(weekStart)) week += total;
      if (!dt.isBefore(todayStart)) today += total;
    }
    return {'today': today, 'week': week, 'month': month};
  });
});

/// Internal lightweight ledger entry model (subset of accounting logic) used
/// to derive payment splits. We only care about sales (in) and purchases (out)
/// along with payment method.
class _LedgerEntryLite {
  final double inAmt; final double outAmt; final String method;
  _LedgerEntryLite(this.inAmt, this.outAmt, this.method);
}

/// Stream of ledger entries combining sales and purchase invoices similar to
/// accounting screen logic, but simplified for providers.
final _ledgerEntriesProvider = StreamProvider<List<_LedgerEntryLite>>((ref) {
  final salesCol = FirebaseFirestore.instance
      .collection('invoices')
      .orderBy('timestampMs', descending: false);
  final purchasesCol = FirebaseFirestore.instance
      .collection('purchase_invoices')
      .orderBy('timestampMs', descending: false);

  // Merge two streams manually.
  Stream<List<_LedgerEntryLite>> sales$ = salesCol.snapshots().map((snap) {
    return snap.docs.map((d) {
      final data = d.data();
      final lines = (data['lines'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
      double sum = 0;
      for (final l in lines) {
        final unit = (l['unitPrice'] is num) ? (l['unitPrice'] as num).toDouble() : double.tryParse('${l['unitPrice']}') ?? 0;
        final qty = (l['qty'] is num) ? (l['qty'] as num).toDouble() : double.tryParse('${l['qty']}') ?? 1;
        sum += unit * qty;
      }
      final method = (data['paymentMode'] ?? 'Unknown').toString();
      return _LedgerEntryLite(sum, 0, method);
    }).toList();
  });

  Stream<List<_LedgerEntryLite>> purchases$ = purchasesCol.snapshots().map((snap) {
    return snap.docs.map((d) {
      final data = d.data();
      final summary = (data['summary'] as Map?) ?? const {};
      double grand = 0;
      final raw = summary['grandTotal'];
      if (raw is num) {
        grand = raw.toDouble();
      } else {
        grand = double.tryParse(raw?.toString() ?? '0') ?? 0;
      }
      final method = (data['paymentMode'] ?? (data['payment']?['mode'] ?? 'Unknown')).toString();
      return _LedgerEntryLite(0, grand, method);
    }).toList();
  });

  // CombineLatest equivalent using manual buffering
  return Stream<List<_LedgerEntryLite>>.multi((controller) {
    List<_LedgerEntryLite>? salesLatest;
    List<_LedgerEntryLite>? purchaseLatest;
    late final StreamSubscription sub1; late final StreamSubscription sub2;
    void emitIfReady() {
      if (salesLatest != null && purchaseLatest != null) {
        controller.add([...salesLatest!, ...purchaseLatest!]);
      }
    }
    sub1 = sales$.listen((s) { salesLatest = s; emitIfReady(); });
    sub2 = purchases$.listen((p) { purchaseLatest = p; emitIfReady(); });
    controller.onCancel = () { sub1.cancel(); sub2.cancel(); };
  });
});

/// Derives payment split percentages (cash / upi / card) from ledger entries.
/// If no data, returns zeros.
final paymentSplitProvider = StreamProvider<Map<String, double>>((ref) {
  // ignore: deprecated_member_use
  return ref.watch(_ledgerEntriesProvider.stream).map((entries) {
    final Map<String, double> netBy = {};
    for (final e in entries) {
      final m = e.method.isEmpty ? 'Unknown' : e.method;
      netBy[m] = (netBy[m] ?? 0) + (e.inAmt - e.outAmt);
    }
    double cash = netBy['Cash'] ?? 0;
    double upi = netBy['UPI'] ?? 0;
    double card = netBy['Card'] ?? 0;
    final total = (cash + upi + card).abs();
    if (total <= 0) return {'cash':0.0,'upi':0.0,'card':0.0};
    // Convert to positive share (ignore sign if negatives introduced by purchases)
    cash = cash.abs(); upi = upi.abs(); card = card.abs();
    final sum = cash + upi + card;
    if (sum <= 0) return {'cash':0.0,'upi':0.0,'card':0.0};
    return {
      'cash': (cash / sum) * 100,
      'upi': (upi / sum) * 100,
      'card': (card / sum) * 100,
    };
  });
});

/// Top-selling products (simple aggregation of invoice lines). Returns a list
/// of maps: [{'name':..., 'units': double, 'revenue': double}, ...] sorted by
/// revenue desc, limited to top 10.
final topSellingProductsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final invoices = FirebaseFirestore.instance
      .collection('invoices')
      .orderBy('timestampMs', descending: true)
      .limit(400); // safety cap
  return invoices.snapshots().map((snap) {
    final Map<String, _ProdAgg> agg = {};
    for (final d in snap.docs) {
      final data = d.data();
      final lines = (data['lines'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
      for (final l in lines) {
        final name = (l['name'] ?? l['product'] ?? '').toString();
        if (name.isEmpty) continue;
        final unitPrice = (l['unitPrice'] is num) ? (l['unitPrice'] as num).toDouble() : double.tryParse('${l['unitPrice']}') ?? 0;
        final qty = (l['qty'] is num) ? (l['qty'] as num).toDouble() : double.tryParse('${l['qty']}') ?? 1;
        final rec = agg.putIfAbsent(name, () => _ProdAgg());
        rec.units += qty;
        rec.revenue += unitPrice * qty;
      }
    }
    final list = agg.entries.map((e) => {
      'name': e.key,
      'units': e.value.units,
      'revenue': e.value.revenue,
    }).toList();
    list.sort((a,b) => (b['revenue'] as double).compareTo(a['revenue'] as double));
    if (list.length > 10) {
      list.removeRange(10, list.length);
    }
    return list;
  });
});

class _ProdAgg { double units = 0; double revenue = 0; }

/// Inventory alerts (low stock & near expiry). Reads inventory collection and
/// inspects batches.
/// Returns list of maps: [{'product':..,'sku':..,'stock':int,'expiry':String,'status':String}]
/// Low stock threshold: < 10; Near expiry: within 7 days.
final inventoryAlertsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final inv = FirebaseFirestore.instance.collection('inventory');
  return inv.snapshots().map((snap) {
    final now = DateTime.now();
    final soon = now.add(const Duration(days: 7));
    final alerts = <Map<String, dynamic>>[];
    for (final d in snap.docs) {
      final data = d.data();
      final name = (data['name'] ?? '').toString();
      final sku = d.id;
      final batches = (data['batches'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
      int totalQty = 0; DateTime? nearestExpiry;
      for (final b in batches) {
        final q = b['qty'];
        int qty = 0;
        if (q is int) {
          qty = q;
        } else if (q is num) {
          qty = q.toInt();
        } else if (q != null) {
          qty = int.tryParse(q.toString()) ?? 0;
        }
        totalQty += qty;
        final exp = b['expiry'];
        DateTime? expDt;
        if (exp is Timestamp) {
          expDt = exp.toDate();
        } else if (exp is DateTime) {
          expDt = exp;
        } else if (exp != null) {
          try {
            expDt = DateTime.parse(exp.toString());
          } catch (_) {}
        }
        if (expDt != null && (nearestExpiry == null || expDt.isBefore(nearestExpiry))) {
          nearestExpiry = expDt;
        }
      }
      final lowStock = totalQty < 10; // threshold
  final nearExpiry = nearestExpiry != null && nearestExpiry.isBefore(soon) && nearestExpiry.isAfter(now);
      if (lowStock || nearExpiry) {
        alerts.add({
          'product': name.isEmpty ? 'Unnamed' : name,
          'sku': sku,
            'stock': totalQty,
          'expiry': nearestExpiry == null ? '—' : _fmtDate(nearestExpiry),
          'status': lowStock && nearExpiry
              ? 'Low & Near Expiry'
              : (lowStock ? 'Low Stock' : 'Near Expiry'),
        });
      }
    }
    alerts.sort((a,b) => (a['product'] as String).compareTo(b['product'] as String));
    if (alerts.length > 10) {
      alerts.removeRange(10, alerts.length); // limit to 10
    }
    return alerts;
  });
});

String _fmtDate(DateTime dt) {
  return dt.toIso8601String().split('T').first;
}
