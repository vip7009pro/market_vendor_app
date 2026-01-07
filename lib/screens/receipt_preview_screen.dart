import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:barcode/barcode.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import '../models/sale.dart';
import '../services/database_service.dart';
import '../services/thermal_printer_service.dart';
import '../services/thermal_printer_settings_service.dart';
import '../models/thermal_printer_config.dart';
import 'printer_settings_screen.dart';

class ReceiptPreviewScreen extends StatefulWidget {
  final Sale sale;
  final NumberFormat currency;

  const ReceiptPreviewScreen({super.key, required this.sale, required this.currency});

  @override
  State<ReceiptPreviewScreen> createState() => _ReceiptPreviewScreenState();
}

class _ReceiptPreviewScreenState extends State<ReceiptPreviewScreen> {
  final Map<String, int> _paperSizes = {'Full': 0, '80mm': 40, '58mm': 32, 'A4 (Màu)': -1}; // Thêm 'Full' với 0 để flag
  String _selectedSize = 'A4 (Màu)'; // Default full luôn cho đại ca
  final _screenshotController = ScreenshotController();
  String _storeName = 'CỬA HÀNG ABC';
  String _storeAddress = 'Địa chỉ: 123 Đường XYZ';
  String _storePhone = 'Hotline: 090xxxxxxx';

  Future<void> _ensureBluetoothPermissions() async {
    if (!mounted) return;

    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();
    if (!scan.isGranted || !connect.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cần cấp quyền Bluetooth để in')),
      );
    }
  }

  Future<void> _printToThermal() async {
    final printers = await ThermalPrinterSettingsService.instance.loadPrinters();
    if (!mounted) return;

    if (printers.isEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Chưa có máy in'),
          content: const Text('Bạn cần thêm máy in (LAN/Bluetooth) trước khi in.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Đóng')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Thiết lập')),
          ],
        ),
      );

      if (go == true && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()),
        );
      }

      return;
    }

    final def = await ThermalPrinterSettingsService.instance.getDefaultPrinter();
    if (!mounted) return;

    final chosen = await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Chọn máy in', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: printers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final p = printers[i];
                    final isDefault = def?.id == p.id;
                    final subtitle = p.type == ThermalPrinterType.bluetooth
                        ? (p.macAddress.isEmpty ? 'Bluetooth' : p.macAddress)
                        : '${p.ip}:${p.port}';
                    return ListTile(
                      leading: Icon(isDefault ? Icons.check_circle : Icons.print_outlined),
                      title: Text(p.name),
                      subtitle: Text(subtitle),
                      onTap: () => Navigator.pop(ctx, p),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()),
                    );
                  },
                  icon: const Icon(Icons.settings),
                  label: const Text('Quản lý máy in'),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (chosen == null) return;

    if (chosen.type == ThermalPrinterType.bluetooth) {
      await _ensureBluetoothPermissions();
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đang in...')));
    try {
      await ThermalPrinterService.instance.printSaleReceipt(
        printerConfig: chosen,
        sale: widget.sale,
        currency: widget.currency,
        storeName: _storeName,
        storeAddress: _storeAddress,
        storePhone: _storePhone,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã gửi lệnh in')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi in: $e')));
    }
  }

  @override
  void initState() {
    super.initState();
    _loadStoreInfo();
  }

  Future<void> _loadStoreInfo() async {
    final row = await DatabaseService.instance.getStoreInfo();
    if (!mounted) return;
    setState(() {
      final name = (row?['name'] as String?)?.trim();
      final address = (row?['address'] as String?)?.trim();
      final phone = (row?['phone'] as String?)?.trim();
      _storeName = (name != null && name.isNotEmpty) ? name : 'CỬA HÀNG ABC';
      _storeAddress = (address != null && address.isNotEmpty) ? address : 'Địa chỉ: 123 Đường XYZ';
      _storePhone = (phone != null && phone.isNotEmpty) ? phone : 'Hotline: 090xxxxxxx';
    });
  }

  String _buildReceiptContent(Sale sale, NumberFormat currency, int columnWidth) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');
    final List<String> lines = [];

    String center(String text) => text.padLeft((columnWidth - text.length) ~/ 2 + text.length);

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
    lines.add('Khách hàng: ${sale.customerName?.trim().isNotEmpty == true ? sale.customerName!.trim() : 'Khách lẻ'}');
    lines.add('-' * columnWidth);

    final headerLeft = 'Mặt hàng';
    final headerRight = 'SL'.padLeft(4) + 'TT'.padLeft(6);
    lines.add(justify(headerLeft, headerRight));
    lines.add('-' * columnWidth);

    for (final item in sale.items) {
      lines.add((item.displayName ?? item.name).trim());
      final itemTotal = currency.format(item.unitPrice * item.quantity);
      final itemQuantity = item.quantity % 1 == 0 ? item.quantity.toInt().toString() : item.quantity.toString();
      final leftPart = currency.format(item.unitPrice);
      final rightPart = 'x $itemQuantity ${item.unit} = $itemTotal';
      lines.add(justify(leftPart, rightPart));
    }

    lines.add('-' * columnWidth);
    final totalQuantity = sale.items.fold<double>(0.0, (sum, item) => sum + item.quantity);
    lines.add('Tổng SL: ${totalQuantity % 1 == 0 ? totalQuantity.toInt() : totalQuantity}');
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

  Future<void> _shareAsImage() async {
    try {
      final imageBytes = await _screenshotController.capture();
      if (!mounted) return;

      if (imageBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lỗi: Không thể tạo ảnh hóa đơn.')),
        );
        return;
      }

      final tempDir = await getTemporaryDirectory();
      if (!mounted) return;

      final file = await File('${tempDir.path}/invoice.png').create();
      await file.writeAsBytes(imageBytes);
      DateTime now = DateTime.now();
      String formattedDate = DateFormat('dd/MM/yyyy HH:mm:ss').format(now);
      await Share.shareXFiles([XFile(file.path)], text: 'Hóa đơn bán hàng ngày $formattedDate');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã xảy ra lỗi khi chia sẻ: $e')),
      );
    }
  }

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
                  pw.Text(receiptContent, style: pw.TextStyle(font: ttfFont, fontSize: 8)),
                  pw.SizedBox(height: 12),
                  pw.Center(
                    child: pw.BarcodeWidget(
                      barcode: Barcode.qrCode(),
                      data: widget.sale.id,
                      width: 110,
                      height: 110,
                      drawText: false,
                    ),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi khi tạo PDF: $e')));
      debugPrint('Lỗi tạo PDF: $e');
    }
  }

  Future<void> _shareA4Pdf(Sale sale) async {
    final receiptContent = _buildReceiptContent(sale, widget.currency, 70);
    await _sharePdf(receiptContent);
  }

  Widget _buildA4ColorPreview() {
    final sale = widget.sale;
    final customerName = sale.customerName?.trim().isNotEmpty == true ? sale.customerName!.trim() : 'Khách lẻ';
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    const primary = Color(0xFFD61F1F);
    const headerBg = Color(0xFFFFF4F4);
    const border = Color(0xFFB7C7E6);

    final tableRows = <TableRow>[
      TableRow(
        decoration: const BoxDecoration(color: headerBg),
        children: const [
          Padding(
            padding: EdgeInsets.all(6),
            child: Text('#', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: EdgeInsets.all(6),
            child: Text('Sản phẩm', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: EdgeInsets.all(6),
            child: Text('ĐVT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          ),
          Padding(
            padding: EdgeInsets.all(6),
            child: Text('SL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.right),
          ),
          Padding(
            padding: EdgeInsets.all(6),
            child: Text('Đơn giá', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.right),
          ),
          Padding(
            padding: EdgeInsets.all(6),
            child: Text('Thành tiền', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.right),
          ),
        ],
      ),
    ];

    for (var i = 0; i < sale.items.length; i++) {
      final it = sale.items[i];
      final qtyStr = it.quantity % 1 == 0 ? it.quantity.toInt().toString() : it.quantity.toString();
      final total = it.unitPrice * it.quantity;
      tableRows.add(
        TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text('${i + 1}', style: const TextStyle(fontSize: 11)),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text((it.displayName ?? it.name).trim(), style: const TextStyle(fontSize: 11)),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text(it.unit, style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text(qtyStr, style: const TextStyle(fontSize: 11), textAlign: TextAlign.right),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text(widget.currency.format(it.unitPrice), style: const TextStyle(fontSize: 11), textAlign: TextAlign.right),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text(widget.currency.format(total), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.right),
            ),
          ],
        ),
      );
    }

    return Container(
      width: 650,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _storeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primary),
                    ),
                    const SizedBox(height: 4),
                    Text(_storeAddress, style: const TextStyle(fontSize: 11)),
                    Text(_storePhone, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: headerBg,
                  border: Border.all(color: primary, width: 0.8),
                ),
                child: Text(dateFormat.format(sale.createdAt), style: const TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: headerBg,
              border: Border.all(color: primary, width: 0.8),
            ),
            child: Row(
              children: [
                Text('Mã hóa đơn: ', style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w600)),
                Expanded(
                  child: Text(
                    sale.id,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 64,
                  height: 64,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: border, width: 0.8),
                  ),
                  child: QrImageView(data: sale.id, version: QrVersions.auto, gapless: true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: primary, width: 0.8), bottom: BorderSide(color: primary, width: 0.8)),
            ),
            child: Column(
              children: [
                Text('HÓA ĐƠN BÁN HÀNG', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primary)),
                const SizedBox(height: 2),
                const Text('(Sales Invoice)', style: TextStyle(fontSize: 10, color: Color(0xFF666666))),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text('Khách hàng: $customerName', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          if (sale.note?.trim().isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Ghi chú: ${sale.note!.trim()}', style: const TextStyle(fontSize: 11, color: Color(0xFF444444))),
            ),
          const SizedBox(height: 10),
          Table(
            border: TableBorder.all(color: border, width: 0.8),
            columnWidths: const {
              0: FixedColumnWidth(30),
              1: FlexColumnWidth(4),
              2: FixedColumnWidth(40),
              3: FixedColumnWidth(40),
              4: FixedColumnWidth(80),
              5: FixedColumnWidth(90),
            },
            children: tableRows,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 280,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: headerBg,
                  border: Border.all(color: border, width: 0.8),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Tạm tính', style: TextStyle(fontSize: 12)),
                        Text(widget.currency.format(sale.subtotal), style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                    if (sale.discount > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Giảm giá', style: TextStyle(fontSize: 12)),
                          Text('-${widget.currency.format(sale.discount)}', style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Container(height: 1, color: border),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('TỔNG CỘNG', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        Text(widget.currency.format(sale.total), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Đã thanh toán', style: TextStyle(fontSize: 12)),
                        Text(widget.currency.format(sale.paidAmount), style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                    if (sale.debt > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Còn nợ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: primary)),
                          Text(widget.currency.format(sale.debt), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: primary)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Cảm ơn quý khách và hẹn gặp lại!', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Color(0xFF666666))),
        ],
      ),
    );
  }

  Widget _dashedLine({required double width}) {
    return SizedBox(
      width: width,
      child: const Text(
        '================================',
        maxLines: 1,
        overflow: TextOverflow.clip,
        textAlign: TextAlign.center,
        style: TextStyle(fontFamily: 'monospace', color: Colors.black87),
      ),
    );
  }

  Widget _buildThermalReceiptPreview({required bool is58mm}) {
    final sale = widget.sale;
    final currency = widget.currency;
    final customerName = sale.customerName?.trim().isNotEmpty == true ? sale.customerName!.trim() : 'Khách lẻ';
    final dateFormat = DateFormat('dd/MM/yy HH:mm');

    final width = is58mm ? 250.0 : 300.0;
    final base = is58mm ? 11.0 : 12.0;
    final small = is58mm ? 10.0 : 11.0;
    final qrSize = is58mm ? 86.0 : 110.0;
    final paddingH = is58mm ? 8.0 : 10.0;

    final totalItems = sale.items.length;
    final totalQty = sale.items.fold<double>(0.0, (p, it) => p + it.quantity);

    Text t(String s, {double? size, FontWeight? w, TextAlign? align, Color? c, int? maxLines}) {
      return Text(
        s,
        maxLines: maxLines,
        overflow: maxLines == null ? TextOverflow.visible : TextOverflow.ellipsis,
        textAlign: align,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: size ?? base,
          fontWeight: w,
          color: c ?? Colors.black,
          height: 1.2,
        ),
      );
    }

    Text t1(String s, {double? size, FontWeight? w, TextAlign? align, Color? c}) {
      return t(s, size: size, w: w, align: align, c: c, maxLines: 1);
    }

    Widget kv(String k, String v) {
      return Row(
        children: [
          Expanded(child: t1(k, size: small, c: Colors.black87)),
          const SizedBox(width: 6),
          t1(v, size: small, w: FontWeight.w700),
        ],
      );
    }

    Widget moneyRow(String label, double amount, {bool bold = false}) {
      return Row(
        children: [
          Expanded(child: t1(label, size: base, w: bold ? FontWeight.w800 : FontWeight.w600)),
          t1(currency.format(amount), size: base, w: bold ? FontWeight.w900 : FontWeight.w700),
        ],
      );
    }

    return Container(
      width: width,
      padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withAlpha(35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(18),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: qrSize,
                height: qrSize,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black.withAlpha(35)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: QrImageView(
                  data: sale.id,
                  version: QrVersions.auto,
                  gapless: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    t(_storeName, size: is58mm ? 14 : 16, w: FontWeight.w900, maxLines: 2),
                    const SizedBox(height: 4),
                    if (_storePhone.trim().isNotEmpty) t(_storePhone, size: small, c: Colors.black87, maxLines: 2),
                    if (_storeAddress.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      t(_storeAddress, size: small, c: Colors.black87, maxLines: 2),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _dashedLine(width: width),
          const SizedBox(height: 10),
          t('HÓA ĐƠN BÁN HÀNG', size: is58mm ? 13 : 14, w: FontWeight.w900, align: TextAlign.center),
          const SizedBox(height: 8),
          kv('Mã:', sale.id),
          const SizedBox(height: 2),
          kv('Ngày:', dateFormat.format(sale.createdAt)),
          const SizedBox(height: 2),
          kv('Khách:', customerName),
          const SizedBox(height: 10),
          _dashedLine(width: width),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(flex: 7, child: t1('Đơn giá', size: small, w: FontWeight.w900)),
              Expanded(flex: 2, child: t1('SL', size: small, w: FontWeight.w900, align: TextAlign.right)),
              Expanded(flex: 3, child: t1('T.tiền', size: small, w: FontWeight.w900, align: TextAlign.right)),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < sale.items.length; i++) ...[
            Builder(
              builder: (ctx) {
                final it = sale.items[i];
                final qtyStr = it.quantity % 1 == 0 ? it.quantity.toInt().toString() : it.quantity.toString();
                final total = it.unitPrice * it.quantity;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    t('${i + 1}. ${(it.displayName ?? it.name).trim()}', size: base, w: FontWeight.w700, maxLines: is58mm ? 2 : null),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          flex: 7,
                          child: t1(currency.format(it.unitPrice), size: base, c: Colors.black87),
                        ),
                        Expanded(
                          flex: 2,
                          child: t1('x$qtyStr', size: base, align: TextAlign.right, c: Colors.black87),
                        ),
                        Expanded(
                          flex: 3,
                          child: t1(currency.format(total), size: base, align: TextAlign.right, w: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                );
              },
            ),
          ],
          _dashedLine(width: width),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: t1('Tổng $totalItems SP', size: base, w: FontWeight.w700)),
              t1('SL: ${totalQty % 1 == 0 ? totalQty.toInt() : totalQty}', size: base, w: FontWeight.w700),
            ],
          ),
          const SizedBox(height: 6),
          moneyRow('Tổng', sale.total, bold: true),
          const SizedBox(height: 6),
          moneyRow('Khách đã trả', sale.paidAmount),
          if (sale.debt > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: t('Còn nợ', size: base, w: FontWeight.w900, c: Colors.black)),
                t(currency.format(sale.debt), size: base, w: FontWeight.w900),
              ],
            ),
          ],
          const SizedBox(height: 10),
          _dashedLine(width: width),
          const SizedBox(height: 10),
          t('Thanh toán tiền mặt hoặc chuyển khoản', size: small, align: TextAlign.center, c: Colors.black54),
        ],
      ),
    );
  }

  // --- HÀM XỬ lý sự kiện nhấn nút In (ĐÃ SỬA LẠI) ---
  Future<void> _handlePrintAction(String receiptContent) async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('In máy in nhiệt (LAN/Bluetooth)'),
              onTap: () {
                Navigator.pop(ctx);
                _printToThermal();
              },
            ),
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('Chia sẻ dạng ảnh (PNG)'),
              onTap: () {
                Navigator.pop(ctx); // Đóng BottomSheet
                _shareAsImage(); // Gọi hàm chia sẻ ảnh
              },
            ),
            ListTile(
              leading: const Icon(Icons.print),
              title: const Text('Chia sẻ PDF (in từ share)'),
              onTap: () {
                Navigator.pop(ctx); // Đóng BottomSheet
                _selectedSize == 'A4 (Màu)'
                    ? _shareA4Pdf(widget.sale)
                    : _sharePdf(receiptContent); // Gọi hàm share PDF
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Thiết lập máy in'),
              onTap: () async {
                Navigator.pop(ctx);
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PrinterSettingsScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    int columnWidth;

    if (_selectedSize == 'A4 (Màu)') {
      columnWidth = 70;
    } else if (_selectedSize == 'Full') {
      // Full screen: Tính columnWidth động dựa trên screen (giả sử monospace char ~8px)
      columnWidth = (screenWidth / 8).round().clamp(50, 80); // 50-80 chars để fit đẹp
    } else {
      columnWidth = _paperSizes[_selectedSize]!;
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
              child: _selectedSize == 'A4 (Màu)'
                  ? Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: _buildA4ColorPreview(),
                      ),
                    )
                  : Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: _buildThermalReceiptPreview(is58mm: _selectedSize == '58mm'),
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