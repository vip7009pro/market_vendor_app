import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/product_provider.dart';
import '../models/product.dart';
import 'package:intl/intl.dart';
import 'scan_screen.dart';

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
            title: Text(p.name),
            subtitle: Text('${currency.format(p.price)} / ${p.unit}'),
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
      // Soft-delete by mark inactive
      final updated = Product(
        id: p.id,
        name: p.name,
        price: p.price,
        unit: p.unit,
        barcode: p.barcode,
        isActive: false,
      );
      await context.read<ProductProvider>().update(updated);
    }
  }

  Future<void> _showProductDialog(BuildContext context, {Product? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl = TextEditingController(text: existing?.price.toStringAsFixed(0) ?? '0');
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
            TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Giá')), 
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
          unit: unitCtrl.text.trim(),
          barcode: barcodeCtrl.text.trim().isEmpty ? null : barcodeCtrl.text.trim(),
        ));
      } else {
        await provider.update(Product(
          id: existing.id,
          name: nameCtrl.text.trim(),
          price: double.tryParse(priceCtrl.text.trim()) ?? 0,
          unit: unitCtrl.text.trim(),
          barcode: barcodeCtrl.text.trim().isEmpty ? null : barcodeCtrl.text.trim(),
          isActive: existing.isActive,
        ));
      }
    }
  }
}
