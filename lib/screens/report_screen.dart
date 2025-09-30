import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/sale_provider.dart';
import '../providers/debt_provider.dart';

// Helper class to store chart data points
class _Point {
  final String x;
  final double y;
  final double cost;
  final double profit;

  _Point(this.x, this.y, {required this.cost, required this.profit});
}

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  DateTimeRange _dateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 6)),
    end: DateTime.now(),
  );

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _dateRange,
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.blue,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _dateRange) {
      setState(() {
        _dateRange = picked;
      });
    }
  }

  double _getMinY(List<_Point> points) {
    if (points.isEmpty) return 0;
    double minY = points[0].profit;
    for (final point in points) {
      if (point.profit < minY) minY = point.profit;
      if (point.y < minY) minY = point.y;
      if (point.cost < minY) minY = point.cost;
    }
    return minY > 0 ? 0 : minY * 1.1;
  }

  double _getMaxY(List<_Point> points) {
    if (points.isEmpty) return 100;
    double maxY = points[0].profit;
    for (final point in points) {
      if (point.profit > maxY) maxY = point.profit;
      if (point.y > maxY) maxY = point.y;
      if (point.cost > maxY) maxY = point.cost;
    }
    if (maxY == 0) return 100;
    return maxY * 1.1;
  }

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

    // Filter sales by selected date range
    final filteredSales = sales.where((s) => 
      !s.createdAt.isBefore(DateTime(_dateRange.start.year, _dateRange.start.month, _dateRange.start.day)) &&
      !s.createdAt.isAfter(DateTime(_dateRange.end.year, _dateRange.end.month, _dateRange.end.day, 23, 59, 59))
    ).toList();

    // Calculate metrics
    final todaySales = sales.where((s) => s.createdAt.isAfter(startOfDay)).fold(0.0, (p, s) => p + s.total);
    final todayCost = sales.where((s) => s.createdAt.isAfter(startOfDay)).fold(0.0, (p, s) => p + s.totalCost);
    final todayProfit = todaySales - todayCost;

    final weekSales = sales.where((s) => s.createdAt.isAfter(startOfWeek)).fold(0.0, (p, s) => p + s.total);
    final weekCost = sales.where((s) => s.createdAt.isAfter(startOfWeek)).fold(0.0, (p, s) => p + s.totalCost);
    final weekProfit = weekSales - weekCost;

    final monthSales = sales.where((s) => s.createdAt.isAfter(startOfMonth)).fold(0.0, (p, s) => p + s.total);
    final monthCost = sales.where((s) => s.createdAt.isAfter(startOfMonth)).fold(0.0, (p, s) => p + s.totalCost);
    final monthProfit = monthSales - monthCost;

    final yearSales = sales.where((s) => s.createdAt.isAfter(startOfYear)).fold(0.0, (p, s) => p + s.total);
    final yearCost = sales.where((s) => s.createdAt.isAfter(startOfYear)).fold(0.0, (p, s) => p + s.totalCost);
    final yearProfit = yearSales - yearCost;

    final totalOweOthers = debtsProvider.totalOweOthers;
    final totalOthersOweMe = debtsProvider.totalOthersOweMe;

    // Prepare data for charts
    final daysInRange = _dateRange.duration.inDays + 1;
    final dailyData = List.generate(daysInRange, (i) {
      final date = _dateRange.start.add(Duration(days: i));
      final daySales = filteredSales.where((s) => 
        s.createdAt.year == date.year && 
        s.createdAt.month == date.month && 
        s.createdAt.day == date.day
      ).toList();
      
      final revenue = daySales.fold(0.0, (p, s) => p + s.total);
      final cost = daySales.fold(0.0, (p, s) => p + s.totalCost);
      final profit = revenue - cost;
      
      return _Point(
        DateFormat('dd/MM').format(date),
        revenue,
        cost: cost,
        profit: profit,
      );
    });

    // Prepare monthly data for current year
    final currentYear = now.year;
    final monthlyDataPoints = List.generate(12, (i) {
      final month = i + 1;
      final monthSales = filteredSales.where((s) => 
        s.createdAt.year == currentYear && 
        s.createdAt.month == month
      ).toList();
      
      final revenue = monthSales.fold(0.0, (p, s) => p + s.total);
      final cost = monthSales.fold(0.0, (p, s) => p + s.totalCost);
      final profit = revenue - cost;
      
      return _Point(
        '$month',
        revenue,
        cost: cost,
        profit: profit,
      );
    });
    
    // Prepare yearly data
    final years = <int>{};
    for (var s in filteredSales) {
      years.add(s.createdAt.year);
    }
    final sortedYears = years.toList()..sort();
    final yearlyDataPoints = sortedYears.map((year) {
      final yearSales = filteredSales.where((s) => s.createdAt.year == year).toList();
      final revenue = yearSales.fold(0.0, (p, s) => p + s.total);
      final cost = yearSales.fold(0.0, (p, s) => p + s.totalCost);
      final profit = revenue - cost;
      
      return _Point(
        year.toString(),
        revenue,
        cost: cost,
        profit: profit,
      );
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Báo cáo'),
        actions: [
          IconButton(
            tooltip: 'Chọn khoảng ngày',
            icon: const Icon(Icons.calendar_today),
            onPressed: () => _selectDateRange(context),
          ),
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
        padding: const EdgeInsets.all(5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Text(
                    'Khoảng ngày: ${DateFormat('dd/MM/yyyy').format(_dateRange.start)} - ${DateFormat('dd/MM/yyyy').format(_dateRange.end)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                GridView.count(
                  crossAxisCount: 2,
                  childAspectRatio: 1.8,
                  crossAxisSpacing: 1,
                  mainAxisSpacing: 1,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 4),
                  children: [
                    _KpiCard(
                      title: 'Hôm nay',
                      revenue: todaySales,
                      cost: todayCost,
                      profit: todayProfit,
                      currency: currency,
                      color: Colors.blue,
                    ),
                    _KpiCard(
                      title: 'Tuần này',
                      revenue: weekSales,
                      cost: weekCost,
                      profit: weekProfit,
                      currency: currency,
                      color: Colors.green,
                    ),
                    _KpiCard(
                      title: 'Tháng này',
                      revenue: monthSales,
                      cost: monthCost,
                      profit: monthProfit,
                      currency: currency,
                      color: Colors.purple,
                    ),
                    _KpiCard(
                      title: 'Năm nay',
                      revenue: yearSales,
                      cost: yearCost,
                      profit: yearProfit,
                      currency: currency,
                      color: Colors.orange,
                    ),
                    _KpiCard(
                      title: 'Tiền nợ tôi',
                      value: totalOthersOweMe,
                      currency: currency,
                      color: Colors.red,
                    ),
                    _KpiCard(
                      title: 'Tiền tôi nợ',
                      value: totalOweOthers,
                      currency: currency,
                      color: Colors.amber,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Daily Chart
            _buildChartCard(
              title: 'Theo ngày (${_dateRange.start.day}/${_dateRange.start.month} - ${_dateRange.end.day}/${_dateRange.end.month})',
              points: dailyData,
              currency: currency,
            ),
            const SizedBox(height: 16),
            // Monthly Chart
            _buildChartCard(
              title: 'Theo tháng (${now.year})',
              points: monthlyDataPoints,
              currency: currency,
            ),
            const SizedBox(height: 16),
            // Yearly Chart
            _buildChartCard(
              title: 'Theo năm',
              points: yearlyDataPoints,
              currency: currency,
              isYearly: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartCard({
    required String title,
    required List<_Point> points,
    required NumberFormat currency,
    bool isYearly = false,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              height: 300,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  minY: _getMinY(points),
                  maxY: _getMaxY(points),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final point = points[groupIndex];
                        final tooltipText = '${point.x}\n\n'
                            'Doanh thu: ${currency.format(point.y)}\n'
                            'Chi phí: ${currency.format(point.cost)}\n'
                            'Lợi nhuận: ${currency.format(point.profit)}';
                        return BarTooltipItem(
                          tooltipText,
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        );
                      },
                      tooltipMargin: 8,
                      tooltipRoundedRadius: 8,
                      tooltipPadding: const EdgeInsets.all(8),
                      getTooltipColor: (_) => Colors.black87,
                    ),
                  ),
                  gridData: const FlGridData(show: true, drawVerticalLine: false),
                  borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.withAlpha(51))),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 || i >= points.length) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              points[i].x,
                              style: const TextStyle(fontSize: 10),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                        reservedSize: 42,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
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
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  barGroups: [
                    for (var i = 0; i < points.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          // Revenue bar
                          BarChartRodData(
                            toY: points[i].y,
                            color: Colors.blue.withOpacity(0.7),
                            width: 10,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          // Cost bar (stacked)
                          BarChartRodData(
                            fromY: 0,
                            toY: points[i].cost,
                            color: Colors.red.withOpacity(0.7),
                            width: 10,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          // Profit bar
                          BarChartRodData(
                            toY: points[i].profit,
                            color: Colors.green.withOpacity(0.7),
                            width: 10,
                            borderRadius: BorderRadius.circular(2),
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
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final double? value;
  final double? revenue;
  final double? cost;
  final double? profit;
  final NumberFormat currency;
  final Color color;

  const _KpiCard({
    required this.title,
    this.value,
    this.revenue,
    this.cost,
    this.profit,
    required this.currency,
    required this.color,
  }) : assert(value != null || (revenue != null && cost != null && profit != null));

  @override
  Widget build(BuildContext context) {
    if (value != null) {
      return _buildSimpleCard(context);
    } else {
      return _buildDetailedCard(context);
    }
  }

  Widget _buildSimpleCard(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title, 
              style: TextStyle(
                color: color, 
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                currency.format(value),
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedCard(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            // Revenue
            _buildMetricRow('Doanh thu', revenue!, Colors.blue),
            const SizedBox(height: 4),
            // Cost
            _buildMetricRow('Chi phí', cost!, Colors.orange),
            const SizedBox(height: 4),
            // Profit
            _buildMetricRow(
              'Lợi nhuận',
              profit!,
              profit! >= 0 ? Colors.green : Colors.red,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, double value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.black87),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            currency.format(value),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}