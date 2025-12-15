import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/product.dart';
import '../providers/product_provider.dart';
import '../services/database_service.dart';
import '../utils/contact_serializer.dart';
import '../utils/number_input_formatter.dart';
import '../utils/text_normalizer.dart';

class PurchaseHistoryScreen extends StatefulWidget {
  const PurchaseHistoryScreen({super.key});

  @override
  State<PurchaseHistoryScreen> createState() => _PurchaseHistoryScreenState();
}

class _PurchaseHistoryScreenState extends State<PurchaseHistoryScreen> {
  DateTimeRange? _range;
  String _query = '';

  static const _prefLastSupplierName = 'purchase_last_supplier_name';
  static const _prefLastSupplierPhone = 'purchase_last_supplier_phone';

  String removeDiacritics(String str) {
    const withDiacritics = 'áàảãạăắằẳẵặâấầuẩẫậéèẻẽẹêếềểễệíìỉĩịóòỏõọôốồổỗộơớờởỡợúùủũụưứừửữựýỳỷỹỵđ';
    const withoutDiacritics = 'aaaaaăaaaaaaâaaaaaaeeeeeêeeeeeiiiiioooooôooooooơooooouuuuuưuuuuuyyyyyd';
    String result = str.toLowerCase();
    for (int i = 0; i < withDiacritics.length; i++) {
      result = result.replaceAll(withDiacritics[i], withoutDiacritics[i]);
    }
    return result;
  }

  Future<Contact?> _showContactPicker(BuildContext context, List<Contact> contacts) async {
    final TextEditingController searchController = TextEditingController();
    List<Contact> filteredContacts = List.from(contacts);

    return await showModalBottomSheet<Contact>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              padding: const EdgeInsets.all(16),
              height: MediaQuery.of(context).size.height * 0.8,
              child: Column(
                children: [
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      labelText: 'Tìm kiếm liên hệ',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          searchController.clear();
                          setState(() {
                            filteredContacts = List.from(contacts);
                          });
                        },
                      ),
                    ),
                    onChanged: (value) {
                      if (value.isEmpty) {
                        setState(() {
                          filteredContacts = List.from(contacts);
                        });
                      } else {
                        final query = value.toLowerCase();
                        setState(() {
                          filteredContacts = contacts.where((contact) {
                            final nameMatch = contact.displayName.toLowerCase().contains(query);
                            final phoneMatch = contact.phones.any(
                              (phone) => phone.number.contains(query),
                            );
                            return nameMatch || phoneMatch;
                          }).toList();
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: filteredContacts.isEmpty
                        ? const Center(
                            child: Text('Không tìm thấy liên hệ nào'),
                          )
                        : ListView.builder(
                            itemCount: filteredContacts.length,
                            itemBuilder: (context, index) {
                              final contact = filteredContacts[index];
                              return ListTile(
                                leading: contact.photo != null
                                    ? CircleAvatar(
                                        backgroundImage: MemoryImage(contact.photo!), 
                                        radius: 20,
                                      )
                                    : const CircleAvatar(
                                        child: Icon(Icons.person),
                                        radius: 20,
                                      ),
                                title: Text(contact.displayName),
                                subtitle: Text(
                                  contact.phones.isNotEmpty
                                      ? contact.phones.first.number
                                      : 'Không có SĐT',
                                ),
                                onTap: () {
                                  Navigator.of(context).pop(contact);
                                },
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

  Future<Product?> _addNewProductDialog() async {
    final nameCtrl = TextEditingController();
    final unitCtrl = TextEditingController(text: 'cái');
    final priceCtrl = TextEditingController(text: '0');
    final costPriceCtrl = TextEditingController(text: '0');
    final barcodeCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Thêm sản phẩm'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Tên sản phẩm')),
            const SizedBox(height: 8),
            TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
              decoration: const InputDecoration(labelText: 'Giá bán'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: costPriceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
              decoration: const InputDecoration(labelText: 'Giá vốn'),
            ),
            const SizedBox(height: 8),
            TextField(controller: unitCtrl, decoration: const InputDecoration(labelText: 'Đơn vị')),
            const SizedBox(height: 8),
            TextField(controller: barcodeCtrl, decoration: const InputDecoration(labelText: 'Mã vạch (tuỳ chọn)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lưu')),
        ],
      ),
    );

    if (ok != true) return null;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return null;

    final provider = context.read<ProductProvider>();
    final newName = TextNormalizer.normalize(name);
    final duplicated = provider.products.any((p) => TextNormalizer.normalize(p.name) == newName);
    if (duplicated) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã tồn tại sản phẩm cùng tên')));
      return null;
    }

    final p = Product(
      name: name,
      price: NumberInputFormatter.tryParse(priceCtrl.text) ?? 0,
      costPrice: NumberInputFormatter.tryParse(costPriceCtrl.text) ?? 0,
      unit: unitCtrl.text.trim().isEmpty ? 'cái' : unitCtrl.text.trim(),
      barcode: barcodeCtrl.text.trim().isEmpty ? null : barcodeCtrl.text.trim(),
      currentStock: 0,
    );
    await provider.add(p);
    await context.read<ProductProvider>().load();
    return p;
  }

  Future<void> _addPurchaseDialog() async {
    var products = context.read<ProductProvider>().products;
    if (products.isEmpty) {
      final created = await _addNewProductDialog();
      if (created == null) return;
      products = context.read<ProductProvider>().products;
    }

    final prefs = await SharedPreferences.getInstance();
    final lastSupplierName = prefs.getString(_prefLastSupplierName);
    final lastSupplierPhone = prefs.getString(_prefLastSupplierPhone);

    String selectedProductId = products.first.id;
    final qtyCtrl = TextEditingController(text: '1');
    final unitCostCtrl = TextEditingController(text: products.first.costPrice.toStringAsFixed(0));
    final noteCtrl = TextEditingController();
    final supplierNameCtrl = TextEditingController(text: lastSupplierName ?? '');
    final supplierPhoneCtrl = TextEditingController(text: lastSupplierPhone ?? '');

    List<Contact> allContacts = await ContactSerializer.loadContactsFromPrefs();
    if (allContacts.isEmpty) {
      try {
        final granted = await FlutterContacts.requestPermission();
        if (granted) {
          allContacts = await FlutterContacts.getContacts(withProperties: true, withPhoto: true);
          await ContactSerializer.saveContactsToPrefs(allContacts);
        }
      } catch (e) {
        debugPrint('Error getting contacts in purchase dialog: $e');
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) => AlertDialog(
          title: const Text('Nhập hàng'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: supplierNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nhà cung cấp (tuỳ chọn)',
                      ),
                      readOnly: true,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.contacts),
                    onPressed: () async {
                      final contact = await _showContactPicker(context, allContacts);
                      if (contact != null && mounted) {
                        supplierNameCtrl.text = contact.displayName;
                        supplierPhoneCtrl.text = contact.phones.isNotEmpty ? contact.phones.first.number : '';
                        setStateDialog(() {});
                      }
                    },
                    tooltip: 'Chọn từ danh bạ',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: supplierPhoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'SĐT nhà cung cấp (tuỳ chọn)',
                ),
                readOnly: true,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: selectedProductId,
                decoration: const InputDecoration(labelText: 'Sản phẩm'),
                items: products
                    .map((p) => DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (id) {
                  if (id == null) return;
                  selectedProductId = id;
                  try {
                    final p = products.firstWhere((e) => e.id == selectedProductId);
                    unitCostCtrl.text = p.costPrice.toStringAsFixed(0);
                  } catch (_) {}
                  setStateDialog(() {});
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [NumberInputFormatter(maxDecimalDigits: 2)],
                decoration: InputDecoration(
                  labelText: () {
                    try {
                      final p = products.firstWhere((e) => e.id == selectedProductId);
                      return 'Số lượng (${p.unit})';
                    } catch (_) {
                      return 'Số lượng';
                    }
                  }(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: unitCostCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
                decoration: const InputDecoration(labelText: 'Giá nhập / đơn vị'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: 'Ghi chú (tuỳ chọn)'),
              ),
              const SizedBox(height: 8),
              Text(
                () {
                  try {
                    final p = products.firstWhere((e) => e.id == selectedProductId);
                    return 'Tồn hiện tại: ${p.currentStock.toStringAsFixed(p.currentStock % 1 == 0 ? 0 : 2)} ${p.unit}';
                  } catch (_) {
                    return 'Tồn hiện tại: 0';
                  }
                }(),
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final created = await _addNewProductDialog();
                if (created == null) return;
                products = context.read<ProductProvider>().products;
                selectedProductId = created.id;
                unitCostCtrl.text = created.costPrice.toStringAsFixed(0);
                setStateDialog(() {});
              },
              child: const Text('Thêm sản phẩm'),
            ),
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lưu')),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final qty = NumberInputFormatter.tryParse(qtyCtrl.text) ?? 0;
    final unitCost = NumberInputFormatter.tryParse(unitCostCtrl.text) ?? 0;
    if (qty <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Số lượng không hợp lệ')));
      return;
    }

    late final Product selected;
    try {
      selected = context.read<ProductProvider>().products.firstWhere((p) => p.id == selectedProductId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sản phẩm không hợp lệ')));
      return;
    }

    await DatabaseService.instance.insertPurchaseHistory(
      productId: selected.id,
      productName: selected.name,
      quantity: qty,
      unitCost: unitCost,
      supplierName: supplierNameCtrl.text.trim().isEmpty ? null : supplierNameCtrl.text.trim(),
      supplierPhone: supplierPhoneCtrl.text.trim().isEmpty ? null : supplierPhoneCtrl.text.trim(),
      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
    );

    await prefs.setString(_prefLastSupplierName, supplierNameCtrl.text.trim());
    await prefs.setString(_prefLastSupplierPhone, supplierPhoneCtrl.text.trim());

    await context.read<ProductProvider>().load();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã nhập hàng')));
  }

  Future<List<Map<String, dynamic>>> _load() {
    return DatabaseService.instance.getPurchaseHistory(range: _range, query: _query);
  }

  @override
  Widget build(BuildContext context) {
    final fmtDate = DateFormat('dd/MM/yyyy HH:mm');
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử nhập hàng'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Nhập hàng',
            onPressed: _addPurchaseDialog,
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
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
              }
            },
          ),
          if (_range != null)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Xoá lọc ngày',
              onPressed: () => setState(() => _range = null),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Tìm theo tên sản phẩm / nhà cung cấp / ghi chú',
                isDense: true,
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _load(),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snap.data ?? const [];
                if (rows.isEmpty) {
                  return const Center(child: Text('Chưa có lịch sử nhập hàng'));
                }

                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    final createdAt = DateTime.tryParse(r['createdAt'] as String? ?? '') ?? DateTime.now();
                    final name = (r['productName'] as String?) ?? '';
                    final qty = (r['quantity'] as num?)?.toDouble() ?? 0;
                    final unitCost = (r['unitCost'] as num?)?.toDouble() ?? 0;
                    final totalCost = (r['totalCost'] as num?)?.toDouble() ?? (qty * unitCost);
                    final note = (r['note'] as String?)?.trim();
                    final supplierName = (r['supplierName'] as String?)?.trim();

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.green.withValues(alpha: 0.12),
                        foregroundColor: Colors.green,
                        child: const Icon(Icons.add_shopping_cart),
                      ),
                      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SL: ${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2)}  |  Giá nhập: ${currency.format(unitCost)}'),
                          Text('Thành tiền: ${currency.format(totalCost)}'),
                          if (supplierName != null && supplierName.isNotEmpty) Text('NCC: $supplierName'),
                          Text(fmtDate.format(createdAt), style: const TextStyle(color: Colors.black54)),
                          if (note != null && note.isNotEmpty) Text('Ghi chú: $note'),
                        ],
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
