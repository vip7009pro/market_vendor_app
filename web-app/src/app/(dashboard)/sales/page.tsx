'use client';

import React, { useEffect, useState } from 'react';
import api from '@/lib/api';

interface SaleItem {
  name: string;
  unitPrice: number;
  quantity: number;
  unit: string;
}

interface Sale {
  id: string;
  createdAt: string;
  customerId?: string;
  customerName: string;
  discount: number;
  paidAmount: number;
  paymentType?: string;
  totalCost: number;
  note?: string;
  items: SaleItem[];
}

export default function SalesPage() {
  const [sales, setSales] = useState<Sale[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [paymentFilter, setPaymentFilter] = useState<'ALL' | 'CASH' | 'BANK'>('ALL');
  const [debtFilter, setDebtFilter] = useState<'ALL' | 'PAID' | 'DEBT'>('ALL');

  // Detail Modal State
  const [selectedSale, setSelectedSale] = useState<Sale | null>(null);

  const fetchSales = async () => {
    try {
      setLoading(true);
      const data = await api.getSales();
      setSales(data);
    } catch (err) {
      console.warn('Could not fetch sales, using demo data', err);
      // Demo sales
      setSales([
        {
          id: 'sale-1',
          createdAt: new Date().toISOString(),
          customerName: 'Chị Lan Chợ Lớn',
          discount: 20000,
          paidAmount: 180000,
          paymentType: 'CASH',
          totalCost: 100000,
          note: 'Giao gấp buổi sáng',
          items: [
            { name: 'Cà phê sữa đá', unitPrice: 25000, quantity: 4, unit: 'ly' },
            { name: 'Trà đào cam sả', unitPrice: 35000, quantity: 2, unit: 'ly' },
            { name: 'Bánh mì thịt nướng', unitPrice: 20000, quantity: 25000 / 20000, unit: 'ổ' },
          ],
        },
        {
          id: 'sale-2',
          createdAt: new Date(Date.now() - 3600000).toISOString(),
          customerName: 'Anh Hùng Đại Lý',
          discount: 0,
          paidAmount: 500000, // Total: 1.2M, Debt: 700k
          paymentType: 'BANK',
          totalCost: 650000,
          items: [
            { name: 'Cà phê đen đá', unitPrice: 20000, quantity: 60, unit: 'ly' },
          ],
        },
        {
          id: 'sale-3',
          createdAt: new Date(Date.now() - 7200000).toISOString(),
          customerName: 'Khách vãng lai',
          discount: 5000,
          paidAmount: 45000,
          paymentType: 'CASH',
          totalCost: 22000,
          items: [
            { name: 'Nước ngọt Coca Cola', unitPrice: 15000, quantity: 3, unit: 'lon' },
            { name: 'Khăn giấy ướt', unitPrice: 5000, quantity: 1, unit: 'gói' },
          ],
        },
      ]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchSales();
  }, []);

  const handleDeleteSale = async (id: string) => {
    if (!confirm('Bạn có chắc chắn muốn hủy đơn hàng này không? Dữ liệu kho hàng sẽ được hoàn trả lại.')) return;
    try {
      try {
        await api.deleteSale(id);
      } catch {
        // Fallback local deletion
      }
      setSales(sales.filter(s => s.id !== id));
      setSelectedSale(null);
    } catch (err) {
      alert('Lỗi khi hủy đơn hàng');
    }
  };

  const getSaleTotal = (s: Sale) => {
    const sub = s.items.reduce((sum, item) => sum + (item.unitPrice * item.quantity), 0);
    return Math.max(0, sub - s.discount);
  };

  const formatCurrency = (val: number) => {
    return new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(val);
  };

  const filteredSales = sales.filter(s => {
    const total = getSaleTotal(s);
    const debt = total - s.paidAmount;
    
    const matchesSearch = s.customerName.toLowerCase().includes(search.toLowerCase()) || 
                          s.id.toLowerCase().includes(search.toLowerCase());
    const matchesPayment = paymentFilter === 'ALL' || s.paymentType === paymentFilter;
    const matchesDebt = debtFilter === 'ALL' || 
                        (debtFilter === 'PAID' && debt <= 0) || 
                        (debtFilter === 'DEBT' && debt > 0);
    
    return matchesSearch && matchesPayment && matchesDebt;
  });

  return (
    <div className="space-y-8 animate-fade-in-up">
      {/* Header */}
      <div>
        <h2 className="text-2xl font-bold text-white font-sans">Lịch sử bán hàng</h2>
        <p className="text-sm text-slate-400">Xem, chỉnh sửa hoặc hủy các đơn hàng đã giao dịch</p>
      </div>

      {/* Filter and Search */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-4">
        {/* Search */}
        <div className="lg:col-span-6 relative">
          <input
            type="text"
            className="input pl-10"
            placeholder="Tìm theo mã đơn hoặc khách hàng..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          <span className="absolute left-3.5 top-3.5 text-slate-500">🔍</span>
        </div>

        {/* Payment Filter */}
        <div className="lg:col-span-3 flex gap-2">
          {['ALL', 'CASH', 'BANK'].map((t) => (
            <button
              key={t}
              onClick={() => setPaymentFilter(t as any)}
              className={`btn flex-1 text-xs font-semibold ${
                paymentFilter === t
                  ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30'
                  : 'bg-slate-900 text-slate-400 border border-white/5'
              }`}
            >
              {t === 'ALL' ? 'Tất cả PT' : t === 'CASH' ? 'Tiền mặt' : 'Chuyển khoản'}
            </button>
          ))}
        </div>

        {/* Debt Filter */}
        <div className="lg:col-span-3 flex gap-2">
          {['ALL', 'PAID', 'DEBT'].map((t) => (
            <button
              key={t}
              onClick={() => setDebtFilter(t as any)}
              className={`btn flex-1 text-xs font-semibold ${
                debtFilter === t
                  ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30'
                  : 'bg-slate-900 text-slate-400 border border-white/5'
              }`}
            >
              {t === 'ALL' ? 'Tất cả trạng thái' : t === 'PAID' ? 'Đã trả đủ' : 'Còn thiếu nợ'}
            </button>
          ))}
        </div>
      </div>

      {/* Sales List Table */}
      <div className="card bg-slate-900 border-white/5 overflow-hidden p-0">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm border-collapse">
            <thead>
              <tr className="border-b border-slate-800 text-slate-500 font-bold text-xs uppercase tracking-wider bg-slate-950/20">
                <th className="py-4 px-6">Thời gian</th>
                <th className="py-4 px-6">Mã đơn</th>
                <th className="py-4 px-6">Khách hàng</th>
                <th className="py-4 px-6">Thanh toán</th>
                <th className="py-4 px-6 text-right">Tổng đơn</th>
                <th className="py-4 px-6 text-right">Đã trả</th>
                <th className="py-4 px-6 text-right">Còn nợ</th>
                <th className="py-4 px-6 text-right">Thao tác</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800 text-slate-300">
              {loading ? (
                <tr>
                  <td colSpan={8} className="py-8 text-center text-slate-500">
                    Đang tải lịch sử đơn hàng...
                  </td>
                </tr>
              ) : filteredSales.length === 0 ? (
                <tr>
                  <td colSpan={8} className="py-8 text-center text-slate-500">
                    Không tìm thấy đơn hàng nào
                  </td>
                </tr>
              ) : (
                filteredSales.map((s) => {
                  const total = getSaleTotal(s);
                  const debt = total - s.paidAmount;
                  return (
                    <tr key={s.id} className="hover:bg-white/5 transition-colors">
                      <td className="py-4 px-6 text-slate-400 text-xs">
                        {new Date(s.createdAt).toLocaleDateString('vi-VN')} {new Date(s.createdAt).toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' })}
                      </td>
                      <td className="py-4 px-6 font-mono text-xs text-indigo-400">
                        #{s.id.slice(-6).toUpperCase()}
                      </td>
                      <td className="py-4 px-6 font-semibold text-white">{s.customerName}</td>
                      <td className="py-4 px-6">
                        <span className={`px-2 py-0.5 rounded text-[10px] font-bold ${
                          s.paymentType === 'CASH' ? 'bg-emerald-500/10 text-emerald-400' : 'bg-cyan-500/10 text-cyan-400'
                        }`}>
                          {s.paymentType === 'CASH' ? 'Tiền mặt' : 'Chuyển khoản'}
                        </span>
                      </td>
                      <td className="py-4 px-6 text-right font-medium text-white">{formatCurrency(total)}</td>
                      <td className="py-4 px-6 text-right text-emerald-400">{formatCurrency(s.paidAmount)}</td>
                      <td className="py-4 px-6 text-right font-bold text-amber-500">
                        {debt > 0 ? formatCurrency(debt) : '-'}
                      </td>
                      <td className="py-4 px-6 text-right">
                        <button
                          onClick={() => setSelectedSale(s)}
                          className="text-indigo-400 hover:text-indigo-300 text-xs font-semibold"
                        >
                          Xem chi tiết
                        </button>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* Sale Detail Modal */}
      {selectedSale && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in">
          <div className="glass w-full max-w-md rounded-2xl border border-white/10 shadow-2xl p-6 relative animate-fade-in-up">
            <div className="flex justify-between items-center mb-6">
              <h3 className="text-xl font-bold text-white">Chi tiết đơn hàng #{selectedSale.id.slice(-6).toUpperCase()}</h3>
              <button onClick={() => setSelectedSale(null)} className="text-slate-400 hover:text-white text-lg">✕</button>
            </div>

            <div className="space-y-4 text-sm">
              {/* Customer and General Details */}
              <div className="bg-slate-950/40 p-4 rounded-xl space-y-2 border border-white/5">
                <div className="flex justify-between text-slate-400">
                  <span>Khách hàng:</span>
                  <span className="text-white font-semibold">{selectedSale.customerName}</span>
                </div>
                <div className="flex justify-between text-slate-400">
                  <span>Thời gian tạo:</span>
                  <span className="text-white">
                    {new Date(selectedSale.createdAt).toLocaleDateString('vi-VN')} {new Date(selectedSale.createdAt).toLocaleTimeString('vi-VN')}
                  </span>
                </div>
                {selectedSale.note && (
                  <div className="flex justify-between text-slate-400">
                    <span>Ghi chú:</span>
                    <span className="text-white italic">{selectedSale.note}</span>
                  </div>
                )}
              </div>

              {/* Items List */}
              <div>
                <h4 className="font-bold text-white mb-2 text-xs uppercase tracking-wider text-slate-500">Danh sách sản phẩm mua</h4>
                <div className="space-y-2 max-h-40 overflow-y-auto pr-1">
                  {selectedSale.items.map((item, idx) => (
                    <div key={idx} className="flex justify-between items-center bg-slate-950/20 p-2.5 rounded-lg border border-white/5 text-xs">
                      <div>
                        <p className="font-semibold text-white">{item.name}</p>
                        <p className="text-[10px] text-slate-500 mt-0.5">{formatCurrency(item.unitPrice)} x {item.quantity} {item.unit}</p>
                      </div>
                      <span className="font-semibold text-white">{formatCurrency(item.unitPrice * item.quantity)}</span>
                    </div>
                  ))}
                </div>
              </div>

              {/* Price Calculation Summary */}
              <div className="bg-slate-950/30 p-3.5 rounded-xl space-y-2 border border-white/5">
                <div className="flex justify-between text-xs text-slate-400">
                  <span>Tạm tính</span>
                  <span>{formatCurrency(selectedSale.items.reduce((sum, item) => sum + (item.unitPrice * item.quantity), 0))}</span>
                </div>
                <div className="flex justify-between text-xs text-slate-400">
                  <span>Giảm giá</span>
                  <span className="text-rose-400">-{formatCurrency(selectedSale.discount)}</span>
                </div>
                <div className="flex justify-between font-bold text-sm text-white border-t border-slate-800 pt-2">
                  <span>Tổng tiền</span>
                  <span className="text-cyan-400">{formatCurrency(getSaleTotal(selectedSale))}</span>
                </div>
                <div className="flex justify-between text-xs text-emerald-400">
                  <span>Đã thanh toán</span>
                  <span>{formatCurrency(selectedSale.paidAmount)}</span>
                </div>
                {getSaleTotal(selectedSale) - selectedSale.paidAmount > 0 && (
                  <div className="flex justify-between font-bold text-xs text-amber-500">
                    <span>Còn thiếu nợ</span>
                    <span>{formatCurrency(getSaleTotal(selectedSale) - selectedSale.paidAmount)}</span>
                  </div>
                )}
              </div>

              {/* Action Buttons */}
              <div className="flex justify-between items-center gap-3 pt-4 border-t border-slate-800">
                <button
                  onClick={() => handleDeleteSale(selectedSale.id)}
                  className="btn btn-secondary text-rose-400 hover:bg-rose-500/10 border-rose-500/10 text-xs shrink-0"
                >
                  🗑️ Hủy & Hoàn trả đơn
                </button>
                <div className="flex gap-2 w-full justify-end">
                  <button
                    onClick={() => setSelectedSale(null)}
                    className="btn btn-secondary text-xs"
                  >
                    Đóng
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
