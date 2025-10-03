import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StoreInfoScreen extends StatefulWidget {
  const StoreInfoScreen({super.key});

  @override
  State<StoreInfoScreen> createState() => _StoreInfoScreenState();
}

class _StoreInfoScreenState extends State<StoreInfoScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStoreInfo();
  }

  Future<void> _loadStoreInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString('store_name') ?? '';
      _addressController.text = prefs.getString('store_address') ?? '';
      _phoneController.text = prefs.getString('store_phone') ?? '';
    });
  }

  Future<void> _saveStoreInfo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('store_name', _nameController.text.trim());
    await prefs.setString('store_address', _addressController.text.trim());
    await prefs.setString('store_phone', _phoneController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu thông tin cửa hàng')),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thông tin cửa hàng'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Tên cửa hàng',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: 'Địa chỉ',
                border: OutlineInputBorder(),
              ),
              maxLines: null,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Số điện thoại',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.save),
              label: const Text('Lưu thông tin'),
              onPressed: _saveStoreInfo,
            ),
          ],
        ),
      ),
    );
  }
}
