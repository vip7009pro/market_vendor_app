import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/debt.dart';
import '../providers/debt_provider.dart';
import '../services/database_service.dart';
import 'debt_detail_screen.dart';

class DebtPartySummaryScreen extends StatelessWidget {
  final String partyId;
  final String partyName;

  const DebtPartySummaryScreen({
    super.key,
    required this.partyId,
    required this.partyName,
  });

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    final debts = context.watch<DebtProvider>().debts;

    bool sameParty(Debt d) {
      final pid = d.partyId.trim();
      if (pid.isNotEmpty && partyId.trim().isNotEmpty) {
        return pid == partyId.trim();
      }
      return d.partyName.trim() == partyName.trim();
    }

    final related = debts.where(sameParty).toList();
    final othersOweMe = related.where((d) => d.type == DebtType.othersOweMe).toList();
    final iOwe = related.where((d) => d.type == DebtType.oweOthers).toList();

    final totalOthersOweMe = othersOweMe.fold<double>(0.0, (p, e) => p + (e.amount));
    final totalIOwe = iOwe.fold<double>(0.0, (p, e) => p + (e.amount));
    final net = (totalOthersOweMe - totalIOwe);

    return Scaffold(
      appBar: AppBar(
        title: Text('Tổng kết: $partyName'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person_outline),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            partyName,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _TotalTile(
                            title: 'Người này nợ tôi',
                            value: currency.format(totalOthersOweMe),
                            color: Colors.redAccent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _TotalTile(
                            title: 'Tôi nợ người này',
                            value: currency.format(totalIOwe),
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: _TotalTile(
                        title: net >= 0 ? 'Chênh lệch (tôi đang được nợ)' : 'Chênh lệch (tôi đang nợ)',
                        value: currency.format(net.abs()),
                        color: net >= 0 ? Colors.green : Colors.deepOrange,
                        center: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                _DebtGroup(
                  title: 'Người này nợ tôi',
                  color: Colors.redAccent,
                  debts: othersOweMe,
                ),
                const SizedBox(height: 10),
                _DebtGroup(
                  title: 'Tôi nợ người này',
                  color: Colors.orange,
                  debts: iOwe,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalTile extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final bool center;

  const _TotalTile({
    required this.title,
    required this.value,
    required this.color,
    this.center = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
        color: color.withOpacity(0.06),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54)),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: color),
          ),
        ],
      ),
    );
  }
}

class _DebtGroup extends StatelessWidget {
  final String title;
  final Color color;
  final List<Debt> debts;

  const _DebtGroup({
    required this.title,
    required this.color,
    required this.debts,
  });

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    final fmtDate = DateFormat('dd/MM/yyyy');
    debts.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
                Text('${debts.length}'),
              ],
            ),
            const SizedBox(height: 8),
            if (debts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('Không có công nợ'),
              )
            else
              ...debts.map((d) {
                final status = (d.settled || d.amount <= 0) ? 'Đã tất toán' : 'Chưa tất toán';
                return FutureBuilder<double>(
                  future: DatabaseService.instance.getTotalPaidForDebt(d.id),
                  builder: (context, snap) {
                    final paid = snap.data ?? 0.0;
                    final remain = d.amount;
                    final initial = paid + remain;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              fmtDate.format(d.createdAt),
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                            ),
                          ),
                          Text(
                            status,
                            style: TextStyle(
                              color: (d.settled || d.amount <= 0) ? Colors.green : Colors.orange,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Nợ ban đầu: ${currency.format(initial)}'),
                            Text('Còn lại: ${currency.format(remain)}'),
                          ],
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => DebtDetailScreen(debt: d)),
                        );
                      },
                    );
                  },
                );
              }),
          ],
        ),
      ),
    );
  }
}
