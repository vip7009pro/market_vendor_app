import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/sale_provider.dart';
import '../models/sale.dart';
import '../services/database_service.dart';
import '../utils/file_helper.dart';
// Import file mới
import 'receipt_preview_screen.dart'; // Thêm dòng này

import 'sales_item_history_screen.dart';
import 'sale_edit_screen.dart';

// Vietnamese diacritics removal (accent-insensitive search)
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

// --- MÀN HÌNH CHÍNH: SalesHistoryScreen ---

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  DateTimeRange? _range;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final sales = context.watch<SaleProvider>().sales;
    final fmtDate = DateFormat('dd/MM/yyyy HH:mm');
    final currency =
        NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);

    var filtered = sales;
    if (_range != null) {
      final start =
          DateTime(_range!.start.year, _range!.start.month, _range!.start.day);
      final end = DateTime(
          _range!.end.year, _range!.end.month, _range!.end.day, 23, 59, 59, 999);
      filtered = filtered
          .where((s) =>
              s.createdAt.isAfter(start.subtract(const Duration(milliseconds: 1))) &&
              s.createdAt.isBefore(end.add(const Duration(milliseconds: 1))))
          .toList();
    }
    if (_query.isNotEmpty) {
      final q = _vn(_query).toLowerCase();
      filtered = filtered.where((s) {
        final rawCustomer = s.customerName?.trim();
        final customer = _vn((rawCustomer != null && rawCustomer.isNotEmpty) ? rawCustomer : 'Khách lẻ').toLowerCase();
        final items = _vn(s.items.map((e) => e.name).join(', ')).toLowerCase();
        return customer.contains(q) || items.contains(q);
      }).toList();
    }

    // Tạo bản sao và sắp xếp theo createdAt giảm dần (mới nhất lên đầu)
    final List<Sale> sortedFiltered = List.from(filtered)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử bán hàng'),
        actions: [
          IconButton(
            tooltip: 'Bán hàng chi tiết',
            icon: const Icon(Icons.view_list),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SalesItemHistoryScreen(),
                ),
              );
            },
          ),
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
          PopupMenuButton<String>(
            onSelected: (val) async {
              if (val == 'delete_all') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Xóa tất cả lịch sử'),
                    content: const Text(
                        'Bạn có chắc muốn xóa tất cả lịch sử bán hàng?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Hủy')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Xóa')),
                    ],
                  ),
                );
                if (ok == true) {
                  final messenger = ScaffoldMessenger.of(context);
                  await context.read<SaleProvider>().deleteAll();
                  messenger.showSnackBar(
                    SnackBar(
                      content: const Text('Đã xóa tất cả lịch sử'),
                      action: SnackBarAction(
                        label: 'Hoàn tác',
                        onPressed: () async {
                          final ok =
                              await context.read<SaleProvider>().undoDeleteAll();
                          if (ok) {
                            messenger.showSnackBar(
                                const SnackBar(content: Text('Đã khôi phục')));
                          }
                        },
                      ),
                    ),
                  );
                }
              } else if (val == 'export_csv') {
                await _exportCsv(context, sortedFiltered); // Sử dụng sortedFiltered
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'delete_all', child: Text('Xóa tất cả')),
              PopupMenuItem(value: 'export_csv', child: Text('Xuất CSV')),
            ],
          )
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
                    decoration: const InputDecoration(
                      hintText: 'Tìm theo khách hàng / mặt hàng',
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => _query = v.trim()),
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
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: sortedFiltered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 1),
              itemBuilder: (context, i) {
                final s = sortedFiltered[i];
                final customer = s.customerName?.trim().isEmpty == false
                    ? s.customerName!.trim()
                    : 'Khách lẻ';
                return Card(
                  margin:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  elevation: 1,
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _SaleDetailScreen(sale: s),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header row with customer and total
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  customer,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: s.debt > 0
                                      ? Colors.red.withOpacity(0.1)
                                      : Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  currency.format(s.total),
                                  style: TextStyle(
                                    color:
                                        s.debt > 0 ? Colors.red : Colors.green,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          // Date and time
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              fmtDate.format(s.createdAt),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),

                          // Items list
                          const SizedBox(height: 8),
                          ...s.items
                              .map((item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          margin:
                                              const EdgeInsets.only(right: 8),
                                          decoration: const BoxDecoration(
                                            color: Colors.blue,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        if (((item.itemType ?? '').toUpperCase().trim()) == 'MIX')
                                          Padding(
                                            padding: const EdgeInsets.only(right: 6),
                                            child: Icon(
                                              Icons.blender,
                                              size: 16,
                                              color: Colors.deepPurple[400],
                                            ),
                                          )
                                        else
                                          Padding(
                                            padding: const EdgeInsets.only(right: 6),
                                            child: Icon(
                                              Icons.inventory_2_outlined,
                                              size: 16,
                                              color: Colors.blueGrey[400],
                                            ),
                                          ),
                                        Expanded(
                                          child: Text(
                                            '${(((item.itemType ?? '').toUpperCase().trim()) == 'MIX' && (item.displayName?.trim().isNotEmpty == true)) ? item.displayName!.trim() : item.name} x ${item.quantity} ${item.unit}',
                                            style: const TextStyle(fontSize: 13),
                                          ),
                                        ),
                                        Text(
                                          '${currency.format(item.unitPrice)} x ${item.quantity} = ${currency.format(item.unitPrice * item.quantity)}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ))
                              .toList(),

                          // Payment status and actions
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (s.discount > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Giảm: ${currency.format(s.discount)}',
                                    style: const TextStyle(
                                      color: Colors.deepOrange,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                )
                              else
                              if (s.debt > 0)
                                FutureBuilder(
                                  future: DatabaseService.instance.getDebtBySource(
                                    sourceType: 'sale',
                                    sourceId: s.id,
                                  ),
                                  builder: (context, snap) {
                                    final d = snap.data;
                                    if (snap.connectionState != ConnectionState.done || d == null) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.red.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'Còn nợ: ${currency.format(s.debt)}',
                                          style: const TextStyle(
                                            color: Colors.red,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      );
                                    }

                                    return FutureBuilder<double>(
                                      future: DatabaseService.instance.getTotalPaidForDebt(d.id),
                                      builder: (context, paidSnap) {
                                        final paid = paidSnap.data ?? 0;
                                        final remain = d.amount;
                                        final settled = d.settled || remain <= 0;
                                        final bg = settled ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1);
                                        final fg = settled ? Colors.green : Colors.red;
                                        final text = settled
                                            ? 'Đã tất toán'
                                            : 'Đã trả: ${currency.format(paid)} | Còn: ${currency.format(remain)}';

                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: bg,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            text,
                                            style: TextStyle(
                                              color: fg,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Đã thanh toán',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),

                              // New Print Button & Delete Button
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.print_outlined,
                                        color: Colors.blueAccent, size: 20),
                                    tooltip: 'In hóa đơn',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => _showPrintPreview(
                                        context, s, currency), // Gọi hàm hiển thị preview
                                  ),
                                  const SizedBox(width: 8),
                                  // Delete button
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.redAccent, size: 20),
                                    tooltip: 'Xóa hóa đơn',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () async {
                                      final ok = await showDialog<bool>(
                                        context: context,
                                        builder: (_) => AlertDialog(
                                          title: const Text('Xóa hóa đơn'),
                                          content: const Text(
                                              'Bạn có chắc muốn xóa hóa đơn này?'),
                                          actions: [
                                            TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(
                                                        context, false),
                                                child: const Text('Hủy')),
                                            FilledButton(
                                                onPressed: () =>
                                                    Navigator.pop(context, true),
                                                child: const Text('Xóa')),
                                          ],
                                        ),
                                      );
                                      if (ok == true) {
                                        await context
                                            .read<SaleProvider>()
                                            .delete(s.id);
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text('Đã xóa hóa đơn')),
                                        );
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  // Edit button
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined,
                                        color: Colors.blueAccent, size: 20),
                                    tooltip: 'Sửa hóa đơn',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () async {
                                      final ok = await Navigator.push<bool>(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => SaleEditScreen(
                                            sale: s,
                                          ),
                                        ),
                                      );
                                      if (ok == true) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text('Đã cập nhật bán hàng')),
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
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

  // Hàm hiển thị màn hình preview và in (Cập nhật: Thay showDialog bằng Navigator.push)
  Future<void> _showPrintPreview(
      BuildContext context, Sale sale, NumberFormat currency) async {
    // Chuyển sang màn hình riêng thay vì dialog
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReceiptPreviewScreen(sale: sale, currency: currency),
      ),
    );
  }

  Future<void> _exportCsv(BuildContext context, List<Sale> sales) async {
    if (!context.mounted) return;

    // Tạo nội dung CSV
    final buffer = StringBuffer();
    buffer.writeln(
        'id,createdAt,customerId,customerName,subtotal,discount,paid,total,debt,items');
    for (final s in sales) {
      final items = s.items
          .map((e) => '${e.name} x ${e.quantity} @ ${e.unitPrice}')
          .join('; ');
      buffer.writeln(
          '${s.id},${s.createdAt.toIso8601String()},${s.customerId ?? ''},${s.customerName ?? ''},${s.subtotal},${s.discount},${s.paidAmount},${s.total},${s.debt},"${items.replaceAll('"', '""')}"');
    }

    // Sử dụng helper để xuất file
    await FileHelper.exportCsv(
      context: context,
      csvContent: buffer.toString(),
      fileName: 'sales_export',
      openAfterExport: false,
    );
  }
}

class _SaleDetailScreen extends StatefulWidget {
  const _SaleDetailScreen({required this.sale});

  final Sale sale;

  @override
  State<_SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<_SaleDetailScreen> {
  late Sale _sale;

  List<Map<String, dynamic>> _decodeMixItems(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(s);

      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  @override
  void initState() {
    super.initState();
    _sale = widget.sale;
  }

  Future<void> _editSale() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SaleEditScreen(sale: widget.sale),
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      await context.read<SaleProvider>().load();
      if (!mounted) return;
      Sale? updated;
      try {
        updated = context.read<SaleProvider>().sales.firstWhere(
              (s) => s.id == widget.sale.id,
            );
      } catch (_) {
        updated = null;
      }
      setState(() {
        _sale = updated ?? _sale;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Đã cập nhật bán hàng')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sale = _sale;
    final fmtDate = DateFormat('dd/MM/yyyy HH:mm');
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);

    final customer = sale.customerName?.trim().isNotEmpty == true ? sale.customerName!.trim() : 'Khách lẻ';

    final paidAll = sale.debt <= 0;
    final statusBg = paidAll ? Colors.green.withOpacity(0.12) : Colors.red.withOpacity(0.12);
    final statusFg = paidAll ? Colors.green : Colors.red;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết bán hàng'),
        actions: [
          IconButton(
            tooltip: 'Sửa',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _editSale,
          ),
          IconButton(
            tooltip: 'In hóa đơn',
            icon: const Icon(Icons.print_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReceiptPreviewScreen(
                    sale: sale,
                    currency: currency,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          customer,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: statusBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          paidAll ? 'Đã thanh toán' : 'Còn nợ',
                          style: TextStyle(color: statusFg, fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    fmtDate.format(sale.createdAt),
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  const Divider(height: 16),
                  Row(
                    children: [
                      Expanded(child: Text('Tạm tính', style: TextStyle(color: Colors.grey[700]))),
                      Text(currency.format(sale.subtotal), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: Text('Giảm', style: TextStyle(color: Colors.grey[700]))),
                      Text(currency.format(sale.discount), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: Text('Khách trả', style: TextStyle(color: Colors.grey[700]))),
                      Text(currency.format(sale.paidAmount), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: Text('Còn nợ', style: TextStyle(color: Colors.grey[700]))),
                      Text(currency.format(sale.debt), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Tổng cộng', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                      Text(currency.format(sale.total), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              'Danh sách hàng (${sale.items.length})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ...sale.items.map((it) {
            final t = (it.itemType ?? '').toUpperCase().trim();
            final isMix = t == 'MIX';
            final title = (isMix && it.displayName?.trim().isNotEmpty == true)
                ? it.displayName!.trim()
                : it.name;
            final mixItems = isMix ? _decodeMixItems(it.mixItemsJson) : const <Map<String, dynamic>>[];

            final leading = isMix
                ? Icon(Icons.blender, color: Colors.deepPurple[400])
                : Icon(Icons.inventory_2_outlined, color: Colors.blueGrey[400]);

            if (!isMix) {
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: leading,
                  title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${it.quantity} ${it.unit} × ${currency.format(it.unitPrice)}'),
                  trailing: Text(currency.format(it.total), style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              );
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ExpansionTile(
                leading: leading,
                title: Row(
                  children: [
                    Expanded(
                      child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Text(currency.format(it.total), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                subtitle: Text('${it.quantity} ${it.unit} × ${currency.format(it.unitPrice)}'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  if (mixItems.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Không có nguyên liệu'),
                    )
                  else
                    Column(
                      children: mixItems.map((m) {
                        final rawName = (m['rawName']?.toString() ?? '').trim();
                        final rawUnit = (m['rawUnit']?.toString() ?? '').trim();
                        final rawQty = (m['rawQty'] as num?)?.toDouble() ?? 0.0;
                        final rawUnitCost = (m['rawUnitCost'] as num?)?.toDouble() ?? 0.0;
                        final lineTotal = rawQty * rawUnitCost;
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  rawName.isEmpty ? 'Nguyên liệu' : rawName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${rawQty.toStringAsFixed(rawQty % 1 == 0 ? 0 : 2)} ${rawUnit.isEmpty ? '' : rawUnit}',
                                style: TextStyle(color: Colors.grey[700]),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                currency.format(rawUnitCost),
                                style: TextStyle(color: Colors.grey[700]),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                currency.format(lineTotal),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}