import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import '../providers/debt_provider.dart';
import '../models/debt.dart';

class DebtHistoryScreen extends StatefulWidget {
  const DebtHistoryScreen({super.key});

  @override
  State<DebtHistoryScreen> createState() => _DebtHistoryScreenState();
}

class _DebtHistoryScreenState extends State<DebtHistoryScreen> {
  DebtType? _filterType; // null = all
  bool _onlyUnsettled = true;
  DateTimeRange? _range;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DebtProvider>();
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    var debts = provider.debts;

    if (_filterType != null) {
      debts = debts.where((d) => d.type == _filterType).toList();
    }
    if (_onlyUnsettled) {
      debts = debts.where((d) => !d.settled).toList();
    }
    if (_range != null) {
      final start = DateTime(_range!.start.year, _range!.start.month, _range!.start.day);
      final end = DateTime(_range!.end.year, _range!.end.month, _range!.end.day, 23, 59, 59, 999);
      debts = debts.where((d) => d.createdAt.isAfter(start.subtract(const Duration(milliseconds: 1))) && d.createdAt.isBefore(end.add(const Duration(milliseconds: 1)))).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      debts = debts.where((d) => d.partyName.toLowerCase().contains(q) || (d.description ?? '').toLowerCase().contains(q)).toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử công nợ'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (val) {
              setState(() {
                if (val == 'all') _filterType = null;
                if (val == 'othersOweMe') _filterType = DebtType.othersOweMe;
                if (val == 'oweOthers') _filterType = DebtType.oweOthers;
              });
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'all', child: Text('Tất cả')),
              PopupMenuItem(value: 'othersOweMe', child: Text('Tiền nợ tôi')),
              PopupMenuItem(value: 'oweOthers', child: Text('Tiền tôi nợ')),
            ],
          ),
          IconButton(
            tooltip: 'Xuất CSV',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () => _exportCsv(context, debts),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(hintText: 'Tìm theo tên/ghi chú', isDense: true, prefixIcon: Icon(Icons.search)),
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.date_range),
                  label: Text(_range == null ? 'Khoảng ngày' : '${DateFormat('dd/MM').format(_range!.start)} - ${DateFormat('dd/MM').format(_range!.end)}'),
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(now.year - 5),
                      lastDate: DateTime(now.year + 1),
                      initialDateRange: _range,
                    );
                    if (picked != null) setState(() => _range = picked);
                  },
                ),
                if (_range != null)
                  IconButton(
                    tooltip: 'Xoá lọc ngày',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _range = null),
                  )
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('Chỉ hiển thị chưa thanh toán'),
            value: _onlyUnsettled,
            onChanged: (v) => setState(() => _onlyUnsettled = v),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: debts.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final d = debts[i];
                return ListTile(
                  leading: Icon(d.type == DebtType.othersOweMe ? Icons.call_received : Icons.call_made),
                  title: Text(d.partyName),
                  subtitle: Text(d.description ?? ''),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(currency.format(d.amount), style: TextStyle(color: d.type == DebtType.othersOweMe ? Colors.red : Colors.amber, fontWeight: FontWeight.bold)),
                      if (d.settled) const Text('Đã thanh toán', style: TextStyle(color: Colors.green)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCsv(BuildContext context, List<Debt> debts) async {
    // Request storage permission for writing to Downloads
    final status = await Permission.storage.request();
    if (!status.isGranted) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không có quyền lưu tệp. Vui lòng cấp quyền lưu trữ.')));
      return;
    }
    final buffer = StringBuffer();
    buffer.writeln('id,type,partyId,partyName,amount,settled,createdAt,description');
    for (final d in debts) {
      final typeStr = d.type == DebtType.othersOweMe ? 'othersOweMe' : 'oweOthers';
      final desc = (d.description ?? '').replaceAll('\n', ' ').replaceAll(',', ' ');
      buffer.writeln('${d.id},$typeStr,${d.partyId},${d.partyName},${d.amount},${d.settled},${d.createdAt.toIso8601String()},$desc');
    }
    final fileName = 'debt_export_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
    Directory? dir;
    try {
      final candidates = await getExternalStorageDirectories(type: StorageDirectory.downloads);
      if (candidates != null && candidates.isNotEmpty) {
        dir = candidates.first;
      }
    } catch (_) {}
    dir ??= await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(buffer.toString());
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã xuất CSV: ${file.path}')));
  }
}
