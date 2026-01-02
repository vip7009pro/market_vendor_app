import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:dropdown_search/dropdown_search.dart';

import '../services/database_service.dart';

class VietQrBankAccountFormScreen extends StatefulWidget {
  final Map<String, dynamic> initial;
  final bool isEdit;

  const VietQrBankAccountFormScreen({
    super.key,
    required this.initial,
    required this.isEdit,
  });

  @override
  State<VietQrBankAccountFormScreen> createState() => _VietQrBankAccountFormScreenState();
}

class _VietQrBankAccountFormScreenState extends State<VietQrBankAccountFormScreen> {
  final _accountNoCtrl = TextEditingController();
  final _accountNameCtrl = TextEditingController();
  bool _isDefault = false;

  Map<String, dynamic>? _selectedBank;
  Future<List<Map<String, dynamic>>>? _banksFuture;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _accountNoCtrl.text = (init['accountNo']?.toString() ?? '').trim();
    _accountNameCtrl.text = (init['accountName']?.toString() ?? '').trim();
    _isDefault = (init['isDefault'] as int?) == 1;

    _banksFuture = _loadBanks();
  }

  @override
  void dispose() {
    _accountNoCtrl.dispose();
    _accountNameCtrl.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadBanks() async {
    final uri = Uri.parse('https://api.vietqr.io/v2/banks');
    final res = await http.get(uri);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map) {
      throw Exception('Invalid response');
    }
    final code = decoded['code']?.toString();
    if (code != '00') {
      throw Exception(decoded['desc']?.toString() ?? 'Get banks failed');
    }
    final data = decoded['data'];
    if (data is! List) return const <Map<String, dynamic>>[];

    final banks = <Map<String, dynamic>>[];
    for (final e in data) {
      if (e is Map) {
        banks.add(Map<String, dynamic>.from(e.cast<String, dynamic>()));
      }
    }

    // Try preselect based on existing record.
    final init = widget.initial;
    final initBin = (init['bin']?.toString() ?? '').trim();
    final initCode = (init['code']?.toString() ?? '').trim();
    final initBankApiId = init['bankApiId'];

    Map<String, dynamic>? match;
    if (initBankApiId != null) {
      match = banks.cast<Map<String, dynamic>?>().firstWhere(
            (b) => b?['id'] == initBankApiId,
            orElse: () => null,
          );
    }
    match ??= banks.cast<Map<String, dynamic>?>().firstWhere(
          (b) => (b?['bin']?.toString() ?? '').trim() == initBin && initBin.isNotEmpty,
          orElse: () => null,
        );
    match ??= banks.cast<Map<String, dynamic>?>().firstWhere(
          (b) => (b?['code']?.toString() ?? '').trim() == initCode && initCode.isNotEmpty,
          orElse: () => null,
        );

    _selectedBank = match;
    return banks;
  }

  Future<void> _save() async {
    final bank = _selectedBank;
    if (bank == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng chọn ngân hàng')));
      return;
    }
    final accountNo = _accountNoCtrl.text.trim();
    final accountName = _accountNameCtrl.text.trim();
    if (accountNo.isEmpty || accountName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập số tài khoản và tên tài khoản')));
      return;
    }

    final row = <String, dynamic>{
      ...widget.initial,
      'bankApiId': bank['id'],
      'name': bank['name'],
      'code': bank['code'],
      'bin': bank['bin'],
      'shortName': bank['shortName'],
      'short_name': bank['short_name'],
      'logo': bank['logo'],
      'transferSupported': bank['transferSupported'],
      'lookupSupported': bank['lookupSupported'],
      'support': bank['support'],
      'isTransfer': bank['isTransfer'],
      'swift_code': bank['swift_code'],
      'accountNo': accountNo,
      'accountName': accountName,
      'isDefault': _isDefault ? 1 : 0,
    };

    try {
      await DatabaseService.instance.upsertVietQrBankAccount(row);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi lưu: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? 'Sửa ngân hàng' : 'Thêm ngân hàng'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Lưu'),
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _banksFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Không tải được danh sách ngân hàng: ${snap.error}'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        setState(() {
                          _banksFuture = _loadBanks();
                        });
                      },
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              ),
            );
          }

          final banks = snap.data ?? const <Map<String, dynamic>>[];

          String displayBank(Map<String, dynamic> b) {
            final shortName = (b['shortName']?.toString() ?? b['short_name']?.toString() ?? '').trim();
            final code = (b['code']?.toString() ?? '').trim();
            final bin = (b['bin']?.toString() ?? '').trim();
            if (shortName.isNotEmpty) return '$shortName ($code - $bin)';
            final name = (b['name']?.toString() ?? '').trim();
            return '$name ($code - $bin)';
          }

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              DropdownSearch<Map<String, dynamic>>(
                items: banks,
                selectedItem: _selectedBank,
                itemAsString: (b) => displayBank(b),
                popupProps: const PopupProps.menu(
                  showSearchBox: true,
                  searchFieldProps: TextFieldProps(
                    decoration: InputDecoration(
                      labelText: 'Tìm ngân hàng',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                dropdownDecoratorProps: const DropDownDecoratorProps(
                  dropdownSearchDecoration: InputDecoration(
                    labelText: 'Ngân hàng',
                    border: OutlineInputBorder(),
                  ),
                ),
                onChanged: (v) {
                  setState(() {
                    _selectedBank = v;
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _accountNoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Số tài khoản',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _accountNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tên tài khoản',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: _isDefault,
                title: const Text('Đặt làm mặc định'),
                onChanged: (v) {
                  setState(() {
                    _isDefault = v;
                  });
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save),
                  label: const Text('Lưu'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
