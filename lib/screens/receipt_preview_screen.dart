import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sale.dart';

class ReceiptPreviewScreen extends StatefulWidget {
  final Sale sale;
  final NumberFormat currency;

  const ReceiptPreviewScreen({super.key, required this.sale, required this.currency});

  @override
  State<ReceiptPreviewScreen> createState() => _ReceiptPreviewScreenState();
}

class _ReceiptPreviewScreenState extends State<ReceiptPreviewScreen> {
  final Map<String, int> _paperSizes = {'Full': 0, '80mm': 40, '57mm': 32}; // Thêm 'Full' với 0 để flag
  String _selectedSize = 'Full'; // Default full luôn cho đại ca
  final _screenshotController = ScreenshotController();
  String _storeName = 'CỬA HÀNG ABC';
  String _storeAddress = 'Địa chỉ: 123 Đường XYZ';
  String _storePhone = 'Hotline: 090xxxxxxx';

  @override
  void initState() {
    super.initState();
    _loadStoreInfo();
  }

  Future<void> _loadStoreInfo() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _storeName = prefs.getString('store_name') ?? 'CỬA HÀNG ABC';
        _storeAddress = prefs.getString('store_address') ?? 'Địa chỉ: 123 Đường XYZ';
        _storePhone = prefs.getString('store_phone') ?? 'Hotline: 090xxxxxxx';
      });
    }
  }

  String _buildReceiptContent(Sale sale, NumberFormat currency, int columnWidth) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');
    final List<String> lines = [];

    String center(String text) =>
        text.padLeft((columnWidth - text.length) ~/ 2 + text.length);

    String justify(String left, String right) {
      final totalLen = left.length + right.length;
      if (totalLen > columnWidth) {
        final maxLeftLength = columnWidth - right.length;
        if (maxLeftLength < 4) {
          return '$left\n${''.padLeft(columnWidth - right.length) + right}';
        }
        final trimLength = maxLeftLength - 3;
        if (trimLength <= 0 || left.length <= trimLength) {
          return left.padRight(columnWidth - right.length) + right;
        }
        final trimmedLeft = left.substring(0, trimLength) + '...';
        return trimmedLeft.padRight(columnWidth - right.length) + right;
      }
      return left.padRight(columnWidth - right.length) + right;
    }

    lines.add('=' * columnWidth);
    lines.add(center(_storeName));
    lines.add(center(_storeAddress));
    lines.add(center(_storePhone));
    lines.add('=' * columnWidth);
    lines.add(center('HÓA ĐƠN BÁN HÀNG'));
    lines.add(justify('Mã HD:', sale.id));
    lines.add(justify('Ngày:', dateFormat.format(sale.createdAt)));
    lines.add(
        'Khách hàng: ${sale.customerName?.trim().isNotEmpty == true ? sale.customerName!.trim() : 'Khách lẻ'}');
    lines.add('-' * columnWidth);

    final headerLeft = 'Mặt hàng';
    final headerRight = 'SL'.padLeft(4) + 'TT'.padLeft(6);
    lines.add(justify(headerLeft, headerRight));
    lines.add('-' * columnWidth);

    for (final item in sale.items) {
      lines.add(item.name);
      final itemTotal = currency.format(item.unitPrice * item.quantity);
      final itemQuantity = item.quantity % 1 == 0
          ? item.quantity.toInt().toString()
          : item.quantity.toString();
      final leftPart = currency.format(item.unitPrice);
      final rightPart = 'x $itemQuantity ${item.unit} = $itemTotal';
      lines.add(justify(leftPart, rightPart));
    }

    lines.add('-' * columnWidth);
    final totalQuantity =
        sale.items.fold<double>(0.0, (sum, item) => sum + item.quantity);
    lines.add(
        'Tổng SL: ${totalQuantity % 1 == 0 ? totalQuantity.toInt() : totalQuantity}');
    lines.add(justify('Tạm tính:', currency.format(sale.subtotal)));
    if (sale.discount > 0) {
      lines.add(justify('Giảm giá:', '-${currency.format(sale.discount)}'));
    }
    lines.add(justify('TỔNG CỘNG:', currency.format(sale.total)));
    lines.add(justify('Đã thanh toán:', currency.format(sale.paidAmount)));
    if (sale.debt > 0) {
      lines.add(justify('CÒN NỢ:', currency.format(sale.debt)));
    }
    lines.add('=' * columnWidth);
    lines.add(center('Cảm ơn quý khách và hẹn gặp lại!'));
    lines.add('=' * columnWidth);
    lines.add('');
    lines.add('');
    lines.add('');
    return lines.join('\n');
  }

  // --- HÀM XỬ lý sự kiện nhấn nút In (ĐÃ SỬA LẠI) ---
  Future<void> _handlePrintAction(String receiptContent) async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('Chia sẻ dạng ảnh (PNG)'),
              onTap: () {
                Navigator.pop(ctx); // Đóng BottomSheet
                _shareAsImage();    // Gọi hàm chia sẻ ảnh
              },
            ),
            ListTile(
              leading: const Icon(Icons.print),
              title: const Text('Chia sẻ PDF (in từ share)'),
              onTap: () {
                Navigator.pop(ctx); // Đóng BottomSheet
                _sharePdf(receiptContent); // Gọi hàm share PDF
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- HÀM Chụp ảnh và chia sẻ (ĐÃ SỬA LẠI) ---
  Future<void> _shareAsImage() async {
    try {
      final imageBytes = await _screenshotController.capture();
      if (!mounted) return;

      if (imageBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Lỗi: Không thể tạo ảnh hóa đơn.')));
        return;
      }
      final tempDir = await getTemporaryDirectory();
      if (!mounted) return;

      final file = await File('${tempDir.path}/invoice.png').create();
      await file.writeAsBytes(imageBytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Hóa đơn bán hàng');

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đã xảy ra lỗi khi chia sẻ: $e')));
    } finally {
      // Sau khi hoàn thành, có thể pop màn hình nếu đại ca muốn, nhưng em giữ nguyên để user tự back
    }
  }

  // --- HÀM Tạo PDF và share (THAY THẾ PRINTING) ---
  Future<void> _sharePdf(String receiptContent) async {
    try {
      final fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      if (!mounted) return;

      final ttfFont = pw.Font.ttf(fontData);
      final pdf = pw.Document();
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return <pw.Widget>[
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    receiptContent,
                    style: pw.TextStyle(font: ttfFont, fontSize: 8),
                  ),
                ],
              ),
            ];
          },
        ),
      );

      final pdfBytes = await pdf.save();
      if (!mounted) return;

      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/hoadon_${widget.sale.id}.pdf').create();
      await file.writeAsBytes(pdfBytes);

      await Share.shareXFiles([XFile(file.path)], text: 'Hóa đơn bán hàng #${widget.sale.id} (chọn "In" từ share để in)');

    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi tạo PDF: $e')));
      debugPrint("Lỗi tạo PDF: $e");
    } finally {
      // Tương tự, không tự pop, user tự back
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    int columnWidth;
    double? maxWidth; // Nullable để full khi cần

    if (_selectedSize == 'Full') {
      // Full screen: Tính columnWidth động dựa trên screen (giả sử monospace char ~8px)
      columnWidth = (screenWidth / 8).round().clamp(50, 80); // 50-80 chars để fit đẹp
      maxWidth = null; // Full width
    } else {
      columnWidth = _paperSizes[_selectedSize]!;
      maxWidth = _selectedSize == '80mm' ? 300.0 : 240.0;
    }

    final receiptContent = _buildReceiptContent(widget.sale, widget.currency, columnWidth);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Xem trước Hóa đơn POS'),
        actions: [
          // Chuyển dropdown từ title dialog sang action ở AppBar
          DropdownButton<String>(
            value: _selectedSize,
            isDense: true,
            underline: const SizedBox.shrink(),
            items: _paperSizes.keys.map((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text('Khổ giấy: $value'),
              );
            }).toList(),
            onChanged: (String? newValue) {
              if (newValue != null && mounted) {
                setState(() {
                  _selectedSize = newValue;
                });
              }
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Screenshot(
              controller: _screenshotController,
              child: Container(
                width: maxWidth ?? double.infinity, // Full nếu null
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black),
                  color: Colors.white,
                ),
                child: SingleChildScrollView( // Chỉ vertical scroll, bỏ horizontal vì full
                  child: Text(
                    receiptContent,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.2,
                      color: Colors.black,
                    ),
                    softWrap: true,
                  ),
                ),
              ),
            ),
          ),
          // Actions ở dưới body thay vì actions của dialog
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Đóng'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.print),
                    label: const Text('In / Chia sẻ'),
                    onPressed: () => _handlePrintAction(receiptContent),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}