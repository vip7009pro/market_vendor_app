import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/sale_provider.dart';
import '../providers/debt_provider.dart';

class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    final sales = context.watch<SaleProvider>().sales;
    final debtsProvider = context.watch<DebtProvider>();
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final startOfWeek = startOfDay.subtract(Duration(days: startOfDay.weekday - 1));
    final startOfMonth = DateTime(now.year, now.month, 1);
    final startOfYear = DateTime(now.year, 1, 1);

    final todaySales = sales.where((s) => s.createdAt.isAfter(startOfDay)).fold(0.0, (p, s) => p + s.total);
    final weekSales = sales.where((s) => s.createdAt.isAfter(startOfWeek)).fold(0.0, (p, s) => p + s.total);
    final monthSales = sales.where((s) => s.createdAt.isAfter(startOfMonth)).fold(0.0, (p, s) => p + s.total);
    final yearSales = sales.where((s) => s.createdAt.isAfter(startOfYear)).fold(0.0, (p, s) => p + s.total);
    final totalOweOthers = debtsProvider.totalOweOthers;
    final totalOthersOweMe = debtsProvider.totalOthersOweMe;

    // Prepare simple last 7 days series
    final last7Days = List.generate(7, (i) => startOfDay.subtract(Duration(days: 6 - i)));
    final dailyData = last7Days.map((d) {
      final amount = sales
          .where((s) => s.createdAt.year == d.year && s.createdAt.month == d.month && s.createdAt.day == d.day)
          .fold(0.0, (p, s) => p + s.total);
      return _Point(DateFormat('dd/MM').format(d), amount);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Báo cáo'),
        actions: [
          IconButton(
            tooltip: 'Lịch sử bán',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).pushNamed('/sales_history'),
          ),
          IconButton(
            tooltip: 'Lịch sử công nợ',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).pushNamed('/debts_history'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GridView.count(
              crossAxisCount: 2,
              childAspectRatio: 1.8,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _KpiCard(title: 'Doanh thu hôm nay', value: currency.format(todaySales), color: Colors.blue),
                _KpiCard(title: 'Doanh thu tuần', value: currency.format(weekSales), color: Colors.green),
                _KpiCard(title: 'Doanh thu tháng', value: currency.format(monthSales), color: Colors.pink),
                _KpiCard(title: 'Doanh thu năm', value: currency.format(yearSales), color: Colors.purple),
                _KpiCard(title: 'Tiền nợ tôi', value: currency.format(totalOthersOweMe), color: Colors.red),
                _KpiCard(title: 'Tiền tôi nợ', value: currency.format(totalOweOthers), color: Colors.orange),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Doanh thu 7 ngày gần nhất', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 200,
                      child: BarChart(
                        BarChartData(
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                reservedSize: 44,
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  // Show compact K/M formatting for large numbers
                                  String txt;
                                  if (value >= 1000000) {
                                    txt = '${(value / 1000000).toStringAsFixed(1)}M';
                                  } else if (value >= 1000) {
                                    txt = '${(value / 1000).toStringAsFixed(0)}k';
                                  } else {
                                    txt = value.toInt().toString();
                                  }
                                  return Text(txt, style: const TextStyle(fontSize: 10));
                                },
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  final i = value.toInt();
                                  if (i < 0 || i >= dailyData.length) return const SizedBox.shrink();
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(dailyData[i].x, style: const TextStyle(fontSize: 10)),
                                  );
                                },
                              ),
                            ),
                          ),
                          barGroups: [
                            for (var i = 0; i < dailyData.length; i++)
                              BarChartGroupData(
                                x: i,
                                barRods: [
                                  BarChartRodData(
                                    toY: dailyData[i].y,
                                    color: Colors.blue,
                                    width: 14,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Point {
  final String x;
  final double y;
  _Point(this.x, this.y);
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  const _KpiCard({required this.title, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            // The actual value is set by parent via currency.format, so keep empty default safe
            Text(value.isEmpty ? '—' : value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
