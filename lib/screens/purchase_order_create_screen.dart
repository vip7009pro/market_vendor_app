import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/customer.dart';
import '../models/debt.dart';
import '../models/product.dart';
import '../providers/customer_provider.dart';
import '../providers/debt_provider.dart';
import '../providers/product_provider.dart';
import '../services/database_service.dart';
import '../utils/number_input_formatter.dart';
import '../utils/contact_serializer.dart';
import '../utils/text_normalizer.dart';
import 'purchase_order_detail_screen.dart';

class PurchaseOrderCreateScreen extends StatefulWidget {
  final String? purchaseOrderId;

  const PurchaseOrderCreateScreen({
    super.key,
    this.purchaseOrderId,
  });

  @override
  State<PurchaseOrderCreateScreen> createState() => _PurchaseOrderCreateScreenState();
}

class _PurchaseOrderLine {
  final Product product;
  final TextEditingController qtyCtrl;
  final TextEditingController unitCostCtrl;
  final String? purchaseHistoryId;

  static final NumberFormat _fmtInt = NumberFormat.decimalPattern('en_US');

  static String _fmtQty(double v) {
    final vv = v.clamp(0.0, double.infinity).toDouble();
    final intPart = vv.floor();
    final dec = (vv - intPart).abs();
    if (dec < 0.0000001) {
      return _fmtInt.format(intPart);
    }
    final fixed = vv.toStringAsFixed(2);
    final parts = fixed.split('.');
    final intText = _fmtInt.format(int.tryParse(parts[0]) ?? 0);
    final decText = parts.length > 1 ? parts[1] : '00';
    final trimmedDec = decText.replaceFirst(RegExp(r'0+$'), '');
    return trimmedDec.isEmpty ? intText : '$intText.$trimmedDec';
  }

  static String _fmtMoney(double v) {
    return _fmtInt.format(v.clamp(0.0, double.infinity).round());
  }

  _PurchaseOrderLine({
    required this.product,
    required double quantity,
    required double unitCost,
    this.purchaseHistoryId,
  })  : qtyCtrl = TextEditingController(text: _fmtQty(quantity)),
        unitCostCtrl = TextEditingController(text: _fmtMoney(unitCost));

  double get quantity => NumberInputFormatter.tryParse(qtyCtrl.text.trim()) ?? 0.0;

  double get unitCost => NumberInputFormatter.tryParse(unitCostCtrl.text.trim()) ?? 0.0;

  double get lineTotal => (quantity * unitCost).clamp(0.0, double.infinity).toDouble();

  void dispose() {
    qtyCtrl.dispose();
    unitCostCtrl.dispose();
  }
}

class _PurchaseOrderCreateScreenState extends State<PurchaseOrderCreateScreen> {
  final _supplierNameCtrl = TextEditingController();
  final _supplierPhoneCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  Customer? _selectedSupplier;

  DateTime _createdAt = DateTime.now();

  String _discountType = 'AMOUNT';
  final _discountValueCtrl = TextEditingController(text: '0');
  final _paidAmountCtrl = TextEditingController(text: '0');

  bool _autoPaid = true;

  final List<_PurchaseOrderLine> _lines = [];

  final Set<String> _initialPurchaseHistoryIds = <String>{};

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<ProductProvider>();
      if (provider.products.isEmpty) {
        await provider.load();
        if (!mounted) return;
        setState(() {});
      }

      final customerProvider = context.read<CustomerProvider>();
      if (customerProvider.customers.isEmpty) {
        await customerProvider.load();
        if (!mounted) return;
        setState(() {});
      }

      final orderId = widget.purchaseOrderId;
      if (orderId != null && orderId.trim().isNotEmpty) {
        await _loadExistingOrder(orderId.trim());
        if (!mounted) return;
        setState(() {});
      }
    });
  }

  Future<void> _loadExistingOrder(String purchaseOrderId) async {
    final order = await DatabaseService.instance.getPurchaseOrderById(purchaseOrderId);
    if (order == null) return;

    final createdAt = DateTime.tryParse(order['createdAt'] as String? ?? '') ?? DateTime.now();
    final supplierName = (order['supplierName'] as String?)?.trim() ?? '';
    final supplierPhone = (order['supplierPhone'] as String?)?.trim() ?? '';
    final note = (order['note'] as String?)?.trim() ?? '';

    String discountType = ((order['discountType'] as String?) ?? 'AMOUNT').toUpperCase().trim();
    if (discountType != 'PERCENT') discountType = 'AMOUNT';
    final discountValue = (order['discountValue'] as num?)?.toDouble() ?? 0.0;
    final paidAmount = (order['paidAmount'] as num?)?.toDouble() ?? 0.0;

    _createdAt = createdAt;
    _supplierNameCtrl.text = supplierName;
    _supplierPhoneCtrl.text = supplierPhone;
    _noteCtrl.text = note;
    _discountType = discountType;
    _discountValueCtrl.text = NumberFormat.decimalPattern('en_US').format(discountValue.round());
    _paidAmountCtrl.text = NumberFormat.decimalPattern('en_US').format(paidAmount.round());
    _autoPaid = false;

    final rows = await DatabaseService.instance.getPurchaseHistoryByOrderId(purchaseOrderId);
    final products = context.read<ProductProvider>().products;

    for (final l in _lines) {
      l.dispose();
    }
    _lines.clear();
    _initialPurchaseHistoryIds.clear();

    for (final r in rows) {
      final lineId = (r['id'] as String?)?.trim();
      final productId = (r['productId'] as String?)?.trim() ?? '';
      final productName = (r['productName'] as String?)?.trim() ?? '';
      final qty = (r['quantity'] as num?)?.toDouble() ?? 0.0;
      final unitCost = (r['unitCost'] as num?)?.toDouble() ?? 0.0;

      Product? p;
      try {
        p = products.firstWhere((e) => e.id == productId);
      } catch (_) {
        p = Product(
          id: productId.isEmpty ? null : productId,
          name: productName.isEmpty ? 'Sản phẩm' : productName,
          price: 0,
          costPrice: unitCost,
          unit: 'cái',
        );
      }

      _lines.add(
        _PurchaseOrderLine(
          product: p,
          quantity: qty <= 0 ? 1 : qty,
          unitCost: unitCost < 0 ? 0 : unitCost,
          purchaseHistoryId: lineId,
        ),
      );
      if (lineId != null && lineId.isNotEmpty) {
        _initialPurchaseHistoryIds.add(lineId);
      }
    }

    final subtotal = _subtotal;
    final dis = _discountAmount(subtotal);
    final total = (subtotal - dis).clamp(0.0, double.infinity).toDouble();
    if ((paidAmount - total).abs() < 0.01) {
      _autoPaid = true;
      _syncPaidIfAuto();
    }
  }

  @override
  void dispose() {
    _supplierNameCtrl.dispose();
    _supplierPhoneCtrl.dispose();
    _noteCtrl.dispose();
    _discountValueCtrl.dispose();
    _paidAmountCtrl.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  double get _discountValue => NumberInputFormatter.tryParse(_discountValueCtrl.text.trim()) ?? 0.0;

  double get _paidAmount => NumberInputFormatter.tryParse(_paidAmountCtrl.text.trim()) ?? 0.0;

  double get _subtotal {
    var s = 0.0;
    for (final l in _lines) {
      s += l.lineTotal;
    }
    return s.clamp(0.0, double.infinity).toDouble();
  }

  double _discountAmount(double subtotal) {
    final dv = _discountValue;
    if (dv <= 0) return 0.0;
    if (_discountType == 'PERCENT') {
      return (subtotal * (dv / 100.0)).clamp(0.0, double.infinity).toDouble();
    }
    return dv.clamp(0.0, double.infinity).toDouble();
  }

  double get _total {
    final subtotal = _subtotal;
    final dis = _discountAmount(subtotal);
    return (subtotal - dis).clamp(0.0, double.infinity).toDouble();
  }

  double get _remainDebt => (_total - _paidAmount).clamp(0.0, double.infinity).toDouble();

  void _setPaidText(double v) {
    final t = v.clamp(0.0, double.infinity).toDouble();
    final formatted = NumberFormat.decimalPattern('en_US').format(t.round());
    _paidAmountCtrl.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  void _syncPaidIfAuto() {
    if (!_autoPaid) return;
    _setPaidText(_total);
  }

  Future<Contact?> _showContactPicker(BuildContext context, List<Contact> contacts) async {
    final TextEditingController searchController = TextEditingController();
    List<Contact> filteredContacts = List.from(contacts);

    final selected = await showModalBottomSheet<Contact>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: searchController,
                      decoration: const InputDecoration(
                        hintText: 'Tìm danh bạ...',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                      onChanged: (value) {
                        final query = value.toLowerCase();
                        filteredContacts = contacts
                            .where((c) => c.displayName.toLowerCase().contains(query))
                            .toList(growable: false);
                        (context as Element).markNeedsBuild();
                      },
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      itemCount: filteredContacts.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final contact = filteredContacts[index];
                        final phone = contact.phones.isNotEmpty ? contact.phones.first.number : '';
                        return ListTile(
                          title: Text(contact.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(phone, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => Navigator.pop(context, contact),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    searchController.dispose();
    return selected;
  }

  Future<Customer?> _createSupplierDialog() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    List<Contact> allContacts = await ContactSerializer.loadContactsFromPrefs();
    if (allContacts.isEmpty) {
      try {
        final granted = await FlutterContacts.requestPermission();
        if (granted) {
          allContacts = await FlutterContacts.getContacts(withProperties: true, withPhoto: true);
          await ContactSerializer.saveContactsToPrefs(allContacts);
        }
      } catch (_) {}
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Thêm nhà cung cấp'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(labelText: 'Tên nhà cung cấp'),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Chọn từ danh bạ',
                      icon: const Icon(Icons.contacts),
                      onPressed: allContacts.isEmpty
                          ? null
                          : () async {
                              final picked = await _showContactPicker(context, allContacts);
                              if (picked == null) return;
                              nameCtrl.text = picked.displayName;
                              phoneCtrl.text = picked.phones.isNotEmpty ? picked.phones.first.number : '';
                            },
                    ),
                  ],
                ),
                TextField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'SĐT'),
                  keyboardType: TextInputType.phone,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Thêm')),
          ],
        );
      },
    );

    if (ok != true) {
      nameCtrl.dispose();
      phoneCtrl.dispose();
      return null;
    }

    final name = nameCtrl.text.trim();
    final phone = phoneCtrl.text.trim();

    nameCtrl.dispose();
    phoneCtrl.dispose();

    if (name.isEmpty) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập tên nhà cung cấp')));
      return null;
    }

    final provider = context.read<CustomerProvider>();
    final c = Customer(
      name: name,
      phone: phone.isEmpty ? null : phone,
      isSupplier: true,
    );
    await provider.add(c);
    await provider.load();
    return c;
  }

  Future<Customer?> _pickSupplier() async {
    final provider = context.read<CustomerProvider>();
    if (provider.customers.isEmpty) {
      await provider.load();
    }
    final allCustomers = provider.customers.toList();
    String q = '';

    return showModalBottomSheet<Customer?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            final norm = TextNormalizer.normalize(q);
            final filtered = norm.isEmpty
                ? allCustomers
                : allCustomers
                    .where((c) => TextNormalizer.normalize(c.name).contains(norm))
                    .toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.78,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: 'Tìm nhà cung cấp',
                            isDense: true,
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (v) => setLocal(() => q = v),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.add),
                        title: const Text('Thêm nhà cung cấp mới'),
                        onTap: () async {
                          final c = await _createSupplierDialog();
                          if (c == null) return;
                          if (!context.mounted) return;
                          Navigator.pop(context, c);
                        },
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(child: Text('Chưa có khách hàng'))
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, i) {
                                  final c = filtered[i];
                                  final phone = (c.phone ?? '').trim();
                                  final role = c.isSupplier ? 'NCC' : 'KH';
                                  return ListTile(
                                    title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    subtitle: Text(phone.isEmpty ? role : '$role | $phone'),
                                    onTap: () => Navigator.pop(context, c),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<Customer?> _ensureSupplier({required String supplierName, String? supplierPhone}) async {
    if (supplierName.trim().isEmpty) return null;
    final provider = context.read<CustomerProvider>();
    if (provider.customers.isEmpty) {
      await provider.load();
    }
    final normalized = TextNormalizer.normalize(supplierName);
    try {
      final existing = provider.customers.firstWhere(
        (c) => c.isSupplier && TextNormalizer.normalize(c.name) == normalized,
      );
      return existing;
    } catch (_) {
      final created = Customer(
        name: supplierName.trim(),
        phone: supplierPhone?.trim().isEmpty == true ? null : supplierPhone?.trim(),
        isSupplier: true,
      );
      await provider.add(created);
      await provider.load();
      return created;
    }
  }

  Future<Product?> _pickProduct() async {
    final products = context.read<ProductProvider>().products;
    String q = '';

    return showModalBottomSheet<Product?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            final norm = TextNormalizer.normalize(q);
            final filtered = norm.isEmpty
                ? products
                : products.where((p) {
                    final name = TextNormalizer.normalize(p.name);
                    final barcode = TextNormalizer.normalize(p.barcode ?? '');
                    return name.contains(norm) || (barcode.isNotEmpty && barcode.contains(norm));
                  }).toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.78,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: 'Tìm theo tên / mã vạch',
                            isDense: true,
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (v) => setLocal(() => q = v),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.add),
                        title: const Text('Thêm sản phẩm mới'),
                        onTap: () async {
                          final p = await _createProductDialog();
                          if (p == null) return;
                          if (!context.mounted) return;
                          Navigator.pop(context, p);
                        },
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(child: Text('Không có sản phẩm'))
                            : ListView.separated(
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (context, i) {
                                  final p = filtered[i];
                                  return ListTile(
                                    title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    subtitle: Text('${p.unit} | Giá vốn: ${p.costPrice.toStringAsFixed(0)}'),
                                    onTap: () => Navigator.pop(context, p),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<Product?> _createProductDialog() async {
    final nameCtrl = TextEditingController();
    final unitCtrl = TextEditingController(text: 'cái');
    final priceCtrl = TextEditingController(text: '0');
    final costCtrl = TextEditingController(text: '0');
    final barcodeCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Thêm sản phẩm'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Tên sản phẩm'),
                ),
                TextField(
                  controller: unitCtrl,
                  decoration: const InputDecoration(labelText: 'Đơn vị'),
                ),
                TextField(
                  controller: priceCtrl,
                  decoration: const InputDecoration(labelText: 'Giá bán'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
                ),
                TextField(
                  controller: costCtrl,
                  decoration: const InputDecoration(labelText: 'Giá vốn'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
                ),
                TextField(
                  controller: barcodeCtrl,
                  decoration: const InputDecoration(labelText: 'Mã vạch (tuỳ chọn)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Thêm')),
          ],
        );
      },
    );

    if (ok != true) {
      nameCtrl.dispose();
      unitCtrl.dispose();
      priceCtrl.dispose();
      costCtrl.dispose();
      barcodeCtrl.dispose();
      return null;
    }

    final name = nameCtrl.text.trim();
    final unit = unitCtrl.text.trim();
    final price = NumberInputFormatter.tryParse(priceCtrl.text.trim()) ?? 0.0;
    final costPrice = NumberInputFormatter.tryParse(costCtrl.text.trim()) ?? 0.0;
    final barcode = barcodeCtrl.text.trim();

    nameCtrl.dispose();
    unitCtrl.dispose();
    priceCtrl.dispose();
    costCtrl.dispose();
    barcodeCtrl.dispose();

    if (name.isEmpty || unit.isEmpty) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập tên và đơn vị')));
      return null;
    }

    final p = Product(
      name: name,
      unit: unit,
      price: price,
      costPrice: costPrice,
      barcode: barcode.isEmpty ? null : barcode,
    );

    await context.read<ProductProvider>().add(p);

    return p;
  }

  void _addLine(Product p) {
    final exists = _lines.indexWhere((e) => e.product.id == p.id);
    if (exists != -1) {
      final old = _lines[exists];
      final nextQty = (old.quantity + 1).clamp(0.0, double.infinity).toDouble();
      old.qtyCtrl.text = _PurchaseOrderLine._fmtQty(nextQty);
      setState(() {
        _syncPaidIfAuto();
      });
      return;
    }

    _lines.add(
      _PurchaseOrderLine(
        product: p,
        quantity: 1,
        unitCost: p.costPrice,
      ),
    );
    setState(() {
      _syncPaidIfAuto();
    });
  }

  Future<void> _addProductToOrder() async {
    final p = await _pickProduct();
    if (p == null) return;
    _addLine(p);
  }

  Future<void> _pickCreatedAt() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(DateTime.now().year - 3),
      lastDate: DateTime(DateTime.now().year + 1),
      initialDate: _createdAt,
    );
    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_createdAt),
    );
    if (time == null) return;

    setState(() {
      _createdAt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    if (_saving) return;

    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng chọn ít nhất 1 sản phẩm')));
      return;
    }

    for (final l in _lines) {
      if (l.quantity <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Số lượng phải > 0')));
        return;
      }
      if (l.unitCost < 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Giá nhập không hợp lệ')));
        return;
      }
    }

    final supplierName = _supplierNameCtrl.text.trim();
    final supplierPhone = _supplierPhoneCtrl.text.trim();
    final remainDebt = _remainDebt;
    if (remainDebt > 0 && supplierName.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Vui lòng nhập nhà cung cấp khi có nợ')));
      return;
    }

    setState(() => _saving = true);
    try {
      final subtotal = _subtotal;
      final discountAmount = _discountAmount(subtotal);
      final total = _total;
      final paid = _paidAmount;

      final editingId = widget.purchaseOrderId;
      if (editingId != null && editingId.trim().isNotEmpty) {
        final orderId = editingId.trim();
        final noteText = _noteCtrl.text.trim();

        await DatabaseService.instance.updatePurchaseOrder(
          id: orderId,
          createdAt: _createdAt,
          supplierName: supplierName.isEmpty ? null : supplierName,
          supplierPhone: supplierPhone.isEmpty ? null : supplierPhone,
          discountType: _discountType,
          discountValue: _discountValue,
          paidAmount: paid,
          note: noteText.isEmpty ? null : noteText,
        );

        final remainLineIds = <String>{};
        for (final l in _lines) {
          final lineId = l.purchaseHistoryId;
          if (lineId != null && lineId.isNotEmpty) {
            remainLineIds.add(lineId);
          }
        }

        for (final oldId in _initialPurchaseHistoryIds) {
          if (!remainLineIds.contains(oldId)) {
            await DatabaseService.instance.deletePurchaseHistory(oldId);
          }
        }

        for (final l in _lines) {
          final lineTotal = (l.quantity * l.unitCost).clamp(0.0, double.infinity).toDouble();
          if (l.purchaseHistoryId != null && l.purchaseHistoryId!.trim().isNotEmpty) {
            await DatabaseService.instance.updatePurchaseHistory(
              id: l.purchaseHistoryId!.trim(),
              productId: l.product.id,
              productName: l.product.name,
              quantity: l.quantity,
              unitCost: l.unitCost,
              paidAmount: lineTotal,
              supplierName: supplierName.isEmpty ? null : supplierName,
              supplierPhone: supplierPhone.isEmpty ? null : supplierPhone,
              note: noteText.isEmpty ? null : noteText,
              createdAt: _createdAt,
              purchaseOrderId: orderId,
            );
          } else {
            await DatabaseService.instance.insertPurchaseHistory(
              productId: l.product.id,
              productName: l.product.name,
              quantity: l.quantity,
              unitCost: l.unitCost,
              paidAmount: lineTotal,
              supplierName: supplierName.isEmpty ? null : supplierName,
              supplierPhone: supplierPhone.isEmpty ? null : supplierPhone,
              note: noteText.isEmpty ? null : noteText,
              createdAt: _createdAt,
              purchaseOrderId: orderId,
            );
          }
        }

        await DatabaseService.instance.syncPurchaseOrderDebt(purchaseOrderId: orderId);

        await context.read<ProductProvider>().load();
        await context.read<DebtProvider>().load();

        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }

      final orderId = await DatabaseService.instance.insertPurchaseOrder(
        createdAt: _createdAt,
        supplierName: supplierName.isEmpty ? null : supplierName,
        supplierPhone: supplierPhone.isEmpty ? null : supplierPhone,
        discountType: _discountType,
        discountValue: _discountValue,
        paidAmount: paid,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );

      for (final l in _lines) {
        final lineTotal = (l.quantity * l.unitCost).clamp(0.0, double.infinity).toDouble();
        await DatabaseService.instance.insertPurchaseHistory(
          productId: l.product.id,
          productName: l.product.name,
          quantity: l.quantity,
          unitCost: l.unitCost,
          paidAmount: lineTotal,
          supplierName: supplierName.isEmpty ? null : supplierName,
          supplierPhone: supplierPhone.isEmpty ? null : supplierPhone,
          note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
          createdAt: _createdAt,
          purchaseOrderId: orderId,
        );
      }

      if (remainDebt > 0) {
        Customer? supplier = _selectedSupplier;
        if (supplier == null) {
          supplier = await _ensureSupplier(
            supplierName: supplierName,
            supplierPhone: supplierPhone.isEmpty ? null : supplierPhone,
          );
        }

        final buf = StringBuffer();
        buf.write('Đơn nhập hàng');
        if (supplierName.isNotEmpty) buf.write(' | NCC: $supplierName');
        buf.write('\nNgày: ${DateFormat('dd/MM/yyyy HH:mm').format(_createdAt)}');
        if (_noteCtrl.text.trim().isNotEmpty) buf.write('\nGhi chú: ${_noteCtrl.text.trim()}');
        buf.write('\n');
        for (final l in _lines) {
          final qty = l.quantity;
          final unitCost = l.unitCost;
          final lineTotal = (qty * unitCost).clamp(0.0, double.infinity).toDouble();
          buf.write(
            '\n- ${l.product.name}: SL ${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2)} ${l.product.unit}, Giá ${NumberFormat.decimalPattern('en_US').format(unitCost.round())}, Tiền ${NumberFormat.decimalPattern('en_US').format(lineTotal.round())}',
          );
        }
        buf.write('\n');
        buf.write(
          '\nTạm tính: ${NumberFormat.decimalPattern('en_US').format(subtotal.round())}',
        );
        buf.write(
          '\nChiết khấu: ${NumberFormat.decimalPattern('en_US').format(discountAmount.round())}',
        );
        buf.write(
          '\nTổng đơn: ${NumberFormat.decimalPattern('en_US').format(total.round())}',
        );
        buf.write(
          '\nĐã trả: ${NumberFormat.decimalPattern('en_US').format(paid.round())}',
        );
        buf.write(
          '\nCòn nợ: ${NumberFormat.decimalPattern('en_US').format(remainDebt.round())}',
        );

        final debt = Debt(
          type: DebtType.oweOthers,
          partyId: supplier?.id ?? 'supplier_unknown',
          partyName: supplier?.name ?? (supplierName.isEmpty ? 'Nhà cung cấp' : supplierName),
          amount: remainDebt,
          description: buf.toString().trim(),
          sourceType: 'purchase',
          sourceId: orderId,
        );
        await context.read<DebtProvider>().add(debt);
      }

      await context.read<ProductProvider>().load();

      if (!mounted) return;

      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PurchaseOrderDetailScreen(purchaseOrderId: orderId),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    final fmtDate = DateFormat('dd/MM/yyyy HH:mm');

    final fmtInt = NumberFormat.decimalPattern('en_US');

    final subtotal = _subtotal;
    final discountAmount = _discountAmount(subtotal);
    final total = _total;
    final paid = _paidAmount;
    final remain = _remainDebt;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.purchaseOrderId == null ? 'Tạo đơn nhập' : 'Sửa đơn nhập'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tổng: ${currency.format(total)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(
                      remain <= 0 ? 'Đã tất toán' : 'Còn nợ: ${currency.format(remain)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: remain <= 0 ? Colors.green : Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(widget.purchaseOrderId == null ? 'Lưu nhập hàng' : 'Cập nhật'),
              ),
            ],
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Nhà cung cấp', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                      TextButton.icon(
                        onPressed: _saving ? null : _pickCreatedAt,
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: Text(fmtDate.format(_createdAt)),
                      ),
                    ],
                  ),
                  TextField(
                    controller: _supplierNameCtrl,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Chọn nhà cung cấp',
                      isDense: true,
                      suffixIcon: IconButton(
                        tooltip: 'Chọn nhà cung cấp',
                        icon: const Icon(Icons.arrow_drop_down),
                        onPressed: _saving
                            ? null
                            : () async {
                                final c = await _pickSupplier();
                                if (c == null) return;
                                if (!c.isSupplier) {
                                  c.isSupplier = true;
                                  await context.read<CustomerProvider>().update(c);
                                  await context.read<CustomerProvider>().load();
                                }
                                _selectedSupplier = c;
                                _supplierNameCtrl.text = c.name;
                                _supplierPhoneCtrl.text = (c.phone ?? '').trim();
                                if (!mounted) return;
                                setState(() {});
                              },
                      ),
                    ),
                    onTap: _saving
                        ? null
                        : () async {
                            final c = await _pickSupplier();
                            if (c == null) return;
                            if (!c.isSupplier) {
                              c.isSupplier = true;
                              await context.read<CustomerProvider>().update(c);
                              await context.read<CustomerProvider>().load();
                            }
                            _selectedSupplier = c;
                            _supplierNameCtrl.text = c.name;
                            _supplierPhoneCtrl.text = (c.phone ?? '').trim();
                            if (!mounted) return;
                            setState(() {});
                          },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _supplierPhoneCtrl,
                          decoration: const InputDecoration(labelText: 'SĐT', isDense: true),
                          keyboardType: TextInputType.phone,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _noteCtrl,
                          decoration: const InputDecoration(labelText: 'Ghi chú', isDense: true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Text('Sản phẩm', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              FilledButton.tonalIcon(
                onPressed: _saving ? null : _addProductToOrder,
                icon: const Icon(Icons.add),
                label: const Text('Chọn sản phẩm'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_lines.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('Chưa có sản phẩm. Bấm "Chọn sản phẩm" để bắt đầu.'),
              ),
            ),
          if (_lines.isNotEmpty)
            Card(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _lines.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final l = _lines[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l.product.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Xoá dòng',
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              onPressed: _saving
                                  ? null
                                  : () {
                                      final removed = _lines.removeAt(i);
                                      removed.dispose();
                                      setState(() {
                                        _syncPaidIfAuto();
                                      });
                                    },
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: l.qtyCtrl,
                                decoration: InputDecoration(
                                  labelText: 'SL (${l.product.unit})',
                                  isDense: true,
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [NumberInputFormatter(maxDecimalDigits: 2)],
                                onChanged: (_) {
                                  setState(() {
                                    _syncPaidIfAuto();
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: l.unitCostCtrl,
                                decoration: const InputDecoration(labelText: 'Giá nhập', isDense: true),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
                                onChanged: (_) {
                                  setState(() {
                                    _syncPaidIfAuto();
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Thành tiền: ${currency.format(l.lineTotal)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Chiết khấu & thanh toán', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: DropdownButtonFormField<String>(
                          value: _discountType,
                          items: const [
                            DropdownMenuItem(value: 'AMOUNT', child: Text('CK: tiền')),
                            DropdownMenuItem(value: 'PERCENT', child: Text('CK: %')),
                          ],
                          onChanged: _saving
                              ? null
                              : (v) {
                                  if (v == null) return;
                                  setState(() {
                                    _discountType = v;
                                    _syncPaidIfAuto();
                                  });
                                },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 5,
                        child: TextField(
                          controller: _discountValueCtrl,
                          decoration: const InputDecoration(labelText: 'Giá trị CK', isDense: true),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [NumberInputFormatter(maxDecimalDigits: 2)],
                          onChanged: (_) {
                            setState(() {
                              _syncPaidIfAuto();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _paidAmountCtrl,
                          decoration: InputDecoration(
                            labelText: 'Đã thanh toán',
                            isDense: true,
                            helperText: _autoPaid ? 'Tự động theo tổng đơn' : null,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
                          onChanged: (_) {
                            _autoPaid = false;
                            setState(() {});
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () {
                                _autoPaid = false;
                                _setPaidText(0);
                                setState(() {});
                              },
                        child: const Text('Nợ tất'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () {
                                _autoPaid = true;
                                _syncPaidIfAuto();
                                setState(() {});
                              },
                        child: const Text('Trả đủ'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Tổng kết', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  _kv('Tạm tính', currency.format(subtotal)),
                  _kv('Chiết khấu', currency.format(discountAmount)),
                  _kv('Tổng đơn', currency.format(total), bold: true),
                  const Divider(height: 16),
                  _kv('Đã thanh toán', currency.format(paid)),
                  _kv(
                    'Còn nợ',
                    remain <= 0 ? '0' : fmtInt.format(remain.round()),
                    bold: true,
                    color: remain <= 0 ? Colors.green : Colors.redAccent,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _kv(
    String label,
    String value, {
    bool bold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}
