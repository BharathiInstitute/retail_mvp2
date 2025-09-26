import 'package:cloud_firestore/cloud_firestore.dart';

/// Basic GSTR-3B summary model (condensed) covering main table buckets.
class Gstr3bSummary {
  // Table 3.1
  final double outwardTaxable; // 3.1(a) taxable value (excl zero/nil/exempt)
  final double outwardZeroRated; // 3.1(b)
  final double outwardExemptNil; // 3.1(c)
  final double inwardReverseChargeTaxable; // 3.1(d) taxable value liable to RCM
  final double taxOnOutward; // total tax on outward taxable supplies (approx CGST+SGST+IGST)
  final double taxOnRCM; // tax payable under reverse charge (inward supplies)

  // Table 4 - ITC
  final double itcInputsCgst;
  final double itcInputsSgst;
  final double itcInputsIgst;
  final double itcCapitalGoods; // simple bucket
  final double itcInwardRCMEligible; // eligible from RCM supplies
  final double itcIneligible; // ineligible ITC

  const Gstr3bSummary({
    required this.outwardTaxable,
    required this.outwardZeroRated,
    required this.outwardExemptNil,
    required this.inwardReverseChargeTaxable,
    required this.taxOnOutward,
    required this.taxOnRCM,
    required this.itcInputsCgst,
    required this.itcInputsSgst,
    required this.itcInputsIgst,
    required this.itcCapitalGoods,
    required this.itcInwardRCMEligible,
    required this.itcIneligible,
  });

  double get totalEligibleITC => itcInputsCgst + itcInputsSgst + itcInputsIgst + itcCapitalGoods + itcInwardRCMEligible;
}

/// Service that computes a simplified GSTR-3B from Firestore.
class Gstr1Summary {
  final double b2bTaxable;
  final double b2cTaxable;
  final double zeroRated;
  final double exempt;
  final double taxOnB2BAndB2C; // aggregate output tax
  final int b2bCount;
  final int b2cCount;
  final int zeroCount;
  final int exemptCount;
  const Gstr1Summary({
    required this.b2bTaxable,
    required this.b2cTaxable,
    required this.zeroRated,
    required this.exempt,
    required this.taxOnB2BAndB2C,
    required this.b2bCount,
    required this.b2cCount,
    required this.zeroCount,
    required this.exemptCount,
  });
  double get totalOutwardTaxable => b2bTaxable + b2cTaxable;
}
class Gstr3bService {
  final FirebaseFirestore _db;
  Gstr3bService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  // GSTR-1 compute preserved (moved from earlier definition)
  Future<Gstr1Summary> computeGstr1({required DateTime from, required DateTime to, String? paymentMode}) async {
    final fromMs = from.millisecondsSinceEpoch;
    final toMs = to.millisecondsSinceEpoch;
    double b2bTaxable = 0, b2cTaxable = 0, zeroRated = 0, exempt = 0;
    double taxValueTotal = 0; // total tax (cgst+sgst+igst) for outward
    int b2bCount = 0, b2cCount = 0, zeroCount = 0, exemptCount = 0;

    final salesSnap = await _db
        .collection('invoices')
        .where('timestampMs', isGreaterThanOrEqualTo: fromMs)
        .where('timestampMs', isLessThanOrEqualTo: toMs)
        .get();
    for (final d in salesSnap.docs) {
      final data = d.data();
      if (paymentMode != null && paymentMode.trim().isNotEmpty) {
        final pm = (data['paymentMode'] ?? '').toString().toLowerCase();
        if (pm != paymentMode.toLowerCase()) continue;
      }
      final isZero = data['zeroRated'] == true;
      final isExempt = data['exempt'] == true;
      final customerName = (data['customerName'] ?? '').toString();
      final isB2B = customerName.toUpperCase().contains('B2B');
      final lines = (data['lines'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
      double invoiceTaxable = 0, invoiceTax = 0;
      for (final l in lines) {
        final rate = _toDouble(l['taxPercent']);
        final qty = _toDouble(l['qty']);
        final unitPrice = _toDouble(l['unitPrice']);
        final gross = unitPrice * (qty == 0 ? 1 : qty);
        final base = rate > 0 ? gross / (1 + rate / 100) : gross;
        final tax = gross - base;
        invoiceTaxable += base;
        invoiceTax += tax;
      }
      if (isZero) { zeroRated += invoiceTaxable; zeroCount++; }
      else if (isExempt) { exempt += invoiceTaxable; exemptCount++; }
      else if (isB2B) { b2bTaxable += invoiceTaxable; b2bCount++; taxValueTotal += invoiceTax; }
      else { b2cTaxable += invoiceTaxable; b2cCount++; taxValueTotal += invoiceTax; }
    }
    return Gstr1Summary(
      b2bTaxable: b2bTaxable,
      b2cTaxable: b2cTaxable,
      zeroRated: zeroRated,
      exempt: exempt,
      taxOnB2BAndB2C: taxValueTotal,
      b2bCount: b2bCount,
      b2cCount: b2cCount,
      zeroCount: zeroCount,
      exemptCount: exemptCount,
    );
  }

  Future<Gstr3bSummary> compute({required DateTime from, required DateTime to, String? paymentMode}) async {
    final fromMs = from.millisecondsSinceEpoch;
    final toMs = to.millisecondsSinceEpoch;

    double outwardTaxable = 0;
    double outwardZeroRated = 0;
    double outwardExemptNil = 0;
    double inwardReverseChargeTaxable = 0;
    double taxOnOutward = 0;
    double taxOnRCM = 0;

    double itcInputsCgst = 0;
    double itcInputsSgst = 0;
    double itcInputsIgst = 0;
    double itcCapitalGoods = 0;
    double itcInwardRCMEligible = 0;
    double itcIneligible = 0;

    // ---- SALES (invoices) ----
    final salesSnap = await _db
        .collection('invoices')
        .where('timestampMs', isGreaterThanOrEqualTo: fromMs)
        .where('timestampMs', isLessThanOrEqualTo: toMs)
        .get();

    for (final d in salesSnap.docs) {
      final data = d.data();
      if (paymentMode != null && paymentMode.trim().isNotEmpty) {
        final pm = (data['paymentMode'] ?? '').toString().toLowerCase();
        if (pm != paymentMode.toLowerCase()) continue;
      }
      final zeroRated = data['zeroRated'] == true;
      final exempt = data['exempt'] == true;
      final lines = (data['lines'] as List?)?.whereType<Map>().toList() ?? const <Map>[];
      for (final l in lines) {
        final qty = (l['qty'] is num) ? (l['qty'] as num).toDouble() : double.tryParse('${l['qty']}') ?? 1;
        final unitPrice = (l['unitPrice'] is num) ? (l['unitPrice'] as num).toDouble() : double.tryParse('${l['unitPrice']}') ?? 0;
        final rate = (l['taxPercent'] is num) ? (l['taxPercent'] as num).toDouble() : double.tryParse('${l['taxPercent']}') ?? 0;
        final gross = unitPrice * qty; // inclusive
        final base = rate > 0 ? gross / (1 + rate / 100) : gross;
        final tax = gross - base;
        if (zeroRated) {
          outwardZeroRated += base;
        } else if (exempt || rate == 0) {
          outwardExemptNil += base;
        } else {
          outwardTaxable += base;
          taxOnOutward += tax; // treat combined for simplicity
        }
      }
    }

    // ---- PURCHASES (purchase_invoices) ----
    final purchaseSnap = await _db
        .collection('purchase_invoices')
        .where('timestampMs', isGreaterThanOrEqualTo: fromMs)
        .where('timestampMs', isLessThanOrEqualTo: toMs)
        .get();

    for (final d in purchaseSnap.docs) {
      final data = d.data();
      if (paymentMode != null && paymentMode.trim().isNotEmpty) {
        final pm = (data['paymentMode'] ?? (data['payment']?['mode'] ?? '')).toString().toLowerCase();
        if (pm != paymentMode.toLowerCase()) continue;
      }
      final zeroRated = data['zeroRated'] == true;
      final exempt = data['exempt'] == true;
      final rcm = data['rcm'] == true;
      final ineligible = data['ineligibleItc'] == true;
      final capital = data['capital'] == true;
      final summary = (data['summary'] as Map?) ?? const {};
      double cgst = _toDouble(summary['cgst']);
      double sgst = _toDouble(summary['sgst']);
      double igst = _toDouble(summary['igst']);
      double grand = _toDouble(summary['grandTotal']);
      final taxable = grand - (cgst + sgst + igst);

      if (rcm) {
        inwardReverseChargeTaxable += taxable;
        taxOnRCM += cgst + sgst + igst; // liability
        // Eligible ITC once paid (simplified assumption)
        itcInwardRCMEligible += cgst + sgst + igst;
        continue;
      }
      if (zeroRated || exempt) {
        // no ITC, nothing else
        continue;
      }
      if (ineligible) {
        itcIneligible += cgst + sgst + igst;
        continue;
      }
      if (capital) {
        itcCapitalGoods += cgst + sgst + igst;
      } else {
        itcInputsCgst += cgst;
        itcInputsSgst += sgst;
        itcInputsIgst += igst;
      }
    }

    return Gstr3bSummary(
      outwardTaxable: outwardTaxable,
      outwardZeroRated: outwardZeroRated,
      outwardExemptNil: outwardExemptNil,
      inwardReverseChargeTaxable: inwardReverseChargeTaxable,
      taxOnOutward: taxOnOutward,
      taxOnRCM: taxOnRCM,
      itcInputsCgst: itcInputsCgst,
      itcInputsSgst: itcInputsSgst,
      itcInputsIgst: itcInputsIgst,
      itcCapitalGoods: itcCapitalGoods,
      itcInwardRCMEligible: itcInwardRCMEligible,
      itcIneligible: itcIneligible,
    );
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }
}
