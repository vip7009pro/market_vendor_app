import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../providers/product_provider.dart';
import '../providers/sale_provider.dart';
import '../widgets/quantity_stepper.dart';
import '../models/customer.dart';
import '../providers/customer_provider.dart';
import '../providers/debt_provider.dart';
import '../models/debt.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import 'scan_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:dropdown_search/dropdown_search.dart';

class SaleScreen extends StatefulWidget {
  const SaleScreen({super.key});

  @override
  State<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends State<SaleScreen> {
  final TextEditingController _productCtrl = TextEditingController();
  final TextEditingController _customerCtrl = TextEditingController();
  final List<SaleItem> _items = [];
  double _discount = 0;
  double _paid = 0;
  String? _customerId;
  String? _customerName;
  bool _paidEdited = false;
  List<String> _recentUnits = ['cái', 'kg', 'g', 'hộp'];
  double _qtyStep = 0.5;
  VoidCallback? _clearProductField;
  VoidCallback? _unfocusProductField;
  List<Customer> _recentCustomers = [];
  List<Product> _recentProducts = [];

  // Hàm chuyển đổi tiếng Việt có dấu thành không dấu
  String removeDiacritics(String str) {
    const withDiacritics = 'áàảãạăắằẳẵặâấầuẩẫậéèẻẽẹêếềểễệíìỉĩịóòỏõọôốồổỗộơớờởỡợúùủũụưứừửữựýỳỷỹỵđ';
    const withoutDiacritics = 'aaaaaăaaaaaaâaaaaaaeeeeeêeeeeeiiiiioooooôooooooơooooouuuuuưuuuuuyyyyyd';
    String result = str.toLowerCase();
    for (int i = 0; i < withDiacritics.length; i++) {
      result = result.replaceAll(withDiacritics[i], withoutDiacritics[i]);
    }
    return result;
  }

  // Hàm lấy chữ cái đầu của các từ
  String getInitials(String str) {
    final normalized = removeDiacritics(str);
    final words = normalized.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return words.map((w) => w[0]).join().toLowerCase();
  }

  @override
  void initState() {
    super.initState();
    _loadRecentUnits();
    _loadQtyStep();
    _loadRecentCustomers();
    _loadRecentProducts();
  }

  Future<void> _loadRecentUnits() async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList('recent_units') ?? _recentUnits;
    setState(() {
      _recentUnits = list.toSet().toList();
    });
  }

  Future<void> _rememberUnit(String unit) async {
    if (unit.trim().isEmpty) return;
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList('recent_units') ?? _recentUnits;
    final set = {...list, unit};
    await sp.setStringList('recent_units', set.toList());
    await sp.setString('last_unit', unit);
    setState(() {
      _recentUnits = set.toList();
    });
  }

  Future<String?> _getLastUnit() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getString('last_unit');
  }

  Future<void> _applyLastUnitTo(SaleItem item) async {
    final last = await _getLastUnit();
    if (last != null && last.isNotEmpty) {
      setState(() => item.unit = last);
    }
  }

  Future<void> _loadQtyStep() async {
    final sp = await SharedPreferences.getInstance();
    setState(() {
      _qtyStep = sp.getDouble('qty_step') ?? 0.5;
    });
  }

  Future<void> _setQtyStep(double v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble('qty_step', v);
    setState(() {
      _qtyStep = v;
    });
  }

  Future<void> _loadRecentCustomers() async {
    final sp = await SharedPreferences.getInstance();
    final customerJsonList = sp.getStringList('recent_customers') ?? [];
    final customers = context.read<CustomerProvider>().customers;
    setState(() {
      _recentCustomers = customerJsonList
          .map((json) => Customer.fromMap(jsonDecode(json)))
          .where((c) => customers.any((cust) => cust.id == c.id))
          .take(3)
          .toList();
    });
  }

  Future<void> _saveRecentCustomer(Customer customer) async {
    final sp = await SharedPreferences.getInstance();
    final customerJsonList = sp.getStringList('recent_customers') ?? [];
    final customerJson = jsonEncode(customer.toMap());
    final updatedList = [customerJson, ...customerJsonList]
        .toSet()
        .take(3)
        .toList();
    await sp.setStringList('recent_customers', updatedList);
    await _loadRecentCustomers();
  }

  Future<void> _loadRecentProducts() async {
    final sp = await SharedPreferences.getInstance();
    final productJsonList = sp.getStringList('recent_products') ?? [];
    final products = context.read<ProductProvider>().products;
    setState(() {
      _recentProducts = productJsonList
          .map((json) => Product.fromMap(jsonDecode(json)))
          .where((p) => products.any((prod) => prod.id == p.id))
          .take(3)
          .toList();
    });
  }

  Future<void> _saveRecentProduct(Product product) async {
    final sp = await SharedPreferences.getInstance();
    final productJsonList = sp.getStringList('recent_products') ?? [];
    final productJson = jsonEncode(product.toMap());
    final updatedList = [productJson, ...productJsonList]
        .toSet()
        .take(3)
        .toList();
    await sp.setStringList('recent_products', updatedList);
    await _loadRecentProducts();
  }

  Future<void> _addQuickProductDialog({String? prefillName}) async {
    final nameCtrl = TextEditingController(text: prefillName ?? '');
    final priceCtrl = TextEditingController(text: '0');
    final costPriceCtrl = TextEditingController(text: '0');
    final unitCtrl = TextEditingController(text: 'cái');
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
            TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Giá bán')),
            const SizedBox(height: 8),
            TextField(controller: costPriceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Giá vốn')),
            const SizedBox(height: 8),
            TextField(controller: unitCtrl, decoration: const InputDecoration(labelText: 'Đơn vị')),
            const SizedBox(height: 8),
            TextField(
              controller: barcodeCtrl,
              decoration: InputDecoration(
                labelText: 'Mã vạch (nếu có)',
                // FIX: Wrap IconButton trong Builder để lấy fresh context có Overlay cho Tooltip
                suffixIcon: Builder(
                  builder: (ctx) => IconButton(
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
      final p = Product(
        name: nameCtrl.text.trim(),
        price: double.tryParse(priceCtrl.text.trim()) ?? 0,
        costPrice: double.tryParse(costPriceCtrl.text.trim()) ?? 0,
        unit: unitCtrl.text.trim().isEmpty ? 'cái' : unitCtrl.text.trim(),
        barcode: barcodeCtrl.text.trim().isEmpty ? null : barcodeCtrl.text.trim(),
      );
      await context.read<ProductProvider>().add(p);
      setState(() {
        final existingItem = _items.firstWhere(
          (item) => item.productId == p.id,
          orElse: () => SaleItem(
            productId: p.id,
            name: p.name,
            unitPrice: p.price,
            unitCost: p.costPrice,
            quantity: 0,
            unit: p.unit,
          ),
        );
        if (_items.contains(existingItem)) {
          existingItem.quantity += 1;
        } else {
          _items.add(existingItem..quantity = 1);
        }
        _productCtrl.text = p.name;
      });
      await _applyLastUnitTo(_items.lastWhere((item) => item.productId == p.id));
      await _saveRecentProduct(p);
      if (!_paidEdited) {
        final subtotal = _items.fold(0.0, (p, e) => p + e.total);
        final total = (subtotal - _discount).clamp(0, double.infinity).toDouble();
        setState(() => _paid = total);
      }
      _unfocusProductField?.call();
    }
  }

  Future<void> _addQuickCustomerDialog() async {
    final nameCtrl = TextEditingController(text: _customerCtrl.text);
    final phoneCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Thêm khách hàng'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Tên')),
            const SizedBox(height: 8),
            TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'SĐT (tuỳ chọn)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lưu')),
        ],
      ),
    );
    if (ok == true && nameCtrl.text.trim().isEmpty == false) {
      final c = Customer(
        name: nameCtrl.text.trim(),
        phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
      );
      await context.read<CustomerProvider>().add(c);
      setState(() {
        _customerId = c.id;
        _customerName = c.name;
        _customerCtrl.text = c.name;
      });
      await _saveRecentCustomer(c);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = context.watch<ProductProvider>().products;
    final customers = context.watch<CustomerProvider>().customers;
    final subtotal = _items.fold(0.0, (p, e) => p + e.total);
    final total = (subtotal - _discount).clamp(0, double.infinity);
    final debt = (total - _paid).clamp(0, double.infinity);
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bán hàng'),
        actions: [
          // FIX: Wrap IconButton trong Builder để lấy fresh context có Overlay cho Tooltip (fix lỗi No Overlay)
          Builder(
            builder: (ctx) => IconButton(
              tooltip: 'Quét mã vạch',
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () async {
                final code = await Navigator.of(context).push<String>(
                  MaterialPageRoute(builder: (_) => const ScanScreen()),
                );
                if (code == null || code.isEmpty) return;
                final p = context.read<ProductProvider>().findByBarcode(code);
                if (p != null) {
                  setState(() {
                    final existingItem = _items.firstWhere(
                      (item) => item.productId == p.id,
                      orElse: () => SaleItem(
                        productId: p.id,
                        name: p.name,
                        unitPrice: p.price,
                        unitCost: p.costPrice,
                        quantity: 0,
                        unit: p.unit,
                      ),
                    );
                    if (_items.contains(existingItem)) {
                      existingItem.quantity += 1;
                    } else {
                      _items.add(existingItem..quantity = 1);
                    }
                    _productCtrl.text = p.name;
                  });
                  await _applyLastUnitTo(_items.lastWhere((item) => item.productId == p.id));
                  await _saveRecentProduct(p);
                  if (!_paidEdited) {
                    final subtotal2 = _items.fold(0.0, (p, e) => p + e.total);
                    final total2 = (subtotal2 - _discount).clamp(0, double.infinity).toDouble();
                    setState(() => _paid = total2);
                  }
                  _clearProductField?.call();
                  _unfocusProductField?.call();
                } else {
                  await _addQuickProductDialog(prefillName: '');
                }
              },
            ),
          ),
          IconButton(
            tooltip: 'Lịch sử bán',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.of(context).pushNamed('/sales_history'),
          ),
          PopupMenuButton<String>(
            onSelected: (val) async {
              if (val == 'set_step') {
                final ctrl = TextEditingController(text: _qtyStep.toString());
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Thiết lập bước số lượng'),
                    content: TextField(
                      controller: ctrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(hintText: 'Ví dụ: 0.1, 0.5, 1'),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lưu')),
                    ],
                  ),
                );
                if (ok == true) {
                  final v = double.tryParse(ctrl.text.replaceAll(',', '.'));
                  if (v != null && v > 0) {
                    await _setQtyStep(v);
                  } else {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Giá trị không hợp lệ')));
                  }
                }
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'set_step', child: Text('Thiết lập bước số lượng')),
            ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Customer selection
            DropdownSearch<Customer>(
              items: customers,
              dropdownDecoratorProps: DropDownDecoratorProps(
                dropdownSearchDecoration: InputDecoration(
                  labelText: 'Khách hàng (tuỳ chọn)',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.person_add_alt),
                    onPressed: _addQuickCustomerDialog,
                    tooltip: 'Thêm khách hàng mới',
                  ),
                  suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
              ),
              onChanged: (c) async {
                if (c != null) {
                  setState(() {
                    _customerId = c.id;
                    _customerName = c.name;
                    _customerCtrl.text = c.name;
                  });
                  await _saveRecentCustomer(c);
                } else {
                  setState(() {
                    _customerId = null;
                    _customerName = null;
                    _customerCtrl.text = '';
                  });
                }
              },
              selectedItem: _customerId != null
                  ? customers.firstWhere((c) => c.id == _customerId, orElse: () => Customer(name: _customerName ?? ''))
                  : null,
              itemAsString: (c) => c.name,
              filterFn: (c, query) {
                final normalizedQuery = removeDiacritics(query).toLowerCase();
                final normalizedName = removeDiacritics(c.name).toLowerCase();
                final initials = getInitials(c.name);
                return normalizedName.contains(normalizedQuery) || initials.contains(normalizedQuery);
              },
              popupProps: const PopupProps.menu(
                showSearchBox: true,
                fit: FlexFit.loose,
                searchDelay: Duration.zero,
              ),
            ),
            const SizedBox(height: 8),
            // Recent Customers
            Wrap(
              spacing: 8,
              children: [
                ..._recentCustomers.map(
                  (c) => ActionChip(
                    side: BorderSide(color: Theme.of(context).colorScheme.primary),
                    label: Text(c.name),
                    onPressed: () async {
                      setState(() {
                        _customerId = c.id;
                        _customerName = c.name;
                        _customerCtrl.text = c.name;
                      });
                      await _saveRecentCustomer(c);
                    },
                  ),
                ),
                ActionChip(
                  side: BorderSide(color: Theme.of(context).colorScheme.primary),
                  label: const Text('Thêm'),
                  avatar: const Icon(Icons.person_add_alt, size: 18),
                  onPressed: _addQuickCustomerDialog,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Product selection
            DropdownSearch<Product>(
              items: products,
              dropdownDecoratorProps: DropDownDecoratorProps(
                dropdownSearchDecoration: InputDecoration(
                  labelText: 'Thêm sản phẩm nhanh',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () async {
                      await _addQuickProductDialog(prefillName: _productCtrl.text.trim().isEmpty ? null : _productCtrl.text.trim());
                      _productCtrl.clear();
                      _unfocusProductField?.call();
                    },
                    tooltip: 'Thêm sản phẩm mới',
                  ),
                  suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
              ),
              onChanged: (p) async {
                if (p != null) {
                  setState(() {
                    final existingItem = _items.firstWhere(
                      (item) => item.productId == p.id,
                      orElse: () => SaleItem(
                        productId: p.id,
                        name: p.name,
                        unitPrice: p.price,
                        unitCost: p.costPrice,
                        quantity: 0,
                        unit: p.unit,
                      ),
                    );
                    if (_items.contains(existingItem)) {
                      existingItem.quantity += 1;
                    } else {
                      _items.add(existingItem..quantity = 1);
                    }
                    _productCtrl.text = p.name;
                  });
                  await _applyLastUnitTo(_items.lastWhere((item) => item.productId == p.id));
                  await _saveRecentProduct(p);
                  if (!_paidEdited) {
                    final subtotal2 = _items.fold(0.0, (p, e) => p + e.total);
                    final total2 = (subtotal2 - _discount).clamp(0, double.infinity).toDouble();
                    setState(() => _paid = total2);
                  }
                  _clearProductField?.call();
                  _unfocusProductField?.call();
                }
              },
              itemAsString: (p) => p.name,
              filterFn: (p, query) {
                final normalizedQuery = removeDiacritics(query).toLowerCase();
                final normalizedName = removeDiacritics(p.name).toLowerCase();
                final initials = getInitials(p.name);
                return normalizedName.contains(normalizedQuery) || initials.contains(normalizedQuery);
              },
              popupProps: const PopupProps.menu(
                showSearchBox: true,
                fit: FlexFit.loose,
                searchDelay: Duration.zero,
              ),
            ),
            const SizedBox(height: 8),
            // Recent Products
            Wrap(
              spacing: 8,
              children: [
                ..._recentProducts.map(
                  (p) => ActionChip(
                    side: BorderSide(color: Theme.of(context).colorScheme.primary),
                    label: Text(p.name),
                    onPressed: () async {
                      setState(() {
                        final existingItem = _items.firstWhere(
                          (item) => item.productId == p.id,
                          orElse: () => SaleItem(
                            productId: p.id,
                            name: p.name,
                            unitPrice: p.price,
                            unitCost: p.costPrice,
                            quantity: 0,
                            unit: p.unit,
                          ),
                        );
                        if (_items.contains(existingItem)) {
                          existingItem.quantity += 1;
                        } else {
                          _items.add(existingItem..quantity = 1);
                        }
                        _productCtrl.text = p.name;
                      });
                      await _applyLastUnitTo(_items.lastWhere((item) => item.productId == p.id));
                      await _saveRecentProduct(p);
                      if (!_paidEdited) {
                        final subtotal2 = _items.fold(0.0, (p, e) => p + e.total);
                        final total2 = (subtotal2 - _discount).clamp(0, double.infinity).toDouble();
                        setState(() => _paid = total2);
                      }
                      _clearProductField?.call();
                      _unfocusProductField?.call();
                    },
                  ),
                ),
                ActionChip(
                  side: BorderSide(color: Theme.of(context).colorScheme.primary),
                  label: const Text('Thêm'),
                  avatar: const Icon(Icons.add, size: 18),
                  onPressed: () async {
                    await _addQuickProductDialog(prefillName: _productCtrl.text.trim().isEmpty ? null : _productCtrl.text.trim());
                    _productCtrl.clear();
                    _unfocusProductField?.call();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final it = _items[i];
                  final qtyCtrl = TextEditingController(text: it.quantity.toStringAsFixed(it.quantity % 1 == 0 ? 0 : 2));
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    it.name,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  InkWell(
                                    onTap: () async {
                                      final ctrl = TextEditingController(text: it.unitPrice.toStringAsFixed(0));
                                      final ok = await showDialog<bool>(
                                        context: context,
                                        builder: (_) => AlertDialog(
                                          title: const Text('Sửa đơn giá'),
                                          content: TextField(
                                            controller: ctrl,
                                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                            decoration: const InputDecoration(labelText: 'Đơn giá'),
                                          ),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
                                            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lưu')),
                                          ],
                                        ),
                                      );
                                      if (ok == true) {
                                        final v = double.tryParse(ctrl.text.replaceAll(',', '.'));
                                        if (v != null && v >= 0) {
                                          setState(() => it.unitPrice = v);
                                        }
                                      }
                                    },
                                    child: Text('${currency.format(it.unitPrice)} × ${it.quantity} ${it.unit} (chạm để sửa)'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              currency.format(it.total),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            SizedBox(
                              width: 60,
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: it.unit.isEmpty ? null : it.unit,
                                  hint: const Text('Đơn vị'),
                                  isExpanded: true,
                                  items: _recentUnits.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                                  onChanged: (u) async {
                                    if (u == null) return;
                                    setState(() => it.unit = u);
                                    await _rememberUnit(u);
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 110,
                              child: TextField(
                                controller: qtyCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Số lượng',
                                  isDense: true,
                                ),
                                onSubmitted: (v) {
                                  final val = double.tryParse(v.replaceAll(',', '.'));
                                  if (val == null) return;
                                  setState(() {
                                    it.quantity = val <= 0 ? 0.0 : val;
                                    qtyCtrl.text = it.quantity.toStringAsFixed(it.quantity % 1 == 0 ? 0 : 2);
                                    if (!_paidEdited) {
                                      final subtotal2 = _items.fold(0.0, (p, e) => p + e.total);
                                      final total2 = (subtotal2 - _discount).clamp(0, double.infinity).toDouble();
                                      _paid = total2;
                                    }
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            QuantityStepper(
                              value: it.quantity,
                              onChanged: (v) {
                                setState(() {
                                  it.quantity = v <= 0 ? 0.0 : v;
                                  qtyCtrl.text = it.quantity.toStringAsFixed(it.quantity % 1 == 0 ? 0 : 2);
                                  if (!_paidEdited) {
                                    final subtotal2 = _items.fold(0.0, (p, e) => p + e.total);
                                    final total2 = (subtotal2 - _discount).clamp(0, double.infinity).toDouble();
                                    _paid = total2;
                                  }
                                });
                              },
                              step: _qtyStep,
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () {
                                setState(() {
                                  _items.removeAt(i);
                                  if (!_paidEdited) {
                                    final subtotal2 = _items.fold(0.0, (p, e) => p + e.total);
                                    final total2 = (subtotal2 - _discount).clamp(0, double.infinity).toDouble();
                                    _paid = total2;
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const Divider(),
            Row(
              children: [
                Expanded(child: Text('Tạm tính: ${currency.format(subtotal)}')),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Giảm'),
                      TextField(
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(hintText: '0', isDense: true),
                        onChanged: (v) {
                          final val = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                          setState(() {
                            _discount = math.max(0, math.min(subtotal, val)).toDouble();
                            if (!_paidEdited) {
                              final total2 = (subtotal - _discount).clamp(0, double.infinity).toDouble();
                              _paid = total2;
                            }
                          });
                        },
                        controller: TextEditingController(text: _discount == 0 ? '' : _discount.toStringAsFixed(0))
                          ..selection = TextSelection.collapsed(offset: (_discount == 0 ? '' : _discount.toStringAsFixed(0)).length),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Khách trả'),
                      TextField(
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(hintText: '0', isDense: true),
                        onChanged: (v) {
                          final val = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                          setState(() {
                            _paidEdited = true;
                            _paid = math.max(0, math.min(total, val)).toDouble();
                          });
                        },
                        controller: TextEditingController(text: _paid == 0 ? '' : _paid.toStringAsFixed(0))
                          ..selection = TextSelection.collapsed(offset: (_paid == 0 ? '' : _paid.toStringAsFixed(0)).length),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _items.isEmpty
                    ? null
                    : () async {
                        // Tính totalCost dựa trên unitCost của các SaleItem
                        double calculatedTotalCost = _items.fold(0.0, (p, e) => p + e.totalCost);
                        final sale = Sale(
                          items: _items.toList(),
                          discount: _discount,
                          paidAmount: _paid,
                          customerId: _customerId,
                          customerName: _customerName,
                          totalCost: calculatedTotalCost, // Thêm totalCost vào Sale
                        );
                        await context.read<SaleProvider>().add(sale);
                        final debtValue = (sale.total - sale.paidAmount).clamp(0.0, double.infinity).toDouble();
                        if (debtValue > 0) {
                          final details = StringBuffer()
                            ..writeln('Bán hàng ngày ${DateFormat('dd/MM/yyyy HH:mm').format(sale.createdAt)}')
                            ..writeln('Khách: ${_customerName ?? 'Khách lẻ'}')
                            ..writeln('Chi tiết:')
                            ..writeln(_items.map((it) => '- ${it.name} x ${it.quantity} ${it.unit} = ${currency.format(it.total)}').join('\n'))
                            ..writeln('Tạm tính: ${currency.format(subtotal)}')
                            ..writeln('Giảm: ${currency.format(_discount)}')
                            ..writeln('Khách trả: ${currency.format(_paid)}')
                            ..writeln('Còn nợ: ${currency.format(debtValue)}');
                          await context.read<DebtProvider>().add(Debt(
                                type: DebtType.othersOweMe,
                                partyId: _customerId ?? 'unknown',
                                partyName: _customerName ?? 'Khách lẻ',
                                amount: debtValue,
                                description: details.toString(),
                              ));
                        }
                        setState(() {
                          _items.clear();
                          _discount = 0;
                          _paid = 0;
                          _customerId = null;
                          _customerName = null;
                          _customerCtrl.clear();
                        });
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu bán hàng')));
                      },
                icon: const Icon(Icons.save),
                label: Text(debt > 0 ? 'Lưu + Ghi nợ (${currency.format(debt)})' : 'Lưu hóa đơn'),
              ),
            )
          ],
        ),
      ),
    );
  }
}