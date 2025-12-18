import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/database_service.dart';

class StoreInfoScreen extends StatefulWidget {
  const StoreInfoScreen({super.key});

  @override
  State<StoreInfoScreen> createState() => _StoreInfoScreenState();
}

class _StoreInfoScreenState extends State<StoreInfoScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _taxCodeController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _bankNameController = TextEditingController();
  final TextEditingController _bankAccountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStoreInfo();
  }

  Future<void> _loadStoreInfo() async {
    final row = await DatabaseService.instance.getStoreInfo();
    if (row != null) {
      if (!mounted) return;
      setState(() {
        _nameController.text = (row['name'] as String?) ?? '';
        _addressController.text = (row['address'] as String?) ?? '';
        _phoneController.text = (row['phone'] as String?) ?? '';
        _taxCodeController.text = (row['taxCode'] as String?) ?? '';
        _emailController.text = (row['email'] as String?) ?? '';
        _bankNameController.text = (row['bankName'] as String?) ?? '';
        _bankAccountController.text = (row['bankAccount'] as String?) ?? '';
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('store_name') ?? '';
    final address = prefs.getString('store_address') ?? '';
    final phone = prefs.getString('store_phone') ?? '';
    final taxCode = prefs.getString('store_tax_code') ?? '';
    final email = prefs.getString('store_email') ?? '';
    final bankName = prefs.getString('store_bank_name') ?? '';
    final bankAccount = prefs.getString('store_bank_account') ?? '';

    if (name.trim().isNotEmpty || address.trim().isNotEmpty || phone.trim().isNotEmpty) {
      await DatabaseService.instance.upsertStoreInfo(
        name: name.trim(),
        address: address.trim(),
        phone: phone.trim(),
        taxCode: taxCode.trim().isEmpty ? null : taxCode.trim(),
        email: email.trim().isEmpty ? null : email.trim(),
        bankName: bankName.trim().isEmpty ? null : bankName.trim(),
        bankAccount: bankAccount.trim().isEmpty ? null : bankAccount.trim(),
      );
    }

    if (!mounted) return;
    setState(() {
      _nameController.text = name;
      _addressController.text = address;
      _phoneController.text = phone;
      _taxCodeController.text = taxCode;
      _emailController.text = email;
      _bankNameController.text = bankName;
      _bankAccountController.text = bankAccount;
    });
  }

  Future<void> _saveStoreInfo() async {
    await DatabaseService.instance.upsertStoreInfo(
      name: _nameController.text.trim(),
      address: _addressController.text.trim(),
      phone: _phoneController.text.trim(),
      taxCode: _taxCodeController.text.trim().isEmpty ? null : _taxCodeController.text.trim(),
      email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
      bankName: _bankNameController.text.trim().isEmpty ? null : _bankNameController.text.trim(),
      bankAccount: _bankAccountController.text.trim().isEmpty ? null : _bankAccountController.text.trim(),
    );
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
    _taxCodeController.dispose();
    _emailController.dispose();
    _bankNameController.dispose();
    _bankAccountController.dispose();
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
            const SizedBox(height: 16),
            TextField(
              controller: _taxCodeController,
              decoration: const InputDecoration(
                labelText: 'Mã số thuế',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _bankNameController,
              decoration: const InputDecoration(
                labelText: 'Ngân hàng',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _bankAccountController,
              decoration: const InputDecoration(
                labelText: 'Số tài khoản',
                border: OutlineInputBorder(),
              ),
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
