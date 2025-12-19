import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../providers/product_provider.dart';
import '../models/product.dart';
import 'package:intl/intl.dart';
import 'scan_screen.dart';
import '../services/database_service.dart';
import '../utils/number_input_formatter.dart';
import '../utils/text_normalizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'inventory_report_screen.dart';
import 'purchase_history_screen.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Tab 0 (Products)
  String _productsQuery = '';

  // Tab 2 (Export history - RAW)
  DateTimeRange? _exportRange;
  String _exportQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickRangeForTab(int tabIndex) async {
    final now = DateTime.now();
    final current = _exportRange;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDateRange: current,
    );
    if (picked == null) return;
    setState(() {
      if (tabIndex == 2) {
        _exportRange = picked;
      }
    });
  }

  void _clearRangeForTab(int tabIndex) {
    setState(() {
      if (tabIndex == 2) _exportRange = null;
    });
  }

  Future<List<Map<String, dynamic>>> _loadExportHistoryRaw() async {
    final start = _exportRange == null
        ? null
        : DateTime(_exportRange!.start.year, _exportRange!.start.month, _exportRange!.start.day);
    final end = _exportRange == null
        ? null
        : DateTime(_exportRange!.end.year, _exportRange!.end.month, _exportRange!.end.day, 23, 59, 59, 999);

    final db = DatabaseService.instance.db;

    final saleRows = await db.rawQuery(
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
      ${start == null ? '' : 'WHERE s.createdAt >= ? AND s.createdAt <= ?'}
      ORDER BY s.createdAt DESC
      ''',
      start == null ? null : [start.toIso8601String(), end!.toIso8601String()],
    );

    final out = <Map<String, dynamic>>[];
    for (final r in saleRows) {
      final itemType = (r['itemType']?.toString() ?? '').toUpperCase().trim();
      if (itemType == 'MIX') {
        final raw = (r['mixItemsJson']?.toString() ?? '').trim();
        if (raw.isEmpty) continue;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            for (final e in decoded) {
              if (e is Map) {
                final rawProductId = (e['rawProductId']?.toString() ?? '').trim();
                if (rawProductId.isEmpty) continue;
                out.add({
                  'saleId': r['saleId'],
                  'saleCreatedAt': r['saleCreatedAt'],
                  'customerName': r['customerName'],
                  'productId': rawProductId,
                  'productName': (e['rawName']?.toString() ?? '').trim(),
                  'unit': (e['rawUnit']?.toString() ?? '').trim(),
                  'quantity': (e['rawQty'] as num?)?.toDouble() ?? 0.0,
                  'source': 'MIX',
                });
              }
            }
          }
        } catch (_) {
          continue;
        }
      } else {
        final pid = (r['productId']?.toString() ?? '').trim();
        if (pid.isEmpty) continue;
        out.add({
          'saleId': r['saleId'],
          'saleCreatedAt': r['saleCreatedAt'],
          'customerName': r['customerName'],
          'productId': pid,
          'productName': (r['name']?.toString() ?? '').trim(),
          'unit': (r['unit']?.toString() ?? '').trim(),
          'quantity': (r['quantity'] as num?)?.toDouble() ?? 0.0,
          'source': 'RAW',
        });
      }
    }

    final q = _exportQuery.trim();
    if (q.isEmpty) return out;
    final qLower = TextNormalizer.normalize(q);
    return out.where((m) {
      final productName = TextNormalizer.normalize((m['productName']?.toString() ?? ''));
      final customerName = TextNormalizer.normalize((m['customerName']?.toString() ?? ''));
      return productName.contains(qLower) || customerName.contains(qLower);
    }).toList();
  }

  Widget _buildTab0Products(BuildContext context) {
    final provider = context.watch<ProductProvider>();
    final products = provider.products;
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);

    final qn = TextNormalizer.normalize(_productsQuery);
    final filtered = qn.isEmpty
        ? products
        : products.where((p) {
            final name = TextNormalizer.normalize(p.name);
            final barcode = (p.barcode ?? '').trim();
            return name.contains(qn) || (barcode.isNotEmpty && barcode.contains(_productsQuery.trim()));
          }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Tìm theo tên / mã vạch',
              isDense: true,
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _productsQuery = v),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final p = filtered[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.withValues(alpha: 0.12),
                  foregroundColor: Colors.blue,
                  child: Icon(
                    (p.barcode != null && p.barcode!.trim().isNotEmpty)
                        ? Icons.qr_code
                        : Icons.inventory_2_outlined,
                  ),
                ),
                title: Text(p.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Giá bán: ${currency.format(p.price)} / ${p.unit}'),
                    Text('Giá vốn: ${currency.format(p.costPrice)}'),
                    Text('Tồn: ${p.currentStock.toStringAsFixed(p.currentStock % 1 == 0 ? 0 : 2)} ${p.unit}'),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _showProductDialog(context, existing: p),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _confirmDelete(context, p),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTab1ImportHistory(BuildContext context) {
    return const PurchaseHistoryScreen(embedded: true);
  }

  Widget _buildTab2ExportHistoryRaw(BuildContext context) {
    final fmtDate = DateFormat('dd/MM/yyyy HH:mm');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Tìm theo sản phẩm / khách hàng',
                    isDense: true,
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _exportQuery = v.trim()),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Chọn khoảng ngày (theo ngày xuất)',
                icon: const Icon(Icons.filter_list),
                onPressed: () => _pickRangeForTab(2),
              ),
              if (_exportRange != null)
                IconButton(
                  tooltip: 'Xoá lọc ngày',
                  icon: const Icon(Icons.clear),
                  onPressed: () => _clearRangeForTab(2),
                ),
            ],
          ),
        ),
        if (_exportRange != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Đang lọc: ${DateFormat('dd/MM/yyyy').format(_exportRange!.start)} - ${DateFormat('dd/MM/yyyy').format(_exportRange!.end)}',
                style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _loadExportHistoryRaw(),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snap.data ?? const [];
              if (rows.isEmpty) {
                return const Center(child: Text('Chưa có lịch sử xuất kho'));
              }

              return ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final r = rows[i];
                  final createdAt = DateTime.tryParse(r['saleCreatedAt'] as String? ?? '') ?? DateTime.now();
                  final productName = (r['productName'] as String?) ?? '';
                  final qty = (r['quantity'] as num?)?.toDouble() ?? 0;
                  final unit = (r['unit'] as String?) ?? '';
                  final customerName = (r['customerName'] as String?)?.trim();
                  final source = (r['source'] as String?) ?? '';

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.orange.withValues(alpha: 0.12),
                      foregroundColor: Colors.orange,
                      child: const Icon(Icons.outbox_outlined),
                    ),
                    title: Text(productName, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SL xuất: ${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2)} ${unit.isEmpty ? '' : unit}'),
                        if (customerName != null && customerName.isNotEmpty) Text('KH: $customerName'),
                        Text(fmtDate.format(createdAt), style: const TextStyle(color: Colors.black54)),
                        if (source == 'MIX')
                          const Text(
                            'Xuất từ MIX',
                            style: TextStyle(color: Colors.deepPurple, fontWeight: FontWeight.w600),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabIndex = _tabController.index;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kho'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Sản phẩm'),
            Tab(text: 'Nhập kho'),
            Tab(text: 'Xuất kho (RAW)'),
          ],
        ),
        actions: [
          if (tabIndex == 0) ...[
            IconButton(
              icon: const Icon(Icons.table_chart_outlined),
              tooltip: 'Bảng kê tồn kho',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const InventoryReportScreen()),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.inventory_2_outlined),
              tooltip: 'Set tồn đầu kỳ (tháng hiện tại)',
              onPressed: () => _showOpeningStockDialog(context),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _showProductDialog(context),
              tooltip: 'Thêm sản phẩm',
            ),
          ] else if (tabIndex == 2) ...[
            IconButton(
              tooltip: 'Chọn khoảng ngày',
              icon: const Icon(Icons.filter_list),
              onPressed: () => _pickRangeForTab(tabIndex),
            ),
            if (_exportRange != null)
              IconButton(
                tooltip: 'Xoá lọc ngày',
                icon: const Icon(Icons.clear),
                onPressed: () => _clearRangeForTab(tabIndex),
              ),
          ],
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTab0Products(context),
          _buildTab1ImportHistory(context),
          _buildTab2ExportHistoryRaw(context),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Product p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xóa sản phẩm?'),
        content: Text('Bạn có chắc muốn xóa "${p.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (ok == true) {
      final used = await DatabaseService.instance.isProductUsed(p.id);
      if (!context.mounted) return;
      if (used) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sản phẩm đã được dùng trong bán hàng/nhập hàng nên không thể xóa')),
        );
        return;
      }

      await context.read<ProductProvider>().delete(p.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa sản phẩm')));
    }
  }

  Future<void> _showProductDialog(BuildContext context, {Product? existing}) async {
    final prefs = await SharedPreferences.getInstance();
    final lastUnit = prefs.getString('last_product_unit') ?? 'cái';
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl = TextEditingController(text: existing?.price.toStringAsFixed(0) ?? '0');
    final costPriceCtrl = TextEditingController(text: existing?.costPrice.toStringAsFixed(0) ?? '0');
    final existingStock = existing?.currentStock ?? 0;
    final stockCtrl = TextEditingController(text: existingStock.toStringAsFixed(existingStock % 1 == 0 ? 0 : 2));
    final unitCtrl = TextEditingController(text: existing?.unit ?? lastUnit);
    final barcodeCtrl = TextEditingController(text: existing?.barcode ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'Thêm sản phẩm' : 'Sửa sản phẩm'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Tên')), 
            const SizedBox(height: 8),
            TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
              decoration: const InputDecoration(labelText: 'Giá bán'),
            ), 
            const SizedBox(height: 8),
            TextField(
              controller: costPriceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
              decoration: const InputDecoration(labelText: 'Giá vốn'),
            ), 
            const SizedBox(height: 8),
            TextField(
              controller: stockCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [NumberInputFormatter(maxDecimalDigits: 2)],
              decoration: const InputDecoration(labelText: 'Tồn hiện tại'),
            ), 
            const SizedBox(height: 8),
            TextField(controller: unitCtrl, decoration: const InputDecoration(labelText: 'Đơn vị')), 
            const SizedBox(height: 8),
            TextField(
              controller: barcodeCtrl,
              decoration: InputDecoration(
                labelText: 'Mã vạch (nếu có)',
                suffixIcon: IconButton(
                  tooltip: 'Quét mã vạch',
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: () async {
                    final code = await Navigator.of(context).push<String>(
                      MaterialPageRoute(builder: (_) => const ScanScreen()),
                    );
                    if (code != null && code.isNotEmpty) {
                      barcodeCtrl.text = code;
                      FocusScope.of(context).unfocus();
                    }
                  },
                ),
              ),
            ), 
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lưu')),
        ],
      ),
    );

    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      final provider = context.read<ProductProvider>();
      final newName = TextNormalizer.normalize(nameCtrl.text);
      final duplicated = provider.products.any((p) {
        if (existing != null && p.id == existing.id) return false;
        return TextNormalizer.normalize(p.name) == newName;
      });
      if (duplicated) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã tồn tại sản phẩm cùng tên')));
        return;
      }

      final unitToSave = unitCtrl.text.trim().isEmpty ? 'cái' : unitCtrl.text.trim();
      await prefs.setString('last_product_unit', unitToSave);
      if (existing == null) {
        final newProduct = Product(
          name: nameCtrl.text.trim(),
          price: NumberInputFormatter.tryParse(priceCtrl.text) ?? 0,
          costPrice: NumberInputFormatter.tryParse(costPriceCtrl.text) ?? 0,
          currentStock: NumberInputFormatter.tryParse(stockCtrl.text) ?? 0,
          unit: unitToSave,
          barcode: barcodeCtrl.text.trim().isEmpty ? null : barcodeCtrl.text.trim(),
        );
        await provider.add(newProduct);
        final now = DateTime.now();
        await DatabaseService.instance.upsertOpeningStocksForMonth(
          year: now.year,
          month: now.month,
          openingByProductId: {newProduct.id: newProduct.currentStock},
        );
      } else {
        await provider.update(Product(
          id: existing.id,
          name: nameCtrl.text.trim(),
          price: NumberInputFormatter.tryParse(priceCtrl.text) ?? 0,
          costPrice: NumberInputFormatter.tryParse(costPriceCtrl.text) ?? 0,
          currentStock: NumberInputFormatter.tryParse(stockCtrl.text) ?? 0,
          unit: unitToSave,
          barcode: barcodeCtrl.text.trim().isEmpty ? null : barcodeCtrl.text.trim(),
          isActive: existing.isActive,
        ));
      }
    }
  }

  Future<void> _showOpeningStockDialog(BuildContext context) async {
    final products = context.read<ProductProvider>().products;
    final now = DateTime.now();
    int year = now.year;
    int month = now.month;

    final controllers = <String, TextEditingController>{};
    for (final p in products) {
      controllers[p.id] = TextEditingController(text: '0');
    }

    Future<void> loadForSelected() async {
      final existingMap = await DatabaseService.instance.getOpeningStocksForMonth(year, month);
      for (final p in products) {
        final v = existingMap[p.id] ?? 0;
        controllers[p.id]!.text = v.toStringAsFixed(v % 1 == 0 ? 0 : 2);
      }
    }

    await loadForSelected();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) => AlertDialog(
          title: Text('Tồn đầu kỳ $month/$year'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: month,
                        decoration: const InputDecoration(labelText: 'Tháng', isDense: true),
                        items: List.generate(
                          12,
                          (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}')),
                        ),
                        onChanged: (v) async {
                          if (v == null) return;
                          month = v;
                          await loadForSelected();
                          setStateDialog(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: year,
                        decoration: const InputDecoration(labelText: 'Năm', isDense: true),
                        items: List.generate(
                          11,
                          (i) {
                            final y = now.year - 5 + i;
                            return DropdownMenuItem(value: y, child: Text('$y'));
                          },
                        ),
                        onChanged: (v) async {
                          if (v == null) return;
                          year = v;
                          await loadForSelected();
                          setStateDialog(() {});
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('Lấy tồn hiện tại cho tất cả'),
                    onPressed: () {
                      for (final p in products) {
                        final v = p.currentStock;
                        controllers[p.id]!.text = v.toStringAsFixed(v % 1 == 0 ? 0 : 2);
                      }
                      setStateDialog(() {});
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: products.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final p = products[i];
                      final ctrl = controllers[p.id]!;
                      return ListTile(
                        title: Text(p.name),
                        subtitle: Text('Đơn vị: ${p.unit}'),
                        trailing: SizedBox(
                          width: 120,
                          child: TextField(
                            controller: ctrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [NumberInputFormatter(maxDecimalDigits: 2)],
                            decoration: const InputDecoration(
                              labelText: 'Tồn',
                              isDense: true,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lưu')),
          ],
        ),
      ),
    );

    if (ok == true) {
      final map = <String, double>{};
      controllers.forEach((productId, ctrl) {
        final v = NumberInputFormatter.tryParse(ctrl.text) ?? 0;
        map[productId] = v;
      });
      await DatabaseService.instance.upsertOpeningStocksForMonth(year: year, month: month, openingByProductId: map);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu tồn đầu kỳ')));
    }
  }
}
