class TaxDeclarationData {
  final bool hkDkCkNdKhoan;
  final bool ckNdPhatSinh;
  final bool toChucCaNhanKhaiThay;
  final bool hkDkCkNdKeKhai;
  final bool hkDkCkNdXacNhanDoanhThu;
  final bool hoKhoanChuyenDoi;

  final String kyTinhThue01aNam;
  final String kyTinhThue01aTuThang;
  final String kyTinhThue01aDenThang;

  final String kyTinhThue01bThang;
  final String kyTinhThue01bNam;

  final String kyTinhThue01cQuy;
  final String kyTinhThue01cNam;
  final String kyTinhThue01cTuThang;
  final String kyTinhThue01cDenThang;

  final String kyTinhThue01dNgay;
  final String kyTinhThue01dThang;
  final String kyTinhThue01dNam;

  final bool lanDau02;
  final String boSungLanThu03;

  final String nguoiNopThue04;
  final String tenCuaHang05;
  final String taiKhoanNganHang06;
  final String maSoThue07;

  final String nganhNgheKinhDoanh08;
  final bool thayDoiThongTin08a;

  final String dienTichKinhDoanh09;
  final bool diThue09a;

  final String soLuongLaoDong10;

  final String thoiGianTuGio11;
  final String thoiGianDenGio11;

  final bool thayDoiThongTin12a;
  final String soNhaDuongPho12b;
  final String phuongXaThiTran12c;
  final String quanHuyenThiXa12d;
  final String tinhThanhPho12dd;
  final bool kinhDoanhTaiChoBienGioi12e;

  final String soNhaDuongPho13a;
  final String phuongXaThiTran13b;
  final String quanHuyenThiXa13c;
  final String tinhThanhPho13d;

  final String dienThoai14;
  final String fax15;
  final String email16;

  final String vanBanUyQuyen17;
  final String vanBanUyQuyenNgay17;
  final String vanBanUyQuyenThang17;
  final String vanBanUyQuyenNam17;

  final String truongHopChuaDangKyThue18;

  final String daiLyThue19;
  final String maSoThue20;
  final String hopDongDaiLyThue21;
  final String hopDongDaiLyNgay21;

  final String tenToChucKhaiThay22;
  final String maSoThue23;
  final String diaChi24;
  final String dienThoai25;
  final String fax26;
  final String email27;

  const TaxDeclarationData({
    required this.hkDkCkNdKhoan,
    required this.ckNdPhatSinh,
    required this.toChucCaNhanKhaiThay,
    required this.hkDkCkNdKeKhai,
    required this.hkDkCkNdXacNhanDoanhThu,
    required this.hoKhoanChuyenDoi,
    required this.kyTinhThue01aNam,
    required this.kyTinhThue01aTuThang,
    required this.kyTinhThue01aDenThang,
    required this.kyTinhThue01bThang,
    required this.kyTinhThue01bNam,
    required this.kyTinhThue01cQuy,
    required this.kyTinhThue01cNam,
    required this.kyTinhThue01cTuThang,
    required this.kyTinhThue01cDenThang,
    required this.kyTinhThue01dNgay,
    required this.kyTinhThue01dThang,
    required this.kyTinhThue01dNam,
    required this.lanDau02,
    required this.boSungLanThu03,
    required this.nguoiNopThue04,
    required this.tenCuaHang05,
    required this.taiKhoanNganHang06,
    required this.maSoThue07,
    required this.nganhNgheKinhDoanh08,
    required this.thayDoiThongTin08a,
    required this.dienTichKinhDoanh09,
    required this.diThue09a,
    required this.soLuongLaoDong10,
    required this.thoiGianTuGio11,
    required this.thoiGianDenGio11,
    required this.thayDoiThongTin12a,
    required this.soNhaDuongPho12b,
    required this.phuongXaThiTran12c,
    required this.quanHuyenThiXa12d,
    required this.tinhThanhPho12dd,
    required this.kinhDoanhTaiChoBienGioi12e,
    required this.soNhaDuongPho13a,
    required this.phuongXaThiTran13b,
    required this.quanHuyenThiXa13c,
    required this.tinhThanhPho13d,
    required this.dienThoai14,
    required this.fax15,
    required this.email16,
    required this.vanBanUyQuyen17,
    required this.vanBanUyQuyenNgay17,
    required this.vanBanUyQuyenThang17,
    required this.vanBanUyQuyenNam17,
    required this.truongHopChuaDangKyThue18,
    required this.daiLyThue19,
    required this.maSoThue20,
    required this.hopDongDaiLyThue21,
    required this.hopDongDaiLyNgay21,
    required this.tenToChucKhaiThay22,
    required this.maSoThue23,
    required this.diaChi24,
    required this.dienThoai25,
    required this.fax26,
    required this.email27,
  });

  factory TaxDeclarationData.empty() {
    return const TaxDeclarationData(
      hkDkCkNdKhoan: false,
      ckNdPhatSinh: false,
      toChucCaNhanKhaiThay: false,
      hkDkCkNdKeKhai: true,
      hkDkCkNdXacNhanDoanhThu: false,
      hoKhoanChuyenDoi: false,
      kyTinhThue01aNam: '',
      kyTinhThue01aTuThang: '',
      kyTinhThue01aDenThang: '',
      kyTinhThue01bThang: '',
      kyTinhThue01bNam: '',
      kyTinhThue01cQuy: '',
      kyTinhThue01cNam: '',
      kyTinhThue01cTuThang: '',
      kyTinhThue01cDenThang: '',
      kyTinhThue01dNgay: '',
      kyTinhThue01dThang: '',
      kyTinhThue01dNam: '',
      lanDau02: false,
      boSungLanThu03: '',
      nguoiNopThue04: '',
      tenCuaHang05: '',
      taiKhoanNganHang06: '',
      maSoThue07: '',
      nganhNgheKinhDoanh08: '',
      thayDoiThongTin08a: false,
      dienTichKinhDoanh09: '',
      diThue09a: false,
      soLuongLaoDong10: '',
      thoiGianTuGio11: '',
      thoiGianDenGio11: '',
      thayDoiThongTin12a: false,
      soNhaDuongPho12b: '',
      phuongXaThiTran12c: '',
      quanHuyenThiXa12d: '',
      tinhThanhPho12dd: '',
      kinhDoanhTaiChoBienGioi12e: false,
      soNhaDuongPho13a: '',
      phuongXaThiTran13b: '',
      quanHuyenThiXa13c: '',
      tinhThanhPho13d: '',
      dienThoai14: '',
      fax15: '',
      email16: '',
      vanBanUyQuyen17: '',
      vanBanUyQuyenNgay17: '',
      vanBanUyQuyenThang17: '',
      vanBanUyQuyenNam17: '',
      truongHopChuaDangKyThue18: '',
      daiLyThue19: '',
      maSoThue20: '',
      hopDongDaiLyThue21: '',
      hopDongDaiLyNgay21: '',
      tenToChucKhaiThay22: '',
      maSoThue23: '',
      diaChi24: '',
      dienThoai25: '',
      fax26: '',
      email27: '',
    );
  }
}
