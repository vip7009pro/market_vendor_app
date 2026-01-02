import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/debt.dart';
import '../providers/debt_provider.dart';
import '../providers/product_provider.dart';
import '../services/database_service.dart';
import 'purchase_order_create_screen.dart';
import 'purchase_order_detail_screen.dart';

class PurchaseOrderListScreen extends StatefulWidget {
  const PurchaseOrderListScreen({super.key});

  @override
  State<PurchaseOrderListScreen> createState() => _PurchaseOrderListScreenState();
}

class _PurchaseOrderListScreenState extends State<PurchaseOrderListScreen> {
  String _query = '';
  DateTimeRange? _range;
  int _reloadTick = 0;

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() => _reloadTick++);
  }

  @override
  Widget build(BuildContext context) {
    final fmtDate = DateFormat('dd/MM/yyyy HH:mm');
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Đơn nhập'),
        actions: [
          IconButton(
            tooltip: 'Chọn khoảng ngày',
            icon: const Icon(Icons.filter_list),
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(now.year - 3),
                lastDate: DateTime(now.year + 1),
                initialDateRange: _range,
              );
              if (picked == null) return;
              if (!mounted) return;
              setState(() => _range = picked);
              await _reload();
            },
          ),
          if (_range != null)
            IconButton(
              tooltip: 'Xoá lọc ngày',
              icon: const Icon(Icons.clear),
              onPressed: () async {
                setState(() => _range = null);
                await _reload();
              },
            ),
          IconButton(
            tooltip: 'Tạo đơn',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PurchaseOrderCreateScreen()),
              );
              await _reload();
            },
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Tìm theo NCC / SĐT / ghi chú',
                isDense: true,
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          if (_range != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Đang lọc: ${DateFormat('dd/MM/yyyy').format(_range!.start)} - ${DateFormat('dd/MM/yyyy').format(_range!.end)}',
                  style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              key: ValueKey(_reloadTick),
              future: DatabaseService.instance.getPurchaseOrders(range: _range, query: _query),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snap.data ?? const [];
                if (rows.isEmpty) {
                  return const Center(child: Text('Chưa có đơn nhập'));
                }

                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    final id = (r['id'] as String?) ?? '';
                    final createdAt = DateTime.tryParse(r['createdAt'] as String? ?? '') ?? DateTime.now();
                    final supplierName = (r['supplierName'] as String?)?.trim();
                    final supplierPhone = (r['supplierPhone'] as String?)?.trim();
                    final docUploaded = (r['purchaseDocUploaded'] as int?) == 1;

                    return FutureBuilder<Map<String, double>?>(
                      future: DatabaseService.instance.getPurchaseOrderTotals(id),
                      builder: (context, ts) {
                        final t = ts.data;
                        final total = t == null ? null : (t['total'] ?? 0);

                        return FutureBuilder<Debt?>(
                          future: DatabaseService.instance.getDebtBySource(sourceType: 'purchase', sourceId: id),
                          builder: (context, ds) {
                            final d = ds.data;
                            final remain = d == null ? 0.0 : (d.amount);
                            final settled = d == null || d.settled || remain <= 0;

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.green.withValues(alpha: 0.12),
                                child: Icon(
                                  docUploaded ? Icons.receipt_long : Icons.receipt_long_outlined,
                                  color: docUploaded ? Colors.green : Colors.black54,
                                ),
                              ),
                              title: Text(
                                supplierName == null || supplierName.isEmpty ? 'Đơn nhập' : 'NCC: $supplierName',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(fmtDate.format(createdAt), style: const TextStyle(color: Colors.black54)),
                                  if (supplierPhone != null && supplierPhone.isNotEmpty) Text('SĐT: $supplierPhone'),
                                  if (total != null)
                                    Text(
                                      'Tổng: ${currency.format(total)}',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  Text(
                                    settled ? 'Đã tất toán' : 'Còn nợ: ${currency.format(remain)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: settled ? Colors.green : Colors.redAccent,
                                    ),
                                  ),
                                ],
                              ),
                              onTap: id.isEmpty
                                  ? null
                                  : () async {
                                      final changed = await Navigator.push<bool>(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PurchaseOrderDetailScreen(purchaseOrderId: id),
                                        ),
                                      );

                                      if (changed == true) {
                                        await context.read<ProductProvider>().load();
                                        await context.read<DebtProvider>().load();
                                      }
                                      await _reload();
                                    },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
