'use client';

import React, { useEffect, useState } from 'react';
import api from '@/lib/api';

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

export default function PurchasesPage() {
  const [activeTab, setActiveTab] = useState<'orders' | 'history'>('orders');
  const [orders, setOrders] = useState<PurchaseOrder[]>([]);
  const [historyItems, setHistoryItems] = useState<any[]>([]);
  const [products, setProducts] = useState<Product[]>([]);
  const [suppliers, setSuppliers] = useState<Customer[]>([]);
  const [loading, setLoading] = useState(true);
  
  // Search and filters
  const [search, setSearch] = useState('');
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');

  // Modal State
  const [modalOpen, setModalOpen] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');

  // Form State
  const [selectedSupplierId, setSelectedSupplierId] = useState<string>('new');
  const [supplierName, setSupplierName] = useState('');
  const [supplierPhone, setSupplierPhone] = useState('');
  const [discountType, setDiscountType] = useState<'AMOUNT' | 'PERCENT'>('AMOUNT');
  const [discountValue, setDiscountValue] = useState(0);
  const [paidAmount, setPaidAmount] = useState(0);
  const [note, setNote] = useState('');
  
  // Purchase Cart State
  const [purchaseCart, setPurchaseCart] = useState<Array<{
    product: Product;
    quantity: number;
    unitCost: number;
  }>>([]);
  
  // Product Selector inside Cart State
  const [addingProductId, setAddingProductId] = useState('');
  const [addingQty, setAddingQty] = useState(1);
  const [addingCost, setAddingCost] = useState(0);

  const loadData = async () => {
    try {
      setLoading(true);
      const [prodData, custData] = await Promise.all([
        api.getProducts().catch(() => null),
        api.getCustomers().catch(() => null),
      ]);

      if (prodData) {
        setProducts(prodData.filter((p: any) => p.itemType === 'RAW')); // RAW items are stocked items
      }
      
      if (custData) {
        setSuppliers(custData.filter((c: any) => c.isSupplier));
      }

      await fetchOrdersAndHistory();
    } catch (err) {
      console.error('Error loading foundation data:', err);
    } finally {
      setLoading(false);
    }
  };

  const fetchOrdersAndHistory = async () => {
    try {
      const params: Record<string, string> = {};
      if (startDate) params.startDate = startDate;
      if (endDate) params.endDate = endDate;
      if (search) params.search = search;

      if (activeTab === 'orders') {
        const orderData = await api.getPurchases(params).catch(() => null);
        if (orderData) {
          setOrders(orderData);
        } else {
          // Demo fallback
          setOrders([
            {
              id: 'po-1',
              createdAt: new Date(Date.now() - 86400000 * 2).toISOString(),
              supplierName: 'Nhà cung cấp Hạt Cà Phê Trung Nguyên',
              supplierPhone: '0281234567',
              discountType: 'AMOUNT',
              discountValue: 100000,
              paidAmount: 2000000,
              note: 'Nhập hạt cafe Arabica đợt cuối tháng',
              items: [
                { id: 'pi-1', productId: '3', productName: 'Nước ngọt Coca Cola', quantity: 100, unitCost: 10500, totalCost: 1050000 }
              ]
            }
          ]);
        }
      } else {
        const histData = await api.getPurchaseHistory(params).catch(() => null);
        if (histData) {
          setHistoryItems(histData);
        } else {
          // Demo fallback
          setHistoryItems([
            {
              id: 'pi-1',
              createdAt: new Date(Date.now() - 86400000 * 2).toISOString(),
              productId: '3',
              productName: 'Nước ngọt Coca Cola',
              quantity: 100,
              unitCost: 10500,
              totalCost: 1050000,
              supplierName: 'Nhà cung cấp Hạt Cà Phê Trung Nguyên',
              note: 'Lô hàng lon nhôm',
            }
          ]);
        }
      }
    } catch (err) {
      console.error('Error fetching data:', err);
    }
  };

  useEffect(() => {
    loadData();
  }, []);

  useEffect(() => {
    fetchOrdersAndHistory();
  }, [activeTab, search, startDate, endDate]);

  const handleSupplierChange = (val: string) => {
    setSelectedSupplierId(val);
    if (val === 'new') {
      setSupplierName('');
      setSupplierPhone('');
    } else {
      const s = suppliers.find(x => x.id === val);
      if (s) {
        setSupplierName(s.name);
        setSupplierPhone(s.phone || '');
      }
    }
  };

  const handleProductSelectForAdd = (val: string) => {
    setAddingProductId(val);
    const p = products.find(x => x.id === val);
    if (p) {
      setAddingCost(Number(p.costPrice));
    }
  };

  const addToCart = () => {
    if (!addingProductId) return;
    const p = products.find(x => x.id === addingProductId);
    if (!p) return;

    // Check if already in cart
    const existing = purchaseCart.find(item => item.product.id === addingProductId);
    if (existing) {
      setPurchaseCart(purchaseCart.map(item => 
        item.product.id === addingProductId 
          ? { ...item, quantity: item.quantity + addingQty } 
          : item
      ));
    } else {
      setPurchaseCart([...purchaseCart, {
        product: p,
        quantity: addingQty,
        unitCost: addingCost,
      }]);
    }

    setAddingProductId('');
    setAddingQty(1);
    setAddingCost(0);
  };

  const removeFromCart = (pid: string) => {
    setPurchaseCart(purchaseCart.filter(item => item.product.id !== pid));
  };

  const getSubtotal = () => {
    return purchaseCart.reduce((sum, item) => sum + (item.quantity * item.unitCost), 0);
  };

  const getTotal = () => {
    const sub = getSubtotal();
    if (discountType === 'PERCENT') {
      return Math.max(0, sub * (1 - discountValue / 100));
    }
    return Math.max(0, sub - discountValue);
  };

  const openAddModal = () => {
    setSelectedSupplierId('new');
    setSupplierName('');
    setSupplierPhone('');
    setDiscountType('AMOUNT');
    setDiscountValue(0);
    setPaidAmount(0);
    setNote('');
    setPurchaseCart([]);
    setErrorMsg('');
    setModalOpen(true);
  };

  const handleCheckoutSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMsg('');

    if (purchaseCart.length === 0) {
      setErrorMsg('Vui lòng thêm sản phẩm vào đơn nhập hàng');
      return;
    }

    if (!supplierName.trim()) {
      setErrorMsg('Vui lòng nhập tên nhà cung cấp');
      return;
    }

    setSubmitting(true);
    const orderData = {
      supplierName,
      supplierPhone: supplierPhone || null,
      discountType,
      discountValue: Number(discountValue),
      paidAmount: Number(paidAmount),
      note: note || null,
      items: purchaseCart.map(item => ({
        productId: item.product.id,
        productName: item.product.name,
        quantity: Number(item.quantity),
        unitCost: Number(item.unitCost),
      })),
    };

    try {
      const res = await api.createPurchase(orderData);
      setOrders([res, ...orders]);
      setModalOpen(false);
      fetchOrdersAndHistory();
    } catch (err: any) {
      setErrorMsg(err.message || 'Lỗi tạo đơn nhập hàng');
    } finally {
      setSubmitting(false);
    }
  };

  const handleDeleteOrder = async (id: string) => {
    if (!confirm('Bạn có chắc chắn muốn xóa đơn nhập hàng này? Hành động này sẽ hoàn trả (trừ) số lượng tồn kho sản phẩm tương ứng và xóa các khoản công nợ phát sinh liên quan!')) return;
    try {
      await api.deletePurchase(id);
      setOrders(orders.filter(o => o.id !== id));
      fetchOrdersAndHistory();
    } catch (err) {
      alert('Không thể xóa đơn nhập hàng');
    }
  };

  const formatCurrency = (val: number) => {
    return new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(val);
  };

  return (
    <div className="space-y-8 animate-fade-in-up">
      {/* Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h2 className="text-2xl font-bold text-white font-sans">Nhập hàng & Kho vận</h2>
          <p className="text-sm text-slate-400">Theo dõi nhập kho sản phẩm và công nợ với nhà cung cấp</p>
        </div>
        <button
          onClick={openAddModal}
          className="btn btn-primary shadow-glow flex items-center gap-2"
        >
          📥 Tạo đơn nhập hàng
        </button>
      </div>

      {/* Tabs */}
      <div className="flex border-b border-slate-800">
        <button
          onClick={() => setActiveTab('orders')}
          className={`px-6 py-3 text-sm font-bold border-b-2 transition-colors cursor-pointer ${
            activeTab === 'orders'
              ? 'border-indigo-500 text-indigo-400'
              : 'border-transparent text-slate-500 hover:text-slate-300'
          }`}
        >
          📜 Đơn nhập hàng
        </button>
        <button
          onClick={() => setActiveTab('history')}
          className={`px-6 py-3 text-sm font-bold border-b-2 transition-colors cursor-pointer ${
            activeTab === 'history'
              ? 'border-indigo-500 text-indigo-400'
              : 'border-transparent text-slate-500 hover:text-slate-300'
          }`}
        >
          📦 Lịch sử mặt hàng
        </button>
      </div>

      {/* Filter and Search */}
      <div className="grid grid-cols-1 md:grid-cols-12 gap-4">
        <div className="md:col-span-6 relative">
          <input
            type="text"
            className="input pl-10"
            placeholder={activeTab === 'orders' ? 'Tìm theo tên nhà cung cấp, ghi chú...' : 'Tìm theo tên sản phẩm, nhà cung cấp...'}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          <span className="absolute left-3.5 top-3.5 text-slate-500">🔍</span>
        </div>
        <div className="md:col-span-3">
          <input
            type="date"
            className="input"
            value={startDate}
            onChange={(e) => setStartDate(e.target.value)}
          />
        </div>
        <div className="md:col-span-3">
          <input
            type="date"
            className="input"
            value={endDate}
            onChange={(e) => setEndDate(e.target.value)}
          />
        </div>
      </div>

      {/* Content */}
      <div className="card bg-slate-900 border-white/5 overflow-hidden p-0">
        <div className="overflow-x-auto">
          {activeTab === 'orders' ? (
            <table className="w-full text-left text-sm border-collapse">
              <thead>
                <tr className="border-b border-slate-800 text-slate-500 font-bold text-xs uppercase tracking-wider bg-slate-950/20">
                  <th className="py-4 px-6">Mã đơn</th>
                  <th className="py-4 px-6">Ngày nhập</th>
                  <th className="py-4 px-6">Nhà cung cấp</th>
                  <th className="py-4 px-6 text-right">Tổng giá trị</th>
                  <th className="py-4 px-6 text-right">Đã trả</th>
                  <th className="py-4 px-6 text-right">Còn nợ</th>
                  <th className="py-4 px-6">Ghi chú</th>
                  <th className="py-4 px-6 text-right">Thao tác</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800 text-slate-300">
                {loading ? (
                  <tr>
                    <td colSpan={8} className="py-8 text-center text-slate-500">
                      Đang tải danh sách đơn nhập...
                    </td>
                  </tr>
                ) : orders.length === 0 ? (
                  <tr>
                    <td colSpan={8} className="py-8 text-center text-slate-500">
                      Không có đơn nhập hàng nào
                    </td>
                  </tr>
                ) : (
                  orders.map((o) => {
                    const subtotal = o.items ? o.items.reduce((s, i) => s + Number(i.totalCost), 0) : 0;
                    const total = o.discountType === 'PERCENT' 
                      ? subtotal * (1 - Number(o.discountValue) / 100) 
                      : Math.max(0, subtotal - Number(o.discountValue));
                    const debt = Math.max(0, total - Number(o.paidAmount));

                    return (
                      <tr key={o.id} className="hover:bg-white/5 transition-colors">
                        <td className="py-4 px-6 font-mono text-xs text-indigo-400">
                          {o.id.startsWith('po-') ? o.id.toUpperCase() : o.id.slice(-6).toUpperCase()}
                        </td>
                        <td className="py-4 px-6 text-xs text-slate-400">
                          {new Date(o.createdAt).toLocaleDateString('vi-VN')} {new Date(o.createdAt).toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' })}
                        </td>
                        <td className="py-4 px-6">
                          <div>
                            <p className="font-semibold text-white">{o.supplierName || 'N/A'}</p>
                            {o.supplierPhone && <p className="text-[10px] text-slate-500">{o.supplierPhone}</p>}
                          </div>
                        </td>
                        <td className="py-4 px-6 text-right font-medium text-white">{formatCurrency(total)}</td>
                        <td className="py-4 px-6 text-right text-emerald-400 font-semibold">{formatCurrency(o.paidAmount)}</td>
                        <td className="py-4 px-6 text-right">
                          <span className={`font-semibold ${debt > 0 ? 'text-rose-400' : 'text-slate-400'}`}>
                            {debt > 0 ? formatCurrency(debt) : 'Thanh toán hết'}
                          </span>
                        </td>
                        <td className="py-4 px-6 text-slate-400 max-w-xs truncate text-xs">{o.note || '—'}</td>
                        <td className="py-4 px-6 text-right">
                          <button
                            onClick={() => handleDeleteOrder(o.id)}
                            className="text-rose-400 hover:text-rose-300 text-xs font-semibold"
                          >
                            Xóa đơn
                          </button>
                        </td>
                      </tr>
                    );
                  })
                )}
              </tbody>
            </table>
          ) : (
            <table className="w-full text-left text-sm border-collapse">
              <thead>
                <tr className="border-b border-slate-800 text-slate-500 font-bold text-xs uppercase tracking-wider bg-slate-950/20">
                  <th className="py-4 px-6">Ngày nhập</th>
                  <th className="py-4 px-6">Tên mặt hàng</th>
                  <th className="py-4 px-6">Nhà cung cấp</th>
                  <th className="py-4 px-6 text-center">Số lượng</th>
                  <th className="py-4 px-6 text-right">Đơn giá nhập</th>
                  <th className="py-4 px-6 text-right">Thành tiền</th>
                  <th className="py-4 px-6">Ghi chú</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800 text-slate-300">
                {loading ? (
                  <tr>
                    <td colSpan={7} className="py-8 text-center text-slate-500">
                      Đang tải lịch sử nhập...
                    </td>
                  </tr>
                ) : historyItems.length === 0 ? (
                  <tr>
                    <td colSpan={7} className="py-8 text-center text-slate-500">
                      Không có lịch sử nhập mặt hàng nào
                    </td>
                  </tr>
                ) : (
                  historyItems.map((h) => (
                    <tr key={h.id} className="hover:bg-white/5 transition-colors">
                      <td className="py-4 px-6 text-xs text-slate-400">
                        {new Date(h.createdAt).toLocaleDateString('vi-VN')}
                      </td>
                      <td className="py-4 px-6 font-semibold text-white">{h.productName}</td>
                      <td className="py-4 px-6 text-slate-300">{h.supplierName || '—'}</td>
                      <td className="py-4 px-6 text-center font-semibold text-white">{h.quantity}</td>
                      <td className="py-4 px-6 text-right text-slate-400">{formatCurrency(h.unitCost)}</td>
                      <td className="py-4 px-6 text-right font-medium text-emerald-400">{formatCurrency(h.totalCost)}</td>
                      <td className="py-4 px-6 text-slate-500 text-xs">{h.note || '—'}</td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {/* New Purchase Order Drawer Modal */}
      {modalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in">
          <div className="glass w-full max-w-2xl rounded-2xl border border-white/10 shadow-2xl p-6 relative animate-fade-in-up flex flex-col max-h-[90vh]">
            <div className="flex justify-between items-center mb-4 border-b border-slate-800 pb-3">
              <h3 className="text-xl font-bold text-white">📦 Nhập hàng vào kho</h3>
              <button onClick={() => setModalOpen(false)} className="text-slate-400 hover:text-white text-lg">✕</button>
            </div>

            {errorMsg && (
              <div className="mb-4 p-3 rounded bg-rose-500/10 border border-rose-500/20 text-rose-400 text-xs">
                ⚠️ {errorMsg}
              </div>
            )}

            <div className="flex-1 overflow-y-auto space-y-4 pr-1">
              {/* Supplier info */}
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                <div>
                  <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Chọn nhà cung cấp</label>
                  <select
                    className="input text-xs"
                    value={selectedSupplierId}
                    onChange={(e) => handleSupplierChange(e.target.value)}
                  >
                    <option value="new">+ Thêm nhà cung cấp mới</option>
                    {suppliers.map(s => (
                      <option key={s.id} value={s.id}>{s.name}</option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Tên nhà cung cấp</label>
                  <input
                    type="text"
                    className="input text-xs"
                    placeholder="Tên nhà cung cấp..."
                    value={supplierName}
                    onChange={(e) => setSupplierName(e.target.value)}
                    disabled={selectedSupplierId !== 'new'}
                  />
                </div>
                <div>
                  <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Số điện thoại</label>
                  <input
                    type="text"
                    className="input text-xs"
                    placeholder="SĐT (nếu có)..."
                    value={supplierPhone}
                    onChange={(e) => setSupplierPhone(e.target.value)}
                    disabled={selectedSupplierId !== 'new'}
                  />
                </div>
              </div>

              {/* Add item to PO */}
              <div className="border border-white/5 bg-slate-950/20 p-4 rounded-xl space-y-3">
                <h4 className="text-xs font-bold text-indigo-400 uppercase tracking-widest">Thêm sản phẩm nhập</h4>
                <div className="grid grid-cols-1 sm:grid-cols-12 gap-3 items-end">
                  <div className="sm:col-span-5">
                    <label className="block text-[10px] font-bold text-slate-500 uppercase tracking-wider mb-1.5">Sản phẩm</label>
                    <select
                      className="input text-xs"
                      value={addingProductId}
                      onChange={(e) => handleProductSelectForAdd(e.target.value)}
                    >
                      <option value="">-- Chọn sản phẩm --</option>
                      {products.map(p => (
                        <option key={p.id} value={p.id}>{p.name} (Tồn: {p.currentStock} {p.unit})</option>
                      ))}
                    </select>
                  </div>
                  <div className="sm:col-span-3 col-span-6">
                    <label className="block text-[10px] font-bold text-slate-500 uppercase tracking-wider mb-1.5">Đơn giá nhập</label>
                    <input
                      type="number"
                      className="input text-xs"
                      value={addingCost}
                      onChange={(e) => setAddingCost(Number(e.target.value))}
                    />
                  </div>
                  <div className="sm:col-span-2 col-span-6">
                    <label className="block text-[10px] font-bold text-slate-500 uppercase tracking-wider mb-1.5">Số lượng</label>
                    <input
                      type="number"
                      className="input text-xs"
                      value={addingQty}
                      onChange={(e) => setAddingQty(Number(e.target.value))}
                    />
                  </div>
                  <div className="sm:col-span-2">
                    <button
                      type="button"
                      onClick={addToCart}
                      disabled={!addingProductId || addingQty <= 0}
                      className="btn btn-primary w-full text-xs font-bold cursor-pointer"
                    >
                      Thêm
                    </button>
                  </div>
                </div>
              </div>

              {/* Items Table */}
              <div className="border border-white/5 rounded-xl overflow-hidden bg-slate-950/20">
                <table className="w-full text-left text-xs border-collapse">
                  <thead>
                    <tr className="border-b border-slate-800 text-slate-500 font-bold uppercase tracking-wider bg-slate-900/50">
                      <th className="py-2.5 px-4">Tên sản phẩm</th>
                      <th className="py-2.5 px-4 text-center">Số lượng</th>
                      <th className="py-2.5 px-4 text-right">Đơn giá nhập</th>
                      <th className="py-2.5 px-4 text-right">Thành tiền</th>
                      <th className="py-2.5 px-4 text-center">Thao tác</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-800 text-slate-300">
                    {purchaseCart.length === 0 ? (
                      <tr>
                        <td colSpan={5} className="py-6 text-center text-slate-500 italic">
                          Chưa có sản phẩm nào được chọn
                        </td>
                      </tr>
                    ) : (
                      purchaseCart.map((item) => (
                        <tr key={item.product.id} className="hover:bg-white/5 transition-colors">
                          <td className="py-2.5 px-4 font-semibold text-white">{item.product.name}</td>
                          <td className="py-2.5 px-4 text-center">{item.quantity} {item.product.unit}</td>
                          <td className="py-2.5 px-4 text-right">{formatCurrency(item.unitCost)}</td>
                          <td className="py-2.5 px-4 text-right font-semibold text-emerald-400">
                            {formatCurrency(item.quantity * item.unitCost)}
                          </td>
                          <td className="py-2.5 px-4 text-center">
                            <button
                              type="button"
                              onClick={() => removeFromCart(item.product.id)}
                              className="text-rose-400 hover:text-rose-300 font-bold"
                            >
                              Xóa
                            </button>
                          </td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>

              {/* Total calculations & paid status */}
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 border-t border-slate-800 pt-4">
                <div className="space-y-3">
                  <div>
                    <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Chiết khấu / Giảm giá</label>
                    <div className="flex gap-2">
                      <select
                        className="input text-xs w-1/3"
                        value={discountType}
                        onChange={(e) => setDiscountType(e.target.value as any)}
                      >
                        <option value="AMOUNT">VNĐ</option>
                        <option value="PERCENT">%</option>
                      </select>
                      <input
                        type="number"
                        className="input text-xs w-2/3"
                        value={discountValue}
                        onChange={(e) => setDiscountValue(Number(e.target.value))}
                      />
                    </div>
                  </div>

                  <div>
                    <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Thực tế đã thanh toán (VNĐ)</label>
                    <input
                      type="number"
                      className="input text-xs"
                      value={paidAmount}
                      onChange={(e) => setPaidAmount(Number(e.target.value))}
                    />
                  </div>
                </div>

                <div className="bg-slate-950/20 border border-white/5 rounded-xl p-4 flex flex-col justify-between text-xs space-y-2">
                  <div className="flex justify-between text-slate-400">
                    <span>Tổng tiền hàng:</span>
                    <span className="text-white font-bold">{formatCurrency(getSubtotal())}</span>
                  </div>
                  <div className="flex justify-between text-slate-400">
                    <span>Chiết khấu:</span>
                    <span className="text-rose-400 font-bold">
                      {discountType === 'PERCENT' ? `${discountValue}%` : `-${formatCurrency(discountValue)}`}
                    </span>
                  </div>
                  <div className="flex justify-between text-slate-400 font-bold border-t border-slate-800 pt-2 text-sm">
                    <span>Tổng cần thanh toán:</span>
                    <span className="text-indigo-400">{formatCurrency(getTotal())}</span>
                  </div>
                  <div className="flex justify-between text-slate-400">
                    <span>Đã trả:</span>
                    <span className="text-emerald-400 font-bold">{formatCurrency(paidAmount)}</span>
                  </div>
                  <div className="flex justify-between text-slate-400 font-bold border-t border-slate-800 pt-2">
                    <span>Còn nợ nhà cung cấp:</span>
                    <span className={getTotal() - paidAmount > 0 ? 'text-rose-400 font-bold' : 'text-slate-400'}>
                      {formatCurrency(Math.max(0, getTotal() - paidAmount))}
                    </span>
                  </div>

                  {getTotal() - paidAmount > 0 && (
                    <div className="p-2 rounded bg-amber-500/10 border border-amber-500/20 text-[10px] text-amber-400 mt-2 leading-relaxed">
                      * Chú ý: Khoản nợ {formatCurrency(getTotal() - paidAmount)} sẽ tự động ghi vào sổ nợ đối tác của nhà cung cấp này.
                    </div>
                  )}
                </div>
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Ghi chú đơn nhập</label>
                <textarea
                  className="input min-h-[50px] text-xs"
                  placeholder="Ghi chú thêm thông tin (lô hàng, hạn sử dụng, v.v.)..."
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                />
              </div>
            </div>

            <div className="flex justify-end gap-3 pt-3 border-t border-slate-800 mt-4">
              <button
                type="button"
                onClick={() => setModalOpen(false)}
                className="btn btn-secondary text-xs"
                disabled={submitting}
              >
                Hủy
              </button>
              <button
                onClick={handleCheckoutSubmit}
                className="btn btn-primary text-xs shadow-glow"
                disabled={submitting || purchaseCart.length === 0}
              >
                {submitting ? 'Đang tạo đơn nhập...' : 'Xác nhận nhập hàng'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
