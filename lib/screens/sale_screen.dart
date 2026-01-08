import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../providers/product_provider.dart';
import 'voice_order_screen.dart';
import '../providers/sale_provider.dart';
import '../widgets/quantity_stepper.dart';
import '../models/customer.dart';
import '../providers/customer_provider.dart';
import '../providers/debt_provider.dart';
import '../models/debt.dart';
import 'package:intl/intl.dart';
import 'scan_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/contact_serializer.dart';
import '../utils/number_input_formatter.dart';
import '../utils/text_normalizer.dart';
import '../services/database_service.dart';
import '../services/product_image_service.dart';

class SaleScreen extends StatefulWidget {
  const SaleScreen({super.key});

  @override
  State<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends State<SaleScreen> {
  final TextEditingController _productCtrl = TextEditingController();
  final TextEditingController _customerCtrl = TextEditingController();
  final List<SaleItem> _items = [];
  final Map<String, TextEditingController> _qtyControllers = {};
  final Map<String, FocusNode> _qtyFocusNodes = {};
  final ScrollController _scrollCtrl = ScrollController();
  final Map<String, TextEditingController> _mixDisplayNameCtrls = {};
  double _discount = 0;
  double _paid = 0;
  String? _customerId;
  String? _customerName;
  String? _employeeId;
  String? _employeeName;
  bool _paidEdited = false;
  bool _showVietQrAfterSave = true;
  List<String> _recentUnits = ['cái', 'kg', 'g', 'hộp'];
  double _qtyStep = 1;
  VoidCallback? _clearProductField;
  VoidCallback? _unfocusProductField;

  List<Customer> _recentCustomers = [];
  List<Product> _recentProducts = [];

  static const String _prefShowVietQrAfterSave = 'sale_show_vietqr_after_save';
  static const String _prefEmployeeId = 'sale_employee_id';
  static const String _prefEmployeeName = 'sale_employee_name';

  Future<List<Map<String, dynamic>>> _ensureEmployees() async {
    var rows = await DatabaseService.instance.getEmployees();
    if (rows.isNotEmpty) return rows;
    await DatabaseService.instance.createEmployee(name: 'Mặc định');
    rows = await DatabaseService.instance.getEmployees();
    return rows;
  }

  Future<void> _loadSelectedEmployee() async {
    final sp = await SharedPreferences.getInstance();
    final savedId = (sp.getString(_prefEmployeeId) ?? '').trim();

    final rows = await _ensureEmployees();
    if (!mounted) return;
    if (rows.isEmpty) return;

    Map<String, dynamic>? selected;
    if (savedId.isNotEmpty) {
      for (final r in rows) {
        final id = (r['id']?.toString() ?? '').trim();
        if (id == savedId) {
          selected = r;
          break;
        }
      }
    }
    selected ??= rows.first;

    setState(() {
      _employeeId = (selected?['id']?.toString() ?? '').trim();
      _employeeName = (selected?['name']?.toString() ?? '').trim();
    });

    final nextId = (_employeeId ?? '').trim();
    final nextName = (_employeeName ?? '').trim();
    if (nextId.isNotEmpty) await sp.setString(_prefEmployeeId, nextId);
    if (nextName.isNotEmpty) await sp.setString(_prefEmployeeName, nextName);
  }

  Future<void> _pickEmployee() async {
    final rows = await _ensureEmployees();
    if (!mounted) return;
    if (rows.isEmpty) return;

    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r = rows[i];
              final id = (r['id']?.toString() ?? '').trim();
              final name = (r['name']?.toString() ?? '').trim();
              final selected = id.isNotEmpty && id == (_employeeId ?? '').trim();
              return ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(name.isEmpty ? id : name),
                subtitle: Text(id),
                trailing: selected ? const Icon(Icons.check, color: Colors.green) : null,
                onTap: () => Navigator.pop(ctx, r),
              );
            },
          ),
        );
      },
    );

    if (picked == null) return;
    final id = (picked['id']?.toString() ?? '').trim();
    final name = (picked['name']?.toString() ?? '').trim();
    if (id.isEmpty) return;

    final sp = await SharedPreferences.getInstance();
    await sp.setString(_prefEmployeeId, id);
    await sp.setString(_prefEmployeeName, name);
    if (!mounted) return;
    setState(() {
      _employeeId = id;
      _employeeName = name;
    });
  }

  Future<String?> _pickPaymentTypeForPaidAmount() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text('Tiền mặt'),
                onTap: () => Navigator.pop(ctx, 'cash'),
              ),
              ListTile(
                leading: const Icon(Icons.account_balance_outlined),
                title: const Text('Chuyển khoản'),
                onTap: () => Navigator.pop(ctx, 'bank'),
              ),
            ],
          ),
        );
      },
    );
    return picked;
  }

  TextEditingController _getQtyController(SaleItem it) {
    return _qtyControllers.putIfAbsent(
      it.productId,
      () => TextEditingController(
        text: it.quantity.toStringAsFixed(it.quantity % 1 == 0 ? 0 : 2),
      ),
    );
  }

  final Map<String, TextEditingController> _mixRawQtyControllers = {};
  final Map<String, FocusNode> _mixRawQtyFocusNodes = {};

  String _mixRawKey(String mixProductId, String rawProductId) => '$mixProductId::$rawProductId';

  TextEditingController _mixRawQtyCtrlFor({required String mixProductId, required String rawProductId, required double initialQty}) {
    final key = _mixRawKey(mixProductId, rawProductId);
    final existing = _mixRawQtyControllers[key];
    if (existing != null) return existing;
    final rawQty = initialQty;
    final ctrl = TextEditingController(
      text: rawQty == 0 ? '' : rawQty.toStringAsFixed(rawQty % 1 == 0 ? 0 : 2),
    );
    _mixRawQtyControllers[key] = ctrl;
    return ctrl;
  }

  FocusNode _mixRawQtyFocusFor({required String mixProductId, required String rawProductId}) {
    final key = _mixRawKey(mixProductId, rawProductId);
    return _mixRawQtyFocusNodes.putIfAbsent(key, () => FocusNode());
  }

  void _disposeMixRawFieldFor({required String mixProductId, required String rawProductId}) {
    final key = _mixRawKey(mixProductId, rawProductId);
    _mixRawQtyControllers.remove(key)?.dispose();
    _mixRawQtyFocusNodes.remove(key)?.dispose();
  }

  Map<String, double> _requiredRawQtyForThisSale() {
    final need = <String, double>{};
    for (final it in _items) {
      final t = (it.itemType ?? '').toUpperCase().trim();
      if (t == 'MIX') {
        final mixItems = _getMixItems(it);
        for (final m in mixItems) {
          final rid = (m['rawProductId']?.toString() ?? '').trim();
          if (rid.isEmpty) continue;
          final q = (m['rawQty'] as num?)?.toDouble() ?? 0.0;
          if (q <= 0) continue;
          need[rid] = (need[rid] ?? 0) + q;
        }
      } else {
        final pid = it.productId;
        final q = it.quantity;
        if (q <= 0) continue;
        need[pid] = (need[pid] ?? 0) + q;
      }
    }
    return need;
  }

  Future<bool> _ensureEnoughStockBeforeSave() async {
    final need = _requiredRawQtyForThisSale();
    if (need.isEmpty) return true;

    final products = await DatabaseService.instance.getProductsForSale();
    final byId = {for (final p in products) p.id: p};

    final now = DateTime.now();

    for (final entry in need.entries) {
      final pid = entry.key;
      final requiredQty = entry.value;
      final p = byId[pid];
      if (p == null) continue;

      final current = p.currentStock;
      if (current >= requiredQty) continue;

      final ctrl = TextEditingController(
        text: NumberFormat.decimalPattern('en_US').format(current),
      );

      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Tồn kho không đủ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sản phẩm: ${p.name}'),
              Text('Cần xuất: ${requiredQty.toStringAsFixed(requiredQty % 1 == 0 ? 0 : 2)} ${p.unit}'),
              Text('Tồn hiện tại: ${current.toStringAsFixed(current % 1 == 0 ? 0 : 2)} ${p.unit}'),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [NumberInputFormatter(maxDecimalDigits: 2)],
                decoration: const InputDecoration(
                  labelText: 'Cập nhật tồn hiện tại mới',
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cập nhật')),
          ],
        ),
      );

      if (ok != true) return false;

      final newCurrent = (NumberInputFormatter.tryParse(ctrl.text) ?? current).toDouble();
      await DatabaseService.instance.setCurrentStockAndRecalcOpeningStockForMonth(
        productId: pid,
        newCurrentStock: newCurrent,
        year: now.year,
        month: now.month,
      );
    }

    await context.read<ProductProvider>().load();
    return true;
  }

  Future<bool> _warnIfSellingBelowRawPrice() async {
    final byId = {for (final p in context.read<ProductProvider>().products) p.id: p};
    final warnings = <Map<String, dynamic>>[];

    for (final it in _items) {
      final t = (it.itemType ?? '').toUpperCase().trim();
      if (t != 'MIX') continue;

      final mixItems = _getMixItems(it);
      if (mixItems.isEmpty) continue;

      double rawSellTotal = 0.0;
      for (final m in mixItems) {
        final rid = (m['rawProductId']?.toString() ?? '').trim();
        final rawQty = (m['rawQty'] as num?)?.toDouble() ?? 0.0;
        if (rid.isEmpty || rawQty <= 0) continue;
        final rawPrice = byId[rid]?.price ?? 0.0;
        rawSellTotal += rawQty * rawPrice;
      }

      final saleTotal = it.total;
      if (rawSellTotal > 0 && saleTotal + 0.000001 < rawSellTotal) {
        warnings.add({
          'name': (it.displayName?.trim().isNotEmpty == true) ? it.displayName!.trim() : it.name,
          'saleTotal': saleTotal,
          'rawSellTotal': rawSellTotal,
        });
      }
    }

    if (warnings.isEmpty) return true;

    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cảnh báo giá bán'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Có sản phẩm bán thấp hơn tổng giá bán của nguyên liệu (RAW):'),
              const SizedBox(height: 8),
              ...warnings.map((w) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          (w['name'] as String?) ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${currency.format(w['saleTotal'] as double)} < ${currency.format(w['rawSellTotal'] as double)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                );
              }).toList(),
              const SizedBox(height: 8),
              const Text('Bạn vẫn muốn lưu hóa đơn?'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Quay lại')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Vẫn lưu')),
        ],
      ),
    );
    return ok == true;
  }

  FocusNode _getQtyFocusNode(SaleItem it) {
    return _qtyFocusNodes.putIfAbsent(it.productId, () => FocusNode());
  }

  void _disposeQtyFieldFor(String productId) {
    _qtyControllers.remove(productId)?.dispose();
    _qtyFocusNodes.remove(productId)?.dispose();
  }

  // Hàm chuyển đổi tiếng Việt có dấu thành không dấu
  String removeDiacritics(String str) {
    const withDiacritics =
        'áàảãạăắằẳẵặâấầuẩẫậéèẻẽẹêếềểễệíìỉĩịóòỏõọôốồổỗộơớờởỡợúùủũụưứừửữựýỳỷỹỵđ';
    const withoutDiacritics =
        'aaaaaăaaaaaaâaaaaaaeeeeeêeeeeeiiiiioooooôooooooơooooouuuuuưuuuuuyyyyyd';
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
    _loadShowVietQrAfterSave();
    _loadSelectedEmployee();
  }

  Future<void> _loadShowVietQrAfterSave() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(_prefShowVietQrAfterSave);
    if (!mounted) return;
    setState(() {
      _showVietQrAfterSave = v ?? true;
    });
  }

  Future<void> _setShowVietQrAfterSave(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefShowVietQrAfterSave, v);
    if (!mounted) return;
    setState(() {
      _showVietQrAfterSave = v;
    });
  }

  String _vietQrUrl({
    required String bankId,
    required String accountNo,
    required String accountName,
    required int amount,
    required String description,
    String template = 'compact2',
  }) {
    final addInfo = Uri.encodeComponent(description);
    final accName = Uri.encodeComponent(accountName);
    return 'https://img.vietqr.io/image/$bankId-$accountNo-$template.png?amount=$amount&addInfo=$addInfo&accountName=$accName';
  }

  String _sanitizeVietQrAddInfo(String s) {
    var out = removeDiacritics(s);
    out = out.replaceAll(RegExp(r'[^a-zA-Z0-9\s=xX\-]'), ' ');
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    return out;
  }

  String _last5DigitsOfId(String id) {
    final digits = id.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 5) return digits.substring(digits.length - 5);
    final raw = id.trim();
    if (raw.length >= 5) return raw.substring(raw.length - 5);
    return raw;
  }

  String _buildVietQrAddInfoFromItems({required String saleId, required List<SaleItem> items}) {
    final parts = <String>[];
    for (final it in items) {
      final name = it.name.trim();
      if (name.isEmpty) continue;
      final qty = it.quantity;
      final total = it.total;
      parts.add('${name} x${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2)}=${total.toInt()}');
    }
    final tail = _last5DigitsOfId(saleId);
    final raw = '${tail.isEmpty ? '' : '$tail '}Noi dung: ${parts.join('; ')}';
    final safe = _sanitizeVietQrAddInfo(raw);
    if (safe.length <= 50) return safe;
    return '${safe.substring(0, 47)}...';
  }

  Future<void> _showVietQrDialog({
    required int amount,
    required String description,
  }) async {
    final bank = await DatabaseService.instance.getDefaultVietQrBankAccount();
    if (!mounted) return;

    if (bank == null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Chưa cấu hình ngân hàng'),
          content: const Text(
            'Bạn chưa cấu hình ngân hàng VietQR mặc định.\n\nVào Cài đặt > Ngân hàng VietQR để thêm và chọn mặc định.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
          ],
        ),
      );
      return;
    }

    final bin = (bank['bin']?.toString() ?? '').trim();
    final code = (bank['code']?.toString() ?? '').trim();
    final bankId = bin.isNotEmpty ? bin : code;
    final accountNo = (bank['accountNo']?.toString() ?? '').trim();
    final accountName = (bank['accountName']?.toString() ?? '').trim();
    final logo = (bank['logo']?.toString() ?? '').trim();

    if (bankId.isEmpty || accountNo.isEmpty || accountName.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Thiếu thông tin ngân hàng'),
          content: const Text('Thông tin ngân hàng VietQR mặc định chưa đầy đủ. Vui lòng kiểm tra lại.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
          ],
        ),
      );
      return;
    }

    final url = _vietQrUrl(
      bankId: bankId,
      accountNo: accountNo,
      accountName: accountName,
      amount: amount,
      description: description,
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            children: [
              if (logo.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    logo,
                    width: 28,
                    height: 28,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox(width: 28, height: 28),
                  ),
                ),
              if (logo.isNotEmpty) const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Quét QR để chuyển khoản',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.network(
                url,
                width: 340,
                height: 340,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(6),
                  child: Text('Không tải được ảnh QR. Vui lòng thử lại.'),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'STK: $accountNo\nTên: $accountName',
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _productCtrl.dispose();
    _customerCtrl.dispose();
    _scrollCtrl.dispose();
    for (final c in _qtyControllers.values) {
      c.dispose();
    }
    for (final f in _qtyFocusNodes.values) {
      f.dispose();
    }
    for (final c in _mixRawQtyControllers.values) {
      c.dispose();
    }
    for (final f in _mixRawQtyFocusNodes.values) {
      f.dispose();
    }
    for (final c in _mixDisplayNameCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _isMixItem(SaleItem it) {
    return (it.itemType ?? '').toUpperCase().trim() == 'MIX';
  }

  TextEditingController _mixDisplayNameCtrlFor(SaleItem it) {
    return _mixDisplayNameCtrls.putIfAbsent(
      it.productId,
      () => TextEditingController(text: it.displayName ?? ''),
    );
  }

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

  void _addSelectedProductToSale(Product product) {
    if (product.itemType == ProductItemType.mix) {
      final exists = _items.any((e) => e.productId == product.id);
      if (exists) {
        _productCtrl.text = product.name;
        return;
      }

      _items.add(
        SaleItem(
          productId: product.id,
          name: product.name,
          unitPrice: product.price,
          unitCost: 0,
          quantity: 0,
          unit: product.unit,
          itemType: 'MIX',
          displayName: product.name,
          mixItemsJson: '[]',
        ),
      );
      _productCtrl.text = product.name;
      return;
    }

    final existingItem = _items.firstWhere(
      (item) => item.productId == product.id,
      orElse:
          () => SaleItem(
            productId: product.id,
            name: product.name,
            unitPrice: product.price,
            unitCost: product.costPrice,
            quantity: 0,
            unit: product.unit,
          ),
    );
    if (_items.contains(existingItem)) {
      existingItem.quantity += 1;
    } else {
      _items.add(existingItem..quantity = 1);
    }
    _productCtrl.text = product.name;
  }

  Future<Customer?> _showCustomerPicker({required List<Customer> customers}) async {
    return await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final TextEditingController searchController = TextEditingController();
        List<Customer> baseCustomers = List.from(customers);
        List<Customer> filteredCustomers = List.from(customers);

        return StatefulBuilder(
          builder: (context, setState) {
            void applyFilter(String value) {
              if (value.trim().isEmpty) {
                setState(() {
                  filteredCustomers = List.from(baseCustomers);
                });
                return;
              }
              final query = value.toLowerCase();
              setState(() {
                filteredCustomers = baseCustomers.where((customer) {
                  final nameMatch = customer.name.toLowerCase().contains(query);
                  final phoneMatch = customer.phone?.toLowerCase().contains(query) ?? false;
                  return nameMatch || phoneMatch;
                }).toList();
              });
            }

            return Container(
              padding: const EdgeInsets.all(16),
              height: MediaQuery.of(context).size.height * 0.8,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          decoration: InputDecoration(
                            labelText: 'Tìm kiếm khách hàng',
                            isDense: true,
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                searchController.clear();
                                applyFilter('');
                              },
                            ),
                          ),
                          onChanged: applyFilter,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Thêm khách hàng mới',
                        icon: const Icon(Icons.person_add_alt),
                        onPressed: () async {
                          await _addQuickCustomerDialog();
                          if (!context.mounted) return;
                          await context.read<CustomerProvider>().load();
                          if (!context.mounted) return;
                          setState(() {
                            baseCustomers = List.from(context.read<CustomerProvider>().customers);
                            applyFilter(searchController.text);
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filteredCustomers.isEmpty
                        ? const Center(child: Text('Không tìm thấy khách hàng nào'))
                        : ListView.builder(
                            itemCount: filteredCustomers.length,
                            itemBuilder: (context, index) {
                              final customer = filteredCustomers[index];
                              return ListTile(
                                leading: const CircleAvatar(child: Icon(Icons.person)),
                                title: Text(customer.name),
                                subtitle: Text(customer.phone ?? 'Không có SĐT'),
                                onTap: () => Navigator.of(context).pop(customer),
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

  Future<Product?> _showRawPicker({String? requiredUnit}) async {
    final products = await DatabaseService.instance.getProductsForSale();
    final raws = products.where((p) => p.itemType == ProductItemType.raw).toList();
    final filtered = requiredUnit == null ? raws : raws.where((p) => p.unit == requiredUnit).toList();

    return await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final TextEditingController searchController = TextEditingController();
        List<Product> filteredProducts = List.from(filtered);

        return StatefulBuilder(
          builder: (context, setState) {
            void applyFilter(String value) {
              if (value.trim().isEmpty) {
                setState(() {
                  filteredProducts = List.from(filtered);
                });
                return;
              }
              final query = value.toLowerCase();
              setState(() {
                filteredProducts = filtered.where((product) {
                  final nameMatch = product.name.toLowerCase().contains(query);
                  final barcodeMatch = product.barcode?.toLowerCase().contains(query) ?? false;
                  return nameMatch || barcodeMatch;
                }).toList();
              });
            }

            return Container(
              padding: const EdgeInsets.all(16),
              height: MediaQuery.of(context).size.height * 0.8,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          decoration: InputDecoration(
                            labelText: requiredUnit == null ? 'Chọn nguyên liệu (RAW)' : 'Chọn nguyên liệu ($requiredUnit)',
                            isDense: true,
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                searchController.clear();
                                applyFilter('');
                              },
                            ),
                          ),
                          onChanged: applyFilter,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Thêm sản phẩm mới',
                        icon: const Icon(Icons.add),
                        onPressed: () async {
                          await _addQuickProductDialog(
                            prefillName: searchController.text.trim().isEmpty ? null : searchController.text.trim(),
                          );
                          if (!context.mounted) return;
                          final products = await DatabaseService.instance.getProductsForSale();
                          final raws = products.where((p) => p.itemType == ProductItemType.raw).toList();
                          setState(() {
                            filteredProducts = requiredUnit == null
                                ? List<Product>.from(raws)
                                : raws.where((p) => p.unit == requiredUnit).toList();
                            applyFilter(searchController.text);
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filteredProducts.isEmpty
                        ? const Center(child: Text('Không tìm thấy nguyên liệu nào'))
                        : ListView.builder(
                            itemCount: filteredProducts.length,
                            itemBuilder: (context, index) {
                              final product = filteredProducts[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  child: Builder(
                                    builder: (_) {
                                      final img = product.imagePath;
                                      if (img != null && img.trim().isNotEmpty) {
                                        return FutureBuilder<String?>(
                                          future: ProductImageService.instance.resolvePath(img),
                                          builder: (context, snap) {
                                            final full = snap.data;
                                            if (full == null || full.isEmpty) {
                                              return const Icon(Icons.inventory_2_outlined);
                                            }
                                            return ClipOval(
                                              child: Image.file(
                                                File(full),
                                                width: 40,
                                                height: 40,
                                                fit: BoxFit.cover,
                                              ),
                                            );
                                          },
                                        );
                                      }
                                      return const Icon(Icons.inventory_2_outlined);
                                    },
                                  ),
                                ),
                                title: Text(product.name),
                                subtitle: Text('${NumberFormat('#,##0').format(product.price)} đ'),
                                trailing: Text('Tồn: ${product.currentStock} ${product.unit}'),
                                onTap: () => Navigator.of(context).pop(product),
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

    // If first raw, lock mix unit to raw unit and also update product unit in DB.
    if (requiredUnit == null) {
      mixLine.unit = raw.unit;
      await DatabaseService.instance.updateProductUnit(productId: mixLine.productId, unit: raw.unit);
    }

    // Add or increment existing raw
    final idx = mixItems.indexWhere((e) => (e['rawProductId']?.toString() ?? '') == raw.id);
    if (idx == -1) {
      mixItems.add({
        'rawProductId': raw.id,
        'rawName': raw.name,
        'rawUnit': raw.unit,
        'rawQty': 0.0,
        'rawUnitCost': raw.costPrice,
      });
    }

    _setMixItems(mixLine, mixItems);
    _recalcMixTotalsFromMixItems(mixLine, mixItems);

    setState(() {
      if (!_paidEdited) {
        final subtotal2 = _items.fold(0.0, (p, e) => p + e.total);
        final total2 = (subtotal2 - _discount).clamp(0, double.infinity).toDouble();
        _paid = total2;
      }
    });
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
      _recentCustomers =
          customerJsonList
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
    final updatedList =
        [customerJson, ...customerJsonList].toSet().take(3).toList();
    await sp.setStringList('recent_customers', updatedList);
    await _loadRecentCustomers();
  }

  Future<void> _loadRecentProducts() async {
    final sp = await SharedPreferences.getInstance();
    final productJsonList = sp.getStringList('recent_products') ?? [];
    final products = context.read<ProductProvider>().products;
    setState(() {
      _recentProducts =
          productJsonList
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
    final updatedList =
        [productJson, ...productJsonList].toSet().take(3).toList();
    await sp.setStringList('recent_products', updatedList);
    await _loadRecentProducts();
  }

  Future<void> _addQuickProductDialog({String? prefillName}) async {
    final nameCtrl = TextEditingController(text: prefillName ?? '');
    final priceCtrl = TextEditingController(text: '0');
    final costPriceCtrl = TextEditingController(text: '0');
    final stockCtrl = TextEditingController(text: '0');
    final prefs = await SharedPreferences.getInstance();
    final lastUnit = prefs.getString('last_product_unit') ?? 'cái';
    final unitCtrl = TextEditingController(text: lastUnit);
    final barcodeCtrl = TextEditingController();
    var isMix = false;

    XFile? pickedImage;
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Thêm sản phẩm'),
            content: StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: Builder(
                              builder: (_) {
                                if (pickedImage != null) {
                                  return Image.file(File(pickedImage!.path), fit: BoxFit.cover);
                                }
                                return const ColoredBox(
                                  color: Color(0xFFEFEFEF),
                                  child: Center(child: Icon(Icons.inventory_2_outlined)),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final x = await ImagePicker().pickImage(
                                    source: ImageSource.camera,
                                    imageQuality: 85,
                                  );
                                  if (x == null) return;
                                  setState(() => pickedImage = x);
                                },
                                icon: const Icon(Icons.photo_camera),
                                label: const Text('Chụp'),
                              ),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final x = await ImagePicker().pickImage(
                                    source: ImageSource.gallery,
                                    imageQuality: 85,
                                  );
                                  if (x == null) return;
                                  setState(() => pickedImage = x);
                                },
                                icon: const Icon(Icons.photo_library_outlined),
                                label: const Text('Chọn'),
                              ),
                              if (pickedImage != null)
                                TextButton.icon(
                                  onPressed: () => setState(() => pickedImage = null),
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Bỏ ảnh'),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: isMix,
                      onChanged: (v) => setState(() => isMix = v ?? false),
                      title: const Text('Hàng MIX'),
                    ),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Tên sản phẩm'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                        controller: priceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: false,
                        ),
                        inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
                        decoration: const InputDecoration(labelText: 'Giá bán'),
                      ),
                      const SizedBox(height: 8),
                    if (!isMix) ...[
                      
                      TextField(
                        controller: costPriceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: false,
                        ),
                        inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
                        decoration: const InputDecoration(labelText: 'Giá vốn'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: stockCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [NumberInputFormatter(maxDecimalDigits: 2)],
                        decoration: const InputDecoration(labelText: 'Tồn hiện tại'),
                      ),
                      const SizedBox(height: 8),
                    ],
                    
                    TextField(
                      controller: unitCtrl,
                      decoration: const InputDecoration(labelText: 'Đơn vị'),
                    ),
                    if (!isMix) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: barcodeCtrl,
                        decoration: InputDecoration(
                          labelText: 'Mã vạch (nếu có)',
                          suffixIcon: Builder(
                            builder:
                                (ctx) => IconButton(
                                  tooltip: 'Quét mã vạch',
                                  icon: const Icon(Icons.qr_code_scanner),
                                  onPressed: () async {
                                    final code = await Navigator.of(ctx).push<String>(
                                      MaterialPageRoute(
                                        builder: (_) => const ScanScreen(),
                                      ),
                                    );
                                    if (code != null && code.isNotEmpty) {
                                      barcodeCtrl.text = code;
                                      FocusScope.of(ctx).unfocus();
                                    }
                                  },
                                ),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Lưu'),
              ),
            ],
          ),
    );
    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      final provider = context.read<ProductProvider>();
      final newName = TextNormalizer.normalize(nameCtrl.text);
      final duplicated = provider.products.any(
        (p) => TextNormalizer.normalize(p.name) == newName,
      );
      if (duplicated) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã tồn tại sản phẩm cùng tên')),
        );
        return;
      }

      final unitValue = unitCtrl.text.trim().isEmpty ? 'cái' : unitCtrl.text.trim();
      final p = Product(
        name: nameCtrl.text.trim(),
        price: NumberInputFormatter.tryParse(priceCtrl.text) ?? 0,
        costPrice: isMix ? 0 : (NumberInputFormatter.tryParse(costPriceCtrl.text) ?? 0),
        currentStock: isMix ? 0 : (NumberInputFormatter.tryParse(stockCtrl.text) ?? 0),
        unit: unitValue,
        barcode: isMix
            ? null
            : (barcodeCtrl.text.trim().isEmpty ? null : barcodeCtrl.text.trim()),
        itemType: isMix ? ProductItemType.mix : ProductItemType.raw,
        isStocked: isMix ? false : true,
      );

      if (pickedImage != null) {
        final relPath = await ProductImageService.instance.saveFromXFile(
          source: pickedImage!,
          productId: p.id,
        );
        p.imagePath = relPath;
      }
      final unitToSave = p.unit.trim();
      if (unitToSave.isNotEmpty) {
        await prefs.setString('last_product_unit', unitToSave);
      }
      await provider.add(p);
      if (!isMix) {
        final now = DateTime.now();
        await DatabaseService.instance.upsertOpeningStocksForMonth(
          year: now.year,
          month: now.month,
          openingByProductId: {p.id: p.currentStock},
        );
      }
      setState(() {
        _addSelectedProductToSale(p);
      });
      if (!isMix) {
        await _applyLastUnitTo(
          _items.lastWhere((item) => item.productId == p.id),
        );
      }
      await _saveRecentProduct(p);
      if (!_paidEdited) {
        final subtotal = _items.fold(0.0, (p, e) => p + e.total);
        final total =
            (subtotal - _discount).clamp(0, double.infinity).toDouble();
        setState(() => _paid = total);
      }
      _unfocusProductField?.call();
    }
  }

  Future<Contact?> _showContactPicker() async {
    List<Contact> allContacts = await ContactSerializer.loadContactsFromPrefs();
    if (allContacts.isEmpty) {
      try {
        final granted = await FlutterContacts.requestPermission();
        if (granted) {
          allContacts = await FlutterContacts.getContacts(
            withProperties: true,
            withPhoto: true,
          );
          await ContactSerializer.saveContactsToPrefs(allContacts);
        }
      } catch (e) {
        debugPrint('Error getting contacts: $e');
      }
    }

    return await showModalBottomSheet<Contact>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final TextEditingController searchController = TextEditingController();
        List<Contact> filteredContacts = List.from(allContacts);

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
                            filteredContacts = List.from(allContacts);
                          });
                        },
                      ),
                    ),
                    onChanged: (value) {
                      if (value.isEmpty) {
                        setState(() {
                          filteredContacts = List.from(allContacts);
                        });
                      } else {
                        final query = value.toLowerCase();
                        setState(() {
                          filteredContacts =
                              allContacts.where((contact) {
                                final nameMatch = contact.displayName
                                    .toLowerCase()
                                    .contains(query);
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
                    child:
                        filteredContacts.isEmpty
                            ? const Center(
                              child: Text('Không tìm thấy liên hệ nào'),
                            )
                            : ListView.builder(
                              itemCount: filteredContacts.length,
                              itemBuilder: (context, index) {
                                final contact = filteredContacts[index];
                                return ListTile(
                                  leading:
                                      contact.photo != null
                                          ? CircleAvatar(
                                            backgroundImage: MemoryImage(
                                              contact.photo!,
                                            ),
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

  Future<Product?> _showProductPicker() async {
    final products = await DatabaseService.instance.getProductsForSale();
    List<Product> baseProducts = products.toList();
    return await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final TextEditingController searchController = TextEditingController();
        List<Product> filteredProducts = List.from(baseProducts);

        return StatefulBuilder(
          builder: (context, setState) {
            void applyFilter(String value) {
              if (value.trim().isEmpty) {
                setState(() {
                  filteredProducts = List.from(baseProducts);
                });
                return;
              }
              final query = value.toLowerCase();
              setState(() {
                filteredProducts = baseProducts.where((product) {
                  final nameMatch = product.name.toLowerCase().contains(query);
                  final barcodeMatch = product.barcode?.toLowerCase().contains(query) ?? false;
                  return nameMatch || barcodeMatch;
                }).toList();
              });
            }

            return Container(
              padding: const EdgeInsets.all(16),
              height: MediaQuery.of(context).size.height * 0.8,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          decoration: InputDecoration(
                            labelText: 'Tìm kiếm sản phẩm',
                            isDense: true,
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                searchController.clear();
                                applyFilter('');
                              },
                            ),
                          ),
                          onChanged: applyFilter,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Thêm sản phẩm nhanh',
                        icon: const Icon(Icons.add),
                        onPressed: () async {
                          await _addQuickProductDialog(
                            prefillName: searchController.text.trim().isEmpty ? null : searchController.text.trim(),
                          );
                          if (!context.mounted) return;
                          final products = await DatabaseService.instance.getProductsForSale();
                          baseProducts = products.toList();
                          setState(() {
                            applyFilter(searchController.text);
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child:
                        filteredProducts.isEmpty
                            ? const Center(
                              child: Text('Không tìm thấy sản phẩm nào'),
                            )
                            : ListView.builder(
                              itemCount: filteredProducts.length,
                              itemBuilder: (context, index) {
                                final product = filteredProducts[index];
                                final iconColor = product.itemType == ProductItemType.mix ? const Color.fromARGB(255, 93, 197, 8) : const Color.fromARGB(255, 240, 157, 184);
                                return ListTile(
                                  leading: CircleAvatar(
                                    radius: 20,
                                    child: Builder(
                                      builder: (_) {
                                        final img = product.imagePath;
                                        if (img != null && img.trim().isNotEmpty) {
                                          return FutureBuilder<String?>(
                                            future: ProductImageService.instance.resolvePath(img),
                                            builder: (context, snap) {
                                              final full = snap.data;
                                              if (full == null || full.isEmpty) {
                                                return Icon(Icons.shopping_bag, color: iconColor);
                                              }
                                              return ClipOval(
                                                child: Image.file(
                                                  File(full),
                                                  width: 40,
                                                  height: 40,
                                                  fit: BoxFit.cover,
                                                ),
                                              );
                                            },
                                          );
                                        }
                                        return Icon(Icons.shopping_bag, color: iconColor);
                                      },
                                    ),
                                  ),
                                  title: Text(product.name),
                                  subtitle: Text(
                                    product.itemType == ProductItemType.mix
                                        ? 'MIX • ${NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0).format(product.price)} / ${product.unit}'
                                        : '${NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0).format(product.price)} / ${product.unit}',
                                  ),
                                  onTap: () {
                                    Navigator.of(context).pop(product);
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

  Future<void> _addQuickCustomerDialog() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Thêm khách hàng mới'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên khách hàng',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Số điện thoại (tuỳ chọn)',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.contacts),
                      onPressed: () async {
                        final contact = await _showContactPicker();
                        if (contact != null) {
                          nameCtrl.text = contact.displayName;
                          if (contact.phones.isNotEmpty) {
                            phoneCtrl.text = contact.phones.first.number;
                          }
                        }
                      },
                      tooltip: 'Chọn từ danh bạ',
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () {
                  if (nameCtrl.text.trim().isNotEmpty) {
                    Navigator.pop(context, true);
                  }
                },
                child: const Text('Lưu'),
              ),
            ],
          ),
    );

    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      final name = nameCtrl.text.trim();
      final phone = phoneCtrl.text.trim();

      final provider = context.read<CustomerProvider>();
      final newName = TextNormalizer.normalize(name);
      final duplicated = provider.customers.any(
        (c) => TextNormalizer.normalize(c.name) == newName,
      );

      if (duplicated) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã tồn tại khách hàng cùng tên')),
        );
        return;
      }

      final customer = Customer(
        name: name,
        phone: phone.isEmpty ? null : phone,
      );

      await provider.add(customer);
      if (!mounted) return;
      setState(() {
        _customerId = customer.id;
        _customerName = customer.name;
        _customerCtrl.text = customer.name;
      });
      await _saveRecentCustomer(customer);
    }
  }

  @override
  Widget build(BuildContext context) {
    assert(() {
      _recentCustomers.length;
      _recentProducts.length;
      return true;
    }());

    final products = context.watch<ProductProvider>().products;
    final customers = context.watch<CustomerProvider>().customers;
    final subtotal = _items.fold(0.0, (p, e) => p + e.total);
    final total = (subtotal - _discount).clamp(0, double.infinity);
    final debt = (total - _paid).clamp(0, double.infinity);
    final currency = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
      decimalDigits: 0,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bán hàng'),
        actions: [
          TextButton.icon(
            onPressed: _pickEmployee,
            icon: const Icon(Icons.badge_outlined),
            label: Text((_employeeName ?? '').trim().isEmpty ? 'Nhân viên' : (_employeeName ?? '').trim()),
          ),
          IconButton(
            tooltip: 'Thêm sản phẩm',
            icon: const Icon(Icons.add_shopping_cart_outlined),
            onPressed: () async {
              final product = await _showProductPicker();
              if (product == null) return;
              if (!mounted) return;
              setState(() {
                _addSelectedProductToSale(product);
              });
              if (product.itemType != ProductItemType.mix) {
                await _applyLastUnitTo(
                  _items.lastWhere((item) => item.productId == product.id),
                );
              }
              await _saveRecentProduct(product);
              if (!_paidEdited) {
                final subtotal2 = _items.fold(0.0, (p, e) => p + e.total);
                final total2 = (subtotal2 - _discount).clamp(0, double.infinity).toDouble();
                if (!mounted) return;
                setState(() => _paid = total2);
              }
              _clearProductField?.call();
              _unfocusProductField?.call();
            },
          ),
          // Nút đặt hàng bằng giọng nói
          Builder(
            builder:
                (context) => IconButton(
                  tooltip: 'Đặt hàng bằng giọng nói',
                  icon: const Icon(Icons.mic),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const VoiceOrderScreen(),
                      ),
                    );
                  },
                ),
          ),
          // Nút quét mã vạch
          Builder(
            builder:
                (context) => IconButton(
                  tooltip: 'Quét mã vạch',
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: () async {
                    final code = await Navigator.of(context).push<String>(
                      MaterialPageRoute(builder: (_) => const ScanScreen()),
                    );
                    if (code == null || code.isEmpty) return;
                    final p = context.read<ProductProvider>().findByBarcode(
                      code,
                    );
                    if (p != null) {
                      setState(() {
                        final existingItem = _items.firstWhere(
                          (item) => item.productId == p.id,
                          orElse:
                              () => SaleItem(
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
                      await _applyLastUnitTo(
                        _items.lastWhere((item) => item.productId == p.id),
                      );
                      await _saveRecentProduct(p);
                      if (!_paidEdited) {
                        final subtotal2 = _items.fold(
                          0.0,
                          (p, e) => p + e.total,
                        );
                        final total2 =
                            (subtotal2 - _discount)
                                .clamp(0, double.infinity)
                                .toDouble();
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
          // Nút lịch sử bán
          /* Builder(
            builder:
                (context) => IconButton(
                  tooltip: 'Lịch sử bán',
                  icon: const Icon(Icons.history),
                  onPressed:
                      () => Navigator.of(context).pushNamed('/sales_history'),
                ),
          ), */
          // Popup menu thiết lập bước số lượng
          PopupMenuButton<String>(
            onSelected: (val) async {
              if (val == 'set_step') {
                final ctrl = TextEditingController(text: _qtyStep.toString());
                final ok = await showDialog<bool>(
                  context: context,
                  builder:
                      (_) => AlertDialog(
                        title: const Text('Thiết lập bước số lượng'),
                        content: TextField(
                          controller: ctrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Ví dụ: 0.1, 0.5, 1',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Hủy'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Lưu'),
                          ),
                        ],
                      ),
                );
                if (ok == true) {
                  final v = double.tryParse(ctrl.text.replaceAll(',', '.'));
                  if (v != null && v > 0) {
                    await _setQtyStep(v);
                  } else {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Giá trị không hợp lệ')),
                    );
                  }
                }
              }
            },
            itemBuilder:
                (context) => const [
                  PopupMenuItem(
                    value: 'set_step',
                    child: Text('Thiết lập bước số lượng'),
                  ),
                ],
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ListView(
            controller: _scrollCtrl,
            children: [
              // Customer selection
              InkWell(
                onTap: () async {
                  final customer = await _showCustomerPicker(customers: customers);
                  if (customer != null) {
                    setState(() {
                      _customerId = customer.id;
                      _customerName = customer.name;
                      _customerCtrl.text = customer.name;
                    });
                    await _saveRecentCustomer(customer);
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),                 
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          (_customerName ?? '').trim().isNotEmpty ? (_customerName ?? '').trim() : 'Chọn khách hàng',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 26),
                    ],
                  ),
                ),
              ),
             /*  const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await _addQuickProductDialog(
                      prefillName:
                          _productCtrl.text.trim().isEmpty ? null : _productCtrl.text.trim(),
                    );
                    _productCtrl.clear();
                    _unfocusProductField?.call();
                  },
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Thêm sản phẩm mới'),
                ),
              ), */
              const SizedBox(height: 8),
              // Wrap(
              //   spacing: 8,
              //   children: [
              //     ..._recentCustomers.map(
              //       (c) => ActionChip(
              //         backgroundColor: Colors.blue.withValues(alpha: 0.10),
              //         side: BorderSide(
              //           color: Colors.blue.withValues(alpha: 0.35),
              //         ),
              //         label: Text(c.name),
              //         labelStyle: const TextStyle(color: Colors.blue),
              //         onPressed: () async {
              //           setState(() {
              //             _customerId = c.id;
              //             _customerName = c.name;
              //             _customerCtrl.text = c.name;
              //           });
              //           await _saveRecentCustomer(c);
              //         },
              //       ),
              //     ),
              //   ],
              // ),
              const SizedBox(height: 8),
              // Wrap(
              //   spacing: 8,
              //   children: [
              //     ..._recentProducts.map(
              //       (p) => ActionChip(
              //         backgroundColor: Colors.green.withValues(alpha: 0.10),
              //         side: BorderSide(
              //           color: Colors.green.withValues(alpha: 0.35),
              //         ),
              //         label: Text(p.name),
              //         labelStyle: const TextStyle(color: Colors.green),
              //         onPressed: () async {
              //           setState(() {
              //             _addSelectedProductToSale(p);
              //           });
              //           if (p.itemType != ProductItemType.mix) {
              //             await _applyLastUnitTo(
              //               _items.lastWhere((item) => item.productId == p.id),
              //             );
              //           }
              //           await _saveRecentProduct(p);
              //           if (!_paidEdited) {
              //             final subtotal2 = _items.fold(
              //               0.0,
              //               (p, e) => p + e.total,
              //             );
              //             final total2 =
              //                 (subtotal2 - _discount)
              //                     .clamp(0, double.infinity)
              //                     .toDouble();
              //             setState(() => _paid = total2);
              //           }
              //           _clearProductField?.call();
              //           _unfocusProductField?.call();
              //         },
              //       ),
              //     ),
              //   ],
              // ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              if (_items.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: Text('Chưa có sản phẩm')),
                )
              else
                ...List.generate(_items.length, (i) {
                  final it = _items[i];
                  Product? prod;
                  try {
                    prod = products.firstWhere((p) => p.id == it.productId);
                  } catch (_) {
                    prod = null;
                  }
                  final isMixLine = _isMixItem(it);
                  final itemBg = i.isEven ? Colors.black.withValues(alpha: 0.03) : Colors.transparent;
                  final itemBorder = Colors.black.withValues(alpha: 0.08);
                  final qtyCtrl = _getQtyController(it);
                  final qtyFocus = _getQtyFocusNode(it);
                  final expectedText = it.quantity.toStringAsFixed(
                    it.quantity % 1 == 0 ? 0 : 2,
                  );
                  if (!qtyFocus.hasFocus && qtyCtrl.text != expectedText) {
                    qtyCtrl.text = expectedText;
                  }

                  return Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: itemBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: itemBorder),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: Colors.green.withValues(alpha: 0.10),
                                  child: Builder(
                                    builder: (_) {
                                      final img = prod?.imagePath;
                                      if (img != null && img.trim().isNotEmpty) {
                                        return FutureBuilder<String?>(
                                          future: ProductImageService.instance.resolvePath(img),
                                          builder: (context, snap) {
                                            final full = snap.data;
                                            if (full == null || full.isEmpty) {
                                              return Icon(isMixLine ? Icons.shopping_bag : Icons.inventory_2_outlined, color: Colors.green);
                                            }
                                            return ClipOval(
                                              child: Image.file(
                                                File(full),
                                                width: 40,
                                                height: 40,
                                                fit: BoxFit.cover,
                                              ),
                                            );
                                          },
                                        );
                                      }
                                      return Icon(isMixLine ? Icons.shopping_bag : Icons.inventory_2_outlined, color: Colors.green);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        it.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (prod != null && !isMixLine) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'Tồn: ${prod.currentStock.toStringAsFixed(prod.currentStock % 1 == 0 ? 0 : 2)} ${prod.unit}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                      if (isMixLine) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'MIX • SL = tổng nguyên liệu (${it.quantity.toStringAsFixed(it.quantity % 1 == 0 ? 0 : 2)} ${it.unit})',
                                          style: const TextStyle(fontSize: 12, color: Colors.black54),
                                        ),
                                      ],
                                      const SizedBox(height: 2),
                                      if (isMixLine)
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Expanded(
                                              child: GestureDetector(
                                                onTap: () async {
                                                  final ctrl = TextEditingController(
                                                    text: NumberFormat('#,###').format(
                                                      it.unitPrice,
                                                    ),
                                                  );
                                                  final ok = await showDialog<bool>(
                                                    context: context,
                                                    builder:
                                                        (_) => AlertDialog(
                                                      title: const Text(
                                                        'Sửa đơn giá',
                                                      ),
                                                      content: TextField(
                                                        controller: ctrl,
                                                        keyboardType:
                                                            const TextInputType.numberWithOptions(
                                                          decimal: true,
                                                        ),
                                                        inputFormatters: [
                                                          NumberInputFormatter(
                                                            maxDecimalDigits: 0,
                                                          ),
                                                        ],
                                                        decoration: const InputDecoration(
                                                          labelText: 'Đơn giá',
                                                        ),
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () => Navigator.pop(
                                                            context,
                                                            false,
                                                          ),
                                                          child: const Text('Hủy'),
                                                        ),
                                                        FilledButton(
                                                          onPressed: () => Navigator.pop(
                                                            context,
                                                            true,
                                                          ),
                                                          child: const Text('Lưu'),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                  if (ok == true) {
                                                    final v = NumberInputFormatter.tryParse(
                                                      ctrl.text,
                                                    );
                                                    if (v != null && v >= 0) {
                                                      setState(() {
                                                        it.unitPrice = v;
                                                        if (!_paidEdited) {
                                                          final subtotal2 = _items.fold(
                                                            0.0,
                                                            (p, e) => p + e.total,
                                                          );
                                                          _discount = _discount
                                                              .clamp(0, subtotal2)
                                                              .toDouble();
                                                          final total2 = (subtotal2 - _discount)
                                                              .clamp(
                                                                0,
                                                                double.infinity,
                                                              )
                                                              .toDouble();
                                                          _paid = total2;
                                                        }
                                                      });
                                                    }
                                                  }
                                                },
                                                child: Text(
                                                  '${currency.format(it.unitPrice)} × ${it.quantity} ${it.unit} (chạm để sửa)',
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              currency.format(it.total),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        )
                                      else
                                        GestureDetector(
                                          onTap: () async {
                                            final ctrl = TextEditingController(
                                              text: NumberFormat('#,###').format(
                                                it.unitPrice,
                                              ),
                                            );
                                            final ok = await showDialog<bool>(
                                              context: context,
                                              builder: (_) => AlertDialog(
                                                title: const Text(
                                                  'Sửa đơn giá',
                                                ),
                                                content: TextField(
                                                  controller: ctrl,
                                                  keyboardType:
                                                      const TextInputType.numberWithOptions(
                                                    decimal: true,
                                                  ),
                                                  inputFormatters: [
                                                    NumberInputFormatter(
                                                      maxDecimalDigits: 0,
                                                    ),
                                                  ],
                                                  decoration: const InputDecoration(
                                                    labelText: 'Đơn giá',
                                                  ),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(
                                                      context,
                                                      false,
                                                    ),
                                                    child: const Text('Hủy'),
                                                  ),
                                                  FilledButton(
                                                    onPressed: () => Navigator.pop(
                                                      context,
                                                      true,
                                                    ),
                                                    child: const Text('Lưu'),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (ok == true) {
                                              final v = NumberInputFormatter.tryParse(
                                                ctrl.text,
                                              );
                                              if (v != null && v >= 0) {
                                                setState(() {
                                                  it.unitPrice = v;
                                                  if (!_paidEdited) {
                                                    final subtotal2 = _items.fold(
                                                      0.0,
                                                      (p, e) => p + e.total,
                                                    );
                                                    _discount = _discount
                                                        .clamp(0, subtotal2)
                                                        .toDouble();
                                                    final total2 = (subtotal2 - _discount)
                                                        .clamp(
                                                          0,
                                                          double.infinity,
                                                        )
                                                        .toDouble();
                                                    _paid = total2;
                                                  }
                                                });
                                              }
                                            }
                                          },
                                          child: Text(
                                            '${currency.format(it.unitPrice)} × ${it.quantity} ${it.unit} (chạm để sửa)',
                                          ),
                                        ),
                                      if (isMixLine) ...[
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
                                        const SizedBox(height: 8),
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
                                          final ctrl = _mixRawQtyCtrlFor(
                                            mixProductId: it.productId,
                                            rawProductId: rawId,
                                            initialQty: rawQty,
                                          );
                                          final focusNode = _mixRawQtyFocusFor(
                                            mixProductId: it.productId,
                                            rawProductId: rawId,
                                          );
                                          double? rawStock;
                                          for (final p in context.read<ProductProvider>().products) {
                                            if (p.id == rawId) {
                                              rawStock = p.currentStock;
                                              break;
                                            }
                                          }
                                          return Padding(
                                            padding: const EdgeInsets.only(top: 6.0),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
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
                                                          const SizedBox(width: 8),
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
                                                      const SizedBox(height: 4),
                                                      Row(
                                                        children: [
                                                          SizedBox(
                                                            width: 74,
                                                            child: TextField(
                                                              controller: ctrl,
                                                              focusNode: focusNode,
                                                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                              inputFormatters: [NumberInputFormatter(maxDecimalDigits: 2)],
                                                              decoration: InputDecoration(
                                                                hintText: rawUnit.isEmpty ? 'SL' : 'SL ($rawUnit)',
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
                                                                setState(() {
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
                                                          Expanded(
                                                            child: Text(
                                                              'Giá: ${currency.format(rawUnitCost)}  •  Thành: ${currency.format(rawQty * rawUnitCost)}',
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                              style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
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
                                                    setState(() {
                                                      if (!_paidEdited) {
                                                        final subtotal2 = _items.fold(0.0, (p, e) => p + e.total);
                                                        final total2 = (subtotal2 - _discount).clamp(0, double.infinity).toDouble();
                                                        _paid = total2;
                                                      }
                                                    });
                                                  },
                                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                                ),
                                              ],
                                            ),
                                          );
                                        }),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (!isMixLine)
                                  Text(
                                    currency.format(it.total),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                if (!isMixLine) ...[
                                  SizedBox(
                                    width: 60,
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: it.unit.isEmpty ? null : it.unit,
                                        hint: const Text('Đơn vị'),
                                        isExpanded: true,
                                        items:
                                            _recentUnits
                                                .map(
                                                  (u) => DropdownMenuItem(
                                                    value: u,
                                                    child: Text(u),
                                                  ),
                                                )
                                                .toList(),
                                        onChanged: (u) async {
                                          if (u == null) return;
                                          setState(() => it.unit = u);
                                          await _rememberUnit(u);
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                SizedBox(
                                  width: 110,
                                  child: Builder(
                                    builder:
                                        (qtyFieldCtx) => TextField(
                                          key: ValueKey('qty_${it.productId}'),
                                          controller: qtyCtrl,
                                          focusNode: qtyFocus,
                                          keyboardType:
                                              const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                          inputFormatters: [
                                            NumberInputFormatter(
                                              maxDecimalDigits: 2,
                                            ),
                                          ],
                                          decoration: const InputDecoration(
                                            labelText: 'Số lượng',
                                            isDense: true,
                                          ),
                                          readOnly: isMixLine,
                                          onTap: () {
                                            Scrollable.ensureVisible(
                                              qtyFieldCtx,
                                              duration: const Duration(
                                                milliseconds: 200,
                                              ),
                                              curve: Curves.easeOut,
                                              alignment: 0.2,
                                            );
                                          },
                                          onChanged: (v) {
                                            final val =
                                                NumberInputFormatter.tryParse(
                                                  v,
                                                );
                                            if (val == null) return;
                                            setState(() {
                                              it.quantity =
                                                  val <= 0 ? 0.0 : val;
                                              if (!_paidEdited) {
                                                final subtotal2 = _items.fold(
                                                  0.0,
                                                  (p, e) => p + e.total,
                                                );
                                                final total2 =
                                                    (subtotal2 - _discount)
                                                        .clamp(
                                                          0,
                                                          double.infinity,
                                                        )
                                                        .toDouble();
                                                _paid = total2;
                                              }
                                            });
                                          },
                                          onSubmitted: (v) {
                                            final val =
                                                NumberInputFormatter.tryParse(
                                                  v,
                                                );
                                            if (val == null) return;
                                            setState(() {
                                              it.quantity =
                                                  val <= 0 ? 0.0 : val;
                                              final t = it.quantity
                                                  .toStringAsFixed(
                                                    it.quantity % 1 == 0
                                                        ? 0
                                                        : 2,
                                                  );
                                              qtyCtrl.value = qtyCtrl.value
                                                  .copyWith(
                                                    text: t,
                                                    selection:
                                                        TextSelection.collapsed(
                                                          offset: t.length,
                                                        ),
                                                    composing: TextRange.empty,
                                                  );
                                              if (!_paidEdited) {
                                                final subtotal2 = _items.fold(
                                                  0.0,
                                                  (p, e) => p + e.total,
                                                );
                                                final total2 =
                                                    (subtotal2 - _discount)
                                                        .clamp(
                                                          0,
                                                          double.infinity,
                                                        )
                                                        .toDouble();
                                                _paid = total2;
                                              }
                                            });
                                          },
                                        ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (!isMixLine)
                                  QuantityStepper(
                                    value: it.quantity,
                                    onChanged: (v) {
                                      setState(() {
                                        it.quantity = v <= 0 ? 0.0 : v;
                                        final t = it.quantity.toStringAsFixed(
                                          it.quantity % 1 == 0 ? 0 : 2,
                                        );
                                        qtyCtrl.value = qtyCtrl.value.copyWith(
                                          text: t,
                                          selection: TextSelection.collapsed(
                                            offset: t.length,
                                          ),
                                          composing: TextRange.empty,
                                        );
                                        if (!_paidEdited) {
                                          final subtotal2 = _items.fold(
                                            0.0,
                                            (p, e) => p + e.total,
                                          );
                                          final total2 =
                                              (subtotal2 - _discount)
                                                  .clamp(0, double.infinity)
                                                  .toDouble();
                                          _paid = total2;
                                        }
                                      });
                                    },
                                    step: _qtyStep,
                                  ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _disposeQtyFieldFor(it.productId);
                                      _mixDisplayNameCtrls.remove(it.productId)?.dispose();
                                      _items.removeAt(i);
                                      if (!_paidEdited) {
                                        final subtotal2 = _items.fold(
                                          0.0,
                                          (p, e) => p + e.total,
                                        );
                                        _discount = _discount.clamp(0, subtotal2).toDouble();
                                        final total2 =
                                            (subtotal2 - _discount)
                                                .clamp(0, double.infinity)
                                                .toDouble();
                                        _paid = total2;
                                      }
                                    });
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    ],
                  );
                }),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text('Tạm tính: ${currency.format(subtotal)}'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Giảm'),
                        TextField(
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            NumberInputFormatter(maxDecimalDigits: 0),
                          ],
                          decoration: const InputDecoration(
                            hintText: '0',
                            isDense: true,
                          ),
                          onChanged: (v) {
                            final val = NumberInputFormatter.tryParse(v) ?? 0;
                            setState(() {
                              _discount = val.clamp(0, subtotal).toDouble();
                              if (!_paidEdited) {
                                final total2 =
                                    (subtotal - _discount)
                                        .clamp(0, double.infinity)
                                        .toDouble();
                                _paid = total2;
                              }
                            });
                          },
                          controller: TextEditingController(
                              text:
                                  _discount == 0
                                      ? ''
                                      : _discount.toStringAsFixed(0),
                            )
                            ..selection = TextSelection.collapsed(
                              offset:
                                  (_discount == 0
                                          ? ''
                                          : _discount.toStringAsFixed(0))
                                      .length,
                            ),
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
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            NumberInputFormatter(maxDecimalDigits: 0),
                          ],
                          decoration: const InputDecoration(
                            hintText: '0',
                            isDense: true,
                          ),
                          onChanged: (v) {
                            final val = NumberInputFormatter.tryParse(v) ?? 0;
                            setState(() {
                              _paidEdited = true;
                              _paid = val.clamp(0, total).toDouble();
                            });
                          },
                          controller: TextEditingController(
                              text: _paid == 0 ? '' : _paid.toStringAsFixed(0),
                            )
                            ..selection = TextSelection.collapsed(
                              offset:
                                  (_paid == 0 ? '' : _paid.toStringAsFixed(0))
                                      .length,
                            ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      //_paidEdited = true;
                      _paid = 0;
                    });
                  },
                  child: const Text('Khách nợ tất'),
                ),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _showVietQrAfterSave,
                onChanged: (v) => _setShowVietQrAfterSave(v),
                title: const Text('Hiển thị VietQR khi lưu (CK)'),
                subtitle: const Text('Mặc định bật. Nếu khách nợ tất thì không hiển thị.'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      _items.isEmpty
                          ? null
                          : () async {
                            final okStock = await _ensureEnoughStockBeforeSave();
                            if (!okStock) return;

                            final okPrice = await _warnIfSellingBelowRawPrice();
                            if (!okPrice) return;

                            if (debt > 0 && (_customerId == null || _customerId!.isEmpty)) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Có nợ thì bắt buộc phải chọn khách hàng'),
                                ),
                              );
                              return;
                            }
                            // Tính totalCost dựa trên unitCost của các SaleItem
                            double calculatedTotalCost = _items.fold(
                              0.0,
                              (p, e) => p + e.totalCost,
                            );

                            String? paymentType;
                            if (_paid > 0) {
                              paymentType = await _pickPaymentTypeForPaidAmount();
                              if (paymentType == null) return;
                            }
                            final sale = Sale(
                              items: _items.toList(),
                              discount: _discount,
                              paidAmount: _paid,
                              paymentType: paymentType,
                              customerId: _customerId,
                              customerName: _customerName,
                              employeeId: _employeeId,
                              employeeName: _employeeName,
                              totalCost:
                                  calculatedTotalCost, // Thêm totalCost vào Sale
                            );
                            await context.read<SaleProvider>().add(sale);

                            // Reload sản phẩm để cập nhật tồn hiện tại sau khi trừ tồn trong DB
                            await context.read<ProductProvider>().load();

                            final debtValue =
                                (sale.total - sale.paidAmount)
                                    .clamp(0.0, double.infinity)
                                    .toDouble();
                            if (debtValue > 0) {
                              final details =
                                  StringBuffer()
                                    ..writeln(
                                      'Bán hàng ngày ${DateFormat('dd/MM/yyyy HH:mm').format(sale.createdAt)}',
                                    )
                                    ..writeln(
                                      'Khách: ${_customerName ?? 'Khách lẻ'}',
                                    )
                                    ..writeln('Chi tiết:')
                                    ..writeln(
                                      _items
                                          .map(
                                            (it) =>
                                                '- ${it.name} x ${it.quantity} ${it.unit} = ${currency.format(it.total)}',
                                          )
                                          .join('\n'),
                                    )
                                    ..writeln(
                                      'Tạm tính: ${currency.format(subtotal)}',
                                    )
                                    ..writeln(
                                      'Giảm: ${currency.format(_discount)}',
                                    )
                                    ..writeln(
                                      'Khách trả: ${currency.format(_paid)}',
                                    )
                                    ..writeln(
                                      'Còn nợ: ${currency.format(debtValue)}',
                                    );
                              await context.read<DebtProvider>().add(
                                Debt(
                                  type: DebtType.othersOweMe,
                                  partyId: _customerId ?? 'unknown',
                                  partyName: _customerName ?? 'Khách lẻ',
                                  amount: debtValue,
                                  description: details.toString(),
                                  sourceType: 'sale',
                                  sourceId: sale.id,
                                ),
                              );
                            }

                            // Show VietQR only when:
                            // - user enabled toggle
                            // - paid amount > 0 and chosen paymentType = bank
                            // - no remaining debt (customer did not choose 'nợ tất')
                            // NOTE: if debtValue > 0, do not show QR.
                            if (_showVietQrAfterSave && paymentType == 'bank' && _paid > 0 && debtValue <= 0) {
                              final desc = _buildVietQrAddInfoFromItems(saleId: sale.id, items: _items);
                              await _showVietQrDialog(
                                amount: _paid.toInt(),
                                description: desc,
                              );
                            }
                            setState(() {
                              _items.clear();
                              _discount = 0;
                              _paid = 0;
                              _customerId = null;
                              _customerName = null;
                              _customerCtrl.clear();
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Đã lưu bán hàng')),
                            );
                          },
                  icon: const Icon(Icons.save),
                  label: Text(
                    debt > 0
                        ? 'Lưu + Ghi nợ (${currency.format(debt)})'
                        : 'Lưu hóa đơn',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
