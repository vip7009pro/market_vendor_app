import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/auth_provider.dart';
import '../services/database_service.dart';
import '../services/drive_sync_service.dart';

class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({super.key});

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  DateTimeRange? _range;
  String _query = '';
  String _category = 'all';

  final Set<String> _docUploading = <String>{};

  static const List<String> _categories = <String>[
    'all',
    'Điện',
    'Nước',
    'Internet',
    'Xăng xe',
    'Chi phí khác',
  ];

  Future<List<Map<String, dynamic>>> _load() {
    return DatabaseService.instance.getExpenses(
      range: _range,
      category: _category,
      query: _query,
    );
  }

  Future<String?> _getDriveToken() async {
    final token = await context.read<AuthProvider>().getAccessToken();
    if (token == null || token.isEmpty) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không lấy được token Google. Vui lòng đăng nhập lại.')),
      );
      return null;
    }
    return token;
  }

  Future<void> _uploadExpenseDoc({required String expenseId}) async {
    final token = await _getDriveToken();
    if (token == null) return;

    if (mounted) {
      setState(() {
        _docUploading.add(expenseId);
      });
    }

    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Chụp ảnh'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Chọn ảnh trong máy'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );

    if (source == null) {
      if (mounted) {
        setState(() {
          _docUploading.remove(expenseId);
        });
      }
      return;
    }

    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) {
      if (mounted) {
        setState(() {
          _docUploading.remove(expenseId);
        });
      }
      return;
    }

    final bytes = await picked.readAsBytes();

    try {
      final meta = await DriveSyncService().uploadOrUpdateExpenseDocJpg(
        accessToken: token,
        expenseId: expenseId,
        bytes: bytes,
      );
      final fileId = (meta['id'] ?? '').trim();
      if (fileId.isNotEmpty) {
        await DatabaseService.instance.markExpenseDocUploaded(expenseId: expenseId, fileId: fileId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã tải chứng từ chi phí lên Google Drive')),
      );
      setState(() {});
    } finally {
      if (mounted) {
        setState(() {
          _docUploading.remove(expenseId);
        });
      }
    }
  }

  Future<void> _openExpenseDoc({required String expenseId, String? fileIdFromDb}) async {
    final token = await _getDriveToken();
    if (token == null) return;

    var fileId = (fileIdFromDb ?? '').trim();
    if (fileId.isEmpty) {
      final info = await DriveSyncService().getExpenseDocByName(accessToken: token, expenseId: expenseId);
      fileId = (info?['id'] ?? '').trim();
      if (fileId.isNotEmpty) {
        await DatabaseService.instance.markExpenseDocUploaded(expenseId: expenseId, fileId: fileId);
      }
    }

    if (fileId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có chứng từ cho chi phí này')),
      );
      return;
    }

    final bytes = await DriveSyncService().downloadFile(accessToken: token, fileId: fileId);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: InteractiveViewer(
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Future<void> _downloadExpenseDoc({
    required String expenseId,
    String? fileIdFromDb,
  }) async {
    final token = await _getDriveToken();
    if (token == null) return;

    var fileId = (fileIdFromDb ?? '').trim();
    if (fileId.isEmpty) {
      final info = await DriveSyncService().getExpenseDocByName(accessToken: token, expenseId: expenseId);
      fileId = (info?['id'] ?? '').trim();
    }

    if (fileId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có chứng từ để tải')),
      );
      return;
    }

    final bytes = await DriveSyncService().downloadFile(accessToken: token, fileId: fileId);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$expenseId.jpg');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path)], text: 'Chứng từ chi phí: $expenseId');
  }

  Future<void> _deleteExpenseDoc({
    required String expenseId,
    String? fileIdFromDb,
  }) async {
    final token = await _getDriveToken();
    if (token == null) return;

    var fileId = (fileIdFromDb ?? '').trim();
    if (fileId.isEmpty) {
      final info = await DriveSyncService().getExpenseDocByName(accessToken: token, expenseId: expenseId);
      fileId = (info?['id'] ?? '').trim();
    }

    if (fileId.isEmpty) {
      await DatabaseService.instance.clearExpenseDoc(expenseId: expenseId);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy chứng từ để xóa')),
      );
      return;
    }

    await DriveSyncService().deleteFile(accessToken: token, fileId: fileId);
    await DatabaseService.instance.clearExpenseDoc(expenseId: expenseId);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã xóa chứng từ')),
    );
  }

  Future<void> _showDocActions({required Map<String, dynamic> row}) async {
    final expenseId = row['id'] as String;
    final uploaded = (row['expenseDocUploaded'] as int?) == 1;
    final fileId = (row['expenseDocFileId'] as String?)?.trim();
    final uploading = _docUploading.contains(expenseId);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: uploading
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_file_outlined),
                title: Text(uploaded ? 'Up lại chứng từ' : 'Upload chứng từ'),
                onTap: uploading
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        await _uploadExpenseDoc(expenseId: expenseId);
                      },
              ),
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('Xem chứng từ'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _openExpenseDoc(expenseId: expenseId, fileIdFromDb: fileId);
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Tải chứng từ'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _downloadExpenseDoc(expenseId: expenseId, fileIdFromDb: fileId);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Xóa chứng từ', style: TextStyle(color: Colors.redAccent)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Xóa chứng từ'),
                      content: const Text('Bạn có chắc muốn xóa chứng từ này?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
                        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa')),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await _deleteExpenseDoc(expenseId: expenseId, fileIdFromDb: fileId);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addOrEditExpense({Map<String, dynamic>? existing}) async {
    DateTime occurredAt = DateTime.now();
    if (existing != null) {
      occurredAt = DateTime.tryParse(existing['occurredAt'] as String? ?? '') ?? DateTime.now();
    }

    final amountCtrl = TextEditingController(
      text: existing == null ? '' : ((existing['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(0),
    );
    String category = existing == null ? 'Chi phí khác' : (existing['category'] as String? ?? 'Chi phí khác');
    final noteCtrl = TextEditingController(text: (existing?['note'] as String?) ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              title: Text(existing == null ? 'Thêm chi phí' : 'Sửa chi phí'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event),
                      title: Text(DateFormat('dd/MM/yyyy HH:mm').format(occurredAt)),
                      onTap: () async {
                        final d = await showDatePicker(
                          context: ctx,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          initialDate: occurredAt,
                        );
                        if (d == null) return;
                        final t = await showTimePicker(
                          context: ctx,
                          initialTime: TimeOfDay.fromDateTime(occurredAt),
                        );
                        final next = DateTime(
                          d.year,
                          d.month,
                          d.day,
                          t?.hour ?? occurredAt.hour,
                          t?.minute ?? occurredAt.minute,
                        );
                        setModalState(() => occurredAt = next);
                      },
                    ),
                    TextField(
                      controller: amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Số tiền',
                        prefixIcon: Icon(Icons.payments_outlined),
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: category,
                      items: _categories
                          .where((c) => c != 'all')
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setModalState(() => category = v);
                      },
                      decoration: const InputDecoration(
                        labelText: 'Phân loại',
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Ghi chú',
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                      minLines: 1,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
                FilledButton(
                  onPressed: () async {
                    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                    if (amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Số tiền không hợp lệ')),
                      );
                      return;
                    }

                    if (existing == null) {
                      await DatabaseService.instance.insertExpense(
                        occurredAt: occurredAt,
                        amount: amount,
                        category: category,
                        note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                      );
                    } else {
                      await DatabaseService.instance.updateExpense(
                        id: existing['id'] as String,
                        occurredAt: occurredAt,
                        amount: amount,
                        category: category,
                        note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                      );
                    }

                    if (!ctx.mounted) return;
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('Lưu'),
                ),
              ],
            );
          },
        );
      },
    );

    amountCtrl.dispose();
    noteCtrl.dispose();

    if (saved == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _deleteExpense(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xóa chi phí'),
        content: const Text('Bạn có chắc muốn xóa chi phí này không?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (ok != true) return;
    await DatabaseService.instance.deleteExpense(row['id'] as String);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa chi phí')));
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi phí'),
        actions: [
          IconButton(
            tooltip: 'Thêm chi phí',
            icon: const Icon(Icons.add),
            onPressed: () => _addOrEditExpense(),
          ),
          IconButton(
            tooltip: 'Chọn khoảng ngày',
            icon: const Icon(Icons.calendar_today),
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(now.year - 2),
                lastDate: DateTime(now.year + 1),
                initialDateRange: _range,
              );
              if (picked != null) {
                setState(() => _range = picked);
              }
            },
          ),
          if (_range != null)
            IconButton(
              tooltip: 'Xóa lọc ngày',
              icon: const Icon(Icons.clear),
              onPressed: () => setState(() => _range = null),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: _category,
                  items: _categories
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(c == 'all' ? 'Tất cả' : c),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _category = v);
                  },
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.category_outlined),
                    labelText: 'Phân loại',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Tìm theo ghi chú',
                    isDense: true,
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _load(),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snap.data ?? const [];
                if (rows.isEmpty) {
                  return const Center(child: Text('Chưa có chi phí'));
                }

                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    final expenseId = r['id'] as String;
                    final occurredAt = DateTime.tryParse(r['occurredAt'] as String? ?? '') ?? DateTime.now();
                    final amount = (r['amount'] as num?)?.toDouble() ?? 0;
                    final category = (r['category'] as String?) ?? '';
                    final note = (r['note'] as String?)?.trim();
                    final docUploaded = (r['expenseDocUploaded'] as int?) == 1;
                    final docUploading = _docUploading.contains(expenseId);

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.deepPurple.withValues(alpha: 0.12),
                        foregroundColor: Colors.deepPurple,
                        child: const Icon(Icons.payments_outlined),
                      ),
                      title: Text(currency.format(amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$category | ${DateFormat('dd/MM/yyyy HH:mm').format(occurredAt)}'),
                          if (note != null && note.isNotEmpty) Text('Ghi chú: $note'),
                          Row(
                            children: [
                              const Text('Chứng từ: '),
                              Text(
                                docUploaded ? 'Đã upload' : 'Chưa upload',
                                style: TextStyle(
                                  color: docUploaded ? Colors.green : Colors.black54,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (docUploading) ...[
                                const SizedBox(width: 8),
                                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                              ],
                            ],
                          ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Chứng từ',
                            onPressed: () => _showDocActions(row: r),
                            icon: Icon(
                              docUploaded ? Icons.verified_outlined : Icons.description_outlined,
                              color: docUploaded ? Colors.green : null,
                            ),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'edit') {
                                await _addOrEditExpense(existing: r);
                              }
                              if (v == 'delete') {
                                await _deleteExpense(r);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Sửa')),
                              PopupMenuItem(value: 'delete', child: Text('Xóa')),
                            ],
                          ),
                        ],
                      ),
                      onTap: () => _addOrEditExpense(existing: r),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
