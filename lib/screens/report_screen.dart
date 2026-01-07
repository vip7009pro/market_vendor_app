import 'package:excel/excel.dart' as ex;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cross_file/cross_file.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';

import '../models/debt.dart';
import '../providers/sale_provider.dart';
import '../providers/debt_provider.dart';
import '../providers/product_provider.dart';
import '../services/database_service.dart';
import '../utils/file_helper.dart';
import 'debt_screen.dart';
import 'expense_screen.dart';
import 'inventory_report_screen.dart';

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

enum _KpiBackdataKind {
  triple,
  cash,
  bank,
  outstanding,
}

class _KpiBackdataScreen extends StatefulWidget {
  final _KpiBackdataKind kind;
  final DateTimeRange dateRange;
  final String? employeeId;
  const _KpiBackdataScreen({
    required this.kind,
    required this.dateRange,
    required this.employeeId,
  });

  @override
  State<_KpiBackdataScreen> createState() => _KpiBackdataScreenState();
}

class _KpiBackdataScreenState extends State<_KpiBackdataScreen> {
  bool _exporting = false;
  final ScrollController _hScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  String _title() {
    switch (widget.kind) {
      case _KpiBackdataKind.triple:
        return 'Backdata Doanh thu / Vốn / Lợi nhuận';
      case _KpiBackdataKind.cash:
        return 'Backdata Thu tiền mặt';
      case _KpiBackdataKind.bank:
        return 'Backdata Thu chuyển khoản';
      case _KpiBackdataKind.outstanding:
        return 'Backdata Nợ bán hàng';
    }
  }

  String _rangeLabel() {
    final fmt = DateFormat('dd/MM/yyyy');
    return '${fmt.format(widget.dateRange.start)} - ${fmt.format(widget.dateRange.end)}';
  }

  ex.CellValue? _cv(Object? v) {
    if (v == null) return null;
    if (v is ex.CellValue) return v;
    if (v is bool) return ex.BoolCellValue(v);
    if (v is int) return ex.IntCellValue(v);
    if (v is double) return ex.DoubleCellValue(v);
    if (v is num) return ex.DoubleCellValue(v.toDouble());
    return ex.TextCellValue(v.toString());
  }

  Future<List<Map<String, dynamic>>> _loadRows() async {
    final start = DateTime(widget.dateRange.start.year, widget.dateRange.start.month, widget.dateRange.start.day);
    final end = DateTime(widget.dateRange.end.year, widget.dateRange.end.month, widget.dateRange.end.day, 23, 59, 59, 999);
    final employeeId = (widget.employeeId ?? '').trim();
    final db = DatabaseService.instance.db;

    if (widget.kind == _KpiBackdataKind.triple) {
      final rows = await db.rawQuery(
        '''
        SELECT
          s.id as saleId,
          s.createdAt as saleCreatedAt,
          s.customerName as customerName,
          s.employeeId as employeeId,
          s.employeeName as employeeName,
          si.productId as productId,
          si.name as productName,
          si.unitPrice as unitPrice,
          si.quantity as quantity,
          si.unit as unit,
          si.unitCost as unitCost
        FROM sale_items si
        JOIN sales s ON s.id = si.saleId
        WHERE s.createdAt >= ? AND s.createdAt <= ?
        ${employeeId.isEmpty ? '' : 'AND s.employeeId = ?'}
        ORDER BY s.createdAt DESC
        ''',
        employeeId.isEmpty
            ? [start.toIso8601String(), end.toIso8601String()]
            : [start.toIso8601String(), end.toIso8601String(), employeeId],
      );

      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    }

    if (widget.kind == _KpiBackdataKind.cash || widget.kind == _KpiBackdataKind.bank) {
      // Must match ReportScreen._loadPayStats:
      // - Take sales in dateRange (and optional employee filter)
      // - Classify cash vs bank by paymentType == 'cash' else bank
      // - Add ALL debt payments for debts of those sales (NO date filter on debt payments)
      final isCash = widget.kind == _KpiBackdataKind.cash;

      final salePaid = await db.rawQuery(
        '''
        SELECT
          s.id as saleId,
          s.createdAt as createdAt,
          s.customerName as customerName,
          s.employeeId as employeeId,
          s.employeeName as employeeName,
          s.paidAmount as amount,
          s.paymentType as paymentType,
          'sale' as source
        FROM sales s
        WHERE s.createdAt >= ? AND s.createdAt <= ?
          AND COALESCE(s.paidAmount, 0) > 0
          AND (
            (? = 1 AND LOWER(COALESCE(s.paymentType, '')) = 'cash')
            OR
            (? = 0 AND LOWER(COALESCE(s.paymentType, '')) != 'cash')
          )
          ${employeeId.isEmpty ? '' : 'AND s.employeeId = ?'}
        ORDER BY s.createdAt DESC
        ''',
        employeeId.isEmpty
            ? [start.toIso8601String(), end.toIso8601String(), isCash ? 1 : 0, isCash ? 1 : 0]
            : [start.toIso8601String(), end.toIso8601String(), isCash ? 1 : 0, isCash ? 1 : 0, employeeId],
      );

      final debtPaid = await db.rawQuery(
        '''
        SELECT
          d.sourceId as saleId,
          p.createdAt as createdAt,
          d.partyName as customerName,
          s.employeeId as employeeId,
          s.employeeName as employeeName,
          p.amount as amount,
          p.paymentType as paymentType,
          'debt' as source
        FROM debt_payments p
        JOIN debts d ON d.id = p.debtId
        JOIN sales s ON s.id = d.sourceId
        WHERE d.sourceType = 'sale'
          AND s.createdAt >= ? AND s.createdAt <= ?
          AND (
            (? = 1 AND LOWER(COALESCE(p.paymentType, '')) = 'cash')
            OR
            (? = 0 AND LOWER(COALESCE(p.paymentType, '')) != 'cash')
          )
          ${employeeId.isEmpty ? '' : 'AND s.employeeId = ?'}
        ORDER BY p.createdAt DESC
        ''',
        employeeId.isEmpty
            ? [start.toIso8601String(), end.toIso8601String(), isCash ? 1 : 0, isCash ? 1 : 0]
            : [start.toIso8601String(), end.toIso8601String(), isCash ? 1 : 0, isCash ? 1 : 0, employeeId],
      );

      final merged = <Map<String, dynamic>>[];
      merged.addAll(salePaid.map((e) => Map<String, dynamic>.from(e)));
      merged.addAll(debtPaid.map((e) => Map<String, dynamic>.from(e)));
      merged.sort((a, b) {
        final at = DateTime.tryParse((a['createdAt'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = DateTime.tryParse((b['createdAt'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      return merged;
    }

    // outstanding: Must match ReportScreen._loadPayStats outstandingDebt
    // - Only sales in dateRange (and optional employee)
    // - Debts for those sales
    // - remain = debt.amount - sum(all payments)
    final rows = await db.rawQuery(
      '''
      SELECT
        s.id as saleId,
        s.createdAt as saleCreatedAt,
        s.customerName as customerName,
        s.employeeId as employeeId,
        s.employeeName as employeeName,
        d.id as debtId,
        d.amount as debtAmount,
        COALESCE(SUM(p.amount), 0) as paidAmount
      FROM sales s
      JOIN debts d ON d.sourceType = 'sale' AND d.sourceId = s.id
      LEFT JOIN debt_payments p ON p.debtId = d.id
      WHERE s.createdAt >= ? AND s.createdAt <= ?
        ${employeeId.isEmpty ? '' : 'AND s.employeeId = ?'}
      GROUP BY s.id, s.createdAt, s.customerName, s.employeeId, s.employeeName, d.id, d.amount
      HAVING (d.amount - COALESCE(SUM(p.amount), 0)) > 0
      ORDER BY s.createdAt DESC
      ''',
      employeeId.isEmpty
          ? [start.toIso8601String(), end.toIso8601String()]
          : [start.toIso8601String(), end.toIso8601String(), employeeId],
    );
    return rows.map((e) {
      final m = Map<String, dynamic>.from(e);
      final debtAmount = (m['debtAmount'] as num?)?.toDouble() ?? 0.0;
      final paidAmount = (m['paidAmount'] as num?)?.toDouble() ?? 0.0;
      m['remain'] = (debtAmount - paidAmount);
      return m;
    }).toList();
  }

  Future<Map<String, double>> _computeTotals(List<Map<String, dynamic>> rows) async {
    if (widget.kind == _KpiBackdataKind.triple) {
      double sell = 0;
      double cost = 0;
      for (final r in rows) {
        final unitPrice = (r['unitPrice'] as num?)?.toDouble() ?? 0.0;
        final qty = (r['quantity'] as num?)?.toDouble() ?? 0.0;
        final unitCost = (r['unitCost'] as num?)?.toDouble() ?? 0.0;
        sell += unitPrice * qty;
        cost += unitCost * qty;
      }
      return {
        'sell': sell,
        'cost': cost,
        'profit': sell - cost,
      };
    }

    if (widget.kind == _KpiBackdataKind.outstanding) {
      final remain = rows.fold<double>(0.0, (p, e) => p + ((e['remain'] as num?)?.toDouble() ?? 0.0));
      return {
        'total': remain,
      };
    }

    final total = rows.fold<double>(0.0, (p, e) => p + ((e['amount'] as num?)?.toDouble() ?? 0.0));
    return {
      'total': total,
    };
  }

  Future<void> _exportExcel(List<Map<String, dynamic>> rows) async {
    setState(() => _exporting = true);
    try {
      final excel = ex.Excel.createExcel();
      excel.delete('Sheet1');
      final sheet = excel['backdata'];

      if (widget.kind == _KpiBackdataKind.triple) {
        sheet.appendRow([
          _cv('Ngày'),
          _cv('Khách'),
          _cv('Sản phẩm'),
          _cv('Đơn giá'),
          _cv('Thành tiền'),
          _cv('Giá vốn'),
          _cv('Tiền vốn'),
          _cv('Lợi nhuận'),
        ]);
        for (final r in rows) {
          final createdAt = (r['saleCreatedAt'] ?? '').toString();
          final dt = DateTime.tryParse(createdAt);
          final dateLabel = dt == null ? createdAt : DateFormat('dd/MM/yyyy').format(dt);
          final customer = (r['customerName'] ?? '').toString();
          final name = (r['productName'] ?? '').toString();
          final unitPrice = (r['unitPrice'] as num?)?.toDouble() ?? 0.0;
          final qty = (r['quantity'] as num?)?.toDouble() ?? 0.0;
          final unitCost = (r['unitCost'] as num?)?.toDouble() ?? 0.0;
          final lineTotal = unitPrice * qty;
          final lineCost = unitCost * qty;
          final profit = lineTotal - lineCost;
          sheet.appendRow([
            _cv(dateLabel),
            _cv(customer),
            _cv(name),
            _cv(unitPrice),
            _cv(lineTotal),
            _cv(unitCost),
            _cv(lineCost),
            _cv(profit),
          ]);
        }
      } else if (widget.kind == _KpiBackdataKind.outstanding) {
        sheet.appendRow([
          _cv('Ngày'),
          _cv('Khách'),
          _cv('SaleId'),
          _cv('DebtId'),
          _cv('Còn nợ'),
        ]);
        for (final r in rows) {
          final createdAt = (r['saleCreatedAt'] ?? '').toString();
          final dt = DateTime.tryParse(createdAt);
          final dateLabel = dt == null ? createdAt : DateFormat('dd/MM/yyyy').format(dt);
          sheet.appendRow([
            _cv(dateLabel),
            _cv(r['customerName']),
            _cv(r['saleId']),
            _cv(r['debtId']),
            _cv(r['remain']),
          ]);
        }
      } else {
        sheet.appendRow([
          _cv('Ngày'),
          _cv('Khách'),
          _cv('SaleId'),
          _cv('Nguồn'),
          _cv('Hình thức'),
          _cv('Số tiền'),
        ]);
        for (final r in rows) {
          final createdAt = (r['createdAt'] ?? '').toString();
          final dt = DateTime.tryParse(createdAt);
          final dateLabel = dt == null ? createdAt : DateFormat('dd/MM/yyyy').format(dt);
          sheet.appendRow([
            _cv(dateLabel),
            _cv(r['customerName']),
            _cv(r['saleId']),
            _cv(r['source']),
            _cv(r['paymentType']),
            _cv(r['amount']),
          ]);
        }
      }

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Không thể tạo file Excel');
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'backdata_$ts.xlsx';
      final filePath = await FileHelper.saveBytesToDownloads(bytes: bytes, fileName: fileName);
      if (filePath == null || filePath.trim().isEmpty) {
        throw Exception('Không thể lưu file Excel');
      }

      if (!mounted) return;
      await Share.shareXFiles([
        XFile(filePath),
      ], text: '${_title()} (${_rangeLabel()})');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã xuất: $fileName'),
          action: SnackBarAction(
            label: 'Mở',
            onPressed: () {
              OpenFilex.open(filePath);
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  List<String> _columns() {
    if (widget.kind == _KpiBackdataKind.triple) {
      return const ['Ngày', 'Khách', 'Sản phẩm', 'Đơn giá', 'Thành tiền', 'Giá vốn', 'Tiền vốn', 'Lợi nhuận'];
    }
    if (widget.kind == _KpiBackdataKind.outstanding) {
      return const ['Ngày', 'Khách', 'SaleId', 'DebtId', 'Còn nợ'];
    }
    return const ['Ngày', 'Khách', 'SaleId', 'Nguồn', 'Hình thức', 'Số tiền'];
  }

  List<List<String>> _rowsAsStrings(List<Map<String, dynamic>> rows, NumberFormat currency) {
    if (widget.kind == _KpiBackdataKind.triple) {
      return rows.map((r) {
        final createdAt = (r['saleCreatedAt'] ?? '').toString();
        final dt = DateTime.tryParse(createdAt);
        final dateLabel = dt == null ? createdAt : DateFormat('dd/MM/yyyy').format(dt);
        final unitPrice = (r['unitPrice'] as num?)?.toDouble() ?? 0.0;
        final qty = (r['quantity'] as num?)?.toDouble() ?? 0.0;
        final unitCost = (r['unitCost'] as num?)?.toDouble() ?? 0.0;
        final lineTotal = unitPrice * qty;
        final lineCost = unitCost * qty;
        final profit = lineTotal - lineCost;
        return [
          dateLabel,
          (r['customerName'] ?? '').toString(),
          (r['productName'] ?? '').toString(),
          currency.format(unitPrice),
          currency.format(lineTotal),
          currency.format(unitCost),
          currency.format(lineCost),
          currency.format(profit),
        ];
      }).toList();
    }

    if (widget.kind == _KpiBackdataKind.outstanding) {
      return rows.map((r) {
        final createdAt = (r['saleCreatedAt'] ?? '').toString();
        final dt = DateTime.tryParse(createdAt);
        final dateLabel = dt == null ? createdAt : DateFormat('dd/MM/yyyy').format(dt);
        final remain = (r['remain'] as num?)?.toDouble() ?? 0.0;
        return [
          dateLabel,
          (r['customerName'] ?? '').toString(),
          (r['saleId'] ?? '').toString(),
          (r['debtId'] ?? '').toString(),
          currency.format(remain),
        ];
      }).toList();
    }

    return rows.map((r) {
      final createdAt = (r['createdAt'] ?? '').toString();
      final dt = DateTime.tryParse(createdAt);
      final dateLabel = dt == null ? createdAt : DateFormat('dd/MM/yyyy').format(dt);
      final amount = (r['amount'] as num?)?.toDouble() ?? 0.0;
      return [
        dateLabel,
        (r['customerName'] ?? '').toString(),
        (r['saleId'] ?? '').toString(),
        (r['source'] ?? '').toString(),
        (r['paymentType'] ?? '').toString(),
        currency.format(amount),
      ];
    }).toList();
  }

  List<double> _calcWidths({required List<String> headers, required List<List<String>> rows}) {
    final maxChars = List<int>.filled(headers.length, 0);
    for (var i = 0; i < headers.length; i++) {
      maxChars[i] = headers[i].trim().length;
    }
    final sampleCount = rows.length > 80 ? 80 : rows.length;
    for (var r = 0; r < sampleCount; r++) {
      final row = rows[r];
      for (var i = 0; i < headers.length && i < row.length; i++) {
        final len = row[i].trim().length;
        if (len > maxChars[i]) maxChars[i] = len;
      }
    }

    double wFor(int chars, {double min = 70, double max = 320}) {
      final w = (chars * 7.4) + 28;
      if (w < min) return min;
      if (w > max) return max;
      return w;
    }

    return List<double>.generate(headers.length, (i) {
      final h = headers[i].toLowerCase();
      if (h.contains('saleid') || h.contains('debtid')) return wFor(maxChars[i], min: 80, max: 100);
      if (h.contains('ngày')) return 100;
      if (h.contains('khách')) return wFor(maxChars[i], min: 80, max: 150);
      if (h.contains('sản phẩm')) return wFor(maxChars[i], min: 180, max: 360);
      if (h.contains('hình thức') || h.contains('nguồn')) return wFor(maxChars[i], min: 50, max: 100);
      if (h.contains('tiền') || h.contains('giá') || h.contains('thành') || h.contains('lợi') || h.contains('còn')) {
        return wFor(maxChars[i], min: 110, max: 160);
      }
      return wFor(maxChars[i]);
    });
  }

  bool _isNumericColumn(String header) {
    final h = header.toLowerCase();
    return h.contains('tiền') || h.contains('giá') || h.contains('thành') || h.contains('lợi') || h.contains('còn') || h.contains('số');
  }

  Widget _buildCell({required String text, required double width, required bool isHeader, required TextAlign align, required TextStyle style}) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: style,
        ),
      ),
    );
  }

  Widget _buildPrettyTable({required List<String> headers, required List<List<String>> bodyRows, required List<double> widths}) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.onPrimary,
        ) ??
        TextStyle(fontWeight: FontWeight.w800, color: theme.colorScheme.onPrimary);
    final cellStyle = theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        ) ??
        TextStyle(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface);

    final header = Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: List.generate(headers.length, (i) {
          final align = _isNumericColumn(headers[i]) ? TextAlign.right : TextAlign.left;
          return _buildCell(
            text: headers[i],
            width: widths[i],
            isHeader: true,
            align: align,
            style: headerStyle,
          );
        }),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor.withAlpha(120)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            header,
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: bodyRows.length,
                itemBuilder: (context, index) {
                  final r = bodyRows[index];
                  final zebra = index.isEven;
                  final bg = zebra ? theme.colorScheme.surface : theme.colorScheme.surfaceContainerHighest;
                  return Container(
                    color: bg,
                    child: Row(
                      children: List.generate(headers.length, (i) {
                        final v = (i < r.length) ? r[i] : '';
                        final align = _isNumericColumn(headers[i]) ? TextAlign.right : TextAlign.left;
                        return _buildCell(
                          text: v,
                          width: widths[i],
                          isHeader: false,
                          align: align,
                          style: cellStyle,
                        );
                      }),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    return Scaffold(
      appBar: AppBar(
        title: Text(_title()),
        actions: [
          IconButton(
            tooltip: 'Xuất / Share Excel',
            onPressed: _exporting
                ? null
                : () async {
                    final rows = await _loadRows();
                    if (!mounted) return;
                    await _exportExcel(rows);
                  },
            icon: _exporting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _loadRows(),
        builder: (context, snap) {
          final rows = snap.data ?? const <Map<String, dynamic>>[];
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return FutureBuilder<Map<String, double>>(
            future: _computeTotals(rows),
            builder: (context, totalSnap) {
              final totals = totalSnap.data ?? const <String, double>{};
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Khoảng: ${_rangeLabel()}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        if (widget.kind == _KpiBackdataKind.triple) ...[
                          Text('Doanh thu: ${currency.format(totals['sell'] ?? 0)}'),
                          Text('Vốn: ${currency.format(totals['cost'] ?? 0)}'),
                          Text('Lợi nhuận: ${currency.format(totals['profit'] ?? 0)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        ] else ...[
                          Text('Tổng: ${currency.format(totals['total'] ?? 0)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: rows.isEmpty
                        ? const Center(child: Text('Chưa có dữ liệu'))
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final tableHeight = constraints.maxHeight;
                                final headers = _columns();
                                final body = _rowsAsStrings(rows, currency);
                                final widths = _calcWidths(headers: headers, rows: body);
                                final minTableWidth = MediaQuery.of(context).size.width - 24;
                                final sumWidth = widths.fold<double>(0.0, (p, e) => p + e);
                                final tableWidth = (sumWidth < minTableWidth) ? minTableWidth : sumWidth;

                                return Scrollbar(
                                  controller: _hScroll,
                                  child: SingleChildScrollView(
                                    controller: _hScroll,
                                    scrollDirection: Axis.horizontal,
                                    child: SizedBox(
                                      height: tableHeight,
                                      width: tableWidth,
                                      child: _buildPrettyTable(headers: headers, bodyRows: body, widths: widths),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _PaymentMetricTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final double value;
  final NumberFormat currency;
  final List<Color> gradientColors;
  final String? tooltip;
  final VoidCallback? onTap;
  const _PaymentMetricTile({
    required this.title,
    required this.icon,
    required this.value,
    required this.currency,
    required this.gradientColors,
    this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: Colors.white),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              currency.format(value),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
    final wrapped = (tooltip == null || tooltip!.trim().isEmpty) ? child : Tooltip(message: tooltip!, child: child);
    if (onTap == null) return wrapped;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: wrapped,
    );
  }
}

class _InventoryMetricTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final double qty;
  final double amountCost;
  final double amountSell;
  final NumberFormat currency;
  final List<Color> gradientColors;
  final String? tooltip;
  final VoidCallback? onTap;
  const _InventoryMetricTile({
    required this.title,
    required this.icon,
    required this.qty,
    required this.amountCost,
    required this.amountSell,
    required this.currency,
    required this.gradientColors,
    this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final qtyText = qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2);
    final child = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: Colors.white),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'SL: $qtyText',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            'GV: ${currency.format(amountCost)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            'GB: ${currency.format(amountSell)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ],
      ),
    );
    final wrapped = (tooltip == null || tooltip!.trim().isEmpty) ? child : Tooltip(message: tooltip!, child: child);
    if (onTap == null) return wrapped;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: wrapped,
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
  bool _hasScrolled = false;

  @override
  void didUpdateWidget(covariant _AutoScrollToEnd oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.signature != oldWidget.signature) {
      _hasScrolled = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollToEndProperly() {
    if (_hasScrolled || !_controller.hasClients) return;

    final double maxExtent = _controller.position.maxScrollExtent;
    if (maxExtent <= 0) {
      _hasScrolled = true;
      return;
    }

    // Nhảy đúng tới cuối, cột cuối sát mép phải
    _controller.animateTo(
      maxExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );

    _hasScrolled = true;
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_hasScrolled) {
          _scrollToEndProperly();
        }
      });
    });
    return widget.builder(_controller);
  }
}

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  DateTimeRange _dateRange = (() {
    final now = DateTime.now();
    return DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: now,
    );
  })();
  String? _selectedEmployeeId;
  List<Map<String, dynamic>> _employees = const [];

  final PageController _chartPageController = PageController(initialPage: 0);
  final ValueNotifier<int> _chartPageIndex = ValueNotifier<int>(0);
  final PageController _netChartPageController = PageController(initialPage: 0);
  final ValueNotifier<int> _netChartPageIndex = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEmployees();
    });
  }

  Future<void> _loadEmployees() async {
    try {
      final rows = await DatabaseService.instance.getEmployees();
      if (!mounted) return;
      setState(() {
        _employees = rows;
      });
    } catch (_) {
      // ignore
    }
  }

  Future<void> _pickEmployeeFilter() async {
    final rows = await DatabaseService.instance.getEmployees();
    if (!mounted) return;

    final picked = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: rows.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              if (i == 0) {
                final selected = _selectedEmployeeId == null;
                return ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: const Text('Tất cả nhân viên'),
                  trailing: selected ? const Icon(Icons.check, color: Colors.green) : null,
                  onTap: () => Navigator.pop(ctx, null),
                );
              }
              final r = rows[i - 1];
              final id = (r['id']?.toString() ?? '').trim();
              final name = (r['name']?.toString() ?? '').trim();
              final selected = id.isNotEmpty && id == (_selectedEmployeeId ?? '').trim();
              return ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(name.isEmpty ? id : name),
                subtitle: Text(id),
                trailing: selected ? const Icon(Icons.check, color: Colors.green) : null,
                onTap: () => Navigator.pop(ctx, id),
              );
            },
          ),
        );
      },
    );

    if (!mounted) return;
    setState(() {
      _selectedEmployeeId = (picked ?? '').trim().isEmpty ? null : picked;
    });
  }

  ex.CellValue? _cv(Object? v) {
    if (v == null) return null;
    if (v is ex.CellValue) return v;
    if (v is bool) return ex.BoolCellValue(v);
    if (v is int) return ex.IntCellValue(v);
    if (v is double) return ex.DoubleCellValue(v);
    if (v is num) return ex.DoubleCellValue(v.toDouble());
    return ex.TextCellValue(v.toString());
  }

  Future<void> _exportAllSheetsExcel(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Expanded(child: Text('Đang xuất Excel...')),
            ],
          ),
        ),
      );
      final monthYear = DateTime(_dateRange.start.year, _dateRange.start.month);
      final monthStart = DateTime(monthYear.year, monthYear.month, 1);
      final monthEnd = DateTime(monthYear.year, monthYear.month + 1, 0, 23, 59, 59, 999);
      final db = DatabaseService.instance.db;
      final customers = await DatabaseService.instance.getCustomersForSync();
      final productsRows = await db.query(
        'products',
        where: 'isActive = 1',
        orderBy: 'name ASC',
      );
      final productsById = <String, Map<String, dynamic>>{
        for (final p in productsRows) (p['id'] as String): p,
      };
      final debts = await DatabaseService.instance.getDebtsForSync();
      final debtPayments = await DatabaseService.instance.getDebtPaymentsForSync(range: _dateRange);
      final purchases = await db.query(
        'purchase_history',
        orderBy: 'createdAt DESC',
      );
      final rangeStart = DateTime(_dateRange.start.year, _dateRange.start.month, _dateRange.start.day);
      final rangeEnd = DateTime(_dateRange.end.year, _dateRange.end.month, _dateRange.end.day, 23, 59, 59, 999);
      final purchasesInRange = await DatabaseService.instance.getPurchaseHistory(
        range: DateTimeRange(start: rangeStart, end: rangeEnd),
      );
      final saleItemsInRange = await db.rawQuery(
        '''
        SELECT
          s.id as saleId,
          s.createdAt as saleCreatedAt,
          s.customerName as customerName,
          s.employeeId as employeeId,
          s.employeeName as employeeName,
          si.productId as productId,
          si.name as name,
          si.unit as unit,
          si.unitPrice as unitPrice,
          si.quantity as quantity,
          si.unitCost as unitCost,
          si.itemType as itemType,
          si.mixItemsJson as mixItemsJson
        FROM sale_items si
        JOIN sales s ON s.id = si.saleId
        WHERE s.createdAt >= ? AND s.createdAt <= ?
        ORDER BY s.createdAt DESC
        ''',
        [rangeStart.toIso8601String(), rangeEnd.toIso8601String()],
      );
      final saleSubtotalRowsInRange = await db.rawQuery(
        '''
        SELECT
          s.id as saleId,
          SUM(si.unitPrice * si.quantity) as subtotal
        FROM sales s
        JOIN sale_items si ON si.saleId = s.id
        WHERE s.createdAt >= ? AND s.createdAt <= ?
        GROUP BY s.id
        ''',
        [rangeStart.toIso8601String(), rangeEnd.toIso8601String()],
      );
      final saleSubtotalById = <String, double>{};
      for (final r in saleSubtotalRowsInRange) {
        final sid = (r['saleId']?.toString() ?? '').trim();
        if (sid.isEmpty) continue;
        saleSubtotalById[sid] = (r['subtotal'] as num?)?.toDouble() ?? 0.0;
      }
      final expenses = await db.query(
        'expenses',
        where: 'occurredAt >= ? AND occurredAt <= ?',
        whereArgs: [rangeStart.toIso8601String(), rangeEnd.toIso8601String()],
        orderBy: 'occurredAt DESC',
      );
      final sales = await DatabaseService.instance.getSalesForSync();
      final saleItems = await db.query('sale_items');
      final saleById = <String, Map<String, dynamic>>{
        for (final s in sales) (s['id'] as String): s,
      };
      final openingRows = await db.query(
        'product_opening_stocks',
        where: 'year = ? AND month = ?',
        whereArgs: [monthYear.year, monthYear.month],
      );
      final openingByProductId = <String, double>{
        for (final r in openingRows)
          (r['productId'] as String): (r['openingStock'] as num?)?.toDouble() ?? 0,
      };
      final importQtyByProductId = <String, double>{};
      final exportQtyByProductId = <String, double>{};
      for (final pr in purchases) {
        final createdAt = DateTime.tryParse(pr['createdAt'] as String? ?? '');
        if (createdAt == null) continue;
        if (createdAt.isBefore(monthStart) || createdAt.isAfter(monthEnd)) continue;
        final pid = pr['productId'] as String;
        final qty = (pr['quantity'] as num?)?.toDouble() ?? 0;
        importQtyByProductId[pid] = (importQtyByProductId[pid] ?? 0) + qty;
      }
      for (final it in saleItems) {
        final saleId = it['saleId'] as String?;
        if (saleId == null) continue;
        final sale = saleById[saleId];
        if (sale == null) continue;
        final createdAt = DateTime.tryParse(sale['createdAt'] as String? ?? '');
        if (createdAt == null) continue;
        if (createdAt.isBefore(monthStart) || createdAt.isAfter(monthEnd)) continue;
        final pid = it['productId'] as String?;
        if (pid == null) continue;
        final qty = (it['quantity'] as num?)?.toDouble() ?? 0;
        exportQtyByProductId[pid] = (exportQtyByProductId[pid] ?? 0) + qty;
      }
      final excel = ex.Excel.createExcel();
      excel.delete('Sheet1');
      final customersSheet = excel['list khách hàng'];
      customersSheet.appendRow([
        _cv('id'),
        _cv('name'),
        _cv('phone'),
        _cv('note'),
        _cv('isSupplier'),
        _cv('updatedAt'),
        _cv('deviceId'),
        _cv('isSynced'),
      ]);
      for (final c in customers) {
        customersSheet.appendRow([
          _cv(c['id']),
          _cv(c['name']),
          _cv(c['phone']),
          _cv(c['note']),
          _cv(c['isSupplier']),
          _cv(c['updatedAt']),
          _cv(c['deviceId']),
          _cv(c['isSynced']),
        ]);
      }
      final productsSheet = excel['list sản phẩm'];
      productsSheet.appendRow([
        _cv('id'),
        _cv('name'),
        _cv('unit'),
        _cv('barcode'),
        _cv('price'),
        _cv('costPrice'),
        _cv('currentStock'),
        _cv('isActive'),
        _cv('updatedAt'),
        _cv('deviceId'),
        _cv('isSynced'),
      ]);
      for (final p in productsRows) {
        productsSheet.appendRow([
          _cv(p['id']),
          _cv(p['name']),
          _cv(p['unit']),
          _cv(p['barcode']),
          _cv(p['price']),
          _cv(p['costPrice']),
          _cv(p['currentStock']),
          _cv(p['isActive']),
          _cv(p['updatedAt']),
          _cv(p['deviceId']),
          _cv(p['isSynced']),
        ]);
      }
      final debtsSheet = excel['list công nợ'];
      debtsSheet.appendRow([
        _cv('id'),
        _cv('customerId'),
        _cv('customerName'),
        _cv('amount'),
        _cv('createdAt'),
        _cv('dueDate'),
        _cv('note'),
        _cv('isPaid'),
        _cv('paidAt'),
        _cv('updatedAt'),
        _cv('sourceType'),
        _cv('sourceId'),
      ]);
      for (final d in debts) {
        debtsSheet.appendRow([
          _cv(d['id']),
          _cv(d['customerId']),
          _cv(d['customerName']),
          _cv(d['amount']),
          _cv(d['createdAt']),
          _cv(d['dueDate']),
          _cv(d['note']),
          _cv(d['isPaid']),
          _cv(d['paidAt']),
          _cv(d['updatedAt']),
          _cv(d['sourceType']),
          _cv(d['sourceId']),
        ]);
      }
      final debtPaymentsSheet = excel['lịch sử trả nợ'];
      debtPaymentsSheet.appendRow([
        _cv('paymentId'),
        _cv('debtId'),
        _cv('debtType'),
        _cv('partyId'),
        _cv('partyName'),
        _cv('amount'),
        _cv('paymentType'),
        _cv('note'),
        _cv('createdAt'),
        _cv('isSynced'),
      ]);
      for (final p in debtPayments) {
        debtPaymentsSheet.appendRow([
          _cv(p['paymentId']),
          _cv(p['debtId']),
          _cv(p['debtType']),
          _cv(p['partyId']),
          _cv(p['partyName']),
          _cv(p['amount']),
          _cv(p['paymentType']),
          _cv(p['note']),
          _cv(p['createdAt']),
          _cv(p['isSynced']),
        ]);
      }
      final expensesSheet = excel['list chi phí'];
      expensesSheet.appendRow([
        _cv('id'),
        _cv('occurredAt'),
        _cv('amount'),
        _cv('category'),
        _cv('note'),
        _cv('expenseDocUploaded'),
        _cv('expenseDocFileId'),
        _cv('expenseDocUpdatedAt'),
        _cv('updatedAt'),
      ]);
      for (final e in expenses) {
        expensesSheet.appendRow([
          _cv(e['id']),
          _cv(e['occurredAt']),
          _cv(e['amount']),
          _cv(e['category']),
          _cv(e['note']),
          _cv(e['expenseDocUploaded']),
          _cv(e['expenseDocFileId']),
          _cv(e['expenseDocUpdatedAt']),
          _cv(e['updatedAt']),
        ]);
      }
      final purchaseHistorySheet = excel['lịch sử nhập kho'];
      purchaseHistorySheet.appendRow([
        _cv('id'),
        _cv('createdAt'),
        _cv('productId'),
        _cv('productName'),
        _cv('unit'),
        _cv('quantity'),
        _cv('unitCost'),
        _cv('totalCost'),
        _cv('supplierName'),
        _cv('supplierPhone'),
        _cv('note'),
      ]);
      for (final ph in purchasesInRange) {
        final pid = ph['productId'] as String;
        final prod = productsById[pid];
        purchaseHistorySheet.appendRow([
          _cv(ph['id']),
          _cv(ph['createdAt']),
          _cv(pid),
          _cv(ph['productName']),
          _cv(prod?['unit']),
          _cv(ph['quantity']),
          _cv(ph['unitCost']),
          _cv(ph['totalCost']),
          _cv(ph['supplierName']),
          _cv(ph['supplierPhone']),
          _cv(ph['note']),
        ]);
      }
      final exportHistorySheet = excel['lịch sử xuất kho'];
      exportHistorySheet.appendRow([
        _cv('saleId'),
        _cv('saleCreatedAt'),
        _cv('customerName'),
        _cv('employeeId'),
        _cv('employeeName'),
        _cv('productId'),
        _cv('productName'),
        _cv('unit'),
        _cv('quantity'),
        _cv('unitPriceSnap'),
        _cv('lineTotalSnap'),
        _cv('unitCostSnap'),
        _cv('lineCostTotalSnap'),
        _cv('source'),
      ]);
      for (final r in saleItemsInRange) {
        final itemType = (r['itemType']?.toString() ?? '').toUpperCase().trim();
        if (itemType == 'MIX') {
          final raw = (r['mixItemsJson']?.toString() ?? '').trim();
          if (raw.isEmpty) continue;
          try {
            final decoded = jsonDecode(raw);
            if (decoded is List) {
              final mixQty = (r['quantity'] as num?)?.toDouble() ?? 0.0;
              final mixUnitPrice = (r['unitPrice'] as num?)?.toDouble() ?? 0.0;
              final mixLineTotal = mixQty * mixUnitPrice;

              double rawSellTotal = 0.0;
              for (final e in decoded) {
                if (e is! Map) continue;
                final rid = (e['rawProductId']?.toString() ?? '').trim();
                if (rid.isEmpty) continue;
                final rq = (e['rawQty'] as num?)?.toDouble() ?? 0.0;
                if (rq <= 0) continue;
                final prod = productsById[rid];
                final rawPrice = (prod?['price'] as num?)?.toDouble() ?? 0.0;
                rawSellTotal += rq * rawPrice;
              }
              final factor = (rawSellTotal <= 0) ? 0.0 : (mixLineTotal / rawSellTotal);

              for (final e in decoded) {
                if (e is Map) {
                  final rid = (e['rawProductId']?.toString() ?? '').trim();
                  if (rid.isEmpty) continue;
                  final rq = (e['rawQty'] as num?)?.toDouble() ?? 0.0;
                  final ruc = (e['rawUnitCost'] as num?)?.toDouble() ?? 0.0;

                  final prod = productsById[rid];
                  final rawPrice = (prod?['price'] as num?)?.toDouble() ?? 0.0;
                  final unitPriceSnap = rawPrice * factor;
                  final lineTotalSnap = unitPriceSnap * rq;

                  exportHistorySheet.appendRow([
                    _cv(r['saleId']),
                    _cv(r['saleCreatedAt']),
                    _cv(r['customerName']),
                    _cv(r['employeeId']),
                    _cv(r['employeeName']),
                    _cv(rid),
                    _cv(e['rawName']),
                    _cv(e['rawUnit']),
                    _cv(rq),
                    _cv(unitPriceSnap),
                    _cv(lineTotalSnap),
                    _cv(ruc),
                    _cv(rq * ruc),
                    _cv('MIX'),
                  ]);
                }
              }
            }
          } catch (_) {
            continue;
          }
        } else {
          final pid = (r['productId']?.toString() ?? '').trim();
          if (pid.isEmpty) continue;
          final qty = (r['quantity'] as num?)?.toDouble() ?? 0.0;
          final unitPriceSnap = (r['unitPrice'] as num?)?.toDouble() ?? 0.0;
          final lineTotalSnap = unitPriceSnap * qty;
          final unitCostSnap = (r['unitCost'] as num?)?.toDouble() ?? 0.0;
          exportHistorySheet.appendRow([
            _cv(r['saleId']),
            _cv(r['saleCreatedAt']),
            _cv(r['customerName']),
            _cv(r['employeeId']),
            _cv(r['employeeName']),
            _cv(pid),
            _cv(r['name']),
            _cv(r['unit']),
            _cv(qty),
            _cv(unitPriceSnap),
            _cv(lineTotalSnap),
            _cv(unitCostSnap),
            _cv(qty * unitCostSnap),
            _cv('RAW'),
          ]);
        }
      }
      final purchaseSheet = excel['list nhập hàng'];
      purchaseSheet.appendRow([
        _cv('id'),
        _cv('createdAt'),
        _cv('productId'),
        _cv('productName'),
        _cv('productUnit'),
        _cv('quantity'),
        _cv('unitCost'),
        _cv('totalCost'),
        _cv('supplierName'),
        _cv('supplierPhone'),
        _cv('note'),
        _cv('updatedAt'),
      ]);
      for (final ph in purchases) {
        final pid = ph['productId'] as String;
        final prod = productsById[pid];
        purchaseSheet.appendRow([
          _cv(ph['id']),
          _cv(ph['createdAt']),
          _cv(pid),
          _cv(ph['productName']),
          _cv(prod?['unit']),
          _cv(ph['quantity']),
          _cv(ph['unitCost']),
          _cv(ph['totalCost']),
          _cv(ph['supplierName']),
          _cv(ph['supplierPhone']),
          _cv(ph['note']),
          _cv(ph['updatedAt']),
        ]);
      }
      final saleSheet = excel['list xuất hàng'];
      saleSheet.appendRow([
        _cv('saleId'),
        _cv('saleCreatedAt'),
        _cv('customerId'),
        _cv('customerName'),
        _cv('employeeId'),
        _cv('employeeName'),
        _cv('saleDiscount'),
        _cv('salePaidAmount'),
        _cv('salePaymentType'),
        _cv('saleTotalCost'),
        _cv('saleNote'),
        _cv('productId'),
        _cv('productName'),
        _cv('productUnit'),
        _cv('unitPrice'),
        _cv('quantity'),
        _cv('lineTotal'),
        _cv('unitCostSnap'),
        _cv('lineCostTotalSnap'),
      ]);
      for (final it in saleItems) {
        final saleId = it['saleId'] as String?;
        if (saleId == null) continue;
        final sale = saleById[saleId];
        if (sale == null) continue;
        final pid = it['productId'] as String?;
        final prod = pid == null ? null : productsById[pid];
        final unitPrice = (it['unitPrice'] as num?)?.toDouble() ?? 0;
        final qty = (it['quantity'] as num?)?.toDouble() ?? 0;
        final lineTotal = unitPrice * qty;
        final unitCostSnap = (it['unitCost'] as num?)?.toDouble() ?? 0.0;
        final lineCostTotalSnap = unitCostSnap * qty;
        saleSheet.appendRow([
          _cv(saleId),
          _cv(sale['createdAt']),
          _cv(sale['customerId']),
          _cv(sale['customerName']),
          _cv(sale['employeeId']),
          _cv(sale['employeeName']),
          _cv(sale['discount']),
          _cv(sale['paidAmount']),
          _cv(sale['paymentType']),
          _cv(sale['totalCost']),
          _cv(sale['note']),
          _cv(pid),
          _cv(it['name']),
          _cv(prod?['unit'] ?? it['unit']),
          _cv(unitPrice),
          _cv(qty),
          _cv(lineTotal),
          _cv(unitCostSnap),
          _cv(lineCostTotalSnap),
        ]);
      }
      final listOrdersSheet = excel['list đơn hàng'];
      listOrdersSheet.appendRow([
        _cv('saleId'),
        _cv('saleCreatedAt'),
        _cv('customerId'),
        _cv('customerName'),
        _cv('employeeId'),
        _cv('employeeName'),
        _cv('saleDiscount'),
        _cv('salePaidAmount'),
        _cv('salePaidCash'),
        _cv('salePaidBank'),
        _cv('salePaidUnset'),
        _cv('salePaymentType'),
        _cv('saleTotalCost'),
        _cv('saleNote'),
        _cv('saleTotal'),
        _cv('debtPaidCash'),
        _cv('debtPaidBank'),
        _cv('debtPaidUnset'),
        _cv('debtPaidTotal'),
        _cv('debtNotPaid'),
        _cv('totalPaidCash'),
        _cv('totalPaidBank'),
        _cv('totalPaidUnset'),
        _cv('totalPaid'),
      ]);
      // Debt stats by saleId (for list đơn hàng)
      final saleIdsInRangeForDebt = <String>[];
      for (final s in sales) {
        final createdAt = DateTime.tryParse(s['createdAt'] as String? ?? '');
        if (createdAt == null) continue;
        if (createdAt.isBefore(rangeStart) || createdAt.isAfter(rangeEnd)) continue;
        final sid = (s['id']?.toString() ?? '').trim();
        if (sid.isEmpty) continue;
        saleIdsInRangeForDebt.add(sid);
      }
      final debtPaidCashBySaleId = <String, double>{};
      final debtPaidBankBySaleId = <String, double>{};
      final debtPaidUnsetBySaleId = <String, double>{};
      final debtPaidTotalBySaleId = <String, double>{};
      final debtRemainBySaleId = <String, double>{};
      if (saleIdsInRangeForDebt.isNotEmpty) {
        final placeholders = List.filled(saleIdsInRangeForDebt.length, '?').join(',');
        final debtRows = await db.query(
          'debts',
          columns: ['id', 'amount', 'sourceId'],
          where: "sourceType = 'sale' AND sourceId IN ($placeholders)",
          whereArgs: saleIdsInRangeForDebt,
        );
        final debtIdToSaleId = <String, String>{};
        final debtIds = <String>[];
        final debtAmountById = <String, double>{};
        for (final d in debtRows) {
          final did = (d['id']?.toString() ?? '').trim();
          final sid = (d['sourceId']?.toString() ?? '').trim();
          if (did.isEmpty) continue;
          debtIds.add(did);
          if (sid.isNotEmpty) {
            debtIdToSaleId[did] = sid;
          }
          debtAmountById[did] = (d['amount'] as num?)?.toDouble() ?? 0.0;
        }
        if (debtIds.isNotEmpty) {
          final dph = List.filled(debtIds.length, '?').join(',');
          final payAgg = await db.rawQuery(
            '''
            SELECT
              debtId as debtId,
              SUM(CASE WHEN paymentType = 'cash' THEN amount ELSE 0 END) as paidCash,
              SUM(CASE WHEN paymentType = 'bank' THEN amount ELSE 0 END) as paidBank,
              SUM(CASE WHEN paymentType IS NULL OR TRIM(paymentType) = '' THEN amount ELSE 0 END) as paidUnset,
              SUM(amount) as paidTotal
            FROM debt_payments
            WHERE debtId IN ($dph)
            GROUP BY debtId
            ''',
            debtIds,
          );
          for (final r in payAgg) {
            final did = (r['debtId']?.toString() ?? '').trim();
            final sid = debtIdToSaleId[did];
            if (sid == null || sid.isEmpty) continue;
            final paidCash = (r['paidCash'] as num?)?.toDouble() ?? 0.0;
            final paidBank = (r['paidBank'] as num?)?.toDouble() ?? 0.0;
            final paidUnset = (r['paidUnset'] as num?)?.toDouble() ?? 0.0;
            final paidTotal = (r['paidTotal'] as num?)?.toDouble() ?? 0.0;
            debtPaidCashBySaleId[sid] = (debtPaidCashBySaleId[sid] ?? 0) + paidCash;
            debtPaidBankBySaleId[sid] = (debtPaidBankBySaleId[sid] ?? 0) + paidBank;
            debtPaidUnsetBySaleId[sid] = (debtPaidUnsetBySaleId[sid] ?? 0) + paidUnset;
            debtPaidTotalBySaleId[sid] = (debtPaidTotalBySaleId[sid] ?? 0) + paidTotal;
          }
        }
      }
      for (final s in sales) {
        final createdAt = DateTime.tryParse(s['createdAt'] as String? ?? '');
        if (createdAt == null) continue;
        if (createdAt.isBefore(rangeStart) || createdAt.isAfter(rangeEnd)) continue;
        final discount = (s['discount'] as num?)?.toDouble() ?? 0.0;
        final saleId = (s['id']?.toString() ?? '').trim();
        if (saleId.isEmpty) continue;
        final subtotal = saleSubtotalById[saleId] ?? 0.0;
        final total = (subtotal - discount).clamp(0.0, double.infinity).toDouble();

        final salePaidAmount = (s['paidAmount'] as num?)?.toDouble() ?? 0.0;
        final salePaymentType = (s['paymentType']?.toString() ?? '').trim().toLowerCase();
        final salePaidCash = salePaymentType == 'cash' ? salePaidAmount : 0.0;
        final salePaidBank = salePaymentType == 'bank' ? salePaidAmount : 0.0;
        final salePaidUnset = (salePaymentType.isEmpty || (salePaymentType != 'cash' && salePaymentType != 'bank'))
            ? salePaidAmount
            : 0.0;

        final debtPaidCash = debtPaidCashBySaleId[saleId] ?? 0.0;
        final debtPaidBank = debtPaidBankBySaleId[saleId] ?? 0.0;
        final debtPaidUnset = debtPaidUnsetBySaleId[saleId] ?? 0.0;
        final debtPaidTotal = debtPaidTotalBySaleId[saleId] ?? 0.0;
        final debtNotPaid = debtRemainBySaleId[saleId] ?? 0.0;

        final totalPaidCash = salePaidCash + debtPaidCash;
        final totalPaidBank = salePaidBank + debtPaidBank;
        final totalPaidUnset = salePaidUnset + debtPaidUnset;
        final totalPaid = totalPaidCash + totalPaidBank + totalPaidUnset;
        listOrdersSheet.appendRow([
          _cv(saleId),
          _cv(s['createdAt']),
          _cv(s['customerId']),
          _cv(s['customerName']),
          _cv(s['employeeId']),
          _cv(s['employeeName']),
          _cv(discount),
          _cv(salePaidAmount),
          _cv(salePaidCash),
          _cv(salePaidBank),
          _cv(salePaidUnset),
          _cv(salePaymentType),
          _cv(s['totalCost']),
          _cv(s['note']),
          _cv(total),
          _cv(debtPaidCash),
          _cv(debtPaidBank),
          _cv(debtPaidUnset),
          _cv(debtPaidTotal),
          _cv(debtNotPaid),
          _cv(totalPaidCash),
          _cv(totalPaidBank),
          _cv(totalPaidUnset),
          _cv(totalPaid),
        ]);
      }
      final tripleBackdataSheet = excel['backdata_triple_kpi'];
      tripleBackdataSheet.appendRow([
        _cv('saleId'),
        _cv('saleCreatedAt'),
        _cv('employeeId'),
        _cv('employeeName'),
        _cv('customerName'),
        _cv('subtotal'),
        _cv('discount'),
        _cv('total'),
        _cv('paidAmount'),
        _cv('paymentType'),
        _cv('saleTotalCost'),
      ]);
      for (final s in sales) {
        final createdAt = DateTime.tryParse(s['createdAt'] as String? ?? '');
        if (createdAt == null) continue;
        if (createdAt.isBefore(rangeStart) || createdAt.isAfter(rangeEnd)) continue;
        final discount = (s['discount'] as num?)?.toDouble() ?? 0.0;
        final saleId = (s['id']?.toString() ?? '').trim();
        if (saleId.isEmpty) continue;
        final subtotal = saleSubtotalById[saleId] ?? 0.0;
        final total = (subtotal - discount).clamp(0.0, double.infinity).toDouble();
        tripleBackdataSheet.appendRow([
          _cv(saleId),
          _cv(s['createdAt']),
          _cv(s['employeeId']),
          _cv(s['employeeName']),
          _cv(s['customerName']),
          _cv(subtotal),
          _cv(discount),
          _cv(total),
          _cv(s['paidAmount']),
          _cv(s['paymentType']),
          _cv(s['totalCost']),
        ]);
      }
      final paymentPaidSheet = excel['backdata_payment_paid_amount'];
      paymentPaidSheet.appendRow([
        _cv('saleId'),
        _cv('saleCreatedAt'),
        _cv('employeeId'),
        _cv('employeeName'),
        _cv('paidAmount'),
        _cv('paymentType'),
      ]);
      final paymentDebtPaidSheet = excel['backdata_payment_debt_paid'];
      paymentDebtPaidSheet.appendRow([
        _cv('saleId'),
        _cv('employeeId'),
        _cv('employeeName'),
        _cv('debtId'),
        _cv('paidCash'),
        _cv('paidBank'),
        _cv('paidUnset'),
        _cv('paidTotal'),
      ]);
      final paymentOutstandingSheet = excel['backdata_payment_outstanding_sale_debt'];
      paymentOutstandingSheet.appendRow([
        _cv('saleId'),
        _cv('employeeId'),
        _cv('employeeName'),
        _cv('debtId'),
        _cv('remain'),
      ]);
      final paymentOutstandingSaSheet = excel['backdata_payment_outstanding_sa'];
      paymentOutstandingSaSheet.appendRow([
        _cv('saleId'),
        _cv('employeeId'),
        _cv('employeeName'),
        _cv('debtId'),
        _cv('remain'),
      ]);
      final saleRowsInRange = await db.query(
        'sales',
        columns: ['id', 'createdAt', 'paidAmount', 'paymentType', 'employeeId', 'employeeName'],
        where: 'createdAt >= ? AND createdAt <= ?',
        whereArgs: [rangeStart.toIso8601String(), rangeEnd.toIso8601String()],
      );
      final empBySaleId = <String, Map<String, Object?>>{};
      final saleIdsInRange = <String>[];
      for (final r in saleRowsInRange) {
        final sid = (r['id']?.toString() ?? '').trim();
        if (sid.isNotEmpty) saleIdsInRange.add(sid);
        empBySaleId[sid] = {
          'employeeId': r['employeeId'],
          'employeeName': r['employeeName'],
        };
        final paid = (r['paidAmount'] as num?)?.toDouble() ?? 0.0;
        paymentPaidSheet.appendRow([
          _cv(sid),
          _cv(r['createdAt']),
          _cv(r['employeeId']),
          _cv(r['employeeName']),
          _cv(paid),
          _cv(r['paymentType']),
        ]);
      }
      if (saleIdsInRange.isNotEmpty) {
        final placeholders = List.filled(saleIdsInRange.length, '?').join(',');
        final debtsForSales = await db.query(
          'debts',
          columns: ['id', 'amount', 'sourceId'],
          where: "sourceType = 'sale' AND sourceId IN ($placeholders)",
          whereArgs: saleIdsInRange,
        );
        final debtIds = <String>[];
        final debtAmountById = <String, double>{};
        for (final d in debtsForSales) {
          final did = (d['id']?.toString() ?? '').trim();
          if (did.isEmpty) continue;
          debtIds.add(did);
          debtAmountById[did] = (d['amount'] as num?)?.toDouble() ?? 0.0;
        }
        if (debtIds.isNotEmpty) {
          final dph = List.filled(debtIds.length, '?').join(',');
          final payAgg = await db.rawQuery(
            '''
            SELECT
              d.id as debtId,
              d.sourceId as saleId,
              SUM(CASE WHEN dp.paymentType = 'cash' THEN dp.amount ELSE 0 END) as paidCash,
              SUM(CASE WHEN dp.paymentType = 'bank' THEN dp.amount ELSE 0 END) as paidBank,
              SUM(CASE WHEN dp.paymentType IS NULL OR TRIM(dp.paymentType) = '' THEN dp.amount ELSE 0 END) as paidUnset,
              SUM(dp.amount) as paidTotal
            FROM debts d
            LEFT JOIN debt_payments dp ON dp.debtId = d.id
            WHERE d.id IN ($dph)
            GROUP BY d.id, d.sourceId
            ''',
            debtIds,
          );
          for (final r in payAgg) {
            final did = (r['debtId']?.toString() ?? '').trim();
            final sid = (r['saleId']?.toString() ?? '').trim();
            if (did.isEmpty || sid.isEmpty) continue;
            final paidCash = (r['paidCash'] as num?)?.toDouble() ?? 0.0;
            final paidBank = (r['paidBank'] as num?)?.toDouble() ?? 0.0;
            final paidUnset = (r['paidUnset'] as num?)?.toDouble() ?? 0.0;
            final paidTotal = (r['paidTotal'] as num?)?.toDouble() ?? 0.0;
            final emp = empBySaleId[sid];
            paymentDebtPaidSheet.appendRow([
              _cv(sid),
              _cv(emp?['employeeId']),
              _cv(emp?['employeeName']),
              _cv(did),
              _cv(paidCash),
              _cv(paidBank),
              _cv(paidUnset),
              _cv(paidTotal),
            ]);
          }
          // Outstanding (align with widget 'Nợ' formula in _loadPayStats):
          // remain = debts.amount - SUM(debt_payments.amount) (no date filter)
          final payAggByDebt = await db.rawQuery(
            '''
            SELECT debtId as debtId, SUM(amount) as total
            FROM debt_payments
            WHERE debtId IN ($dph)
            GROUP BY debtId
            ''',
            debtIds,
          );
          final paidByDebtId = <String, double>{};
          for (final r in payAggByDebt) {
            final did = (r['debtId']?.toString() ?? '').trim();
            if (did.isEmpty) continue;
            paidByDebtId[did] = (r['total'] as num?)?.toDouble() ?? 0.0;
          }
          final saleIdByDebtId = <String, String>{};
          final amountByDebtId = <String, double>{};
          for (final d in debtsForSales) {
            final did = (d['id']?.toString() ?? '').trim();
            final sid = (d['sourceId']?.toString() ?? '').trim();
            if (did.isEmpty || sid.isEmpty) continue;
            saleIdByDebtId[did] = sid;
            amountByDebtId[did] = (d['amount'] as num?)?.toDouble() ?? 0.0;
          }
          for (final did in debtIds) {
            final sid = saleIdByDebtId[did];
            if (sid == null || sid.isEmpty) continue;
            final initial = amountByDebtId[did] ?? 0.0;
            final paid = paidByDebtId[did] ?? 0.0;
            final remain = (initial - paid);
            if (remain <= 0) continue;
            final emp = empBySaleId[sid];
            paymentOutstandingSheet.appendRow([
              _cv(sid),
              _cv(emp?['employeeId']),
              _cv(emp?['employeeName']),
              _cv(did),
              _cv(remain),
            ]);
            paymentOutstandingSaSheet.appendRow([
              _cv(sid),
              _cv(emp?['employeeId']),
              _cv(emp?['employeeName']),
              _cv(did),
              _cv(remain),
            ]);
          }
        }
      }
      final openingSheet = excel['list tồn đầu kỳ'];
      openingSheet.appendRow([
        _cv('year'),
        _cv('month'),
        _cv('productId'),
        _cv('productName'),
        _cv('productUnit'),
        _cv('openingStock'),
        _cv('updatedAt'),
      ]);
      for (final r in openingRows) {
        final pid = r['productId'] as String;
        final prod = productsById[pid];
        openingSheet.appendRow([
          _cv(r['year']),
          _cv(r['month']),
          _cv(pid),
          _cv(prod?['name']),
          _cv(prod?['unit']),
          _cv(r['openingStock']),
          _cv(r['updatedAt']),
        ]);
      }
      final endingSheet = excel['list tồn cuối kỳ'];
      endingSheet.appendRow([
        _cv('year'),
        _cv('month'),
        _cv('productId'),
        _cv('productName'),
        _cv('productUnit'),
        _cv('openingStock'),
        _cv('importQty'),
        _cv('exportQty'),
        _cv('endingQty'),
        _cv('costPrice'),
        _cv('endingAmountCost'),
        _cv('price'),
        _cv('endingAmountSell'),
      ]);
      final productIds = <String>{
        ...productsById.keys,
        ...openingByProductId.keys,
        ...importQtyByProductId.keys,
        ...exportQtyByProductId.keys,
      }.toList();
      productIds.sort((a, b) {
        final an = (productsById[a]?['name'] as String?) ?? '';
        final bn = (productsById[b]?['name'] as String?) ?? '';
        return an.compareTo(bn);
      });
      for (final pid in productIds) {
        final prod = productsById[pid];
        final opening = openingByProductId[pid] ?? 0;
        final importQty = importQtyByProductId[pid] ?? 0;
        final exportQty = exportQtyByProductId[pid] ?? 0;
        final endingQty = opening + importQty - exportQty;
        final costPrice = (prod?['costPrice'] as num?)?.toDouble() ?? 0;
        final price = (prod?['price'] as num?)?.toDouble() ?? 0;
        endingSheet.appendRow([
          _cv(monthYear.year),
          _cv(monthYear.month),
          _cv(pid),
          _cv(prod?['name']),
          _cv(prod?['unit']),
          _cv(opening),
          _cv(importQty),
          _cv(exportQty),
          _cv(endingQty),
          _cv(costPrice),
          _cv(endingQty * costPrice),
          _cv(price),
          _cv(endingQty * price),
        ]);
      }
      final bytes = excel.encode();
      if (bytes == null) {
        throw Exception('Không thể tạo file Excel');
      }
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'bao_cao_tong_hop_$ts.xlsx';
      final filePath = await FileHelper.saveBytesToDownloads(
        bytes: bytes,
        fileName: fileName,
      );
      if (filePath == null) {
        throw Exception('Không thể lưu file vào Downloads');
      }
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text('Đã xuất Excel: $fileName'),
            action: SnackBarAction(
              label: 'Mở',
              onPressed: () {
                OpenFilex.open(filePath);
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        messenger.showSnackBar(
          SnackBar(content: Text('Lỗi xuất Excel: $e')),
        );
      }
    }
  }

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

  Future<_PayStats> _loadPayStats({required DateTime start, required DateTime end, String? employeeId}) async {
    final db = DatabaseService.instance.db;
    String? where;
    final whereArgs = <Object?>[];
    where = 'createdAt >= ? AND createdAt <= ?';
    whereArgs.addAll([start.toIso8601String(), end.toIso8601String()]);
    final eid = (employeeId ?? '').trim();
    if (eid.isNotEmpty) {
      where = '$where AND employeeId = ?';
      whereArgs.add(eid);
    }
    final saleRows = await db.query(
      'sales',
      columns: ['id', 'paidAmount', 'paymentType'],
      where: where,
      whereArgs: whereArgs,
    );
    double cash = 0;
    double bank = 0;
    final saleIds = <String>[];

    for (final r in saleRows) {
      final sid = (r['id']?.toString() ?? '').trim();
      if (sid.isNotEmpty) saleIds.add(sid);
      final paid = (r['paidAmount'] as num?)?.toDouble() ?? 0.0;
      if (paid <= 0) continue;
      final t = (r['paymentType']?.toString() ?? '').trim().toLowerCase();
      if (t == 'cash') {
        cash += paid;
      } else {
        bank += paid;
      }
    }
    if (saleIds.isEmpty) {
      return const _PayStats(cashRevenue: 0, bankRevenue: 0, outstandingDebt: 0);
    }
    final placeholders = List.filled(saleIds.length, '?').join(',');
    final debtsForSales = await db.query(
      'debts',
      columns: ['id', 'amount', 'sourceId'],
      where: "sourceType = 'sale' AND sourceId IN ($placeholders)",
      whereArgs: saleIds,
    );
    final debtIds = <String>[];
    final debtAmountById = <String, double>{};
    for (final d in debtsForSales) {
      final did = (d['id']?.toString() ?? '').trim();
      if (did.isEmpty) continue;
      debtIds.add(did);
      debtAmountById[did] = (d['amount'] as num?)?.toDouble() ?? 0.0;
    }

    double outstanding = 0.0;
    if (debtIds.isNotEmpty) {
      final dph = List.filled(debtIds.length, '?').join(',');

      // 1) Sum payments by paymentType to add into cash/bank revenue.
      final payAggByType = await db.rawQuery(
        '''
        SELECT paymentType as paymentType, SUM(amount) as total
        FROM debt_payments
        WHERE debtId IN ($dph)
        GROUP BY paymentType
        ''',
        debtIds,
      );
      for (final r in payAggByType) {
        final total = (r['total'] as num?)?.toDouble() ?? 0.0;
        if (total <= 0) continue;
        final t = (r['paymentType']?.toString() ?? '').trim().toLowerCase();
        if (t == 'cash') {
          cash += total;
        } else {
          bank += total;
        }
      }

      // 2) Sum payments per debt to compute outstanding.
      final payAggByDebt = await db.rawQuery(
        '''
        SELECT debtId as debtId, SUM(amount) as total
        FROM debt_payments
        WHERE debtId IN ($dph)
        GROUP BY debtId
        ''',
        debtIds,
      );
      final paidByDebtId = <String, double>{};
      for (final r in payAggByDebt) {
        final did = (r['debtId']?.toString() ?? '').trim();
        if (did.isEmpty) continue;
        paidByDebtId[did] = (r['total'] as num?)?.toDouble() ?? 0.0;
      }

      for (final did in debtIds) {
        final initial = debtAmountById[did] ?? 0.0;
        final paid = paidByDebtId[did] ?? 0.0;
        final remain = (initial - paid);
        if (remain > 0) outstanding += remain;
      }
    }

    return _PayStats(cashRevenue: cash, bankRevenue: bank, outstandingDebt: outstanding);
  }

  @override
  void dispose() {
    _chartPageController.dispose();
    _chartPageIndex.dispose();
    _netChartPageController.dispose();
    _netChartPageIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    final sales = context.watch<SaleProvider>().sales;
    final products = context.watch<ProductProvider>().products;
    final debtsProvider = context.watch<DebtProvider>();

    final now = DateTime.now();

    final inRangeSales = sales.where((s) =>
        !s.createdAt.isBefore(DateTime(_dateRange.start.year, _dateRange.start.month, _dateRange.start.day)) &&
        !s.createdAt.isAfter(DateTime(_dateRange.end.year, _dateRange.end.month, _dateRange.end.day, 23, 59, 59))
    ).toList();

    final filteredSales = (_selectedEmployeeId == null)
        ? inRangeSales
        : inRangeSales.where((s) => (s.employeeId ?? '').trim() == (_selectedEmployeeId ?? '').trim()).toList();

    // Inventory overview must NOT be filtered by employee.
    final exportQty = inRangeSales.fold<double>(
      0,
      (p, s) => p + s.items.fold<double>(0, (p2, it) => p2 + it.quantity),
    );
    final exportAmount = inRangeSales.fold<double>(0, (p, s) => p + s.totalCost);
    final exportAmountSell = inRangeSales.fold<double>(0, (p, s) => p + s.total);

    final totalOweOthers = debtsProvider.totalOweOthers;
    final openOthersOweMe = debtsProvider.debts.where((d) => d.type == DebtType.othersOweMe && !d.settled).toList();
    final saleEmployeeBySaleId = <String, String>{
      for (final s in sales) (s.id): (s.employeeId ?? '').trim(),
    };
    final selectedEid = (_selectedEmployeeId ?? '').trim();
    final totalOthersOweMeFromSales = openOthersOweMe
        .where((d) {
          final okSale = (d.sourceType ?? '').trim() == 'sale' && (d.sourceId ?? '').trim().isNotEmpty;
          if (!okSale) return false;
          if (selectedEid.isEmpty) return true;
          final sid = (d.sourceId ?? '').trim();
          return saleEmployeeBySaleId[sid] == selectedEid;
        })
        .fold<double>(0.0, (p, d) => p + d.amount);

    final totalOthersOweMeOutside = openOthersOweMe
        .where((d) => (d.sourceType ?? '').trim() != 'sale' || (d.sourceId ?? '').trim().isEmpty)
        .fold<double>(0.0, (p, d) => p + d.amount);
    final totalOthersOweMe = totalOthersOweMeFromSales + totalOthersOweMeOutside;

    final start = DateTime(_dateRange.start.year, _dateRange.start.month, _dateRange.start.day);
    final end = DateTime(_dateRange.end.year, _dateRange.end.month, _dateRange.end.day, 23, 59, 59, 999);
    final periodRevenue = filteredSales.fold<double>(0, (p, s) => p + s.total);
    final periodCost = filteredSales.fold<double>(0, (p, s) => p + s.totalCost);
    final periodProfit = periodRevenue - periodCost;

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

    final topAgg = <String, _TopProductRow>{};
    for (final s in filteredSales) {
      for (final it in s.items) {
        final itemType = (it.itemType ?? '').toUpperCase().trim();
        final displayName = (itemType == 'MIX' && (it.displayName?.trim().isNotEmpty == true))
            ? it.displayName!.trim()
            : it.name;
        final key = it.productId.trim().isNotEmpty ? it.productId.trim() : displayName;
        final prev = topAgg[key];
        final nextQty = (prev?.qty ?? 0) + it.quantity;
        final nextAmount = (prev?.amount ?? 0) + (it.unitPrice * it.quantity);
        topAgg[key] = _TopProductRow(
          key: key,
          name: prev?.name ?? displayName,
          unit: prev?.unit ?? it.unit,
          qty: nextQty,
          amount: nextAmount,
        );
      }
    }
    final topProducts = topAgg.values.toList()
      ..sort((a, b) {
        final c = b.qty.compareTo(a.qty);
        if (c != 0) return c;
        return b.amount.compareTo(a.amount);
      });
    final topProductsLimited = topProducts.take(10).toList();

    final selectedEmployeeName = (_selectedEmployeeId == null)
        ? 'Tất cả'
        : (() {
            for (final r in _employees) {
              final id = (r['id']?.toString() ?? '').trim();
              if (id == (_selectedEmployeeId ?? '').trim()) {
                final name = (r['name']?.toString() ?? '').trim();
                return name.isEmpty ? id : name;
              }
            }
            return _selectedEmployeeId ?? '';
          })();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Báo cáo'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu),
            onSelected: (v) {
              if (v == 'export_excel') {
                _exportAllSheetsExcel(context);
              } else if (v == 'sales_history') {
                Navigator.of(context).pushNamed('/sales_history');
              } else if (v == 'debts_history') {
                Navigator.of(context).pushNamed('/debts_history');
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'export_excel',
                child: Text('Xuất Excel'),
              ),
              PopupMenuItem(
                value: 'sales_history',
                child: Text('Lịch sử bán'),
              ),
              PopupMenuItem(
                value: 'debts_history',
                child: Text('Lịch sử công nợ'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickEmployeeFilter,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.badge_outlined, size: 16),
                        label: Text(
                          selectedEmployeeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _selectDateRange(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(
                          '${DateFormat('dd/MM').format(_dateRange.start)} - ${DateFormat('dd/MM').format(_dateRange.end)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 14),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'Tổng quan kinh doanh',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: FutureBuilder<List<Object>>(
                      future: Future.wait([
                        DatabaseService.instance.db.query(
                          'expenses',
                          columns: ['amount', 'category', 'occurredAt'],
                          where: 'occurredAt >= ? AND occurredAt <= ?',
                          whereArgs: [start.toIso8601String(), end.toIso8601String()],
                        ),
                        _loadPayStats(
                          start: start,
                          end: end,
                          employeeId: _selectedEmployeeId,
                        ),
                      ]),
                      builder: (context, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const SizedBox(
                            height: 120,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        final data = snap.data;
                        final expenseRows = (data != null && data.isNotEmpty)
                            ? (data[0] as List<Map<String, dynamic>>)
                            : const <Map<String, dynamic>>[];
                        final payStats = (data != null && data.length > 1)
                            ? (data[1] as _PayStats)
                            : const _PayStats(cashRevenue: 0, bankRevenue: 0, outstandingDebt: 0);

                        double totalExpenseAll = 0.0;
                        double expenseOutsideBusiness = 0.0;
                        final expenseByCategory = <String, double>{};
                        for (final e in expenseRows) {
                          final cat = (e['category']?.toString() ?? '').trim();
                          final amount = (e['amount'] as num?)?.toDouble() ?? 0.0;
                          totalExpenseAll += amount;
                          if (cat == 'Chi tiêu ngoài kinh doanh') {
                            expenseOutsideBusiness += amount;
                            continue;
                          }
                          expenseByCategory[cat] = (expenseByCategory[cat] ?? 0) + amount;
                        }

                        final expenseReasonable = totalExpenseAll - expenseOutsideBusiness;
                        final netProfit = periodProfit - expenseReasonable;

                        final pieColors = <Color>[
                          const Color(0xFF2E7DFF),
                          const Color(0xFFFF8A00),
                          const Color(0xFF2E7D32),
                          const Color(0xFF6A1B9A),
                          const Color(0xFF0D47A1),
                          const Color(0xFF009688),
                          const Color(0xFF424242),
                          const Color(0xFFD81B60),
                        ];

                        final pieEntries = expenseByCategory.entries.toList()
                          ..sort((a, b) => b.value.compareTo(a.value));
                        final pieTotal = pieEntries.fold<double>(0.0, (p, e) => p + e.value);

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GridView.count(
                              crossAxisCount: 3,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 1.55,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              children: [
                                _PaymentMetricTile(
                                  title: 'Doanh thu',
                                  icon: Icons.payments_outlined,
                                  value: periodRevenue,
                                  currency: currency,
                                  gradientColors: const [Color(0xFF2E7DFF), Color(0xFF00C2FF)],
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => _KpiBackdataScreen(
                                          kind: _KpiBackdataKind.triple,
                                          dateRange: _dateRange,
                                          employeeId: _selectedEmployeeId,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                _PaymentMetricTile(
                                  title: 'Vốn',
                                  icon: Icons.inventory_2_outlined,
                                  value: periodCost,
                                  currency: currency,
                                  gradientColors: const [Color(0xFFFF8A00), Color(0xFFFFC107)],
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => _KpiBackdataScreen(
                                          kind: _KpiBackdataKind.triple,
                                          dateRange: _dateRange,
                                          employeeId: _selectedEmployeeId,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                _PaymentMetricTile(
                                  title: 'Lợi nhuận',
                                  icon: Icons.trending_up,
                                  value: periodProfit,
                                  currency: currency,
                                  gradientColors: const [Color(0xFF2E7D32), Color(0xFF00C853)],
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => _KpiBackdataScreen(
                                          kind: _KpiBackdataKind.triple,
                                          dateRange: _dateRange,
                                          employeeId: _selectedEmployeeId,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                _PaymentMetricTile(
                                  title: 'Thu TM',
                                  icon: Icons.attach_money,
                                  value: payStats.cashRevenue,
                                  currency: currency,
                                  gradientColors: const [Color(0xFF009688), Color(0xFF26A69A)],
                                  tooltip: 'Tiền mặt (bán + thu nợ) trong kỳ',
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => _KpiBackdataScreen(
                                          kind: _KpiBackdataKind.cash,
                                          dateRange: _dateRange,
                                          employeeId: _selectedEmployeeId,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                _PaymentMetricTile(
                                  title: 'Thu CK',
                                  icon: Icons.account_balance_outlined,
                                  value: payStats.bankRevenue,
                                  currency: currency,
                                  gradientColors: const [Color(0xFF3949AB), Color(0xFF5C6BC0)],
                                  tooltip: 'Chuyển khoản (bán + thu nợ) trong kỳ',
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => _KpiBackdataScreen(
                                          kind: _KpiBackdataKind.bank,
                                          dateRange: _dateRange,
                                          employeeId: _selectedEmployeeId,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                _PaymentMetricTile(
                                  title: 'Nợ bán hàng',
                                  icon: Icons.credit_card_off_outlined,
                                  value: payStats.outstandingDebt,
                                  currency: currency,
                                  gradientColors: const [Color(0xFF424242), Color(0xFF757575)],
                                  tooltip: 'Tổng nợ bán hàng còn lại (không lọc theo ngày thu nợ)',
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => _KpiBackdataScreen(
                                          kind: _KpiBackdataKind.outstanding,
                                          dateRange: _dateRange,
                                          employeeId: _selectedEmployeeId,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                _PaymentMetricTile(
                                  title: 'Tổng chi phí',
                                  icon: Icons.receipt_long_outlined,
                                  value: totalExpenseAll,
                                  currency: currency,
                                  gradientColors: const [Color(0xFF6A1B9A), Color(0xFFAB47BC)],
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const ExpenseScreen()),
                                    );
                                  },
                                ),
                                _PaymentMetricTile(
                                  title: 'Chi phí hợp lý',
                                  icon: Icons.fact_check_outlined,
                                  value: expenseReasonable,
                                  currency: currency,
                                  gradientColors: const [Color(0xFF7B1FA2), Color(0xFFBA68C8)],
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const ExpenseScreen()),
                                    );
                                  },
                                ),
                                _PaymentMetricTile(
                                  title: 'Chi phí ngoài kinh doanh',
                                  icon: Icons.local_mall_outlined,
                                  value: expenseOutsideBusiness,
                                  currency: currency,
                                  gradientColors: const [Color(0xFF455A64), Color(0xFF90A4AE)],
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const ExpenseScreen()),
                                    );
                                  },
                                ),
                                _PaymentMetricTile(
                                  title: 'Nợ phải trả',
                                  icon: Icons.call_received_outlined,
                                  value: totalOweOthers,
                                  currency: currency,
                                  gradientColors: const [Color(0xFFB71C1C), Color(0xFFFF5252)],
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const DebtScreen()),
                                    );
                                  },
                                ),
                                _PaymentMetricTile(
                                  title: 'Nợ phải thu',
                                  icon: Icons.call_made_outlined,
                                  value: totalOthersOweMe,
                                  currency: currency,
                                  gradientColors: const [Color(0xFF0D47A1), Color(0xFF42A5F5)],
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const DebtScreen()),
                                    );
                                  },
                                ),
                                _PaymentMetricTile(
                                  title: 'Lợi nhuận ròng',
                                  icon: Icons.trending_up,
                                  value: netProfit,
                                  currency: currency,
                                  gradientColors: const [Color(0xFF00695C), Color(0xFF26A69A)],
                                  tooltip: 'Lợi nhuận ròng = Lợi nhuận - Chi phí hợp lý',
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Card(
                              elevation: 2,
                              shadowColor: Colors.black.withAlpha(35),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.black.withAlpha(8)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Tỉ trọng chi phí',
                                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '(${DateFormat('dd/MM').format(_dateRange.start)} - ${DateFormat('dd/MM').format(_dateRange.end)})',
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 12),
                                    if (pieEntries.isEmpty || pieTotal <= 0)
                                      const SizedBox(
                                        height: 160,
                                        child: Center(child: Text('Chưa có dữ liệu')),
                                      )
                                    else
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          SizedBox(
                                            width: 180,
                                            height: 180,
                                            child: PieChart(
                                              PieChartData(
                                                sectionsSpace: 2,
                                                centerSpaceRadius: 44,
                                                sections: List.generate(pieEntries.length, (i) {
                                                  final e = pieEntries[i];
                                                  final percent = (e.value / pieTotal) * 100;
                                                  return PieChartSectionData(
                                                    value: e.value,
                                                    color: pieColors[i % pieColors.length],
                                                    radius: 54,
                                                    title: percent >= 12 ? '${percent.toStringAsFixed(0)}%' : '',
                                                    titleStyle: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.w900,
                                                      fontSize: 12,
                                                    ),
                                                  );
                                                }),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                for (var i = 0; i < pieEntries.length; i++)
                                                  Padding(
                                                    padding: const EdgeInsets.only(bottom: 8),
                                                    child: Row(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Container(
                                                          width: 12,
                                                          height: 12,
                                                          margin: const EdgeInsets.only(top: 3),
                                                          decoration: BoxDecoration(
                                                            color: pieColors[i % pieColors.length],
                                                            borderRadius: BorderRadius.circular(3),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Expanded(
                                                          child: Text(
                                                            pieEntries[i].key,
                                                            style: const TextStyle(fontWeight: FontWeight.w700),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Text(
                                                          currency.format(pieEntries[i].value),
                                                          style: const TextStyle(fontWeight: FontWeight.w800),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _buildTopProductsCard(
                      currency: currency,
                      dateRange: _dateRange,
                      rows: topProductsLimited,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'Tổng quan tồn kho',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _buildInventorySummary(
                      currency: currency,
                      dateRange: _dateRange,
                      products: products,
                      exportQty: exportQty,
                      exportAmount: exportAmount,
                      exportAmountSell: exportAmountSell,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'Biểu đồ doanh thu / vốn / lợi nhuận',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 360,
                    child: PageView(
                      controller: _chartPageController,
                      onPageChanged: (index) {
                        _chartPageIndex.value = index;
                      },
                      children: [
                        _buildChartCard(
                          title: 'Theo ngày (${_dateRange.start.day}/${_dateRange.start.month} - ${_dateRange.end.day}/${_dateRange.end.month})',
                          points: dailyData,
                          currency: currency,
                        ),
                        _buildChartCard(
                          title: 'Theo tháng (${now.year})',
                          points: monthlyDataPoints,
                          currency: currency,
                        ),
                        _buildChartCard(
                          title: 'Theo năm',
                          points: yearlyDataPoints,
                          currency: currency,
                          isYearly: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  ValueListenableBuilder<int>(
                    valueListenable: _chartPageIndex,
                    builder: (context, pageIndex, _) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(3, (i) {
                          final isActive = i == pageIndex;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: isActive ? 16 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: isActive ? Colors.blue : Colors.grey.shade400,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: DatabaseService.instance.db.query(
                        'expenses',
                        columns: ['amount', 'category', 'occurredAt'],
                        where: 'occurredAt >= ? AND occurredAt <= ?',
                        whereArgs: [start.toIso8601String(), end.toIso8601String()],
                      ),
                      builder: (context, snap) {
                        final rows = snap.data ?? const <Map<String, dynamic>>[];
                        final expenseByDay = <String, double>{};
                        final expenseByMonth = <int, double>{};
                        final expenseByYear = <int, double>{};
                        for (final e in rows) {
                          final occurredAt = DateTime.tryParse(e['occurredAt']?.toString() ?? '');
                          if (occurredAt == null) continue;
                          final amount = (e['amount'] as num?)?.toDouble() ?? 0.0;
                          final cat = (e['category']?.toString() ?? '').trim();
                          if (cat == 'Chi tiêu ngoài kinh doanh') continue;
                          final dayKey = DateFormat('dd/MM').format(occurredAt);
                          expenseByDay[dayKey] = (expenseByDay[dayKey] ?? 0) + amount;
                          expenseByMonth[occurredAt.month] = (expenseByMonth[occurredAt.month] ?? 0) + amount;
                          expenseByYear[occurredAt.year] = (expenseByYear[occurredAt.year] ?? 0) + amount;
                        }
                        final netDailyPoints = dailyData.map((p) {
                          final exp = expenseByDay[p.x] ?? 0.0;
                          final net = p.profit - exp;
                          return _Point(p.x, 0, cost: 0, profit: net);
                        }).toList();
                        final netMonthlyPoints = monthlyDataPoints.map((p) {
                          final m = int.tryParse(p.x) ?? 0;
                          final exp = expenseByMonth[m] ?? 0.0;
                          final net = p.profit - exp;
                          return _Point(p.x, 0, cost: 0, profit: net);
                        }).toList();
                        final netYearlyPoints = yearlyDataPoints.map((p) {
                          final y = int.tryParse(p.x) ?? 0;
                          final exp = expenseByYear[y] ?? 0.0;
                          final net = p.profit - exp;
                          return _Point(p.x, 0, cost: 0, profit: net);
                        }).toList();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Biểu đồ lợi nhuận ròng (Doanh - Vốn - Chi phí)',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 320,
                              child: PageView(
                                controller: _netChartPageController,
                                onPageChanged: (index) {
                                  _netChartPageIndex.value = index;
                                },
                                children: [
                                  _buildNetProfitChartCard(
                                    title: 'Theo ngày (${_dateRange.start.day}/${_dateRange.start.month} - ${_dateRange.end.day}/${_dateRange.end.month})',
                                    points: netDailyPoints,
                                    currency: currency,
                                  ),
                                  _buildNetProfitChartCard(
                                    title: 'Theo tháng (${now.year})',
                                    points: netMonthlyPoints,
                                    currency: currency,
                                  ),
                                  _buildNetProfitChartCard(
                                    title: 'Theo năm',
                                    points: netYearlyPoints,
                                    currency: currency,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            ValueListenableBuilder<int>(
                              valueListenable: _netChartPageIndex,
                              builder: (context, pageIndex, _) {
                                return Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: List.generate(3, (i) {
                                    final isActive = i == pageIndex;
                                    return AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      margin: const EdgeInsets.symmetric(horizontal: 4),
                                      width: isActive ? 16 : 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: isActive ? Colors.teal : Colors.grey.shade400,
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                    );
                                  }),
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopProductsCard({
    required NumberFormat currency,
    required DateTimeRange dateRange,
    required List<_TopProductRow> rows,
  }) {
    final maxQty = rows.isEmpty ? 0.0 : rows.map((e) => e.qty).reduce((a, b) => a > b ? a : b);
    return Card(
      elevation: 2,
      shadowColor: Colors.black.withAlpha(35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.black.withAlpha(8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Top hàng bán chạy', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
            const SizedBox(height: 6),
            Text(
              '(${DateFormat('dd/MM/yyyy').format(dateRange.start)} - ${DateFormat('dd/MM/yyyy').format(dateRange.end)})',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: Text('Chưa có dữ liệu')),
              )
            else
              Column(
                children: [
                  for (var i = 0; i < rows.length; i++)
                    Padding(
                      padding: EdgeInsets.only(bottom: i == rows.length - 1 ? 0 : 10),
                      child: _TopProductBarRow(
                        index: i + 1,
                        row: rows[i],
                        maxQty: maxQty,
                        currency: currency,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _formatCompactMoney(double value) {
    final abs = value.abs();
    final sign = value < 0 ? '-' : '';
    if (abs >= 1000000) {
      final v = abs / 1000000;
      if (v >= 10) {
        return '${sign}${v.floor()}M';
      }
      final t = (v * 10).floor() / 10;
      return '${sign}${t.toStringAsFixed(t % 1 == 0 ? 0 : 1)}M';
    }
    if (abs >= 1000) {
      final k = (abs / 1000).floor();
      return '${sign}${k}K';
    }
    return '${sign}${abs.toInt()}';
  }

  Widget _buildNetProfitChartCard({
    required String title,
    required List<_Point> points,
    required NumberFormat currency,
  }) {
    return Card(
      elevation: 2,
      shadowColor: Colors.black.withAlpha(35),
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
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Tính minWidth chính xác để tránh trắng thừa
                  const double barWidth = 16.0;
                  const double groupsSpace = 32.0;
                  const double margin = 40.0; // hai bên
                  final double calculatedWidth = (points.length * barWidth) +
                      ((points.isNotEmpty ? points.length - 1 : 0) * groupsSpace) +
                      margin;
                  final double chartWidth = calculatedWidth < constraints.maxWidth
                      ? constraints.maxWidth
                      : calculatedWidth;
                  return _AutoScrollToEnd(
                    signature: '$title-${points.length}-${points.isNotEmpty ? points.last.x : ''}',
                    builder: (controller) {
                      return SingleChildScrollView(
                        controller: controller,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: chartWidth,
                          height: constraints.maxHeight,
                          child: BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.start,
                              groupsSpace: groupsSpace,
                              minY: _getMinY(points),
                              maxY: _getMaxY(points),
                              barTouchData: BarTouchData(
                                enabled: true,
                                handleBuiltInTouches: false,
                                touchTooltipData: BarTouchTooltipData(
                                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                    final point = points[groupIndex];
                                    return BarTooltipItem(
                                      _formatCompactMoney(point.profit),
                                      const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 11,
                                      ),
                                    );
                                  },
                                  tooltipMargin: 8,
                                  tooltipRoundedRadius: 8,
                                  tooltipPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  getTooltipColor: (_) => Colors.black87,
                                  fitInsideHorizontally: true,
                                  fitInsideVertically: true,
                                ),
                              ),
                              gridData: FlGridData(show: true, drawVerticalLine: false),
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
                                    reservedSize: 38,
                                  ),
                                ),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 44,
                                    getTitlesWidget: (value, meta) {
                                      return Text(_formatCompactMoney(value), style: const TextStyle(fontSize: 10));
                                    },
                                  ),
                                ),
                                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              ),
                              barGroups: List.generate(
                                points.length,
                                (i) => BarChartGroupData(
                                  x: i,
                                  showingTooltipIndicators: const [0],
                                  barRods: [
                                    BarChartRodData(
                                      toY: points[i].profit,
                                      color: (points[i].profit >= 0 ? Colors.teal : Colors.red).withAlpha(191),
                                      width: 16,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ],
                                ),
                              ),
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

  Widget _buildChartCard({
    required String title,
    required List<_Point> points,
    required NumberFormat currency,
    bool isYearly = false,
  }) {
    return Card(
      elevation: 2,
      shadowColor: Colors.black.withAlpha(35),
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
              height: 280,
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
                              gridData: FlGridData(show: true, drawVerticalLine: false),
                              borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.withAlpha(51))),
                              titlesData: FlTitlesData(
                                show: true,
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 42,
                                    getTitlesWidget: (value, meta) {
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          points[value.toInt()].x,
                                          style: const TextStyle(fontSize: 10),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    },
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
                              barGroups: List.generate(
                                points.length,
                                (i) => BarChartGroupData(
                                  x: i,
                                  barsSpace: 2,
                                  barRods: [
                                    BarChartRodData(
                                      toY: points[i].y,
                                      color: Colors.blue.withAlpha(191),
                                      width: isYearly ? 16 : 12,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                    BarChartRodData(
                                      toY: points[i].cost,
                                      color: Colors.orange.withAlpha(191),
                                      width: isYearly ? 16 : 12,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                    BarChartRodData(
                                      toY: points[i].profit,
                                      color: (points[i].profit >= 0 ? Colors.green : Colors.red).withAlpha(191),
                                      width: isYearly ? 16 : 12,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ],
                                ),
                              ),
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

  Widget _buildInventorySummary({
    required NumberFormat currency,
    required DateTimeRange dateRange,
    required List products,
    required double exportQty,
    required double exportAmount,
    required double exportAmountSell,
  }) {
    final openingYear = dateRange.start.year;
    final openingMonth = dateRange.start.month;
    return FutureBuilder<List<Object>>(
      future: Future.wait([
        DatabaseService.instance.getOpeningStocksForMonth(openingYear, openingMonth),
        DatabaseService.instance.getPurchaseHistory(range: dateRange),
      ]),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
            height: 110,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snap.data;
        final openingMap = (data != null && data.isNotEmpty)
            ? (data[0] as Map<String, double>)
            : <String, double>{};
        final purchases = (data != null && data.length > 1)
            ? (data[1] as List<Map<String, dynamic>>)
            : <Map<String, dynamic>>[];

        double openingQty = 0;
        double openingAmount = 0;
        double openingAmountSell = 0;
        for (final p in products) {
          final pid = (p.id as String);
          final qty = openingMap[pid] ?? 0;
          openingQty += qty;
          final cost = (p.costPrice as double);
          openingAmount += qty * cost;
          final price = (p.price as double);
          openingAmountSell += qty * price;
        }

        final importQty = purchases.fold<double>(
          0,
          (p, r) => p + ((r['quantity'] as num?)?.toDouble() ?? 0),
        );
        final importAmount = purchases.fold<double>(
          0,
          (p, r) => p + ((r['totalCost'] as num?)?.toDouble() ?? 0),
        );

        final productsById = <String, dynamic>{
          for (final p in products) (p.id as String): p,
        };
        final importAmountSell = purchases.fold<double>(
          0,
          (p, r) {
            final pid = r['productId'] as String?;
            if (pid == null) return p;
            final prod = productsById[pid];
            if (prod == null) return p;
            final qty = ((r['quantity'] as num?)?.toDouble() ?? 0);
            final price = (prod.price as double);
            return p + (qty * price);
          },
        );

        final endingQty = openingQty + importQty - exportQty;
        final endingAmount = openingAmount + importAmount - exportAmount;
        final endingAmountSell = openingAmountSell + importAmountSell - exportAmountSell;

        return GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.55,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _InventoryMetricTile(
              title: 'Tồn đầu kỳ',
              icon: Icons.inventory_2_outlined,
              qty: openingQty,
              amountCost: openingAmount,
              amountSell: openingAmountSell,
              currency: currency,
              gradientColors: const [Color(0xFF1565C0), Color(0xFF42A5F5)],
              tooltip: 'SL + giá trị (GV/GB) tồn đầu kỳ',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const InventoryReportScreen()),
                );
              },
            ),
            _InventoryMetricTile(
              title: 'Nhập trong kỳ',
              icon: Icons.call_received_outlined,
              qty: importQty,
              amountCost: importAmount,
              amountSell: importAmountSell,
              currency: currency,
              gradientColors: const [Color(0xFF2E7D32), Color(0xFF66BB6A)],
              tooltip: 'SL + giá trị (GV/GB) nhập trong kỳ',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const InventoryReportScreen()),
                );
              },
            ),
            _InventoryMetricTile(
              title: 'Xuất trong kỳ',
              icon: Icons.call_made_outlined,
              qty: exportQty,
              amountCost: exportAmount,
              amountSell: exportAmountSell,
              currency: currency,
              gradientColors: const [Color(0xFFB71C1C), Color(0xFFFF5252)],
              tooltip: 'SL + giá trị (GV/GB) xuất trong kỳ',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const InventoryReportScreen()),
                );
              },
            ),
            _InventoryMetricTile(
              title: 'Tồn cuối kỳ',
              icon: Icons.inventory_outlined,
              qty: endingQty,
              amountCost: endingAmount,
              amountSell: endingAmountSell,
              currency: currency,
              gradientColors: const [Color(0xFF6A1B9A), Color(0xFFAB47BC)],
              tooltip: 'SL + giá trị (GV/GB) tồn cuối kỳ',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const InventoryReportScreen()),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _TopProductBarRow extends StatelessWidget {
  final int index;
  final _TopProductRow row;
  final double maxQty;
  final NumberFormat currency;
  const _TopProductBarRow({
    required this.index,
    required this.row,
    required this.maxQty,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final qtyText = row.qty.toStringAsFixed(row.qty % 1 == 0 ? 0 : 2);
    final factor = (maxQty <= 0) ? 0.0 : (row.qty / maxQty).clamp(0.0, 1.0).toDouble();
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
                row.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            Text('$qtyText ${row.unit}', style: valueStyle),
            const SizedBox(width: 10),
            Text(currency.format(row.amount), style: valueStyle),
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
                      Colors.blue.withAlpha(220),
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