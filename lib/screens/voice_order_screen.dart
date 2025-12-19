import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/customer.dart';
import '../models/debt.dart';
import '../models/product.dart';
import '../models/sale.dart';

import '../providers/debt_provider.dart';
import '../providers/product_provider.dart';
import '../providers/customer_provider.dart';
import '../providers/sale_provider.dart';
import '../utils/number_input_formatter.dart';
import '../utils/string_utils.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../utils/contact_serializer.dart';

class VoiceOrderScreen extends StatefulWidget {
  const VoiceOrderScreen({Key? key}) : super(key: key);

  @override
  State<VoiceOrderScreen> createState() => _VoiceOrderScreenState();
}

class _VoiceOrderScreenState extends State<VoiceOrderScreen> {

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _status = 'Nhấn vào nút micrô để bắt đầu nhận dạng giọng nói';
  String _recognizedText = '';

  // State cho đơn hàng tự động
  List<Map<String, dynamic>> _orders = []; // List items: {'item': '', 'quantity': 0, 'price': 0}
  String? _customerId;
  String _customer = ''; // Tên khách hàng
  bool _customerExactMatched = false;
  double _paid = 0;
  bool _paidEdited = false;
  final TextEditingController _paidCtrl = TextEditingController();

  final Map<Object, TextEditingController> _qtyCtrls = {};
  final Map<Object, TextEditingController> _priceCtrls = {};

  Product? _getProductById(String id) {
    final products = context.read<ProductProvider>().products;
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  String _formatForInput(double v, {required int maxDecimalDigits, bool blankIfZero = false}) {
    if (blankIfZero && v == 0) return '';

    final abs = v.abs();
    final sign = v < 0 ? '-' : '';
    final intPart = abs.truncate();
    final formattedInt = NumberFormat.decimalPattern('en_US').format(intPart);

    if (maxDecimalDigits <= 0) return '$sign$formattedInt';

    final hasDecimals = abs % 1 != 0;
    if (!hasDecimals) return '$sign$formattedInt';

    var dec = abs.toStringAsFixed(maxDecimalDigits).split('.').last;
    dec = dec.replaceFirst(RegExp(r'0+$'), '');
    if (dec.isEmpty) return '$sign$formattedInt';
    return '$sign$formattedInt.$dec';
  }

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  void _syncPaidCtrlFromPaid() {
    final t = _formatForInput(
      _paid,
      maxDecimalDigits: 0,
      blankIfZero: true,
    );
    if (_paidCtrl.text == t) return;
    _paidCtrl.text = t;
    _paidCtrl.selection = TextSelection.collapsed(offset: _paidCtrl.text.length);
  }

  void _syncPaidWithTotalIfNotEdited(double total) {
    if (_paidEdited) return;
    final desired = total.clamp(0, double.infinity).toDouble();
    if ((_paid - desired).abs() < 0.0001) {
      _syncPaidCtrlFromPaid();
      return;
    }
    _paid = desired;
    _syncPaidCtrlFromPaid();
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
      } catch (_) {}
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
              padding: const EdgeInsets.all(12),
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
                      final q = value.trim().toLowerCase();
                      if (q.isEmpty) {
                        setState(() {
                          filteredContacts = List.from(allContacts);
                        });
                        return;
                      }
                      setState(() {
                        filteredContacts = allContacts.where((contact) {
                          final nameMatch = contact.displayName.toLowerCase().contains(q);
                          final phoneMatch = contact.phones.any((phone) => phone.number.contains(q));
                          return nameMatch || phoneMatch;
                        }).toList();
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: filteredContacts.isEmpty
                        ? const Center(child: Text('Không tìm thấy liên hệ nào'))
                        : ListView.builder(
                            itemCount: filteredContacts.length,
                            itemBuilder: (context, index) {
                              final contact = filteredContacts[index];
                              return ListTile(
                                leading: contact.photo != null
                                    ? CircleAvatar(backgroundImage: MemoryImage(contact.photo!))
                                    : const CircleAvatar(child: Icon(Icons.person)),
                                title: Text(contact.displayName),
                                subtitle: Text(
                                  contact.phones.isNotEmpty ? contact.phones.first.number : 'Không có SĐT',
                                ),
                                onTap: () => Navigator.of(context).pop(contact),
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

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: (status) {
        if (!mounted) return;
        setState(() {
          _status = 'Trạng thái: $status';
        });
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _status = 'Lỗi: $error';
          _isListening = false;
        });
      },
    );

    if (!available && mounted) {
      setState(() {
        _status = 'Không thể khởi tạo nhận dạng giọng nói';
      });
    }
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() => _isListening = false);
      return;
    }

    final available = await _speech.initialize();
    if (!available) {
      if (!mounted) return;
      setState(() {
        _status = 'Không thể bắt đầu nhận dạng giọng nói';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isListening = true;
      _status = 'Đang nghe...';
      _recognizedText = '';
    });

    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _recognizedText = result.recognizedWords;
          if (result.finalResult) {
            _isListening = false;
            _status = 'Đang gửi AI xử lý...';
            _processWithAI(_recognizedText);
          }
        });
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      listenOptions: stt.SpeechListenOptions(partialResults: true),
      localeId: 'vi_VN',
    );
  }

  TextEditingController _qtyCtrlFor(Map<String, dynamic> order) {
    final key = order['productId'] ?? order['item'] ?? order;
    return _qtyCtrls.putIfAbsent(
      key,
      () => TextEditingController(
        text: _formatForInput(
          ((order['quantity'] as num?)?.toDouble() ?? 0),
          maxDecimalDigits: 2,
        ),
      ),
    );
  }

  Future<String?> _showProductPicker() async {
    final products = context.read<ProductProvider>().products;
    return await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final searchController = TextEditingController();
        var filtered = List.of(products);
        final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              padding: const EdgeInsets.all(12),
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
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                searchController.clear();
                                setState(() => filtered = List.of(products));
                              },
                            ),
                          ),
                          onChanged: (value) {
                            final q = value.trim().toLowerCase();
                            if (q.isEmpty) {
                              setState(() => filtered = List.of(products));
                              return;
                            }
                            setState(() {
                              filtered = products.where((p) {
                                final nameMatch = p.name.toLowerCase().contains(q);
                                final barcodeMatch = p.barcode?.toLowerCase().contains(q) ?? false;
                                return nameMatch || barcodeMatch;
                              }).toList();
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 56,
                        width: 48,
                        child: IconButton(
                          tooltip: 'Thêm sản phẩm mới',
                          icon: const Icon(Icons.add_box_outlined),
                          onPressed: () async {
                            final q = searchController.text.trim();
                            final tempOrder = <String, dynamic>{
                              'item': q,
                              'quantity': 1.0,
                              'price': 0.0,
                            };
                            await _addQuickProductDialog(
                              prefillName: q.isEmpty ? null : q,
                              targetOrder: tempOrder,
                            );
                            final newId = tempOrder['productId']?.toString();
                            if (newId != null && newId.isNotEmpty && mounted) {
                              Navigator.of(context).pop(newId);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('Không tìm thấy sản phẩm nào'))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final p = filtered[index];
                              return ListTile(
                                leading: const CircleAvatar(child: Icon(Icons.shopping_bag)),
                                title: Text(p.name),
                                subtitle: Text(currency.format(p.price)),
                                trailing: Text(
                                  'Tồn: ${p.currentStock.toStringAsFixed(p.currentStock % 1 == 0 ? 0 : 2)} ${p.unit}',
                                ),
                                onTap: () {
                                  Navigator.of(context).pop(p.id);
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

  TextEditingController _priceCtrlFor(Map<String, dynamic> order) {
    final key = order['productId'] ?? order['item'] ?? order;
    return _priceCtrls.putIfAbsent(
      key,
      () => TextEditingController(
        text: _formatForInput(
          ((order['price'] as num?)?.toDouble() ?? 0),
          maxDecimalDigits: 0,
          blankIfZero: true,
        ),
      ),
    );
  }

  Future<void> _addQuickCustomerDialog({String? prefillName}) async {
    final nameCtrl = TextEditingController(text: prefillName ?? '');
    final phoneCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Thêm khách hàng mới'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Tên khách hàng'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'SĐT (tuỳ chọn)',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.contacts),
                  tooltip: 'Chọn từ danh bạ',
                  onPressed: () async {
                    final contact = await _showContactPicker();
                    if (contact != null) {
                      nameCtrl.text = contact.displayName;
                      if (contact.phones.isNotEmpty) {
                        phoneCtrl.text = contact.phones.first.number;
                      }
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: 'Ghi chú (tuỳ chọn)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lưu')),
        ],
      ),
    );
    if (ok != true) return;

    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;

    final c = Customer(
      name: name,
      phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      isSupplier: false,
    );

    await context.read<CustomerProvider>().add(c);
    if (!mounted) return;
    setState(() {
      _customerId = c.id;
      _customer = c.name;
      _customerExactMatched = true;
    });
  }

  Future<void> _addQuickProductDialog({String? prefillName, required Map<String, dynamic> targetOrder}) async {
    final nameCtrl = TextEditingController(text: prefillName ?? '');
    final priceCtrl = TextEditingController(text: '0');
    final costPriceCtrl = TextEditingController(text: '0');
    final stockCtrl = TextEditingController(text: '0');
    final prefs = await SharedPreferences.getInstance();
    final lastUnit = prefs.getString('last_product_unit') ?? 'cái';
    final unitCtrl = TextEditingController(text: lastUnit);
    final barcodeCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Thêm sản phẩm'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Tên sản phẩm'),
            ),
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
            TextField(
              controller: unitCtrl,
              decoration: const InputDecoration(labelText: 'Đơn vị'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: barcodeCtrl,
              decoration: const InputDecoration(labelText: 'Mã vạch (tuỳ chọn)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lưu')),
        ],
      ),
    );
    if (ok != true) return;

    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;

    final price = (NumberInputFormatter.tryParse(priceCtrl.text) ?? 0).toDouble();
    final costPrice = (NumberInputFormatter.tryParse(costPriceCtrl.text) ?? 0).toDouble();
    final stock = (NumberInputFormatter.tryParse(stockCtrl.text) ?? 0).toDouble();
    final unit = unitCtrl.text.trim().isEmpty ? 'cái' : unitCtrl.text.trim();
    final barcode = barcodeCtrl.text.trim().isEmpty ? null : barcodeCtrl.text.trim();

    final p = Product(
      name: name,
      price: price,
      costPrice: costPrice,
      currentStock: stock,
      unit: unit,
      barcode: barcode,
      isActive: true,
    );

    final unitToSave = p.unit.trim();
    if (unitToSave.isNotEmpty) {
      await prefs.setString('last_product_unit', unitToSave);
    }

    await context.read<ProductProvider>().add(p);
    if (!mounted) return;

    setState(() {
      targetOrder['productId'] = p.id;
      targetOrder['item'] = p.name;
      targetOrder['unit'] = p.unit;
      if ((targetOrder['price'] as num?)?.toDouble() == 0) {
        targetOrder['price'] = p.price.toDouble();
      }
      targetOrder['dbExactMatched'] = true;
      _priceCtrls.removeWhere((k, _) => true);
      _qtyCtrls.removeWhere((k, _) => true);
    });
  }

  Future<String?> _showCustomerPicker() async {
    final customers = context.read<CustomerProvider>().customers;
    return await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final searchController = TextEditingController();
        var filtered = List.of(customers);
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
                      labelText: 'Tìm kiếm khách hàng',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          searchController.clear();
                          setState(() => filtered = List.of(customers));
                        },
                      ),
                    ),
                    onChanged: (value) {
                      final q = value.trim().toLowerCase();
                      if (q.isEmpty) {
                        setState(() => filtered = List.of(customers));
                        return;
                      }
                      setState(() {
                        filtered = customers.where((c) {
                          final nameMatch = c.name.toLowerCase().contains(q);
                          final phoneMatch = c.phone?.toLowerCase().contains(q) ?? false;
                          return nameMatch || phoneMatch;
                        }).toList();
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('Không tìm thấy khách hàng nào'))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final c = filtered[index];
                              return ListTile(
                                leading: const CircleAvatar(child: Icon(Icons.person)),
                                title: Text(c.name),
                                subtitle: Text(c.phone ?? 'Không có SĐT'),
                                onTap: () {
                                  Navigator.of(context).pop(c.id);
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

  // Hàm gửi đến OpenRouter AI và xử lý kết quả
  Future<void> _processWithAI(String text) async {
    if (text.isEmpty) return;

    const apiKey = String.fromEnvironment('OPENROUTER_API_KEY');
    
    if (apiKey.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _status = 'Thiếu API key (OPENROUTER_API_KEY). Hãy build với --dart-define=OPENROUTER_API_KEY=...';
      });

      return;
    }
    const String model = 'nvidia/nemotron-3-nano-30b-a3b:free';

    final String prompt = '''
Phân tích lệnh giọng nói tiếng Việt này và trả về đúng một JSON object theo schema sau (không thêm text thừa):
{
  "customer": "tên khách hàng (nếu có)",
  "paidAmount": 0,
  "items": [
    {
      "action": "add" hoặc "remove",
      "item": "tên sản phẩm",
      "quantity": số lượng,
      "price": giá tiền (nếu có)

    }
  ]
}

Ví dụ 1 (đơn hàng đơn giản):
"Mua 2 chai nước ngọt giá 15000 đồng" 
-> {
  "items": [
    {"action": "add", "item": "nước ngọt", "quantity": 2, "price": 15000}
  ]
}

Ví dụ 2 (nhiều sản phẩm):
"Mua 2 chai nước ngọt giá 15000, 3 bánh mì giá 20000"
-> {
  "items": [
    {"action": "add", "item": "nước ngọt", "quantity": 2, "price": 15000},
    {"action": "add", "item": "bánh mì", "quantity": 3, "price": 20000}
  ]
}

Ví dụ 3 (kèm thông tin khách hàng):
"Đặt hàng cho khách Nguyễn Văn A: 2 nước ngọt giá 15000, 1 bánh mì giá 20000"
-> {
  "customer": "Nguyễn Văn A",
  "paidAmount": 0,
  "items": [
    {"action": "add", "item": "nước ngọt", "quantity": 2, "price": 15000},
    {"action": "add", "item": "bánh mì", "quantity": 1, "price": 20000}
  ]
}

Ví dụ 6 (có khách trả tiền):
"Khách Nguyễn Văn A mua 2 nước ngọt, khách trả 20000"
-> {
  "customer": "Nguyễn Văn A",
  "paidAmount": 20000,
  "items": [
    {"action": "add", "item": "nước ngọt", "quantity": 2}
  ]
}
}

Ví dụ 4 (xoá sản phẩm):
"Xoá 1 nước ngọt"
-> {
  "items": [
    {"action": "remove", "item": "nước ngọt", "quantity": 1}
  ]
}

Ví dụ 5 (xoá toàn bộ):
"Xoá toàn bộ đơn hàng"
-> {
  "clear_all": true
}
Chú ý: nhớ trả về tên sản phẩm đầy đủ, ví dụ: "gạo khang dân" thì phải trả về gạo khang dân, chứ không phải trả về mỗi "gạo"

Lệnh: $text
''';

    try {
      if (mounted) {
        setState(() {
          _status = 'Đang gửi AI xử lý...';
        });
      }
      final response = await http.post(
        Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {'role': 'user', 'content': prompt},
          ],
        }),
      );
      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final String aiContent = jsonResponse['choices'][0]['message']['content'];

        // Parse JSON từ AI
        final Map<String, dynamic> schema = jsonDecode(aiContent);

        // Lấy providers
        final productProvider = context.read<ProductProvider>();
        final customerProvider = context.read<CustomerProvider>();

        // Xử lý khách hàng nếu có
        if (schema['customer'] != null && schema['customer'].toString().isNotEmpty) {
          final customerName = schema['customer'].toString().trim();
          final matchedCustomer = customerProvider.findByName(customerName, threshold: 0.6);
          final exact = matchedCustomer != null &&
              StringUtils.normalize(matchedCustomer.name) == StringUtils.normalize(customerName);

          setState(() {
            _customerId = matchedCustomer?.id;
            _customer = matchedCustomer?.name ?? customerName;
            _customerExactMatched = exact;
            if (matchedCustomer == null) {
              _status = 'Không tìm thấy khách hàng chính xác, đã giữ nguyên tên: $customerName';
            }
          });
        }

        // Xử lý các mục hàng
        if (schema['items'] is List) {
          final List<Map<String, dynamic>> matchedItems = [];

          for (var item in schema['items']) {
            if (item is Map<String, dynamic> && item['item'] != null) {
              final productName = item['item'].toString().trim();
              final matchedProduct = productProvider.findByName(productName, threshold: 0.6);

              // Tạo bản sao của item để tránh thay đổi trực tiếp
              final matchedItem = Map<String, dynamic>.from(item);

              if (matchedProduct != null) {
                // Nếu tìm thấy sản phẩm tương tự, sử dụng thông tin từ database
                matchedItem['item'] = matchedProduct.name;
                final rawPrice = matchedItem['price'];
                final double aiPrice = rawPrice is num ? rawPrice.toDouble() : 0;
                // Nếu AI không nói giá (0 hoặc thiếu) thì lấy giá DB, còn có giá thì dùng giá AI
                matchedItem['price'] = aiPrice > 0 ? aiPrice : matchedProduct.price.toDouble();
                matchedItem['unit'] = matchedProduct.unit;
                matchedItem['productId'] = matchedProduct.id;
                matchedItem['dbExactMatched'] =
                    StringUtils.normalize(matchedProduct.name) == StringUtils.normalize(productName);

                // Thêm thông báo nếu tên không khớp chính xác
                if (matchedProduct.name.toLowerCase() != productName.toLowerCase()) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Đã tìm thấy sản phẩm tương tự: "${matchedProduct.name}"'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } else {
                // Nếu không tìm thấy, giữ nguyên tên sản phẩm đã nhận dạng
                matchedItem['item'] = productName;
                // Nếu AI không có giá hợp lệ thì để 0
                final rawPrice = matchedItem['price'];
                matchedItem['price'] = rawPrice is num ? rawPrice.toDouble() : 0.0;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Không tìm thấy sản phẩm: "$productName"'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }

              matchedItems.add(matchedItem);
            }
          }

          // Cập nhật schema với các mục đã được so khớp
          schema['items'] = matchedItems;
        }

        // Cập nhật đơn hàng
        _updateOrder(schema);

        setState(() {
          _status = 'Đã xử lý đơn hàng';
        });
      } else {
        setState(() {
          _status = 'Lỗi API: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Lỗi: $e';
      });
    }
  }

  // Hàm xoá toàn bộ đơn hàng và thông tin khách hàng
  void _clearOrder() {
    setState(() {
      _orders.clear();
      _customerId = null;
      _customer = '';
      _customerExactMatched = false;
      _paid = 0;
      _paidEdited = false;
      _paidCtrl.clear();
      _status = 'Đã xoá đơn hàng hiện tại';
    });
  }

  double _orderLineTotal(Map<String, dynamic> order) {
    final qty = (order['quantity'] as num?)?.toDouble() ?? 0;
    final price = (order['price'] as num?)?.toDouble() ?? 0;
    return qty * price;
  }

  double get _orderTotal {
    return _orders.fold<double>(0, (sum, o) => sum + _orderLineTotal(o));
  }

  // Hàm phân tích schema và cập nhật state đơn hàng
  void _updateOrder(Map<String, dynamic> schema) {
    // Xử lý thông tin khách hàng nếu có
    if (schema['customer'] != null && schema['customer'].toString().trim().isNotEmpty) {
      _customer = schema['customer'].toString().trim();
    }

    final rawPaid = schema['paidAmount'];
    final paidFromAi = rawPaid is num ? rawPaid.toDouble() : null;
    if (paidFromAi != null && paidFromAi >= 0 && !_paidEdited) {
      _paid = paidFromAi;
      _syncPaidCtrlFromPaid();
    }

    // Xử lý xoá toàn bộ đơn hàng
    if (schema['clear_all'] == true) {
      _clearOrder();
      return;
    }

    // Xử lý danh sách sản phẩm
    if (schema['items'] is List) {
      for (var item in schema['items']) {
        if (item is Map<String, dynamic>) {
          final action = item['action']?.toString() ?? '';
          final itemName = item['item']?.toString() ?? '';
          final quantity = item['quantity'] is num ? (item['quantity'] as num).toDouble() : 0.0;
          final price = item['price'] is num ? (item['price'] as num).toDouble() : 0.0;
          final unit = item['unit']?.toString();
          final productId = item['productId']?.toString();

          if (action == 'add' && itemName.isNotEmpty && quantity > 0) {
            bool exists = false;
            for (var order in _orders) {
              if (order['item'] == itemName) {
                order['quantity'] = ((order['quantity'] as num?)?.toDouble() ?? 0) + quantity;

                if (price > 0) {
                  order['price'] = price;
                }
                if (unit != null && unit.isNotEmpty) {
                  order['unit'] = unit;
                }
                if (productId != null && productId.isNotEmpty) {
                  order['productId'] = productId;
                }
                if (item['dbExactMatched'] != null) {
                  order['dbExactMatched'] = item['dbExactMatched'];
                }
                exists = true;
                break;
              }
            }
            if (!exists) {
              _orders.add({
                'item': itemName,
                'quantity': quantity,
                'price': price,
                if (unit != null && unit.isNotEmpty) 'unit': unit,
                if (productId != null && productId.isNotEmpty) 'productId': productId,
                if (item['dbExactMatched'] != null) 'dbExactMatched': item['dbExactMatched'],
              });
            }
          } else if (action == 'remove' && itemName.isNotEmpty) {
            if (quantity <= 0) {
              // Nếu không chỉ định số lượng hoặc số lượng <= 0 thì xoá hết
              _orders.removeWhere((order) => order['item'] == itemName);
            } else {
              // Giảm số lượng nếu có chỉ định số lượng
              for (var order in _orders) {
                if (order['item'] == itemName) {
                  final newQty = ((order['quantity'] as num?)?.toDouble() ?? 0) - quantity;
                  order['quantity'] = newQty;
                  if (newQty <= 0) {
                    _orders.remove(order);
                  }
                  break;
                }
              }
            }
          }
        }
      }
    }

    // Không set _status ở đây để tránh ghi đè flow trạng thái của AI
    setState(() {
      _syncPaidWithTotalIfNotEdited(_orderTotal);
    });
  }

  Future<void> _saveOrder() async {
    if (_orders.isEmpty) return;

    // Require all items match DB (have productId)
    final missing = _orders.where((o) => (o['productId']?.toString() ?? '').isEmpty).toList();
    if (missing.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn hoặc thêm sản phẩm để khớp DB trước khi lưu')),
      );
      return;
    }

    final products = context.read<ProductProvider>().products;
    final productsById = {for (final p in products) p.id: p};
    final items = <SaleItem>[];
    for (final o in _orders) {
      final pid = o['productId']?.toString();
      final name = o['item']?.toString() ?? '';
      final qty = (o['quantity'] as num?)?.toDouble() ?? 0;
      final unitPrice = (o['price'] as num?)?.toDouble() ?? 0;
      final unit = o['unit']?.toString() ?? '';
      if (pid == null || pid.isEmpty) continue;
      if (qty <= 0) continue;
      final prod = productsById[pid];
      items.add(
        SaleItem(
          productId: pid,
          name: name,
          unitPrice: unitPrice,
          unitCost: (prod?.costPrice ?? 0).toDouble(),
          quantity: qty,
          unit: unit.isEmpty ? (prod?.unit ?? '') : unit,
        ),
      );
    }

    if (items.isEmpty) return;

    double calculatedTotalCost = items.fold(0.0, (p, e) => p + e.totalCost);
    final sale = Sale(
      items: items,
      discount: 0,
      paidAmount: _paid.clamp(0, double.infinity).toDouble(),
      customerId: _customerId,
      customerName: _customer.isEmpty ? null : _customer,
      totalCost: calculatedTotalCost,
    );
    final debtValue = (sale.total - sale.paidAmount).clamp(0.0, double.infinity).toDouble();
    if (debtValue > 0) {
      if ((_customerId ?? '').isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cần chọn/Thêm khách hàng (khớp DB) trước khi ghi nợ')),
        );
        return;
      }
    }

    await context.read<SaleProvider>().add(sale);
    await context.read<ProductProvider>().load();

    if (debtValue > 0) {
      final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
      final details = StringBuffer()
        ..writeln('Bán hàng ngày ${DateFormat('dd/MM/yyyy HH:mm').format(sale.createdAt)}')
        ..writeln('Khách: ${sale.customerName ?? 'Khách lẻ'}')
        ..writeln('Chi tiết:')
        ..writeln(items.map((it) => '- ${it.name} x ${it.quantity} ${it.unit} = ${currency.format(it.total)}').join('\n'))
        ..writeln('Khách trả: ${currency.format(sale.paidAmount)}')
        ..writeln('Còn nợ: ${currency.format(debtValue)}');

      await context.read<DebtProvider>().add(
            Debt(
              type: DebtType.othersOweMe,
              partyId: _customerId ?? 'unknown',
              partyName: _customer.isEmpty ? 'Khách lẻ' : _customer,
              amount: debtValue,
              description: details.toString(),
              sourceType: 'sale',
              sourceId: sale.id,
            ),
          );
    }

    if (!mounted) return;
    setState(() {
      _orders.clear();
      _customerId = null;
      _customer = '';
      _customerExactMatched = false;
      _paid = 0;
      _paidEdited = false;
      _paidCtrl.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu đơn hàng')));
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    final products = context.watch<ProductProvider>().products;
    final productsById = {for (final p in products) p.id: p};

    final total = _orderTotal;
    final debt = (total - _paid).clamp(0, double.infinity).toDouble();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_paidEdited) return;
      final desired = total.clamp(0, double.infinity).toDouble();
      if ((_paid - desired).abs() < 0.0001) {
        _syncPaidCtrlFromPaid();
        return;
      }
      setState(() {
        _paid = desired;
        _syncPaidCtrlFromPaid();
      });
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Đặt hàng bằng giọng nói'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status text
            Text(
              _status,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // Recognized text display
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _recognizedText.isNotEmpty
                    ? _recognizedText
                    : 'Nội dung đã nhận dạng sẽ hiển thị ở đây...',
                style: TextStyle(
                  fontSize: 16,
                  color: _recognizedText.isNotEmpty
                      ? Colors.black87
                      : Colors.grey,
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Hiển thị đơn hàng hiện tại
            Card(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Đơn hàng hiện tại:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 18,
                          color: _customer.isEmpty
                              ? Colors.grey
                              : (_customerExactMatched ? Colors.green : Colors.orange),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final pickedId = await _showCustomerPicker();
                              if (pickedId == null) return;
                              final provider = context.read<CustomerProvider>();
                              final picked = provider.customers.where((c) => c.id == pickedId).toList();
                              if (picked.isEmpty) return;
                              setState(() {
                                _customerId = picked.first.id;
                                _customer = picked.first.name;
                                _customerExactMatched = true;
                              });
                            },
                            child: Text(
                              _customer.isEmpty
                                  ? 'Chọn khách hàng (chạm để chọn)'
                                  : 'Khách hàng: $_customer',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Chọn khách hàng',
                          icon: const Icon(Icons.people_alt_outlined),
                          onPressed: () async {
                            final pickedId = await _showCustomerPicker();
                            if (pickedId == null) return;
                            final provider = context.read<CustomerProvider>();
                            final picked = provider.customers.where((c) => c.id == pickedId).toList();
                            if (picked.isEmpty) return;
                            setState(() {
                              _customerId = picked.first.id;
                              _customer = picked.first.name;
                              _customerExactMatched = true;
                            });
                          },
                        ),
                        IconButton(
                          tooltip: 'Thêm khách hàng mới',
                          icon: Icon(
                            Icons.person_add_alt,
                            color: _customerExactMatched ? Colors.black54 : Colors.orange,
                          ),
                          onPressed: () => _addQuickCustomerDialog(prefillName: _customer),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Thêm sản phẩm'),
                        onPressed: () async {
                          final pickedProductId = await _showProductPicker();
                          if (pickedProductId == null) return;
                          final picked = productsById[pickedProductId] ?? _getProductById(pickedProductId);
                          if (picked == null) return;
                          setState(() {
                            _orders.add({
                              'productId': picked.id,
                              'item': picked.name,
                              'quantity': 1.0,
                              'unit': picked.unit,
                              'price': picked.price.toDouble(),
                              'dbExactMatched': true,
                            });
                            _syncPaidWithTotalIfNotEdited(_orderTotal);
                          });
                        },
                      ),
                    ),
                    if (_orders.isNotEmpty)
                      const SizedBox(height: 8),
                    ..._orders.map((order) {
                      final name = order['item']?.toString() ?? '';
                      final unit = order['unit']?.toString();
                      final lineTotal = _orderLineTotal(order);

                      final pid = order['productId']?.toString();
                      final prod = pid == null ? null : productsById[pid];

                      final isExact = (order['dbExactMatched'] == true) && (pid != null && pid.isNotEmpty);
                      final qtyCtrl = _qtyCtrlFor(order);
                      final priceCtrl = _priceCtrlFor(order);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,

                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        size: 18,
                                        color: pid == null || pid.isEmpty
                                            ? Colors.orange
                                            : (isExact ? Colors.green : Colors.orange),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: InkWell(
                                          onTap: () async {
                                            final pickedProductId = await _showProductPicker();
                                            if (pickedProductId == null) return;
                                            final picked = productsById[pickedProductId] ?? _getProductById(pickedProductId);
                                            if (picked == null) return;
                                            setState(() {
                                              order['productId'] = picked.id;
                                              order['item'] = picked.name;
                                              order['unit'] = picked.unit;
                                              order['price'] = picked.price.toDouble();
                                              order['dbExactMatched'] = true;
                                            });
                                            _qtyCtrlFor(order).text = _formatForInput(
                                              (order['quantity'] as num?)?.toDouble() ?? 0,
                                              maxDecimalDigits: 2,
                                            );
                                            _priceCtrlFor(order).text = _formatForInput(
                                              picked.price.toDouble(),
                                              maxDecimalDigits: 0,
                                            );
                                          },
                                          child: Text(
                                            name,
                                            style: const TextStyle(fontWeight: FontWeight.w600),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Thêm sản phẩm mới',
                                        icon: Icon(
                                          Icons.add_box_outlined,
                                          color: isExact ? Colors.black54 : Colors.orange,
                                        ),
                                        onPressed: () => _addQuickProductDialog(
                                          prefillName: name,
                                          targetOrder: order,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (prod != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Tồn: ${prod.currentStock.toStringAsFixed(prod.currentStock % 1 == 0 ? 0 : 2)} ${prod.unit}',
                                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      SizedBox(
                                        width: 90,
                                        child: TextField(
                                          controller: qtyCtrl,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          inputFormatters: [NumberInputFormatter(maxDecimalDigits: 2)],
                                          decoration: const InputDecoration(
                                            labelText: 'SL',
                                            isDense: true,
                                          ),
                                          onChanged: (v) {
                                            final val = NumberInputFormatter.tryParse(v);
                                            if (val == null || val < 0) return;
                                            setState(() {
                                              order['quantity'] = val;
                                              _syncPaidWithTotalIfNotEdited(_orderTotal);
                                            });
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(unit ?? ''),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: TextField(
                                          controller: priceCtrl,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
                                          decoration: const InputDecoration(
                                            labelText: 'Đơn giá',
                                            isDense: true,
                                          ),
                                          onChanged: (v) {
                                            final val = NumberInputFormatter.tryParse(v);
                                            if (val == null || val < 0) return;
                                            setState(() {
                                              order['price'] = val;
                                              _syncPaidWithTotalIfNotEdited(_orderTotal);
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Thành tiền: ${currency.format(lineTotal)}',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),

                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              tooltip: 'Xóa dòng',
                              onPressed: () {
                                setState(() {
                                  _orders.remove(order);
                                  _syncPaidWithTotalIfNotEdited(_orderTotal);
                                });
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                    if (_orders.isNotEmpty) ...[
                      const Divider(height: 16),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Tổng tiền:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Text(
                            currency.format(_orderTotal),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Expanded(child: Text('Khách trả:')),
                          SizedBox(
                            width: 160,
                            child: TextField(
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
                              decoration: const InputDecoration(
                                hintText: '0',
                                isDense: true,
                              ),
                              onChanged: (v) {
                                final val = NumberInputFormatter.tryParse(v) ?? 0;
                                setState(() {
                                  _paidEdited = true;
                                  _paid = val.clamp(0, total).toDouble();
                                  _syncPaidCtrlFromPaid();
                                });
                              },
                              controller: _paidCtrl,
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
                              _syncPaidCtrlFromPaid();
                            });
                          },
                          child: const Text('Khách nợ tất'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saveOrder,
                          icon: const Icon(Icons.save),
                          label: Text(
                            debt > 0 ? 'Lưu + Ghi nợ (${currency.format(debt)})' : 'Lưu hóa đơn',
                          ),
                        ),
                      ),
                    ],
                    if (_orders.isEmpty && _customer.isEmpty) const Text('Chưa có đơn hàng'),
                    if (_orders.isNotEmpty || _customer.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            height: 44,
                            child: OutlinedButton.icon(
                              onPressed: _clearOrder,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: const BorderSide(color: Colors.redAccent),
                              ),
                              icon: const Icon(Icons.delete_outline, size: 20),
                              label: const Text('Xoá đơn hàng'),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Example command
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Ví dụ:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text('• Mua 2 chai nước ngọt giá 15.000 đồng'),
                    Text('• Thêm 1 ký thịt heo giá 120.000 đồng'),
                    Text('• Xoá 1 nước ngọt'),
                    Text('• Đặt hàng cho khách Nguyễn Văn A: 2 nước ngọt 15000, 1 bánh mì 20000'),
                    Text('• Xoá toàn bộ đơn hàng'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleListening,
        backgroundColor: _isListening ? Colors.red : Theme.of(context).primaryColor,
        child: Icon(
          _isListening ? Icons.mic_off : Icons.mic,
          color: Colors.white,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _speech.stop();
    _paidCtrl.dispose();
    for (final c in _qtyCtrls.values) {
      c.dispose();
    }
    for (final c in _priceCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }
}