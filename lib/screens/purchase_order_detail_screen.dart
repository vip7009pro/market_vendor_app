import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../providers/debt_provider.dart';
import '../providers/product_provider.dart';
import '../services/database_service.dart';
import '../services/document_storage_service.dart';
import 'purchase_order_create_screen.dart';

class PurchaseOrderDetailScreen extends StatefulWidget {
  final String purchaseOrderId;

  const PurchaseOrderDetailScreen({
    super.key,
    required this.purchaseOrderId,
  });

  @override
  State<PurchaseOrderDetailScreen> createState() => _PurchaseOrderDetailScreenState();
}

class _PurchaseOrderDetailScreenState extends State<PurchaseOrderDetailScreen> {
  int _reloadTick = 0;
  bool _busy = false;

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() => _reloadTick++);
  }

  Future<void> _editOrder(Map<String, dynamic> order) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseOrderCreateScreen(purchaseOrderId: widget.purchaseOrderId),
      ),
    );

    if (changed == true) {
      await context.read<ProductProvider>().load();
      await context.read<DebtProvider>().load();
      await _reload();
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá đơn nhập'),
        content: const Text('Bạn chắc chắn muốn xoá đơn?\n\nHệ thống sẽ xoá các dòng nhập đã gán và hoàn tồn kho tương ứng.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xoá')),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await DatabaseService.instance.deletePurchaseOrder(purchaseOrderId: widget.purchaseOrderId);

      await context.read<ProductProvider>().load();
      await context.read<DebtProvider>().load();

      if (!mounted) return;
      Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openOrderDoc(String? relativePath) async {
    final full = await DocumentStorageService.instance.resolvePath(relativePath);
    if (full == null || full.isEmpty) return;
    await OpenFilex.open(full);
  }

  Future<void> _uploadOrderDoc() async {
    if (_busy) return;

    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Chụp ảnh'),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Chọn ảnh'),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.attach_file),
                title: const Text('Chọn file'),
                onTap: () => Navigator.pop(context, 'file'),
              ),
            ],
          ),
        );
      },
    );

    if (picked == null) return;

    setState(() => _busy = true);
    try {
      String? relPath;
      if (picked == 'camera') {
        final picker = ImagePicker();
        final img = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
        if (img == null) return;
        relPath = await DocumentStorageService.instance.savePurchaseOrderDoc(
          purchaseOrderId: widget.purchaseOrderId,
          sourcePath: img.path,
          extension: '.jpg',
        );
      } else if (picked == 'gallery') {
        final picker = ImagePicker();
        final img = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
        if (img == null) return;
        relPath = await DocumentStorageService.instance.savePurchaseOrderDoc(
          purchaseOrderId: widget.purchaseOrderId,
          sourcePath: img.path,
          extension: '.jpg',
        );
      } else {
        final res = await FilePicker.platform.pickFiles();
        final path = res?.files.single.path;
        if (path == null || path.trim().isEmpty) return;
        relPath = await DocumentStorageService.instance.savePurchaseOrderDoc(
          purchaseOrderId: widget.purchaseOrderId,
          sourcePath: path,
        );
      }

      if (relPath.isEmpty) return;

      await DatabaseService.instance.markPurchaseOrderDocUploaded(
        purchaseOrderId: widget.purchaseOrderId,
        fileId: relPath,
      );
      await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteOrderDoc({required String? relativePath}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xoá chứng từ'),
        content: const Text('Bạn chắc chắn muốn xoá chứng từ của đơn?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xoá')),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await DocumentStorageService.instance.delete(relativePath);
      await DatabaseService.instance.clearPurchaseOrderDoc(purchaseOrderId: widget.purchaseOrderId);
      await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAndAssignLines() async {
    if (_busy) return;

    final db = DatabaseService.instance.db;
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    final fmtDate = DateFormat('dd/MM/yyyy HH:mm');

    final rows = await db.query(
      'purchase_history',
      where: 'purchaseOrderId IS NULL',
      orderBy: 'createdAt DESC',
      limit: 300,
    );

    if (!mounted) return;

    final selected = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Gán dòng nhập kho'),
              content: SizedBox(
                width: 520,
                height: 460,
                child: rows.isEmpty
                    ? const Center(child: Text('Không có dòng nhập nào chưa gán'))
                    : ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final r = rows[i];
                          final id = (r['id'] as String?) ?? '';
                          final createdAt = DateTime.tryParse(r['createdAt'] as String? ?? '') ?? DateTime.now();
                          final name = (r['productName'] as String?) ?? '';
                          final qty = (r['quantity'] as num?)?.toDouble() ?? 0.0;
                          final totalCost = (r['totalCost'] as num?)?.toDouble() ?? 0.0;

                          final checked = selected.contains(id);
                          return CheckboxListTile(
                            value: checked,
                            onChanged: (v) {
                              if (id.isEmpty) return;
                              setLocal(() {
                                if (v == true) {
                                  selected.add(id);
                                } else {
                                  selected.remove(id);
                                }
                              });
                            },
                            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              '${fmtDate.format(createdAt)}\nSL: ${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2)} | Thành tiền: ${currency.format(totalCost)}',
                            ),
                            isThreeLine: true,
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
                FilledButton(
                  onPressed: selected.isEmpty ? null : () => Navigator.pop(context, true),
                  child: Text('Gán (${selected.length})'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true || selected.isEmpty) return;

    setState(() => _busy = true);
    try {
      for (final id in selected) {
        await DatabaseService.instance.assignPurchaseHistoryToOrder(
          purchaseHistoryId: id,
          purchaseOrderId: widget.purchaseOrderId,
        );
      }

      await DatabaseService.instance.syncPurchaseOrderDebt(purchaseOrderId: widget.purchaseOrderId);
      await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unassignLine(String purchaseHistoryId) async {
    if (_busy) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bỏ gán sản phẩm khỏi đơn'),
        content: const Text(
          'Bạn chắc chắn muốn bỏ gán dòng nhập này khỏi đơn?\n\nDòng nhập sẽ trở về Nhập kho (cũ) và không nằm trong đơn nữa.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Bỏ gán')),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await DatabaseService.instance.unassignPurchaseHistoryFromOrder(purchaseHistoryId: purchaseHistoryId);

      await DatabaseService.instance.syncPurchaseOrderDebt(purchaseOrderId: widget.purchaseOrderId);
      await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    final fmtDate = DateFormat('dd/MM/yyyy HH:mm');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết đơn nhập'),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        key: ValueKey(_reloadTick),
        future: DatabaseService.instance.getPurchaseOrderById(widget.purchaseOrderId),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final order = snap.data;
          if (order == null) {
            return const Center(child: Text('Không tìm thấy đơn nhập'));
          }

          final createdAt = DateTime.tryParse(order['createdAt'] as String? ?? '') ?? DateTime.now();
          final supplierName = (order['supplierName'] as String?)?.trim();
          final supplierPhone = (order['supplierPhone'] as String?)?.trim();
          final note = (order['note'] as String?)?.trim();

          final docUploaded = (order['purchaseDocUploaded'] as int?) == 1;
          final docRel = (order['purchaseDocFileId'] as String?)?.trim();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Ngày: ${fmtDate.format(createdAt)}',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Sửa',
                            onPressed: _busy ? null : () => _editOrder(order),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Xoá',
                            onPressed: _busy ? null : _confirmDelete,
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                          ),
                        ],
                      ),
                      if (supplierName != null && supplierName.isNotEmpty) Text('NCC: $supplierName'),
                      if (supplierPhone != null && supplierPhone.isNotEmpty) Text('SĐT: $supplierPhone'),
                      if (note != null && note.isNotEmpty) Text('Ghi chú: $note'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Chứng từ: ${docUploaded ? 'Đã có' : 'Chưa có'}',
                              style: TextStyle(
                                color: docUploaded ? Colors.green : Colors.black54,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _uploadOrderDoc,
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Tải lên'),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Mở',
                            onPressed: (!docUploaded || docRel == null || docRel.isEmpty || _busy)
                                ? null
                                : () => _openOrderDoc(docRel),
                            icon: const Icon(Icons.open_in_new),
                          ),
                          IconButton(
                            tooltip: 'Xoá chứng từ',
                            onPressed: (!docUploaded || _busy) ? null : () => _deleteOrderDoc(relativePath: docRel),
                            icon: const Icon(Icons.delete_sweep_outlined),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FutureBuilder<Map<String, double>?>(
                key: ValueKey('totals_$_reloadTick'),
                future: DatabaseService.instance.getPurchaseOrderTotals(widget.purchaseOrderId),
                builder: (context, ts) {
                  if (ts.connectionState != ConnectionState.done) {
                    return const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()));
                  }
                  final t = ts.data;
                  if (t == null) return const SizedBox.shrink();

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Tổng hợp', style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          _kv('Tạm tính', currency.format(t['subtotal'] ?? 0)),
                          _kv('Chiết khấu', currency.format(t['discountAmount'] ?? 0)),
                          _kv('Tổng đơn', currency.format(t['total'] ?? 0), bold: true),
                          const Divider(height: 16),
                          _kv('Đã thanh toán', currency.format(t['paidAmount'] ?? 0)),
                          _kv('Còn nợ', currency.format(t['remainDebt'] ?? 0), bold: true, color: Colors.redAccent),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: Text('Dòng nhập đã gán', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pickAndAssignLines,
                    icon: const Icon(Icons.link),
                    label: const Text('Gán dòng'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FutureBuilder<List<Map<String, dynamic>>>(
                key: ValueKey('lines_$_reloadTick'),
                future: DatabaseService.instance.getPurchaseHistoryByOrderId(widget.purchaseOrderId),
                builder: (context, ls) {
                  if (ls.connectionState != ConnectionState.done) {
                    return const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()));
                  }

                  final rows = ls.data ?? const [];
                  if (rows.isEmpty) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Chưa có dòng nhập nào được gán vào đơn này'),
                      ),
                    );
                  }

                  return Card(
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final r = rows[i];
                        final id = (r['id'] as String?) ?? '';
                        final createdAt = DateTime.tryParse(r['createdAt'] as String? ?? '') ?? DateTime.now();
                        final name = (r['productName'] as String?) ?? '';
                        final qty = (r['quantity'] as num?)?.toDouble() ?? 0.0;
                        final unitCost = (r['unitCost'] as num?)?.toDouble() ?? 0.0;
                        final totalCost = (r['totalCost'] as num?)?.toDouble() ?? (qty * unitCost);
                        final note = (r['note'] as String?)?.trim();

                        return ListTile(
                          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Ngày: ${fmtDate.format(createdAt)}'),
                              Text('SL: ${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2)}'),
                              Text('Giá nhập: ${currency.format(unitCost)} | Thành tiền: ${currency.format(totalCost)}'),
                              if (note != null && note.isNotEmpty) Text('Ghi chú: $note'),
                            ],
                          ),
                          trailing: IconButton(
                            tooltip: 'Bỏ gán',
                            onPressed: (_busy || id.isEmpty) ? null : () => _unassignLine(id),
                            icon: const Icon(Icons.link_off),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _kv(
    String label,
    String value, {
    bool bold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}
