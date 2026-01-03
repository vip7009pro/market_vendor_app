import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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

  Future<void> _pickBankFromBottomSheet(List<Map<String, dynamic>> banks) async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final searchCtrl = TextEditingController();
        return StatefulBuilder(
          builder: (ctx, setStateSheet) {
            final q = searchCtrl.text.trim().toLowerCase();
            final filtered = q.isEmpty
                ? banks
                : banks.where((b) {
                    final name = (b['name']?.toString() ?? '').toLowerCase();
                    final shortName = (b['shortName']?.toString() ?? b['short_name']?.toString() ?? '').toLowerCase();
                    final code = (b['code']?.toString() ?? '').toLowerCase();
                    final bin = (b['bin']?.toString() ?? '').toLowerCase();
                    return name.contains(q) || shortName.contains(q) || code.contains(q) || bin.contains(q);
                  }).toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 12,
                  top: 8,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tìm ngân hàng',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (_) => setStateSheet(() {}),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final b = filtered[i];
                          final logo = (b['logo']?.toString() ?? '').trim();
                          final shortName = (b['shortName']?.toString() ?? b['short_name']?.toString() ?? '').trim();
                          final name = (b['name']?.toString() ?? '').trim();
                          final code = (b['code']?.toString() ?? '').trim();
                          final bin = (b['bin']?.toString() ?? '').trim();
                          final title = shortName.isNotEmpty ? shortName : name;

                          return ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                width: 46,
                                height: 46,
                                color: Colors.grey.withAlpha(18),
                                alignment: Alignment.center,
                                child: logo.isEmpty
                                    ? const Icon(Icons.account_balance_outlined)
                                    : Image.network(
                                        logo,
                                        width: 34,
                                        height: 34,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) => const Icon(Icons.account_balance_outlined),
                                      ),
                              ),
                            ),
                            title: Text(title.isEmpty ? 'Ngân hàng' : title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('$code - $bin', maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () => Navigator.of(ctx).pop(b),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (picked == null) return;
    setState(() {
      _selectedBank = picked;
    });
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

          final selectedTitle = (() {
            final b = _selectedBank;
            if (b == null) return '';
            final shortName = (b['shortName']?.toString() ?? b['short_name']?.toString() ?? '').trim();
            final name = (b['name']?.toString() ?? '').trim();
            return (shortName.isNotEmpty ? shortName : name).trim();
          })();
          final selectedSub = (() {
            final b = _selectedBank;
            if (b == null) return '';
            final code = (b['code']?.toString() ?? '').trim();
            final bin = (b['bin']?.toString() ?? '').trim();
            return '$code - $bin'.trim();
          })();
          final selectedLogo = (() {
            final b = _selectedBank;
            if (b == null) return '';
            return (b['logo']?.toString() ?? '').trim();
          })();

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              InkWell(
                onTap: () => _pickBankFromBottomSheet(banks),
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Ngân hàng',
                    border: OutlineInputBorder(),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 46,
                          height: 46,
                          color: Colors.grey.withAlpha(18),
                          alignment: Alignment.center,
                          child: selectedLogo.isEmpty
                              ? const Icon(Icons.account_balance_outlined)
                              : Image.network(
                                  selectedLogo,
                                  width: 34,
                                  height: 34,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.account_balance_outlined),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selectedTitle.isEmpty ? 'Chọn ngân hàng' : selectedTitle,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (selectedSub.isNotEmpty)
                              Text(
                                selectedSub,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down),
                    ],
                  ),
                ),
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
