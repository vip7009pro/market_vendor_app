'use client';

import React, { useEffect, useState } from 'react';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth';

const NAV_ITEMS = [
  { path: '/dashboard', label: 'Tổng quan', icon: '📊' },
  { path: '/pos', label: 'Bán hàng (POS)', icon: '🛒' },
  { path: '/sales', label: 'Lịch sử bán', icon: '📜' },
  { path: '/purchases', label: 'Nhập hàng', icon: '📥' },
  { path: '/products', label: 'Sản phẩm', icon: '📦' },
  { path: '/customers', label: 'Khách hàng', icon: '👥' },
  { path: '/debts', label: 'Công nợ', icon: '💳' },
  { path: '/expenses', label: 'Chi phí', icon: '💸' },
  { path: '/reports', label: 'Báo cáo chi tiết', icon: '📈' },
  { path: '/settings', label: 'Cài đặt', icon: '⚙️' },
];

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const { user, loading, logout } = useAuth();
  const router = useRouter();
  const pathname = usePathname();
  const [sidebarOpen, setSidebarOpen] = useState(false);

  useEffect(() => {
    if (!loading && !user) {
      router.push('/login');
    }
  }, [user, loading, router]);

  if (loading) {
    return (
      <div className="min-h-screen bg-[#0f172a] text-white flex items-center justify-center font-sans">
        <div className="flex flex-col items-center gap-4">
          <div className="w-12 h-12 border-4 border-indigo-500/30 border-t-indigo-500 rounded-full animate-spin"></div>
          <p className="text-slate-400 text-sm">Đang tải cấu hình hệ thống...</p>
        </div>
      </div>
    );
  }

  if (!user) {
    return null; // Will redirect in useEffect
  }

  const activeItem = NAV_ITEMS.find((item) => pathname.startsWith(item.path)) || NAV_ITEMS[0];

  return (
    <div className="min-h-screen bg-[#0f172a] text-[#f1f5f9] font-sans flex flex-col md:flex-row">
      {/* Sidebar for Desktop */}
      <aside className="hidden md:flex flex-col w-64 border-r border-white/5 bg-[#0f172a] shrink-0">
        {/* Brand */}
        <div className="p-6 border-b border-white/5 flex items-center gap-3">
          <div className="w-8 h-8 rounded-lg bg-gradient-to-tr from-indigo-500 to-cyan-400 flex items-center justify-center font-bold text-white text-lg shadow-md shadow-indigo-500/10">
            M
          </div>
          <div>
            <h1 className="font-bold text-sm leading-none tracking-tight">Market Vendor</h1>
            <span className="text-[9px] text-cyan-400 uppercase tracking-widest font-semibold">Dashboard</span>
          </div>
        </div>

        {/* Navigation */}
        <nav className="flex-1 p-4 space-y-1.5">
          {NAV_ITEMS.map((item) => {
            const isActive = pathname === item.path || pathname.startsWith(item.path + '/');
            return (
              <Link
                key={item.path}
                href={item.path}
                className={`flex items-center gap-3.5 px-4 py-3 rounded-lg text-sm font-semibold transition-all duration-200 ${
                  isActive
                    ? 'bg-gradient-to-r from-indigo-500/20 to-indigo-500/10 text-indigo-300 border border-indigo-500/20 shadow-md'
                    : 'text-slate-400 hover:text-slate-200 hover:bg-white/5 border border-transparent'
                }`}
              >
                <span>{item.icon}</span>
                <span>{item.label}</span>
              </Link>
            );
          })}
        </nav>

        {/* User profile / Logout */}
        <div className="p-4 border-t border-white/5 space-y-3">
          <div className="flex items-center gap-3 px-2">
            <div className="w-9 h-9 rounded-full bg-indigo-500/20 border border-indigo-500/30 flex items-center justify-center text-sm font-bold text-indigo-300">
              {user.name ? user.name.charAt(0).toUpperCase() : user.email.charAt(0).toUpperCase()}
            </div>
            <div className="truncate">
              <p className="text-xs font-bold text-white truncate">{user.name || 'Người dùng'}</p>
              <p className="text-[10px] text-slate-500 truncate">{user.email}</p>
            </div>
          </div>
          <button
            onClick={logout}
            className="w-full text-left flex items-center gap-3 px-4 py-2.5 rounded-lg text-xs font-semibold text-rose-400 hover:bg-rose-500/10 transition-colors"
          >
            <span>🚪</span>
            <span>Đăng xuất</span>
          </button>
        </div>
      </aside>

      {/* Mobile Header / Navigation */}
      <header className="md:hidden flex justify-between items-center px-6 py-4 bg-[#0f172a] border-b border-white/5 relative z-40">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 rounded-lg bg-gradient-to-tr from-indigo-500 to-cyan-400 flex items-center justify-center font-bold text-white text-lg">
            M
          </div>
          <div>
            <h1 className="font-bold text-sm leading-none tracking-tight">Market Vendor</h1>
            <span className="text-[9px] text-cyan-400 uppercase tracking-widest font-semibold">Dashboard</span>
          </div>
        </div>

        <button
          onClick={() => setSidebarOpen(!sidebarOpen)}
          className="text-2xl p-1 hover:bg-white/5 rounded"
        >
          {sidebarOpen ? '✕' : '☰'}
        </button>

        {/* Mobile Dropdown Menu */}
        {sidebarOpen && (
          <div className="absolute top-full left-0 right-0 border-b border-white/5 bg-[#0f172a]/95 backdrop-blur-lg flex flex-col p-4 shadow-xl space-y-1 z-50">
            {NAV_ITEMS.map((item) => {
              const isActive = pathname === item.path || pathname.startsWith(item.path + '/');
              return (
                <Link
                  key={item.path}
                  href={item.path}
                  onClick={() => setSidebarOpen(false)}
                  className={`flex items-center gap-3 px-4 py-3 rounded-lg text-sm font-semibold ${
                    isActive ? 'bg-indigo-500/20 text-indigo-300' : 'text-slate-400 hover:text-slate-200'
                  }`}
                >
                  <span>{item.icon}</span>
                  <span>{item.label}</span>
                </Link>
              );
            })}
            <div className="border-t border-white/5 my-2 pt-2 flex items-center justify-between px-4">
              <span className="text-xs text-slate-400 truncate">{user.email}</span>
              <button
                onClick={logout}
                className="text-xs font-semibold text-rose-400 hover:underline"
              >
                Đăng xuất
              </button>
            </div>
          </div>
        )}
      </header>

      {/* Main Content Area */}
      <main className="flex-1 flex flex-col min-h-0 bg-[#0f172a]/50 relative z-10 overflow-y-auto">
        {/* Top bar (for Desktop) */}
        <header className="hidden md:flex justify-between items-center py-5 px-8 border-b border-white/5">
          <div className="flex items-center gap-2">
            <span className="text-lg text-slate-500">Dashboard</span>
            <span className="text-slate-600 text-sm">/</span>
            <span className="text-sm font-bold text-white">{activeItem.label}</span>
          </div>
          <div className="flex items-center gap-4">
            <span className="text-xs text-slate-400 font-semibold">{user.name || user.email}</span>
            <Link href="/pos" className="btn btn-primary text-xs shadow-indigo-500/5">
              🛒 Tạo đơn mới
            </Link>
            <button
              onClick={logout}
              className="btn btn-secondary text-xs border-rose-500/20 text-rose-400 hover:bg-rose-500/10"
            >
              🚪 Đăng xuất
            </button>
          </div>
        </header>

        {/* Children content wrapper */}
        <div className="flex-1 p-6 md:p-8">
          {children}
        </div>
      </main>
    </div>
  );
}
