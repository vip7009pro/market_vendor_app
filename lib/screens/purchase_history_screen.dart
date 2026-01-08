import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

import '../models/product.dart';
import '../models/debt.dart';
import '../providers/debt_provider.dart';
import '../providers/product_provider.dart';
import '../providers/auth_provider.dart';
import '../services/database_service.dart';
import '../services/drive_sync_service.dart';
import '../services/document_storage_service.dart';
import '../services/product_image_service.dart';
import '../utils/number_input_formatter.dart';
import 'purchase_order_detail_screen.dart';
import 'purchase_order_create_screen.dart';

class PurchaseHistoryScreen extends StatefulWidget {
  final bool embedded;

  const PurchaseHistoryScreen({
    super.key,
    this.embedded = false,
  });

  @override
  State<PurchaseHistoryScreen> createState() => _PurchaseHistoryScreenState();
}

class _OrderDebtInfo {
  final double paid;
  final double remain;
  final bool settled;

  _OrderDebtInfo({
    required this.paid,
    required this.remain,
    required this.settled,
  });
}

class _PurchaseHistoryScreenState extends State<PurchaseHistoryScreen> {
  DateTimeRange? _range;
  String _query = '';

  bool _isTableView = false;

  bool _autoCreatingOrders = false;
  bool _autoCreatedOnce = false;

  final Map<String, Future<_OrderDebtInfo>> _orderDebtInfoCache = {};

  Future<_OrderDebtInfo> _loadOrderDebtInfo(String purchaseOrderId) async {
    final totals = await DatabaseService.instance.getPurchaseOrderTotals(purchaseOrderId);
    final total = totals?['total'] ?? 0.0;
    final debt = await DatabaseService.instance.getDebtBySource(sourceType: 'purchase', sourceId: purchaseOrderId);
    if (debt == null) {
      return _OrderDebtInfo(paid: total, remain: 0.0, settled: true);
    }
    final remain = (debt.amount).clamp(0.0, double.infinity).toDouble();
    final paid = (total - remain).clamp(0.0, double.infinity).toDouble();
    final settled = debt.settled || remain <= 0;
    return _OrderDebtInfo(paid: paid, remain: remain, settled: settled);
  }

  Future<_OrderDebtInfo> _orderDebtInfoFuture(String purchaseOrderId) {
    return _orderDebtInfoCache.putIfAbsent(purchaseOrderId, () => _loadOrderDebtInfo(purchaseOrderId));
  }

  final Set<String> _docUploading = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_autoCreatedOnce || _autoCreatingOrders) return;
      _autoCreatedOnce = true;
      _autoCreatingOrders = true;
      try {
        final createdOrderIds = await DatabaseService.instance.autoCreateOrdersForUnassignedPurchaseHistory(
          range: _range,
        );

        if (!mounted) return;
        if (createdOrderIds.isNotEmpty) {
          await context.read<ProductProvider>().load();
          await context.read<DebtProvider>().load();
          setState(() {
            _orderDebtInfoCache.clear();
          });
        }
      } finally {
        _autoCreatingOrders = false;
        if (mounted) setState(() {});
      }
    });
  }

  String removeDiacritics(String str) {
    const withDiacritics = 'áàảãạăắằẳẵặâấầuẩẫậéèẻẽẹêếềểễệíìỉĩịóòỏõọôốồổỗộơớờởỡợúùủũụưứừửữựýỳỷỹỵđ';
    const withoutDiacritics = 'aaaaaăaaaaaaâaaaaaaeeeeeêeeeeeiiiiioooooôooooooơooooouuuuuưuuuuuyyyyyd';
    String result = str.toLowerCase();
    for (int i = 0; i < withDiacritics.length; i++) {
      result = result.replaceAll(withDiacritics[i], withoutDiacritics[i]);
    }
    return result;
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

  Widget _buildTable({
    required List<Map<String, dynamic>> rows,
    required NumberFormat currency,
    required DateFormat fmtDate,
  }) {
    if (rows.isEmpty) {
      return const Center(child: Text('Chưa có dữ liệu'));
    }

    const wDate = 150.0;
    const wProduct = 280.0;
    const wQty = 80.0;
    const wUnitCost = 120.0;
    const wTotalCost = 130.0;
    const wPaid = 120.0;
    const wRemain = 120.0;
    const wSupplier = 200.0;
    const wNote = 260.0;
    const wDoc = 90.0;
    const wOrder = 110.0;
    const wActions = 120.0;
    const tableWidth =
        wDate + wProduct + wQty + wUnitCost + wTotalCost + wPaid + wRemain + wSupplier + wNote + wDoc + wOrder + wActions;

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
                      _tableHeaderCell('Sản phẩm', width: wProduct),
                      _tableHeaderCell('SL', width: wQty, align: TextAlign.right),
                      _tableHeaderCell('Giá nhập', width: wUnitCost, align: TextAlign.right),
                      _tableHeaderCell('Thành tiền', width: wTotalCost, align: TextAlign.right),
                      _tableHeaderCell('Đã trả', width: wPaid, align: TextAlign.right),
                      _tableHeaderCell('Còn nợ', width: wRemain, align: TextAlign.right),
                      _tableHeaderCell('NCC', width: wSupplier),
                      _tableHeaderCell('Ghi chú', width: wNote),
                      _tableHeaderCell('Chứng từ', width: wDoc, align: TextAlign.center),
                      _tableHeaderCell('Đơn', width: wOrder, align: TextAlign.center),
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
                      final createdAt = DateTime.tryParse(r['createdAt'] as String? ?? '') ?? DateTime.now();
                      final name = (r['productName'] as String?) ?? '';
                      final qty = (r['quantity'] as num?)?.toDouble() ?? 0;
                      final unitCost = (r['unitCost'] as num?)?.toDouble() ?? 0;
                      final totalCost = (r['totalCost'] as num?)?.toDouble() ?? (qty * unitCost);
                      final paidAmount = (r['paidAmount'] as num?)?.toDouble() ?? 0;
                      final remainDebt = (totalCost - paidAmount).clamp(0.0, double.infinity).toDouble();
                      final note = (r['note'] as String?)?.trim();
                      final supplierName = (r['supplierName'] as String?)?.trim();
                      final docUploaded = (r['purchaseDocUploaded'] as int?) == 1;
                      final purchaseId = (r['id'] as String?) ?? '';
                      final docUploading = purchaseId.isNotEmpty && _docUploading.contains(purchaseId);
                      final purchaseOrderId = (r['purchaseOrderId'] as String?)?.trim();
                      final assignedOrder = purchaseOrderId != null && purchaseOrderId.isNotEmpty;

                      return InkWell(
                        onTap: () async {
                          await _editPurchaseDialog(r);
                          if (!mounted) return;
                          setState(() {});
                        },
                        child: Row(
                          children: [
                            _tableCell(Text(fmtDate.format(createdAt)), width: wDate),
                            _tableCell(
                              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
                              width: wProduct,
                            ),
                            _tableCell(
                              Text(qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2)),
                              width: wQty,
                              alignment: Alignment.centerRight,
                            ),
                            _tableCell(
                              Text(currency.format(unitCost)),
                              width: wUnitCost,
                              alignment: Alignment.centerRight,
                            ),
                            _tableCell(
                              Text(currency.format(totalCost)),
                              width: wTotalCost,
                              alignment: Alignment.centerRight,
                            ),
                            _tableCell(
                              assignedOrder
                                  ? FutureBuilder<_OrderDebtInfo>(
                                      future: _orderDebtInfoFuture(purchaseOrderId),
                                      builder: (context, snap) {
                                        final info = snap.data;
                                        final val = info?.paid ?? 0.0;
                                        return Text(currency.format(val));
                                      },
                                    )
                                  : Text(currency.format(paidAmount)),
                              width: wPaid,
                              alignment: Alignment.centerRight,
                            ),
                            _tableCell(
                              assignedOrder
                                  ? FutureBuilder<_OrderDebtInfo>(
                                      future: _orderDebtInfoFuture(purchaseOrderId),
                                      builder: (context, snap) {
                                        final info = snap.data;
                                        final remain = info?.remain ?? 0.0;
                                        final settled = info?.settled ?? true;
                                        final text = settled ? 'Đã TT' : currency.format(remain);
                                        final color = settled ? Colors.green : Colors.redAccent;
                                        return Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700));
                                      },
                                    )
                                  : Text(currency.format(remainDebt)),
                              width: wRemain,
                              alignment: Alignment.centerRight,
                            ),
                            _tableCell(
                              Text(supplierName ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                              width: wSupplier,
                            ),
                            _tableCell(
                              Text(note ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                              width: wNote,
                            ),
                            _tableCell(
                              docUploading
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : IconButton(
                                      tooltip: 'Chứng từ',
                                      onPressed: () => _showDocActions(row: r),
                                      icon: Icon(
                                        docUploaded ? Icons.verified_outlined : Icons.description_outlined,
                                        color: docUploaded ? Colors.green : null,
                                      ),
                                    ),
                              width: wDoc,
                              alignment: Alignment.center,
                            ),
                            _tableCell(
                              assignedOrder
                                  ? IconButton(
                                      tooltip: 'Mở đơn',
                                      icon: const Icon(Icons.receipt_long),
                                      onPressed: () async {
                                        final changed = await Navigator.push<bool>(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => PurchaseOrderDetailScreen(
                                              purchaseOrderId: purchaseOrderId,
                                            ),
                                          ),
                                        );
                                        if (!mounted) return;
                                        if (changed == true) {
                                          await context.read<ProductProvider>().load();
                                          await context.read<DebtProvider>().load();
                                        }
                                        setState(() {
                                          _orderDebtInfoCache.clear();
                                        });
                                      },
                                    )
                                  : IconButton(
                                      tooltip: 'Tạo đơn nhanh',
                                      icon: const Icon(Icons.receipt_long_outlined),
                                      onPressed: purchaseId.isEmpty
                                          ? null
                                          : () async {
                                              final orderId = await DatabaseService.instance
                                                  .quickCreateOrderForPurchaseHistoryRow(purchaseHistoryId: purchaseId);
                                              if (!mounted) return;
                                              if (orderId == null || orderId.trim().isEmpty) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('Không thể tạo đơn')),
                                                );
                                                return;
                                              }
                                              final changed = await Navigator.push<bool>(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => PurchaseOrderDetailScreen(purchaseOrderId: orderId),
                                                ),
                                              );
                                              if (!mounted) return;
                                              if (changed == true) {
                                                await context.read<ProductProvider>().load();
                                                await context.read<DebtProvider>().load();
                                              }
                                              setState(() {
                                                _orderDebtInfoCache.clear();
                                              });
                                            },
                                    ),
                              width: wOrder,
                              alignment: Alignment.center,
                            ),
                            _tableCell(
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    tooltip: 'Sửa',
                                    icon: const Icon(Icons.edit_outlined, size: 18),
                                    onPressed: () async {
                                      await _editPurchaseDialog(r);
                                      if (!mounted) return;
                                      setState(() {});
                                    },
                                  ),
                                  IconButton(
                                    tooltip: 'Xóa',
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                    onPressed: () async {
                                      await _deletePurchase(r);
                                      if (!mounted) return;
                                      setState(() {});
                                    },
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

  bool _looksLikeLocalPurchaseDocPath(String? fileIdOrPath) {
    final s = (fileIdOrPath ?? '').trim();
    return s.startsWith('purchase_docs/') || s.startsWith('purchase_docs\\');
  }

  Future<String?> _ensurePurchaseDocLocal({
    required String purchaseId,
    String? fileIdFromDb,
  }) async {
    final existing = (fileIdFromDb ?? '').trim();
    if (existing.isEmpty) return null;
    if (_looksLikeLocalPurchaseDocPath(existing)) return existing;

    // Legacy: Drive fileId (old versions uploaded jpg)
    final token = await _getDriveToken();
    if (token == null) return null;

    final bytes = await DriveSyncService().downloadFile(accessToken: token, fileId: existing);
    final dir = await getTemporaryDirectory();
    final tmp = File('${dir.path}/$purchaseId');
    await tmp.writeAsBytes(bytes, flush: true);

    final rel = await DocumentStorageService.instance.savePurchaseDoc(
      purchaseId: purchaseId,
      sourcePath: tmp.path,
      extension: '.jpg',
    );
    await DatabaseService.instance.markPurchaseDocUploaded(purchaseId: purchaseId, fileId: rel);
    return rel;
  }

  Future<void> _deletePurchaseDoc({required String purchaseId, String? fileIdFromDb}) async {
    final existing = (fileIdFromDb ?? '').trim();
    if (existing.isEmpty) {
      await DatabaseService.instance.clearPurchaseDoc(purchaseId: purchaseId);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy chứng từ để xóa')),
      );
      return;
    }

    if (_looksLikeLocalPurchaseDocPath(existing)) {
      await DocumentStorageService.instance.delete(existing);
    }
    await DatabaseService.instance.clearPurchaseDoc(purchaseId: purchaseId);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã xóa chứng từ')),
    );
  }

  Future<void> _showDocActions({
    required Map<String, dynamic> row,
  }) async {
    final purchaseId = row['id'] as String;
    final uploaded = (row['purchaseDocUploaded'] as int?) == 1;
    final fileId = (row['purchaseDocFileId'] as String?)?.trim();
    final uploading = _docUploading.contains(purchaseId);

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
                        await _uploadPurchaseDoc(purchaseId: purchaseId);
                      },
              ),
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('Xem chứng từ'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _openPurchaseDoc(purchaseId: purchaseId, fileIdFromDb: fileId);
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Tải chứng từ'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _downloadPurchaseDoc(purchaseId: purchaseId);
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
                    await _deletePurchaseDoc(purchaseId: purchaseId, fileIdFromDb: fileId);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<Product?> _showProductPicker() async {
    final products = context.read<ProductProvider>().products;
    if (products.isEmpty) return null;
    return showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final TextEditingController searchController = TextEditingController();
        List<Product> filteredProducts = List.from(products);

        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              padding: const EdgeInsets.all(16),
              height: MediaQuery.of(context).size.height * 0.8,
              child: Column(
                children: [
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      labelText: 'Tìm kiếm sản phẩm',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          searchController.clear();
                          setState(() {
                            filteredProducts = List.from(products);
                          });
                        },
                      ),
                    ),
                    onChanged: (value) {
                      if (value.isEmpty) {
                        setState(() {
                          filteredProducts = List.from(products);
                        });
                      } else {
                        final query = value.toLowerCase();
                        setState(() {
                          filteredProducts = products.where((product) {
                            final nameMatch = product.name.toLowerCase().contains(query);
                            final barcodeMatch = product.barcode?.toLowerCase().contains(query) ?? false;
                            return nameMatch || barcodeMatch;
                          }).toList();
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: filteredProducts.isEmpty
                        ? const Center(child: Text('Không tìm thấy sản phẩm nào'))
                        : ListView.builder(
                            itemCount: filteredProducts.length,
                            itemBuilder: (context, index) {
                              final product = filteredProducts[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  radius: 20,
                                  backgroundColor: Colors.blue.withValues(alpha: 0.12),
                                  child: Builder(
                                    builder: (_) {
                                      final img = product.imagePath;
                                      if (img != null && img.trim().isNotEmpty) {
                                        return FutureBuilder<String?>(
                                          future: ProductImageService.instance.resolvePath(img),
                                          builder: (context, snap) {
                                            final full = snap.data;
                                            if (full == null || full.isEmpty) {
                                              return const Icon(Icons.shopping_bag);
                                            }
                                            return ClipOval(
                                              child: Image.file(
                                                File(full),
                                                width: 40,
                                                height: 40,
                                                fit: BoxFit.cover,
                                              ),
                                            );
                                          },
                                        );
                                      }
                                      return const Icon(Icons.shopping_bag);
                                    },
                                  ),
                                ),
                                title: Text(product.name),
                                subtitle: Text('${NumberFormat('#,##0').format(product.price)} đ'),
                                trailing: Text('Tồn: ${product.currentStock} ${product.unit}'),
                                onTap: () {
                                  Navigator.of(context).pop(product);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _editPurchaseDialog(Map<String, dynamic> row) async {
    var products = context.read<ProductProvider>().products;
    if (products.isEmpty) return;

    String selectedProductId = (row['productId'] as String?) ?? products.first.id;
    DateTime createdAt = DateTime.tryParse((row['createdAt'] as String?) ?? '') ?? DateTime.now();
    final initialQty = (row['quantity'] as num?)?.toDouble() ?? 0;
    final initialUnitCost = (row['unitCost'] as num?)?.toDouble() ?? 0;
    final initialPaid = (row['paidAmount'] as num?)?.toDouble();
    bool oweAll = (initialPaid ?? 0) == 0;

    final qtyCtrl = TextEditingController(text: initialQty.toString());
    final unitCostCtrl = TextEditingController(text: initialUnitCost.toStringAsFixed(0));
    final paidAmountCtrl = TextEditingController(
      text: oweAll
          ? '0'
          : ((initialPaid != null && initialPaid > 0) ? initialPaid : (initialQty * initialUnitCost)).toStringAsFixed(0),
    );
    final noteCtrl = TextEditingController(text: (row['note'] as String?) ?? '');
    final supplierNameCtrl = TextEditingController(text: (row['supplierName'] as String?) ?? '');
    final supplierPhoneCtrl = TextEditingController(text: (row['supplierPhone'] as String?) ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) => AlertDialog(
          title: const Text('Sửa nhập hàng'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: createdAt,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (d == null) return;
                  final t = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(createdAt),
                  );
                  if (t == null) return;
                  createdAt = DateTime(d.year, d.month, d.day, t.hour, t.minute);
                  setStateDialog(() {});
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Ngày giờ nhập'),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          DateFormat('dd/MM/yyyy HH:mm').format(createdAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.edit_calendar_outlined, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: supplierNameCtrl,
                decoration: const InputDecoration(labelText: 'Nhà cung cấp (tuỳ chọn)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: supplierPhoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'SĐT nhà cung cấp (tuỳ chọn)'),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await _showProductPicker();
                  if (picked == null) return;
                  selectedProductId = picked.id;
                  unitCostCtrl.text = picked.costPrice.toStringAsFixed(0);
                  if (!oweAll) {
                    final q = (NumberInputFormatter.tryParse(qtyCtrl.text) ?? 0).toDouble();
                    paidAmountCtrl.text = (q * picked.costPrice).toStringAsFixed(0);
                  }
                  setStateDialog(() {});
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Sản phẩm'),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          () {
                            try {
                              return products.firstWhere((e) => e.id == selectedProductId).name;
                            } catch (_) {
                              return '';
                            }
                          }(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [NumberInputFormatter(maxDecimalDigits: 2)],
                onChanged: (_) {
                  if (!oweAll) {
                    final q = (NumberInputFormatter.tryParse(qtyCtrl.text) ?? 0).toDouble();
                    final uc = (NumberInputFormatter.tryParse(unitCostCtrl.text) ?? 0).toDouble();
                    paidAmountCtrl.text = (q * uc).toStringAsFixed(0);
                  }
                  setStateDialog(() {});
                },
                decoration: const InputDecoration(labelText: 'Số lượng'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: unitCostCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
                onChanged: (_) {
                  if (!oweAll) {
                    final q = (NumberInputFormatter.tryParse(qtyCtrl.text) ?? 0).toDouble();
                    final uc = (NumberInputFormatter.tryParse(unitCostCtrl.text) ?? 0).toDouble();
                    paidAmountCtrl.text = (q * uc).toStringAsFixed(0);
                  }
                  setStateDialog(() {});
                },
                decoration: const InputDecoration(labelText: 'Giá nhập / đơn vị'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: paidAmountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
                      decoration: const InputDecoration(labelText: 'Tiền thanh toán'),
                      enabled: !oweAll,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Nợ tất'),
                      Checkbox(
                        value: oweAll,
                        onChanged: (v) {
                          oweAll = v ?? false;
                          if (oweAll) {
                            paidAmountCtrl.text = '0';
                          } else {
                            final q = (NumberInputFormatter.tryParse(qtyCtrl.text) ?? 0).toDouble();
                            final uc = (NumberInputFormatter.tryParse(unitCostCtrl.text) ?? 0).toDouble();
                            paidAmountCtrl.text = (q * uc).toStringAsFixed(0);
                          }
                          setStateDialog(() {});
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: 'Ghi chú (tuỳ chọn)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lưu')),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final qty = (NumberInputFormatter.tryParse(qtyCtrl.text) ?? 0).toDouble();
    final unitCost = (NumberInputFormatter.tryParse(unitCostCtrl.text) ?? 0).toDouble();
    final paidAmount = oweAll ? 0.0 : (NumberInputFormatter.tryParse(paidAmountCtrl.text) ?? 0).toDouble();
    if (qty <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Số lượng không hợp lệ')));
      return;
    }

    late final Product selected;
    try {
      selected = products.firstWhere((p) => p.id == selectedProductId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sản phẩm không hợp lệ')));
      return;
    }

    await DatabaseService.instance.updatePurchaseHistory(
      id: (row['id'] as String),
      productId: selected.id,
      productName: selected.name,
      quantity: qty,
      unitCost: unitCost,
      paidAmount: paidAmount,
      supplierName: supplierNameCtrl.text.trim().isEmpty ? null : supplierNameCtrl.text.trim(),
      supplierPhone: supplierPhoneCtrl.text.trim().isEmpty ? null : supplierPhoneCtrl.text.trim(),
      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      createdAt: createdAt,
    );

    final purchaseId = (row['id'] as String);
    final totalCost = qty * unitCost;
    final debtInitialAmount = (totalCost - paidAmount).clamp(0.0, double.infinity).toDouble();
    final existingDebt = await DatabaseService.instance.getDebtBySource(sourceType: 'purchase', sourceId: purchaseId);
    if (existingDebt != null) {
      final alreadyPaidForDebt = await DatabaseService.instance.getTotalPaidForDebt(existingDebt.id);
      final newRemain = (debtInitialAmount - alreadyPaidForDebt).clamp(0.0, double.infinity).toDouble();
      final updatedDebt = Debt(
        id: existingDebt.id,
        createdAt: existingDebt.createdAt,
        type: DebtType.oweOthers,
        partyId: existingDebt.partyId,
        partyName: existingDebt.partyName,
        initialAmount: debtInitialAmount,
        amount: newRemain,
        description:
            'Nhập hàng: ${selected.name}, SL ${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2)} ${selected.unit}, Giá nhập ${unitCost.toStringAsFixed(0)}, Thành tiền ${totalCost.toStringAsFixed(0)}, Đã trả ${paidAmount.toStringAsFixed(0)}',
        settled: newRemain <= 0,
        sourceType: 'purchase',
        sourceId: purchaseId,
      );
      await DatabaseService.instance.updateDebt(updatedDebt);
      await context.read<DebtProvider>().load();
    } else if (debtInitialAmount > 0) {
      final supplierName = supplierNameCtrl.text.trim();
      final newDebt = Debt(
        type: DebtType.oweOthers,
        partyId: 'supplier_unknown',
        partyName: supplierName.isEmpty ? 'Nhà cung cấp' : supplierName,
        amount: debtInitialAmount,
        description:
            'Nhập hàng: ${selected.name}, SL ${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2)} ${selected.unit}, Giá nhập ${unitCost.toStringAsFixed(0)}, Thành tiền ${totalCost.toStringAsFixed(0)}, Đã trả ${paidAmount.toStringAsFixed(0)}',
        sourceType: 'purchase',
        sourceId: purchaseId,
      );
      await context.read<DebtProvider>().add(newDebt);
    }

    await context.read<ProductProvider>().load();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã cập nhật nhập hàng')));
  }

  Future<void> _deletePurchase(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xóa nhập hàng'),
        content: Text('Bạn có chắc muốn xóa "${row['productName'] ?? ''}" không?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (ok != true) return;
    await DatabaseService.instance.deletePurchaseHistory(row['id'] as String);
    await context.read<ProductProvider>().load();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa lịch sử nhập hàng')));
  }

  Future<List<Map<String, dynamic>>> _load() {
    return DatabaseService.instance.getPurchaseHistory(range: _range, query: _query);
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

  Future<void> _uploadPurchaseDoc({required String purchaseId}) async {
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

    if (action == null) return;

    if (mounted) {
      setState(() {
        _docUploading.add(purchaseId);
      });
    }

    try {
      String? relPath;

      if (action == 'camera') {
        final picker = ImagePicker();
        final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
        if (picked != null) {
          relPath = await DocumentStorageService.instance.savePurchaseDoc(
            purchaseId: purchaseId,
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
          relPath = await DocumentStorageService.instance.savePurchaseDoc(
            purchaseId: purchaseId,
            sourcePath: path,
          );
        }
      }

      if (relPath == null || relPath.trim().isEmpty) return;
      await DatabaseService.instance.markPurchaseDocUploaded(purchaseId: purchaseId, fileId: relPath);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu chứng từ vào ứng dụng')),
      );
      setState(() {});
    } finally {
      if (mounted) {
        setState(() {
          _docUploading.remove(purchaseId);
        });
      }
    }
  }

  Future<void> _openPurchaseDoc({required String purchaseId, String? fileIdFromDb}) async {
    final localRel = await _ensurePurchaseDocLocal(purchaseId: purchaseId, fileIdFromDb: fileIdFromDb);
    if (localRel == null || localRel.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có chứng từ cho phiếu nhập này')),
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

  Future<void> _downloadPurchaseDoc({required String purchaseId}) async {
    final row = await DatabaseService.instance.db.query(
      'purchase_history',
      columns: ['purchaseDocFileId'],
      where: 'id = ?',
      whereArgs: [purchaseId],
      limit: 1,
    );
    final fileIdOrPath = row.isNotEmpty ? (row.first['purchaseDocFileId'] as String?) : null;

    final localRel = await _ensurePurchaseDocLocal(purchaseId: purchaseId, fileIdFromDb: fileIdOrPath);
    if (localRel == null || localRel.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có chứng từ để tải')),
      );
      return;
    }

    final full = await DocumentStorageService.instance.resolvePath(localRel);
    if (full == null) return;
    await Share.shareXFiles([XFile(full)], text: 'Chứng từ nhập hàng: $purchaseId');
  }

  @override
  Widget build(BuildContext context) {
    final fmtDate = DateFormat('dd/MM/yyyy HH:mm');
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    final products = context.watch<ProductProvider>().products;
    final productById = {for (final p in products) p.id: p};

    final content = Column(
        children: [
          if (widget.embedded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const PurchaseOrderCreateScreen()),
                        );
                        if (!mounted) return;
                        await context.read<ProductProvider>().load();
                        await context.read<DebtProvider>().load();
                        setState(() {
                          _orderDebtInfoCache.clear();
                        });
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Nhập hàng'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: _isTableView ? 'Hiển thị dạng thẻ' : 'Hiển thị dạng bảng',
                    icon: Icon(_isTableView ? Icons.view_agenda_outlined : Icons.table_chart_outlined),
                    onPressed: () => setState(() => _isTableView = !_isTableView),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.filter_list),
                    label: const Text('Khoảng ngày'),
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
                  if (_range != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: 'Xoá lọc ngày',
                      onPressed: () => setState(() => _range = null),
                    ),
                  ],
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Tìm theo tên sản phẩm / nhà cung cấp / ghi chú',
                isDense: true,
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _load(),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snap.data ?? const [];
                if (rows.isEmpty) {
                  return const Center(child: Text('Chưa có lịch sử nhập hàng'));
                }

                if (_isTableView) {
                  return _buildTable(rows: rows, currency: currency, fmtDate: fmtDate);
                }

                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = rows[i];
                    final createdAt = DateTime.tryParse(r['createdAt'] as String? ?? '') ?? DateTime.now();
                    final name = (r['productName'] as String?) ?? '';
                    final pid = (r['productId'] as String?) ?? '';
                    final prod = pid.isEmpty ? null : productById[pid];
                    final qty = (r['quantity'] as num?)?.toDouble() ?? 0;
                    final unitCost = (r['unitCost'] as num?)?.toDouble() ?? 0;
                    final totalCost = (r['totalCost'] as num?)?.toDouble() ?? (qty * unitCost);
                    final paidAmount = (r['paidAmount'] as num?)?.toDouble() ?? 0;
                    final remainDebt = (totalCost - paidAmount).clamp(0.0, double.infinity).toDouble();
                    final note = (r['note'] as String?)?.trim();
                    final supplierName = (r['supplierName'] as String?)?.trim();
                    final docUploaded = (r['purchaseDocUploaded'] as int?) == 1;
                    final docUploading = _docUploading.contains(r['id'] as String);
                    final purchaseId = (r['id'] as String?) ?? '';
                    final purchaseOrderId = (r['purchaseOrderId'] as String?)?.trim();
                    final assignedOrder = purchaseOrderId != null && purchaseOrderId.isNotEmpty;

                    return ListTile(
                      dense: true,
                      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      onTap: () async {
                        await _editPurchaseDialog(r);
                        if (!mounted) return;
                        setState(() {});
                      },
                      leading: CircleAvatar(
                        backgroundColor: Colors.green.withValues(alpha: 0.12),
                        child: Builder(
                          builder: (_) {
                            final img = prod?.imagePath;
                            if (img != null && img.trim().isNotEmpty) {
                              return FutureBuilder<String?>(
                                future: ProductImageService.instance.resolvePath(img),
                                builder: (context, snap) {
                                  final full = snap.data;
                                  if (full == null || full.isEmpty) {
                                    return const Icon(Icons.add_shopping_cart, color: Colors.green);
                                  }
                                  return ClipOval(
                                    child: Image.file(
                                      File(full),
                                      width: 40,
                                      height: 40,
                                      fit: BoxFit.cover,
                                    ),
                                  );
                                },
                              );
                            }
                            return const Icon(Icons.add_shopping_cart, color: Colors.green);
                          },
                        ),
                      ),
                      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SL: ${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2)}  |  Giá: ${currency.format(unitCost)}  |  TT: ${currency.format(totalCost)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (assignedOrder)
                            FutureBuilder<_OrderDebtInfo>(
                              future: _orderDebtInfoFuture(purchaseOrderId),
                              builder: (context, snap) {
                                final info = snap.data;
                                final settled = info?.settled ?? true;
                                final paid = info?.paid ?? 0.0;
                                final remain = info?.remain ?? 0.0;
                                final text = settled
                                    ? 'Đơn: Đã tất toán'
                                    : 'Đơn: Đã trả: ${currency.format(paid)} | Còn: ${currency.format(remain)}';
                                final color = settled ? Colors.green : Colors.redAccent;
                                return Text(
                                  text,
                                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                                );
                              },
                            ),
                          if (!assignedOrder) ...[
                            Text('Đã trả: ${currency.format(paidAmount)}'),
                            if (remainDebt > 0)
                              FutureBuilder(
                                future: DatabaseService.instance.getDebtBySource(
                                  sourceType: 'purchase',
                                  sourceId: r['id'] as String,
                                ),
                                builder: (context, snap) {
                                  final d = snap.data;
                                  if (snap.connectionState != ConnectionState.done || d == null) {
                                    return Text(
                                      'Còn nợ: ${currency.format(remainDebt)}',
                                      style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
                                    );
                                  }

                                  return FutureBuilder<double>(
                                    future: DatabaseService.instance.getTotalPaidForDebt(d.id),
                                    builder: (context, paidSnap) {
                                      final paid = paidSnap.data ?? 0;
                                      final remain = d.amount;
                                      final settled = d.settled || remain <= 0;
                                      final text = settled
                                          ? 'Đã tất toán'
                                          : 'Đã trả: ${currency.format(paid)} | Còn: ${currency.format(remain)}';
                                      final color = settled ? Colors.green : Colors.redAccent;
                                      return Text(
                                        text,
                                        style: TextStyle(color: color, fontWeight: FontWeight.w600),
                                      );
                                    },
                                  );
                                },
                              ),
                            if (remainDebt <= 0)
                              const Text(
                                'Đã tất toán',
                                style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                              ),
                          ],
                          if (supplierName != null && supplierName.isNotEmpty)
                            Text('NCC: $supplierName', maxLines: 1, overflow: TextOverflow.ellipsis),
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
                          Row(
                            children: [
                              const Text('Đơn: '),
                              Text(
                                assignedOrder ? 'Đã gán' : 'Chưa gán',
                                style: TextStyle(
                                  color: assignedOrder ? Colors.green : Colors.black54,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          Text(fmtDate.format(createdAt), style: const TextStyle(color: Colors.black54)),
                          if (note != null && note.isNotEmpty) Text('Ghi chú: $note'),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: assignedOrder ? 'Mở đơn' : 'Tạo đơn nhanh',
                            onPressed: purchaseId.isEmpty
                                ? null
                                : () async {
                                    if (assignedOrder) {
                                      final changed = await Navigator.push<bool>(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => PurchaseOrderDetailScreen(purchaseOrderId: purchaseOrderId),
                                        ),
                                      );
                                      if (!mounted) return;
                                      if (changed == true) {
                                        await context.read<ProductProvider>().load();
                                        await context.read<DebtProvider>().load();
                                      }
                                      setState(() {
                                        _orderDebtInfoCache.clear();
                                      });
                                      return;
                                    }

                                    final orderId = await DatabaseService.instance
                                        .quickCreateOrderForPurchaseHistoryRow(purchaseHistoryId: purchaseId);
                                    if (!mounted) return;
                                    if (orderId == null || orderId.trim().isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Không thể tạo đơn')),
                                      );
                                      return;
                                    }
                                    final changed = await Navigator.push<bool>(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => PurchaseOrderDetailScreen(purchaseOrderId: orderId),
                                      ),
                                    );
                                    if (!mounted) return;
                                    if (changed == true) {
                                      await context.read<ProductProvider>().load();
                                      await context.read<DebtProvider>().load();
                                    }
                                    setState(() {
                                      _orderDebtInfoCache.clear();
                                    });
                                  },
                            icon: Icon(assignedOrder ? Icons.receipt_long : Icons.receipt_long_outlined),
                          ),
                          PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'doc') {
                                _showDocActions(row: r);
                              }
                              if (v == 'edit') {
                                await _editPurchaseDialog(r);
                              }
                              if (v == 'delete') {
                                await _deletePurchase(r);
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'edit', child: Text('Sửa')),
                              PopupMenuItem(
                                value: 'doc',
                                child: Row(
                                  children: [
                                    Icon(
                                      docUploaded ? Icons.verified_outlined : Icons.description_outlined,
                                      size: 18,
                                      color: docUploaded ? Colors.green : null,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text('Chứng từ'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(value: 'delete', child: Text('Xóa')),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử nhập hàng'),
        actions: [
          IconButton(
            tooltip: _isTableView ? 'Hiển thị dạng thẻ' : 'Hiển thị dạng bảng',
            icon: Icon(_isTableView ? Icons.view_agenda_outlined : Icons.table_chart_outlined),
            onPressed: () => setState(() => _isTableView = !_isTableView),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Nhập hàng',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PurchaseOrderCreateScreen()),
              );
              if (!mounted) return;
              await context.read<ProductProvider>().load();
              await context.read<DebtProvider>().load();
              setState(() {
                _orderDebtInfoCache.clear();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Chọn khoảng ngày',
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
              icon: const Icon(Icons.clear),
              tooltip: 'Xoá lọc ngày',
              onPressed: () => setState(() => _range = null),
            ),
        ],
      ),
      body: content,
    );
  }
}
