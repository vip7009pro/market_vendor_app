'use client';

import React, { useEffect, useMemo, useState } from 'react';
import { GridColDef, GridRowParams } from '@mui/x-data-grid';
import api from '@/lib/api';
import AppDataGrid, { toRowSelectionModel } from '@/components/ui/AppDataGrid';
import MasterDetailLayout from '@/components/ui/MasterDetailLayout';
import VietQrDisplay from '@/components/ui/VietQrDisplay';
import { buildVietQrAddInfoFromItems } from '@/lib/vietqr';
import { formatCurrency, formatDateTime } from '@/lib/format';
import { matchVietnamese } from '@/lib/text';

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

function getSaleTotal(s: Sale): number {
  const sub = (s.items || []).reduce((sum, item) => sum + item.unitPrice * item.quantity, 0);
  return Math.max(0, sub - Number(s.discount));
}

export default function SalesPage() {
  const [sales, setSales] = useState<Sale[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [paymentFilter, setPaymentFilter] = useState<'ALL' | 'CASH' | 'BANK'>('ALL');
  const [debtFilter, setDebtFilter] = useState<'ALL' | 'PAID' | 'DEBT'>('ALL');
  const [selectedSale, setSelectedSale] = useState<Sale | null>(null);
  const [bankAccount, setBankAccount] = useState<any>(null);

  const fetchSales = async () => {
    try {
      setLoading(true);
      const data = await api.getSales();
      setSales((data || []).map((s: any) => ({
        ...s,
        discount: Number(s.discount),
        paidAmount: Number(s.paidAmount),
        totalCost: Number(s.totalCost),
        items: (s.items || []).map((it: any) => ({
          ...it,
          unitPrice: Number(it.unitPrice),
          quantity: Number(it.quantity),
        })),
      })));
    } catch {
      setSales([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchSales();
    api.getBankAccounts().then((data) => {
      const defaultAcc = data?.find((acc: any) => acc.isDefault);
      setBankAccount(defaultAcc || data?.[0] || null);
    }).catch(() => null);
  }, []);

  const handleDeleteSale = async (id: string) => {
    if (!confirm('Hủy đơn hàng này? Tồn kho sẽ được hoàn trả.')) return;
    try {
      await api.deleteSale(id);
      setSales(sales.filter((s) => s.id !== id));
      if (selectedSale?.id === id) setSelectedSale(null);
    } catch {
      alert('Lỗi khi hủy đơn hàng');
    }
  };

  const filteredSales = useMemo(() => sales.filter((s) => {
    const total = getSaleTotal(s);
    const debt = total - s.paidAmount;
    const matchesSearch = matchVietnamese(s.customerName, search) || matchVietnamese(s.id, search);
    const matchesPayment = paymentFilter === 'ALL' || s.paymentType === paymentFilter;
    const matchesDebt = debtFilter === 'ALL' || (debtFilter === 'PAID' && debt <= 0) || (debtFilter === 'DEBT' && debt > 0);
    return matchesSearch && matchesPayment && matchesDebt;
  }), [sales, search, paymentFilter, debtFilter]);

  const rows = useMemo(() => filteredSales.map((s) => {
    const total = getSaleTotal(s);
    return {
      id: s.id,
      createdAt: s.createdAt,
      customerName: s.customerName,
      paymentType: s.paymentType === 'CASH' ? 'Tiền mặt' : s.paymentType === 'BANK' ? 'Chuyển khoản' : '—',
      total,
      paidAmount: s.paidAmount,
      debt: Math.max(0, total - s.paidAmount),
    };
  }), [filteredSales]);

  const columns: GridColDef[] = [
    { field: 'createdAt', headerName: 'Thời gian', width: 130, valueFormatter: (v) => formatDateTime(String(v)) },
    { field: 'id', headerName: 'Mã đơn', width: 90, valueFormatter: (v) => `#${String(v).slice(-6).toUpperCase()}` },
    { field: 'customerName', headerName: 'Khách hàng', flex: 1, minWidth: 140 },
    { field: 'paymentType', headerName: 'PT', width: 100 },
    { field: 'total', headerName: 'Tổng đơn', width: 120, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
    { field: 'paidAmount', headerName: 'Đã trả', width: 110, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
    { field: 'debt', headerName: 'Còn nợ', width: 110, align: 'right', headerAlign: 'right', valueFormatter: (v) => Number(v) > 0 ? formatCurrency(Number(v)) : '—' },
  ];

  const onRowClick = (params: GridRowParams) => {
    const s = sales.find((x) => x.id === params.id);
    if (s) setSelectedSale(s);
  };

  const saleTotal = selectedSale ? getSaleTotal(selectedSale) : 0;
  const saleDebt = selectedSale ? Math.max(0, saleTotal - selectedSale.paidAmount) : 0;

  return (
    <div className="space-y-6 animate-fade-in-up">
      <div>
        <h2 className="text-2xl font-bold text-white">Lịch sử bán hàng</h2>
        <p className="text-sm text-slate-400">Xem chi tiết đơn, VietQR và hủy đơn</p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-4">
        <div className="lg:col-span-6 relative">
          <input className="input pl-10" placeholder="Tìm mã đơn hoặc khách hàng..." value={search} onChange={(e) => setSearch(e.target.value)} />
          <span className="absolute left-3.5 top-3.5 text-slate-500">🔍</span>
        </div>
        <div className="lg:col-span-3 flex gap-2">
          {['ALL', 'CASH', 'BANK'].map((t) => (
            <button key={t} onClick={() => setPaymentFilter(t as any)} className={`btn flex-1 text-xs font-semibold ${paymentFilter === t ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30' : 'bg-slate-900 text-slate-400 border border-white/5'}`}>
              {t === 'ALL' ? 'Tất cả' : t === 'CASH' ? 'Tiền mặt' : 'CK'}
            </button>
          ))}
        </div>
        <div className="lg:col-span-3 flex gap-2">
          {['ALL', 'PAID', 'DEBT'].map((t) => (
            <button key={t} onClick={() => setDebtFilter(t as any)} className={`btn flex-1 text-xs font-semibold ${debtFilter === t ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30' : 'bg-slate-900 text-slate-400 border border-white/5'}`}>
              {t === 'ALL' ? 'Tất cả' : t === 'PAID' ? 'Đủ' : 'Nợ'}
            </button>
          ))}
        </div>
      </div>

      <MasterDetailLayout
        detailTitle={selectedSale ? `Đơn #${selectedSale.id.slice(-6).toUpperCase()}` : 'Chi tiết đơn hàng'}
        showDetail={!!selectedSale}
        list={<AppDataGrid rows={rows} columns={columns} loading={loading} height="100%" onRowClick={onRowClick} rowSelectionModel={toRowSelectionModel(selectedSale ? [selectedSale.id] : [])} />}
        detail={selectedSale && (
          <div className="space-y-4 text-sm">
            <div className="text-xs text-slate-400 space-y-1">
              <p><span className="text-slate-500">Khách:</span> <strong className="text-white">{selectedSale.customerName}</strong></p>
              <p><span className="text-slate-500">Thời gian:</span> {formatDateTime(selectedSale.createdAt)}</p>
              {selectedSale.note && <p><span className="text-slate-500">Ghi chú:</span> {selectedSale.note}</p>}
            </div>

            <div className="space-y-2 max-h-48 overflow-y-auto">
              {selectedSale.items.map((item, idx) => (
                <div key={idx} className="flex justify-between p-2.5 bg-slate-950/30 rounded-lg border border-white/5 text-xs">
                  <div>
                    <p className="font-semibold text-white">{item.name}</p>
                    <p className="text-slate-500">{formatCurrency(item.unitPrice)} × {item.quantity} {item.unit}</p>
                  </div>
                  <span className="font-semibold text-white">{formatCurrency(item.unitPrice * item.quantity)}</span>
                </div>
              ))}
            </div>

            <div className="bg-slate-950/30 p-3 rounded-xl space-y-1 text-xs border border-white/5">
              <div className="flex justify-between"><span>Giảm giá</span><span className="text-rose-400">-{formatCurrency(selectedSale.discount)}</span></div>
              <div className="flex justify-between font-bold"><span>Tổng</span><span className="text-cyan-400">{formatCurrency(saleTotal)}</span></div>
              <div className="flex justify-between text-emerald-400"><span>Đã trả</span><span>{formatCurrency(selectedSale.paidAmount)}</span></div>
              {saleDebt > 0 && <div className="flex justify-between text-amber-500 font-bold"><span>Còn nợ</span><span>{formatCurrency(saleDebt)}</span></div>}
            </div>

            {selectedSale.paymentType === 'BANK' && (
              <div className="bg-slate-950/30 p-4 rounded-xl border border-white/5">
                <VietQrDisplay
                  bank={bankAccount}
                  amount={saleDebt > 0 ? saleDebt : selectedSale.paidAmount}
                  description={buildVietQrAddInfoFromItems(selectedSale.id, selectedSale.items.map((i) => ({
                    name: i.name, quantity: i.quantity, unitPrice: i.unitPrice,
                  })))}
                  size="lg"
                />
              </div>
            )}

            <button onClick={() => handleDeleteSale(selectedSale.id)} className="btn btn-secondary text-xs text-rose-400 border-rose-500/20">🗑️ Hủy & Hoàn trả đơn</button>
          </div>
        )}
      />
    </div>
  );
}
