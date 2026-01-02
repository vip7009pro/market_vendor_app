import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../services/database_service.dart';
import 'vietqr_bank_account_form_screen.dart';

class VietQrBankAccountsScreen extends StatefulWidget {
  const VietQrBankAccountsScreen({super.key});

  @override
  State<VietQrBankAccountsScreen> createState() => _VietQrBankAccountsScreenState();
}

class _VietQrBankAccountsScreenState extends State<VietQrBankAccountsScreen> {
  final _uuid = const Uuid();

  Future<void> _openCreate() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VietQrBankAccountFormScreen(
          initial: {
            'id': _uuid.v4(),
            'isDefault': 0,
          },
          isEdit: false,
        ),
      ),
    );
    if (created == true) {
      setState(() {});
    }
  }

  Future<void> _openEdit(Map<String, dynamic> row) async {
    final edited = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VietQrBankAccountFormScreen(
          initial: Map<String, dynamic>.from(row),
          isEdit: true,
        ),
      ),
    );
    if (edited == true) {
      setState(() {});
    }
  }

  Future<void> _setDefault(String id) async {
    await DatabaseService.instance.setDefaultVietQrBankAccount(id);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa ngân hàng'),
        content: const Text('Bạn có chắc muốn xóa tài khoản ngân hàng này?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (ok != true) return;
    await DatabaseService.instance.deleteVietQrBankAccount(id);
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ngân hàng VietQR'),
        actions: [
          IconButton(
            tooltip: 'Thêm',
            icon: const Icon(Icons.add),
            onPressed: _openCreate,
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: DatabaseService.instance.getVietQrBankAccounts(),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snap.data ?? const <Map<String, dynamic>>[];
          if (rows.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Chưa có ngân hàng nào. Nhấn + để thêm.'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _openCreate,
                      icon: const Icon(Icons.add),
                      label: const Text('Thêm ngân hàng'),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemBuilder: (context, i) {
              final r = rows[i];
              final id = (r['id']?.toString() ?? '').trim();
              final isDefault = (r['isDefault'] as int?) == 1;
              final logo = (r['logo']?.toString() ?? '').trim();
              final bankName = (r['shortName']?.toString() ?? r['short_name']?.toString() ?? r['name']?.toString() ?? '').trim();
              final accountNo = (r['accountNo']?.toString() ?? '').trim();
              final accountName = (r['accountName']?.toString() ?? '').trim();

              return ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: logo.isEmpty
                      ? Container(
                          width: 44,
                          height: 44,
                          color: Colors.grey.withAlpha(25),
                          child: const Icon(Icons.account_balance_outlined),
                        )
                      : Image.network(
                          logo,
                          width: 44,
                          height: 44,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Container(
                            width: 44,
                            height: 44,
                            color: Colors.grey.withAlpha(25),
                            child: const Icon(Icons.account_balance_outlined),
                          ),
                        ),
                ),
                title: Text(
                  bankName.isEmpty ? 'Ngân hàng' : bankName,
                  style: TextStyle(fontWeight: isDefault ? FontWeight.w800 : FontWeight.w700),
                ),
                subtitle: Text('$accountNo\n$accountName'),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'default') {
                      await _setDefault(id);
                    } else if (v == 'edit') {
                      await _openEdit(r);
                    } else if (v == 'delete') {
                      await _delete(id);
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'default',
                      enabled: !isDefault,
                      child: Text(isDefault ? 'Đang mặc định' : 'Đặt mặc định'),
                    ),
                    const PopupMenuItem(value: 'edit', child: Text('Sửa')),
                    const PopupMenuItem(value: 'delete', child: Text('Xóa')),
                  ],
                ),
                onTap: () => _openEdit(r),
              );
            },
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemCount: rows.length,
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreate,
        child: const Icon(Icons.add),
      ),
    );
  }
}
