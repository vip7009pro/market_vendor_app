import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:barcode/barcode.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import '../models/sale.dart';
import '../services/database_service.dart';

class ReceiptPreviewScreen extends StatefulWidget {
  final Sale sale;
  final NumberFormat currency;

  const ReceiptPreviewScreen({super.key, required this.sale, required this.currency});

  @override
  State<ReceiptPreviewScreen> createState() => _ReceiptPreviewScreenState();
}

class _ReceiptPreviewScreenState extends State<ReceiptPreviewScreen> {
  final Map<String, int> _paperSizes = {'Full': 0, '80mm': 40, '57mm': 32, 'A4 (Màu)': -1}; // Thêm 'Full' với 0 để flag
  String _selectedSize = 'A4 (Màu)'; // Default full luôn cho đại ca
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

  Future<void> _shareA4Pdf(Sale sale) async {
    try {
      final fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
      if (!mounted) return;

      final ttfFont = pw.Font.ttf(fontData);
      final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
      final pdf = pw.Document();

      pw.Widget cell(
        String text, {
        pw.TextAlign align = pw.TextAlign.left,
        bool bold = false,
        pw.EdgeInsets padding = const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        pw.BoxDecoration? decoration,
      }) {
        return pw.Container(
          padding: padding,
          decoration: decoration,
          child: pw.Text(
            text,
            textAlign: align,
            style: pw.TextStyle(
              font: ttfFont,
              fontSize: 9,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        );
      }

      final customerName = sale.customerName?.trim().isNotEmpty == true ? sale.customerName!.trim() : 'Khách lẻ';

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context context) {
            final rows = <pw.TableRow>[];
            rows.add(
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEAF2FF)),
                children: [
                  cell('STT', align: pw.TextAlign.center, bold: true),
                  cell('Tên hàng hóa, dịch vụ', bold: true),
                  cell('ĐVT', align: pw.TextAlign.center, bold: true),
                  cell('Số lượng', align: pw.TextAlign.right, bold: true),
                  cell('Đơn giá', align: pw.TextAlign.right, bold: true),
                  cell('Thành tiền', align: pw.TextAlign.right, bold: true),
                ],
              ),
            );

            for (var i = 0; i < sale.items.length; i++) {
              final it = sale.items[i];
              final qty = it.quantity % 1 == 0 ? it.quantity.toInt().toString() : it.quantity.toString();
              rows.add(
                pw.TableRow(
                  children: [
                    cell('${i + 1}', align: pw.TextAlign.center),
                    cell(it.name),
                    cell(it.unit, align: pw.TextAlign.center),
                    cell(qty, align: pw.TextAlign.right),
                    cell(widget.currency.format(it.unitPrice), align: pw.TextAlign.right),
                    cell(widget.currency.format(it.unitPrice * it.quantity), align: pw.TextAlign.right),
                  ],
                ),
              );
            }

            return <pw.Widget>[
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: const PdfColor.fromInt(0xFF2E6FD8), width: 1.2),
                ),
                padding: const pw.EdgeInsets.all(16),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.FittedBox(
                                fit: pw.BoxFit.scaleDown,
                                alignment: pw.Alignment.centerLeft,
                                child: pw.Text(
                                  _storeName,
                                  style: pw.TextStyle(
                                    font: ttfFont,
                                    fontSize: 16,
                                    fontWeight: pw.FontWeight.bold,
                                    color: const PdfColor.fromInt(0xFFD61F1F),
                                  ),
                                ),
                              ),
                              pw.SizedBox(height: 4),
                              pw.Text(_storeAddress, style: pw.TextStyle(font: ttfFont, fontSize: 9)),
                              pw.Text(_storePhone, style: pw.TextStyle(font: ttfFont, fontSize: 9)),
                            ],
                          ),
                        ),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: pw.BoxDecoration(
                            color: const PdfColor.fromInt(0xFFEAF2FF),
                            border: pw.Border.all(color: const PdfColor.fromInt(0xFF2E6FD8), width: 0.8),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.end,
                            children: [
                              pw.Text(
                                dateFormat.format(sale.createdAt),
                                style: pw.TextStyle(font: ttfFont, fontSize: 9),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 8),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: pw.BoxDecoration(
                        color: const PdfColor.fromInt(0xFFEAF2FF),
                        border: pw.Border.all(color: const PdfColor.fromInt(0xFF2E6FD8), width: 0.8),
                      ),
                      child: pw.Row(
                        children: [
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Text(
                                  'Mã hóa đơn',
                                  style: pw.TextStyle(font: ttfFont, fontSize: 8, color: const PdfColor.fromInt(0xFF2E6FD8)),
                                ),
                                pw.SizedBox(height: 2),
                                pw.Text(
                                  sale.id,
                                  style: pw.TextStyle(font: ttfFont, fontSize: 10, fontWeight: pw.FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          pw.SizedBox(width: 12),
                          pw.BarcodeWidget(
                            barcode: Barcode.qrCode(),
                            data: sale.id,
                            width: 64,
                            height: 64,
                            drawText: false,
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 12),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(vertical: 10),
                      decoration: pw.BoxDecoration(
                        border: pw.Border(
                          top: pw.BorderSide(color: const PdfColor.fromInt(0xFF2E6FD8), width: 0.8),
                          bottom: pw.BorderSide(color: const PdfColor.fromInt(0xFF2E6FD8), width: 0.8),
                        ),
                      ),
                      child: pw.Column(
                        children: [
                          pw.Text(
                            'HÓA ĐƠN BÁN HÀNG',
                            style: pw.TextStyle(
                              font: ttfFont,
                              fontSize: 15,
                              fontWeight: pw.FontWeight.bold,
                              color: const PdfColor.fromInt(0xFF2E6FD8),
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            '(Sales Invoice)',
                            style: pw.TextStyle(font: ttfFont, fontSize: 9, color: const PdfColor.fromInt(0xFF666666)),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 10),
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text('Khách hàng: $customerName', style: pw.TextStyle(font: ttfFont, fontSize: 10)),
                              if (sale.note?.trim().isNotEmpty == true)
                                pw.Padding(
                                  padding: const pw.EdgeInsets.only(top: 2),
                                  child: pw.Text('Ghi chú: ${sale.note!.trim()}', style: pw.TextStyle(font: ttfFont, fontSize: 9, color: const PdfColor.fromInt(0xFF444444))),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 10),
                    pw.Table(
                      border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFB7C7E6), width: 0.8),
                      columnWidths: {
                        0: const pw.FixedColumnWidth(30),
                        1: const pw.FlexColumnWidth(4),
                        2: const pw.FixedColumnWidth(40),
                        3: const pw.FixedColumnWidth(60),
                        4: const pw.FixedColumnWidth(70),
                        5: const pw.FixedColumnWidth(80),
                      },
                      children: rows,
                    ),
                    pw.SizedBox(height: 10),
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: pw.Container(),
                        ),
                        pw.Container(
                          width: 230,
                          child: pw.Column(
                            children: [
                              pw.Row(
                                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                children: [
                                  pw.Text('Tạm tính', style: pw.TextStyle(font: ttfFont, fontSize: 10)),
                                  pw.Text(widget.currency.format(sale.subtotal), style: pw.TextStyle(font: ttfFont, fontSize: 10)),
                                ],
                              ),
                              if (sale.discount > 0)
                                pw.Padding(
                                  padding: const pw.EdgeInsets.only(top: 3),
                                  child: pw.Row(
                                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                    children: [
                                      pw.Text('Giảm giá', style: pw.TextStyle(font: ttfFont, fontSize: 10, color: const PdfColor.fromInt(0xFFD61F1F))),
                                      pw.Text('-${widget.currency.format(sale.discount)}', style: pw.TextStyle(font: ttfFont, fontSize: 10, color: const PdfColor.fromInt(0xFFD61F1F))),
                                    ],
                                  ),
                                ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.only(top: 6),
                                child: pw.Container(
                                  padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                                  decoration: pw.BoxDecoration(
                                    color: const PdfColor.fromInt(0xFFEAF2FF),
                                    border: pw.Border.all(color: const PdfColor.fromInt(0xFF2E6FD8), width: 0.8),
                                  ),
                                  child: pw.Row(
                                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                    children: [
                                      pw.Text('TỔNG CỘNG:', style: pw.TextStyle(font: ttfFont, fontSize: 11, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF2E6FD8))),
                                      pw.Text(widget.currency.format(sale.total), style: pw.TextStyle(font: ttfFont, fontSize: 11, fontWeight: pw.FontWeight.bold, color: const PdfColor.fromInt(0xFF2E6FD8))),
                                    ],
                                  ),
                                ),
                              ),
                              pw.Padding(
                                padding: const pw.EdgeInsets.only(top: 6),
                                child: pw.Row(
                                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                  children: [
                                    pw.Text('Đã thanh toán', style: pw.TextStyle(font: ttfFont, fontSize: 10)),
                                    pw.Text(widget.currency.format(sale.paidAmount), style: pw.TextStyle(font: ttfFont, fontSize: 10)),
                                  ],
                                ),
                              ),
                              if (sale.debt > 0)
                                pw.Padding(
                                  padding: const pw.EdgeInsets.only(top: 3),
                                  child: pw.Row(
                                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                    children: [
                                      pw.Text('Còn nợ', style: pw.TextStyle(font: ttfFont, fontSize: 10, color: const PdfColor.fromInt(0xFFD61F1F), fontWeight: pw.FontWeight.bold)),
                                      pw.Text(widget.currency.format(sale.debt), style: pw.TextStyle(font: ttfFont, fontSize: 10, color: const PdfColor.fromInt(0xFFD61F1F), fontWeight: pw.FontWeight.bold)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 22),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Expanded(
                          child: pw.Column(
                            children: [
                              pw.Text('Người mua hàng', style: pw.TextStyle(font: ttfFont, fontSize: 10, fontWeight: pw.FontWeight.bold)),
                              pw.SizedBox(height: 40),
                              pw.Text('(Ký, ghi rõ họ tên)', style: pw.TextStyle(font: ttfFont, fontSize: 8, color: const PdfColor.fromInt(0xFF666666))),
                            ],
                          ),
                        ),
                        pw.SizedBox(width: 24),
                        pw.Expanded(
                          child: pw.Column(
                            children: [
                              pw.Text('Người bán hàng', style: pw.TextStyle(font: ttfFont, fontSize: 10, fontWeight: pw.FontWeight.bold)),
                              pw.SizedBox(height: 40),
                              pw.Text('(Ký, ghi rõ họ tên)', style: pw.TextStyle(font: ttfFont, fontSize: 8, color: const PdfColor.fromInt(0xFF666666))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
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

      await Share.shareXFiles([
        XFile(file.path)
      ], text: 'Hóa đơn bán hàng #${widget.sale.id} (chọn "In" từ share để in)');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi khi tạo PDF: $e')));
      debugPrint("Lỗi tạo PDF: $e");
    } finally {
    }
  }

  Widget _buildA4ColorPreview() {
    final sale = widget.sale;
    final customerName = sale.customerName?.trim().isNotEmpty == true ? sale.customerName!.trim() : 'Khách lẻ';
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final headerBg = const Color(0xFFEAF2FF);
    final primary = const Color(0xFF2E6FD8);
    final danger = const Color(0xFFD61F1F);

    Widget headerCell(String text, {TextAlign align = TextAlign.left}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        color: headerBg,
        child: Text(
          text,
          textAlign: align,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF1F3C70)),
        ),
      );
    }

    Widget cell(String text, {TextAlign align = TextAlign.left, bool bold = false, Color? color}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Text(
          text,
          textAlign: align,
          style: TextStyle(fontSize: 11, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color),
        ),
      );
    }

    final tableRows = <TableRow>[
      TableRow(
        decoration: const BoxDecoration(color: Color(0xFFEAF2FF)),
        children: [
          headerCell('STT', align: TextAlign.center),
          headerCell('Tên hàng hóa, dịch vụ'),
          headerCell('ĐVT', align: TextAlign.center),
          headerCell('Số lượng', align: TextAlign.right),
          headerCell('Đơn giá', align: TextAlign.right),
          headerCell('Thành tiền', align: TextAlign.right),
        ],
      ),
    ];

    for (var i = 0; i < sale.items.length; i++) {
      final it = sale.items[i];
      final qty = it.quantity % 1 == 0 ? it.quantity.toInt().toString() : it.quantity.toString();
      tableRows.add(
        TableRow(
          children: [
            cell('${i + 1}', align: TextAlign.center),
            cell(it.displayName ?? it.name), // Use displayName if available, otherwise fall back to name
            cell(it.unit, align: TextAlign.center),
            cell(qty, align: TextAlign.right),
            cell(widget.currency.format(it.unitPrice), align: TextAlign.right),
            cell(widget.currency.format(it.unitPrice * it.quantity), align: TextAlign.right),
          ],
        ),
      );
    }

    return Container(
      width: 420,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: primary, width: 1.2),
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
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _storeName,
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFD61F1F)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(_storeAddress, style: const TextStyle(fontSize: 11)),
                    Text(_storePhone, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: headerBg,
                  border: Border.all(color: primary, width: 0.8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(dateFormat.format(sale.createdAt), style: const TextStyle(fontSize: 11)),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: headerBg,
              border: Border.all(color: primary, width: 0.8),
            ),
            child: Row(
              children: [
                Text(
                  'Mã hóa đơn: ',
                  style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w600),
                ),
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
                    border: Border.all(color: const Color(0xFFB7C7E6), width: 0.8),
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
            border: TableBorder.all(color: const Color(0xFFB7C7E6), width: 0.8),
            columnWidths: const {
              0: FixedColumnWidth(30),
              1: FlexColumnWidth(4),
              2: FixedColumnWidth(40),
              3: FixedColumnWidth(60),
              4: FixedColumnWidth(70),
              5: FixedColumnWidth(80),
            },
            children: tableRows,
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 250,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Tạm tính', style: TextStyle(fontSize: 12)),
                      Text(widget.currency.format(sale.subtotal), style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                  if (sale.discount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Giảm giá', style: TextStyle(fontSize: 12, color: danger, fontWeight: FontWeight.w600)),
                          Text('-${widget.currency.format(sale.discount)}', style: TextStyle(fontSize: 12, color: danger, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: headerBg,
                      border: Border.all(color: primary, width: 0.8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('TỔNG CỘNG', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primary)),
                        Text(widget.currency.format(sale.total), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Đã thanh toán', style: TextStyle(fontSize: 12)),
                      Text(widget.currency.format(sale.paidAmount), style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                  if (sale.debt > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Còn nợ', style: TextStyle(fontSize: 12, color: danger, fontWeight: FontWeight.bold)),
                          Text(widget.currency.format(sale.debt), style: TextStyle(fontSize: 12, color: danger, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: const [
                    Text('Người mua hàng', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    SizedBox(height: 44),
                    Text('(Ký, ghi rõ họ tên)', style: TextStyle(fontSize: 10, color: Color(0xFF666666))),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: const [
                    Text('Người bán hàng', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    SizedBox(height: 44),
                    Text('(Ký, ghi rõ họ tên)', style: TextStyle(fontSize: 10, color: Color(0xFF666666))),
                  ],
                ),
              ),
            ],
          ),
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
      DateTime now = DateTime.now();
      String formattedDate = DateFormat('dd/MM/yyyy HH:mm:ss').format(now);
      await Share.shareXFiles([XFile(file.path)], text: 'Hóa đơn bán hàng ngày $formattedDate');

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
    double fontSize;

    if (_selectedSize == 'A4 (Màu)') {
      columnWidth = 70;
      maxWidth = null;
      fontSize = 12;
    } else if (_selectedSize == 'Full') {
      // Full screen: Tính columnWidth động dựa trên screen (giả sử monospace char ~8px)
      columnWidth = (screenWidth / 8).round().clamp(50, 80); // 50-80 chars để fit đẹp
      maxWidth = null; // Full width
      fontSize = 12;
    } else {
      columnWidth = _paperSizes[_selectedSize]!;
      maxWidth = _selectedSize == '80mm' ? 300.0 : 240.0;
      fontSize = _selectedSize == '80mm' ? 12 : 11;
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
                  : Container(
                      width: maxWidth ?? double.infinity, // Full nếu null
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.black),
                        color: Colors.white,
                      ),
                      child: SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Text(
                            receiptContent,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: fontSize,
                              height: 1.2,
                              color: Colors.black,
                            ),
                            softWrap: false,
                          ),
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