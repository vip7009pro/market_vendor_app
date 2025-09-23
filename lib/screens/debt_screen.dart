import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/debt.dart';
import '../providers/debt_provider.dart';
import 'debt_form_screen.dart';
import 'debt_detail_screen.dart';
import 'package:intl/intl.dart';

class DebtScreen extends StatefulWidget {
  const DebtScreen({super.key});

  @override
  State<DebtScreen> createState() => _DebtScreenState();
}

class _DebtScreenState extends State<DebtScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

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
    final othersOwe = provider.debts.where((d) => d.type == DebtType.othersOweMe).toList();
    final iOwe = provider.debts.where((d) => d.type == DebtType.oweOthers).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ghi nợ'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Tiền nợ tôi'),
            Tab(text: 'Tiền tôi nợ'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DebtList(debts: othersOwe, color: Colors.red),
          _DebtList(debts: iOwe, color: Colors.amber),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final type = _tabController.index == 0 ? DebtType.othersOweMe : DebtType.oweOthers;
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DebtFormScreen(initialType: type)));
        },
        label: const Text('Thêm'),
        icon: const Icon(Icons.add),
      ),
    );
  }
}

class _DebtList extends StatelessWidget {
  final List<Debt> debts;
  final Color color;
  const _DebtList({required this.debts, required this.color});

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
        return ListTile(
          title: Text(d.partyName),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((d.description ?? '').isNotEmpty) Text(d.description!),
              Text(
                d.settled ? 'Đã tất toán' : 'Chưa tất toán',
                style: TextStyle(color: d.settled ? Colors.green : Colors.orange, fontSize: 12),
              ),
            ],
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                currency.format(d.amount),
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Trả nợ',
                    icon: const Icon(Icons.payments_outlined),
                    onPressed: () => _showPayDialog(context, d, currency),
                  ),
                  IconButton(
                    tooltip: 'Lịch sử',
                    icon: const Icon(Icons.history),
                    onPressed: () => _showPaymentHistory(context, d, currency),
                  ),
                ],
              ),
            ],
          ),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DebtDetailScreen(debt: d)));
          },
          onLongPress: () async {
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
              await context.read<DebtProvider>().deleteDebt(d.id);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa công nợ')));
            }
          },
        );
      },
    );
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
      await context.read<DebtProvider>().addPayment(debt: d, amount: amount, note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim());
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
}
