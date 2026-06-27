'use client';

import React, { useEffect, useMemo, useState } from 'react';
import { GridColDef, GridRowParams } from '@mui/x-data-grid';
import api from '@/lib/api';
import Modal from '@/components/ui/Modal';
import AppDataGrid, { toRowSelectionModel } from '@/components/ui/AppDataGrid';
import MasterDetailLayout from '@/components/ui/MasterDetailLayout';
import ProductSearchSelect from '@/components/ui/ProductSearchSelect';
import { formatCurrency, formatDateTime } from '@/lib/format';
import { matchVietnamese } from '@/lib/text';

interface PurchaseItem {
  id: string;
  productId: string;
  productName: string;
  quantity: number;
  unitCost: number;
  totalCost: number;
  note?: string;
}

interface PurchaseOrder {
  id: string;
  createdAt: string;
  supplierName?: string;
  supplierPhone?: string;
  discountType: 'AMOUNT' | 'PERCENT';
  discountValue: number;
  paidAmount: number;
  note?: string;
  items: PurchaseItem[];
  purchaseDocFileId?: string | null;
}

interface Product {
  id: string;
  name: string;
  price: number;
  costPrice: number;
  currentStock: number;
  unit: string;
  itemType: string;
}

interface Customer {
  id: string;
  name: string;
  phone?: string;
  isSupplier: boolean;
}

type CartItem = { product: Product; quantity: number; unitCost: number };

function calcOrderTotal(o: PurchaseOrder): number {
  const sub = (o.items || []).reduce((s, i) => s + Number(i.totalCost || i.quantity * i.unitCost), 0);
  if (o.discountType === 'PERCENT') return Math.max(0, sub * (1 - Number(o.discountValue) / 100));
  return Math.max(0, sub - Number(o.discountValue));
}

export default function PurchasesPage() {
  const [activeTab, setActiveTab] = useState<'orders' | 'history'>('orders');
  const [orders, setOrders] = useState<PurchaseOrder[]>([]);
  const [historyItems, setHistoryItems] = useState<any[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [suppliers, setSuppliers] = useState<Customer[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const todayStr = new Date().toISOString().slice(0, 10);
  const [startDate, setStartDate] = useState('2020-01-01');
  const [endDate, setEndDate] = useState(todayStr);
  const [selectedOrder, setSelectedOrder] = useState<PurchaseOrder | null>(null);

  const [modalOpen, setModalOpen] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');

  const [selectedSupplierId, setSelectedSupplierId] = useState('new');
  const [supplierName, setSupplierName] = useState('');
  const [supplierPhone, setSupplierPhone] = useState('');
  const [discountType, setDiscountType] = useState<'AMOUNT' | 'PERCENT'>('AMOUNT');
  const [discountValue, setDiscountValue] = useState(0);
  const [paidAmount, setPaidAmount] = useState(0);
  const [debtMode, setDebtMode] = useState(false);
  const [note, setNote] = useState('');
  const [purchaseCart, setPurchaseCart] = useState<CartItem[]>([]);

  const [addingProductId, setAddingProductId] = useState('');
  const [addingQty, setAddingQty] = useState(1);
  const [addingCost, setAddingCost] = useState(0);

  // Search supplier autocomplete
  const [supplierSearch, setSupplierSearch] = useState('');
  const [supplierDropdownOpen, setSupplierDropdownOpen] = useState(false);

  // Editing state
  const [editingOrderId, setEditingOrderId] = useState<string | null>(null);

  // Document upload state
  const [uploadingDocOrderId, setUploadingDocOrderId] = useState<string | null>(null);

  const loadData = async () => {
    try {
      setLoading(true);
      const [prodData, custData] = await Promise.all([
        api.getProducts().catch(() => []),
        api.getCustomers().catch(() => []),
      ]);
      setProducts((prodData || []).filter((p: Product) => p.itemType === 'RAW'));
      setSuppliers((custData || []).filter((c: Customer) => c.isSupplier));
      await fetchOrdersAndHistory();
    } finally {
      setLoading(false);
    }
  };

  const fetchOrdersAndHistory = async () => {
    const params: Record<string, string> = {};
    if (startDate) params.startDate = startDate;
    if (endDate) params.endDate = endDate;
    if (search) params.search = search;

    if (activeTab === 'orders') {
      const orderData = await api.getPurchases(params).catch(() => []);
      setOrders(orderData || []);
    } else {
      const histData = await api.getPurchaseHistory(params).catch(() => []);
      setHistoryItems(histData || []);
    }
  };

  useEffect(() => { loadData(); }, []);
  useEffect(() => { fetchOrdersAndHistory(); }, [activeTab, search, startDate, endDate]);
  useEffect(() => {
    if (!debtMode && modalOpen) setPaidAmount(getTotal());
  }, [purchaseCart, discountType, discountValue, debtMode, modalOpen]);

  const handleSupplierChange = (val: string) => {
    setSelectedSupplierId(val);
    if (val === 'new') {
      setSupplierName('');
      setSupplierPhone('');
    } else {
      const s = suppliers.find((x) => x.id === val);
      if (s) {
        setSupplierName(s.name);
        setSupplierPhone(s.phone || '');
      }
    }
  };

  const addToCart = () => {
    if (!addingProductId || addingQty <= 0) return;
    const p = products.find((x) => x.id === addingProductId);
    if (!p) return;
    const existing = purchaseCart.find((item) => item.product.id === addingProductId);
    if (existing) {
      setPurchaseCart(purchaseCart.map((item) =>
        item.product.id === addingProductId
          ? { ...item, quantity: item.quantity + addingQty, unitCost: addingCost || item.unitCost }
          : item
      ));
    } else {
      setPurchaseCart([...purchaseCart, { product: p, quantity: addingQty, unitCost: addingCost || p.costPrice }]);
    }
    setAddingProductId('');
    setAddingQty(1);
    setAddingCost(0);
  };

  const updateCartQty = (pid: string, delta: number) => {
    setPurchaseCart(purchaseCart.map((item) => {
      if (item.product.id !== pid) return item;
      const qty = Math.max(0, item.quantity + delta);
      return { ...item, quantity: qty };
    }).filter((item) => item.quantity > 0));
  };

  const updateCartField = (pid: string, field: 'quantity' | 'unitCost', value: number) => {
    setPurchaseCart(purchaseCart.map((item) =>
      item.product.id === pid ? { ...item, [field]: Math.max(field === 'quantity' ? 1 : 0, value) } : item
    ));
  };

  const removeFromCart = (pid: string) => {
    setPurchaseCart(purchaseCart.filter((item) => item.product.id !== pid));
  };

  const getSubtotal = () => purchaseCart.reduce((sum, item) => sum + item.quantity * item.unitCost, 0);
  const getTotal = () => {
    const sub = getSubtotal();
    if (discountType === 'PERCENT') return Math.max(0, sub * (1 - discountValue / 100));
    return Math.max(0, sub - discountValue);
  };

  const openAddModal = () => {
    setEditingOrderId(null);
    setSelectedSupplierId('new');
    setSupplierName('');
    setSupplierPhone('');
    setDiscountType('AMOUNT');
    setDiscountValue(0);
    setPaidAmount(0);
    setDebtMode(false);
    setNote('');
    setPurchaseCart([]);
    setErrorMsg('');
    setModalOpen(true);
  };

  const handlePickSupplierContact = async () => {
    if (typeof window !== 'undefined' && 'contacts' in navigator && 'ContactsManager' in window) {
      try {
        const props = ['name', 'tel'];
        const opts = { multiple: false };
        const contacts = await (navigator as any).contacts.select(props, opts);
        if (contacts && contacts.length > 0) {
          const contact = contacts[0];
          const nameVal = contact.name && contact.name[0] ? contact.name[0] : '';
          const phoneVal = contact.tel && contact.tel[0] ? contact.tel[0] : '';
          const cleanPhone = phoneVal.replace(/[\s\-\(\)]/g, '').replace(/^\+84/, '0');
          setSupplierName(nameVal);
          setSupplierPhone(cleanPhone);
        }
      } catch (err) {
        console.error('Contact picker error:', err);
      }
    } else {
      alert('Tính năng chọn từ danh bạ chỉ khả dụng trên thiết bị di động (Chrome/Android) qua kết nối HTTPS bảo mật.');
    }
  };

  const handleEditOrder = (order: PurchaseOrder) => {
    setEditingOrderId(order.id);
    const found = suppliers.find(s => s.name === order.supplierName);
    if (found) {
      setSelectedSupplierId(found.id);
    } else {
      setSelectedSupplierId('new');
    }
    setSupplierName(order.supplierName || '');
    setSupplierPhone(order.supplierPhone || '');
    setDiscountType(order.discountType);
    setDiscountValue(order.discountValue);
    setPaidAmount(order.paidAmount);
    setDebtMode(order.paidAmount < calcOrderTotal(order));
    setNote(order.note || '');
    
    setPurchaseCart(order.items.map((item) => {
      const product = products.find(p => p.id === item.productId) || {
        id: item.productId,
        name: item.productName,
        price: 0,
        costPrice: Number(item.unitCost),
        currentStock: 0,
        unit: 'cái',
        itemType: 'RAW',
      };
      return {
        product,
        quantity: Number(item.quantity),
        unitCost: Number(item.unitCost),
      };
    }));
    
    setErrorMsg('');
    setModalOpen(true);
  };

  const handleUploadPurchaseDoc = async (orderId: string, event: React.ChangeEvent<HTMLInputElement>) => {
    const files = event.target.files;
    if (!files || files.length === 0) return;
    const file = files[0];

    const reader = new FileReader();
    reader.onload = async (e) => {
      const base64Data = e.target?.result as string;
      if (!base64Data) return;

      try {
        setLoading(true);
        const uploadRes = await api.uploadFile(base64Data, file.name);
        const filePath = uploadRes.filePath;

        const currentOrder = orders.find(o => o.id === orderId);
        if (!currentOrder) return;

        const updated = await api.updatePurchase(orderId, {
          supplierName: currentOrder.supplierName,
          supplierPhone: currentOrder.supplierPhone,
          discountType: currentOrder.discountType,
          discountValue: Number(currentOrder.discountValue),
          paidAmount: Number(currentOrder.paidAmount),
          note: currentOrder.note,
          items: currentOrder.items.map(it => ({
            productId: it.productId,
            productName: it.productName,
            quantity: Number(it.quantity),
            unitCost: Number(it.unitCost)
          })),
          purchaseDocUploaded: true,
          purchaseDocFileId: filePath,
          purchaseDocUpdatedAt: new Date().toISOString()
        });

        setOrders(orders.map(o => o.id === orderId ? updated : o));
        if (selectedOrder?.id === orderId) {
          setSelectedOrder(updated);
        }
      } catch (err: any) {
        alert(err.message || 'Lỗi tải lên chứng từ');
      } finally {
        setLoading(false);
      }
    };
    reader.readAsDataURL(file);
  };

  const handleRemovePurchaseDoc = async (orderId: string) => {
    if (!confirm('Bạn có chắc chắn muốn xóa chứng từ đính kèm này?')) return;
    try {
      setLoading(true);
      const currentOrder = orders.find(o => o.id === orderId);
      if (!currentOrder) return;

      const updated = await api.updatePurchase(orderId, {
        supplierName: currentOrder.supplierName,
        supplierPhone: currentOrder.supplierPhone,
        discountType: currentOrder.discountType,
        discountValue: Number(currentOrder.discountValue),
        paidAmount: Number(currentOrder.paidAmount),
        note: currentOrder.note,
        items: currentOrder.items.map(it => ({
          productId: it.productId,
          productName: it.productName,
          quantity: Number(it.quantity),
          unitCost: Number(it.unitCost)
        })),
        purchaseDocUploaded: false,
        purchaseDocFileId: null,
        purchaseDocUpdatedAt: null
      });

      setOrders(orders.map(o => o.id === orderId ? updated : o));
      if (selectedOrder?.id === orderId) {
        setSelectedOrder(updated);
      }
    } catch (err: any) {
      alert(err.message || 'Lỗi khi xóa chứng từ');
    } finally {
      setLoading(false);
    }
  };

  const handleCheckoutSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (purchaseCart.length === 0) { setErrorMsg('Vui lòng thêm sản phẩm'); return; }
    if (!supplierName.trim()) { setErrorMsg('Vui lòng nhập tên nhà cung cấp'); return; }
    setSubmitting(true);
    
    const payload = {
      supplierName,
      supplierPhone: supplierPhone || null,
      discountType,
      discountValue: Number(discountValue),
      paidAmount: Number(paidAmount),
      note: note || null,
      items: purchaseCart.map((item) => ({
        productId: item.product.id,
        productName: item.product.name,
        quantity: Number(item.quantity),
        unitCost: Number(item.unitCost),
      })),
    };

    try {
      if (editingOrderId) {
        const res = await api.updatePurchase(editingOrderId, payload);
        setOrders(orders.map((o) => o.id === editingOrderId ? res : o));
        if (selectedOrder?.id === editingOrderId) {
          setSelectedOrder(res);
        }
      } else {
        const res = await api.createPurchase(payload);
        setOrders([res, ...orders]);
      }
      setModalOpen(false);
      fetchOrdersAndHistory();
    } catch (err: any) {
      setErrorMsg(err.message || 'Lỗi lưu đơn nhập hàng');
    } finally {
      setSubmitting(false);
    }
  };

  const handleDeleteOrder = async (id: string) => {
    if (!confirm('Xóa đơn nhập hàng này? Tồn kho và công nợ liên quan sẽ được hoàn trả.')) return;
    try {
      await api.deletePurchase(id);
      setOrders(orders.filter((o) => o.id !== id));
      if (selectedOrder?.id === id) setSelectedOrder(null);
      fetchOrdersAndHistory();
    } catch {
      alert('Không thể xóa đơn nhập hàng');
    }
  };

  const orderRows = useMemo(() => orders.map((o) => {
    const total = calcOrderTotal(o);
    return {
      id: o.id,
      createdAt: o.createdAt,
      supplierName: o.supplierName || '—',
      total,
      paidAmount: Number(o.paidAmount),
      debt: Math.max(0, total - Number(o.paidAmount)),
      note: o.note || '—',
    };
  }), [orders]);

  const orderColumns: GridColDef[] = [
    { field: 'id', headerName: 'Mã đơn', width: 100, valueFormatter: (v) => `#${String(v).slice(-6).toUpperCase()}` },
    { field: 'createdAt', headerName: 'Ngày nhập', width: 130, valueFormatter: (v) => formatDateTime(String(v)) },
    { field: 'supplierName', headerName: 'Nhà cung cấp', flex: 1, minWidth: 160 },
    { field: 'total', headerName: 'Tổng', width: 120, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
    { field: 'paidAmount', headerName: 'Đã trả', width: 110, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
    { field: 'debt', headerName: 'Còn nợ', width: 110, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
  ];

  const historyRows = useMemo(() => historyItems.map((h) => ({
    id: h.id,
    createdAt: h.createdAt,
    productName: h.productName,
    supplierName: h.supplierName || '—',
    quantity: Number(h.quantity),
    unitCost: Number(h.unitCost),
    totalCost: Number(h.totalCost),
  })), [historyItems]);

  const historyColumns: GridColDef[] = [
    { field: 'createdAt', headerName: 'Ngày', width: 110, valueFormatter: (v) => new Date(String(v)).toLocaleDateString('vi-VN') },
    { field: 'productName', headerName: 'Sản phẩm', flex: 1, minWidth: 140 },
    { field: 'supplierName', headerName: 'NCC', width: 140 },
    { field: 'quantity', headerName: 'SL', width: 70, align: 'center', headerAlign: 'center' },
    { field: 'unitCost', headerName: 'Đơn giá', width: 110, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
    { field: 'totalCost', headerName: 'Thành tiền', width: 120, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
  ];

  const onOrderRowClick = (params: GridRowParams) => {
    const o = orders.find((x) => x.id === params.id);
    if (o) setSelectedOrder(o);
  };

  return (
    <div className="space-y-6 animate-fade-in-up">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h2 className="text-2xl font-bold text-white">Nhập hàng & Kho vận</h2>
          <p className="text-sm text-slate-400">Quản lý đơn nhập, chỉnh sửa giá từng lô hàng</p>
        </div>
        <button onClick={openAddModal} className="btn btn-primary shadow-glow">📥 Tạo đơn nhập hàng</button>
      </div>

      <div className="flex border-b border-slate-800">
        <button onClick={() => { setActiveTab('orders'); setSelectedOrder(null); }} className={`px-6 py-3 text-sm font-bold border-b-2 ${activeTab === 'orders' ? 'border-indigo-500 text-indigo-400' : 'border-transparent text-slate-500'}`}>📜 Đơn nhập hàng</button>
        <button onClick={() => setActiveTab('history')} className={`px-6 py-3 text-sm font-bold border-b-2 ${activeTab === 'history' ? 'border-indigo-500 text-indigo-400' : 'border-transparent text-slate-500'}`}>📦 Lịch sử mặt hàng</button>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-12 gap-4">
        <div className="md:col-span-6 relative">
          <input className="input pl-10" placeholder={activeTab === 'orders' ? 'Tìm NCC, ghi chú...' : 'Tìm sản phẩm, NCC...'} value={search} onChange={(e) => setSearch(e.target.value)} />
          <span className="absolute left-3.5 top-3.5 text-slate-500">🔍</span>
        </div>
        <div className="md:col-span-3"><input type="date" className="input" value={startDate} onChange={(e) => setStartDate(e.target.value)} /></div>
        <div className="md:col-span-3"><input type="date" className="input" value={endDate} onChange={(e) => setEndDate(e.target.value)} /></div>
      </div>

      {activeTab === 'orders' ? (
        <MasterDetailLayout
          detailTitle={selectedOrder ? `Đơn #${selectedOrder.id.slice(-6).toUpperCase()}` : 'Chi tiết đơn nhập'}
          showDetail={!!selectedOrder}
          list={<AppDataGrid rows={orderRows} columns={orderColumns} loading={loading} height="100%" onRowClick={onOrderRowClick} rowSelectionModel={toRowSelectionModel(selectedOrder ? [selectedOrder.id] : [])} />}
          detail={selectedOrder && (
            <div className="space-y-4 text-sm">
              <div className="space-y-1 text-xs text-slate-400">
                <p><span className="text-slate-500">NCC:</span> <strong className="text-white">{selectedOrder.supplierName}</strong></p>
                <p><span className="text-slate-500">Ngày:</span> {formatDateTime(selectedOrder.createdAt)}</p>
                {selectedOrder.note && <p><span className="text-slate-500">Ghi chú:</span> {selectedOrder.note}</p>}
              </div>
              <div className="border border-white/5 rounded-xl overflow-hidden">
                <table className="w-full text-xs">
                  <thead><tr className="bg-slate-950/50 text-slate-500"><th className="py-2 px-3 text-left">SP</th><th className="py-2 px-2 text-center">SL</th><th className="py-2 px-2 text-right">Giá nhập</th><th className="py-2 px-3 text-right">T.Tiền</th></tr></thead>
                  <tbody className="divide-y divide-slate-800">
                    {(selectedOrder.items || []).map((it) => (
                      <tr key={it.id}>
                        <td className="py-2 px-3 text-white">{it.productName}</td>
                        <td className="py-2 px-2 text-center">{it.quantity}</td>
                        <td className="py-2 px-2 text-right">{formatCurrency(Number(it.unitCost))}</td>
                        <td className="py-2 px-3 text-right text-emerald-400">{formatCurrency(Number(it.totalCost || it.quantity * it.unitCost))}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <div className="text-xs space-y-1">
                <div className="flex justify-between"><span className="text-slate-500">Tổng đơn</span><span className="text-white font-bold">{formatCurrency(calcOrderTotal(selectedOrder))}</span></div>
                <div className="flex justify-between"><span className="text-slate-500">Đã trả</span><span className="text-emerald-400">{formatCurrency(Number(selectedOrder.paidAmount))}</span></div>
                <div className="flex justify-between"><span className="text-slate-500">Còn nợ</span><span className="text-rose-400">{formatCurrency(Math.max(0, calcOrderTotal(selectedOrder) - Number(selectedOrder.paidAmount)))}</span></div>
              </div>
              {/* Document upload / preview */}
              <div className="bg-slate-950/20 p-3 rounded-xl border border-white/5 space-y-2">
                <p className="text-[11px] font-bold text-slate-400 uppercase tracking-wider">Chứng từ đính kèm</p>
                {selectedOrder.purchaseDocFileId ? (
                  <div className="flex items-center justify-between gap-3">
                    <span className="text-xs text-slate-300 truncate max-w-[150px]">📎 {selectedOrder.purchaseDocFileId.split('/').pop()}</span>
                    <div className="flex gap-2">
                      <button 
                        onClick={(e) => {
                          e.stopPropagation();
                          window.open(`${api.baseUrl}/${selectedOrder.purchaseDocFileId}`, '_blank');
                        }}
                        className="btn btn-secondary py-1 px-2.5 text-[10px] font-semibold text-indigo-400 border-indigo-500/20 cursor-pointer"
                      >
                        👁️ Xem
                      </button>
                      <button 
                        onClick={() => handleRemovePurchaseDoc(selectedOrder.id)}
                        className="btn btn-secondary py-1 px-2.5 text-[10px] font-semibold text-rose-400 border-rose-500/20"
                      >
                        ❌ Xóa
                      </button>
                    </div>
                  </div>
                ) : (
                  <div className="flex items-center gap-3">
                    <label className="btn btn-secondary py-1 px-3 text-xs border-indigo-500/20 text-indigo-300 bg-indigo-500/5 hover:bg-indigo-500/10 cursor-pointer flex items-center justify-center gap-1.5 flex-1 font-semibold">
                      📤 Tải lên chứng từ
                      <input 
                        type="file" 
                        accept="image/*,application/pdf" 
                        className="hidden" 
                        onChange={(e) => handleUploadPurchaseDoc(selectedOrder.id, e)} 
                      />
                    </label>
                  </div>
                )}
              </div>

              <div className="flex gap-2">
                <button onClick={() => handleEditOrder(selectedOrder)} className="btn btn-secondary text-xs border-indigo-500/20 text-indigo-300 bg-indigo-500/5 hover:bg-indigo-500/10 flex-1 py-2 flex items-center justify-center gap-1.5 font-semibold">
                  ✏️ Sửa đơn nhập
                </button>
                <button onClick={() => handleDeleteOrder(selectedOrder.id)} className="btn btn-secondary text-xs text-rose-400 border-rose-500/20 flex-1 py-2 flex items-center justify-center gap-1.5 font-semibold">
                  🗑️ Xóa đơn nhập
                </button>
              </div>
            </div>
          )}
        />
      ) : (
        <AppDataGrid rows={historyRows} columns={historyColumns} loading={loading} height="calc(100vh - 270px)" />
      )}

      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title="📦 Nhập hàng vào kho" maxWidth="max-w-3xl" closeOnBackdrop={false} contentClassName="max-h-[90vh] overflow-y-auto">
        {errorMsg && <div className="mb-4 p-3 rounded bg-rose-500/10 border border-rose-500/20 text-rose-400 text-xs">⚠️ {errorMsg}</div>}

        <div className="space-y-4">
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            {/* Supplier Select */}
            <div>
              <label className="block text-xs font-bold text-slate-400 uppercase mb-2">Nhà cung cấp</label>
              <div className="relative">
                <input
                  type="text"
                  className="input text-xs pr-8 cursor-pointer"
                  placeholder="Tìm kiếm nhà cung cấp..."
                  value={supplierDropdownOpen ? supplierSearch : (selectedSupplierId === 'new' ? '+ Thêm mới' : suppliers.find(s => s.id === selectedSupplierId)?.name || '')}
                  onFocus={() => {
                    setSupplierSearch('');
                    setSupplierDropdownOpen(true);
                  }}
                  onChange={(e) => setSupplierSearch(e.target.value)}
                  onBlur={() => {
                    setTimeout(() => setSupplierDropdownOpen(false), 200);
                  }}
                />
                <span className="absolute right-3 top-3 text-slate-500 text-[10px] pointer-events-none">
                  {supplierDropdownOpen ? '▲' : '▼'}
                </span>
                
                {supplierDropdownOpen && (
                  <div className="absolute z-50 w-full mt-1 bg-slate-900 border border-white/10 rounded-lg shadow-xl max-h-56 overflow-y-auto divide-y divide-white/5 backdrop-blur-md">
                    <div 
                      className="px-3 py-2.5 text-xs hover:bg-indigo-500/10 cursor-pointer text-indigo-400 font-bold transition-colors"
                      onMouseDown={() => {
                        handleSupplierChange('new');
                        setSupplierDropdownOpen(false);
                      }}
                    >
                      ➕ Thêm mới nhà cung cấp
                    </div>
                    {suppliers
                      .filter(s => matchVietnamese(s.name, supplierSearch) || matchVietnamese(s.phone || '', supplierSearch))
                      .map(s => (
                        <div
                          key={s.id}
                          className="px-3 py-2.5 text-xs hover:bg-indigo-500/10 cursor-pointer text-white transition-colors"
                          onMouseDown={() => {
                            handleSupplierChange(s.id);
                            setSupplierDropdownOpen(false);
                          }}
                        >
                          <p className="font-semibold">{s.name}</p>
                          {s.phone && <p className="text-[10px] text-slate-400 mt-0.5">{s.phone}</p>}
                        </div>
                      ))
                    }
                  </div>
                )}
              </div>
            </div>

            {/* Supplier Name */}
            <div>
              <label className="block text-xs font-bold text-slate-400 uppercase mb-2">Tên nhà cung cấp</label>
              <input className="input text-xs" value={supplierName} onChange={(e) => setSupplierName(e.target.value)} disabled={selectedSupplierId !== 'new'} placeholder="Tên nhà cung cấp mới..." />
            </div>

            {/* Supplier Phone */}
            <div>
              <div className="flex justify-between items-center mb-2">
                <label className="block text-xs font-bold text-slate-400 uppercase">SĐT nhà cung cấp</label>
                {selectedSupplierId === 'new' && (
                  <button
                    type="button"
                    onClick={handlePickSupplierContact}
                    className="text-[9px] text-indigo-400 hover:text-indigo-300 font-bold uppercase flex items-center gap-1 transition-colors"
                  >
                    📱 Danh bạ
                  </button>
                )}
              </div>
              <input className="input text-xs" value={supplierPhone} onChange={(e) => setSupplierPhone(e.target.value)} disabled={selectedSupplierId !== 'new'} placeholder="Số điện thoại..." />
            </div>
          </div>

          <div className="border border-white/5 bg-slate-950/20 p-4 rounded-xl space-y-3">
            <h4 className="text-xs font-bold text-indigo-400 uppercase">Thêm sản phẩm</h4>
            <div className="grid grid-cols-1 sm:grid-cols-12 gap-3 items-end">
              <div className="sm:col-span-5">
                <label className="block text-[10px] font-bold text-slate-500 uppercase mb-1.5">Tìm sản phẩm (Enter để chọn)</label>
                <ProductSearchSelect
                  products={products}
                  value={addingProductId}
                  onChange={setAddingProductId}
                  onSelect={(p) => setAddingCost(Number(p.costPrice) || 0)}
                />
              </div>
              <div className="sm:col-span-3">
                <label className="block text-[10px] font-bold text-slate-500 uppercase mb-1.5">Đơn giá nhập</label>
                <input type="number" className="input text-xs" value={addingCost || ''} onChange={(e) => setAddingCost(Number(e.target.value))} />
              </div>
              <div className="sm:col-span-2">
                <label className="block text-[10px] font-bold text-slate-500 uppercase mb-1.5">SL</label>
                <input type="number" className="input text-xs" value={addingQty} onChange={(e) => setAddingQty(Number(e.target.value))} />
              </div>
              <div className="sm:col-span-2">
                <button type="button" onClick={addToCart} disabled={!addingProductId || addingQty <= 0} className="btn btn-primary w-full text-xs">Thêm</button>
              </div>
            </div>
          </div>

          <div className="border border-white/5 rounded-xl overflow-hidden">
            <table className="w-full text-xs">
              <thead>
                <tr className="bg-slate-950/50 text-slate-500 uppercase">
                  <th className="py-2.5 px-3 text-left">Sản phẩm</th>
                  <th className="py-2.5 px-2 text-center w-36">Số lượng</th>
                  <th className="py-2.5 px-2 text-right w-32">Đơn giá</th>
                  <th className="py-2.5 px-3 text-right">Thành tiền</th>
                  <th className="py-2.5 px-2 w-12"></th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800">
                {purchaseCart.length === 0 ? (
                  <tr><td colSpan={5} className="py-6 text-center text-slate-500 italic">Chưa có sản phẩm</td></tr>
                ) : purchaseCart.map((item) => (
                  <tr key={item.product.id}>
                    <td className="py-2 px-3 font-semibold text-white">{item.product.name}</td>
                    <td className="py-2 px-2">
                      <div className="flex items-center justify-center gap-1">
                        <button type="button" onClick={() => updateCartQty(item.product.id, -1)} className="w-7 h-7 rounded bg-slate-800 text-slate-300 text-sm">−</button>
                        <input
                          type="number"
                          className="input h-7 w-14 text-center text-xs px-1"
                          value={item.quantity}
                          onChange={(e) => updateCartField(item.product.id, 'quantity', Number(e.target.value))}
                        />
                        <button type="button" onClick={() => updateCartQty(item.product.id, 1)} className="w-7 h-7 rounded bg-slate-800 text-slate-300 text-sm">+</button>
                      </div>
                    </td>
                    <td className="py-2 px-2">
                      <input
                        type="number"
                        className="input h-7 text-xs text-right"
                        value={item.unitCost || ''}
                        onChange={(e) => updateCartField(item.product.id, 'unitCost', Number(e.target.value))}
                      />
                    </td>
                    <td className="py-2 px-3 text-right text-emerald-400 font-semibold">{formatCurrency(item.quantity * item.unitCost)}</td>
                    <td className="py-2 px-2 text-center">
                      <button type="button" onClick={() => removeFromCart(item.product.id)} className="text-rose-400 text-sm">✕</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div className="space-y-3">
              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase mb-2">Chiết khấu</label>
                <div className="flex gap-2">
                  <select className="input text-xs w-1/3" value={discountType} onChange={(e) => setDiscountType(e.target.value as any)}>
                    <option value="AMOUNT">VNĐ</option>
                    <option value="PERCENT">%</option>
                  </select>
                  <input type="number" className="input text-xs w-2/3" value={discountValue} onChange={(e) => setDiscountValue(Number(e.target.value))} />
                </div>
              </div>
              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase mb-2">Đã thanh toán</label>
                <input type="number" className="input text-xs" value={paidAmount} onChange={(e) => { setPaidAmount(Number(e.target.value)); setDebtMode(Number(e.target.value) < getTotal()); }} />
                <div className="flex gap-2 mt-2">
                  <button type="button" onClick={() => { setDebtMode(true); setPaidAmount(0); }} className="btn py-1 px-2 text-[10px] bg-rose-500/10 text-rose-400 border border-rose-500/20 rounded-lg">Nợ tất</button>
                  <button type="button" onClick={() => { setDebtMode(false); setPaidAmount(getTotal()); }} className="btn py-1 px-2 text-[10px] bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 rounded-lg">Trả hết</button>
                </div>
              </div>
              <textarea className="input min-h-[50px] text-xs" placeholder="Ghi chú đơn nhập..." value={note} onChange={(e) => setNote(e.target.value)} />
            </div>
            <div className="bg-slate-950/20 border border-white/5 rounded-xl p-4 text-xs space-y-2">
              <div className="flex justify-between"><span>Tổng hàng</span><span className="font-bold">{formatCurrency(getSubtotal())}</span></div>
              <div className="flex justify-between border-t border-slate-800 pt-2"><span>Tổng thanh toán</span><span className="text-indigo-400 font-bold">{formatCurrency(getTotal())}</span></div>
              <div className="flex justify-between"><span>Còn nợ NCC</span><span className="text-rose-400 font-bold">{formatCurrency(Math.max(0, getTotal() - paidAmount))}</span></div>
            </div>
          </div>

          <div className="flex justify-end gap-3 pt-3 border-t border-slate-800">
            <button type="button" onClick={() => setModalOpen(false)} className="btn btn-secondary text-xs" disabled={submitting}>Hủy</button>
            <button type="button" onClick={handleCheckoutSubmit} className="btn btn-primary text-xs shadow-glow" disabled={submitting || purchaseCart.length === 0}>
              {submitting ? 'Đang tạo...' : 'Xác nhận nhập hàng'}
            </button>
          </div>
        </div>
      </Modal>
    </div>
  );
}
