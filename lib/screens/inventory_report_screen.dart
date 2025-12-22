import 'dart:convert';

import 'package:excel/excel.dart' as ex;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../providers/product_provider.dart';
import '../services/database_service.dart';
import '../utils/file_helper.dart';
import '../utils/number_input_formatter.dart';
import '../utils/text_normalizer.dart';

class InventoryReportScreen extends StatefulWidget {
  const InventoryReportScreen({super.key});

  @override
  State<InventoryReportScreen> createState() => _InventoryReportScreenState();
}

class _InventoryReportScreenState extends State<InventoryReportScreen> {
  DateTimeRange _range = DateTimeRange(
    start: DateTime(DateTime.now().year, DateTime.now().month, 1),
    end: DateTime.now(),
  );

  String _query = '';
  bool _loading = false;

  _AmountMode _amountMode = _AmountMode.sell;

  late Future<List<_InventoryRow>> _rowsFuture;
  final ScrollController _scrollCtrl = ScrollController();

  List<Map<String, dynamic>> _decodeMixItems(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(s);
      if (decoded is List) {
        return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  Future<double> _exportQtyForProductInRange({
    required String productId,
    required DateTime start,
    required DateTime end,
  }) async {
    final db = DatabaseService.instance.db;

    final rows = await db.rawQuery(
      '''
      SELECT si.productId, si.quantity, si.itemType, si.mixItemsJson
      FROM sale_items si
      JOIN sales s ON s.id = si.saleId
      WHERE s.createdAt >= ? AND s.createdAt <= ?
      ''',
      [start.toIso8601String(), end.toIso8601String()],
    );

    double total = 0.0;
    for (final r in rows) {
      final itemType = (r['itemType']?.toString() ?? '').toUpperCase().trim();
      if (itemType == 'MIX') {
        final mixItems = _decodeMixItems(r['mixItemsJson']?.toString());
        for (final m in mixItems) {
          final rid = (m['rawProductId']?.toString() ?? '').trim();
          if (rid != productId) continue;
          total += (m['rawQty'] as num?)?.toDouble() ?? 0.0;
        }
      } else {
        final pid = (r['productId']?.toString() ?? '').trim();
        if (pid != productId) continue;
        total += (r['quantity'] as num?)?.toDouble() ?? 0.0;
      }
    }
    return total;
  }

  @override
  void initState() {
    super.initState();
    _rowsFuture = _loadRows();
  }

  void _refreshRowsPreserveScroll() {
    final offset = _scrollCtrl.hasClients ? _scrollCtrl.offset : 0.0;
    setState(() {
      _rowsFuture = _loadRows();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      final max = _scrollCtrl.position.maxScrollExtent;
      final target = offset.clamp(0.0, max);
      _scrollCtrl.jumpTo(target);
    });
  }

  String _fmtQty(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2);

  Future<void> _editOpeningForProduct({
    required String productId,
    required String productName,
    required String unit,
    required double currentStock,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final monthYear = DateTime(_range.start.year, _range.start.month);

    final existingMap =
        await DatabaseService.instance.getOpeningStocksForMonth(monthYear.year, monthYear.month);
    final existing = existingMap[productId] ?? 0;

    final ctrl = TextEditingController(text: _fmtQty(existing));
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Tồn đầu kỳ ${monthYear.month}/${monthYear.year}'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(productName, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 10),
                TextField(
                  controller: ctrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [NumberInputFormatter(maxDecimalDigits: 2)],
                  decoration: InputDecoration(
                    labelText: 'Tồn đầu kỳ',
                    suffixText: unit,
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text('Lấy tồn hiện tại'),
                      onPressed: () {
                        ctrl.text = _fmtQty(currentStock);
                        FocusScope.of(context).unfocus();
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.calculate_outlined),
                      label: const Text('Tính tồn đầu kỳ'),
                      onPressed: () async {
                        final start = DateTime(
                          _range.start.year,
                          _range.start.month,
                          _range.start.day,
                        );
                        final end = DateTime(
                          _range.end.year,
                          _range.end.month,
                          _range.end.day,
                          23,
                          59,
                          59,
                          999,
                        );

                        final db = DatabaseService.instance.db;

                        final purchaseRows = await db.query(
                          'purchase_history',
                          columns: ['quantity'],
                          where: 'productId = ? AND createdAt >= ? AND createdAt <= ?',
                          whereArgs: [
                            productId,
                            start.toIso8601String(),
                            end.toIso8601String(),
                          ],
                        );
                        double importQty = 0;
                        for (final r in purchaseRows) {
                          importQty += (r['quantity'] as num?)?.toDouble() ?? 0;
                        }

                        final exportQty = await _exportQtyForProductInRange(
                          productId: productId,
                          start: start,
                          end: end,
                        );

                        final opening = currentStock + exportQty - importQty;
                        ctrl.text = _fmtQty(opening);
                        FocusScope.of(context).unfocus();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Tồn hiện tại: ${_fmtQty(currentStock)} $unit',
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lưu')),
        ],
      ),
    );
    if (ok != true) return;

    final v = (NumberInputFormatter.tryParse(ctrl.text) ?? 0).toDouble();
    await DatabaseService.instance.upsertOpeningStocksForMonth(
      year: monthYear.year,
      month: monthYear.month,
      openingByProductId: {productId: v},
    );
    if (!mounted) return;
    _refreshRowsPreserveScroll();
    messenger.showSnackBar(const SnackBar(content: Text('Đã cập nhật tồn đầu kỳ')));
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

  Future<List<_InventoryRow>> _loadRows() async {
    final provider = context.read<ProductProvider>();
    final products = provider.products;

    final start = DateTime(_range.start.year, _range.start.month, _range.start.day);
    final end = DateTime(_range.end.year, _range.end.month, _range.end.day, 23, 59, 59, 999);

    final monthYear = DateTime(_range.start.year, _range.start.month);
    final openingByProductId = await DatabaseService.instance.getOpeningStocksForMonth(monthYear.year, monthYear.month);

    final db = DatabaseService.instance.db;

    final purchaseRows = await db.query(
      'purchase_history',
      where: 'createdAt >= ? AND createdAt <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
    );

    final importQtyByProductId = <String, double>{};
    final importAmountCostByProductId = <String, double>{};
    for (final r in purchaseRows) {
      final pid = r['productId'] as String;
      final qty = (r['quantity'] as num?)?.toDouble() ?? 0;
      final unitCost = (r['unitCost'] as num?)?.toDouble() ?? 0;
      importQtyByProductId[pid] = (importQtyByProductId[pid] ?? 0) + qty;
      importAmountCostByProductId[pid] = (importAmountCostByProductId[pid] ?? 0) + (qty * unitCost);
    }

    final exportQtyByProductId = <String, double>{};
    final saleRows = await db.rawQuery(
      '''
      SELECT si.productId, si.quantity, si.itemType, si.mixItemsJson
      FROM sale_items si
      JOIN sales s ON s.id = si.saleId
      WHERE s.createdAt >= ? AND s.createdAt <= ?
      ''',
      [start.toIso8601String(), end.toIso8601String()],
    );
    for (final r in saleRows) {
      final itemType = (r['itemType']?.toString() ?? '').toUpperCase().trim();
      if (itemType == 'MIX') {
        final mixItems = _decodeMixItems(r['mixItemsJson']?.toString());
        for (final m in mixItems) {
          final rid = (m['rawProductId']?.toString() ?? '').trim();
          if (rid.isEmpty) continue;
          final q = (m['rawQty'] as num?)?.toDouble() ?? 0.0;
          exportQtyByProductId[rid] = (exportQtyByProductId[rid] ?? 0) + q;
        }
      } else {
        final pid = (r['productId']?.toString() ?? '').trim();
        if (pid.isEmpty) continue;
        final q = (r['quantity'] as num?)?.toDouble() ?? 0.0;
        exportQtyByProductId[pid] = (exportQtyByProductId[pid] ?? 0) + q;
      }
    }

    final qn = TextNormalizer.normalize(_query);
    final filtered = qn.isEmpty
        ? products
        : products.where((p) => TextNormalizer.normalize(p.name).contains(qn)).toList();

    final rows = <_InventoryRow>[];
    for (final p in filtered) {
      final openingQty = openingByProductId[p.id] ?? 0;
      final importQty = importQtyByProductId[p.id] ?? 0;
      final exportQty = exportQtyByProductId[p.id] ?? 0;
      final endingQty = openingQty + importQty - exportQty;

      final openingAmountCost = openingQty * p.costPrice;
      final openingAmountSell = openingQty * p.price;

      final importAmountCost = importAmountCostByProductId[p.id] ?? 0;
      final importAmountSell = importQty * p.price;

      final exportAmountCost = exportQty * p.costPrice;
      final exportAmountSell = exportQty * p.price;

      final endingAmountCost = endingQty * p.costPrice;
      final endingAmountSell = endingQty * p.price;

      rows.add(
        _InventoryRow(
          productId: p.id,
          productName: p.name,
          unit: p.unit,
          openingQty: openingQty,
          openingAmountCost: openingAmountCost,
          openingAmountSell: openingAmountSell,
          importQty: importQty,
          importAmountCost: importAmountCost,
          importAmountSell: importAmountSell,
          exportQty: exportQty,
          exportAmountCost: exportAmountCost,
          exportAmountSell: exportAmountSell,
          endingQty: endingQty,
          endingAmountCost: endingAmountCost,
          endingAmountSell: endingAmountSell,
        ),
      );
    }

    rows.sort((a, b) => a.productName.compareTo(b.productName));
    return rows;
  }

  Future<void> _exportExcel(List<_InventoryRow> rows) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      setState(() => _loading = true);

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Expanded(child: Text('Đang xuất Excel...')),
            ],
          ),
        ),
      );

      final excel = ex.Excel.createExcel();
      excel.delete('Sheet1');

      final sheet = excel['bang_ke_ton_kho'];
      final header = <ex.CellValue?>[
        _cv('Tên sản phẩm'),
        _cv('Đơn vị'),
        _cv('Tồn đầu kỳ (SL)'),
      ];
      if (_amountMode == _AmountMode.cost || _amountMode == _AmountMode.both) {
        header.add(_cv('Tồn đầu kỳ (Tiền giá vốn)'));
      }
      if (_amountMode == _AmountMode.sell || _amountMode == _AmountMode.both) {
        header.add(_cv('Tồn đầu kỳ (Tiền giá bán)'));
      }

      header.addAll([
        _cv('Nhập trong kỳ (SL)'),
      ]);
      if (_amountMode == _AmountMode.cost || _amountMode == _AmountMode.both) {
        header.add(_cv('Nhập trong kỳ (Tiền giá vốn)'));
      }
      if (_amountMode == _AmountMode.sell || _amountMode == _AmountMode.both) {
        header.add(_cv('Nhập trong kỳ (Tiền giá bán)'));
      }

      header.addAll([
        _cv('Xuất trong kỳ (SL)'),
      ]);
      if (_amountMode == _AmountMode.cost || _amountMode == _AmountMode.both) {
        header.add(_cv('Xuất trong kỳ (Tiền giá vốn)'));
      }
      if (_amountMode == _AmountMode.sell || _amountMode == _AmountMode.both) {
        header.add(_cv('Xuất trong kỳ (Tiền giá bán)'));
      }

      header.addAll([
        _cv('Tồn cuối kỳ (SL)'),
      ]);
      if (_amountMode == _AmountMode.cost || _amountMode == _AmountMode.both) {
        header.add(_cv('Tồn cuối kỳ (Tiền giá vốn)'));
      }
      if (_amountMode == _AmountMode.sell || _amountMode == _AmountMode.both) {
        header.add(_cv('Tồn cuối kỳ (Tiền giá bán)'));
      }

      sheet.appendRow(header);

      for (final r in rows) {
        final row = <ex.CellValue?>[
          _cv(r.productName),
          _cv(r.unit),
          _cv(r.openingQty),
        ];
        if (_amountMode == _AmountMode.cost || _amountMode == _AmountMode.both) {
          row.add(_cv(r.openingAmountCost));
        }
        if (_amountMode == _AmountMode.sell || _amountMode == _AmountMode.both) {
          row.add(_cv(r.openingAmountSell));
        }

        row.add(_cv(r.importQty));
        if (_amountMode == _AmountMode.cost || _amountMode == _AmountMode.both) {
          row.add(_cv(r.importAmountCost));
        }
        if (_amountMode == _AmountMode.sell || _amountMode == _AmountMode.both) {
          row.add(_cv(r.importAmountSell));
        }

        row.add(_cv(r.exportQty));
        if (_amountMode == _AmountMode.cost || _amountMode == _AmountMode.both) {
          row.add(_cv(r.exportAmountCost));
        }
        if (_amountMode == _AmountMode.sell || _amountMode == _AmountMode.both) {
          row.add(_cv(r.exportAmountSell));
        }

        row.add(_cv(r.endingQty));
        if (_amountMode == _AmountMode.cost || _amountMode == _AmountMode.both) {
          row.add(_cv(r.endingAmountCost));
        }
        if (_amountMode == _AmountMode.sell || _amountMode == _AmountMode.both) {
          row.add(_cv(r.endingAmountSell));
        }
        sheet.appendRow(row);
      }

      final bytes = excel.encode();
      if (bytes == null) {
        throw Exception('Không thể tạo file Excel');
      }

      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'bang_ke_ton_kho_$ts.xlsx';
      final filePath = await FileHelper.saveBytesToDownloads(bytes: bytes, fileName: fileName);

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      if (filePath == null) {
        throw Exception('Không thể lưu file vào Downloads');
      }

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
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
        messenger.showSnackBar(SnackBar(content: Text('Lỗi xuất Excel: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    final products = context.watch<ProductProvider>().products;
    final productById = {for (final p in products) p.id: p};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bảng kê tồn kho'),
        actions: [
          PopupMenuButton<_AmountMode>(
            initialValue: _amountMode,
            tooltip: 'Kiểu hiển thị tiền',
            onSelected: (v) => setState(() => _amountMode = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: _AmountMode.cost, child: Text('Giá vốn')),
              PopupMenuItem(value: _AmountMode.sell, child: Text('Giá bán')),
              PopupMenuItem(value: _AmountMode.both, child: Text('Cả 2')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.price_change_outlined),
                  const SizedBox(width: 6),
                  Text(_amountMode.label),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'Chọn khoảng ngày',
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(now.year - 2),
                lastDate: DateTime(now.year + 1),
                initialDateRange: _range,
              );
              if (picked != null) {
                setState(() => _range = picked);
                _refreshRowsPreserveScroll();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Lọc theo tên sản phẩm',
                isDense: true,
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) {
                setState(() => _query = v);
                _refreshRowsPreserveScroll();
              },
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Từ ${DateFormat('dd/MM/yyyy').format(_range.start)} đến ${DateFormat('dd/MM/yyyy').format(_range.end)}',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _loading
                      ? null
                      : () async {
                          setState(() => _loading = true);
                          final rows = await _loadRows();
                          if (!mounted) return;
                          setState(() => _loading = false);
                          await _exportExcel(rows);
                        },
                  icon: const Icon(Icons.download),
                  label: const Text('Xuất Excel'),
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          Expanded(
            child: FutureBuilder<List<_InventoryRow>>(
              future: _rowsFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Lỗi: ${snap.error}'));
                }
                final rows = snap.data ?? const [];
                if (rows.isEmpty) {
                  return const Center(child: Text('Không có dữ liệu'));
                }

                final totalOpeningQty = rows.fold<double>(0, (p, e) => p + e.openingQty);
                final totalImportQty = rows.fold<double>(0, (p, e) => p + e.importQty);
                final totalExportQty = rows.fold<double>(0, (p, e) => p + e.exportQty);
                final totalEndingQty = rows.fold<double>(0, (p, e) => p + e.endingQty);

                double totalOpeningCost = 0;
                double totalOpeningSell = 0;
                double totalImportCost = 0;
                double totalImportSell = 0;
                double totalExportCost = 0;
                double totalExportSell = 0;
                double totalEndingCost = 0;
                double totalEndingSell = 0;
                for (final r in rows) {
                  totalOpeningCost += r.openingAmountCost;
                  totalOpeningSell += r.openingAmountSell;
                  totalImportCost += r.importAmountCost;
                  totalImportSell += r.importAmountSell;
                  totalExportCost += r.exportAmountCost;
                  totalExportSell += r.exportAmountSell;
                  totalEndingCost += r.endingAmountCost;
                  totalEndingSell += r.endingAmountSell;
                }

                return ListView.builder(
                  controller: _scrollCtrl,
                  key: const PageStorageKey('inventory_report_list'),
                  itemCount: rows.length + 1,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Card(
                        elevation: 0,
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.summarize_outlined),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Tổng hợp (${rows.length} sản phẩm)',
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Column(
                                children: [
                                  IntrinsicHeight(
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: _MetricPill(
                                            height: 86,
                                            label: 'Tồn đầu',
                                            qtyText: _fmtQty(totalOpeningQty),
                                            amountText: _amountMode == _AmountMode.cost
                                                ? currency.format(totalOpeningCost)
                                                : _amountMode == _AmountMode.sell
                                                    ? currency.format(totalOpeningSell)
                                                    : '${currency.format(totalOpeningCost)} | ${currency.format(totalOpeningSell)}',
                                            color: Colors.blue,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _MetricPill(
                                            height: 86,
                                            label: 'Nhập',
                                            qtyText: _fmtQty(totalImportQty),
                                            amountText: _amountMode == _AmountMode.cost
                                                ? currency.format(totalImportCost)
                                                : _amountMode == _AmountMode.sell
                                                    ? currency.format(totalImportSell)
                                                    : '${currency.format(totalImportCost)} | ${currency.format(totalImportSell)}',
                                            color: Colors.green,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  IntrinsicHeight(
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: _MetricPill(
                                            height: 86,
                                            label: 'Xuất',
                                            qtyText: _fmtQty(totalExportQty),
                                            amountText: _amountMode == _AmountMode.cost
                                                ? currency.format(totalExportCost)
                                                : _amountMode == _AmountMode.sell
                                                    ? currency.format(totalExportSell)
                                                    : '${currency.format(totalExportCost)} | ${currency.format(totalExportSell)}',
                                            color: Colors.redAccent,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _MetricPill(
                                            height: 86,
                                            label: 'Tồn cuối',
                                            qtyText: _fmtQty(totalEndingQty),
                                            amountText: _amountMode == _AmountMode.cost
                                                ? currency.format(totalEndingCost)
                                                : _amountMode == _AmountMode.sell
                                                    ? currency.format(totalEndingSell)
                                                    : '${currency.format(totalEndingCost)} | ${currency.format(totalEndingSell)}',
                                            color: Colors.deepPurple,
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
                      );
                    }

                    final r = rows[i - 1];
                    final p = productById[r.productId];
                    final currentStock = p?.currentStock ?? 0;

                    final openingAmount = _amountMode == _AmountMode.cost
                        ? currency.format(r.openingAmountCost)
                        : _amountMode == _AmountMode.sell
                            ? currency.format(r.openingAmountSell)
                            : '${currency.format(r.openingAmountCost)} | ${currency.format(r.openingAmountSell)}';
                    final importAmount = _amountMode == _AmountMode.cost
                        ? currency.format(r.importAmountCost)
                        : _amountMode == _AmountMode.sell
                            ? currency.format(r.importAmountSell)
                            : '${currency.format(r.importAmountCost)} | ${currency.format(r.importAmountSell)}';
                    final exportAmount = _amountMode == _AmountMode.cost
                        ? currency.format(r.exportAmountCost)
                        : _amountMode == _AmountMode.sell
                            ? currency.format(r.exportAmountSell)
                            : '${currency.format(r.exportAmountCost)} | ${currency.format(r.exportAmountSell)}';
                    final endingAmount = _amountMode == _AmountMode.cost
                        ? currency.format(r.endingAmountCost)
                        : _amountMode == _AmountMode.sell
                            ? currency.format(r.endingAmountSell)
                            : '${currency.format(r.endingAmountCost)} | ${currency.format(r.endingAmountSell)}';

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    r.productName,
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Sửa tồn đầu kỳ',
                                  icon: const Icon(Icons.edit_note_outlined),
                                  onPressed: p == null
                                      ? null
                                      : () => _editOpeningForProduct(
                                            productId: r.productId,
                                            productName: r.productName,
                                            unit: r.unit,
                                            currentStock: currentStock,
                                          ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'ĐVT: ${r.unit}  •  Tồn hiện tại: ${_fmtQty(currentStock)}',
                              style: const TextStyle(color: Colors.black54),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _MetricCard(
                                    title: 'Tồn đầu',
                                    qty: _fmtQty(r.openingQty),
                                    amount: openingAmount,
                                    color: Colors.blue,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _MetricCard(
                                    title: 'Nhập',
                                    qty: _fmtQty(r.importQty),
                                    amount: importAmount,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _MetricCard(
                                    title: 'Xuất',
                                    qty: _fmtQty(r.exportQty),
                                    amount: exportAmount,
                                    color: Colors.redAccent,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _MetricCard(
                                    title: 'Tồn cuối',
                                    qty: _fmtQty(r.endingQty),
                                    amount: endingAmount,
                                    color: Colors.deepPurple,
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
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String qty;
  final String amount;
  final Color color;

  const _MetricCard({required this.title, required this.qty, required this.amount, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('SL: $qty', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(amount, style: const TextStyle(color: Colors.black87)),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final String qtyText;
  final String amountText;
  final Color color;
  final double? height;

  const _MetricPill({
    required this.label,
    required this.qtyText,
    required this.amountText,
    required this.color,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('SL: $qtyText', style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(amountText, style: const TextStyle(color: Colors.black87)),
          ],
        ),
      ),
    );
  }
}

enum _AmountMode {
  cost,
  sell,
  both,
}

extension on _AmountMode {
  String get label {
    switch (this) {
      case _AmountMode.cost:
        return 'Giá vốn';
      case _AmountMode.sell:
        return 'Giá bán';
      case _AmountMode.both:
        return 'Cả 2';
    }
  }
}

class _InventoryRow {
  final String productId;
  final String productName;
  final String unit;

  final double openingQty;
  final double openingAmountCost;
  final double openingAmountSell;

  final double importQty;
  final double importAmountCost;
  final double importAmountSell;

  final double exportQty;
  final double exportAmountCost;
  final double exportAmountSell;

  final double endingQty;
  final double endingAmountCost;
  final double endingAmountSell;

  _InventoryRow({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.openingQty,
    required this.openingAmountCost,
    required this.openingAmountSell,
    required this.importQty,
    required this.importAmountCost,
    required this.importAmountSell,
    required this.exportQty,
    required this.exportAmountCost,
    required this.exportAmountSell,
    required this.endingQty,
    required this.endingAmountCost,
    required this.endingAmountSell,
  });
}
