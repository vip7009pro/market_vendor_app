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
  bool _paidEdited = false; // track if user manually edited paid
  List<String> _recentUnits = ['cái', 'kg', 'g', 'hộp'];
  double _qtyStep = 0.5;
  VoidCallback? _clearProductField;
  VoidCallback? _unfocusProductField;

  @override
  void initState() {
    super.initState();
    _loadRecentUnits();
    _loadQtyStep();
  }

  Future<void> _loadRecentUnits() async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList('recent_units') ?? _recentUnits;
    setState(() {
      _recentUnits = list.toSet().toList();
      // no direct state to set from last here; we apply per-item when adding
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

  Future<void> _addQuickProductDialog({String? prefillName}) async {
    final nameCtrl = TextEditingController(text: prefillName ?? '');
    final priceCtrl = TextEditingController(text: '0');
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
      final p = Product(
        name: nameCtrl.text.trim(),
        price: double.tryParse(priceCtrl.text.trim()) ?? 0,
        unit: unitCtrl.text.trim().isEmpty ? 'cái' : unitCtrl.text.trim(),
        barcode: barcodeCtrl.text.trim().isEmpty ? null : barcodeCtrl.text.trim(),
      );
      await context.read<ProductProvider>().add(p);
      setState(() {
        final newItem = SaleItem(
          productId: p.id,
          name: p.name,
          unitPrice: p.price,
          quantity: 1,
          unit: p.unit,
        );
        _items.add(newItem);
      });
      await _applyLastUnitTo(_items.last);
      if (!_paidEdited) {
        final subtotal = _items.fold(0.0, (p, e) => p + e.total);
        final total = (subtotal - _discount).clamp(0, double.infinity).toDouble();
        setState(() => _paid = total);
      }
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
    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      final c = Customer(name: nameCtrl.text.trim(), phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim());
      await context.read<CustomerProvider>().add(c);
      setState(() {
        _customerId = c.id;
        _customerName = c.name;
        _customerCtrl.text = c.name;
      });
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
          IconButton(
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
                  final it = SaleItem(
                    productId: p.id,
                    name: p.name,
                    unitPrice: p.price,
                    quantity: 1,
                    unit: p.unit,
                  );
                  _items.add(it);
                });
                await _applyLastUnitTo(_items.last);
                if (!_paidEdited) {
                  final subtotal2 = _items.fold(0.0, (p, e) => p + e.total);
                  final total2 = (subtotal2 - _discount).clamp(0, double.infinity).toDouble();
                  setState(() => _paid = total2);
                }
                // Clear product field and hide keyboard (use callbacks from fieldViewBuilder)
                _clearProductField?.call();
                _unfocusProductField?.call();
              } else {
                await _addQuickProductDialog(prefillName: '');
              }
            },
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
            Autocomplete<Customer>(
              optionsBuilder: (text) {
                final q = text.text.toLowerCase();
                if (q.isEmpty) return customers;
                return customers.where((c) => c.name.toLowerCase().contains(q));
              },
              displayStringForOption: (c) => c.name,
              fieldViewBuilder: (context, ctrl, focus, onSubmit) {
                _customerCtrl.value = ctrl.value;
                return TextField(
                  controller: ctrl,
                  focusNode: focus,
                  decoration: InputDecoration(
                    labelText: 'Khách hàng (tuỳ chọn)',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.person_add_alt),
                      onPressed: _addQuickCustomerDialog,
                    ),
                  ),
                  onChanged: (v) {
                    setState(() {
                      _customerId = null;
                      _customerName = v.isEmpty ? null : v;
                    });
                  },
                );
              },
              onSelected: (c) {
                setState(() {
                  _customerId = c.id;
                  _customerName = c.name;
                  _customerCtrl.text = c.name;
                });
              },
            ),
            const SizedBox(height: 12),
            Autocomplete<Product>(
              optionsBuilder: (text) {
                final q = text.text.toLowerCase();
                // show all products if empty to open list immediately on focus
                final base = q.isEmpty ? products : products.where((p) => p.name.toLowerCase().contains(q));
                return base;
              },
              displayStringForOption: (p) => p.name,
              fieldViewBuilder: (context, ctrl, focus, onSubmit) {
                _productCtrl.value = ctrl.value;
                // When gaining focus with empty input, briefly nudge the controller to show options
                focus.addListener(() {
                  if (focus.hasFocus && (ctrl.text.isEmpty)) {
                    final orig = ctrl.text;
                    ctrl.text = ' ';
                    ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
                    Future.microtask(() {
                      ctrl.text = orig;
                      ctrl.selection = TextSelection.collapsed(offset: orig.length);
                    });
                  }
                });
                // wire clear/unfocus callbacks so outside handlers can control this field
                _clearProductField = () => ctrl.clear();
                _unfocusProductField = () => focus.unfocus();
                return TextField(
                  controller: ctrl,
                  focusNode: focus,
                  decoration: InputDecoration(
                    labelText: 'Thêm sản phẩm nhanh',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () async {
                        await _addQuickProductDialog(prefillName: ctrl.text.trim().isEmpty ? null : ctrl.text.trim());
                        ctrl.clear();
                        FocusScope.of(context).unfocus();
                      },
                    ),
                  ),
                );
              },
              onSelected: (p) async {
                setState(() {
                  final it = SaleItem(
                    productId: p.id,
                    name: p.name,
                    unitPrice: p.price,
                    quantity: 1,
                    unit: p.unit,
                  );
                  _items.add(it);
                });
                await _applyLastUnitTo(_items.last);
                if (!_paidEdited) {
                  final subtotal2 = _items.fold(0.0, (p, e) => p + e.total);
                  final total2 = (subtotal2 - _discount).clamp(0, double.infinity).toDouble();
                  setState(() => _paid = total2);
                }
                _clearProductField?.call();
                _unfocusProductField?.call();
              },
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
                            // Unit dropdown
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
                            // Direct quantity input
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
                            // Quantity stepper
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
                        final sale = Sale(
                          items: _items.toList(),
                          discount: _discount,
                          paidAmount: _paid,
                          customerId: _customerId,
                          customerName: _customerName,
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
