import 'package:excel/excel.dart' as ex;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';

import '../models/debt.dart';
import '../providers/sale_provider.dart';
import '../providers/debt_provider.dart';
import '../providers/product_provider.dart';
import '../services/database_service.dart';
import '../utils/file_helper.dart';

// Helper class to store chart data points
class _Point {
  final String x;
  final double y;
  final double cost;
  final double profit;

  _Point(this.x, this.y, {required this.cost, required this.profit});
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

class _PaymentKpi extends StatelessWidget {
  final String title;
  final double totalRevenue;
  final _PayStats stats;
  final NumberFormat currency;
  final Color color;

  const _PaymentKpi({
    required this.title,
    required this.totalRevenue,
    required this.stats,
    required this.currency,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54);
    final valueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withAlpha(8)),
        color: color.withOpacity(0.06),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text('Tổng DT', style: labelStyle)),
              Text(currency.format(totalRevenue), style: valueStyle),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: Text('Tiền mặt', style: labelStyle)),
              Text(currency.format(stats.cashRevenue), style: valueStyle),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: Text('Chuyển khoản', style: labelStyle)),
              Text(currency.format(stats.bankRevenue), style: valueStyle),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: Text('Nợ chưa trả', style: labelStyle)),
              Text(currency.format(stats.outstandingDebt), style: valueStyle?.copyWith(color: Colors.redAccent)),
            ],
          ),
        ],
      ),
    );
  }
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

  final PageController _chartPageController = PageController(initialPage: 0);
  final ValueNotifier<int> _chartPageIndex = ValueNotifier<int>(0);

  final PageController _netChartPageController = PageController(initialPage: 0);
  final ValueNotifier<int> _netChartPageIndex = ValueNotifier<int>(0);

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
          si.productId as productId,
          si.name as name,
          si.unit as unit,
          si.quantity as quantity,
          si.itemType as itemType,
          si.mixItemsJson as mixItemsJson
        FROM sale_items si
        JOIN sales s ON s.id = si.saleId
        WHERE s.createdAt >= ? AND s.createdAt <= ?
        ORDER BY s.createdAt DESC
        ''',
        [rangeStart.toIso8601String(), rangeEnd.toIso8601String()],
      );

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
        _cv('productId'),
        _cv('productName'),
        _cv('unit'),
        _cv('quantity'),
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
              for (final e in decoded) {
                if (e is Map) {
                  final rid = (e['rawProductId']?.toString() ?? '').trim();
                  if (rid.isEmpty) continue;
                  exportHistorySheet.appendRow([
                    _cv(r['saleId']),
                    _cv(r['saleCreatedAt']),
                    _cv(r['customerName']),
                    _cv(rid),
                    _cv(e['rawName']),
                    _cv(e['rawUnit']),
                    _cv((e['rawQty'] as num?)?.toDouble() ?? 0.0),
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
          exportHistorySheet.appendRow([
            _cv(r['saleId']),
            _cv(r['saleCreatedAt']),
            _cv(r['customerName']),
            _cv(pid),
            _cv(r['name']),
            _cv(r['unit']),
            _cv((r['quantity'] as num?)?.toDouble() ?? 0.0),
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
        _cv('productCostPrice'),
        _cv('lineCostTotal'),
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
        final costPrice = (prod?['costPrice'] as num?)?.toDouble() ?? 0;
        final lineCostTotal = costPrice * qty;
        saleSheet.appendRow([
          _cv(saleId),
          _cv(sale['createdAt']),
          _cv(sale['customerId']),
          _cv(sale['customerName']),
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
          _cv(costPrice),
          _cv(lineCostTotal),
        ]);
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

  Future<_PayStats> _loadPayStats({required DateTime start, required DateTime end}) async {
    final db = DatabaseService.instance.db;

    final saleRows = await db.query(
      'sales',
      columns: ['id', 'paidAmount', 'paymentType'],
      where: 'createdAt >= ? AND createdAt <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
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
        // default: bank (including null/empty)
        bank += paid;
      }
    }

    if (saleIds.isEmpty) {
      return const _PayStats(cashRevenue: 0, bankRevenue: 0, outstandingDebt: 0);
    }

    final placeholders = List.filled(saleIds.length, '?').join(',');
    final debtsForSales = await db.query(
      'debts',
      columns: ['id', 'amount'],
      where: "sourceType = 'sale' AND sourceId IN ($placeholders)",
      whereArgs: saleIds,
    );

    double outstanding = 0;
    final debtIds = <String>[];
    for (final d in debtsForSales) {
      final did = (d['id']?.toString() ?? '').trim();
      if (did.isNotEmpty) debtIds.add(did);
      outstanding += (d['amount'] as num?)?.toDouble() ?? 0.0;
    }

    if (debtIds.isNotEmpty) {
      final dph = List.filled(debtIds.length, '?').join(',');
      final payAgg = await db.rawQuery(
        '''
        SELECT paymentType as paymentType, SUM(amount) as total
        FROM debt_payments
        WHERE debtId IN ($dph)
        GROUP BY paymentType
        ''',
        debtIds,
      );

      for (final r in payAgg) {
        final total = (r['total'] as num?)?.toDouble() ?? 0.0;
        if (total <= 0) continue;
        final t = (r['paymentType']?.toString() ?? '').trim().toLowerCase();
        if (t == 'cash') {
          cash += total;
        } else {
          // default: bank
          bank += total;
        }
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
    final startOfDay = DateTime(now.year, now.month, now.day);
    final startOfWeek = startOfDay.subtract(Duration(days: startOfDay.weekday - 1));
    final startOfMonth = DateTime(now.year, now.month, 1);
    final startOfYear = DateTime(now.year, 1, 1);

    // Filter sales by selected date range
    final filteredSales = sales.where((s) =>
        !s.createdAt.isBefore(DateTime(_dateRange.start.year, _dateRange.start.month, _dateRange.start.day)) &&
        !s.createdAt.isAfter(DateTime(_dateRange.end.year, _dateRange.end.month, _dateRange.end.day, 23, 59, 59))
    ).toList();

    final exportQty = filteredSales.fold<double>(
      0,
      (p, s) => p + s.items.fold<double>(0, (p2, it) => p2 + it.quantity),
    );
    final exportAmount = filteredSales.fold<double>(0, (p, s) => p + s.totalCost);

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
    final openOthersOweMe = debtsProvider.debts.where((d) => d.type == DebtType.othersOweMe && !d.settled).toList();
    final totalOthersOweMeFromSales = openOthersOweMe
        .where((d) => (d.sourceType ?? '').trim() == 'sale' && (d.sourceId ?? '').trim().isNotEmpty)
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
            tooltip: 'Xuất Excel',
            icon: const Icon(Icons.table_view_outlined),
            onPressed: () => _exportAllSheetsExcel(context),
          ),
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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
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
                    Row(
                      children: [
                        const Icon(Icons.calendar_month, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Khoảng ngày: ${DateFormat('dd/MM/yyyy').format(_dateRange.start)} - ${DateFormat('dd/MM/yyyy').format(_dateRange.end)}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder<List<_PayStats>>(
                      future: Future.wait([
                        _loadPayStats(start: startOfDay, end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999)),
                        _loadPayStats(start: startOfWeek, end: DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day, 23, 59, 59, 999).add(const Duration(days: 6))),
                        _loadPayStats(start: startOfMonth, end: DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999)),
                        _loadPayStats(start: startOfYear, end: DateTime(now.year, 12, 31, 23, 59, 59, 999)),
                      ]),
                      builder: (context, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const SizedBox(
                            height: 92,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        final stats = snap.data ?? const <_PayStats>[];
                        final todayPay = stats.isNotEmpty ? stats[0] : const _PayStats(cashRevenue: 0, bankRevenue: 0, outstandingDebt: 0);
                        final weekPay = stats.length > 1 ? stats[1] : const _PayStats(cashRevenue: 0, bankRevenue: 0, outstandingDebt: 0);
                        final monthPay = stats.length > 2 ? stats[2] : const _PayStats(cashRevenue: 0, bankRevenue: 0, outstandingDebt: 0);
                        final yearPay = stats.length > 3 ? stats[3] : const _PayStats(cashRevenue: 0, bankRevenue: 0, outstandingDebt: 0);

                        final fixedToday = _PayStats(
                          cashRevenue: todayPay.cashRevenue,
                          bankRevenue: todayPay.bankRevenue,
                          outstandingDebt: todayPay.outstandingDebt,
                        );
                        final fixedWeek = _PayStats(
                          cashRevenue: weekPay.cashRevenue,
                          bankRevenue: weekPay.bankRevenue,
                          outstandingDebt: weekPay.outstandingDebt,
                        );
                        final fixedMonth = _PayStats(
                          cashRevenue: monthPay.cashRevenue,
                          bankRevenue: monthPay.bankRevenue,
                          outstandingDebt: monthPay.outstandingDebt,
                        );
                        final fixedYear = _PayStats(
                          cashRevenue: yearPay.cashRevenue,
                          bankRevenue: yearPay.bankRevenue,
                          outstandingDebt: yearPay.outstandingDebt,
                        );

                        return LayoutBuilder(
                          builder: (context, constraints) {
                            final isNarrow = constraints.maxWidth < 720;

                            final wToday = _PaymentKpi(
                              title: 'Hôm nay',
                              stats: fixedToday,
                              totalRevenue: fixedToday.cashRevenue + fixedToday.bankRevenue + fixedToday.outstandingDebt,
                              currency: currency,
                              color: Colors.blue,
                            );
                            final wWeek = _PaymentKpi(
                              title: 'Tuần này',
                              stats: fixedWeek,
                              totalRevenue: fixedWeek.cashRevenue + fixedWeek.bankRevenue + fixedWeek.outstandingDebt,
                              currency: currency,
                              color: Colors.green,
                            );
                            final wMonth = _PaymentKpi(
                              title: 'Tháng này',
                              stats: fixedMonth,
                              totalRevenue: fixedMonth.cashRevenue + fixedMonth.bankRevenue + fixedMonth.outstandingDebt,
                              currency: currency,
                              color: Colors.purple,
                            );
                            final wYear = _PaymentKpi(
                              title: 'Năm nay',
                              stats: fixedYear,
                              totalRevenue: fixedYear.cashRevenue + fixedYear.bankRevenue + fixedYear.outstandingDebt,
                              currency: currency,
                              color: Colors.orange,
                            );

                            if (!isNarrow) {
                              return Row(
                                children: [
                                  Expanded(child: wToday),
                                  const SizedBox(width: 6),
                                  Expanded(child: wWeek),
                                  const SizedBox(width: 6),
                                  Expanded(child: wMonth),
                                  const SizedBox(width: 6),
                                  Expanded(child: wYear),
                                ],
                              );
                            }

                            return Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: wToday),
                                    const SizedBox(width: 6),
                                    Expanded(child: wWeek),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Expanded(child: wMonth),
                                    const SizedBox(width: 6),
                                    Expanded(child: wYear),
                                  ],
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 720;

                        final kpiToday = _TripleKpi(
                          title: 'Hôm nay',
                          revenue: todaySales,
                          cost: todayCost,
                          profit: todayProfit,
                          currency: currency,
                          color: Colors.blue,
                        );
                        final kpiWeek = _TripleKpi(
                          title: 'Tuần này',
                          revenue: weekSales,
                          cost: weekCost,
                          profit: weekProfit,
                          currency: currency,
                          color: Colors.green,
                        );
                        final kpiMonth = _TripleKpi(
                          title: 'Tháng này',
                          revenue: monthSales,
                          cost: monthCost,
                          profit: monthProfit,
                          currency: currency,
                          color: Colors.purple,
                        );
                        final kpiYear = _TripleKpi(
                          title: 'Năm nay',
                          revenue: yearSales,
                          cost: yearCost,
                          profit: yearProfit,
                          currency: currency,
                          color: Colors.orange,
                        );

                        if (!isNarrow) {
                          return Row(
                            children: [
                              Expanded(child: kpiToday),
                              const SizedBox(width: 6),
                              Expanded(child: kpiWeek),
                              const SizedBox(width: 6),
                              Expanded(child: kpiMonth),
                              const SizedBox(width: 6),
                              Expanded(child: kpiYear),
                            ],
                          );
                        }

                        return Column(
                          children: [
                            Row(
                              children: [
                                Expanded(child: kpiToday),
                                const SizedBox(width: 6),
                                Expanded(child: kpiWeek),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(child: kpiMonth),
                                const SizedBox(width: 6),
                                Expanded(child: kpiYear),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder<List<Map<String, dynamic>>>(
                      future: DatabaseService.instance.db.query(
                        'expenses',
                        columns: ['amount', 'category', 'occurredAt'],
                        where: 'occurredAt >= ? AND occurredAt <= ?',
                        whereArgs: [start.toIso8601String(), end.toIso8601String()],
                      ),
                      builder: (context, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const SizedBox(
                            height: 72,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }

                        final rows = snap.data ?? const <Map<String, dynamic>>[];
                        double totalAll = 0;
                        double totalNonBiz = 0;
                        for (final r in rows) {
                          final amount = (r['amount'] as num?)?.toDouble() ?? 0.0;
                          totalAll += amount;
                          final cat = (r['category']?.toString() ?? '').trim();
                          if (cat == 'Chi tiêu ngoài kinh doanh') {
                            totalNonBiz += amount;
                          }
                        }
                        final totalBusiness = totalAll - totalNonBiz;
                        final netProfit = periodProfit - totalBusiness;

                        return Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _SingleKpi(
                                    title: 'Tổng nợ tôi',
                                    value: totalOthersOweMe,
                                    currency: currency,
                                    color: Colors.red,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _SingleKpi(
                                    title: 'Nợ từ bán hàng',
                                    value: totalOthersOweMeFromSales,
                                    currency: currency,
                                    color: Colors.redAccent,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _SingleKpi(
                                    title: 'Nợ ngoài',
                                    value: totalOthersOweMeOutside,
                                    currency: currency,
                                    color: Colors.deepOrange,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: _SingleKpi(
                                    title: 'Tôi nợ',
                                    value: totalOweOthers,
                                    currency: currency,
                                    color: Colors.amber,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _SingleKpi(
                                    title: 'Chi phí HL',
                                    value: totalBusiness,
                                    currency: currency,
                                    color: Colors.deepPurple,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _SingleKpi(
                                    title: 'Ngoài KD',
                                    value: totalNonBiz,
                                    currency: currency,
                                    color: Colors.brown,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: _SingleKpi(
                                    title: 'LN kỳ',
                                    value: periodProfit,
                                    currency: currency,
                                    color: periodProfit >= 0 ? Colors.green : Colors.red,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _SingleKpi(
                                    title: 'CP HL kỳ',
                                    value: totalBusiness,
                                    currency: currency,
                                    color: Colors.deepPurple,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: _SingleKpi(
                                    title: 'LN ròng',
                                    value: netProfit,
                                    currency: currency,
                                    color: netProfit >= 0 ? Colors.teal : Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Tổng quan tồn kho',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 8),
            _buildInventorySummary(
              currency: currency,
              dateRange: _dateRange,
              products: products,
              exportQty: exportQty,
              exportAmount: exportAmount,
              exportAmountSell: filteredSales.fold<double>(0, (p, s) => p + s.total),
            ),
            const SizedBox(height: 16),
            const Text(
              'Biểu đồ doanh thu / vốn / lợi nhuận',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
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
            FutureBuilder<List<Map<String, dynamic>>>(
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
                  if (cat == 'Chi tiêu ngoài kinh doanh') {
                    continue;
                  }

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
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetProfitChartCard({
    required String title,
    required List<_Point> points,
    required NumberFormat currency,
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
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  minY: _getMinY(points),
                  maxY: _getMaxY(points),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final point = points[groupIndex];
                        final tooltipText = '${point.x}\n\nLN ròng: ${currency.format(point.profit)}';
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
                          final abs = value.abs();
                          if (abs >= 1000000) {
                            txt = '${(value / 1000000).toStringAsFixed(1)}M';
                          } else if (abs >= 1000) {
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
                          BarChartRodData(
                            toY: points[i].profit,
                            color: (points[i].profit >= 0 ? Colors.teal : Colors.red).withOpacity(0.75),
                            width: 12,
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

  Widget _buildChartCard({
    required String title,
    required List<_Point> points,
    required NumberFormat currency,
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
              height: 280,
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

        final importQty = purchases.fold<double>(0, (p, r) => p + ((r['quantity'] as num?)?.toDouble() ?? 0));
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
                Text(
                  'Tồn kho (${DateFormat('dd/MM/yyyy').format(dateRange.start)} - ${DateFormat('dd/MM/yyyy').format(dateRange.end)})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _InventoryMetric(
                        title: 'Tồn đầu kỳ',
                        qty: openingQty,
                        amount: openingAmount,
                        amountSell: openingAmountSell,
                        currency: currency,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _InventoryMetric(
                        title: 'Nhập trong kỳ',
                        qty: importQty,
                        amount: importAmount,
                        amountSell: importAmountSell,
                        currency: currency,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _InventoryMetric(
                        title: 'Xuất trong kỳ',
                        qty: exportQty,
                        amount: exportAmount,
                        amountSell: exportAmountSell,
                        currency: currency,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _InventoryMetric(
                        title: 'Tồn cuối kỳ',
                        qty: endingQty,
                        amount: endingAmount,
                        amountSell: endingAmountSell,
                        currency: currency,
                        color: Colors.purple,
                      ),
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

class _InventoryMetric extends StatelessWidget {
  final String title;
  final double qty;
  final double amount;
  final double? amountSell;
  final NumberFormat currency;
  final Color color;

  const _InventoryMetric({
    required this.title,
    required this.qty,
    required this.amount,
    this.amountSell,
    required this.currency,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final qtyText = qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
          const SizedBox(height: 6),
          Text('SL: $qtyText', style: const TextStyle(fontSize: 12, color: Colors.black87)),
          const SizedBox(height: 2),
          Text('GV: ${currency.format(amount)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          if (amountSell != null) ...[
            const SizedBox(height: 2),
            Text('GB: ${currency.format(amountSell)}', style: const TextStyle(fontSize: 12, color: Colors.black87)),
          ],
        ],
      ),
    );
  }
}

class _SingleKpi extends StatelessWidget {
  final String title;
  final double value;
  final NumberFormat currency;
  final Color color;

  const _SingleKpi({
    required this.title,
    required this.value,
    required this.currency,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              currency.format(value),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TripleKpi extends StatelessWidget {
  final String title;
  final double revenue;
  final double cost;
  final double profit;
  final NumberFormat currency;
  final Color color;

  const _TripleKpi({
    required this.title,
    required this.revenue,
    required this.cost,
    required this.profit,
    required this.currency,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final profitColor = profit >= 0 ? Colors.green : Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          _TripleKpiRow(label: 'DT', value: revenue, currency: currency, valueColor: Colors.blue),
          const SizedBox(height: 2),
          _TripleKpiRow(label: 'Vốn', value: cost, currency: currency, valueColor: Colors.orange),
          const SizedBox(height: 2),
          _TripleKpiRow(label: 'LN', value: profit, currency: currency, valueColor: profitColor),
        ],
      ),
    );
  }
}

class _TripleKpiRow extends StatelessWidget {
  final String label;
  final double value;
  final NumberFormat currency;
  final Color valueColor;

  const _TripleKpiRow({
    required this.label,
    required this.value,
    required this.currency,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 30,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                currency.format(value),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}