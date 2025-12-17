import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'dart:convert';
import '../providers/product_provider.dart';
import '../providers/customer_provider.dart';

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
  String _customer = ''; // Tên khách hàng

  // Hàm thêm nhiều sản phẩm vào đơn hàng
  void _addMultipleItems(List<dynamic> items) {
    for (var item in items) {
      if (item is Map<String, dynamic> && 
          item.containsKey('item') && 
          item.containsKey('quantity') && 
          item['quantity'] > 0) {
        
        bool exists = false;
        for (var order in _orders) {
          if (order['item'] == item['item']) {
            order['quantity'] += item['quantity'];
            exists = true;
            break;
          }
        }
        if (!exists) {
          _orders.add({
            'item': item['item'],
            'quantity': item['quantity'],
            'price': item['price'] ?? 0,
          });
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    bool available = await _speech.initialize(
      onStatus: (status) {
        setState(() {
          _status = 'Trạng thái: $status';
        });
      },
      onError: (error) {
        setState(() {
          _status = 'Lỗi: $error';
          _isListening = false;
        });
      },
    );

    if (!available) {
      setState(() {
        _status = 'Không thể khởi tạo nhận dạng giọng nói';
      });
    }
  }

  void _toggleListening() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    } else {
      bool available = await _speech.initialize();
      if (available) {
        setState(() {
          _isListening = true;
          _status = 'Đang nghe...';
          _recognizedText = '';
        });
        
        await _speech.listen(
          onResult: (result) {
            setState(() {
              _recognizedText = result.recognizedWords;
              if (result.finalResult) {
                _isListening = false;
                _status = 'Đã nhận dạng xong, đang gửi đến AI...';
                _processWithAI(_recognizedText); // Tích hợp gửi đến OpenRouter
              }
            });
          },
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 5),
          listenOptions: stt.SpeechListenOptions(partialResults: true),
          localeId: 'vi_VN', // Set to Vietnamese language
        );
      } else {
        setState(() {
          _status = 'Không thể bắt đầu nhận dạng giọng nói';
        });
      }
    }
  }

  // Hàm gửi đến OpenRouter AI và xử lý kết quả
  Future<void> _processWithAI(String text) async {
    if (text.isEmpty) return;

    //const apiKey = String.fromEnvironment('OPENROUTER_API_KEY');
    
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
  "items": [
    {"action": "add", "item": "nước ngọt", "quantity": 2, "price": 15000},
    {"action": "add", "item": "bánh mì", "quantity": 1, "price": 20000}
  ]
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
          
          setState(() {
            _customer = matchedCustomer?.name ?? customerName;
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
      _customer = '';
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
                // Nếu có giá > 0 thì cập nhật giá (ưu tiên giá vừa parse)
                if (price > 0) {
                  order['price'] = price;
                }
                if (unit != null && unit.isNotEmpty) {
                  order['unit'] = unit;
                }
                if (productId != null && productId.isNotEmpty) {
                  order['productId'] = productId;
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
    
    // Cập nhật UI
    setState(() {
      _status = 'Đã cập nhật đơn hàng';
    });
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Đặt hàng bằng giọng nói'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
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
                    if (_customer.isNotEmpty) Text('Khách hàng: $_customer'),
                    if (_orders.isNotEmpty)
                      const SizedBox(height: 8),
                    ..._orders.map((order) {
                      final name = order['item']?.toString() ?? '';
                      final qty = (order['quantity'] as num?)?.toDouble() ?? 0;
                      final price = (order['price'] as num?)?.toDouble() ?? 0;
                      final unit = order['unit']?.toString();
                      final lineTotal = _orderLineTotal(order);

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
                                  Text(
                                    name,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'SL: ${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2)}${unit != null && unit.isNotEmpty ? ' $unit' : ''}  •  Đơn giá: ${currency.format(price)}',
                                    style: const TextStyle(color: Colors.black54),
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
                    ],
                    if (_orders.isEmpty && _customer.isEmpty) const Text('Chưa có đơn hàng'),
                    if (_orders.isNotEmpty || _customer.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0),
                        child: ElevatedButton.icon(
                          onPressed: _clearOrder,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red[50],
                            foregroundColor: Colors.red,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(color: Colors.red.shade200),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.delete_outline, size: 20),
                          label: const Text('Xoá đơn hàng'),
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
    super.dispose();
  }
}