import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/customer_provider.dart';
import '../providers/debt_provider.dart';
import '../providers/product_provider.dart';
import '../providers/sale_provider.dart';
import '../services/database_service.dart';
import '../services/drive_sync_service.dart';

class DriveBackupManagerScreen extends StatefulWidget {
  const DriveBackupManagerScreen({super.key});

  @override
  State<DriveBackupManagerScreen> createState() => _DriveBackupManagerScreenState();
}

class _DriveBackupManagerScreenState extends State<DriveBackupManagerScreen> {
  bool _loading = false;
  bool _backingUp = false;
  bool _deleting = false;
  bool _restoring = false;
  String? _error;
  List<Map<String, String>> _files = const [];

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const k = 1024.0;
    final kb = bytes / k;
    if (kb < 1) return '$bytes B';
    final mb = kb / k;
    if (mb < 1) return '${kb.toStringAsFixed(1)} KB';
    final gb = mb / k;
    if (gb < 1) return '${mb.toStringAsFixed(1)} MB';
    return '${gb.toStringAsFixed(2)} GB';
  }

  Future<String?> _getToken() async {
    final token = await context.read<AuthProvider>().getAccessToken();
    if (token == null || token.isEmpty) return null;
    return token;
  }

  Future<void> _restoreFile(Map<String, String> f) async {
    final id = (f['id'] ?? '').trim();
    if (id.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xác nhận khôi phục'),
        content: Text(
          'Khôi phục từ "${f['name'] ?? ''}"? Dữ liệu hiện tại sẽ bị ghi đè.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Khôi phục')),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _restoring = true;
      _error = null;
    });

    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Không lấy được token Google. Vui lòng đăng nhập lại.');
      }

      await DatabaseService.instance.close();
      await DriveSyncService().restoreToLocal(accessToken: token, fileId: id);
      await DatabaseService.instance.reinitialize();

      if (!mounted) return;
      final productProvider = Provider.of<ProductProvider>(context, listen: false);
      final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
      final saleProvider = Provider.of<SaleProvider>(context, listen: false);
      final debtProvider = Provider.of<DebtProvider>(context, listen: false);

      await Future.wait([
        productProvider.load(),
        customerProvider.load(),
        saleProvider.load(),
        debtProvider.load(),
      ]);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã khôi phục từ ${f['name'] ?? ''}')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _restoring = false;
      });
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Không lấy được token Google. Vui lòng đăng nhập lại.');
      }
      final files = await DriveSyncService().listBackups(accessToken: token);
      if (!mounted) return;
      setState(() {
        _files = files;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _backupNow() async {
    setState(() {
      _backingUp = true;
      _error = null;
    });

    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Không lấy được token Google. Vui lòng đăng nhập lại.');
      }
      final msg = await DriveSyncService().uploadLocalDb(accessToken: token);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _backingUp = false;
      });
    }
  }

  DateTime? _parseModifiedTime(String? s) {
    final raw = (s ?? '').trim();
    if (raw.isEmpty) return null;
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteFile(Map<String, String> f) async {
    final id = (f['id'] ?? '').trim();
    if (id.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xóa bản sao lưu'),
        content: Text('Bạn có chắc muốn xóa "${f['name'] ?? ''}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa')),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _deleting = true;
      _error = null;
    });

    try {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Không lấy được token Google. Vui lòng đăng nhập lại.');
      }
      await DriveSyncService().deleteFile(accessToken: token, fileId: id);
      if (!mounted) return;
      await _load();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa bản sao lưu')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _deleting = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý backup Google Drive'),
        actions: [
          IconButton(
            tooltip: 'Tải lại',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (_backingUp || _loading) ? null : _backupNow,
                      icon: _backingUp
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload_outlined, size: 18),
                      label: Text(_backingUp ? 'Đang sao lưu...' : 'Backup ngay'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _load,
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.list_alt_outlined, size: 18),
                    label: const Text('Danh sách'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _files.isEmpty
                  ? const Center(child: Text('Chưa có bản sao lưu nào'))
                  : ListView.separated(
                      itemCount: _files.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final f = _files[i];
                        final name = f['name'] ?? '';
                        final modified = _parseModifiedTime(f['modifiedTime']);
                        final subtitleTime = modified == null ? (f['modifiedTime'] ?? '') : fmt.format(modified);
                        final sizeRaw = (f['size'] ?? '').trim();
                        final sizeInt = int.tryParse(sizeRaw) ?? 0;
                        final subtitle = sizeInt > 0 ? '$subtitleTime  •  ${_formatBytes(sizeInt)}' : subtitleTime;
                        final lower = name.toLowerCase();
                        final isZip = lower.endsWith('.zip');
                        final isDb = lower.endsWith('.db');

                        return ListTile(
                          leading: Icon(isZip ? Icons.archive_outlined : Icons.backup_outlined),
                          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(subtitle),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color: (isZip ? Colors.green : (isDb ? Colors.blueGrey : Colors.black45))
                                      .withValues(alpha: 0.12),
                                  border: Border.all(
                                    color: (isZip ? Colors.green : (isDb ? Colors.blueGrey : Colors.black45))
                                        .withValues(alpha: 0.30),
                                  ),
                                ),
                                child: Text(
                                  isZip ? 'ZIP: DB + Ảnh' : (isDb ? 'DB-only' : 'File'),
                                  style: TextStyle(
                                    color: isZip ? Colors.green : (isDb ? Colors.blueGrey : Colors.black45),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: 'Khôi phục',
                                onPressed: (_restoring || _loading || _backingUp || _deleting)
                                    ? null
                                    : () => _restoreFile(f),
                                icon: _restoring
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.restore, color: Colors.blueAccent),
                              ),
                              IconButton(
                                tooltip: 'Xóa',
                                onPressed: (_deleting || _loading || _backingUp || _restoring)
                                    ? null
                                    : () => _deleteFile(f),
                                icon: _deleting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.delete_outline, color: Colors.redAccent),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
