'use client';

import React, { useEffect, useState } from 'react';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth';
import MuiProvider from '@/components/providers/MuiProvider';

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
  
  useEffect(() => {
    if (!loading && !user) {
      router.push('/login');
    }
  }, [user, loading, router]);

  if (loading) {
    return (
      <div className="min-h-screen bg-[var(--color-bg)] text-[var(--color-text)] flex items-center justify-center font-sans">
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
    <MuiProvider>
    <div className="h-screen w-screen bg-[var(--color-bg)] text-[var(--color-text)] font-sans flex flex-row overflow-hidden">
      {/* Sidebar for Desktop */}
      <aside className="hidden md:flex flex-col w-64 border-r border-white/5 bg-[var(--color-bg-secondary)] shrink-0">
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
            className="w-full text-left flex items-center gap-3 px-4 py-2.5 rounded-lg text-xs font-semibold text-rose-400 hover:bg-rose-500/10 transition-colors cursor-pointer"
          >
            <span>🚪</span>
            <span>Đăng xuất</span>
          </button>
        </div>
      </aside>

      {/* Main Container sandwich for Mobile and Desktop Content */}
      <div className="flex-1 flex flex-col min-h-0 overflow-hidden">
        {/* Mobile Header */}
        <header className="md:hidden flex justify-between items-center px-6 py-3 bg-[var(--color-bg-secondary)] border-b border-white/5 relative z-40 shrink-0">
          <div className="flex items-center gap-2.5">
            <div className="w-7 h-7 rounded-lg bg-gradient-to-tr from-indigo-500 to-cyan-400 flex items-center justify-center font-bold text-white text-xs">
              M
            </div>
            <div>
              <h1 className="font-bold text-xs leading-none tracking-tight text-white">Market Vendor</h1>
              <span className="text-[7px] text-cyan-400 uppercase tracking-widest font-semibold">Dashboard</span>
            </div>
          </div>
          
          <div className="flex items-center gap-2.5">
            <Link 
              href="/pos" 
              className="w-8 h-8 rounded-lg bg-[var(--gradient-primary)] flex items-center justify-center text-white shadow-glow hover:scale-105 transition-transform" 
              title="Tạo đơn mới (POS)"
            >
              🛒
            </Link>
            <button 
              onClick={logout} 
              className="w-8 h-8 rounded-lg border border-[var(--color-border)] text-rose-400 flex items-center justify-center hover:scale-105 transition-transform cursor-pointer" 
              title="Đăng xuất"
            >
              🚪
            </button>
          </div>
        </header>

        {/* Scrollable Content Area */}
        <main className="flex-1 flex flex-col min-h-0 bg-[var(--color-bg)]/50 relative z-10 overflow-y-auto">
          {/* Top bar (for Desktop) */}
          <header className="hidden md:flex justify-between items-center py-5 px-8 border-b border-white/5 bg-[var(--color-bg-secondary)]">
            <div className="flex items-center gap-2">
              <span className="text-sm text-slate-500">Dashboard</span>
              <span className="text-slate-600 text-sm">/</span>
              <span className="text-sm font-bold text-white">{activeItem.label}</span>
            </div>
            <div className="flex items-center gap-4">
              <span className="text-xs text-slate-400 font-semibold">{user.name || user.email}</span>
              <Link 
                href="/pos" 
                className="w-9 h-9 rounded-lg bg-[var(--gradient-primary)] flex items-center justify-center text-white shadow-glow hover:scale-105 transition-transform" 
                title="Tạo đơn mới (POS)"
              >
                🛒
              </Link>
              <button
                onClick={logout}
                className="w-9 h-9 rounded-lg border border-[var(--color-border)] text-rose-400 hover:bg-rose-500/10 flex items-center justify-center hover:scale-105 transition-transform cursor-pointer"
                title="Đăng xuất"
              >
                🚪
              </button>
            </div>
          </header>

          {/* Children content wrapper */}
          <div className="flex-1 p-4 md:p-8">
            {children}
          </div>
        </main>

        {/* Mobile Bottom Navigation Bar */}
        <nav className="md:hidden bg-[var(--color-bg-secondary)]/95 backdrop-blur-md border-t border-white/5 flex overflow-x-auto whitespace-nowrap py-2 px-3 gap-1.5 items-center justify-start select-none scrollbar-none snap-x shrink-0">
          {NAV_ITEMS.map((item) => {
            const isActive = pathname === item.path || pathname.startsWith(item.path + '/');
            return (
              <Link
                key={item.path}
                href={item.path}
                className={`flex flex-col items-center justify-center min-w-[68px] py-1 px-1.5 rounded-xl transition-all duration-200 snap-center shrink-0 ${
                  isActive
                    ? 'text-indigo-400 bg-indigo-500/10 font-bold scale-105'
                    : 'text-slate-400 font-semibold hover:text-slate-200'
                }`}
              >
                <span className="text-lg mb-0.5">{item.icon}</span>
                <span className="text-[10px] tracking-tight">{item.label}</span>
              </Link>
            );
          })}
        </nav>
      </div>
    </div>
    </MuiProvider>
  );
}
