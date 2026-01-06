import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../models/debt.dart';
import '../models/sale.dart';
import '../providers/debt_provider.dart';
import 'debt_form_screen.dart';
import 'debt_detail_screen.dart';
import 'debt_party_summary_screen.dart';
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
  DateTimeRange _reportRange = (() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    return DateTimeRange(start: start, end: end);
  })();
  bool _showOnlyUnpaid = true;
  _DebtLinkFilter _linkFilter = _DebtLinkFilter.all;

  bool _isTableView = false;

  final PageController _oweChartPageController = PageController(initialPage: 0);
  final ValueNotifier<int> _oweChartPageIndex = ValueNotifier<int>(0);
  final PageController _iOweChartPageController = PageController(initialPage: 0);
  final ValueNotifier<int> _iOweChartPageIndex = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _oweChartPageController.dispose();
    _oweChartPageIndex.dispose();
    _iOweChartPageController.dispose();
    _iOweChartPageIndex.dispose();
    super.dispose();
  }

  Future<void> _selectReportDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _reportRange,
    );
    if (picked == null) return;
    setState(() {
      _reportRange = DateTimeRange(
        start: DateTime(picked.start.year, picked.start.month, picked.start.day),
        end: DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59, 999),
      );
    });
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

    bool isLinked(Debt d) {
      final st = (d.sourceType ?? '').trim();
      final sid = (d.sourceId ?? '').trim();
      if (sid.isEmpty) return false;
      return st == 'sale' || st == 'purchase';
    }

    bool isExternal(Debt d) {
      final st = (d.sourceType ?? '').trim();
      final sid = (d.sourceId ?? '').trim();
      if (sid.isEmpty) return true;
      return !(st == 'sale' || st == 'purchase');
    }

    if (_linkFilter == _DebtLinkFilter.linked) {
      othersOwe = othersOwe.where(isLinked).toList();
      iOwe = iOwe.where(isLinked).toList();
    } else if (_linkFilter == _DebtLinkFilter.external) {
      othersOwe = othersOwe.where(isExternal).toList();
      iOwe = iOwe.where(isExternal).toList();
    }

    final allDebtsForPartyTab = <Debt>[...othersOwe, ...iOwe];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ghi nợ'),
        actions: [
          IconButton(
            tooltip: _isTableView ? 'Hiển thị dạng thẻ' : 'Hiển thị dạng bảng',
            icon: Icon(_isTableView ? Icons.view_agenda_outlined : Icons.table_chart_outlined),
            onPressed: () => setState(() => _isTableView = !_isTableView),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Thêm công nợ',
            onPressed: () async {
              final tab = _tabController.index;
              final type = tab == 1 ? DebtType.oweOthers : DebtType.othersOweMe;
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
            Tab(text: 'Gom theo người'),
            Tab(text: 'Báo cáo nợ'),
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 2.0),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Tất cả'),
                  selected: _linkFilter == _DebtLinkFilter.all,
                  onSelected: (_) => setState(() => _linkFilter = _DebtLinkFilter.all),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Có giao dịch'),
                  selected: _linkFilter == _DebtLinkFilter.linked,
                  onSelected: (_) => setState(() => _linkFilter = _DebtLinkFilter.linked),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Nợ ngoài'),
                  selected: _linkFilter == _DebtLinkFilter.external,
                  onSelected: (_) => setState(() => _linkFilter = _DebtLinkFilter.external),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                DebtList(debts: othersOwe, color: Colors.red, isTableView: _isTableView),
                DebtList(debts: iOwe, color: Colors.amber, isTableView: _isTableView),
                _DebtPartyAggTab(
                  allDebts: allDebtsForPartyTab,
                  query: _searchCtrl.text.trim(),
                ),
                _DebtReportTab(
                  allDebts: allDebtsForPartyTab,
                  range: _reportRange,
                  onPickRange: () => _selectReportDateRange(context),
                  oweChartController: _oweChartPageController,
                  oweChartIndex: _oweChartPageIndex,
                  iOweChartController: _iOweChartPageController,
                  iOweChartIndex: _iOweChartPageIndex,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

enum _DebtLinkFilter { all, linked, external }

class _DebtPartyAggRow {
  final String partyKey;
  final String partyName;
  final double oweMe;
  final double iOwe;
  final int oweMeCount;
  final int iOweCount;
  final DateTime? oldestOutstanding;

  const _DebtPartyAggRow({
    required this.partyKey,
    required this.partyName,
    required this.oweMe,
    required this.iOwe,
    required this.oweMeCount,
    required this.iOweCount,
    required this.oldestOutstanding,
  });

  double get net => oweMe - iOwe;

  bool get isSettled => oweMe <= 0 && iOwe <= 0;

  int get oldestDays {
    final t = oldestOutstanding;
    if (t == null) return 0;
    final now = DateTime.now();
    final days = now.difference(DateTime(t.year, t.month, t.day)).inDays;
    return days < 0 ? 0 : days;
  }
}

class _DebtPartyAggTab extends StatelessWidget {
  final List<Debt> allDebts;
  final String query;

  const _DebtPartyAggTab({
    required this.allDebts,
    required this.query,
  });

  @override
  Widget build(BuildContext context) {
    final q = query.trim();
    final qNorm = q.isEmpty ? '' : _vn(q).toLowerCase();

    final byKey = <String, List<Debt>>{};
    for (final d in allDebts) {
      final key = (d.partyId.trim().isNotEmpty) ? d.partyId.trim() : d.partyName.trim();
      if (key.isEmpty) continue;
      byKey.putIfAbsent(key, () => <Debt>[]).add(d);
    }

    final rows = <_DebtPartyAggRow>[];
    for (final e in byKey.entries) {
      final list = e.value;
      final partyName = list.map((x) => x.partyName.trim()).firstWhere((x) => x.isNotEmpty, orElse: () => e.key);
      if (qNorm.isNotEmpty && !_vn(partyName).toLowerCase().contains(qNorm)) continue;

      double oweMe = 0;
      double iOwe = 0;
      int oweMeCount = 0;
      int iOweCount = 0;
      DateTime? oldest;
      for (final d in list) {
        final amt = (d.amount).clamp(0.0, double.infinity).toDouble();
        if (d.type == DebtType.othersOweMe) {
          oweMe += amt;
          if (amt > 0) oweMeCount++;
        } else {
          iOwe += amt;
          if (amt > 0) iOweCount++;
        }
        if (amt > 0) {
          if (oldest == null || d.createdAt.isBefore(oldest)) oldest = d.createdAt;
        }
      }
      rows.add(
        _DebtPartyAggRow(
          partyKey: e.key,
          partyName: partyName,
          oweMe: oweMe,
          iOwe: iOwe,
          oweMeCount: oweMeCount,
          iOweCount: iOweCount,
          oldestOutstanding: oldest,
        ),
      );
    }

    rows.sort((a, b) {
      final c = b.net.abs().compareTo(a.net.abs());
      if (c != 0) return c;
      return b.oldestDays.compareTo(a.oldestDays);
    });

    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    if (rows.isEmpty) {
      return const Center(child: Text('Chưa có dữ liệu'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemBuilder: (context, i) {
        final r = rows[i];
        final settled = r.isSettled;
        final bg = settled ? Colors.green.withAlpha(18) : Colors.red.withAlpha(12);
        final netColor = r.net >= 0 ? Colors.teal : Colors.deepOrange;
        final oldestText = r.oldestOutstanding == null ? '-' : DateFormat('dd/MM/yyyy').format(r.oldestOutstanding!);

        return Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black.withAlpha(8)),
          ),
          child: ListTile(
            title: Text(
              r.partyName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('Nợ tôi: ${currency.format(r.oweMe)} (${r.oweMeCount})')),
                      Expanded(child: Text('Tôi nợ: ${currency.format(r.iOwe)} (${r.iOweCount})')),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Tổng nợ: ${currency.format(r.net)}',
                          style: TextStyle(fontWeight: FontWeight.w800, color: netColor),
                        ),
                      ),
                      Expanded(child: Text('Nợ lâu nhất: $oldestText')),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Số ngày nợ: ${r.oldestDays} ngày'),
                ],
              ),
            ),
            trailing: settled
                ? const Icon(Icons.check_circle, color: Colors.green)
                : const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DebtPartySummaryScreen(partyId: r.partyKey, partyName: r.partyName),
                ),
              );
            },
          ),
        );
      },
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemCount: rows.length,
    );
  }
}

class _DebtAmountPoint {
  final String x;
  final double y;
  const _DebtAmountPoint(this.x, this.y);
}

class _DebtReportTab extends StatelessWidget {
  final List<Debt> allDebts;
  final DateTimeRange range;
  final VoidCallback onPickRange;
  final PageController oweChartController;
  final ValueNotifier<int> oweChartIndex;
  final PageController iOweChartController;
  final ValueNotifier<int> iOweChartIndex;

  const _DebtReportTab({
    required this.allDebts,
    required this.range,
    required this.onPickRange,
    required this.oweChartController,
    required this.oweChartIndex,
    required this.iOweChartController,
    required this.iOweChartIndex,
  });

  List<Debt> _inRange(List<Debt> debts) {
    bool inRange(DateTime t) => t.isAfter(range.start.subtract(const Duration(milliseconds: 1))) && t.isBefore(range.end.add(const Duration(milliseconds: 1)));
    return debts.where((d) => inRange(d.createdAt)).toList();
  }

  List<_DebtAmountPoint> _dailyPoints(List<Debt> debts) {
    final daysInRange = range.duration.inDays + 1;
    return List.generate(daysInRange, (i) {
      final date = range.start.add(Duration(days: i));
      final dayRows = debts.where((d) => d.createdAt.year == date.year && d.createdAt.month == date.month && d.createdAt.day == date.day);
      final amount = dayRows.fold<double>(0.0, (p, d) => p + d.amount);
      return _DebtAmountPoint(DateFormat('dd/MM').format(date), amount);
    });
  }

  List<_DebtAmountPoint> _monthlyPoints(List<Debt> debts) {
    final now = DateTime.now();
    final year = now.year;
    return List.generate(12, (i) {
      final m = i + 1;
      final rows = debts.where((d) => d.createdAt.year == year && d.createdAt.month == m);
      final amount = rows.fold<double>(0.0, (p, d) => p + d.amount);
      return _DebtAmountPoint('$m', amount);
    });
  }

  List<_DebtAmountPoint> _yearlyPoints(List<Debt> debts) {
    final years = <int>{};
    for (final d in debts) {
      years.add(d.createdAt.year);
    }
    final sorted = years.toList()..sort();
    return sorted.map((y) {
      final rows = debts.where((d) => d.createdAt.year == y);
      final amount = rows.fold<double>(0.0, (p, d) => p + d.amount);
      return _DebtAmountPoint(y.toString(), amount);
    }).toList();
  }

  Widget _buildAmountChartCard({
    required String title,
    required List<_DebtAmountPoint> points,
    required NumberFormat currency,
    Color color = Colors.blue,
    bool isYearly = false,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.black.withAlpha(8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              height: 260,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final minWidth = points.length * 64.0;
                  final chartWidth = minWidth < constraints.maxWidth ? constraints.maxWidth : minWidth;
                  return _AutoScrollToEnd(
                    signature: '$title-${points.length}-${points.isNotEmpty ? points.last.x : ''}',
                    builder: (controller) {
                      return SingleChildScrollView(
                        controller: controller,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: chartWidth,
                          child: BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.start,
                              groupsSpace: 18,
                              minY: 0,
                              barTouchData: BarTouchData(
                                touchTooltipData: BarTouchTooltipData(
                                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                    final p = points[groupIndex];
                                    return BarTooltipItem(
                                      '${p.x}\n\n${currency.format(p.y)}',
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
                                    barsSpace: 2,
                                    barRods: [
                                      BarChartRodData(
                                        toY: points[i].y,
                                        color: color.withAlpha(191),
                                        width: isYearly ? 16 : 12,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPagerIndicator(ValueNotifier<int> idx, int count) {
    return ValueListenableBuilder<int>(
      valueListenable: idx,
      builder: (context, pageIndex, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(count, (i) {
            final active = i == pageIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: active ? 18 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: active ? Colors.blue : Colors.grey.withAlpha(128),
                borderRadius: BorderRadius.circular(8),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildTopPartyCard({
    required String title,
    required String subtitle,
    required List<_DebtPartyAggRow> rows,
    required double Function(_DebtPartyAggRow r) valueOf,
    required String Function(_DebtPartyAggRow r) valueText,
    required Color color,
  }) {
    final list = rows.take(10).toList();
    final maxV = list.isEmpty
        ? 0.0
        : list.map((e) => valueOf(e)).reduce((a, b) => a > b ? a : b);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.black.withAlpha(8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            const SizedBox(height: 6),
            Text(subtitle, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black54)),
            const SizedBox(height: 10),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: Text('Chưa có dữ liệu')),
              )
            else
              Column(
                children: [
                  for (var i = 0; i < list.length; i++)
                    Padding(
                      padding: EdgeInsets.only(bottom: i == list.length - 1 ? 0 : 10),
                      child: _TopPartyBarRow(
                        index: i + 1,
                        row: list[i],
                        maxValue: maxV,
                        valueOf: valueOf,
                        valueText: valueText,
                        color: color,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    final inRange = _inRange(allDebts);
    final oweMe = inRange.where((d) => d.type == DebtType.othersOweMe).toList();
    final iOwe = inRange.where((d) => d.type == DebtType.oweOthers).toList();

    final oweMeDaily = _dailyPoints(oweMe);
    final oweMeMonthly = _monthlyPoints(oweMe);
    final oweMeYearly = _yearlyPoints(oweMe);

    final iOweDaily = _dailyPoints(iOwe);
    final iOweMonthly = _monthlyPoints(iOwe);
    final iOweYearly = _yearlyPoints(iOwe);

    final partyAgg = <String, _DebtPartyAggRow>{};
    for (final d in allDebts) {
      final key = (d.partyId.trim().isNotEmpty) ? d.partyId.trim() : d.partyName.trim();
      if (key.isEmpty) continue;
      final partyName = d.partyName.trim().isNotEmpty ? d.partyName.trim() : key;
      final prev = partyAgg[key];
      final amt = (d.amount).clamp(0.0, double.infinity).toDouble();
      final oweMeAmt = (d.type == DebtType.othersOweMe) ? amt : 0.0;
      final iOweAmt = (d.type == DebtType.oweOthers) ? amt : 0.0;
      DateTime? oldest = prev?.oldestOutstanding;
      if (amt > 0) {
        if (oldest == null || d.createdAt.isBefore(oldest)) oldest = d.createdAt;
      }
      partyAgg[key] = _DebtPartyAggRow(
        partyKey: key,
        partyName: partyName,
        oweMe: (prev?.oweMe ?? 0) + oweMeAmt,
        iOwe: (prev?.iOwe ?? 0) + iOweAmt,
        oweMeCount: (prev?.oweMeCount ?? 0) + ((d.type == DebtType.othersOweMe && amt > 0) ? 1 : 0),
        iOweCount: (prev?.iOweCount ?? 0) + ((d.type == DebtType.oweOthers && amt > 0) ? 1 : 0),
        oldestOutstanding: oldest,
      );
    }
    final parties = partyAgg.values.toList();

    final topOweMe = parties.where((e) => e.oweMe > 0).toList()
      ..sort((a, b) => b.oweMe.compareTo(a.oweMe));
    final topIOwe = parties.where((e) => e.iOwe > 0).toList()
      ..sort((a, b) => b.iOwe.compareTo(a.iOwe));
    final topLongTerm = parties.where((e) => !e.isSettled && e.oldestDays > 0).toList()
      ..sort((a, b) => b.oldestDays.compareTo(a.oldestDays));

    final now = DateTime.now();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text('${DateFormat('dd/MM').format(range.start)} - ${DateFormat('dd/MM').format(range.end)}'),
                onPressed: onPickRange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildTopPartyCard(
          title: 'Top 10 người nợ tôi nhiều nhất',
          subtitle: '(${DateFormat('dd/MM/yyyy').format(range.start)} - ${DateFormat('dd/MM/yyyy').format(range.end)})',
          rows: topOweMe,
          valueOf: (r) => r.oweMe,
          valueText: (r) => currency.format(r.oweMe),
          color: Colors.red,
        ),
        const SizedBox(height: 12),
        _buildTopPartyCard(
          title: 'Top 10 người tôi nợ nhiều nhất',
          subtitle: '(${DateFormat('dd/MM/yyyy').format(range.start)} - ${DateFormat('dd/MM/yyyy').format(range.end)})',
          rows: topIOwe,
          valueOf: (r) => r.iOwe,
          valueText: (r) => currency.format(r.iOwe),
          color: Colors.amber,
        ),
        const SizedBox(height: 12),
        _buildTopPartyCard(
          title: 'Top nợ dài hạn (số ngày nợ lâu nhất)',
          subtitle: '(${DateFormat('dd/MM/yyyy').format(range.start)} - ${DateFormat('dd/MM/yyyy').format(range.end)})',
          rows: topLongTerm,
          valueOf: (r) => r.oldestDays.toDouble(),
          valueText: (r) => '${r.oldestDays} ngày',
          color: Colors.indigo,
        ),
        const SizedBox(height: 16),
        const Text('Trending nợ tôi', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        const SizedBox(height: 8),
        SizedBox(
          height: 344,
          child: PageView(
            controller: oweChartController,
            onPageChanged: (i) => oweChartIndex.value = i,
            children: [
              _buildAmountChartCard(
                title: 'Theo ngày (${DateFormat('dd/MM').format(range.start)} - ${DateFormat('dd/MM').format(range.end)})',
                points: oweMeDaily,
                currency: currency,
                color: Colors.red,
              ),
              _buildAmountChartCard(
                title: 'Theo tháng (${now.year})',
                points: oweMeMonthly,
                currency: currency,
                color: Colors.red,
              ),
              _buildAmountChartCard(
                title: 'Theo năm',
                points: oweMeYearly,
                currency: currency,
                color: Colors.red,
                isYearly: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _buildPagerIndicator(oweChartIndex, 3),
        const SizedBox(height: 16),
        const Text('Trending tôi nợ', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        const SizedBox(height: 8),
        SizedBox(
          height: 344,
          child: PageView(
            controller: iOweChartController,
            onPageChanged: (i) => iOweChartIndex.value = i,
            children: [
              _buildAmountChartCard(
                title: 'Theo ngày (${DateFormat('dd/MM').format(range.start)} - ${DateFormat('dd/MM').format(range.end)})',
                points: iOweDaily,
                currency: currency,
                color: Colors.amber,
              ),
              _buildAmountChartCard(
                title: 'Theo tháng (${now.year})',
                points: iOweMonthly,
                currency: currency,
                color: Colors.amber,
              ),
              _buildAmountChartCard(
                title: 'Theo năm',
                points: iOweYearly,
                currency: currency,
                color: Colors.amber,
                isYearly: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _buildPagerIndicator(iOweChartIndex, 3),
      ],
    );
  }
}

class _TopPartyBarRow extends StatelessWidget {
  final int index;
  final _DebtPartyAggRow row;
  final double maxValue;
  final double Function(_DebtPartyAggRow r) valueOf;
  final String Function(_DebtPartyAggRow r) valueText;
  final Color color;
  const _TopPartyBarRow({
    required this.index,
    required this.row,
    required this.maxValue,
    required this.valueOf,
    required this.valueText,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final v = valueOf(row);
    final factor = (maxValue <= 0) ? 0.0 : (v / maxValue).clamp(0.0, 1.0).toDouble();
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54);
    final valueStyle = Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(width: 26, child: Text('$index.', style: labelStyle)),
            Expanded(
              child: Text(
                row.partyName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 10),
            Text(valueText(row), style: valueStyle),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: Container(
            height: 10,
            color: Colors.black.withAlpha(10),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: factor,
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      color.withAlpha(220),
                      Colors.indigo.withAlpha(220),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AutoScrollToEnd extends StatefulWidget {
  final String signature;
  final Widget Function(ScrollController controller) builder;
  const _AutoScrollToEnd({
    required this.signature,
    required this.builder,
  });

  @override
  State<_AutoScrollToEnd> createState() => _AutoScrollToEndState();
}

class _AutoScrollToEndState extends State<_AutoScrollToEnd> {
  final ScrollController _controller = ScrollController();
  String _lastSig = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeScroll();
  }

  @override
  void didUpdateWidget(covariant _AutoScrollToEnd oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeScroll();
  }

  void _maybeScroll() {
    if (widget.signature == _lastSig) return;
    _lastSig = widget.signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients) return;
      _controller.jumpTo(_controller.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_controller);
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

Future<String?> _pickPaymentTypeRequired(BuildContext context) async {
  final picked = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text('Tiền mặt'),
              onTap: () => Navigator.pop(ctx, 'cash'),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_outlined),
              title: const Text('Chuyển khoản'),
              onTap: () => Navigator.pop(ctx, 'bank'),
            ),
          ],
        ),
      );
    },
  );
  return picked;
}

Future<void> _settleDebt(BuildContext context, Debt d, NumberFormat currency) async {
  if (d.amount <= 0) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Tất toán công nợ'),
      content: Text('Bạn có chắc muốn tất toán ${currency.format(d.amount)} không?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xác nhận')),
      ],
    ),
  );
  if (ok != true) return;

  final paymentType = await _pickPaymentTypeRequired(context);
  if (paymentType == null) return;

  final remain = d.amount;
  await context.read<DebtProvider>().addPayment(
        debt: d,
        amount: remain,
        note: 'Tất toán',
        paymentType: paymentType,
      );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã tất toán')));
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

    final paymentType = await _pickPaymentTypeRequired(context);
    if (paymentType == null) return;

    await context.read<DebtProvider>().addPayment(
      debt: d,
      amount: amount,
      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      paymentType: paymentType,
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
                final paymentId = m['id'] as int;
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${DateFormat('dd/MM/yyyy HH:mm').format(createdAt)} - ${currency.format(amount)}'),
                  subtitle: note.isEmpty ? null : Text(note),
                  trailing: IconButton(
                    tooltip: 'Sửa',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      DateTime editedAt = createdAt;
                      final amountCtrl = TextEditingController(text: amount.toStringAsFixed(0));
                      final noteCtrl = TextEditingController(text: note);

                      Future<void> pickDateTime(StateSetter setStateDialog) async {
                        final dd = await showDatePicker(
                          context: context,
                          initialDate: editedAt,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (dd == null) return;
                        final tt = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(editedAt),
                        );
                        if (tt == null) return;
                        editedAt = DateTime(dd.year, dd.month, dd.day, tt.hour, tt.minute);
                        setStateDialog(() {});
                      }

                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => StatefulBuilder(
                          builder: (dialogCtx, setStateDialog) => AlertDialog(
                            title: const Text('Sửa thanh toán'),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text(DateFormat('dd/MM/yyyy HH:mm').format(editedAt))),
                                    TextButton(onPressed: () => pickDateTime(setStateDialog), child: const Text('Đổi')),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: amountCtrl,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(labelText: 'Số tiền'),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: noteCtrl,
                                  decoration: const InputDecoration(labelText: 'Ghi chú (tuỳ chọn)'),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Hủy')),
                              FilledButton(onPressed: () => Navigator.pop(dialogCtx, true), child: const Text('Lưu')),
                            ],
                          ),
                        ),
                      );

                      if (ok == true) {
                        final newAmount = double.tryParse(amountCtrl.text.replaceAll(',', '.')) ?? 0;
                        if (newAmount <= 0) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Số tiền không hợp lệ')));
                          return;
                        }
                        await context.read<DebtProvider>().updatePayment(
                              paymentId: paymentId,
                              debtId: d.id,
                              amount: newAmount,
                              createdAt: editedAt,
                              note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                            );
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã cập nhật thanh toán')));
                      }
                    },
                  ),
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
  final bool isTableView;
  const DebtList({required this.debts, required this.color, required this.isTableView});

  Future<void> _openPartySummary(BuildContext context, Debt d) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DebtPartySummaryScreen(
          partyId: d.partyId,
          partyName: d.partyName,
        ),
      ),
    );
  }

  Widget _tableHeaderCell(String text, {double? width, TextAlign align = TextAlign.left}) {
    return Container(
      alignment: align == TextAlign.right
          ? Alignment.centerRight
          : align == TextAlign.center
              ? Alignment.center
              : Alignment.centerLeft,
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Widget _tableCell(Widget child, {double? width, Alignment alignment = Alignment.centerLeft}) {
    return Container(
      alignment: alignment,
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: child,
    );
  }

  Future<void> _linkDebtTransaction(BuildContext context, Debt d) async {
    String? picked;
    String? type;
    if (d.type == DebtType.othersOweMe) {
      picked = await _pickSaleId(context);
      type = 'sale';
    } else {
      picked = await _pickPurchaseId(context);
      type = 'purchase';
    }
    if (picked == null || picked.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận gán giao dịch'),
        content: const Text('Bạn có chắc chắn muốn gán giao dịch này cho công nợ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Đồng ý'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    d.sourceType = type;
    d.sourceId = picked;
    await context.read<DebtProvider>().update(d);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã gán giao dịch cho công nợ')),
    );
  }

  Future<void> _deleteDebt(BuildContext context, Debt d) async {
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
    if (ok != true) return;

    final deleted = await context.read<DebtProvider>().deleteDebt(d.id);
    if (!context.mounted) return;
    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không được xóa công nợ của hóa đơn còn nợ. Vui lòng trả/tất toán.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa công nợ')));
  }

  Future<void> _showDebtActionSheet(BuildContext context, Debt d, NumberFormat currency) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.link_outlined),
                title: const Text('Gán giao dịch'),
                subtitle: Text(d.type == DebtType.othersOweMe ? 'Chọn hóa đơn bán' : 'Chọn phiếu nhập'),
                onTap: () => Navigator.of(context).pop('link'),
              ),
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text('Trả nợ một phần'),
                onTap: () => Navigator.of(context).pop('pay'),
              ),
              ListTile(
                leading: const Icon(Icons.done_all),
                title: const Text('Tất toán'),
                onTap: d.amount <= 0 ? null : () => Navigator.of(context).pop('settle'),
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Lịch sử thanh toán'),
                onTap: () => Navigator.of(context).pop('history'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Xóa công nợ', style: TextStyle(color: Colors.redAccent)),
                onTap: () => Navigator.of(context).pop('delete'),
              ),
            ],
          ),
        );
      },
    );

    if (action == 'link') {
      await _linkDebtTransaction(context, d);
      return;
    }
    if (action == 'pay') {
      await _showPayDialog(context, d, currency);
      return;
    }
    if (action == 'settle') {
      await _settleDebt(context, d, currency);
      return;
    }
    if (action == 'history') {
      await _showPaymentHistory(context, d, currency);
      return;
    }
    if (action == 'delete') {
      await _deleteDebt(context, d);
      return;
    }
  }

  Widget _buildAssignmentChip(Debt d) {
    final isAssigned = (d.sourceId ?? '').trim().isNotEmpty;
    final bg = isAssigned ? Colors.green.withOpacity(0.12) : Colors.orange.withOpacity(0.12);
    final fg = isAssigned ? Colors.green.shade800 : Colors.orange.shade800;
    final icon = isAssigned ? Icons.link : Icons.link_off;
    final label = isAssigned ? 'Đã gán' : 'Chưa gán';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _pickSaleId(BuildContext context) async {
    final sales = await DatabaseService.instance.getSales();

    final searchCtrl = TextEditingController();
    String query = '';
    List<Sale> filtered = List.from(sales);

    void applyFilter(void Function(void Function()) setState) {
      final q = _vn(query.trim()).toLowerCase();
      setState(() {
        if (q.isEmpty) {
          filtered = List.from(sales);
          return;
        }
        filtered = sales.where((s) {
          final customerRaw = (s.customerName ?? '').trim();
          final customer = _vn(customerRaw).toLowerCase();
          final items = _vn(s.items.map((e) => e.name).join(', ')).toLowerCase();
          return customer.contains(q) || items.contains(q);
        }).toList();
      });
    }

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) {
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
                      query = v;
                      applyFilter(setState);
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

    final searchCtrl = TextEditingController();
    String query = '';
    List<Map<String, dynamic>> filtered = List.from(rows);

    void applyFilter(void Function(void Function()) setState) {
      final q = _vn(query.trim()).toLowerCase();
      setState(() {
        if (q.isEmpty) {
          filtered = List.from(rows);
          return;
        }
        filtered = rows.where((r) {
          final name = _vn((r['productName'] as String? ?? '').trim()).toLowerCase();
          final supplier = _vn((r['supplierName'] as String? ?? '').trim()).toLowerCase();
          return name.contains(q) || supplier.contains(q);
        }).toList();
      });
    }

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) {
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
                      query = v;
                      applyFilter(setState);
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

    if (isTableView) {
      final fmt = DateFormat('dd/MM/yyyy');

      const wDate = 110.0;
      const wParty = 200.0;
      const wRemain = 130.0;
      const wInitial = 140.0;
      const wAssigned = 110.0;
      const wKind = 110.0;
      const wStatus = 110.0;
      const wDesc = 220.0;
      const wActions = 220.0;
      const tableWidth = wDate + wParty + wRemain + wInitial + wAssigned + wKind + wStatus + wDesc + wActions;

      return LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  Material(
                    color: Theme.of(context).colorScheme.surface,
                    elevation: 1,
                    child: Row(
                      children: [
                        _tableHeaderCell('Ngày', width: wDate),
                        _tableHeaderCell('Người', width: wParty),
                        _tableHeaderCell('Còn nợ', width: wRemain, align: TextAlign.right),
                        _tableHeaderCell('Nợ ban đầu', width: wInitial, align: TextAlign.right),
                        _tableHeaderCell('Gán', width: wAssigned, align: TextAlign.center),
                        _tableHeaderCell('Loại', width: wKind),
                        _tableHeaderCell('Trạng thái', width: wStatus),
                        _tableHeaderCell('Mô tả', width: wDesc),
                        _tableHeaderCell('Thao tác', width: wActions, align: TextAlign.center),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      itemCount: debts.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final d = debts[i];
                        final st = (d.sourceType ?? '').trim();
                        final kind = st == 'sale' ? 'Bán hàng' : (st == 'purchase' ? 'Nhập hàng' : (st.isEmpty ? 'Nợ ngoài' : st));
                        final statusText = d.settled || d.amount <= 0 ? 'Đã tất toán' : 'Chưa tất toán';
                        final desc = (d.description ?? '').trim();

                        return InkWell(
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => DebtDetailScreen(debt: d)),
                            );
                          },
                          onLongPress: () async {
                            await _showDebtActionSheet(context, d, currency);
                          },
                          child: Row(
                            children: [
                              _tableCell(Text(fmt.format(d.createdAt)), width: wDate),
                              _tableCell(
                                Text(d.partyName, maxLines: 2, overflow: TextOverflow.ellipsis),
                                width: wParty,
                              ),
                              _tableCell(
                                Text(currency.format(d.amount), style: TextStyle(fontWeight: FontWeight.w700, color: color)),
                                width: wRemain,
                                alignment: Alignment.centerRight,
                              ),
                              _tableCell(
                                FutureBuilder<double>(
                                  future: DatabaseService.instance.getTotalPaidForDebt(d.id),
                                  builder: (context, snap) {
                                    final paid = snap.data ?? 0;
                                    final initial = paid + d.amount;
                                    return Text(currency.format(initial));
                                  },
                                ),
                                width: wInitial,
                                alignment: Alignment.centerRight,
                              ),
                              _tableCell(
                                Center(child: _buildAssignmentChip(d)),
                                width: wAssigned,
                                alignment: Alignment.center,
                              ),
                              _tableCell(Text(kind), width: wKind),
                              _tableCell(Text(statusText), width: wStatus),
                              _tableCell(
                                Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis),
                                width: wDesc,
                              ),
                              _tableCell(
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      tooltip: 'Thanh toán',
                                      icon: Icon(Icons.payment, color: d.amount <= 0 ? Colors.grey : Colors.green),
                                      onPressed: d.amount <= 0 ? null : () => _showPayDialog(context, d, currency),
                                    ),
                                    IconButton(
                                      tooltip: 'Tất toán',
                                      icon: Icon(Icons.done_all, color: d.amount <= 0 ? Colors.grey : Colors.orange),
                                      onPressed: d.amount <= 0 ? null : () => _settleDebt(context, d, currency),
                                    ),
                                    IconButton(
                                      tooltip: 'Tổng kết',
                                      icon: const Icon(Icons.analytics_outlined, color: Colors.blueGrey),
                                      onPressed: () => _openPartySummary(context, d),
                                    ),
                                    IconButton(
                                      tooltip: 'Lịch sử',
                                      icon: const Icon(Icons.history, color: Colors.blue),
                                      onPressed: () => _showPaymentHistory(context, d, currency),
                                    ),
                                    IconButton(
                                      tooltip: 'Gán',
                                      icon: const Icon(Icons.link_outlined),
                                      onPressed: () => _linkDebtTransaction(context, d),
                                    ),
                                    IconButton(
                                      tooltip: 'Xóa',
                                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                      onPressed: () => _deleteDebt(context, d),
                                    ),
                                  ],
                                ),
                                width: wActions,
                                alignment: Alignment.center,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
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
                      if (true)
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
                final confirm = await showDialog<bool>(
                  context: context,
                  builder:
                      (context) => AlertDialog(
                        title: const Text('Xác nhận gán giao dịch'),
                        content: const Text(
                          'Bạn có chắc chắn muốn gán giao dịch này cho công nợ?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Hủy'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Đồng ý'),
                          ),
                        ],
                      ),
                );
                if (confirm == true) {
                  d.sourceType = type;
                  d.sourceId = picked;
                  await context.read<DebtProvider>().update(d);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Đã gán giao dịch cho công nợ'),
                    ),
                  );
                }
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
                final deleted = await context.read<DebtProvider>().deleteDebt(d.id);
                if (!context.mounted) return;
                if (!deleted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Không được xóa công nợ của hóa đơn còn nợ. Vui lòng trả/tất toán.')),
                  );
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa công nợ')));
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
                          _buildAssignmentChip(d),
                          if ((d.sourceType ?? '').trim().isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                d.sourceType == 'sale' ? 'Bán hàng' : (d.sourceType == 'purchase' ? 'Nhập hàng' : d.sourceType!),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),

                      const SizedBox(height: 2),

                      FutureBuilder<double>(
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

                        // Settle button
                        GestureDetector(
                          onTap: d.amount <= 0 ? null : () => _settleDebt(context, d, currency),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Icon(Icons.done_all, size: 18, color: d.amount <= 0 ? Colors.grey : Colors.orange),
                          ),
                        ),

                        const SizedBox(width: 6),

                        // Summary button
                        GestureDetector(
                          onTap: () => _openPartySummary(context, d),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(Icons.analytics_outlined, size: 18, color: Colors.blueGrey),
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
