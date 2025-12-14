import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/sale.dart';
import '../providers/sale_provider.dart';

String _vn(String s) {
  const groups = <String, String>{
    'a': 'àáạảãâầấậẩẫăằắặẳẵ',
    'A': 'ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴ',
    'e': 'èéẹẻẽêềếệểễ',
    'E': 'ÈÉẸẺẼÊỀẾỆỂỄ',
    'i': 'ìíịỉĩ',
    'I': 'ÌÍỊỈĨ',
    'o': 'òóọỏõôồốộổỗơờớợởỡ',
    'O': 'ÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠ',
    'u': 'ùúụủũưừứựửữ',
    'U': 'ÙÚỤỦŨƯỪỨỰỬỮ',
    'y': 'ỳýỵỷỹ',
    'Y': 'ỲÝỴỶỸ',
    'd': 'đ',
    'D': 'Đ',
  };
  groups.forEach((base, chars) {
    for (final ch in chars.split('')) {
      s = s.replaceAll(ch, base);
    }
  });
  return s;
}

class SaleItemHistoryRow {
  final Sale sale;
  final SaleItem item;

  const SaleItemHistoryRow({
    required this.sale,
    required this.item,
  });

  String get customerName {
    final raw = sale.customerName?.trim();
    return raw != null && raw.isNotEmpty ? raw : 'Khách lẻ';
  }

  double get lineTotal => item.unitPrice * item.quantity;
}

class SalesItemHistoryScreen extends StatefulWidget {
  const SalesItemHistoryScreen({super.key});

  @override
  State<SalesItemHistoryScreen> createState() => _SalesItemHistoryScreenState();
}

class _SalesItemHistoryScreenState extends State<SalesItemHistoryScreen> {
  DateTimeRange? _range;
  String _productQuery = '';
  String _customerQuery = '';

  @override
  Widget build(BuildContext context) {
    final sales = context.watch<SaleProvider>().sales;
    final fmtDate = DateFormat('dd/MM/yyyy HH:mm');
    final currency =
        NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);

    List<Sale> filteredSales = sales;
    if (_range != null) {
      final start =
          DateTime(_range!.start.year, _range!.start.month, _range!.start.day);
      final end = DateTime(
          _range!.end.year, _range!.end.month, _range!.end.day, 23, 59, 59, 999);
      filteredSales = filteredSales
          .where((s) =>
              s.createdAt
                  .isAfter(start.subtract(const Duration(milliseconds: 1))) &&
              s.createdAt
                  .isBefore(end.add(const Duration(milliseconds: 1))))
          .toList();
    }

    var rows = <SaleItemHistoryRow>[];
    for (final s in filteredSales) {
      for (final it in s.items) {
        rows.add(SaleItemHistoryRow(sale: s, item: it));
      }
    }

    if (_productQuery.isNotEmpty) {
      final q = _vn(_productQuery).toLowerCase();
      rows = rows
          .where((r) => _vn(r.item.name).toLowerCase().contains(q))
          .toList();
    }

    if (_customerQuery.isNotEmpty) {
      final q = _vn(_customerQuery).toLowerCase();
      rows = rows
          .where((r) => _vn(r.customerName).toLowerCase().contains(q))
          .toList();
    }

    rows.sort((a, b) => b.sale.createdAt.compareTo(a.sale.createdAt));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bán hàng chi tiết'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(now.year - 2),
                lastDate: DateTime(now.year + 1),
                initialDateRange: _range,
              );
              if (picked != null) setState(() => _range = picked);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Tìm theo tên mặt hàng',
                    isDense: true,
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _productQuery = v.trim()),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Lọc theo khách hàng',
                          isDense: true,
                          prefixIcon: Icon(Icons.person_search),
                        ),
                        onChanged: (v) =>
                            setState(() => _customerQuery = v.trim()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.date_range),
                      label: Text(
                        _range == null
                            ? 'Khoảng ngày'
                            : '${DateFormat('dd/MM').format(_range!.start)} - ${DateFormat('dd/MM').format(_range!.end)}',
                      ),
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(now.year - 2),
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
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('Không có dữ liệu'))
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 1),
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            vertical: 4, horizontal: 8),
                        elevation: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    margin: const EdgeInsets.only(right: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withValues(alpha: 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.shopping_bag_outlined,
                                      color: Colors.orange,
                                      size: 20,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      r.item.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    currency.format(r.lineTotal),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${r.customerName} • ${fmtDate.format(r.sale.createdAt)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'SL: ${r.item.quantity} ${r.item.unit}',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  Text(
                                    '${currency.format(r.item.unitPrice)} x ${r.item.quantity}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
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
    );
  }
}
