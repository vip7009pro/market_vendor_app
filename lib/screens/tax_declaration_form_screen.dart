import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';

import '../models/tax_declaration.dart';
import '../services/tax_declaration_pdf_service.dart';
import '../utils/file_helper.dart';

class TaxDeclarationFormScreen extends StatefulWidget {
  const TaxDeclarationFormScreen({super.key});

  @override
  State<TaxDeclarationFormScreen> createState() => _TaxDeclarationFormScreenState();
}

class _TaxDeclarationFormScreenState extends State<TaxDeclarationFormScreen> {
  final _formKey = GlobalKey<FormState>();

  bool hkDkCkNdKhoan = false;
  bool ckNdPhatSinh = false;
  bool toChucCaNhanKhaiThay = false;
  bool hkDkCkNdKeKhai = true;
  bool hkDkCkNdXacNhanDoanhThu = false;
  bool hoKhoanChuyenDoi = false;

  bool lanDau02 = false;
  bool thayDoiThongTin08a = false;
  bool diThue09a = false;
  bool thayDoiThongTin12a = false;
  bool kinhDoanhTaiChoBienGioi12e = false;

  final kyTinhThue01aNam = TextEditingController();
  final kyTinhThue01aTuThang = TextEditingController();
  final kyTinhThue01aDenThang = TextEditingController();

  final kyTinhThue01bThang = TextEditingController();
  final kyTinhThue01bNam = TextEditingController();

  final kyTinhThue01cQuy = TextEditingController();
  final kyTinhThue01cNam = TextEditingController();
  final kyTinhThue01cTuThang = TextEditingController();
  final kyTinhThue01cDenThang = TextEditingController();

  final kyTinhThue01dNgay = TextEditingController();
  final kyTinhThue01dThang = TextEditingController();
  final kyTinhThue01dNam = TextEditingController();

  final boSungLanThu03 = TextEditingController();
  final nguoiNopThue04 = TextEditingController();
  final tenCuaHang05 = TextEditingController();
  final taiKhoanNganHang06 = TextEditingController();
  final maSoThue07 = TextEditingController();
  final nganhNgheKinhDoanh08 = TextEditingController();
  final dienTichKinhDoanh09 = TextEditingController();
  final soLuongLaoDong10 = TextEditingController();
  final thoiGianTuGio11 = TextEditingController();
  final thoiGianDenGio11 = TextEditingController();

  final soNhaDuongPho12b = TextEditingController();
  final phuongXaThiTran12c = TextEditingController();
  final quanHuyenThiXa12d = TextEditingController();
  final tinhThanhPho12dd = TextEditingController();

  final soNhaDuongPho13a = TextEditingController();
  final phuongXaThiTran13b = TextEditingController();
  final quanHuyenThiXa13c = TextEditingController();
  final tinhThanhPho13d = TextEditingController();

  final dienThoai14 = TextEditingController();
  final fax15 = TextEditingController();
  final email16 = TextEditingController();

  final vanBanUyQuyen17 = TextEditingController();
  final vanBanUyQuyenNgay17 = TextEditingController();
  final vanBanUyQuyenThang17 = TextEditingController();
  final vanBanUyQuyenNam17 = TextEditingController();

  final truongHopChuaDangKyThue18 = TextEditingController();

  final daiLyThue19 = TextEditingController();
  final maSoThue20 = TextEditingController();
  final hopDongDaiLyThue21 = TextEditingController();
  final hopDongDaiLyNgay21 = TextEditingController();

  final tenToChucKhaiThay22 = TextEditingController();
  final maSoThue23 = TextEditingController();
  final diaChi24 = TextEditingController();
  final dienThoai25 = TextEditingController();
  final fax26 = TextEditingController();
  final email27 = TextEditingController();

  bool _busy = false;

  @override
  void dispose() {
    kyTinhThue01aNam.dispose();
    kyTinhThue01aTuThang.dispose();
    kyTinhThue01aDenThang.dispose();
    kyTinhThue01bThang.dispose();
    kyTinhThue01bNam.dispose();
    kyTinhThue01cQuy.dispose();
    kyTinhThue01cNam.dispose();
    kyTinhThue01cTuThang.dispose();
    kyTinhThue01cDenThang.dispose();
    kyTinhThue01dNgay.dispose();
    kyTinhThue01dThang.dispose();
    kyTinhThue01dNam.dispose();
    boSungLanThu03.dispose();
    nguoiNopThue04.dispose();
    tenCuaHang05.dispose();
    taiKhoanNganHang06.dispose();
    maSoThue07.dispose();
    nganhNgheKinhDoanh08.dispose();
    dienTichKinhDoanh09.dispose();
    soLuongLaoDong10.dispose();
    thoiGianTuGio11.dispose();
    thoiGianDenGio11.dispose();
    soNhaDuongPho12b.dispose();
    phuongXaThiTran12c.dispose();
    quanHuyenThiXa12d.dispose();
    tinhThanhPho12dd.dispose();
    soNhaDuongPho13a.dispose();
    phuongXaThiTran13b.dispose();
    quanHuyenThiXa13c.dispose();
    tinhThanhPho13d.dispose();
    dienThoai14.dispose();
    fax15.dispose();
    email16.dispose();
    vanBanUyQuyen17.dispose();
    vanBanUyQuyenNgay17.dispose();
    vanBanUyQuyenThang17.dispose();
    vanBanUyQuyenNam17.dispose();
    truongHopChuaDangKyThue18.dispose();
    daiLyThue19.dispose();
    maSoThue20.dispose();
    hopDongDaiLyThue21.dispose();
    hopDongDaiLyNgay21.dispose();
    tenToChucKhaiThay22.dispose();
    maSoThue23.dispose();
    diaChi24.dispose();
    dienThoai25.dispose();
    fax26.dispose();
    email27.dispose();
    super.dispose();
  }

  TaxDeclarationData _buildData() {
    return TaxDeclarationData(
      hkDkCkNdKhoan: hkDkCkNdKhoan,
      ckNdPhatSinh: ckNdPhatSinh,
      toChucCaNhanKhaiThay: toChucCaNhanKhaiThay,
      hkDkCkNdKeKhai: hkDkCkNdKeKhai,
      hkDkCkNdXacNhanDoanhThu: hkDkCkNdXacNhanDoanhThu,
      hoKhoanChuyenDoi: hoKhoanChuyenDoi,
      kyTinhThue01aNam: kyTinhThue01aNam.text,
      kyTinhThue01aTuThang: kyTinhThue01aTuThang.text,
      kyTinhThue01aDenThang: kyTinhThue01aDenThang.text,
      kyTinhThue01bThang: kyTinhThue01bThang.text,
      kyTinhThue01bNam: kyTinhThue01bNam.text,
      kyTinhThue01cQuy: kyTinhThue01cQuy.text,
      kyTinhThue01cNam: kyTinhThue01cNam.text,
      kyTinhThue01cTuThang: kyTinhThue01cTuThang.text,
      kyTinhThue01cDenThang: kyTinhThue01cDenThang.text,
      kyTinhThue01dNgay: kyTinhThue01dNgay.text,
      kyTinhThue01dThang: kyTinhThue01dThang.text,
      kyTinhThue01dNam: kyTinhThue01dNam.text,
      lanDau02: lanDau02,
      boSungLanThu03: boSungLanThu03.text,
      nguoiNopThue04: nguoiNopThue04.text,
      tenCuaHang05: tenCuaHang05.text,
      taiKhoanNganHang06: taiKhoanNganHang06.text,
      maSoThue07: maSoThue07.text,
      nganhNgheKinhDoanh08: nganhNgheKinhDoanh08.text,
      thayDoiThongTin08a: thayDoiThongTin08a,
      dienTichKinhDoanh09: dienTichKinhDoanh09.text,
      diThue09a: diThue09a,
      soLuongLaoDong10: soLuongLaoDong10.text,
      thoiGianTuGio11: thoiGianTuGio11.text,
      thoiGianDenGio11: thoiGianDenGio11.text,
      thayDoiThongTin12a: thayDoiThongTin12a,
      soNhaDuongPho12b: soNhaDuongPho12b.text,
      phuongXaThiTran12c: phuongXaThiTran12c.text,
      quanHuyenThiXa12d: quanHuyenThiXa12d.text,
      tinhThanhPho12dd: tinhThanhPho12dd.text,
      kinhDoanhTaiChoBienGioi12e: kinhDoanhTaiChoBienGioi12e,
      soNhaDuongPho13a: soNhaDuongPho13a.text,
      phuongXaThiTran13b: phuongXaThiTran13b.text,
      quanHuyenThiXa13c: quanHuyenThiXa13c.text,
      tinhThanhPho13d: tinhThanhPho13d.text,
      dienThoai14: dienThoai14.text,
      fax15: fax15.text,
      email16: email16.text,
      vanBanUyQuyen17: vanBanUyQuyen17.text,
      vanBanUyQuyenNgay17: vanBanUyQuyenNgay17.text,
      vanBanUyQuyenThang17: vanBanUyQuyenThang17.text,
      vanBanUyQuyenNam17: vanBanUyQuyenNam17.text,
      truongHopChuaDangKyThue18: truongHopChuaDangKyThue18.text,
      daiLyThue19: daiLyThue19.text,
      maSoThue20: maSoThue20.text,
      hopDongDaiLyThue21: hopDongDaiLyThue21.text,
      hopDongDaiLyNgay21: hopDongDaiLyNgay21.text,
      tenToChucKhaiThay22: tenToChucKhaiThay22.text,
      maSoThue23: maSoThue23.text,
      diaChi24: diaChi24.text,
      dienThoai25: dienThoai25.text,
      fax26: fax26.text,
      email27: email27.text,
    );
  }

  Future<void> _preview() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final bytes = await TaxDeclarationPdfService.buildPdf(data: _buildData());
      if (!mounted) return;
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'to_khai_thue_$ts.pdf';
      final path = await FileHelper.saveBytesToDownloads(
        bytes: bytes,
        fileName: fileName,
        mimeType: 'application/pdf',
      );
      if (!mounted) return;
      if (path == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không thể lưu file PDF')));
        return;
      }
      await OpenFilex.open(path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi tạo PDF: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }

  Widget _tf(String label, TextEditingController c, {int maxLines = 1, TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _cb(String label, bool v, ValueChanged<bool?> onChanged) {
    return CheckboxListTile(
      value: v,
      onChanged: onChanged,
      title: Text(label),
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      contentPadding: EdgeInsets.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Khai thuế'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _preview,
            child: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Preview / Lưu PDF'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle('Tùy chọn'),
            _cb('HKD, CNKD nộp thuế theo phương pháp khoán', hkDkCkNdKhoan, (v) => setState(() => hkDkCkNdKhoan = v ?? false)),
            _cb('CNKD nộp thuế theo từng lần phát sinh', ckNdPhatSinh, (v) => setState(() => ckNdPhatSinh = v ?? false)),
            _cb('Tổ chức, cá nhân khai thay, nộp thuế thay', toChucCaNhanKhaiThay, (v) => setState(() => toChucCaNhanKhaiThay = v ?? false)),
            _cb('HKD, CNKD nộp thuế theo phương pháp kê khai', hkDkCkNdKeKhai, (v) => setState(() => hkDkCkNdKeKhai = v ?? false)),
            _cb('HKD, CNKD trong lĩnh vực cần xác định doanh thu theo xác nhận cơ quan chức năng', hkDkCkNdXacNhanDoanhThu, (v) => setState(() => hkDkCkNdXacNhanDoanhThu = v ?? false)),
            _cb('Hộ khoán chuyển đổi phương pháp tính thuế', hoKhoanChuyenDoi, (v) => setState(() => hoKhoanChuyenDoi = v ?? false)),

            _sectionTitle('[01] Kỳ tính thuế'),
            _tf('[01a] Năm', kyTinhThue01aNam, keyboardType: TextInputType.number),
            _tf('[01a] Từ tháng', kyTinhThue01aTuThang, keyboardType: TextInputType.number),
            _tf('[01a] Đến tháng', kyTinhThue01aDenThang, keyboardType: TextInputType.number),
            _tf('[01b] Tháng', kyTinhThue01bThang, keyboardType: TextInputType.number),
            _tf('[01b] Năm', kyTinhThue01bNam, keyboardType: TextInputType.number),
            _tf('[01c] Quý', kyTinhThue01cQuy, keyboardType: TextInputType.number),
            _tf('[01c] Năm', kyTinhThue01cNam, keyboardType: TextInputType.number),
            _tf('[01c] Từ tháng', kyTinhThue01cTuThang, keyboardType: TextInputType.number),
            _tf('[01c] Đến tháng', kyTinhThue01cDenThang, keyboardType: TextInputType.number),
            _tf('[01d] Ngày', kyTinhThue01dNgay, keyboardType: TextInputType.number),
            _tf('[01d] Tháng', kyTinhThue01dThang, keyboardType: TextInputType.number),
            _tf('[01d] Năm', kyTinhThue01dNam, keyboardType: TextInputType.number),

            _sectionTitle('[02]-[03]'),
            _cb('[02] Lần đầu', lanDau02, (v) => setState(() => lanDau02 = v ?? false)),
            _tf('[03] Bổ sung lần thứ', boSungLanThu03, keyboardType: TextInputType.text),

            _sectionTitle('[04]-[11]'),
            _tf('[04] Người nộp thuế', nguoiNopThue04),
            _tf('[05] Tên cửa hàng/Thương hiệu', tenCuaHang05),
            _tf('[06] Tài khoản ngân hàng', taiKhoanNganHang06),
            _tf('[07] Mã số thuế', maSoThue07),
            _tf('[08] Ngành nghề kinh doanh', nganhNgheKinhDoanh08),
            _cb('[08a] Thay đổi thông tin', thayDoiThongTin08a, (v) => setState(() => thayDoiThongTin08a = v ?? false)),
            _tf('[09] Diện tích kinh doanh', dienTichKinhDoanh09),
            _cb('[09a] Đi thuê', diThue09a, (v) => setState(() => diThue09a = v ?? false)),
            _tf('[10] Số lượng lao động sử dụng thường xuyên', soLuongLaoDong10),
            _tf('[11] Thời gian hoạt động từ (giờ)', thoiGianTuGio11),
            _tf('[11] Thời gian hoạt động đến (giờ)', thoiGianDenGio11),

            _sectionTitle('[12] Địa chỉ kinh doanh'),
            _cb('[12a] Thay đổi thông tin', thayDoiThongTin12a, (v) => setState(() => thayDoiThongTin12a = v ?? false)),
            _tf('[12b] Số nhà/đường phố/xóm/ấp/thôn', soNhaDuongPho12b),
            _tf('[12c] Phường/Xã/Thị trấn', phuongXaThiTran12c),
            _tf('[12d] Quận/Huyện/Thị xã/Thành phố thuộc tỉnh', quanHuyenThiXa12d),
            _tf('[12đ] Tỉnh/Thành phố', tinhThanhPho12dd),
            _cb('[12e] Kinh doanh tại chợ biên giới', kinhDoanhTaiChoBienGioi12e, (v) => setState(() => kinhDoanhTaiChoBienGioi12e = v ?? false)),

            _sectionTitle('[13] Địa chỉ cư trú'),
            _tf('[13a] Số nhà/đường phố/xóm/ấp/thôn', soNhaDuongPho13a),
            _tf('[13b] Phường/Xã/Thị trấn', phuongXaThiTran13b),
            _tf('[13c] Quận/Huyện/Thị xã/Thành phố thuộc tỉnh', quanHuyenThiXa13c),
            _tf('[13d] Tỉnh/Thành phố', tinhThanhPho13d),

            _sectionTitle('[14]-[16]'),
            _tf('[14] Điện thoại', dienThoai14, keyboardType: TextInputType.phone),
            _tf('[15] Fax', fax15, keyboardType: TextInputType.phone),
            _tf('[16] Email', email16, keyboardType: TextInputType.emailAddress),

            _sectionTitle('[17] Văn bản ủy quyền'),
            _tf('[17] Số văn bản', vanBanUyQuyen17),
            _tf('[17] Ngày', vanBanUyQuyenNgay17, keyboardType: TextInputType.number),
            _tf('[17] Tháng', vanBanUyQuyenThang17, keyboardType: TextInputType.number),
            _tf('[17] Năm', vanBanUyQuyenNam17, keyboardType: TextInputType.number),

            _sectionTitle('[18] Thông tin bổ sung'),
            _tf('[18] Nội dung', truongHopChuaDangKyThue18, maxLines: 6),

            _sectionTitle('[19]-[27] Thông tin đại lý / tổ chức khai thay'),
            _tf('[19] Tên đại lý thuế', daiLyThue19),
            _tf('[20] Mã số thuế', maSoThue20),
            _tf('[21] Hợp đồng đại lý thuế (số)', hopDongDaiLyThue21),
            _tf('[21] Ngày', hopDongDaiLyNgay21),
            _tf('[22] Tên tổ chức khai thay', tenToChucKhaiThay22),
            _tf('[23] Mã số thuế', maSoThue23),
            _tf('[24] Địa chỉ', diaChi24),
            _tf('[25] Điện thoại', dienThoai25, keyboardType: TextInputType.phone),
            _tf('[26] Fax', fax26, keyboardType: TextInputType.phone),
            _tf('[27] Email', email27, keyboardType: TextInputType.emailAddress),

            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _preview,
              child: const Text('Preview / Lưu PDF'),
            ),
          ],
        ),
      ),
    );
  }
}
