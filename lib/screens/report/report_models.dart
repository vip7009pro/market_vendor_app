part of '../report_screen.dart';

// Helper class to store chart data points
class _Point {
  final String x;
  final double y;
  final double cost;
  final double profit;
  _Point(this.x, this.y, {required this.cost, required this.profit});
}

class _TopProductRow {
  final String key;
  final String name;
  final String unit;
  final double qty;
  final double amount;
  const _TopProductRow({
    required this.key,
    required this.name,
    required this.unit,
    required this.qty,
    required this.amount,
  });
}

class _PayStats {
  final double cashRevenue;
  final double bankRevenue;
  final double outstandingDebt;
  const _PayStats({
    required this.cashRevenue,
    required this.bankRevenue,
    required this.outstandingDebt,
  });
}
