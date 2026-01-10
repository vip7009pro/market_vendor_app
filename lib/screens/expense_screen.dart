import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/auth_provider.dart';
import '../services/document_storage_service.dart';
import '../services/database_service.dart';
import '../services/drive_sync_service.dart';
import '../utils/number_input_formatter.dart';

class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({super.key});

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  DateTimeRange? _range;
  String _query = '';
  String _category = 'all';

  bool _isTableView = false;

  final Set<String> _docUploading = <String>{};

  static const List<String> _categories = <String>[
    'all',
    'Nhân công',
    'Thuê mặt bằng-kho bãi',
    'Phí quản lý (vpp, dụng cụ)',
    'Điện',
    'Nước',
    'Internet',
    'Xăng xe',
    'Chi tiêu ngoài kinh doanh',
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

  bool _looksLikeLocalDocPath(String? fileIdOrPath) {
    final s = (fileIdOrPath ?? '').trim();
    return s.startsWith('expense_docs/') || s.startsWith('expense_docs\\');
  }

  Future<String?> _ensureExpenseDocLocal({
    required String expenseId,
    String? fileIdFromDb,
  }) async {
    final existing = (fileIdFromDb ?? '').trim();
    if (existing.isEmpty) return null;
    if (_looksLikeLocalDocPath(existing)) return existing;

    // Legacy: Drive fileId
    final token = await _getDriveToken();
    if (token == null) return null;

    final bytes = await DriveSyncService().downloadFile(accessToken: token, fileId: existing);

    final dir = await getTemporaryDirectory();
    final tmp = File('${dir.path}/$expenseId');
    await tmp.writeAsBytes(bytes, flush: true);

    // Default to jpg when migrating (old versions uploaded jpg)
    final rel = await DocumentStorageService.instance.saveExpenseDoc(
      expenseId: expenseId,
      sourcePath: tmp.path,
      extension: '.jpg',
    );
    await DatabaseService.instance.markExpenseDocUploaded(expenseId: expenseId, fileId: rel);
    return rel;
  }

  Future<void> _uploadExpenseDoc({required String expenseId}) async {
    if (mounted) {
      setState(() {
        _docUploading.add(expenseId);
      });
    }

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Chụp ảnh (JPG)'),
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.upload_file_outlined),
                title: const Text('Chọn file (PDF/Ảnh)'),
                onTap: () => Navigator.pop(ctx, 'file'),
              ),
            ],
          ),
        );
      },
    );

    if (action == null) {
      if (mounted) {
        setState(() {
          _docUploading.remove(expenseId);
        });
      }
      return;
    }

    try {
      String? relPath;

      if (action == 'camera') {
        final picker = ImagePicker();
        final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
        if (picked != null) {
          relPath = await DocumentStorageService.instance.saveExpenseDoc(
            expenseId: expenseId,
            sourcePath: picked.path,
            extension: '.jpg',
          );
        }
      } else {
        final res = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowMultiple: false,
          allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
          withData: false,
        );
        final path = res?.files.single.path;
        if (path != null && path.trim().isNotEmpty) {
          relPath = await DocumentStorageService.instance.saveExpenseDoc(
            expenseId: expenseId,
            sourcePath: path,
          );
        }
      }

      if (relPath == null || relPath.trim().isEmpty) return;
      await DatabaseService.instance.markExpenseDocUploaded(expenseId: expenseId, fileId: relPath);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu chứng từ vào ứng dụng')),
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
    final localRel = await _ensureExpenseDocLocal(expenseId: expenseId, fileIdFromDb: fileIdFromDb);
    if (localRel == null || localRel.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có chứng từ cho chi phí này')),
      );
      return;
    }

    final full = await DocumentStorageService.instance.resolvePath(localRel);
    if (full == null) return;
    final ext = full.toLowerCase();
    if (ext.endsWith('.jpg') || ext.endsWith('.jpeg') || ext.endsWith('.png')) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: InteractiveViewer(
            child: Image.file(File(full), fit: BoxFit.contain),
          ),
        ),
      );
      return;
    }

    await OpenFilex.open(full);
  }

  Future<void> _downloadExpenseDoc({
    required String expenseId,
    String? fileIdFromDb,
  }) async {
    final localRel = await _ensureExpenseDocLocal(expenseId: expenseId, fileIdFromDb: fileIdFromDb);
    if (localRel == null || localRel.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có chứng từ để tải')),
      );
      return;
    }

    final full = await DocumentStorageService.instance.resolvePath(localRel);
    if (full == null) return;
    await Share.shareXFiles([XFile(full)], text: 'Chứng từ chi phí: $expenseId');
  }

  Future<void> _deleteExpenseDoc({
    required String expenseId,
    String? fileIdFromDb,
  }) async {
    final existing = (fileIdFromDb ?? '').trim();
    if (existing.isEmpty) {
      await DatabaseService.instance.clearExpenseDoc(expenseId: expenseId);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy chứng từ để xóa')),
      );
      return;
    }

    if (_looksLikeLocalDocPath(existing)) {
      await DocumentStorageService.instance.delete(existing);
    }
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
    final amountCtrl = TextEditingController(
      text: existing == null
          ? ''
          : NumberFormat.decimalPattern('en_US').format(((existing['amount'] as num?)?.toDouble() ?? 0).round()),
    );
    final noteCtrl = TextEditingController(
      text: existing == null ? '' : (existing['note'] as String? ?? ''),
    );

    var occurredAt = DateTime.tryParse(existing?['occurredAt'] as String? ?? '') ?? DateTime.now();
    var category = (existing?['category'] as String?) ?? _categories.firstWhere((c) => c != 'all', orElse: () => 'Chi phí khác');

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
                      keyboardType: const TextInputType.numberWithOptions(decimal: false),
                      inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
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
                    final amount = NumberInputFormatter.tryParse(amountCtrl.text) ?? 0;
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      amountCtrl.dispose();
      noteCtrl.dispose();
    });

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

  Widget _tableHeaderCell(String text, {double? width, TextAlign align = TextAlign.left}) {
    return Container(
      alignment: align == TextAlign.right
          ? Alignment.centerRight
          : align == TextAlign.center
              ? Alignment.center
              : Alignment.centerLeft,
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Widget _tableCell(Widget child, {double? width, Alignment alignment = Alignment.centerLeft}) {
    return Container(
      alignment: alignment,
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: child,
    );
  }

  Widget _buildExpenseTable({
    required List<Map<String, dynamic>> rows,
    required NumberFormat currency,
  }) {
    if (rows.isEmpty) {
      return const Center(child: Text('Chưa có chi phí'));
    }

    final fmtDate = DateFormat('dd/MM/yyyy HH:mm');

    const wDate = 150.0;
    const wAmount = 120.0;
    const wCategory = 220.0;
    const wNote = 320.0;
    const wDoc = 110.0;
    const wActions = 140.0;
    const tableWidth = wDate + wAmount + wCategory + wNote + wDoc + wActions;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            height: constraints.maxHeight,
            child: Column(
              children: [
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  elevation: 1,
                  child: Row(
                    children: [
                      _tableHeaderCell('Ngày', width: wDate),
                      _tableHeaderCell('Số tiền', width: wAmount, align: TextAlign.right),
                      _tableHeaderCell('Phân loại', width: wCategory),
                      _tableHeaderCell('Ghi chú', width: wNote),
                      _tableHeaderCell('Chứng từ', width: wDoc, align: TextAlign.center),
                      _tableHeaderCell('Thao tác', width: wActions, align: TextAlign.center),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = rows[i];
                      final expenseId = r['id'] as String;
                      final occurredAt = DateTime.tryParse(r['occurredAt'] as String? ?? '') ?? DateTime.now();
                      final amount = (r['amount'] as num?)?.toDouble() ?? 0;
                      final category = (r['category'] as String?) ?? '';
                      final note = (r['note'] as String?)?.trim() ?? '';
                      final docUploaded = (r['expenseDocUploaded'] as int?) == 1;
                      final docUploading = _docUploading.contains(expenseId);

                      return InkWell(
                        onTap: () => _addOrEditExpense(existing: r),
                        child: Row(
                          children: [
                            _tableCell(Text(fmtDate.format(occurredAt)), width: wDate),
                            _tableCell(
                              Text(currency.format(amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                              width: wAmount,
                              alignment: Alignment.centerRight,
                            ),
                            _tableCell(Text(category), width: wCategory),
                            _tableCell(
                              Text(note, maxLines: 2, overflow: TextOverflow.ellipsis),
                              width: wNote,
                            ),
                            _tableCell(
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    docUploaded ? 'Đã upload' : 'Chưa upload',
                                    style: TextStyle(
                                      color: docUploaded ? Colors.green : Colors.black54,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (docUploading) ...[
                                    const SizedBox(width: 6),
                                    const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                                  ],
                                ],
                              ),
                              width: wDoc,
                              alignment: Alignment.center,
                            ),
                            _tableCell(
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    tooltip: 'Chứng từ',
                                    onPressed: () => _showDocActions(row: r),
                                    icon: Icon(
                                      docUploaded ? Icons.verified_outlined : Icons.description_outlined,
                                      color: docUploaded ? Colors.green : null,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Sửa',
                                    onPressed: () => _addOrEditExpense(existing: r),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Xóa',
                                    onPressed: () => _deleteExpense(r),
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  ),
                                ],
                              ),
                              width: wActions,
                              alignment: Alignment.center,
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi phí'),
        actions: [
          IconButton(
            tooltip: _isTableView ? 'Xem dạng thẻ' : 'Xem dạng bảng',
            icon: Icon(_isTableView ? Icons.view_agenda_outlined : Icons.table_rows_outlined),
            onPressed: () => setState(() => _isTableView = !_isTableView),
          ),
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

                if (_isTableView) {
                  return _buildExpenseTable(rows: rows, currency: currency);
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
                      leading: GestureDetector(
                        onTap: () => _showDocActions(row: r),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              backgroundColor: (docUploaded ? Colors.green : Colors.deepPurple).withValues(alpha: 0.12),
                              foregroundColor: docUploaded ? Colors.green : Colors.deepPurple,
                              child: Icon(
                                docUploaded ? Icons.verified_outlined : Icons.description_outlined,
                              ),
                            ),
                            if (docUploading)
                              const Positioned(
                                right: -2,
                                bottom: -2,
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                          ],
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              currency.format(amount),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('dd/MM/yyyy HH:mm').format(occurredAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.black54, fontSize: 12),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(category, maxLines: 1, overflow: TextOverflow.ellipsis),
                          if (note != null && note.isNotEmpty) Text('Ghi chú: $note'),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
