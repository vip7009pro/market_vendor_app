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
  bool _loading = true;
  final GlobalKey _captureKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _debt = widget.debt;
    _load();
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
    if (!mounted) return;
    setState(() {
      _payments = data;
      _loading = false;
    });
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
      await context.read<DebtProvider>().addPayment(debt: _debt, amount: amount, note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim());
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
      await context.read<DebtProvider>().addPayment(debt: _debt, amount: remain, note: 'Tất toán');
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
        title: const Text('Chi tiết công nợ'),
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
          IconButton(
            tooltip: 'Chia sẻ',
            icon: const Icon(Icons.share_outlined),
            onPressed: _sharePng,
          ),
          PopupMenuButton<String>(
            onSelected: (val) async {
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
                  await context.read<DebtProvider>().deleteDebt(_debt.id);
                  if (!mounted) return;
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
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'delete', child: Text('Xóa công nợ')),
            ],
          ),
        ],
      ),
      body: RepaintBoundary(
        key: _captureKey,
        child: Material(
          color: theme.scaffoldBackgroundColor,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
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
                        if ((_debt.description ?? '').isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(_debt.description!, style: theme.textTheme.bodyMedium),
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
                const SizedBox(height: 4),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _payments.isEmpty
                            ? const Center(child: Text('Chưa có lịch sử', style: TextStyle(color: Colors.grey)))
                            : ListView.builder(
                                itemCount: _payments.length,
                                itemBuilder: (_, i) {
                                  final m = _payments[i];
                                  final createdAt = DateTime.parse(m['createdAt'] as String);
                                  final note = (m['note'] as String?) ?? '';
                                  final amount = (m['amount'] as num).toDouble();
                                  final id = m['id'] as int;
                                  return ListTile(
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    title: Text(DateFormat('dd/MM/yyyy HH:mm').format(createdAt), style: theme.textTheme.bodyMedium),
                                    subtitle: note.isEmpty ? null : Text(note, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
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
                                  );
                                },
                              ),
                  ),
                ),
              ],
            ),
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