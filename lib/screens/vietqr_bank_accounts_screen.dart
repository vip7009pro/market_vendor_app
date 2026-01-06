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

  String _vietQrTransferUrl({
    required String bankId,
    required String accountNo,
    required String accountName,
    String template = 'compact2',
  }) {
    final accName = Uri.encodeComponent(accountName);
    return 'https://img.vietqr.io/image/$bankId-$accountNo-$template.png?accountName=$accName';
  }

  Future<void> _showTransferQr(Map<String, dynamic> row) async {
    final bin = (row['bin']?.toString() ?? '').trim();
    final code = (row['code']?.toString() ?? '').trim();
    final bankId = bin.isNotEmpty ? bin : code;
    final logo = (row['logo']?.toString() ?? '').trim();
    final bankName = (row['shortName']?.toString() ?? row['short_name']?.toString() ?? row['name']?.toString() ?? '').trim();
    final accountNo = (row['accountNo']?.toString() ?? '').trim();
    final accountName = (row['accountName']?.toString() ?? '').trim();

    if (bankId.isEmpty || accountNo.isEmpty || accountName.isEmpty) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Thiếu thông tin ngân hàng'),
          content: const Text('Vui lòng kiểm tra BIN/Mã ngân hàng, số tài khoản và tên tài khoản.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
          ],
        ),
      );
      return;
    }

    final url = _vietQrTransferUrl(
      bankId: bankId,
      accountNo: accountNo,
      accountName: accountName,
    );

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('QR chuyển khoản'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (logo.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Image.network(
                  logo,
                  width: 46,
                  height: 46,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            Text(bankName.isEmpty ? 'Ngân hàng' : bankName),
            const SizedBox(height: 6),
            Text(accountNo, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(accountName, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                url,
                width: 260,
                height: 260,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('Không tải được QR. Vui lòng kiểm tra mạng.'),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
        ],
      ),
    );
  }

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
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 56,
                    height: 56,
                    color: Colors.grey.withAlpha(18),
                    alignment: Alignment.center,
                    child: logo.isEmpty
                        ? const Icon(Icons.account_balance_outlined)
                        : Image.network(
                            logo,
                            width: 44,
                            height: 44,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(Icons.account_balance_outlined),
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
                    } else if (v == 'show_qr') {
                      await _showTransferQr(r);
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
                    const PopupMenuItem(value: 'show_qr', child: Text('Show QR')),
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
