import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/product_provider.dart';
import '../models/product.dart';
import 'package:intl/intl.dart';
import 'scan_screen.dart';
import '../services/database_service.dart';

class ProductListScreen extends StatelessWidget {
  const ProductListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProductProvider>();
    final products = provider.products;
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sản phẩm'),
        actions: [
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
        ],
      ),
      body: ListView.separated(
        itemCount: products.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final p = products[i];
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showProductDialog(context),
        child: const Icon(Icons.add),
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
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl = TextEditingController(text: existing?.price.toStringAsFixed(0) ?? '0');
    final costPriceCtrl = TextEditingController(text: existing?.costPrice.toStringAsFixed(0) ?? '0');
    final existingStock = existing?.currentStock ?? 0;
    final stockCtrl = TextEditingController(text: existingStock.toStringAsFixed(existingStock % 1 == 0 ? 0 : 2));
    final unitCtrl = TextEditingController(text: existing?.unit ?? 'cái');
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
            TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Giá bán')), 
            const SizedBox(height: 8),
            TextField(controller: costPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Giá vốn')), 
            const SizedBox(height: 8),
            TextField(controller: stockCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tồn hiện tại')), 
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
      if (existing == null) {
        await provider.add(Product(
          name: nameCtrl.text.trim(),
          price: double.tryParse(priceCtrl.text.trim()) ?? 0,
          costPrice: double.tryParse(costPriceCtrl.text.trim()) ?? 0,
          currentStock: double.tryParse(stockCtrl.text.trim().replaceAll(',', '.')) ?? 0,
          unit: unitCtrl.text.trim(),
          barcode: barcodeCtrl.text.trim().isEmpty ? null : barcodeCtrl.text.trim(),
        ));
      } else {
        await provider.update(Product(
          id: existing.id,
          name: nameCtrl.text.trim(),
          price: double.tryParse(priceCtrl.text.trim()) ?? 0,
          costPrice: double.tryParse(costPriceCtrl.text.trim()) ?? 0,
          currentStock: double.tryParse(stockCtrl.text.trim().replaceAll(',', '.')) ?? 0,
          unit: unitCtrl.text.trim(),
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
        final v = double.tryParse(ctrl.text.trim().replaceAll(',', '.')) ?? 0;
        map[productId] = v;
      });
      await DatabaseService.instance.upsertOpeningStocksForMonth(year: year, month: month, openingByProductId: map);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu tồn đầu kỳ')));
    }
  }
}
