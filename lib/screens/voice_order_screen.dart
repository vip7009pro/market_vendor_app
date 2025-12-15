import 'package:flutter/material.dart';

class VoiceOrderScreen extends StatefulWidget {
  const VoiceOrderScreen({Key? key}) : super(key: key);

  @override
  State<VoiceOrderScreen> createState() => _VoiceOrderScreenState();
}

class _VoiceOrderScreenState extends State<VoiceOrderScreen> {
  bool _isListening = false;
  String _status = 'Nhấn vào nút micrô để bắt đầu nhận dạng giọng nói';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Đặt hàng bằng giọng nói'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated microphone icon
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _isListening ? Colors.red.withOpacity(0.1) : Colors.grey[200],
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isListening ? Icons.mic : Icons.mic_none,
                size: 64,
                color: _isListening ? Colors.red : Colors.grey,
              ),
            ),
            const SizedBox(height: 32),
            // Status text
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Text(
                _status,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 24),
            // Instructions
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32.0),
              child: Text(
                'Ví dụ: "Mua 2 chai nước ngọt giá 15.000 đồng cho khách hàng Nguyễn Văn A"',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleListening,
        child: Icon(_isListening ? Icons.stop : Icons.mic),
      ),
    );
  }

  void _toggleListening() {
    setState(() {
      _isListening = !_isListening;
      _status = _isListening 
          ? 'Đang nghe...' 
          : 'Nhấn vào nút micrô để bắt đầu nhận dạng giọng nói';
    });
    
    // TODO: Add speech recognition logic here
  }
}
