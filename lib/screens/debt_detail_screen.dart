import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';
import '../models/debt.dart';
import '../providers/debt_provider.dart';

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
    // Request storage permission to write to public Downloads
    final status = await Permission.storage.request();
    if (!status.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không có quyền lưu tệp. Vui lòng cấp quyền lưu trữ.')));
      return;
    }
    final buffer = StringBuffer();
    buffer.writeln('id,debtId,createdAt,amount,note');
    for (final m in _payments) {
      final note = (m['note'] as String? ?? '').replaceAll('\n', ' ').replaceAll('"', '""');
      buffer.writeln("${m['id']},${_debt.id},${m['createdAt']},${m['amount']},\"$note\"");
    }
    final fileName = 'debt_${_debt.id}_payments_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
    Directory? dir;
    try {
      final candidates = await getExternalStorageDirectories(type: StorageDirectory.downloads);
      if (candidates != null && candidates.isNotEmpty) {
        dir = candidates.first;
      }
    } catch (_) {}
    dir ??= await getApplicationDocumentsDirectory();
    final dirPath = dir.path;
    final file = File('$dirPath/$fileName');
    await file.writeAsString(buffer.toString());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã xuất CSV: ${file.path}'),
        action: SnackBarAction(
          label: 'Mở thư mục',
          onPressed: () => OpenFilex.open(dirPath),
        ),
      ),
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
      final raw = amountCtrl.text.replaceAll(',', '.');
      final amount = double.tryParse(raw) ?? 0;
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
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text('Tên: ${_debt.partyName}')),
                            Chip(label: Text(_debt.type == DebtType.othersOweMe ? 'Nợ tôi' : 'Tôi nợ')),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Số tiền còn lại: ${_currency.format(_debt.amount)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        if ((_debt.description ?? '').isNotEmpty) Text(_debt.description!),
                        const SizedBox(height: 4),
                        Text(_debt.settled ? 'Đã tất toán' : 'Chưa tất toán', style: TextStyle(color: _debt.settled ? Colors.green : Colors.orange)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: Text('Lịch sử thanh toán', style: Theme.of(context).textTheme.titleMedium)),
                    TextButton.icon(
                      onPressed: () => _exportPaymentsCsv(context),
                      icon: const Icon(Icons.file_download_outlined),
                      label: const Text('Xuất CSV'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _payments.isEmpty
                          ? const Center(child: Text('Chưa có lịch sử'))
                          : ListView.separated(
                              itemCount: _payments.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final m = _payments[i];
                                final createdAt = DateTime.parse(m['createdAt'] as String);
                                final note = (m['note'] as String?) ?? '';
                                final amount = (m['amount'] as num).toDouble();
                                final id = m['id'] as int;
                                return ListTile(
                                  title: Text('${DateFormat('dd/MM/yyyy HH:mm').format(createdAt)}'),
                                  subtitle: note.isEmpty ? null : Text(note),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(_currency.format(amount), style: const TextStyle(fontWeight: FontWeight.bold)),
                                      IconButton(
                                        tooltip: 'Xóa',
                                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
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
                                  )],
                                  ),
                                );
                              },
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
