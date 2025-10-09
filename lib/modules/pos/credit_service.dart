import 'package:cloud_firestore/cloud_firestore.dart';

/// Result of a credit mutation.
class CreditOpResult {
  final double previousBalance;
  final double newBalance;
  final double amountChanged; // positive for add, negative for repayment
  final String type; // add_sale | repayment
  final String? invoiceNumber;
  final bool ledgerRecorded;
  CreditOpResult({
    required this.previousBalance,
    required this.newBalance,
    required this.amountChanged,
    required this.type,
    this.invoiceNumber,
    this.ledgerRecorded = true,
  });
}

class CustomerCreditService {
  static final _fs = FirebaseFirestore.instance;

  /// Adds a sale amount to customer credit (customer owes the business).
  /// Creates a ledger entry at `customers/{id}/credit_ledger/{autoId}`.
  static Future<CreditOpResult> addSaleOnCredit({
    required String customerId,
    required double amount,
    required String invoiceNumber,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('Amount must be > 0');
    }
    final custRef = _fs.collection('customers').doc(customerId);
    final ledgerRef = custRef.collection('credit_ledger').doc();
    late CreditOpResult result;
    await _fs.runTransaction((tx) async {
      final snap = await tx.get(custRef);
      if (!snap.exists) {
        // Initialize minimal customer doc if somehow missing (prevent null crash)
        tx.set(custRef, {'creditBalance': 0, 'createdAt': FieldValue.serverTimestamp()});
      }
      final data = snap.data() ?? <String, dynamic>{};
      final prevRaw = data['creditBalance'] ?? data['khathaBalance'] ?? 0;
      double prev = 0;
      if (prevRaw is num) prev = prevRaw.toDouble();
      else if (prevRaw is String) prev = double.tryParse(prevRaw) ?? 0;
      final next = prev + amount;
      tx.update(custRef, {
        'creditBalance': next,
        'creditUpdatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(ledgerRef, {
        'type': 'add_sale',
        'amount': amount,
        'balanceAfter': next,
        'invoiceNumber': invoiceNumber,
        'timestamp': FieldValue.serverTimestamp(),
      });
      result = CreditOpResult(
        previousBalance: prev,
        newBalance: next,
        amountChanged: amount,
        type: 'add_sale',
        invoiceNumber: invoiceNumber,
      );
    });
    return result;
  }

  /// Repays (reduces) customer credit. Amount is clamped to existing balance.
  static Future<CreditOpResult> repayCredit({
    required String customerId,
    required double amount,
  }) async {
    if (amount <= 0) {
      throw ArgumentError('Amount must be > 0');
    }
    final custRef = _fs.collection('customers').doc(customerId);
    final ledgerRef = custRef.collection('credit_ledger').doc();
    late CreditOpResult result;
    try {
      await _fs.runTransaction((tx) async {
        final snap = await tx.get(custRef);
        if (!snap.exists) {
          throw StateError('Customer not found');
        }
        final data = snap.data() ?? <String, dynamic>{};
        final prevRaw = data['creditBalance'] ?? data['khathaBalance'] ?? 0;
        double prev = 0;
        if (prevRaw is num) {
          prev = prevRaw.toDouble();
        } else if (prevRaw is String) {
          prev = double.tryParse(prevRaw) ?? 0;
        }
        final repay = amount > prev ? prev : amount;
        final next = prev - repay;
        tx.update(custRef, {
          'creditBalance': next,
          'creditUpdatedAt': FieldValue.serverTimestamp(),
        });
        tx.set(ledgerRef, {
          'type': 'repayment',
          'amount': repay,
          'balanceAfter': next,
          'timestamp': FieldValue.serverTimestamp(),
        });
        result = CreditOpResult(
          previousBalance: prev,
          newBalance: next,
          amountChanged: -repay,
          type: 'repayment',
          ledgerRecorded: true,
        );
      });
      return result;
    } on FirebaseException catch (e) {
      // Permission denied fallback: try simple creditBalance decrement without ledger (if rules allow anonymous delta)
      if (e.code == 'permission-denied') {
        await _fs.runTransaction((tx) async {
          final snap = await tx.get(custRef);
          if (!snap.exists) {
            throw StateError('Customer not found');
          }
          final data = snap.data() ?? <String, dynamic>{};
          final prevRaw = data['creditBalance'] ?? data['khathaBalance'] ?? 0;
          double prev = 0;
          if (prevRaw is num) {
            prev = prevRaw.toDouble();
          } else if (prevRaw is String) {
            prev = double.tryParse(prevRaw) ?? 0;
          }
          final repay = amount > prev ? prev : amount;
          final next = prev - repay;
          tx.update(custRef, {
            'creditBalance': next,
            'creditUpdatedAt': FieldValue.serverTimestamp(),
          });
          result = CreditOpResult(
            previousBalance: prev,
            newBalance: next,
            amountChanged: -repay,
            type: 'repayment',
            ledgerRecorded: false,
          );
        });
        return result;
      }
      rethrow;
    }
  }

  /// Adjusts customer credit for a single checkout that might both:
  ///  - add to credit (unpaid portion of this sale)
  ///  - repay existing credit (excess cash paid relative to this sale)
  /// Only one of [creditAdd] or [creditRepay] is typically > 0, but the
  /// method safely handles both being > 0 by applying addition first then repayment.
  /// Returns the net effect. Positive amountChanged means balance increased, negative means decreased.
  static Future<CreditOpResult> adjustForCheckout({
    required String customerId,
    required double creditAdd,
    required double creditRepay,
    required String invoiceNumber,
  }) async {
    // Normalize inputs (no negatives)
    final addPortion = creditAdd.isNaN ? 0.0 : creditAdd.clamp(0, double.infinity);
    final repayPortion = creditRepay.isNaN ? 0.0 : creditRepay.clamp(0, double.infinity);
    if (addPortion == 0 && repayPortion == 0) {
      // Nothing to do: fetch current balance to return a result for consistency.
      final snap = await _fs.collection('customers').doc(customerId).get();
      final data = snap.data() ?? <String, dynamic>{};
      final prevRaw = data['creditBalance'] ?? data['khathaBalance'] ?? 0;
      double prev = 0;
      if (prevRaw is num) prev = prevRaw.toDouble();
      else if (prevRaw is String) prev = double.tryParse(prevRaw) ?? 0;
      return CreditOpResult(
        previousBalance: prev,
        newBalance: prev,
        amountChanged: 0,
        type: 'noop',
        invoiceNumber: invoiceNumber,
        ledgerRecorded: false,
      );
    }

    final custRef = _fs.collection('customers').doc(customerId);
    // Pre-create ledger doc refs (up to two) for deterministic ordering inside transaction
    final ledgerAddRef = addPortion > 0 ? custRef.collection('credit_ledger').doc() : null;
    final ledgerRepayRef = repayPortion > 0 ? custRef.collection('credit_ledger').doc() : null;
    late CreditOpResult result;

  Future<CreditOpResult> txBody(Transaction tx) async {
      final snap = await tx.get(custRef);
      if (!snap.exists) {
        // Initialize minimal customer doc to avoid nulls
        tx.set(custRef, {'creditBalance': 0, 'createdAt': FieldValue.serverTimestamp()});
      }
      final data = snap.data() ?? <String, dynamic>{};
      final prevRaw = data['creditBalance'] ?? data['khathaBalance'] ?? 0;
      double prev = 0;
      if (prevRaw is num) {
        prev = prevRaw.toDouble();
      } else if (prevRaw is String) {
        prev = double.tryParse(prevRaw) ?? 0;
      }

      // Apply add then repayment ensuring we don't go negative.
      double intermediate = prev + addPortion;
  double repayClamp = repayPortion.clamp(0, intermediate).toDouble(); // cannot repay more than after addition
      double next = intermediate - repayClamp;

      tx.update(custRef, {
        'creditBalance': next,
        'creditUpdatedAt': FieldValue.serverTimestamp(),
      });

      if (ledgerAddRef != null && addPortion > 0) {
        tx.set(ledgerAddRef, {
          'type': 'add_sale',
          'amount': addPortion,
          'balanceAfter': intermediate, // balance after addition but before repayment
          'invoiceNumber': invoiceNumber,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
      if (ledgerRepayRef != null && repayClamp > 0) {
        tx.set(ledgerRepayRef, {
          'type': 'repayment',
          'amount': repayClamp,
          'balanceAfter': next,
          'invoiceNumber': invoiceNumber,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      final net = (addPortion - repayClamp);
      result = CreditOpResult(
        previousBalance: prev,
        newBalance: next,
        amountChanged: net, // positive => added, negative => repaid
        type: (addPortion > 0 && repayClamp > 0)
            ? 'mixed'
            : (addPortion > 0 ? 'add_sale' : 'repayment'),
        invoiceNumber: invoiceNumber,
        ledgerRecorded: true,
      );
      return result;
    }

    try {
  await _fs.runTransaction(txBody);
      return result;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        // Fallback without ledger entries.
        await _fs.runTransaction((tx) async {
          final snap = await tx.get(custRef);
            if (!snap.exists) {
              tx.set(custRef, {'creditBalance': 0, 'createdAt': FieldValue.serverTimestamp()});
            }
            final data = snap.data() ?? <String, dynamic>{};
            final prevRaw = data['creditBalance'] ?? data['khathaBalance'] ?? 0;
            double prev = 0;
            if (prevRaw is num) {
              prev = prevRaw.toDouble();
            } else if (prevRaw is String) {
              prev = double.tryParse(prevRaw) ?? 0;
            }
            double intermediate = prev + addPortion;
            double repayClamp = repayPortion.clamp(0, intermediate).toDouble();
            double next = intermediate - repayClamp;
            tx.update(custRef, {
              'creditBalance': next,
              'creditUpdatedAt': FieldValue.serverTimestamp(),
            });
            final net = addPortion - repayClamp;
            result = CreditOpResult(
              previousBalance: prev,
              newBalance: next,
              amountChanged: net,
              type: (addPortion > 0 && repayClamp > 0)
                  ? 'mixed'
                  : (addPortion > 0 ? 'add_sale' : 'repayment'),
              invoiceNumber: invoiceNumber,
              ledgerRecorded: false,
            );
        });
        return result;
      }
      rethrow;
    }
  }

  /// Ensures the customer document has a numeric `creditBalance` field.
  /// If the doc exists and lacks both `creditBalance` and legacy `khathaBalance`,
  /// this will set `creditBalance` to 0 (idempotent safe initialization).
  static Future<void> ensureCreditField(String customerId) async {
    final ref = _fs.collection('customers').doc(customerId);
    try {
      await _fs.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return; // don't create customer implicitly
        final data = snap.data() ?? <String, dynamic>{};
        if (!data.containsKey('creditBalance') && !data.containsKey('khathaBalance')) {
          tx.update(ref, {
            'creditBalance': 0.0,
            'creditUpdatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (e) {
      // Swallow silently; absence just means we couldn't initialize.
    }
  }

  /// Pure helper to compute credit mixing outcomes without side effects.
  /// [saleDue] - amount due for current cart after discounts/redemptions.
  /// [existingCredit] - current outstanding credit before this sale.
  /// [paidNow] - amount customer pays now.
  /// Returns a map: {add: double, repay: double, net: double, newCredit: double}
  static Map<String, double> computeCreditMix({
    required double saleDue,
    required double existingCredit,
    required double paidNow,
  }) {
    final safeSale = saleDue.isNaN ? 0.0 : saleDue.clamp(0, double.infinity);
    final safeExisting = existingCredit.isNaN ? 0.0 : existingCredit.clamp(0, double.infinity);
    final safePaid = paidNow.isNaN ? 0.0 : paidNow.clamp(0, double.infinity);
    double addPortion = 0;
    double repayPortion = 0;
    if (safePaid >= safeSale) {
      final excess = safePaid - safeSale;
      repayPortion = excess.clamp(0, safeExisting).toDouble();
    } else {
      addPortion = (safeSale - safePaid).toDouble();
    }
    final newCredit = safeExisting + addPortion - repayPortion;
    final net = addPortion - repayPortion; // positive => increase, negative => decrease
    return {
      'add': addPortion,
      'repay': repayPortion,
      'net': net,
      'newCredit': newCredit,
    };
  }
}
