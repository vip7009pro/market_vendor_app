'use client';

import React, { useState } from 'react';

export default function ReportsPage() {
  const [timeRange, setTimeRange] = useState<'WEEK' | 'MONTH' | 'YEAR'>('WEEK');

  // Hardcoded premium reports data for visualization
  const reportData = {
    WEEK: {
      revenue: 14850000,
      cost: 7200000,
      profit: 7650000,
      expenses: 1250000,
      netProfit: 6400000,
      chartData: [
        { label: 'Thứ 2', revenue: 1800000, profit: 900000 },
        { label: 'Thứ 3', revenue: 2100000, profit: 1100000 },
        { label: 'Thứ 4', revenue: 1500000, profit: 800000 },
        { label: 'Thứ 5', revenue: 2500000, profit: 1300000 },
        { label: 'Thứ 6', revenue: 3100000, profit: 1600000 },
        { label: 'Thứ 7', revenue: 2350000, profit: 1150000 },
        { label: 'Chủ Nhật', revenue: 1500000, profit: 800000 },
      ],
      topProducts: [
        { name: 'Cà phê sữa đá', quantity: 182, totalRev: 4550000 },
        { name: 'Cà phê đen đá', quantity: 124, totalRev: 2480000 },
        { name: 'Trà đào cam sả', quantity: 95, totalRev: 3325000 },
      ]
    },
    MONTH: {
      revenue: 62400000,
      cost: 31200000,
      profit: 31200000,
      expenses: 5600000,
      netProfit: 25600000,
      chartData: [
        { label: 'Tuần 1', revenue: 14000000, profit: 7000000 },
        { label: 'Tuần 2', revenue: 16500000, profit: 8200000 },
        { label: 'Tuần 3', revenue: 15800000, profit: 7900000 },
        { label: 'Tuần 4', revenue: 16100000, profit: 8100000 },
      ],
      topProducts: [
        { name: 'Cà phê sữa đá', quantity: 720, totalRev: 18000000 },
        { name: 'Cà phê đen đá', quantity: 512, totalRev: 10240000 },
        { name: 'Trà đào cam sả', quantity: 380, totalRev: 13300000 },
      ]
    },
    YEAR: {
      revenue: 780000000,
      cost: 390000000,
      profit: 390000000,
      expenses: 72000000,
      netProfit: 318000000,
      chartData: [
        { label: 'T1', revenue: 58000000, profit: 29000000 },
        { label: 'T2', revenue: 62000000, profit: 31000000 },
        { label: 'T3', revenue: 65000000, profit: 32500000 },
        { label: 'T4', revenue: 71000000, profit: 35500000 },
        { label: 'T5', revenue: 68000000, profit: 34000000 },
        { label: 'T6', revenue: 75000000, profit: 37500000 },
        { label: 'T7', revenue: 70000000, profit: 35000000 },
        { label: 'T8', revenue: 72000000, profit: 36000000 },
        { label: 'T9', revenue: 69000000, profit: 34500000 },
        { label: 'T10', revenue: 74000000, profit: 37000000 },
        { label: 'T11', revenue: 78000000, profit: 39000000 },
        { label: 'T12', revenue: 88000000, profit: 44000000 },
      ],
      topProducts: [
        { name: 'Cà phê sữa đá', quantity: 8640, totalRev: 216000000 },
        { name: 'Cà phê đen đá', quantity: 6140, totalRev: 122800000 },
        { name: 'Trà đào cam sả', quantity: 4560, totalRev: 159600000 },
      ]
    }
  };

  const activeData = reportData[timeRange];

  const formatCurrency = (val: number) => {
    return new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(val);
  };

  // Find max value in chart data for relative height calculations
  const maxRevenue = Math.max(...activeData.chartData.map(d => d.revenue));

  return (
    <div className="space-y-8 animate-fade-in-up">
      {/* Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h2 className="text-2xl font-bold text-white font-sans">Báo cáo doanh thu & lợi nhuận</h2>
          <p className="text-sm text-slate-400">Xem thống kê tình hình kinh doanh của cửa hàng</p>
        </div>

        {/* Filter select */}
        <div className="flex gap-2">
          {['WEEK', 'MONTH', 'YEAR'].map((t) => (
            <button
              key={t}
              onClick={() => setTimeRange(t as any)}
              className={`btn px-4 py-2 text-xs font-semibold ${
                timeRange === t
                  ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30'
                  : 'bg-slate-900 text-slate-400 border border-white/5'
              }`}
            >
              {t === 'WEEK' ? 'Tuần này' : t === 'MONTH' ? 'Tháng này' : 'Năm nay'}
            </button>
          ))}
        </div>
      </div>

      {/* Numerical Metrics Summary */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-6">
        <div className="card bg-slate-900 border-white/5 flex items-center gap-4 relative overflow-hidden group">
          <div className="absolute top-0 right-0 w-24 h-24 bg-cyan-500/5 rounded-full -mr-8 -mt-8"></div>
          <div className="w-12 h-12 rounded-xl bg-cyan-500/10 flex items-center justify-center text-xl text-cyan-400">
            📈
          </div>
          <div>
            <p className="text-xs text-slate-500 font-semibold uppercase tracking-wider">Tổng doanh thu</p>
            <h3 className="text-xl font-bold text-white mt-1">{formatCurrency(activeData.revenue)}</h3>
          </div>
        </div>

        <div className="card bg-slate-900 border-white/5 flex items-center gap-4 relative overflow-hidden group">
          <div className="absolute top-0 right-0 w-24 h-24 bg-rose-500/5 rounded-full -mr-8 -mt-8"></div>
          <div className="w-12 h-12 rounded-xl bg-rose-500/10 flex items-center justify-center text-xl text-rose-400">
            💸
          </div>
          <div>
            <p className="text-xs text-slate-500 font-semibold uppercase tracking-wider">Tổng chi phí phát sinh</p>
            <h3 className="text-xl font-bold text-rose-400 mt-1">{formatCurrency(activeData.expenses)}</h3>
          </div>
        </div>

        <div className="card bg-slate-900 border-white/5 flex items-center gap-4 relative overflow-hidden group">
          <div className="absolute top-0 right-0 w-24 h-24 bg-emerald-500/5 rounded-full -mr-8 -mt-8"></div>
          <div className="w-12 h-12 rounded-xl bg-emerald-500/10 flex items-center justify-center text-xl text-emerald-400">
            ✨
          </div>
          <div>
            <p className="text-xs text-slate-500 font-semibold uppercase tracking-wider">Lợi nhuận ròng thực tế</p>
            <h3 className="text-xl font-bold text-emerald-400 mt-1">{formatCurrency(activeData.netProfit)}</h3>
          </div>
        </div>
      </div>

      {/* Chart Section & Top Selling Products */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* Custom Premium Chart Representation */}
        <div className="lg:col-span-2 card bg-slate-900 border-white/5 space-y-6">
          <h4 className="font-bold text-white text-base">Biểu đồ doanh thu & lợi nhuận</h4>
          
          <div className="h-64 flex items-end justify-between gap-3 pt-6 border-b border-slate-800 pb-2 relative">
            {/* Chart Guide Y-axis labels */}
            <div className="absolute left-0 top-0 bottom-0 flex flex-col justify-between text-[10px] text-slate-600 pointer-events-none pr-4 bg-slate-900/80">
              <span>{formatCurrency(maxRevenue)}</span>
              <span>{formatCurrency(maxRevenue * 0.5)}</span>
              <span>0 đ</span>
            </div>

            {activeData.chartData.map((d, idx) => {
              const revPercent = (d.revenue / maxRevenue) * 100;
              const profPercent = (d.profit / maxRevenue) * 100;
              return (
                <div key={idx} className="flex-1 flex flex-col items-center gap-2 group cursor-pointer relative z-10 pl-6">
                  {/* Visual columns */}
                  <div className="w-full flex justify-center gap-1 items-end h-48 relative">
                    {/* Revenue Bar */}
                    <div
                      style={{ height: `${revPercent}%` }}
                      className="w-4 bg-indigo-500/25 group-hover:bg-indigo-500/40 rounded-t transition-all duration-300 relative"
                      title={`Doanh thu: ${formatCurrency(d.revenue)}`}
                    ></div>
                    {/* Profit Bar */}
                    <div
                      style={{ height: `${profPercent}%` }}
                      className="w-4 bg-gradient-to-t from-indigo-500 to-cyan-400 rounded-t transition-all duration-300 relative shadow-lg shadow-indigo-500/10"
                      title={`Lợi nhuận: ${formatCurrency(d.profit)}`}
                    ></div>
                  </div>
                  {/* Label */}
                  <span className="text-[10px] text-slate-500 font-semibold">{d.label}</span>
                </div>
              );
            })}
          </div>
          
          {/* Chart Legend */}
          <div className="flex justify-center gap-6 text-xs font-semibold">
            <div className="flex items-center gap-2">
              <span className="w-3.5 h-3.5 rounded bg-indigo-500/20 border border-indigo-500/30"></span>
              <span className="text-slate-400">Doanh thu bán hàng</span>
            </div>
            <div className="flex items-center gap-2">
              <span className="w-3.5 h-3.5 rounded bg-gradient-to-tr from-indigo-500 to-cyan-400"></span>
              <span className="text-slate-400">Lợi nhuận thu về</span>
            </div>
          </div>
        </div>

        {/* Top Products */}
        <div className="card bg-slate-900 border-white/5 space-y-6">
          <h4 className="font-bold text-white text-base">Sản phẩm bán chạy nhất</h4>
          
          <div className="space-y-4">
            {activeData.topProducts.map((p, idx) => (
              <div key={idx} className="flex items-center justify-between p-3.5 rounded-xl border border-white/5 bg-slate-950/20 group">
                <div className="flex items-center gap-3">
                  <div className="w-8 h-8 rounded-lg bg-indigo-500/10 text-indigo-400 font-bold flex items-center justify-center text-xs">
                    #{idx + 1}
                  </div>
                  <div>
                    <p className="font-semibold text-white text-xs">{p.name}</p>
                    <p className="text-[10px] text-slate-500 mt-0.5">Số lượng bán: {p.quantity}</p>
                  </div>
                </div>
                <span className="font-bold text-indigo-300 text-xs">{formatCurrency(p.totalRev)}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
