import 'package:flutter/foundation.dart';
import '../models/debt.dart';
import '../services/database_service.dart';

class DebtProvider with ChangeNotifier {
  final List<Debt> _debts = [];
  // Undo caches
  Map<String, dynamic>? _lastDeletedPayment; // {debtId, amount, note, createdAt}
  Debt? _lastDeletedDebt;
  List<Map<String, dynamic>> _lastDeletedDebtPayments = const [];

  List<Debt> get debts => List.unmodifiable(_debts);

  Future<void> load() async {
    final data = await DatabaseService.instance.getDebts();
    _debts
      ..clear()
      ..addAll(data);
    notifyListeners();
  }

  Future<Debt?> getById(String debtId) async {
    try {
      return await DatabaseService.instance.getDebtById(debtId);
    } catch (_) {
      try {
        return _debts.firstWhere((d) => d.id == debtId);
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> updateDebtCreatedAt({required Debt debt, required DateTime createdAt}) async {
    final updated = Debt(
      id: debt.id,
      createdAt: createdAt,
      type: debt.type,
      partyId: debt.partyId,
      partyName: debt.partyName,
      amount: debt.amount,
      description: debt.description,
      dueDate: debt.dueDate,
      settled: debt.settled,
      sourceType: debt.sourceType,
      sourceId: debt.sourceId,
    );
    await DatabaseService.instance.updateDebtWithCreatedAt(updated);
    await load();
  }

  Future<void> updateDebtCreatedAtAndInitialAmount({
    required Debt debt,
    required DateTime createdAt,
    required double initialAmount,
    required double alreadyPaid,
  }) async {
    final newRemain = (initialAmount - alreadyPaid).clamp(0, double.infinity).toDouble();
    final updated = Debt(
      id: debt.id,
      createdAt: createdAt,
      type: debt.type,
      partyId: debt.partyId,
      partyName: debt.partyName,
      amount: newRemain,
      description: debt.description,
      dueDate: debt.dueDate,
      settled: newRemain <= 0,
      sourceType: debt.sourceType,
      sourceId: debt.sourceId,
    );
    await DatabaseService.instance.updateDebtWithCreatedAt(updated);
    await load();
  }

  Future<void> updatePayment({
    required int paymentId,
    required String debtId,
    required double amount,
    required DateTime createdAt,
    String? note,
  }) async {
    await DatabaseService.instance.updateDebtPaymentWithAdjustment(
      paymentId: paymentId,
      debtId: debtId,
      newAmount: amount,
      newCreatedAt: createdAt,
      newNote: note,
    );
    await load();
  }

  Future<void> add(Debt d) async {
    _debts.add(d);
    notifyListeners();
    await DatabaseService.instance.insertDebt(d);
  }

  Future<void> update(Debt d) async {
    final idx = _debts.indexWhere((e) => e.id == d.id);
    if (idx != -1) {
      _debts[idx] = d;
      notifyListeners();
      await DatabaseService.instance.updateDebt(d);
    }
  }

  // Record a partial payment for a debt, reduce remaining amount, settle if zero
  Future<void> addPayment({required Debt debt, required double amount, String? note, String? paymentType}) async {
    if (amount <= 0) return;
    await DatabaseService.instance.insertDebtPayment(
      debtId: debt.id,
      amount: amount,
      note: note,
      paymentType: paymentType,
    );
    debt.amount = (debt.amount - amount).clamp(0, double.infinity);
    if (debt.amount == 0) {
      debt.settled = true;
    }
    await DatabaseService.instance.updateDebt(debt);
    final idx = _debts.indexWhere((e) => e.id == debt.id);
    if (idx != -1) {
      _debts[idx] = debt;
      notifyListeners();
    }
  }

  Future<List<Map<String, dynamic>>> paymentsFor(String debtId) async {
    return DatabaseService.instance.getDebtPayments(debtId);
  }

  Future<void> deletePayment({required int paymentId, required String debtId}) async {
    // Fetch payment to know amount and note/time
    final payment = await DatabaseService.instance.getDebtPaymentById(paymentId);
    if (payment != null) {
      // Cache for undo
      _lastDeletedPayment = {
        'debtId': debtId,
        'amount': (payment['amount'] as num).toDouble(),
        'note': payment['note'] as String?,
        'createdAt': payment['createdAt'] as String,
      };
      // Delete payment row
      await DatabaseService.instance.deleteDebtPayment(paymentId);
      // Increase remaining amount on debt (reverse the payment)
      final idx = _debts.indexWhere((d) => d.id == debtId);
      if (idx != -1) {
        final d = _debts[idx];
        d.amount += (payment['amount'] as num).toDouble();
        d.settled = d.amount == 0 ? d.settled : false;
        await DatabaseService.instance.updateDebt(d);
        _debts[idx] = d;
      }
      notifyListeners();
    }
  }

  Future<bool> deleteDebt(String debtId) async {
    // Cache for undo
    final idx = _debts.indexWhere((d) => d.id == debtId);
    if (idx != -1) {
      _lastDeletedDebt = _debts[idx];
      _lastDeletedDebtPayments = await DatabaseService.instance.getDebtPayments(debtId);

      final srcType = (_lastDeletedDebt?.sourceType ?? '').trim();
      final srcId = (_lastDeletedDebt?.sourceId ?? '').trim();
      if (srcType == 'sale' && srcId.isNotEmpty) {
        final saleTotals = await DatabaseService.instance.getSaleTotals(srcId);
        if (saleTotals != null) {
          final total = saleTotals['total'] ?? 0.0;
          final paidAmount = saleTotals['paidAmount'] ?? 0.0;
          final remain = (total - paidAmount).clamp(0.0, double.infinity).toDouble();
          if (remain > 0) {
            return false;
          }
        }
      }

      await DatabaseService.instance.deleteDebt(debtId);
      _debts.removeAt(idx);
      notifyListeners();
    }

    return true;
  }

  Future<bool> undoLastPaymentDeletion() async {
    final data = _lastDeletedPayment;
    if (data == null) return false;
    final debtId = data['debtId'] as String;
    final amount = (data['amount'] as num).toDouble();
    final note = data['note'] as String?;
    final createdAt = DateTime.parse(data['createdAt'] as String);
    // Reinsert payment
    await DatabaseService.instance.insertDebtPayment(debtId: debtId, amount: amount, note: note, createdAt: createdAt);
    // Reduce debt again
    final idx = _debts.indexWhere((d) => d.id == debtId);
    if (idx != -1) {
      final d = _debts[idx];
      d.amount = (d.amount - amount).clamp(0, double.infinity);
      if (d.amount == 0) d.settled = true;
      await DatabaseService.instance.updateDebt(d);
      _debts[idx] = d;
    }
    _lastDeletedPayment = null;
    notifyListeners();
    return true;
  }

  Future<bool> undoLastDebtDeletion() async {
    final debt = _lastDeletedDebt;
    if (debt == null) return false;
    // Reinsert debt
    await DatabaseService.instance.insertDebt(debt);
    // Reinsert payments
    for (final p in _lastDeletedDebtPayments) {
      await DatabaseService.instance.insertDebtPayment(
        debtId: debt.id,
        amount: (p['amount'] as num).toDouble(),
        note: p['note'] as String?,
        createdAt: DateTime.parse(p['createdAt'] as String),
      );
    }
    _debts.add(debt);
    _lastDeletedDebt = null;
    _lastDeletedDebtPayments = const [];
    notifyListeners();
    return true;
  }

  double get totalOweOthers => _debts
      .where((d) => d.type == DebtType.oweOthers && !d.settled)
      .fold(0, (p, e) => p + e.amount);

  double get totalOthersOweMe => _debts
      .where((d) => d.type == DebtType.othersOweMe && !d.settled)
      .fold(0, (p, e) => p + e.amount);
}
