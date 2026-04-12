import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ai_provider_service.dart';

/// Result returned by [VoiceProductInputDialog].
/// Contains parsed product fields from AI.
class VoiceProductResult {
  final String name;
  final double price;
  final double costPrice;
  final String unit;
  final double currentStock;
  final String barcode;

  const VoiceProductResult({
    required this.name,
    required this.price,
    required this.costPrice,
    required this.unit,
    required this.currentStock,
    required this.barcode,
  });
}

/// A dialog that lets users dictate product information via voice,
/// sends it to AI for parsing, and returns structured product data.
///
/// Usage:
/// ```dart
/// final result = await VoiceProductInputDialog.show(context);
/// if (result != null) {
///   nameCtrl.text = result.name;
///   priceCtrl.text = result.price.toStringAsFixed(0);
///   // ...
/// }
/// ```
class VoiceProductInputDialog extends StatefulWidget {
  const VoiceProductInputDialog({super.key});

  /// Show the dialog and return parsed product data, or null if cancelled.
  static Future<VoiceProductResult?> show(BuildContext context) {
    return showDialog<VoiceProductResult>(
      context: context,
      builder: (_) => const VoiceProductInputDialog(),
    );
  }

  @override
  State<VoiceProductInputDialog> createState() =>
      _VoiceProductInputDialogState();
}

class _VoiceProductInputDialogState extends State<VoiceProductInputDialog> {
  static const _prefAutoSend = 'voice_product_auto_send';

  final _textCtrl = TextEditingController();
  final _stt = stt.SpeechToText();

  bool _isListening = false;
  bool _autoSend = true;
  bool _processing = false;
  String? _errorMsg;
  bool _sttAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadAutoSendPref();
    _initStt();
  }

  Future<void> _loadAutoSendPref() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _autoSend = prefs.getBool(_prefAutoSend) ?? true;
    });
  }

  Future<void> _saveAutoSendPref(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutoSend, v);
  }

  Future<void> _initStt() async {
    final available = await _stt.initialize(
      onError: (e) {
        debugPrint('[VoiceProductInput] STT error: ${e.errorMsg}');
        if (!mounted) return;
        setState(() {
          _isListening = false;
        });
      },
      onStatus: (status) {
        debugPrint('[VoiceProductInput] STT status: $status');
        if (status == 'done' || status == 'notListening') {
          if (!mounted) return;
          setState(() => _isListening = false);
          // Auto-send if enabled and there's text
          if (_autoSend && _textCtrl.text.trim().isNotEmpty && !_processing) {
            _processWithAI();
          }
        }
      },
    );
    if (!mounted) return;
    setState(() => _sttAvailable = available);
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _stt.stop();
      setState(() => _isListening = false);
      return;
    }

    if (!_sttAvailable) {
      setState(() => _errorMsg = 'Không thể khởi tạo nhận dạng giọng nói');
      return;
    }

    setState(() {
      _errorMsg = null;
      _isListening = true;
    });

    await _stt.listen(
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _textCtrl.text = result.recognizedWords;
          _textCtrl.selection = TextSelection.collapsed(
            offset: _textCtrl.text.length,
          );
        });
      },
      localeId: 'vi_VN',
      listenOptions: stt.SpeechListenOptions(
        listenMode: stt.ListenMode.dictation,
        cancelOnError: true,
        partialResults: true,
      ),
    );
  }

  Future<void> _processWithAI() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      setState(() => _errorMsg = 'Chưa có nội dung để xử lý');
      return;
    }

    setState(() {
      _processing = true;
      _errorMsg = null;
    });

    try {
      final aiService = AiProviderService.instance;
      await aiService.load();

      if (aiService.activeApiKey.trim().isEmpty) {
        setState(() {
          _processing = false;
          _errorMsg = 'Thiếu API key. Vào Cài đặt > Chọn AI để nhập key.';
        });
        return;
      }

      const prompt = '''
Phân tích mô tả sản phẩm từ giọng nói tiếng Việt và trả về đúng một JSON object theo schema sau (không thêm text thừa):
{
  "name": "tên sản phẩm (bắt buộc)",
  "price": giá bán (số, mặc định 0),
  "costPrice": giá vốn (số, mặc định 0),
  "unit": "đơn vị (mặc định: cái)",
  "currentStock": tồn hiện tại (số, mặc định 0),
  "barcode": "mã vạch (mặc định rỗng)"
}

Ví dụ 1:
"gạo khang dân giá bán 20000 giá vốn 18000 đơn vị kg"
-> {"name": "gạo khang dân", "price": 20000, "costPrice": 18000, "unit": "kg", "currentStock": 0, "barcode": ""}

Ví dụ 2:
"nước ngọt pepsi giá 15000 vốn 12000"
-> {"name": "nước ngọt pepsi", "price": 15000, "costPrice": 12000, "unit": "cái", "currentStock": 0, "barcode": ""}

Ví dụ 3:
"bánh mì 10 nghìn vốn 7 nghìn tồn 50 cái"
-> {"name": "bánh mì", "price": 10000, "costPrice": 7000, "unit": "cái", "currentStock": 50, "barcode": ""}

Chú ý:
- "nghìn" = 1000, "triệu" = 1000000
- Nếu không nói đơn vị thì mặc định "cái"
- Nếu không nói giá vốn thì mặc định 0
- Nếu không nói tồn thì mặc định 0
- Trả về tên sản phẩm đầy đủ, không rút gọn

''';

      final fullPrompt = '$prompt\nMô tả: $text';
      final aiContent = await aiService.sendChatCompletion(fullPrompt);

      debugPrint('[VoiceProductInput] AI response: $aiContent');

      // Try parsing JSON
      Map<String, dynamic> parsed;
      try {
        parsed = jsonDecode(aiContent);
      } catch (_) {
        // Try extracting JSON from markdown code blocks
        final jsonMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(aiContent);
        if (jsonMatch != null) {
          parsed = jsonDecode(jsonMatch.group(1)!.trim());
        } else {
          throw FormatException('AI trả về dữ liệu không hợp lệ');
        }
      }

      final name = (parsed['name']?.toString() ?? '').trim();
      if (name.isEmpty) {
        setState(() {
          _processing = false;
          _errorMsg = 'AI không nhận diện được tên sản phẩm';
        });
        return;
      }

      final result = VoiceProductResult(
        name: name,
        price: (parsed['price'] as num?)?.toDouble() ?? 0,
        costPrice: (parsed['costPrice'] as num?)?.toDouble() ?? 0,
        unit: (parsed['unit']?.toString() ?? 'cái').trim(),
        currentStock: (parsed['currentStock'] as num?)?.toDouble() ?? 0,
        barcode: (parsed['barcode']?.toString() ?? '').trim(),
      );

      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      debugPrint('[VoiceProductInput] Error: $e');
      if (!mounted) return;
      setState(() {
        _processing = false;
        _errorMsg = 'Lỗi: $e';
      });
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _stt.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.mic, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('Thêm SP bằng giọng nói')),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Text field showing speech recognition result
            TextField(
              controller: _textCtrl,
              maxLines: 3,
              minLines: 2,
              decoration: InputDecoration(
                hintText: 'Bấm mic và nói mô tả sản phẩm...\nVD: "gạo khang dân giá 20 nghìn vốn 18 nghìn đơn vị kg"',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey[500]),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
            const SizedBox(height: 12),

            // Controls row
            Row(
              children: [
                // Record button
                Material(
                  color: _isListening ? Colors.red : theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: _processing ? null : _toggleListening,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isListening ? Icons.stop : Icons.mic,
                            color: _isListening ? Colors.white : theme.colorScheme.onPrimaryContainer,
                            size: 20,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isListening ? 'Dừng' : 'Thu âm',
                            style: TextStyle(
                              color: _isListening ? Colors.white : theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                // Auto/Manual switch
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Auto',
                      style: TextStyle(
                        fontSize: 13,
                        color: _autoSend ? theme.colorScheme.primary : Colors.grey,
                        fontWeight: _autoSend ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    SizedBox(
                      height: 32,
                      child: Switch(
                        value: _autoSend,
                        onChanged: (v) {
                          setState(() => _autoSend = v);
                          _saveAutoSendPref(v);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Listening indicator
            if (_isListening) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.red[400],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Đang nghe...',
                    style: TextStyle(color: Colors.red[400], fontSize: 13),
                  ),
                ],
              ),
            ],

            // Processing indicator
            if (_processing) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Đang gửi AI xử lý...',
                      style: TextStyle(color: theme.colorScheme.primary, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],

            // Error message
            if (_errorMsg != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMsg!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _processing ? null : () => Navigator.pop(context),
          child: const Text('Huỷ'),
        ),
        FilledButton.icon(
          onPressed: _processing || _textCtrl.text.trim().isEmpty ? null : _processWithAI,
          icon: const Icon(Icons.smart_toy_outlined, size: 18),
          label: const Text('Xử lý AI'),
        ),
      ],
    );
  }
}
