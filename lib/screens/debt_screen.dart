import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/debt.dart';
import '../models/sale.dart';
import '../providers/debt_provider.dart';
import 'debt_form_screen.dart';
import 'debt_detail_screen.dart';
import 'package:intl/intl.dart';
import '../services/database_service.dart';

class DebtScreen extends StatefulWidget {
  const DebtScreen({super.key});

  @override
  State<DebtScreen> createState() => _DebtScreenState();
}

class _DebtScreenState extends State<DebtScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();
  DateTimeRange? _range;
  bool _showOnlyUnpaid = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DebtProvider>();
    var othersOwe = provider.debts.where((d) => d.type == DebtType.othersOweMe).toList();
    var iOwe = provider.debts.where((d) => d.type == DebtType.oweOthers).toList();

    final q = _searchCtrl.text.trim();
    if (q.isNotEmpty) {
      final qNorm = _vn(q).toLowerCase();
      othersOwe = othersOwe.where((d) => _vn(d.partyName).toLowerCase().contains(qNorm)).toList();
      iOwe = iOwe.where((d) => _vn(d.partyName).toLowerCase().contains(qNorm)).toList();
    }
    if (_range != null) {
      bool inRange(DateTime t) => t.isAfter(_range!.start.subtract(const Duration(seconds: 1))) && t.isBefore(_range!.end.add(const Duration(seconds: 1)));
      othersOwe = othersOwe.where((d) => inRange(d.createdAt)).toList();
      iOwe = iOwe.where((d) => inRange(d.createdAt)).toList();
    }
    
    if (_showOnlyUnpaid) {
      othersOwe = othersOwe.where((d) => d.amount > 0).toList();
      iOwe = iOwe.where((d) => d.amount > 0).toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ghi nợ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Thêm công nợ',
            onPressed: () async {
              final type = _tabController.index == 0 ? DebtType.othersOweMe : DebtType.oweOthers;
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => DebtFormScreen(initialType: type)),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Tiền nợ tôi'),
            Tab(text: 'Tiền tôi nợ'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Lọc theo tên người',
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text(_range == null
                      ? 'Khoảng ngày'
                      : '${DateFormat('dd/MM').format(_range!.start)} - ${DateFormat('dd/MM').format(_range!.end)}'),
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(now.year - 3),
                      lastDate: DateTime(now.year + 3),
                      initialDateRange: _range,
                    );
                    if (picked != null) setState(() => _range = picked);
                  },
                ),
                if (_range != null)
                  IconButton(
                    tooltip: 'Xóa lọc ngày',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _range = null),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Row(
              children: [
                const Text('Chỉ hiển thị còn nợ'),
                const SizedBox(width: 8),
                Switch(
                  value: _showOnlyUnpaid,
                  onChanged: (value) {
                    setState(() {
                      _showOnlyUnpaid = value;
                    });
                  },
                ),
                const Spacer(),
                Text(
                  'Tổng: ${_tabController.index == 0 ? othersOwe.length : iOwe.length} người',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                DebtList(debts: othersOwe, color: Colors.red),
                DebtList(debts: iOwe, color: Colors.amber),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

// Vietnamese diacritics removal (accent-insensitive search) without external deps
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

Future<void> _showPayDialog(BuildContext context, Debt d, NumberFormat currency) async {
  final amountCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Trả nợ một phần'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Còn nợ: ${currency.format(d.amount)}'),
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
    if (amount <= 0 || amount > d.amount) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Số tiền không hợp lệ')));
      return;
    }
    await context.read<DebtProvider>().addPayment(
      debt: d,
      amount: amount,
      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
    );
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã ghi nhận thanh toán')));
  }
}

Future<void> _showPaymentHistory(BuildContext context, Debt d, NumberFormat currency) async {
    final payments = await context.read<DebtProvider>().paymentsFor(d.id);
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Lịch sử thanh toán', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (payments.isEmpty)
              const Text('Chưa có lịch sử')
            else
              ...payments.map((m) {
                final createdAt = DateTime.parse(m['createdAt'] as String);
                final note = (m['note'] as String?) ?? '';
                final amount = (m['amount'] as num).toDouble();
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${DateFormat('dd/MM/yyyy HH:mm').format(createdAt)} - ${currency.format(amount)}'),
                  subtitle: note.isEmpty ? null : Text(note),
                );
              }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }


class DebtList extends StatelessWidget {
  final List<Debt> debts;
  final Color color;
  const DebtList({required this.debts, required this.color});

  Future<String?> _pickSaleId(BuildContext context) async {
    final sales = await DatabaseService.instance.getSales();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) {
        final searchCtrl = TextEditingController();
        List<Sale> filtered = List.from(sales);
        final fmt = DateFormat('dd/MM/yyyy HH:mm');
        final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
        return StatefulBuilder(
          builder: (context, setState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: 12 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: searchCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Tìm theo khách hàng / mặt hàng',
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) {
                      final q = v.trim().toLowerCase();
                      setState(() {
                        if (q.isEmpty) {
                          filtered = List.from(sales);
                        } else {
                          filtered = sales.where((s) {
                            final customer = (s.customerName ?? '').toLowerCase();
                            final items = s.items.map((e) => e.name).join(', ').toLowerCase();
                            return customer.contains(q) || items.contains(q);
                          }).toList();
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final s = filtered[i];
                        final title = (s.customerName?.trim().isNotEmpty == true) ? s.customerName!.trim() : 'Khách lẻ';
                        final subtitle = '${fmt.format(s.createdAt)} • ${currency.format(s.total)}';
                        return ListTile(
                          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => Navigator.of(context).pop(s.id),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _pickPurchaseId(BuildContext context) async {
    final rows = await DatabaseService.instance.getPurchaseHistory();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) {
        final searchCtrl = TextEditingController();
        List<Map<String, dynamic>> filtered = List.from(rows);
        final fmt = DateFormat('dd/MM/yyyy HH:mm');
        final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
        return StatefulBuilder(
          builder: (context, setState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: 12 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: searchCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Tìm theo sản phẩm / NCC',
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) {
                      final q = v.trim().toLowerCase();
                      setState(() {
                        if (q.isEmpty) {
                          filtered = List.from(rows);
                        } else {
                          filtered = rows.where((r) {
                            final name = (r['productName'] as String? ?? '').toLowerCase();
                            final supplier = (r['supplierName'] as String? ?? '').toLowerCase();
                            return name.contains(q) || supplier.contains(q);
                          }).toList();
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final r = filtered[i];
                        final id = r['id'] as String;
                        final createdAt = DateTime.tryParse(r['createdAt'] as String? ?? '') ?? DateTime.now();
                        final name = (r['productName'] as String?) ?? '';
                        final totalCost = (r['totalCost'] as num?)?.toDouble() ?? 0;
                        final supplier = (r['supplierName'] as String?)?.trim();
                        final subtitle = '${fmt.format(createdAt)} • ${currency.format(totalCost)}${(supplier != null && supplier.isNotEmpty) ? ' • $supplier' : ''}';
                        return ListTile(
                          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => Navigator.of(context).pop(id),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    if (debts.isEmpty) {
      return const Center(child: Text('Chưa có dữ liệu'));
    }
    return ListView.separated(
      itemCount: debts.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final d = debts[i];
        return GestureDetector(
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DebtDetailScreen(debt: d)));
          },
          onLongPress: () async {
            final action = await showModalBottomSheet<String>(
              context: context,
              showDragHandle: true,
              builder: (_) {
                return SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if ((d.sourceId == null || d.sourceId!.isEmpty))
                        ListTile(
                          leading: const Icon(Icons.link_outlined),
                          title: const Text('Gán giao dịch'),
                          subtitle: Text(d.type == DebtType.othersOweMe ? 'Chọn hóa đơn bán' : 'Chọn phiếu nhập'),
                          onTap: () => Navigator.of(context).pop('link'),
                        ),
                      ListTile(
                        leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        title: const Text('Xóa công nợ'),
                        onTap: () => Navigator.of(context).pop('delete'),
                      ),
                    ],
                  ),
                );
              },
            );

            if (action == 'link') {
              String? picked;
              String? type;
              if (d.type == DebtType.othersOweMe) {
                picked = await _pickSaleId(context);
                type = 'sale';
              } else {
                picked = await _pickPurchaseId(context);
                type = 'purchase';
              }
              if (picked != null && picked.isNotEmpty) {
                d.sourceType = type;
                d.sourceId = picked;
                await context.read<DebtProvider>().update(d);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã gán giao dịch cho công nợ')));
              }
              return;
            }

            if (action == 'delete') {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Xóa công nợ'),
                  content: const Text('Bạn có chắc muốn xóa công nợ này? Mọi lịch sử thanh toán sẽ bị xóa.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Hủy'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Xóa'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                await context.read<DebtProvider>().deleteDebt(d.id);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã xóa công nợ')),
                );
              }
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left side - Main content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // First row - Name and status
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              d.partyName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 16,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: d.settled ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              d.settled ? 'Đã tất toán' : 'Chưa tất toán',
                              style: TextStyle(
                                color: d.settled ? Colors.green : Colors.orange,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 4),
                      
                      // Second row - Date and initial debt
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            DateFormat('dd/MM/yyyy').format(d.createdAt),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FutureBuilder<double>(
                              future: DatabaseService.instance.getTotalPaidForDebt(d.id),
                              builder: (context, snap) {
                                if (snap.connectionState == ConnectionState.waiting) {
                                  return const SizedBox.shrink();
                                }
                                final paid = snap.data ?? 0;
                                final initial = paid + d.amount;
                                return Text(
                                  'Nợ ban đầu: ${NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0).format(initial)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      
                      // Description (if exists)
                      if ((d.description ?? '').isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          d.description!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),

                // Right side - Amount and actions
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Amount
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        currency.format(d.amount),
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    
                    // Action buttons
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Pay button
                        GestureDetector(
                          onTap: () => _showPayDialog(context, d, currency),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(Icons.payments_outlined, size: 18, color: Colors.green),
                          ),
                        ),
                        
                        const SizedBox(width: 6),
                        
                        // History button
                        GestureDetector(
                          onTap: () => _showPaymentHistory(context, d, currency),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(Icons.history, size: 18, color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
