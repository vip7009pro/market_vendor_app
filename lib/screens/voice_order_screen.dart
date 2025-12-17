import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

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
                _status = 'Đã nhận dạng xong';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Đặt hàng bằng giọng nói'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Status text
            Text(
              _status,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            
            // Recognized text display
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
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
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Example command
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    Text('• Xoá sản phẩm nước ngọt'),
                    Text('• Đặt hàng cho khách Nguyễn Văn A'),
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