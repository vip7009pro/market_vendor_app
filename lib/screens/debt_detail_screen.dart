import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:open_filex/open_filex.dart';
import '../models/debt.dart';
import '../providers/debt_provider.dart';
import '../services/database_service.dart';
import '../utils/file_helper.dart';
import '../utils/number_input_formatter.dart';

class DebtDetailScreen extends StatefulWidget {
  final Debt debt;
  const DebtDetailScreen({super.key, required this.debt});

  @override
  State<DebtDetailScreen> createState() => _DebtDetailScreenState();
}

class _DebtDetailScreenState extends State<DebtDetailScreen> {
  late Debt _debt;
  final _currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _sourceItems = [];
  bool _loadingSource = true;
  bool _loading = true;
  final GlobalKey _captureKey = GlobalKey();

  IconData _paymentTypeIcon(String? t) {
    final v = (t ?? '').trim().toLowerCase();
    if (v == 'cash') return Icons.payments_outlined;
    if (v == 'bank') return Icons.account_balance_outlined;
    return Icons.help_outline;
  }

  Color? _paymentTypeColor(BuildContext context, String? t) {
    final v = (t ?? '').trim().toLowerCase();
    if (v == 'cash') return Colors.green;
    if (v == 'bank') return Colors.blue;
    return Theme.of(context).colorScheme.onSurface.withOpacity(0.55);
  }

  String _paymentTypeLabel(String? t) {
    final v = (t ?? '').trim();
    if (v == 'cash') return 'Tiền mặt';
    if (v == 'bank') return 'Chuyển khoản';
    return 'Chưa phân loại';
  }

  Future<String?> _pickPaymentType({String? current}) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text('Tiền mặt'),
                onTap: () => Navigator.pop(ctx, 'cash'),
              ),
              ListTile(
                leading: const Icon(Icons.account_balance_outlined),
                title: const Text('Chuyển khoản'),
                onTap: () => Navigator.pop(ctx, 'bank'),
              ),
              ListTile(
                leading: const Icon(Icons.clear),
                title: const Text('Bỏ phân loại'),
                onTap: () => Navigator.pop(ctx, ''),
              ),
            ],
          ),
        );
      },
    );
    return picked;
  }

  Future<String?> _pickPaymentTypeRequired() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text('Tiền mặt'),
                onTap: () => Navigator.pop(ctx, 'cash'),
              ),
              ListTile(
                leading: const Icon(Icons.account_balance_outlined),
                title: const Text('Chuyển khoản'),
                onTap: () => Navigator.pop(ctx, 'bank'),
              ),
            ],
          ),
        );
      },
    );
    return picked;
  }

  Future<void> _setPaymentTypeForPayment(Map<String, dynamic> payment) async {
    final id = payment['id'] as int;
    final current = payment['paymentType'] as String?;
    final picked = await _pickPaymentType(current: current);
    if (picked == null) return;
    await DatabaseService.instance.updateDebtPaymentType(
      paymentId: id,
      paymentType: picked.trim().isEmpty ? null : picked.trim(),
    );
    await _load();
  }

  Future<void> _setPaymentTypeForAllPayments() async {
    final picked = await _pickPaymentType();
    if (picked == null) return;
    await DatabaseService.instance.updateAllDebtPaymentsPaymentType(
      debtId: _debt.id,
      paymentType: picked.trim().isEmpty ? null : picked.trim(),
    );
    await _load();
  }

  @override
  void initState() {
    super.initState();
    _debt = widget.debt;
    _load();
  }

  Future<void> _editDebtCreatedAt() async {
    DateTime createdAt = _debt.createdAt;
    final paid = _payments.fold<double>(0, (p, e) => p + ((e['amount'] as num).toDouble()));
    final initialNow = paid + _debt.amount;
    final initialCtrl = TextEditingController(text: initialNow.toStringAsFixed(0));
    Future<void> pickDateTime(StateSetter setStateDialog) async {
      final d = await showDatePicker(
        context: context,
        initialDate: createdAt,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (d == null) return;
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(createdAt),
      );
      if (t == null) return;
      createdAt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
      setStateDialog(() {});
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogCtx, setStateDialog) => AlertDialog(
          title: const Text('Sửa ngày giờ công nợ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat('dd/MM/yyyy HH:mm').format(createdAt),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: () => pickDateTime(setStateDialog),
                    child: const Text('Đổi'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: initialCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
                decoration: const InputDecoration(labelText: 'Nợ ban đầu'),
              ),
              const SizedBox(height: 6),
              Text(
                'Đã trả: ${_currency.format(paid)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Hủy')),
            FilledButton(onPressed: () => Navigator.pop(dialogCtx, true), child: const Text('Lưu')),
          ],
        ),
      ),
    );

    if (ok == true) {
      final initialAmount = NumberInputFormatter.tryParse(initialCtrl.text) ?? 0;
      if (initialAmount < 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nợ ban đầu không hợp lệ')));
        return;
      }

      await context.read<DebtProvider>().updateDebtCreatedAtAndInitialAmount(
            debt: _debt,
            createdAt: createdAt,
            initialAmount: initialAmount,
            alreadyPaid: paid,
          );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã cập nhật ngày giờ công nợ')));
    }
  }

  Future<void> _editPayment(Map<String, dynamic> m) async {
    final paymentId = m['id'] as int;
    DateTime createdAt = DateTime.parse(m['createdAt'] as String);
    final amountCtrl = TextEditingController(text: (m['amount'] as num).toDouble().toStringAsFixed(0));
    final noteCtrl = TextEditingController(text: (m['note'] as String?) ?? '');

    Future<void> pickDateTime(StateSetter setStateDialog) async {
      final d = await showDatePicker(
        context: context,
        initialDate: createdAt,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (d == null) return;
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(createdAt),
      );
      if (t == null) return;
      createdAt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
      setStateDialog(() {});
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogCtx, setStateDialog) => AlertDialog(
          title: const Text('Sửa thanh toán'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(DateFormat('dd/MM/yyyy HH:mm').format(createdAt))),
                  TextButton(onPressed: () => pickDateTime(setStateDialog), child: const Text('Đổi')),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
                decoration: const InputDecoration(labelText: 'Số tiền'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: 'Ghi chú (tuỳ chọn)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Hủy')),
            FilledButton(onPressed: () => Navigator.pop(dialogCtx, true), child: const Text('Lưu')),
          ],
        ),
      ),
    );

    if (ok == true) {
      final amount = NumberInputFormatter.tryParse(amountCtrl.text) ?? 0;
      if (amount <= 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Số tiền không hợp lệ')));
        return;
      }

      await context.read<DebtProvider>().updatePayment(
            paymentId: paymentId,
            debtId: _debt.id,
            amount: amount,
            createdAt: createdAt,
            note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
          );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã cập nhật thanh toán')));
    }
  }

  Future<void> _exportPaymentsCsv(BuildContext context) async {
    if (!mounted) return;
    
    // Tạo nội dung CSV
    final buffer = StringBuffer();
    buffer.writeln('id,debtId,createdAt,amount,note');
    for (final m in _payments) {
      final note = (m['note'] as String? ?? '').replaceAll('\n', ' ').replaceAll('"', '""');
      buffer.writeln("${m['id']},${_debt.id},${m['createdAt']},${m['amount']},\"$note\"");
    }
    
    // Sử dụng helper để xuất file
    await FileHelper.exportCsv(
      context: context,
      csvContent: buffer.toString(),
      fileName: 'debt_${_debt.id}_payments',
      openAfterExport: false,
    );
  }

  Future<void> _load() async {
    final data = await context.read<DebtProvider>().paymentsFor(_debt.id);
    final debtLatest = await context.read<DebtProvider>().getById(_debt.id);
    await _loadSource();
    if (!mounted) return;
    setState(() {
      _payments = data;
      if (debtLatest != null) {
        _debt = debtLatest;
      }
      _loading = false;
    });
  }

  Future<void> _loadSource() async {
    final sourceType = (_debt.sourceType ?? '').trim();
    final sourceId = (_debt.sourceId ?? '').trim();

    if (sourceType.isEmpty || sourceId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _sourceItems = [];
        _loadingSource = false;
      });
      return;
    }

    try {
      final db = DatabaseService.instance.db;

      if (sourceType == 'sale') {
        final items = await db.query('sale_items', where: 'saleId = ?', whereArgs: [sourceId]);
        if (!mounted) return;
        setState(() {
          _sourceItems = items;
          _loadingSource = false;
        });
        return;
      }

      if (sourceType == 'purchase') {
        final purchaseRows = await db.query('purchase_history', where: 'id = ?', whereArgs: [sourceId], limit: 1);
        final header = purchaseRows.isEmpty ? null : purchaseRows.first;
        if (!mounted) return;
        setState(() {
          _sourceItems = header == null ? [] : [header];
          _loadingSource = false;
        });
        return;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sourceItems = [];
        _loadingSource = false;
      });
    }

    if (!mounted) return;
    setState(() {
      _sourceItems = [];
      _loadingSource = false;
    });
  }

  String _sourceTypeLabel(String? t) {
    final v = (t ?? '').trim();
    if (v == 'sale') return 'Bán hàng';
    if (v == 'purchase') return 'Nhập hàng';
    return v;
  }

  Future<void> _showPayDialog() async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Trả nợ một phần'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Còn nợ: ${_currency.format(_debt.amount)}'),
            const SizedBox(height: 8),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
              decoration: const InputDecoration(labelText: 'Số tiền trả'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: 'Ghi chú (tuỳ chọn)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xác nhận')),
        ],
      ),
    );
    if (ok == true) {
      final amount = NumberInputFormatter.tryParse(amountCtrl.text) ?? 0;
      if (amount <= 0 || amount > _debt.amount) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Số tiền không hợp lệ')));
        return;
      }

      final paymentType = await _pickPaymentTypeRequired();
      if (paymentType == null) return;

      await context.read<DebtProvider>().addPayment(
            debt: _debt,
            amount: amount,
            note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
            paymentType: paymentType,
          );
      setState(() {}); // reflect new amount/settled
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã ghi nhận thanh toán')));
    }
  }

  Future<void> _settleAll() async {
    if (_debt.amount <= 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tất toán công nợ'),
        content: Text('Bạn có chắc muốn tất toán ${_currency.format(_debt.amount)} không?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xác nhận')),
        ],
      ),
    );
    if (ok == true) {
      final remain = _debt.amount;

      final paymentType = await _pickPaymentTypeRequired();
      if (paymentType == null) return;

      await context.read<DebtProvider>().addPayment(
            debt: _debt,
            amount: remain,
            note: 'Tất toán',
            paymentType: paymentType,
          );
      setState(() {});
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã tất toán')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remainingColor = _debt.amount > 0 ? Colors.red : Colors.green;
    final typeColor = _debt.type == DebtType.othersOweMe ? Colors.blue : Colors.redAccent;
    final paid = _payments.fold<double>(0, (p, e) => p + ((e['amount'] as num).toDouble()));
    final initial = paid + _debt.amount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết công nợ', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Trả nợ',
            icon: const Icon(Icons.payments_outlined),
            onPressed: _debt.amount <= 0 ? null : _showPayDialog,
          ),
          IconButton(
            tooltip: 'Tất toán',
            icon: const Icon(Icons.done_all),
            onPressed: _debt.amount <= 0 ? null : _settleAll,
          ),
          PopupMenuButton<String>(
            onSelected: (val) async {
              if (val == 'edit_created_at') {
                await _editDebtCreatedAt();
              }
              if (val == 'share') {
                await _sharePng();
              }
              if (val == 'set_payment_type_all') {
                await _setPaymentTypeForAllPayments();
              }
              if (val == 'delete') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Xóa công nợ'),
                    content: const Text('Bạn có chắc muốn xóa công nợ này? Mọi lịch sử thanh toán sẽ bị xóa.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa')),
                    ],
                  ),
                );
                if (ok == true) {
                  final messenger = ScaffoldMessenger.of(context);
                  final deleted = await context.read<DebtProvider>().deleteDebt(_debt.id);
                  if (!mounted) return;
                  if (!deleted) {
                    messenger.showSnackBar(const SnackBar(
                      content: Text('Không được xóa công nợ của hóa đơn còn nợ. Vui lòng trả/tất toán.'),
                    ));
                    return;
                  }
                  Navigator.of(context).pop();
                  messenger.showSnackBar(
                    SnackBar(
                      content: const Text('Đã xóa công nợ'),
                      action: SnackBarAction(
                        label: 'Hoàn tác',
                        onPressed: () async {
                          final ok = await context.read<DebtProvider>().undoLastDebtDeletion();
                          if (ok) {
                            messenger.showSnackBar(const SnackBar(content: Text('Đã khôi phục công nợ')));
                          }
                        },
                      ),
                    ),
                  );
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit_created_at', child: Text('Sửa ngày giờ')),
              PopupMenuItem(
                value: 'set_payment_type_all',
                enabled: _payments.isNotEmpty,
                child: const Text('Set kiểu thanh toán (tất cả)'),
              ),
              const PopupMenuItem(value: 'share', child: Text('Chia sẻ ảnh')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'delete', child: Text('Xóa công nợ')),
            ],
          ),
        ],
      ),
      body: RepaintBoundary(
        key: _captureKey,
        child: Material(
          color: theme.scaffoldBackgroundColor,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(12),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text('Tên: ${_debt.partyName}', style: theme.textTheme.titleMedium),
                                trailing: Chip(
                                  label: Text(_debt.type == DebtType.othersOweMe ? 'Nợ tôi' : 'Tôi nợ'),
                                  backgroundColor: typeColor.withOpacity(0.2),
                                  labelStyle: TextStyle(color: typeColor),
                                ),
                              ),
                              const Divider(height: 8),
                              Text(
                                'Số tiền còn lại: ${_currency.format(_debt.amount)}',
                                style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold, color: remainingColor),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Nợ ban đầu: ${_currency.format(initial)}',
                                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                              ),
                              if ((_debt.sourceId ?? '').trim().isNotEmpty || (_debt.sourceType ?? '').trim().isNotEmpty || (_debt.description ?? '').trim().isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.grey.withOpacity(0.18)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if ((_debt.sourceType ?? '').trim().isNotEmpty)
                                        Text(
                                          'Nguồn: ${_sourceTypeLabel(_debt.sourceType)}',
                                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                                        ),
                                      if ((_debt.sourceId ?? '').trim().isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Mã giao dịch: ${_debt.sourceId}',
                                          style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black87),
                                        ),
                                      ],
                                      if ((_debt.description ?? '').trim().isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          'Ghi chú:',
                                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(_debt.description!.trim(), style: theme.textTheme.bodyMedium),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                _debt.settled ? 'Đã tất toán' : 'Chưa tất toán',
                                style: theme.textTheme.bodyMedium?.copyWith(color: _debt.settled ? Colors.green : Colors.orange),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if ((_debt.sourceType ?? '').trim().isNotEmpty && (_debt.sourceId ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Card(
                          elevation: 1,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Chi tiết giao dịch', style: theme.textTheme.titleMedium),
                                const SizedBox(height: 8),
                                if (_loadingSource)
                                  const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
                                else if (_sourceItems.isEmpty)
                                  const Text('Không tìm thấy dữ liệu giao dịch', style: TextStyle(color: Colors.black54))
                                else if ((_debt.sourceType ?? '').trim() == 'sale')
                                  Column(
                                    children: _sourceItems.map((it) {
                                      final name = (it['name'] as String?) ?? '';
                                      final qty = (it['quantity'] as num?)?.toDouble() ?? 0;
                                      final unit = (it['unit'] as String?) ?? '';
                                      final unitPrice = (it['unitPrice'] as num?)?.toDouble() ?? 0;
                                      final lineTotal = unitPrice * qty;
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 6),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '${_currency.format(unitPrice)} × ${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2)} ${unit.isEmpty ? '' : unit}',
                                                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              _currency.format(lineTotal),
                                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  )
                                else
                                  Builder(
                                    builder: (_) {
                                      final it = _sourceItems.first;
                                      final name = (it['productName'] as String?) ?? '';
                                      final qty = (it['quantity'] as num?)?.toDouble() ?? 0;
                                      final unitCost = (it['unitCost'] as num?)?.toDouble() ?? 0;
                                      final totalCost = (it['totalCost'] as num?)?.toDouble() ?? (qty * unitCost);
                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Đơn giá nhập: ${_currency.format(unitCost)}',
                                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
                                          ),
                                          Text(
                                            'Số lượng: ${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2)}',
                                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            'Thành tiền: ${_currency.format(totalCost)}',
                                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Lịch sử thanh toán', style: theme.textTheme.titleMedium),
                          TextButton.icon(
                            onPressed: () => _exportPaymentsCsv(context),
                            icon: const Icon(Icons.file_download_outlined, size: 20),
                            label: const Text('Xuất CSV'),
                            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_payments.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('Chưa có lịch sử', style: TextStyle(color: Colors.grey))),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  sliver: SliverList.separated(
                    itemCount: _payments.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey[300]),
                    itemBuilder: (_, i) {
                      final m = _payments[i];
                      final createdAt = DateTime.parse(m['createdAt'] as String);
                      final note = (m['note'] as String?) ?? '';
                      final amount = (m['amount'] as num).toDouble();
                      final id = m['id'] as int;
                      final paymentType = m['paymentType'] as String?;
                      return Material(
                        color: Colors.transparent,
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),

                          leading: Icon(
                            _paymentTypeIcon(paymentType),
                            color: _paymentTypeColor(context, paymentType),
                          ),
                          title: Text(DateFormat('dd/MM/yyyy HH:mm').format(createdAt), style: theme.textTheme.bodyMedium),
                          subtitle: note.isEmpty
                              ? null
                              : Text(
                                  note,
                                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                                ),
                          onLongPress: () async {
                            await showModalBottomSheet<void>(
                              context: context,
                              showDragHandle: true,
                              builder: (ctx) {

                                return SafeArea(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ListTile(
                                        leading: const Icon(Icons.tune),
                                        title: const Text('Set kiểu thanh toán'),
                                        subtitle: Text(_paymentTypeLabel(paymentType)),
                                        onTap: () async {
                                          Navigator.pop(ctx);
                                          await _setPaymentTypeForPayment(m);
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Sửa',
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _editPayment(m),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _currency.format(amount),
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.green),
                              ),
                              IconButton(
                                tooltip: 'Xóa',
                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () async {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      title: const Text('Xóa thanh toán'),
                                      content: const Text('Bạn có chắc muốn xóa khoản thanh toán này?'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
                                        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa')),
                                      ],
                                    ),
                                  );
                                  if (ok == true) {
                                    final messenger = ScaffoldMessenger.of(context);
                                    await context.read<DebtProvider>().deletePayment(paymentId: id, debtId: _debt.id);
                                    await _load();
                                    if (!mounted) return;
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: const Text('Đã xóa thanh toán'),
                                        action: SnackBarAction(
                                          label: 'Hoàn tác',
                                          onPressed: () async {
                                            final ok = await context.read<DebtProvider>().undoLastPaymentDeletion();
                                            if (ok) {
                                              await _load();
                                              if (!mounted) return;
                                              messenger.showSnackBar(const SnackBar(content: Text('Đã khôi phục thanh toán')));
                                            }
                                          },
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sharePng() async {
    try {
      final boundary = _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/debt_${_debt.id}.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Công nợ: ${_debt.partyName}');
    } catch (_) {}
  }
}