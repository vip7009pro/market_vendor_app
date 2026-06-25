'use client';

import React from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { useAuth } from '@/lib/auth';

export default function LandingPage() {
  const { user } = useAuth();

  return (
    <div className="min-h-screen bg-[#0f172a] text-[#f1f5f9] font-sans selection:bg-indigo-500 selection:text-white overflow-x-hidden">
      {/* Header */}
      <header className="fixed top-0 left-0 right-0 z-50 glass border-b border-white/5 py-4 px-4 sm:px-6">
        <div className="max-w-6xl mx-auto flex justify-between items-center w-full px-2 sm:px-6">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-gradient-to-tr from-indigo-500 to-cyan-400 flex items-center justify-center font-bold text-white text-xl shadow-lg shadow-indigo-500/20">
              M
            </div>
            <div>
              <h1 className="font-bold text-base md:text-lg leading-none tracking-tight">Market Vendor</h1>
              <span className="text-[10px] text-cyan-400 uppercase tracking-widest font-semibold">Web App</span>
            </div>
          </div>

          <nav className="hidden md:flex items-center gap-8 text-sm font-medium text-slate-300">
            <a href="#features" className="hover:text-white transition-colors">Tính năng</a>
            <a href="#about" className="hover:text-white transition-colors">Về chúng tôi</a>
            <a href="#pricing" className="hover:text-white transition-colors">Báo giá</a>
          </nav>

          <div className="flex items-center gap-2 md:gap-4">
            {user ? (
              <Link href="/dashboard" className="btn btn-primary text-xs md:text-sm shadow-indigo-500/10">
                Quản lý
              </Link>
            ) : (
              <>
                <Link href="/login" className="text-xs md:text-sm font-medium text-slate-300 hover:text-white transition-colors px-2 py-1">
                  Đăng nhập
                </Link>
                <Link href="/login?mode=register" className="btn btn-primary text-xs md:text-sm shadow-indigo-500/10">
                  Dùng thử
                </Link>
              </>
            )}
          </div>
        </div>
      </header>

      {/* Hero Section */}
      <section className="relative pt-36 pb-24 md:pt-48 md:pb-32 overflow-hidden bg-gradient-to-b from-[#0f172a] via-[#121b3a] to-[#0f172a]">
        <div className="absolute inset-0 z-0 bg-[radial-gradient(circle_at_top_right,rgba(99,102,241,0.08),transparent_45%)]" />
        <div className="absolute inset-0 z-0 bg-[radial-gradient(circle_at_bottom_left,rgba(6,182,212,0.08),transparent_45%)]" />
        
        <div className="max-w-6xl mx-auto px-6 relative z-10 grid md:grid-cols-12 gap-12 items-center">
          <div className="md:col-span-7 space-y-6 text-center md:text-left">
            <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-indigo-500/10 border border-indigo-500/20 text-indigo-300 text-xs font-semibold tracking-wider uppercase">
              ⚡ Chuyển đổi số cho Tiểu Thương
            </div>
            
            <h2 className="text-4xl md:text-6xl font-extrabold tracking-tight leading-[1.1]">
              Quản lý bán hàng <br />
              <span className="text-gradient">thông minh & dễ dàng</span>
            </h2>
            
            <p className="text-lg text-slate-400 max-w-xl mx-auto md:mx-0">
              Giải pháp tối ưu dành riêng cho các hộ kinh doanh và tiểu thương. Quản lý sản phẩm, đơn hàng, công nợ, chi phí tức thời trên mọi thiết bị.
            </p>
            
            <div className="flex flex-col sm:flex-row items-center justify-center md:justify-start gap-4 pt-4">
              {user ? (
                <Link href="/dashboard" className="btn btn-primary btn-lg w-full sm:w-auto shadow-glow">
                  Đến trang quản lý →
                </Link>
              ) : (
                <>
                  <Link href="/login?mode=register" className="btn btn-primary btn-lg w-full sm:w-auto shadow-glow">
                    Bắt đầu miễn phí →
                  </Link>
                  <Link href="#features" className="btn btn-secondary btn-lg w-full sm:w-auto">
                    Tìm hiểu thêm
                  </Link>
                </>
              )}
            </div>

            <div className="grid grid-cols-3 gap-2 sm:gap-6 pt-8 border-t border-slate-800 text-center md:text-left">
              <div>
                <p className="text-xl md:text-3xl font-extrabold text-white">100%</p>
                <p className="text-[10px] sm:text-xs text-slate-500 uppercase tracking-wider mt-1">Đồng bộ</p>
              </div>
              <div>
                <p className="text-xl md:text-3xl font-extrabold text-white">0đ</p>
                <p className="text-[10px] sm:text-xs text-slate-500 uppercase tracking-wider mt-1">Miễn phí</p>
              </div>
              <div>
                <p className="text-xl md:text-3xl font-extrabold text-white">&lt; 3s</p>
                <p className="text-[10px] sm:text-xs text-slate-500 uppercase tracking-wider mt-1">Tạo đơn</p>
              </div>
            </div>
          </div>

          <div className="hidden lg:flex lg:col-span-5 relative justify-center">
            {/* Glassmorphic interactive-like mock dashboard preview */}
            <div className="w-full max-w-[420px] rounded-2xl border border-white/10 bg-[#1e293b]/60 backdrop-blur-xl shadow-2xl p-6 relative overflow-hidden animate-float">
              {/* Header inside mock */}
              <div className="flex justify-between items-center mb-6">
                <div className="flex items-center gap-2">
                  <span className="w-3 h-3 rounded-full bg-rose-500"></span>
                  <span className="w-3 h-3 rounded-full bg-amber-500"></span>
                  <span className="w-3 h-3 rounded-full bg-emerald-500"></span>
                </div>
                <div className="text-[11px] bg-slate-800 text-slate-400 px-3 py-1 rounded-full font-mono">
                  dashboard.marketvendor.vn
                </div>
              </div>
              
              {/* Sales Chart Mock */}
              <div className="space-y-4">
                <div className="flex justify-between items-end">
                  <div>
                    <span className="text-xs text-slate-400">Doanh thu hôm nay</span>
                    <h4 className="text-2xl font-bold text-white mt-1">1.820.000 đ</h4>
                  </div>
                  <span className="text-xs text-emerald-400 bg-emerald-500/10 px-2 py-0.5 rounded font-semibold">+14.2%</span>
                </div>
                
                {/* Visual mock chart */}
                <div className="h-32 flex items-end gap-2.5 pt-4 border-b border-slate-800">
                  <div className="w-full bg-indigo-500/20 hover:bg-indigo-500/40 transition-colors rounded-t h-[40%]" title="Thứ 2"></div>
                  <div className="w-full bg-indigo-500/20 hover:bg-indigo-500/40 transition-colors rounded-t h-[55%]" title="Thứ 3"></div>
                  <div className="w-full bg-indigo-500/20 hover:bg-indigo-500/40 transition-colors rounded-t h-[30%]" title="Thứ 4"></div>
                  <div className="w-full bg-indigo-500/40 hover:bg-indigo-500/60 transition-colors rounded-t h-[75%]" title="Thứ 5"></div>
                  <div className="w-full bg-gradient-to-t from-indigo-500 to-cyan-400 rounded-t h-[95%] relative group cursor-pointer" title="Hôm nay">
                    <div className="absolute -top-8 left-1/2 -translate-x-1/2 bg-slate-950 text-[10px] text-white px-1.5 py-0.5 rounded opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap shadow-md">
                      1.8M
                    </div>
                  </div>
                </div>
                
                {/* Recent transaction items */}
                <div className="space-y-3 pt-2">
                  <span className="text-[11px] font-bold text-slate-500 uppercase tracking-widest">Đơn hàng mới</span>
                  <div className="flex justify-between items-center text-xs">
                    <div>
                      <p className="font-semibold text-white">Cà phê sữa đá</p>
                      <p className="text-[10px] text-slate-400">Khách vãng lai • 09:42</p>
                    </div>
                    <p className="font-bold text-indigo-300">+25.000 đ</p>
                  </div>
                  <div className="flex justify-between items-center text-xs">
                    <div>
                      <p className="font-semibold text-white">Nước ngọt các loại (x4)</p>
                      <p className="text-[10px] text-slate-400">Anh Tuấn (Ghi nợ) • 09:15</p>
                    </div>
                    <p className="font-bold text-amber-400">+60.000 đ</p>
                  </div>
                </div>
              </div>
            </div>
            
            {/* Small floating bubble */}
            <div className="absolute -bottom-4 left-4 bg-slate-900 border border-white/5 shadow-xl rounded-xl p-3.5 flex items-center gap-3 backdrop-blur-md">
              <div className="w-8 h-8 rounded-full bg-emerald-500/20 flex items-center justify-center text-emerald-400">
                ✓
              </div>
              <div>
                <p className="text-[11px] text-slate-400 leading-none">Hàng tồn kho</p>
                <p className="text-xs font-bold text-white mt-1">Đã cập nhật tự động</p>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Features Section */}
      <section id="features" className="py-24 max-w-6xl mx-auto px-6">
        <div className="text-center max-w-2xl mx-auto mb-16 space-y-4">
          <span className="text-cyan-400 text-xs font-bold tracking-widest uppercase">Tính năng nổi bật</span>
          <h3 className="text-3xl md:text-4xl font-bold">Giải pháp bán hàng hiện đại</h3>
          <p className="text-slate-400">
            Thiết kế tối giản hóa quy trình bán hàng, loại bỏ sổ sách giấy tờ thủ công dễ thất lạc.
          </p>
        </div>

        <div className="grid md:grid-cols-3 gap-8">
          {/* Feature 1 */}
          <div className="card space-y-4 bg-slate-900/50 border-white/5 hover:border-indigo-500/30 transition-all group">
            <div className="w-12 h-12 rounded-xl bg-indigo-500/10 flex items-center justify-center text-indigo-400 text-xl group-hover:bg-indigo-500 group-hover:text-white transition-colors duration-300">
              🛒
            </div>
            <h4 className="text-lg font-bold text-white">POS Bán Hàng Siêu Tốc</h4>
            <p className="text-sm text-slate-400">
              Giao diện bán hàng trực quan, hỗ trợ tìm kiếm sản phẩm nhanh, in hóa đơn chuyên nghiệp và lưu trữ giao dịch tức thời.
            </p>
          </div>

          {/* Feature 2 */}
          <div className="card space-y-4 bg-slate-900/50 border-white/5 hover:border-indigo-500/30 transition-all group">
            <div className="w-12 h-12 rounded-xl bg-indigo-500/10 flex items-center justify-center text-indigo-400 text-xl group-hover:bg-indigo-500 group-hover:text-white transition-colors duration-300">
              📦
            </div>
            <h4 className="text-lg font-bold text-white">Quản Lý Tồn Kho Thông Minh</h4>
            <p className="text-sm text-slate-400">
              Tự động trừ kho khi bán hàng, cảnh báo hết hàng, quản lý sản phẩm dạng thô (RAW) hoặc công thức phối trộn (MIX).
            </p>
          </div>

          {/* Feature 3 */}
          <div className="card space-y-4 bg-slate-900/50 border-white/5 hover:border-indigo-500/30 transition-all group">
            <div className="w-12 h-12 rounded-xl bg-indigo-500/10 flex items-center justify-center text-indigo-400 text-xl group-hover:bg-indigo-500 group-hover:text-white transition-colors duration-300">
              💳
            </div>
            <h4 className="text-lg font-bold text-white">Quản Lý Công Nợ & Chi Phí</h4>
            <p className="text-sm text-slate-400">
              Theo dõi chi tiết công nợ khách hàng, nhà cung cấp, lịch sử trả nợ và ghi chép chi phí phát sinh hàng ngày để tối ưu ngân sách.
            </p>
          </div>
        </div>
      </section>

      {/* Pricing Section */}
      <section id="pricing" className="py-20 bg-slate-950/60 border-y border-white/5">
        <div className="max-w-6xl mx-auto px-6">
          <div className="text-center max-w-2xl mx-auto mb-16 space-y-4">
            <span className="text-indigo-400 text-xs font-bold tracking-widest uppercase">Báo giá dịch vụ</span>
            <h3 className="text-3xl md:text-4xl font-bold">Lựa chọn gói dịch vụ phù hợp</h3>
            <p className="text-slate-400">
              Cam kết giá trị bền vững và minh bạch, không phụ phí ẩn.
            </p>
          </div>

          <div className="grid md:grid-cols-2 gap-8 max-w-3xl mx-auto">
            {/* Pricing 1 */}
            <div className="card bg-slate-900 border-white/5 relative p-8 flex flex-col justify-between">
              <div>
                <h4 className="text-lg font-bold text-white">Bản Miễn Phí</h4>
                <p className="text-xs text-slate-500 mt-1">Dành cho cá nhân kinh doanh nhỏ</p>
                <div className="my-6">
                  <span className="text-4xl font-extrabold text-white">0 đ</span>
                  <span className="text-slate-400 text-sm"> / tháng</span>
                </div>
                <ul className="space-y-3.5 text-sm text-slate-400 border-t border-slate-800 pt-6">
                  <li className="flex items-center gap-2">✓ Bán hàng POS và in hóa đơn</li>
                  <li className="flex items-center gap-2">✓ Quản lý tối đa 100 sản phẩm</li>
                  <li className="flex items-center gap-2">✓ Lưu trữ dữ liệu thiết bị local</li>
                </ul>
              </div>
              <div className="pt-8">
                <Link href="/login?mode=register" className="btn btn-secondary w-full">
                  Đăng ký miễn phí
                </Link>
              </div>
            </div>

            {/* Pricing 2 (Featured) */}
            <div className="card bg-slate-900 border-indigo-500/30 relative p-8 flex flex-col justify-between shadow-lg shadow-indigo-500/5">
              <div className="absolute top-0 right-6 -translate-y-1/2 bg-indigo-500 text-white px-3 py-1 rounded-full text-[10px] font-bold uppercase tracking-wider">
                Phổ biến nhất
              </div>
              <div>
                <h4 className="text-lg font-bold text-indigo-300">Bản Chuyên Nghiệp</h4>
                <p className="text-xs text-slate-500 mt-1">Đầy đủ tính năng, hoạt động đa thiết bị</p>
                <div className="my-6">
                  <span className="text-4xl font-extrabold text-white">99.000 đ</span>
                  <span className="text-slate-400 text-sm"> / tháng</span>
                </div>
                <ul className="space-y-3.5 text-sm text-slate-400 border-t border-slate-800 pt-6">
                  <li className="flex items-center gap-2 text-indigo-200">✓ Không giới hạn sản phẩm & đơn hàng</li>
                  <li className="flex items-center gap-2 text-indigo-200">✓ Đồng bộ tự động đám mây thời gian thực</li>
                  <li className="flex items-center gap-2 text-indigo-200">✓ Báo cáo nâng cao doanh thu, lợi nhuận</li>
                  <li className="flex items-center gap-2 text-indigo-200">✓ Quản lý công nợ & chi tiết đơn nhập</li>
                </ul>
              </div>
              <div className="pt-8">
                <Link href="/login?mode=register" className="btn btn-primary w-full shadow-glow">
                  Dùng thử miễn phí 30 ngày
                </Link>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* CTA Section */}
      <section className="py-24 max-w-6xl mx-auto px-6 text-center">
        <div className="gradient-border p-12 bg-slate-900/40 relative overflow-hidden">
          <div className="absolute inset-0 bg-[radial-gradient(circle_at_center,rgba(99,102,241,0.06),transparent_50%)]" />
          <div className="relative z-10 max-w-2xl mx-auto space-y-6">
            <h3 className="text-3xl md:text-4xl font-bold text-white">Bắt đầu chuyển đổi số cửa hàng của bạn ngay hôm nay</h3>
            <p className="text-slate-400 text-base">
              Không cần thẻ tín dụng. Đăng ký tài khoản nhanh chóng chỉ trong 1 phút và bắt đầu quản lý cửa hàng chuyên nghiệp hơn.
            </p>
            <div className="pt-4">
              <Link href="/login?mode=register" className="btn btn-primary btn-lg shadow-glow">
                Đăng Ký Tài Khoản Ngay
              </Link>
            </div>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-white/5 py-12 px-6 bg-slate-950 text-slate-500 text-sm">
        <div className="max-w-6xl mx-auto flex flex-col md:flex-row justify-between items-center gap-6">
          <div className="flex items-center gap-2">
            <div className="w-8 h-8 rounded-lg bg-indigo-500/20 flex items-center justify-center font-bold text-indigo-400">
              M
            </div>
            <p className="font-semibold text-slate-400">Market Vendor © 2026</p>
          </div>
          <p className="text-center md:text-right">
            Được phát triển với tình yêu bởi đội ngũ Next.js Việt Nam. Tất cả quyền được bảo lưu.
          </p>
        </div>
      </footer>
    </div>
  );
}
