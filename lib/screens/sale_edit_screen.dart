import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/debt.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../providers/debt_provider.dart';
import '../providers/product_provider.dart';
import '../providers/sale_provider.dart';
import '../services/database_service.dart';
import '../utils/number_input_formatter.dart';

class SaleEditScreen extends StatefulWidget {
  const SaleEditScreen({super.key, required this.sale});

  final Sale sale;

  @override
  State<SaleEditScreen> createState() => _SaleEditScreenState();
}

class _SaleEditScreenState extends State<SaleEditScreen> {
  late DateTime _createdAt;

  late final List<SaleItem> _items;

  late final TextEditingController _discountCtrl;
  late final TextEditingController _paidCtrl;

  bool _paidEdited = false;

  final Map<int, TextEditingController> _qtyCtrls = {};
  final Map<int, TextEditingController> _priceCtrls = {};
  final Map<int, TextEditingController> _costCtrls = {};

  final Map<String, TextEditingController> _mixDisplayNameCtrls = {};
  final Map<String, TextEditingController> _mixRawQtyCtrls = {};
  final Map<String, TextEditingController> _mixRawCostCtrls = {};
  final Map<String, TextEditingController> _mixRawPriceCtrls = {};
  final Map<String, FocusNode> _mixRawQtyFocus = {};

  String _mixRawKey(String mixProductId, String rawProductId) => '$mixProductId::$rawProductId';

  TextEditingController _mixDisplayNameCtrlFor(SaleItem it) {
    return _mixDisplayNameCtrls.putIfAbsent(
      it.productId,
      () => TextEditingController(text: it.displayName ?? ''),
    );
  }

  TextEditingController _mixRawQtyCtrlFor({required String mixProductId, required String rawProductId, required double initialQty}) {
    final key = _mixRawKey(mixProductId, rawProductId);
    final existing = _mixRawQtyCtrls[key];
    if (existing != null) return existing;

    final ctrl = TextEditingController(
      text: initialQty == 0 ? '' : initialQty.toStringAsFixed(initialQty % 1 == 0 ? 0 : 2),
    );
    _mixRawQtyCtrls[key] = ctrl;
    return ctrl;
  }

  TextEditingController _mixRawCostCtrlFor({required String mixProductId, required String rawProductId, required double initialCost}) {
    final key = _mixRawKey(mixProductId, rawProductId);
    final existing = _mixRawCostCtrls[key];
    if (existing != null) return existing;

    final ctrl = TextEditingController(text: initialCost == 0 ? '' : initialCost.toStringAsFixed(0));
    _mixRawCostCtrls[key] = ctrl;
    return ctrl;
  }

  TextEditingController _mixRawPriceCtrlFor({required String mixProductId, required String rawProductId, required double initialPrice}) {
    final key = _mixRawKey(mixProductId, rawProductId);
    final existing = _mixRawPriceCtrls[key];
    if (existing != null) return existing;

    final ctrl = TextEditingController(text: initialPrice == 0 ? '' : initialPrice.toStringAsFixed(0));
    _mixRawPriceCtrls[key] = ctrl;
    return ctrl;
  }

  FocusNode _mixRawQtyFocusFor({required String mixProductId, required String rawProductId}) {
    final key = _mixRawKey(mixProductId, rawProductId);
    return _mixRawQtyFocus.putIfAbsent(key, () => FocusNode());
  }

  void _disposeMixRawFieldFor({required String mixProductId, required String rawProductId}) {
    final key = _mixRawKey(mixProductId, rawProductId);
    _mixRawQtyCtrls.remove(key)?.dispose();
    _mixRawCostCtrls.remove(key)?.dispose();
    _mixRawPriceCtrls.remove(key)?.dispose();
    _mixRawQtyFocus.remove(key)?.dispose();
  }

  bool _isMixItem(SaleItem it) => (it.itemType ?? '').toUpperCase().trim() == 'MIX';

  List<Map<String, dynamic>> _getMixItems(SaleItem it) {
    final raw = (it.mixItemsJson ?? '').trim();
    if (raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  void _setMixItems(SaleItem it, List<Map<String, dynamic>> mixItems) {
    it.mixItemsJson = jsonEncode(mixItems);
  }

  void _recalcMixTotalsFromMixItems(SaleItem it, List<Map<String, dynamic>> mixItems) {
    final qty = mixItems.fold<double>(0.0, (p, e) => p + ((e['rawQty'] as num?)?.toDouble() ?? 0));
    final totalCost = mixItems.fold<double>(
      0.0,
      (p, e) => p + (((e['rawQty'] as num?)?.toDouble() ?? 0) * ((e['rawUnitCost'] as num?)?.toDouble() ?? 0)),
    );
    it.quantity = qty;
    it.unitCost = qty <= 0 ? 0 : (totalCost / qty);
  }

  void _syncPaidWithTotalIfNotEdited(double total) {
    if (_paidEdited) return;
    final desired = total.clamp(0, double.infinity).toDouble();
    final formatted = NumberFormat.decimalPattern('en_US').format(desired.truncate());
    if (_paidCtrl.text == formatted) return;
    _paidCtrl.text = formatted;
    _paidCtrl.selection = TextSelection.collapsed(offset: _paidCtrl.text.length);
  }

  void _setPaidFromUi(double value) {
    final desired = value.clamp(0, double.infinity).toDouble();
    final formatted = NumberFormat.decimalPattern('en_US').format(desired.truncate());
    _paidEdited = true;
    if (_paidCtrl.text != formatted) {
      _paidCtrl.text = formatted;
      _paidCtrl.selection = TextSelection.collapsed(offset: _paidCtrl.text.length);
    }
    setState(() {});
  }

  double _parseMoney(String s) {
    return (NumberInputFormatter.tryParse(s) ?? 0).toDouble();
  }

  double _parseQty(String s) {
    return (NumberInputFormatter.tryParse(s) ?? 0).toDouble();
  }

  double _subtotal() {
    var sum = 0.0;
    for (var i = 0; i < _items.length; i++) {
      final it = _items[i];
      if (_isMixItem(it)) {
        sum += it.total;
        continue;
      }

      final qtyText = (_qtyCtrls[i]?.text ?? '').trim();
      final priceText = (_priceCtrls[i]?.text ?? '').trim();
      final qty = _parseQty(qtyText);
      final unitPrice = _parseMoney(priceText);
      final effectiveQty = qtyText.isEmpty ? it.quantity : qty;
      final effectivePrice = priceText.isEmpty ? it.unitPrice : unitPrice;
      sum += (effectiveQty * effectivePrice);
    }
    return sum;
  }

  double _totalCostSnap() {
    var sum = 0.0;
    for (var i = 0; i < _items.length; i++) {
      final it = _items[i];
      if (_isMixItem(it)) {
        sum += it.totalCost;
        continue;
      }

      final qtyText = (_qtyCtrls[i]?.text ?? '').trim();
      final costText = (_costCtrls[i]?.text ?? '').trim();
      final qty = _parseQty(qtyText);
      final unitCost = _parseMoney(costText);
      final effectiveQty = qtyText.isEmpty ? it.quantity : qty;
      final effectiveCost = costText.isEmpty ? it.unitCost : unitCost;
      sum += (effectiveQty * effectiveCost);
    }
    return sum;
  }

  double _discountValue() {
    final v = _parseMoney(_discountCtrl.text);
    final max = _subtotal();
    return v.clamp(0.0, max).toDouble();
  }

  double _total() => (_subtotal() - _discountValue()).clamp(0.0, double.infinity).toDouble();

  double _paidValue() {
    final v = _parseMoney(_paidCtrl.text);
    return v.clamp(0.0, double.infinity).toDouble();
  }

  Future<void> _pickDateTime() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _createdAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_createdAt),
    );
    if (t == null) return;

    setState(() {
      _createdAt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  Future<Product?> _showRawPicker({String? requiredUnit}) async {
    final products = await DatabaseService.instance.getProductsForSale();
    final raws = products.where((p) => p.itemType == ProductItemType.raw).toList();
    final filtered = requiredUnit == null ? raws : raws.where((p) => p.unit == requiredUnit).toList();

    if (!mounted) return null;

    return await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final searchController = TextEditingController();
        var filteredProducts = List<Product>.from(filtered);

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
                      labelText: requiredUnit == null ? 'Chọn nguyên liệu (RAW)' : 'Chọn nguyên liệu ($requiredUnit)',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          searchController.clear();
                          setState(() {
                            filteredProducts = List<Product>.from(filtered);
                          });
                        },
                      ),
                    ),
                    onChanged: (value) {
                      final q = value.trim().toLowerCase();
                      if (q.isEmpty) {
                        setState(() {
                          filteredProducts = List<Product>.from(filtered);
                        });
                        return;
                      }
                      setState(() {
                        filteredProducts = filtered.where((p) {
                          final nameMatch = p.name.toLowerCase().contains(q);
                          final barcodeMatch = p.barcode?.toLowerCase().contains(q) ?? false;
                          return nameMatch || barcodeMatch;
                        }).toList();
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: filteredProducts.isEmpty
                        ? const Center(child: Text('Không tìm thấy nguyên liệu nào'))
                        : ListView.builder(
                            itemCount: filteredProducts.length,
                            itemBuilder: (context, index) {
                              final p = filteredProducts[index];
                              return ListTile(
                                leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
                                title: Text(p.name),
                                subtitle: Text('${NumberFormat('#,##0').format(p.price)} đ'),
                                trailing: Text('Tồn: ${p.currentStock} ${p.unit}'),
                                onTap: () => Navigator.of(context).pop(p),
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

  Future<void> _addRawToMix(SaleItem mixLine) async {
    final mixItems = _getMixItems(mixLine);
    final requiredUnit = mixLine.unit.trim().isEmpty ? null : mixLine.unit;
    final raw = await _showRawPicker(requiredUnit: requiredUnit);
    if (raw == null) return;

    if (requiredUnit != null && raw.unit != requiredUnit) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể trộn nguyên liệu khác đơn vị')),
      );
      return;
    }

    if (requiredUnit == null) {
      mixLine.unit = raw.unit;
      await DatabaseService.instance.updateProductUnit(productId: mixLine.productId, unit: raw.unit);
    }

    final idx = mixItems.indexWhere((e) => (e['rawProductId']?.toString() ?? '') == raw.id);
    if (idx == -1) {
      mixItems.add({
        'rawProductId': raw.id,
        'rawName': raw.name,
        'rawUnit': raw.unit,
        'rawQty': 0.0,
        'rawUnitCost': raw.costPrice,
        'rawUnitPrice': raw.price,
      });
    }

    _setMixItems(mixLine, mixItems);
    _recalcMixTotalsFromMixItems(mixLine, mixItems);

    setState(() {
      _syncPaidWithTotalIfNotEdited(_total());
    });
  }

  Future<void> _save() async {
    for (var i = 0; i < _items.length; i++) {
      final it = _items[i];
      if (_isMixItem(it)) continue;

      final qty = _parseQty(_qtyCtrls[i]?.text ?? '');
      final unitPrice = _parseMoney(_priceCtrls[i]?.text ?? '');
      final unitCost = _parseMoney(_costCtrls[i]?.text ?? '');
      if (qty <= 0 || unitPrice < 0) {
        throw Exception('Số lượng/đơn giá không hợp lệ ở dòng ${i + 1}');
      }
      if (unitCost < 0) {
        throw Exception('Giá vốn không hợp lệ ở dòng ${i + 1}');
      }
      it.quantity = qty;
      it.unitPrice = unitPrice;
      it.unitCost = unitCost;
    }

    for (final it in _items) {
      if (!_isMixItem(it)) continue;
      it.displayName = _mixDisplayNameCtrlFor(it).text.trim().isEmpty ? null : _mixDisplayNameCtrlFor(it).text.trim();

      final mixItems = _getMixItems(it);
      if (mixItems.isNotEmpty) {
        final unit = (mixItems.first['rawUnit']?.toString() ?? '').trim();
        if (unit.isNotEmpty) {
          for (final m in mixItems) {
            final u = (m['rawUnit']?.toString() ?? '').trim();
            if (u.isNotEmpty && u != unit) {
              throw Exception('Nguyên liệu MIX phải cùng đơn vị');
            }
          }
        }
      }
    }

    final discount = _discountValue();
    final paid = _paidValue();

    final total = (_subtotal() - discount).clamp(0.0, double.infinity).toDouble();
    if (paid > total) {
      final formatted = NumberFormat.decimalPattern('en_US').format(total.truncate());
      _paidCtrl.text = formatted;
      _paidCtrl.selection = TextSelection.collapsed(offset: _paidCtrl.text.length);
      throw Exception('Khách trả không được lớn hơn tổng tiền');
    }

    final totalCostSnap = _totalCostSnap();
    if (totalCostSnap > total) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Cảnh báo lợi nhuận âm'),
          content: Text(
            'Tổng vốn (${NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0).format(totalCostSnap)}) '
            'đang lớn hơn tổng tiền bán (${NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0).format(total)}).\n\n'
            'Bạn vẫn muốn lưu hóa đơn?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Vẫn lưu')),
          ],
        ),
      );
      if (ok != true) return;
    }

    final oldSale = widget.sale;
    final newSale = Sale(
      id: oldSale.id,
      createdAt: _createdAt,
      customerId: oldSale.customerId,
      customerName: oldSale.customerName,
      employeeId: oldSale.employeeId,
      employeeName: oldSale.employeeName,
      items: _items,
      discount: discount,
      paidAmount: paid,
      paymentType: oldSale.paymentType,
      note: oldSale.note,
      totalCost: totalCostSnap,
    );

    await DatabaseService.instance.updateSaleWithStockAdjustment(oldSale: oldSale, newSale: newSale);

    final saleId = newSale.id;
    final newDebtInitialAmount = newSale.debt;
    final existingDebt = await DatabaseService.instance.getDebtBySource(
      sourceType: 'sale',
      sourceId: saleId,
    );

    if (existingDebt != null) {
      final alreadyPaidForDebt = await DatabaseService.instance.getTotalPaidForDebt(existingDebt.id);
      final newRemain = (newDebtInitialAmount - alreadyPaidForDebt).clamp(0.0, double.infinity).toDouble();
      final updatedDebt = Debt(
        id: existingDebt.id,
        createdAt: existingDebt.createdAt,
        type: DebtType.othersOweMe,
        partyId: existingDebt.partyId,
        partyName: existingDebt.partyName,
        initialAmount: newDebtInitialAmount,
        amount: newRemain,
        description:
            'Bán hàng: ${(newSale.customerName?.trim().isNotEmpty == true) ? newSale.customerName!.trim() : 'Khách lẻ'}, Tổng ${newSale.total.toStringAsFixed(0)}, Đã trả ${newSale.paidAmount.toStringAsFixed(0)}',
        settled: newRemain <= 0,
        sourceType: 'sale',
        sourceId: saleId,
      );
      await DatabaseService.instance.updateDebt(updatedDebt);
      await context.read<DebtProvider>().load();
    } else if (newDebtInitialAmount > 0) {
      final partyName = (newSale.customerName?.trim().isNotEmpty == true) ? newSale.customerName!.trim() : 'Khách lẻ';
      final newDebt = Debt(
        type: DebtType.othersOweMe,
        partyId: (newSale.customerId?.trim().isNotEmpty == true) ? newSale.customerId!.trim() : 'customer_unknown',
        partyName: partyName,
        amount: newDebtInitialAmount,
        description:
            'Bán hàng: $partyName, Tổng ${newSale.total.toStringAsFixed(0)}, Đã trả ${newSale.paidAmount.toStringAsFixed(0)}',
        sourceType: 'sale',
        sourceId: saleId,
      );
      await context.read<DebtProvider>().add(newDebt);
    }

    await context.read<SaleProvider>().load();
    await context.read<ProductProvider>().load();

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  void initState() {
    super.initState();

    _createdAt = widget.sale.createdAt;

    _items = widget.sale.items
        .map(
          (e) => SaleItem(
            productId: e.productId,
            name: e.name,
            unitPrice: e.unitPrice,
            unitCost: e.unitCost,
            quantity: e.quantity,
            unit: e.unit,
            itemType: e.itemType,
            displayName: e.displayName,
            mixItemsJson: e.mixItemsJson,
          ),
        )
        .toList();

    _discountCtrl = TextEditingController(
      text: widget.sale.discount == 0 ? '' : NumberFormat.decimalPattern('en_US').format(widget.sale.discount.truncate()),
    );
    _paidCtrl = TextEditingController(
      text: widget.sale.paidAmount == 0 ? '' : NumberFormat.decimalPattern('en_US').format(widget.sale.paidAmount.truncate()),
    );

    for (var i = 0; i < _items.length; i++) {
      final it = _items[i];
      if (_isMixItem(it)) continue;

      _qtyCtrls[i] = TextEditingController(text: it.quantity.toStringAsFixed(it.quantity % 1 == 0 ? 0 : 2));
      _priceCtrls[i] = TextEditingController(text: it.unitPrice.toStringAsFixed(0));
      _costCtrls[i] = TextEditingController(text: it.unitCost.toStringAsFixed(0));
    }

    _discountCtrl.addListener(() {
      setState(() {});
    });

    _paidCtrl.addListener(() {
      setState(() {
        _paidEdited = true;
      });
    });
  }

  @override
  void dispose() {
    _discountCtrl.dispose();
    _paidCtrl.dispose();

    for (final c in _qtyCtrls.values) {
      c.dispose();
    }
    for (final c in _priceCtrls.values) {
      c.dispose();
    }
    for (final c in _costCtrls.values) {
      c.dispose();
    }
    for (final c in _mixDisplayNameCtrls.values) {
      c.dispose();
    }
    for (final c in _mixRawQtyCtrls.values) {
      c.dispose();
    }
    for (final c in _mixRawCostCtrls.values) {
      c.dispose();
    }
    for (final c in _mixRawPriceCtrls.values) {
      c.dispose();
    }
    for (final f in _mixRawQtyFocus.values) {
      f.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fmtDate = DateFormat('dd/MM/yyyy HH:mm');
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);

    final subtotal = _subtotal();
    final totalCostSnap = _totalCostSnap();
    final discount = _discountValue();
    final total = (subtotal - discount).clamp(0.0, double.infinity).toDouble();
    final paid = _paidValue();
    final debt = (total - paid).clamp(0.0, double.infinity).toDouble();
    final profitSnap = total - totalCostSnap;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sửa bán hàng'),
        actions: [
          IconButton(
            tooltip: 'Lưu',
            icon: const Icon(Icons.save_outlined),
            onPressed: () async {
              try {
                await _save();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không thể lưu: $e')));
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Ngày giờ: ${fmtDate.format(_createdAt)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(onPressed: _pickDateTime, child: const Text('Đổi')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _discountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: false),
                          inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
                          decoration: const InputDecoration(
                            labelText: 'Giảm giá',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _paidCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: false),
                          inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
                          decoration: const InputDecoration(
                            labelText: 'Khách trả',
                            isDense: true,
                          ),
                          onChanged: (_) {
                            _paidEdited = true;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _setPaidFromUi(0),
                          child: const Text('Khách nợ tất'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => _setPaidFromUi(total),
                          child: const Text('Khách trả tất'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: Text('Tạm tính', style: TextStyle(color: Colors.grey[700]))),
                      Text(currency.format(subtotal), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: Text('Tổng', style: TextStyle(color: Colors.grey[700]))),
                      Text(currency.format(total), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: Text('Tổng vốn', style: TextStyle(color: Colors.grey[700]))),
                      Text(currency.format(totalCostSnap), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: Text('Lợi nhuận', style: TextStyle(color: Colors.grey[700]))),
                      Text(
                        currency.format(profitSnap),
                        style: TextStyle(fontWeight: FontWeight.w700, color: profitSnap >= 0 ? Colors.green : Colors.red),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: Text('Còn nợ', style: TextStyle(color: Colors.grey[700]))),
                      Text(currency.format(debt), style: TextStyle(fontWeight: FontWeight.w700, color: debt > 0 ? Colors.red : Colors.green)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...List.generate(_items.length, (i) {
            final it = _items[i];
            final isMix = _isMixItem(it);
            final title = (isMix && it.displayName?.trim().isNotEmpty == true) ? it.displayName!.trim() : it.name;

            if (!isMix) {
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _qtyCtrls[i],
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [NumberInputFormatter(maxDecimalDigits: 2)],
                              decoration: InputDecoration(labelText: 'Số lượng (${it.unit})', isDense: true),
                              onChanged: (_) {
                                setState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _priceCtrls[i],
                              keyboardType: const TextInputType.numberWithOptions(decimal: false),
                              inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
                              decoration: const InputDecoration(labelText: 'Đơn giá', isDense: true),
                              onChanged: (_) {
                                setState(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _costCtrls[i],
                        keyboardType: const TextInputType.numberWithOptions(decimal: false),
                        inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
                        decoration: const InputDecoration(labelText: 'Giá vốn (snap)', isDense: true),
                        onChanged: (_) {
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Hiện tại: ${it.quantity} ${it.unit} × ${currency.format(it.unitPrice)} | Vốn: ${currency.format(it.unitCost)}',
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
                        Text(currency.format(it.total), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _mixDisplayNameCtrlFor(it),
                      decoration: const InputDecoration(
                        labelText: 'Tên hiển thị trên hóa đơn (không bắt buộc)',
                        isDense: true,
                      ),
                      onChanged: (v) {
                        it.displayName = v.trim().isEmpty ? null : v.trim();
                      },
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: () => _addRawToMix(it),
                        icon: const Icon(Icons.add),
                        label: const Text('Thêm nguyên liệu (RAW)'),
                      ),
                    ),
                    ..._getMixItems(it).asMap().entries.map((entry) {
                      final idx = entry.key;
                      final m = entry.value;
                      final rawName = (m['rawName']?.toString() ?? '').trim();
                      final rawUnit = (m['rawUnit']?.toString() ?? '').trim();
                      final rawId = (m['rawProductId']?.toString() ?? '').trim();
                      final rawQty = (m['rawQty'] as num?)?.toDouble() ?? 0;
                      final rawUnitCost = (m['rawUnitCost'] as num?)?.toDouble() ?? 0.0;
                      final rawUnitPrice = (m['rawUnitPrice'] as num?)?.toDouble() ?? 0.0;

                      double? rawStock;
                      for (final p in context.read<ProductProvider>().products) {
                        if (p.id == rawId) {
                          rawStock = p.currentStock;
                          break;
                        }
                      }

                      final ctrl = _mixRawQtyCtrlFor(
                        mixProductId: it.productId,
                        rawProductId: rawId,
                        initialQty: rawQty,
                      );
                      final costCtrl = _mixRawCostCtrlFor(
                        mixProductId: it.productId,
                        rawProductId: rawId,
                        initialCost: rawUnitCost,
                      );
                      final priceCtrl = _mixRawPriceCtrlFor(
                        mixProductId: it.productId,
                        rawProductId: rawId,
                        initialPrice: rawUnitPrice,
                      );
                      final focusNode = _mixRawQtyFocusFor(mixProductId: it.productId, rawProductId: rawId);

                      final rawLineTotal = rawQty * rawUnitCost;

                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    rawName.isEmpty ? 'Nguyên liệu' : rawName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  rawStock == null
                                      ? ''
                                      : 'Tồn: ${rawStock.toStringAsFixed(rawStock % 1 == 0 ? 0 : 2)}${rawUnit.isEmpty ? '' : ' $rawUnit'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: ctrl,
                                    focusNode: focusNode,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    inputFormatters: [NumberInputFormatter(maxDecimalDigits: 2)],
                                    decoration: InputDecoration(
                                      labelText: rawUnit.isEmpty ? 'Số lượng' : 'Số lượng ($rawUnit)',
                                      isDense: true,
                                    ),
                                    onChanged: (v) {
                                      final val = NumberInputFormatter.tryParse(v);
                                      if (val == null || val < 0) return;
                                      final items = _getMixItems(it);
                                      if (idx >= items.length) return;
                                      items[idx]['rawQty'] = val;
                                      _setMixItems(it, items);
                                      _recalcMixTotalsFromMixItems(it, items);
                                      setState(() {});
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: costCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: false),
                                    inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
                                    decoration: const InputDecoration(
                                      labelText: 'Giá vốn',
                                      isDense: true,
                                    ),
                                    onChanged: (v) {
                                      final val = NumberInputFormatter.tryParse(v);
                                      if (val == null || val < 0) return;
                                      final items = _getMixItems(it);
                                      if (idx >= items.length) return;
                                      items[idx]['rawUnitCost'] = val;
                                      _setMixItems(it, items);
                                      _recalcMixTotalsFromMixItems(it, items);
                                      setState(() {});
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: priceCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: false),
                                    inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
                                    decoration: const InputDecoration(
                                      labelText: 'Giá bán',
                                      isDense: true,
                                    ),
                                    onChanged: (v) {
                                      final val = NumberInputFormatter.tryParse(v);
                                      if (val == null || val < 0) return;
                                      final items = _getMixItems(it);
                                      if (idx >= items.length) return;
                                      items[idx]['rawUnitPrice'] = val;
                                      _setMixItems(it, items);
                                      setState(() {});
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 92,
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      currency.format(rawLineTotal),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Xóa nguyên liệu',
                                  onPressed: () {
                                    final items = _getMixItems(it);
                                    if (idx >= items.length) return;
                                    final removedId = (items[idx]['rawProductId']?.toString() ?? '').trim();
                                    items.removeAt(idx);
                                    _setMixItems(it, items);
                                    _recalcMixTotalsFromMixItems(it, items);
                                    if (removedId.isNotEmpty) {
                                      _disposeMixRawFieldFor(mixProductId: it.productId, rawProductId: removedId);
                                    }
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
