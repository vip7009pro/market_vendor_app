'use client';

import React, { useEffect, useMemo, useState } from 'react';
import { GridColDef, GridRowParams } from '@mui/x-data-grid';
import api from '@/lib/api';
import Modal from '@/components/ui/Modal';
import AppDataGrid, { toRowSelectionModel } from '@/components/ui/AppDataGrid';
import MasterDetailLayout from '@/components/ui/MasterDetailLayout';
import VietQrDisplay from '@/components/ui/VietQrDisplay';
import { buildVietQrAddInfoFromItems } from '@/lib/vietqr';
import { formatCurrency, formatDateTime } from '@/lib/format';
import { matchVietnamese } from '@/lib/text';
import { shareReceiptImage } from '@/lib/receiptShare';

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
  const [storeInfo, setStoreInfo] = useState<any>(null);

  // Edit Sale modal state
  const [editModalOpen, setEditModalOpen] = useState(false);
  const [editCustomerId, setEditCustomerId] = useState('walk-in');
  const [editCustomerName, setEditCustomerName] = useState('');
  const [editCreatedAt, setEditCreatedAt] = useState('');
  const [editDiscount, setEditDiscount] = useState(0);
  const [editPaidAmount, setEditPaidAmount] = useState(0);
  const [editPaymentType, setEditPaymentType] = useState<'CASH' | 'BANK'>('CASH');
  const [editNote, setEditNote] = useState('');
  const [editCart, setEditCart] = useState<any[]>([]);
  const [customers, setCustomers] = useState<any[]>([]);
  const [products, setProducts] = useState<any[]>([]);
  const [submittingEdit, setSubmittingEdit] = useState(false);
  const [editErrorMsg, setEditErrorMsg] = useState('');

  // Search Customer in Edit Sale dropdown
  const [editCustomerSearch, setEditCustomerSearch] = useState('');
  const [editCustomerDropdownOpen, setEditCustomerDropdownOpen] = useState(false);

  // Search Product to add in Edit Sale
  const [addingProductId, setAddingProductId] = useState('');
  const [addingQty, setAddingQty] = useState(1);

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
    
    api.getStoreInfo().then((store) => {
      setStoreInfo(store);
    }).catch(() => null);

    // Load products and customers for edit form
    api.getCustomers().then(data => setCustomers(data || [])).catch(() => null);
    api.getProducts().then(data => setProducts(data || [])).catch(() => null);
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

  const handleOpenEditSale = () => {
    if (!selectedSale) return;
    setEditCustomerId(selectedSale.customerId || 'walk-in');
    setEditCustomerName(selectedSale.customerName || 'Khách vãng lai');
    setEditCreatedAt(selectedSale.createdAt);
    setEditDiscount(Number(selectedSale.discount) || 0);
    setEditPaidAmount(Number(selectedSale.paidAmount) || 0);
    setEditPaymentType((selectedSale.paymentType || 'CASH') as 'CASH' | 'BANK');
    setEditNote(selectedSale.note || '');
    setEditCart(selectedSale.items.map(it => {
      const originalProduct = products.find(p => p.name === it.name || p.id === (it as any).productId);
      return {
        productId: (it as any).productId || originalProduct?.id || null,
        name: it.name,
        unitPrice: Number(it.unitPrice) || 0,
        quantity: Number(it.quantity) || 1,
        unit: it.unit || 'cái',
        itemType: (it as any).itemType || originalProduct?.itemType || 'RAW',
        mixItemsJson: (it as any).mixItemsJson || (originalProduct?.mixItems ? JSON.stringify(originalProduct.mixItems) : null)
      };
    }));
    setEditErrorMsg('');
    setEditModalOpen(true);
  };

  const removeFromEditCart = (idx: number) => {
    setEditCart(editCart.filter((_, i) => i !== idx));
  };

  const updateEditCartQty = (idx: number, delta: number) => {
    setEditCart(editCart.map((item, i) => {
      if (i !== idx) return item;
      return { ...item, quantity: Math.max(1, item.quantity + delta) };
    }));
  };

  const updateEditCartPrice = (idx: number, price: number) => {
    setEditCart(editCart.map((item, i) => {
      if (i !== idx) return item;
      return { ...item, unitPrice: Math.max(0, price) };
    }));
  };

  const addToEditCart = () => {
    if (!addingProductId) return;
    const prod = products.find(p => p.id === addingProductId);
    if (!prod) return;

    // Check if product already exists in edit cart
    const existingIdx = editCart.findIndex(it => it.productId === prod.id);
    if (existingIdx > -1) {
      setEditCart(editCart.map((it, i) => i === existingIdx ? { ...it, quantity: it.quantity + addingQty } : it));
    } else {
      setEditCart([...editCart, {
        productId: prod.id,
        name: prod.name,
        unitPrice: Number(prod.price) || 0,
        quantity: addingQty,
        unit: prod.unit || 'cái',
        itemType: prod.itemType || 'RAW',
        mixItemsJson: prod.mixItems ? JSON.stringify(prod.mixItems) : null
      }]);
    }
    setAddingProductId('');
    setAddingQty(1);
  };

  const getEditSubtotal = () => {
    return editCart.reduce((sum, item) => sum + (Number(item.unitPrice) * Number(item.quantity)), 0);
  };

  const getEditTotal = () => {
    return Math.max(0, getEditSubtotal() - editDiscount);
  };

  const handleEditSaleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setEditErrorMsg('');
    if (editCart.length === 0) {
      setEditErrorMsg('Đơn hàng phải có ít nhất 1 sản phẩm');
      return;
    }

    try {
      setSubmittingEdit(true);
      const payload = {
        customerId: editCustomerId === 'walk-in' ? null : editCustomerId,
        customerName: editCustomerId === 'walk-in' ? 'Khách vãng lai' : editCustomerName,
        discount: Number(editDiscount),
        paidAmount: Number(editPaidAmount),
        paymentType: editPaymentType,
        note: editNote || null,
        createdAt: editCreatedAt,
        items: editCart.map(it => ({
          productId: it.productId,
          name: it.name,
          unitPrice: Number(it.unitPrice),
          quantity: Number(it.quantity),
          unit: it.unit,
          itemType: it.itemType,
          mixItemsJson: it.mixItemsJson
        }))
      };

      const res = await api.updateSale(selectedSale!.id, payload);
      
      const updatedSale = {
        ...res.data,
        discount: Number(res.data.discount),
        paidAmount: Number(res.data.paidAmount),
        totalCost: Number(res.data.totalCost),
        items: (res.data.items || []).map((it: any) => ({
          ...it,
          unitPrice: Number(it.unitPrice),
          quantity: Number(it.quantity),
        })),
      };

      setSales(sales.map(s => s.id === selectedSale!.id ? updatedSale : s));
      setSelectedSale(updatedSale);
      setEditModalOpen(false);
    } catch (err: any) {
      setEditErrorMsg(err.message || 'Lỗi khi cập nhật đơn hàng');
    } finally {
      setSubmittingEdit(false);
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

            <div className="grid grid-cols-3 gap-2">
              <button
                onClick={async () => {
                  if (selectedSale) {
                    await shareReceiptImage({
                      id: selectedSale.id,
                      createdAt: selectedSale.createdAt,
                      customerName: selectedSale.customerName,
                      employeeName: null,
                      items: selectedSale.items.map((it) => ({
                        name: it.name,
                        quantity: it.quantity,
                        unitPrice: it.unitPrice,
                        unit: it.unit,
                      })),
                      discount: selectedSale.discount,
                      subtotal: saleTotal + selectedSale.discount,
                      total: saleTotal,
                      paidAmount: selectedSale.paidAmount,
                      paymentType: selectedSale.paymentType,
                    }, storeInfo);
                  }
                }}
                className="btn btn-secondary text-[11px] px-1 border-indigo-500/20 text-indigo-300 bg-indigo-500/5 hover:bg-indigo-500/10 py-2 flex items-center justify-center gap-1 font-semibold"
              >
                📱 Chia sẻ HĐ
              </button>
              <button
                onClick={handleOpenEditSale}
                className="btn btn-secondary text-[11px] px-1 border-emerald-500/20 text-emerald-300 bg-emerald-500/5 hover:bg-emerald-500/10 py-2 flex items-center justify-center gap-1 font-semibold"
              >
                ✏️ Sửa đơn
              </button>
              <button
                onClick={() => handleDeleteSale(selectedSale.id)}
                className="btn btn-secondary text-[11px] px-1 text-rose-400 border-rose-500/20 py-2 flex items-center justify-center gap-1 font-semibold"
              >
                🗑️ Hủy đơn
              </button>
            </div>
          </div>
        )}
      />
      <Modal open={editModalOpen} onClose={() => setEditModalOpen(false)} title="✏️ Chỉnh sửa chi tiết đơn hàng" maxWidth="max-w-4xl" closeOnBackdrop={false} contentClassName="max-h-[90vh] overflow-y-auto">
        {editErrorMsg && <div className="mb-4 p-3 rounded bg-rose-500/10 border border-rose-500/20 text-rose-400 text-xs">⚠️ {editErrorMsg}</div>}

        <form onSubmit={handleEditSaleSubmit} className="space-y-4 text-sm">
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            {/* Customer Search Autocomplete */}
            <div>
              <label className="block text-xs font-bold text-slate-400 uppercase mb-2">Khách hàng</label>
              <div className="relative">
                <input
                  type="text"
                  className="input text-xs pr-8 cursor-pointer"
                  placeholder="Tìm khách hàng..."
                  value={editCustomerDropdownOpen ? editCustomerSearch : (editCustomerId === 'walk-in' ? 'Khách vãng lai' : editCustomerName)}
                  onFocus={() => {
                    setEditCustomerSearch('');
                    setEditCustomerDropdownOpen(true);
                  }}
                  onChange={(e) => setEditCustomerSearch(e.target.value)}
                  onBlur={() => {
                    setTimeout(() => setEditCustomerDropdownOpen(false), 200);
                  }}
                />
                <span className="absolute right-3 top-3 text-slate-500 text-[10px] pointer-events-none">
                  {editCustomerDropdownOpen ? '▲' : '▼'}
                </span>
                
                {editCustomerDropdownOpen && (
                  <div className="absolute z-50 w-full mt-1 bg-[var(--color-bg-secondary)] border border-[var(--color-border)] rounded-xl shadow-xl max-h-56 overflow-y-auto p-1.5 space-y-0.5 backdrop-blur-md">
                    <div 
                      className="px-3.5 py-2.5 text-sm hover:bg-indigo-500/10 cursor-pointer text-[var(--color-text-secondary)] transition-colors"
                      onMouseDown={() => {
                        setEditCustomerId('walk-in');
                        setEditCustomerName('Khách vãng lai');
                        setEditCustomerDropdownOpen(false);
                      }}
                    >
                      Khách vãng lai
                    </div>
                    {customers
                      .filter(c => matchVietnamese(c.name, editCustomerSearch) || matchVietnamese(c.phone || '', editCustomerSearch))
                      .map(c => (
                        <div
                          key={c.id}
                          className="px-3.5 py-2.5 text-sm hover:bg-indigo-500/10 cursor-pointer text-[var(--color-text)] transition-colors"
                          onMouseDown={() => {
                            setEditCustomerId(c.id);
                            setEditCustomerName(c.name);
                            setEditCustomerDropdownOpen(false);
                          }}
                        >
                          <p className="font-semibold">{c.name}</p>
                          {c.phone && <p className="text-[11px] text-[var(--color-text-secondary)] mt-0.5">{c.phone}</p>}
                        </div>
                      ))
                    }
                  </div>
                )}
              </div>
            </div>

            {/* Note */}
            <div className="sm:col-span-2">
              <label className="block text-xs font-bold text-slate-400 uppercase mb-2">Ghi chú</label>
              <input type="text" className="input text-xs" value={editNote} onChange={(e) => setEditNote(e.target.value)} placeholder="Ghi chú đơn hàng..." />
            </div>
          </div>

          {/* Add products in edit modal */}
          <div className="border border-white/5 bg-slate-950/20 p-4 rounded-xl space-y-3">
            <h4 className="text-xs font-bold text-indigo-400 uppercase">Thêm sản phẩm mới</h4>
            <div className="grid grid-cols-1 sm:grid-cols-12 gap-3 items-end">
              <div className="sm:col-span-8">
                <label className="block text-[10px] font-bold text-slate-500 uppercase mb-1.5">Sản phẩm</label>
                <select className="input text-xs" value={addingProductId} onChange={(e) => setAddingProductId(e.target.value)}>
                  <option value="">Chọn sản phẩm...</option>
                  {products.map(p => <option key={p.id} value={p.id}>{p.name} ({formatCurrency(Number(p.price))})</option>)}
                </select>
              </div>
              <div className="sm:col-span-2">
                <label className="block text-[10px] font-bold text-slate-500 uppercase mb-1.5">SL</label>
                <input type="number" className="input text-xs" value={addingQty} onChange={(e) => setAddingQty(Number(e.target.value))} />
              </div>
              <div className="sm:col-span-2">
                <button type="button" onClick={addToEditCart} disabled={!addingProductId || addingQty <= 0} className="btn btn-primary w-full text-xs">Thêm</button>
              </div>
            </div>
          </div>

          {/* Items Table */}
          <div className="border border-white/5 rounded-xl overflow-hidden">
            <table className="w-full text-xs">
              <thead>
                <tr className="bg-slate-950/50 text-slate-500 uppercase">
                  <th className="py-2.5 px-3 text-left">Sản phẩm</th>
                  <th className="py-2.5 px-2 text-center w-32">Số lượng</th>
                  <th className="py-2.5 px-2 text-right w-36">Đơn giá bán</th>
                  <th className="py-2.5 px-3 text-right">Thành tiền</th>
                  <th className="py-2.5 px-2 w-12"></th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800">
                {editCart.map((item, idx) => (
                  <tr key={idx} className="hover:bg-white/[0.02]">
                    <td className="py-3 px-3 text-white">
                      <p className="font-semibold">{item.name}</p>
                      <p className="text-[10px] text-slate-400 mt-0.5">{item.itemType === 'MIX' ? 'Sản phẩm MIX' : 'Sản phẩm thường'}</p>
                    </td>
                    <td className="py-3 px-2 text-center">
                      <div className="flex items-center justify-center gap-1">
                        <button type="button" onClick={() => updateEditCartQty(idx, -1)} className="w-6 h-6 rounded bg-slate-800 text-slate-400 hover:text-white flex items-center justify-center font-bold">-</button>
                        <span className="w-8 text-center text-white">{item.quantity}</span>
                        <button type="button" onClick={() => updateEditCartQty(idx, 1)} className="w-6 h-6 rounded bg-slate-800 text-slate-400 hover:text-white flex items-center justify-center font-bold">+</button>
                      </div>
                    </td>
                    <td className="py-3 px-2">
                      <input 
                        type="number" 
                        className="input text-xs text-right py-1" 
                        value={item.unitPrice} 
                        onChange={(e) => updateEditCartPrice(idx, Number(e.target.value))} 
                      />
                    </td>
                    <td className="py-3 px-3 text-right font-semibold text-white">
                      {formatCurrency(Number(item.unitPrice) * item.quantity)}
                    </td>
                    <td className="py-3 px-2 text-center">
                      <button type="button" onClick={() => removeFromEditCart(idx)} className="text-rose-400 hover:text-rose-300 text-xs">🗑️</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Checkout Info */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-6 pt-4 border-t border-slate-800">
            <div className="space-y-3">
              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase mb-2">Giảm giá (VNĐ)</label>
                <input type="number" className="input text-xs" value={editDiscount === 0 ? '' : editDiscount} onChange={(e) => setEditDiscount(Number(e.target.value))} />
              </div>
              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase mb-2">Phương thức thanh toán</label>
                <div className="grid grid-cols-2 gap-2">
                  <button type="button" onClick={() => setEditPaymentType('CASH')} className={`btn py-2 text-xs font-semibold ${editPaymentType === 'CASH' ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30' : 'bg-slate-900 text-slate-500 border border-white/5'}`}>💵 Tiền mặt</button>
                  <button type="button" onClick={() => setEditPaymentType('BANK')} className={`btn py-2 text-xs font-semibold ${editPaymentType === 'BANK' ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30' : 'bg-slate-900 text-slate-500 border border-white/5'}`}>🏦 Chuyển khoản</button>
                </div>
              </div>
            </div>

            <div className="bg-slate-950/30 p-4 rounded-xl space-y-2.5 border border-white/5 text-xs">
              <div className="flex justify-between text-slate-400"><span>Tạm tính</span><span>{formatCurrency(getEditSubtotal())}</span></div>
              <div className="flex justify-between text-rose-400"><span>Giảm giá</span><span>-{formatCurrency(editDiscount)}</span></div>
              <div className="flex justify-between font-bold text-white text-sm"><span>Tổng cộng</span><span className="text-cyan-400">{formatCurrency(getEditTotal())}</span></div>
              
              <div className="pt-3 border-t border-slate-800">
                <label className="block text-[10px] font-bold text-slate-400 uppercase mb-1.5">Khách đã trả (VNĐ)</label>
                <input type="number" className="input text-xs text-right bg-slate-900 border-white/5" value={editPaidAmount} onChange={(e) => setEditPaidAmount(Number(e.target.value))} />
              </div>
              <div className="flex justify-between font-bold text-slate-400 mt-2">
                <span>Còn nợ</span>
                <span className={getEditTotal() - editPaidAmount > 0 ? 'text-amber-500' : 'text-emerald-400'}>
                  {formatCurrency(Math.max(0, getEditTotal() - editPaidAmount))}
                </span>
              </div>
            </div>
          </div>

          <div className="flex justify-end gap-3 pt-4 border-t border-slate-800">
            <button type="button" onClick={() => setEditModalOpen(false)} className="btn btn-secondary text-xs" disabled={submittingEdit}>Hủy</button>
            <button type="submit" className="btn btn-primary text-xs shadow-glow" disabled={submittingEdit}>{submittingEdit ? 'Đang lưu...' : 'Lưu thay đổi'}</button>
          </div>
        </form>
      </Modal>
    </div>
  );
}
