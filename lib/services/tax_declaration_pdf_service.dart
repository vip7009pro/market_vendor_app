import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/tax_declaration.dart';

class TaxDeclarationPdfService {
  static const _fontRegularPath = 'assets/fonts/times.ttf';
  static const _fontBoldPath = 'assets/fonts/timesbd.ttf';

  static Future<Uint8List> buildPdf({
    required TaxDeclarationData data,
    List<List<String>> tableA = const [],
    List<List<String>> tableB = const [],
    List<List<String>> tableC = const [],
  }) async {
    final fontRegularData = await rootBundle.load(_fontRegularPath);
    final fontBoldData = await rootBundle.load(_fontBoldPath);
    final ttf = pw.Font.ttf(fontRegularData);
    final ttfBold = pw.Font.ttf(fontBoldData);

    final doc = pw.Document();

    pw.TextStyle st(double size, {bool bold = false}) {
      return pw.TextStyle(
        font: bold ? ttfBold : ttf,
        fontSize: size,
      );
    }

    pw.Widget checkbox(bool v) {
      return pw.Container(
        width: 10,
        height: 10,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black, width: 0.8)),
        child: v ? pw.Text('X', style: st(8, bold: true)) : pw.SizedBox(),
      );
    }

    pw.Widget lineText(String value, {double size = 10}) {
      final v = value.trim();
      return pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 1),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.6)),
        ),
        child: pw.Text(v.isEmpty ? ' ' : v, style: st(size)),
      );
    }

    pw.Widget rowLine(String label, String value, {double size = 10}) {
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Text(label, style: st(size, bold: true)),
          pw.SizedBox(width: 6),
          pw.Expanded(child: lineText(value, size: size)),
        ],
      );
    }

    pw.Widget rowLineFixed(String label, String value, {double size = 10, double labelWidth = 140}) {
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.SizedBox(width: labelWidth, child: pw.Text(label, style: st(size, bold: true))),
          pw.SizedBox(width: 6),
          pw.Expanded(child: lineText(value, size: size)),
        ],
      );
    }

    pw.Widget optionLine(bool v, String text) {
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          checkbox(v),
          pw.SizedBox(width: 6),
          pw.Expanded(child: pw.Text(text, style: st(10))),
        ],
      );
    }

    pw.Widget table({required List<String> header, required List<pw.TableRow> rows, required Map<int, pw.TableColumnWidth> widths}) {
      return pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
        columnWidths: widths,
        children: [
          pw.TableRow(
            children: [
              for (final h in header)
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  alignment: pw.Alignment.center,
                  child: pw.Text(h, style: st(9, bold: true), textAlign: pw.TextAlign.center),
                ),
            ],
          ),
          ...rows,
        ],
      );
    }

    pw.TableRow tr(List<String> cells, {List<pw.TextAlign>? align}) {
      return pw.TableRow(
        children: [
          for (var i = 0; i < cells.length; i++)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: pw.Text(
                cells[i],
                style: st(9),
                textAlign: (align != null && i < align.length) ? align[i] : pw.TextAlign.left,
              ),
            ),
        ],
      );
    }

    final pageTheme = pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(24, 24, 24, 24),
    );

    final page1 = pw.Page(
      pageTheme: pageTheme,
      build: (ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text('CỘNG HÒA XÃ HỘI CHỦ NGHĨA VIỆT NAM', style: st(11, bold: true), textAlign: pw.TextAlign.center),
            pw.Text('Độc lập - Tự do - Hạnh phúc', style: st(10, bold: true), textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 8),
            pw.Text('TỜ KHAI THUẾ ĐỐI VỚI HỘ KINH DOANH, CÁ NHÂN KINH DOANH', style: st(11, bold: true), textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 10),
            optionLine(data.hkDkCkNdKhoan, 'HKD, CNKD nộp thuế theo phương pháp khoán'),
            pw.SizedBox(height: 2),
            optionLine(data.ckNdPhatSinh, 'CNKD nộp thuế theo từng lần phát sinh'),
            pw.SizedBox(height: 2),
            optionLine(data.toChucCaNhanKhaiThay, 'Tổ chức, cá nhân khai thuế thay, nộp thuế thay'),
            pw.SizedBox(height: 2),
            optionLine(data.hkDkCkNdKeKhai, 'HKD, CNKD nộp thuế theo phương pháp kê khai'),
            pw.SizedBox(height: 2),
            optionLine(data.hkDkCkNdXacNhanDoanhThu, 'HKD, CNKD trong lĩnh vực ngành nghề có căn cứ xác định doanh thu theo xác nhận của cơ quan chức năng'),
            pw.SizedBox(height: 2),
            optionLine(data.hoKhoanChuyenDoi, 'Hộ khoán chuyển đổi phương pháp tính thuế'),
            pw.SizedBox(height: 10),
            pw.Text('[01] Kỳ tính thuế:', style: st(10, bold: true)),
            pw.SizedBox(height: 4),
            rowLineFixed(
              '[01a] Năm',
              '${data.kyTinhThue01aNam} (từ tháng ${data.kyTinhThue01aTuThang} đến tháng ${data.kyTinhThue01aDenThang})',
              size: 10,
              labelWidth: 85,
            ),
            pw.SizedBox(height: 4),
            rowLineFixed('[01b] Tháng', '${data.kyTinhThue01bThang} / ${data.kyTinhThue01bNam}', size: 10, labelWidth: 85),
            pw.SizedBox(height: 4),
            rowLineFixed(
              '[01c] Quý',
              '${data.kyTinhThue01cQuy} / ${data.kyTinhThue01cNam} (từ tháng ${data.kyTinhThue01cTuThang} đến tháng ${data.kyTinhThue01cDenThang})',
              size: 10,
              labelWidth: 85,
            ),
            pw.SizedBox(height: 4),
            rowLineFixed(
              '[01d] Lần phát sinh',
              '${data.kyTinhThue01dNgay}/${data.kyTinhThue01dThang}/${data.kyTinhThue01dNam}',
              size: 10,
              labelWidth: 120,
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              children: [
                pw.Text('[02] Lần đầu:', style: st(10, bold: true)),
                pw.SizedBox(width: 6),
                checkbox(data.lanDau02),
                pw.SizedBox(width: 18),
                pw.Text('[03] Bổ sung lần thứ:', style: st(10, bold: true)),
                pw.SizedBox(width: 6),
                pw.Expanded(child: lineText(data.boSungLanThu03, size: 10)),
              ],
            ),
            pw.SizedBox(height: 8),
            rowLine('[04] Người nộp thuế', data.nguoiNopThue04, size: 10),
            pw.SizedBox(height: 4),
            rowLine('[05] Tên cửa hàng/thương hiệu', data.tenCuaHang05, size: 10),
            pw.SizedBox(height: 4),
            rowLine('[06] Tài khoản ngân hàng', data.taiKhoanNganHang06, size: 10),
            pw.SizedBox(height: 4),
            rowLine('[07] Mã số thuế', data.maSoThue07, size: 10),
            pw.SizedBox(height: 4),
            pw.Row(
              children: [
                pw.Expanded(child: rowLine('[08] Ngành nghề kinh doanh', data.nganhNgheKinhDoanh08, size: 10)),
                pw.SizedBox(width: 12),
                pw.Text('[08a] Thay đổi:', style: st(10, bold: true)),
                pw.SizedBox(width: 6),
                checkbox(data.thayDoiThongTin08a),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              children: [
                pw.Expanded(child: rowLine('[09] Diện tích kinh doanh', data.dienTichKinhDoanh09, size: 10)),
                pw.SizedBox(width: 12),
                pw.Text('[09a] Đi thuê:', style: st(10, bold: true)),
                pw.SizedBox(width: 6),
                checkbox(data.diThue09a),
              ],
            ),
            pw.SizedBox(height: 4),
            rowLine('[10] Số lượng lao động sử dụng thường xuyên', data.soLuongLaoDong10, size: 10),
            pw.SizedBox(height: 4),
            pw.Row(
              children: [
                pw.Text('[11] Thời gian hoạt động trong ngày từ', style: st(10, bold: true)),
                pw.SizedBox(width: 6),
                pw.SizedBox(width: 60, child: lineText(data.thoiGianTuGio11, size: 10)),
                pw.SizedBox(width: 6),
                pw.Text('giờ đến', style: st(10, bold: true)),
                pw.SizedBox(width: 6),
                pw.SizedBox(width: 60, child: lineText(data.thoiGianDenGio11, size: 10)),
                pw.SizedBox(width: 6),
                pw.Text('giờ', style: st(10, bold: true)),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Row(
              children: [
                pw.Text('[12] Địa chỉ kinh doanh', style: st(10, bold: true)),
                pw.SizedBox(width: 12),
                pw.Text('[12a] Thay đổi:', style: st(10, bold: true)),
                pw.SizedBox(width: 6),
                checkbox(data.thayDoiThongTin12a),
                pw.SizedBox(width: 12),
                pw.Text('[12e] Chợ biên giới:', style: st(10, bold: true)),
                pw.SizedBox(width: 6),
                checkbox(data.kinhDoanhTaiChoBienGioi12e),
              ],
            ),
            pw.SizedBox(height: 4),
            rowLine('[12b] Số nhà/đường phố/xóm/ấp/thôn', data.soNhaDuongPho12b, size: 10),
            pw.SizedBox(height: 4),
            rowLine('[12c] Phường/Xã/Thị trấn', data.phuongXaThiTran12c, size: 10),
            pw.SizedBox(height: 4),
            rowLine('[12d] Quận/Huyện/Thị xã/Thành phố thuộc tỉnh', data.quanHuyenThiXa12d, size: 10),
            pw.SizedBox(height: 4),
            rowLine('[12đ] Tỉnh/Thành phố', data.tinhThanhPho12dd, size: 10),
            pw.SizedBox(height: 4),
            rowLine('[13a] Địa chỉ cư trú: Số nhà/đường phố/xóm/ấp/thôn', data.soNhaDuongPho13a, size: 10),
          ],
        );
      },
    );

    doc.addPage(page1);

    doc.addPage(
      pw.Page(
        pageTheme: pageTheme,
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              rowLine('[13b] Phường/Xã/Thị trấn', data.phuongXaThiTran13b, size: 10),
              pw.SizedBox(height: 4),
              rowLine('[13c] Quận/Huyện/Thị xã/Thành phố thuộc tỉnh', data.quanHuyenThiXa13c, size: 10),
              pw.SizedBox(height: 4),
              pw.Row(
                children: [
                  pw.Expanded(child: rowLine('[13d] Tỉnh/Thành phố', data.tinhThanhPho13d, size: 10)),
                  pw.SizedBox(width: 12),
                  pw.Expanded(child: rowLine('[14] Điện thoại', data.dienThoai14, size: 10)),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                children: [
                  pw.Expanded(child: rowLine('[15] Fax', data.fax15, size: 10)),
                  pw.SizedBox(width: 12),
                  pw.Expanded(child: rowLine('[16] Email', data.email16, size: 10)),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('[17] Văn bản ủy quyền khai thuế (nếu có):', style: st(10, bold: true)),
                  pw.SizedBox(width: 6),
                  pw.Expanded(child: lineText(data.vanBanUyQuyen17, size: 10)),
                ],
              ),
              pw.SizedBox(height: 4),
              rowLine('[18] Thông tin bổ sung', data.truongHopChuaDangKyThue18, size: 10),
              pw.SizedBox(height: 10),
              rowLine('[19] Tên đại lý thuế (nếu có)', data.daiLyThue19, size: 10),
              pw.SizedBox(height: 4),
              rowLine('[20] Mã số thuế', data.maSoThue20, size: 10),
              pw.SizedBox(height: 4),
              rowLine('[21] Hợp đồng đại lý thuế: Số', data.hopDongDaiLyThue21, size: 10),
              pw.SizedBox(height: 4),
              rowLine('[22] Tên của tổ chức khai thay (nếu có)', data.tenToChucKhaiThay22, size: 10),
              pw.SizedBox(height: 4),
              rowLine('[23] Mã số thuế', data.maSoThue23, size: 10),
              pw.SizedBox(height: 4),
              rowLine('[24] Địa chỉ', data.diaChi24, size: 10),
              pw.SizedBox(height: 4),
              pw.Row(
                children: [
                  pw.Expanded(child: rowLine('[25] Điện thoại', data.dienThoai25, size: 10)),
                  pw.SizedBox(width: 12),
                  pw.Expanded(child: rowLine('[26] Fax', data.fax26, size: 10)),
                  pw.SizedBox(width: 12),
                  pw.Expanded(child: rowLine('[27] Email', data.email27, size: 10)),
                ],
              ),
            ],
          );
        },
      ),
    );

    doc.addPage(
      pw.Page(
        pageTheme: pageTheme,
        build: (ctx) {
          final aRows = <pw.TableRow>[];
          if (tableA.isEmpty) {
            for (var i = 0; i < 4; i++) {
              aRows.add(tr(['${i + 1}', '', '', '', '', '', ''], align: [pw.TextAlign.center]));
            }
          } else {
            for (var i = 0; i < tableA.length; i++) {
              final r = tableA[i];
              aRows.add(tr([
                '${i + 1}',
                r.isNotEmpty ? r[0] : '',
                r.length > 1 ? r[1] : '',
                r.length > 2 ? r[2] : '',
                r.length > 3 ? r[3] : '',
                r.length > 4 ? r[4] : '',
                r.length > 5 ? r[5] : '',
              ]));
            }
          }

          final bRows = <pw.TableRow>[];
          if (tableB.isEmpty) {
            for (var i = 0; i < 3; i++) {
              bRows.add(tr(['${i + 1}', '', '', '', '', '', ''], align: [pw.TextAlign.center]));
            }
          } else {
            for (var i = 0; i < tableB.length; i++) {
              final r = tableB[i];
              bRows.add(tr([
                '${i + 1}',
                r.isNotEmpty ? r[0] : '',
                r.length > 1 ? r[1] : '',
                r.length > 2 ? r[2] : '',
                r.length > 3 ? r[3] : '',
                r.length > 4 ? r[4] : '',
                r.length > 5 ? r[5] : '',
              ]));
            }
          }

          final cRows = <pw.TableRow>[];
          final cCount = tableC.isEmpty ? 6 : tableC.length;
          for (var i = 0; i < cCount; i++) {
            final r = (tableC.isNotEmpty && i < tableC.length) ? tableC[i] : const <String>[];
            cRows.add(tr([
              '${i + 1}',
              r.isNotEmpty ? r[0] : '',
              r.length > 1 ? r[1] : '',
              r.length > 2 ? r[2] : '',
              r.length > 3 ? r[3] : '',
              r.length > 4 ? r[4] : '',
              r.length > 5 ? r[5] : '',
              r.length > 6 ? r[6] : '',
            ], align: [pw.TextAlign.center]));
          }

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text('A. KÊ KHAI THUẾ GIÁ TRỊ GIA TĂNG (GTGT), THUẾ THU NHẬP CÁ NHÂN (TNCN)', style: st(11, bold: true)),
              pw.SizedBox(height: 6),
              table(
                header: const ['STT', 'Nhóm ngành nghề', 'Mã chỉ tiêu', 'GTGT\nDT (a)', 'GTGT\nThuế (b)', 'TNCN\nDT (a)', 'TNCN\nThuế (b)'],
                rows: aRows,
                widths: {
                  0: const pw.FixedColumnWidth(28),
                  1: const pw.FlexColumnWidth(3.0),
                  2: const pw.FixedColumnWidth(50),
                  3: const pw.FixedColumnWidth(55),
                  4: const pw.FixedColumnWidth(55),
                  5: const pw.FixedColumnWidth(55),
                  6: const pw.FixedColumnWidth(55),
                },
              ),
              pw.SizedBox(height: 10),
              pw.Text('B. KÊ KHAI THUẾ TIÊU THỤ ĐẶC BIỆT (TTĐB)', style: st(11, bold: true)),
              pw.SizedBox(height: 6),
              table(
                header: const ['STT', 'Hàng hóa, dịch vụ', 'Mã chỉ tiêu', 'ĐVT', 'DT tính thuế', 'Thuế suất', 'Số thuế'],
                rows: bRows,
                widths: {
                  0: const pw.FixedColumnWidth(28),
                  1: const pw.FlexColumnWidth(3.0),
                  2: const pw.FixedColumnWidth(50),
                  3: const pw.FixedColumnWidth(40),
                  4: const pw.FixedColumnWidth(70),
                  5: const pw.FixedColumnWidth(55),
                  6: const pw.FixedColumnWidth(60),
                },
              ),
              pw.SizedBox(height: 10),
              pw.Text('C. KÊ KHAI THUẾ/PHÍ BẢO VỆ MÔI TRƯỜNG HOẶC THUẾ TÀI NGUYÊN', style: st(11, bold: true)),
              pw.SizedBox(height: 6),
              table(
                header: const ['STT', 'Tài nguyên/hàng hóa', 'Mã', 'ĐVT', 'SL', 'Giá tính thuế', 'Thuế suất', 'Số thuế'],
                rows: cRows,
                widths: {
                  0: const pw.FixedColumnWidth(28),
                  1: const pw.FlexColumnWidth(3.0),
                  2: const pw.FixedColumnWidth(40),
                  3: const pw.FixedColumnWidth(40),
                  4: const pw.FixedColumnWidth(45),
                  5: const pw.FixedColumnWidth(70),
                  6: const pw.FixedColumnWidth(55),
                  7: const pw.FixedColumnWidth(60),
                },
              ),
            ],
          );
        },
      ),
    );

    doc.addPage(
      pw.Page(
        pageTheme: pageTheme,
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.SizedBox(height: 8),
              pw.Text('Tôi cam đoan số liệu khai trên là đúng và chịu trách nhiệm trước pháp luật về những số liệu đã khai.', style: st(10)),
              pw.SizedBox(height: 16),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      children: [
                        pw.Text('NHÂN VIÊN ĐẠI LÝ THUẾ', style: st(10, bold: true), textAlign: pw.TextAlign.center),
                        pw.SizedBox(height: 40),
                        pw.Text('(Ký, ghi rõ họ tên)', style: st(9), textAlign: pw.TextAlign.center),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 20),
                  pw.Expanded(
                    child: pw.Column(
                      children: [
                        pw.Text('NGƯỜI NỘP THUẾ', style: st(10, bold: true), textAlign: pw.TextAlign.center),
                        pw.SizedBox(height: 40),
                        pw.Text('(Ký, ghi rõ họ tên, chức vụ và đóng dấu (nếu có))', style: st(9), textAlign: pw.TextAlign.center),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return doc.save();
  }
}
