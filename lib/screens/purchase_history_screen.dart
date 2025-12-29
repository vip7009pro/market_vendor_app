import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

import '../models/product.dart';
import '../models/customer.dart';
import '../models/debt.dart';
import '../providers/customer_provider.dart';
import '../providers/debt_provider.dart';
import '../providers/product_provider.dart';
import '../providers/auth_provider.dart';
import '../services/database_service.dart';
import '../services/drive_sync_service.dart';
import '../services/document_storage_service.dart';
import '../services/product_image_service.dart';
import '../utils/contact_serializer.dart';
import '../utils/number_input_formatter.dart';
import '../utils/text_normalizer.dart';

class PurchaseHistoryScreen extends StatefulWidget {
  final bool embedded;

  const PurchaseHistoryScreen({
    super.key,
    this.embedded = false,
  });

  @override
  State<PurchaseHistoryScreen> createState() => _PurchaseHistoryScreenState();
}

class _PurchaseHistoryScreenState extends State<PurchaseHistoryScreen> {
  DateTimeRange? _range;
  String _query = '';

  final Set<String> _docUploading = <String>{};

  static const _prefLastSupplierName = 'purchase_last_supplier_name';
  static const _prefLastSupplierPhone = 'purchase_last_supplier_phone';

  String removeDiacritics(String str) {
    const withDiacritics = 'áàảãạăắằẳẵặâấầuẩẫậéèẻẽẹêếềểễệíìỉĩịóòỏõọôốồổỗộơớờởỡợúùủũụưứừửữựýỳỷỹỵđ';
    const withoutDiacritics = 'aaaaaăaaaaaaâaaaaaaeeeeeêeeeeeiiiiioooooôooooooơooooouuuuuưuuuuuyyyyyd';
    String result = str.toLowerCase();
    for (int i = 0; i < withDiacritics.length; i++) {
      result = result.replaceAll(withDiacritics[i], withoutDiacritics[i]);
    }

    return result;
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
    return await showModalBottomSheet<Product>(
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

  Future<Customer?> _ensureSupplier({required String supplierName, String? supplierPhone}) async {
    if (supplierName.trim().isEmpty) return null;
    final provider = context.read<CustomerProvider>();
    final normalized = TextNormalizer.normalize(supplierName);
    try {
      final existing = provider.customers.firstWhere(
        (c) => c.isSupplier && TextNormalizer.normalize(c.name) == normalized,
      );
      return existing;
    } catch (_) {
      final created = Customer(
        name: supplierName.trim(),
        phone: supplierPhone?.trim().isEmpty == true ? null : supplierPhone?.trim(),
        isSupplier: true,
      );
      await provider.add(created);
      await provider.load();
      return created;
    }
  }


  Future<Contact?> _showContactPicker(BuildContext context, List<Contact> contacts) async {
    final TextEditingController searchController = TextEditingController();
    List<Contact> filteredContacts = List.from(contacts);

    return await showModalBottomSheet<Contact>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
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
                      labelText: 'Tìm kiếm liên hệ',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          searchController.clear();
                          setState(() {
                            filteredContacts = List.from(contacts);
                          });
                        },
                      ),
                    ),
                    onChanged: (value) {
                      if (value.isEmpty) {
                        setState(() {
                          filteredContacts = List.from(contacts);
                        });
                      } else {
                        final query = value.toLowerCase();
                        setState(() {
                          filteredContacts = contacts.where((contact) {
                            final nameMatch = contact.displayName.toLowerCase().contains(query);
                            final phoneMatch = contact.phones.any(
                              (phone) => phone.number.contains(query),
                            );
                            return nameMatch || phoneMatch;
                          }).toList();
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: filteredContacts.isEmpty
                        ? const Center(
                            child: Text('Không tìm thấy liên hệ nào'),
                          )
                        : ListView.builder(
                            itemCount: filteredContacts.length,
                            itemBuilder: (context, index) {
                              final contact = filteredContacts[index];
                              return ListTile(
                                leading: contact.photo != null
                                    ? CircleAvatar(
                                        backgroundImage: MemoryImage(contact.photo!), 
                                        radius: 20,
                                      )
                                    : const CircleAvatar(
                                        child: Icon(Icons.person),
                                        radius: 20,
                                      ),
                                title: Text(contact.displayName),
                                subtitle: Text(
                                  contact.phones.isNotEmpty
                                      ? contact.phones.first.number
                                      : 'Không có SĐT',
                                ),
                                onTap: () {
                                  Navigator.of(context).pop(contact);
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

  Future<Product?> _addNewProductDialog() async {
    final nameCtrl = TextEditingController();
    final unitCtrl = TextEditingController(text: 'cái');
    final priceCtrl = TextEditingController(text: '0');
    final costPriceCtrl = TextEditingController(text: '0');
    final barcodeCtrl = TextEditingController();

    XFile? pickedImage;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) {
          return AlertDialog(
            title: const Text('Thêm sản phẩm'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 56,
                        height: 56,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Builder(
                            builder: (_) {
                              if (pickedImage != null) {
                                return Image.file(File(pickedImage!.path), fit: BoxFit.cover);
                              }
                              return const ColoredBox(
                                color: Color(0xFFEFEFEF),
                                child: Center(child: Icon(Icons.inventory_2_outlined)),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () async {
                                final x = await ImagePicker().pickImage(
                                  source: ImageSource.camera,
                                  imageQuality: 85,
                                );
                                if (x == null) return;
                                setStateDialog(() => pickedImage = x);
                              },
                              icon: const Icon(Icons.photo_camera),
                              label: const Text('Chụp'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final x = await ImagePicker().pickImage(
                                  source: ImageSource.gallery,
                                  imageQuality: 85,
                                );
                                if (x == null) return;
                                setStateDialog(() => pickedImage = x);
                              },
                              icon: const Icon(Icons.photo_library_outlined),
                              label: const Text('Chọn'),
                            ),
                            if (pickedImage != null)
                              TextButton.icon(
                                onPressed: () => setStateDialog(() => pickedImage = null),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Bỏ ảnh'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Tên sản phẩm')),
                  const SizedBox(height: 8),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
                    decoration: const InputDecoration(labelText: 'Giá bán'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: costPriceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [NumberInputFormatter(maxDecimalDigits: 0)],
                    decoration: const InputDecoration(labelText: 'Giá vốn'),
                  ),
                  const SizedBox(height: 8),
                  TextField(controller: unitCtrl, decoration: const InputDecoration(labelText: 'Đơn vị')),
                  const SizedBox(height: 8),
                  TextField(controller: barcodeCtrl, decoration: const InputDecoration(labelText: 'Mã vạch (tuỳ chọn)')),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Hủy')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Lưu')),
            ],
          );
        },
      ),
    );

    if (ok != true) return null;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return null;

    final provider = context.read<ProductProvider>();
    final newName = TextNormalizer.normalize(name);
    final duplicated = provider.products.any((p) => TextNormalizer.normalize(p.name) == newName);
    if (duplicated) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã tồn tại sản phẩm cùng tên')));
      return null;
    }

    final p = Product(
      name: name,
      price: NumberInputFormatter.tryParse(priceCtrl.text) ?? 0,
      costPrice: NumberInputFormatter.tryParse(costPriceCtrl.text) ?? 0,
      unit: unitCtrl.text.trim().isEmpty ? 'cái' : unitCtrl.text.trim(),
      barcode: barcodeCtrl.text.trim().isEmpty ? null : barcodeCtrl.text.trim(),
      currentStock: 0,
    );

    if (pickedImage != null) {
      final relPath = await ProductImageService.instance.saveFromXFile(
        source: pickedImage!,
        productId: p.id,
      );
      p.imagePath = relPath;
    }

    await provider.add(p);
    await context.read<ProductProvider>().load();
    return p;
  }

  Future<void> _addPurchaseDialog() async {
    var products = context.read<ProductProvider>().products;
    if (products.isEmpty) {
      final created = await _addNewProductDialog();
      if (created == null) return;
      products = context.read<ProductProvider>().products;
    }

    final prefs = await SharedPreferences.getInstance();
    final lastSupplierName = prefs.getString(_prefLastSupplierName);
    final lastSupplierPhone = prefs.getString(_prefLastSupplierPhone);

    String selectedProductId = products.first.id;
    final qtyCtrl = TextEditingController(text: '1');
    final unitCostCtrl = TextEditingController(text: products.first.costPrice.toStringAsFixed(0));
    final paidAmountCtrl = TextEditingController(text: (1 * products.first.costPrice).toStringAsFixed(0));
    bool oweAll = false;
    final noteCtrl = TextEditingController();
    final supplierNameCtrl = TextEditingController(text: lastSupplierName ?? '');
    final supplierPhoneCtrl = TextEditingController(text: lastSupplierPhone ?? '');

    List<Contact> allContacts = await ContactSerializer.loadContactsFromPrefs();
    if (allContacts.isEmpty) {
      try {
        final granted = await FlutterContacts.requestPermission();
        if (granted) {
          allContacts = await FlutterContacts.getContacts(withProperties: true, withPhoto: true);
          await ContactSerializer.saveContactsToPrefs(allContacts);
        }
      } catch (e) {
        debugPrint('Error getting contacts in purchase dialog: $e');
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) => AlertDialog(
          title: const Text('Nhập hàng'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: supplierNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nhà cung cấp (tuỳ chọn)',
                      ),
                      readOnly: true,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.contacts),
                    onPressed: () async {
                      final contact = await _showContactPicker(context, allContacts);
                      if (contact != null && mounted) {
                        supplierNameCtrl.text = contact.displayName;
                        supplierPhoneCtrl.text = contact.phones.isNotEmpty ? contact.phones.first.number : '';
                        setStateDialog(() {});
                      }
                    },
                    tooltip: 'Chọn từ danh bạ',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: supplierPhoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'SĐT nhà cung cấp (tuỳ chọn)',
                ),
                readOnly: true,
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
                decoration: InputDecoration(
                  labelText: () {
                    try {
                      final p = products.firstWhere((e) => e.id == selectedProductId);
                      return 'Số lượng (${p.unit})';
                    } catch (_) {
                      return 'Số lượng';
                    }
                  }(),
                ),
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
              const SizedBox(height: 8),
              Text(
                () {
                  try {
                    final p = products.firstWhere((e) => e.id == selectedProductId);
                    return 'Tồn hiện tại: ${p.currentStock.toStringAsFixed(p.currentStock % 1 == 0 ? 0 : 2)} ${p.unit}';
                  } catch (_) {
                    return 'Tồn hiện tại: 0';
                  }
                }(),
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final created = await _addNewProductDialog();
                if (created == null) return;
                products = context.read<ProductProvider>().products;
                selectedProductId = created.id;
                unitCostCtrl.text = created.costPrice.toStringAsFixed(0);
                setStateDialog(() {});
              },
              child: const Text('Thêm sản phẩm'),
            ),
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
      selected = context.read<ProductProvider>().products.firstWhere((p) => p.id == selectedProductId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sản phẩm không hợp lệ')));
      return;
    }

    final totalCost = qty * unitCost;
    final debtAmount = (totalCost - paidAmount).clamp(0.0, double.infinity).toDouble();
    Customer? supplier;
    if (debtAmount > 0) {
      final supplierName = supplierNameCtrl.text.trim();
      if (supplierName.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Vui lòng nhập nhà cung cấp khi có nợ')));
        return;
      }
      final supplierPhone = supplierPhoneCtrl.text.trim();
      supplier = await _ensureSupplier(
        supplierName: supplierName,
        supplierPhone: supplierPhone.isEmpty ? null : supplierPhone,
      );
    }

    final purchaseId = await DatabaseService.instance.insertPurchaseHistory(
      productId: selected.id,
      productName: selected.name,
      quantity: qty,
      unitCost: unitCost,
      paidAmount: paidAmount,
      supplierName: supplierNameCtrl.text.trim().isEmpty ? null : supplierNameCtrl.text.trim(),
      supplierPhone: supplierPhoneCtrl.text.trim().isEmpty ? null : supplierPhoneCtrl.text.trim(),
      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
    );

    if (debtAmount > 0) {
      final supplierName = supplierNameCtrl.text.trim();
      final debt = Debt(
        type: DebtType.oweOthers,
        partyId: supplier?.id ?? 'supplier_unknown',
        partyName: supplier?.name ?? (supplierName.isEmpty ? 'Nhà cung cấp' : supplierName),
        amount: debtAmount,
        description:
            'Nhập hàng: ${selected.name}, SL ${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2)} ${selected.unit}, Giá nhập ${unitCost.toStringAsFixed(0)}, Thành tiền ${totalCost.toStringAsFixed(0)}, Đã trả ${paidAmount.toStringAsFixed(0)}',
        sourceType: 'purchase',
        sourceId: purchaseId,
      );
      await context.read<DebtProvider>().add(debt);
    }

    await prefs.setString(_prefLastSupplierName, supplierNameCtrl.text.trim());
    await prefs.setString(_prefLastSupplierPhone, supplierPhoneCtrl.text.trim());

    await context.read<ProductProvider>().load();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã nhập hàng')));
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
                      onPressed: _addPurchaseDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Nhập hàng'),
                    ),
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

                    return ListTile(
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
                          Text('SL: ${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2)}  |  Giá nhập: ${currency.format(unitCost)}'),
                          Text('Thành tiền: ${currency.format(totalCost)}'),
                          Text('Thanh toán: ${currency.format(paidAmount)}'),
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
                          if (supplierName != null && supplierName.isNotEmpty) Text('NCC: $supplierName'),
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
                          Text(fmtDate.format(createdAt), style: const TextStyle(color: Colors.black54)),
                          if (note != null && note.isNotEmpty) Text('Ghi chú: $note'),
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
                                await _editPurchaseDialog(r);
                              }
                              if (v == 'delete') {
                                await _deletePurchase(r);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Sửa')),
                              PopupMenuItem(value: 'delete', child: Text('Xóa')),
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
            icon: const Icon(Icons.add),
            tooltip: 'Nhập hàng',
            onPressed: _addPurchaseDialog,
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
