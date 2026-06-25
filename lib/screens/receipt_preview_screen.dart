import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
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

  const ReceiptPreviewScreen({
    super.key,
    required this.sale,
    required this.currency,
  });

  @override
  State<ReceiptPreviewScreen> createState() => _ReceiptPreviewScreenState();
}

class _ReceiptPreviewScreenState extends State<ReceiptPreviewScreen> {
  final Map<String, int> _paperSizes = {'A4 (Màu)': -1, '80mm': 40, '58mm': 32};
  String _selectedSize = 'A4 (Màu)';
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
    final printers =
        await ThermalPrinterSettingsService.instance.loadPrinters();
    if (!mounted) return;

    if (printers.isEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder:
            (_) => AlertDialog(
              title: const Text('Chưa có máy in'),
              content: const Text(
                'Bạn cần thêm máy in (LAN/Bluetooth) trước khi in.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Đóng'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Thiết lập'),
                ),
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

    final def =
        await ThermalPrinterSettingsService.instance.getDefaultPrinter();
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
                child: Text(
                  'Chọn máy in',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: printers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final p = printers[i];
                    final isDefault = def?.id == p.id;
                    final subtitle =
                        p.type == ThermalPrinterType.bluetooth
                            ? (p.macAddress.isEmpty
                                ? 'Bluetooth'
                                : p.macAddress)
                            : '${p.ip}:${p.port}';
                    return ListTile(
                      leading: Icon(
                        isDefault ? Icons.check_circle : Icons.print_outlined,
                      ),
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
                      MaterialPageRoute(
                        builder: (_) => const PrinterSettingsScreen(),
                      ),
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Đang in...')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã gửi lệnh in')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi in: $e')));
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
      _storeAddress =
          (address != null && address.isNotEmpty)
              ? address
              : 'Địa chỉ: 123 Đường XYZ';
      _storePhone =
          (phone != null && phone.isNotEmpty) ? phone : 'Hotline: 090xxxxxxx';
    });
  }

  Future<void> _shareAsImage() async {
    try {
      final imageBytes = await _screenshotController.capture(
        delay: const Duration(milliseconds: 200),
        pixelRatio: 2.0,
      );

      if (!mounted) return;

      if (imageBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lỗi: Không thể chụp ảnh hóa đơn.')),
        );
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final file =
          await File('${tempDir.path}/hoadon_${widget.sale.id}.png').create();
      await file.writeAsBytes(imageBytes);

      DateTime now = DateTime.now();
      String formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(now);
      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'Hóa đơn bán hàng ngày $formattedDate');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Đã xảy ra lỗi khi chia sẻ: $e')));
    }
  }

  Future<void> _shareProfessionalPdf() async {
    try {
      final fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      final ttfFont = pw.Font.ttf(fontData);

      final pdf = pw.Document();
      final sale = widget.sale;
      final shortId =
          sale.id.length > 12
              ? sale.id.substring(sale.id.length - 12)
              : sale.id;
      final customerName =
          sale.customerName?.trim().isNotEmpty == true
              ? sale.customerName!.trim()
              : 'Khách lẻ';
      final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

      const primaryColor = PdfColor.fromInt(0xFFD61F1F);
      const headerBg = PdfColor.fromInt(0xFFFFF4F4);
      const borderColor = PdfColor.fromInt(0xFFB7C7E6);
      const textColor = PdfColor.fromInt(0xFF000000);
      const greyColor = PdfColor.fromInt(0xFF666666);

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) {
            return [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        _storeName,
                        style: pw.TextStyle(
                          font: ttfFont,
                          fontSize: 22,
                          color: primaryColor,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        _storeAddress,
                        style: pw.TextStyle(
                          font: ttfFont,
                          fontSize: 12,
                          color: textColor,
                        ),
                      ),
                      pw.Text(
                        _storePhone,
                        style: pw.TextStyle(
                          font: ttfFont,
                          fontSize: 12,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: pw.BoxDecoration(
                      color: headerBg,
                      border: pw.Border.all(color: primaryColor, width: 1),
                    ),
                    child: pw.Text(
                      dateFormat.format(sale.createdAt),
                      style: pw.TextStyle(font: ttfFont, fontSize: 12),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: headerBg,
                  border: pw.Border.all(color: primaryColor, width: 1),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'HÓA ĐƠN BÁN HÀNG',
                          style: pw.TextStyle(
                            font: ttfFont,
                            fontSize: 20,
                            color: primaryColor,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Mã HD: $shortId',
                          style: pw.TextStyle(
                            font: ttfFont,
                            fontSize: 12,
                            color: primaryColor,
                          ),
                        ),
                        pw.SizedBox(height: 8),
                        pw.Text(
                          'Khách hàng: $customerName',
                          style: pw.TextStyle(font: ttfFont, fontSize: 12),
                        ),
                        if (sale.note?.trim().isNotEmpty == true)
                          pw.Text(
                            'Ghi chú: ${sale.note!.trim()}',
                            style: pw.TextStyle(
                              font: ttfFont,
                              fontSize: 12,
                              color: greyColor,
                            ),
                          ),
                      ],
                    ),
                    pw.Container(
                      width: 70,
                      height: 70,
                      padding: const pw.EdgeInsets.all(4),
                      decoration: pw.BoxDecoration(
                        color: const PdfColor(1, 1, 1),
                        border: pw.Border.all(color: borderColor, width: 1),
                      ),
                      child: pw.BarcodeWidget(
                        barcode: pw.Barcode.qrCode(),
                        data: sale.id,
                        drawText: false,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              pw.TableHelper.fromTextArray(
                headers: [
                  '#',
                  'Sản phẩm',
                  'ĐVT',
                  'SL',
                  'Đơn giá',
                  'Thành tiền',
                ],
                data: List<List<String>>.generate(sale.items.length, (index) {
                  final it = sale.items[index];
                  final qtyStr =
                      it.quantity % 1 == 0
                          ? it.quantity.toInt().toString()
                          : it.quantity.toString();
                  return [
                    '${index + 1}',
                    (it.displayName ?? it.name).trim(),
                    it.unit,
                    qtyStr,
                    widget.currency.format(it.unitPrice),
                    widget.currency.format(it.unitPrice * it.quantity),
                  ];
                }),
                border: pw.TableBorder.all(color: borderColor, width: 1),
                headerStyle: pw.TextStyle(
                  font: ttfFont,
                  fontSize: 12,
                  color: textColor,
                ),
                headerDecoration: const pw.BoxDecoration(color: headerBg),
                cellStyle: pw.TextStyle(
                  font: ttfFont,
                  fontSize: 12,
                  color: textColor,
                ),
                cellAlignments: {
                  0: pw.Alignment.center,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.center,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.centerRight,
                },
                columnWidths: {
                  0: const pw.FixedColumnWidth(30),
                  1: const pw.FlexColumnWidth(4),
                  2: const pw.FixedColumnWidth(50),
                  3: const pw.FixedColumnWidth(40),
                  4: const pw.FixedColumnWidth(80),
                  5: const pw.FixedColumnWidth(90),
                },
              ),
              pw.SizedBox(height: 20),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Container(
                  width: 250,
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: headerBg,
                    border: pw.Border.all(color: borderColor, width: 1),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Tạm tính:',
                            style: pw.TextStyle(font: ttfFont, fontSize: 12),
                          ),
                          pw.Text(
                            widget.currency.format(sale.subtotal),
                            style: pw.TextStyle(font: ttfFont, fontSize: 12),
                          ),
                        ],
                      ),
                      if (sale.discount > 0) ...[
                        pw.SizedBox(height: 4),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'Giảm giá:',
                              style: pw.TextStyle(font: ttfFont, fontSize: 12),
                            ),
                            pw.Text(
                              '-${widget.currency.format(sale.discount)}',
                              style: pw.TextStyle(font: ttfFont, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                      pw.SizedBox(height: 8),
                      pw.Divider(color: borderColor),
                      pw.SizedBox(height: 8),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'TỔNG CỘNG:',
                            style: pw.TextStyle(
                              font: ttfFont,
                              fontSize: 14,
                              color: primaryColor,
                            ),
                          ),
                          pw.Text(
                            widget.currency.format(sale.total),
                            style: pw.TextStyle(
                              font: ttfFont,
                              fontSize: 14,
                              color: primaryColor,
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 4),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Đã thanh toán:',
                            style: pw.TextStyle(font: ttfFont, fontSize: 12),
                          ),
                          pw.Text(
                            widget.currency.format(sale.paidAmount),
                            style: pw.TextStyle(font: ttfFont, fontSize: 12),
                          ),
                        ],
                      ),
                      if (sale.debt > 0) ...[
                        pw.SizedBox(height: 4),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'Còn nợ:',
                              style: pw.TextStyle(
                                font: ttfFont,
                                fontSize: 12,
                                color: primaryColor,
                              ),
                            ),
                            pw.Text(
                              widget.currency.format(sale.debt),
                              style: pw.TextStyle(
                                font: ttfFont,
                                fontSize: 12,
                                color: primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              pw.SizedBox(height: 30),
              pw.Center(
                child: pw.Text(
                  'Cảm ơn quý khách và hẹn gặp lại!',
                  style: pw.TextStyle(
                    font: ttfFont,
                    fontSize: 12,
                    color: greyColor,
                  ),
                ),
              ),
            ];
          },
        ),
      );

      final pdfBytes = await pdf.save();
      if (!mounted) return;

      final tempDir = await getTemporaryDirectory();
      final file = await File('${tempDir.path}/hoadon_${sale.id}.pdf').create();
      await file.writeAsBytes(pdfBytes);

      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'Hóa đơn bán hàng #${sale.id}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi khi tạo PDF: $e')));
    }
  }

  Widget _buildA4ColorPreview() {
    final sale = widget.sale;
    final shortId =
        sale.id.length > 12 ? sale.id.substring(sale.id.length - 12) : sale.id;
    final customerName =
        sale.customerName?.trim().isNotEmpty == true
            ? sale.customerName!.trim()
            : 'Khách lẻ';
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    const primary = Color(0xFFD61F1F);
    const headerBg = Color(0xFFFFF4F4);
    const border = Color(0xFFB7C7E6);

    final tableRows = <TableRow>[
      TableRow(
        decoration: const BoxDecoration(color: headerBg),
        children: const [
          Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              '#',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Sản phẩm',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'ĐVT',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'SL',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Đơn giá',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ),
          Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Thành tiền',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    ];

    for (var i = 0; i < sale.items.length; i++) {
      final it = sale.items[i];
      final qtyStr =
          it.quantity % 1 == 0
              ? it.quantity.toInt().toString()
              : it.quantity.toString();
      final total = it.unitPrice * it.quantity;
      tableRows.add(
        TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('${i + 1}', style: const TextStyle(fontSize: 12)),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                (it.displayName ?? it.name).trim(),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                it.unit,
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                qtyStr,
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.right,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                widget.currency.format(it.unitPrice),
                style: const TextStyle(fontSize: 12),
                textAlign: TextAlign.right,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                widget.currency.format(total),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: 700,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: border, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
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
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(_storeAddress, style: const TextStyle(fontSize: 13)),
                    Text(_storePhone, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: headerBg,
                  border: Border.all(color: primary, width: 1),
                ),
                child: Text(
                  dateFormat.format(sale.createdAt),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: headerBg,
              border: Border.all(color: primary, width: 1),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'HÓA ĐƠN BÁN HÀNG',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Mã HD: $shortId',
                        style: const TextStyle(
                          fontSize: 12,
                          color: primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Khách hàng: $customerName',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (sale.note?.trim().isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Ghi chú: ${sale.note!.trim()}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF666666),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  width: 80,
                  height: 80,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: border, width: 1),
                  ),
                  child: QrImageView(
                    data: sale.id,
                    version: QrVersions.auto,
                    gapless: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Table(
            border: TableBorder.all(color: border, width: 1),
            columnWidths: const {
              0: FixedColumnWidth(40),
              1: FlexColumnWidth(4),
              2: FixedColumnWidth(60),
              3: FixedColumnWidth(50),
              4: FixedColumnWidth(100),
              5: FixedColumnWidth(110),
            },
            children: tableRows,
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 320,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: headerBg,
                  border: Border.all(color: border, width: 1),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Tạm tính', style: TextStyle(fontSize: 14)),
                        Text(
                          widget.currency.format(sale.subtotal),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                    if (sale.discount > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Giảm giá',
                            style: TextStyle(fontSize: 14),
                          ),
                          Text(
                            '-${widget.currency.format(sale.discount)}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Container(height: 1, color: border),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TỔNG CỘNG',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: primary,
                          ),
                        ),
                        Text(
                          widget.currency.format(sale.total),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Đã thanh toán',
                          style: TextStyle(fontSize: 14),
                        ),
                        Text(
                          widget.currency.format(sale.paidAmount),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                    if (sale.debt > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Còn nợ',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: primary,
                            ),
                          ),
                          Text(
                            widget.currency.format(sale.debt),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Cảm ơn quý khách và hẹn gặp lại!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF666666)),
          ),
        ],
      ),
    );
  }

  Widget _dashedLine({required double width}) {
    return SizedBox(
      width: width,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final boxWidth = constraints.constrainWidth();
          const dashWidth = 4.0;
          const dashHeight = 1.0;
          final dashCount = (boxWidth / (2 * dashWidth)).floor();
          return Flex(
            direction: Axis.horizontal,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(dashCount, (_) {
              return const SizedBox(
                width: dashWidth,
                height: dashHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black54),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _buildThermalReceiptPreview({required bool is58mm}) {
    final sale = widget.sale;
    final shortId =
        sale.id.length > 12 ? sale.id.substring(sale.id.length - 12) : sale.id;
    final currency = widget.currency;
    final customerName =
        sale.customerName?.trim().isNotEmpty == true
            ? sale.customerName!.trim()
            : 'Khách lẻ';
    final dateFormat = DateFormat('dd/MM/yy HH:mm');

    final width = is58mm ? 300.0 : 380.0;
    final base = is58mm ? 13.0 : 14.0;
    final small = is58mm ? 12.0 : 13.0;
    final qrSize = is58mm ? 80.0 : 90.0;
    final paddingH = is58mm ? 16.0 : 20.0;

    final totalItems = sale.items.length;
    final totalQty = sale.items.fold<double>(0.0, (p, it) => p + it.quantity);

    Text t(
      String s, {
      double? size,
      FontWeight? w,
      TextAlign? align,
      Color? c,
      int? maxLines,
    }) {
      return Text(
        s,
        maxLines: maxLines,
        overflow:
            maxLines == null ? TextOverflow.visible : TextOverflow.ellipsis,
        textAlign: align,
        style: TextStyle(
          fontSize: size ?? base,
          fontWeight: w ?? FontWeight.normal,
          color: c ?? Colors.black87,
          height: 1.4,
        ),
      );
    }

    Text t1(
      String s, {
      double? size,
      FontWeight? w,
      TextAlign? align,
      Color? c,
    }) {
      return t(s, size: size, w: w, align: align, c: c, maxLines: 1);
    }

    Widget kv(String k, String v) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          t(k, size: small, c: Colors.black54),
          const SizedBox(width: 8),
          Expanded(
            child: t(
              v,
              size: small,
              w: FontWeight.w600,
              align: TextAlign.right,
            ),
          ),
        ],
      );
    }

    Widget moneyRow(String label, double amount, {bool bold = false}) {
      return Row(
        children: [
          Expanded(
            child: t1(
              label,
              size: base,
              w: bold ? FontWeight.bold : FontWeight.w500,
            ),
          ),
          t1(
            currency.format(amount),
            size: base,
            w: bold ? FontWeight.bold : FontWeight.w600,
          ),
        ],
      );
    }

    return Container(
      width: width,
      padding: EdgeInsets.symmetric(horizontal: paddingH, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300, width: 1),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 12,
            offset: Offset(0, 6),
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
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: QrImageView(
                  data: sale.id,
                  version: QrVersions.auto,
                  gapless: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    t(
                      _storeName,
                      size: is58mm ? 16 : 18,
                      w: FontWeight.bold,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 4),
                    if (_storePhone.trim().isNotEmpty)
                      t(
                        _storePhone,
                        size: small,
                        c: Colors.black54,
                        maxLines: 2,
                      ),
                    if (_storeAddress.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      t(
                        _storeAddress,
                        size: small,
                        c: Colors.black54,
                        maxLines: 2,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _dashedLine(width: width),
          const SizedBox(height: 16),
          t(
            'HÓA ĐƠN BÁN HÀNG',
            size: is58mm ? 16 : 18,
            w: FontWeight.bold,
            align: TextAlign.center,
          ),
          const SizedBox(height: 12),
          kv('Mã HD:', shortId),
          const SizedBox(height: 4),
          kv('Ngày:', dateFormat.format(sale.createdAt)),
          const SizedBox(height: 4),
          kv('Khách hàng:', customerName),
          const SizedBox(height: 16),
          _dashedLine(width: width),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 7,
                child: t1('Sản phẩm', size: small, w: FontWeight.bold),
              ),
              Expanded(
                flex: 2,
                child: t1(
                  'SL',
                  size: small,
                  w: FontWeight.bold,
                  align: TextAlign.center,
                ),
              ),
              Expanded(
                flex: 4,
                child: t1(
                  'Thành tiền',
                  size: small,
                  w: FontWeight.bold,
                  align: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < sale.items.length; i++) ...[
            Builder(
              builder: (ctx) {
                final it = sale.items[i];
                final qtyStr =
                    it.quantity % 1 == 0
                        ? it.quantity.toInt().toString()
                        : it.quantity.toString();
                final total = it.unitPrice * it.quantity;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      t(
                        '${i + 1}. ${(it.displayName ?? it.name).trim()}',
                        size: base,
                        w: FontWeight.w600,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            flex: 7,
                            child: t1(
                              currency.format(it.unitPrice),
                              size: base,
                              c: Colors.black54,
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: t1(
                              'x$qtyStr',
                              size: base,
                              align: TextAlign.center,
                              c: Colors.black54,
                            ),
                          ),
                          Expanded(
                            flex: 4,
                            child: t1(
                              currency.format(total),
                              size: base,
                              align: TextAlign.right,
                              w: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 4),
          _dashedLine(width: width),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: t1(
                  'Tổng cộng ${totalItems.toStringAsFixed(1)} SP',
                  size: base,
                  w: FontWeight.w500,
                ),
              ),
              t1(
                'SL: ${totalQty % 1 == 0 ? totalQty.toInt() : totalQty}',
                size: base,
                w: FontWeight.w500,
              ),
            ],
          ),
          const SizedBox(height: 10),
          moneyRow('Tạm tính', sale.subtotal),
          if (sale.discount > 0) ...[
            const SizedBox(height: 6),
            moneyRow('Giảm giá', -sale.discount),
          ],
          const SizedBox(height: 6),
          moneyRow('TỔNG CỘNG', sale.total, bold: true),
          const SizedBox(height: 6),
          moneyRow('Khách đã trả', sale.paidAmount),
          if (sale.debt > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: t(
                    'Còn nợ',
                    size: base,
                    w: FontWeight.bold,
                    c: Colors.red.shade700,
                  ),
                ),
                t(
                  currency.format(sale.debt),
                  size: base,
                  w: FontWeight.bold,
                  c: Colors.red.shade700,
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          _dashedLine(width: width),
          const SizedBox(height: 16),
          t(
            'Xin cảm ơn quý khách và hẹn gặp lại!',
            size: small,
            align: TextAlign.center,
            c: Colors.black54,
          ),
        ],
      ),
    );
  }

  Future<void> _handlePrintAction() async {
    await showModalBottomSheet(
      context: context,
      builder:
          (ctx) => SafeArea(
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
                    Navigator.pop(ctx);
                    _shareAsImage();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf),
                  title: const Text('Chia sẻ PDF (A4)'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _shareProfessionalPdf();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Thiết lập máy in'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PrinterSettingsScreen(),
                      ),
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
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Xem trước Hóa đơn'),
        actions: [
          DropdownButton<String>(
            value: _selectedSize,
            isDense: true,
            underline: const SizedBox.shrink(),
            items:
                _paperSizes.keys.map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text('Khổ: $value'),
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
            child: InteractiveViewer(
              constrained: false,
              boundaryMargin: const EdgeInsets.all(60),
              minScale: 0.1,
              maxScale: 3.0,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Center(
                  child: Screenshot(
                    controller: _screenshotController,
                    child: Container(
                      color: Colors.white,
                      child:
                          _selectedSize == 'A4 (Màu)'
                              ? _buildA4ColorPreview()
                              : _buildThermalReceiptPreview(
                                is58mm: _selectedSize == '58mm',
                              ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Đóng'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.share),
                    label: const Text('In / Chia sẻ'),
                    onPressed: _handlePrintAction,
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
