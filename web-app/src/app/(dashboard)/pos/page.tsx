'use client';

import React, { useState, useEffect, useMemo } from 'react';
import api from '@/lib/api';
import { matchVietnamese } from '@/lib/text';
import VoiceOrderModal from '@/components/pos/VoiceOrderModal';
import Modal from '@/components/ui/Modal';
import VietQrDisplay from '@/components/ui/VietQrDisplay';
import { buildVietQrAddInfoFromItems } from '@/lib/vietqr';
import { shareReceiptImage } from '@/lib/receiptShare';

interface Product {
  id: string;
  name: string;
  price: number;
  costPrice: number;
  currentStock: number;
  unit: string;
  itemType: 'RAW' | 'MIX';
}

interface Customer {
  id: string;
  name: string;
  phone?: string;
  isSupplier: boolean;
}

interface Employee {
  id: string;
  name: string;
}

interface MixItem {
  rawProductId: string;
  rawName: string;
  rawUnit: string;
  rawQty: number;
  rawUnitCost: number;
}

interface CartItem {
  product: Product;
  quantity: number;
  displayName?: string;
  mixItems?: MixItem[];
  unitCost?: number;
}

export default function PosPage() {
  const [products, setProducts] = useState<Product[]>([]);
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [bankAccount, setBankAccount] = useState<any>(null);
  const [loading, setLoading] = useState(true);

  const [cart, setCart] = useState<CartItem[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedCustomerId, setSelectedCustomerId] = useState<string>('walk-in');
  const [selectedEmployeeId, setSelectedEmployeeId] = useState<string>('');
  const [discount, setDiscount] = useState<number>(0);
  const [paymentType, setPaymentType] = useState<'CASH' | 'BANK'>('CASH');
  const [note, setNote] = useState('');

  // Search Select Customer state
  const [customerSearch, setCustomerSearch] = useState('');
  const [customerDropdownOpen, setCustomerDropdownOpen] = useState(false);

  // Quick Add Customer Modal State
  const [quickAddCustomerOpen, setQuickAddCustomerOpen] = useState(false);
  const [newCustName, setNewCustName] = useState('');
  const [newCustPhone, setNewCustPhone] = useState('');
  const [quickAddSubmitting, setQuickAddSubmitting] = useState(false);

  // Checkout Modal State
  const [checkoutModalOpen, setCheckoutModalOpen] = useState(false);
  const [paidAmount, setPaidAmount] = useState<number>(0);
  const [debtMode, setDebtMode] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  // Success Receipt Modal
  const [receiptModalOpen, setReceiptModalOpen] = useState(false);
  const [completedOrder, setCompletedOrder] = useState<any>(null);

  // Voice Order Modal State
  const [voiceModalOpen, setVoiceModalOpen] = useState(false);

  // Mobile Modals State
  const [mobileCustomerModalOpen, setMobileCustomerModalOpen] = useState(false);
  const [mobileEmployeeModalOpen, setMobileEmployeeModalOpen] = useState(false);
  const [mobileProductModalOpen, setMobileProductModalOpen] = useState(false);
  const [mobileProductSearch, setMobileProductSearch] = useState('');

  // Warnings State
  const [stockWarningOpen, setStockWarningOpen] = useState(false);
  const [outOfStockItems, setOutOfStockItems] = useState<any[]>([]);
  const [mixWarningOpen, setMixWarningOpen] = useState(false);
  const [mixPriceWarnings, setMixPriceWarnings] = useState<any[]>([]);

  // Raw Product Picker for MIX State
  const [mixProductSelectOpen, setMixProductSelectOpen] = useState<string | null>(null);

  const handleApplyVoiceOrder = (result: {
    customer?: Customer;
    paidAmount?: number;
    items: Array<{ product: Product; quantity: number; overridePrice?: number }>;
  }) => {
    if (result.customer) {
      setSelectedCustomerId(result.customer.id);
    }

    // Add items to cart
    const newCart = [...cart];
    for (const item of result.items) {
      const prod = {
        ...item.product,
        price: item.overridePrice || item.product.price
      };
      const existingIdx = newCart.findIndex(c => c.product.id === prod.id);
      if (existingIdx > -1) {
        newCart[existingIdx].quantity += item.quantity;
      } else {
        newCart.push({ product: prod, quantity: item.quantity });
      }
    }
    setCart(newCart);

    // Calculate new total to set debtMode
    const newSubtotal = newCart.reduce((sum, item) => sum + (Number(item.product.price) * item.quantity), 0);
    const newTotal = Math.max(0, newSubtotal - discount);
    if (result.paidAmount !== undefined) {
      setPaidAmount(result.paidAmount);
      setDebtMode(result.paidAmount < newTotal);
    } else {
      setDebtMode(false);
    }
  };

  const handlePickContact = async () => {
    if (typeof window !== 'undefined' && 'contacts' in navigator && 'ContactsManager' in window) {
      try {
        const props = ['name', 'tel'];
        const opts = { multiple: false };
        const contacts = await (navigator as any).contacts.select(props, opts);
        if (contacts && contacts.length > 0) {
          const contact = contacts[0];
          const nameVal = contact.name && contact.name[0] ? contact.name[0] : '';
          const phoneVal = contact.tel && contact.tel[0] ? contact.tel[0] : '';

          // clean phone number
          const cleanPhone = phoneVal.replace(/[\s\-\(\)]/g, '').replace(/^\+84/, '0');

          setNewCustName(nameVal);
          setNewCustPhone(cleanPhone);
        }
      } catch (err) {
        console.error('Contact picker error:', err);
      }
    } else {
      alert('Tính năng chọn từ danh bạ chỉ khả dụng trên thiết bị di động (Chrome/Android) qua kết nối HTTPS bảo mật.');
    }
  };

  const handleQuickAddCustomerSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newCustName.trim()) return;

    try {
      setQuickAddSubmitting(true);
      const res = await api.createCustomer({
        name: newCustName.trim(),
        phone: newCustPhone.trim() || undefined,
        isSupplier: false,
      });
      setCustomers([res, ...customers]);
      setSelectedCustomerId(res.id);
      setQuickAddCustomerOpen(false);
      setNewCustName('');
      setNewCustPhone('');
    } catch (err: any) {
      alert(err.message || 'Lỗi khi thêm khách hàng mới');
    } finally {
      setQuickAddSubmitting(false);
    }
  };

  const loadData = async () => {
    try {
      setLoading(true);
      const [prodData, custData, empData, bankData] = await Promise.all([
        api.getProducts().catch(() => null),
        api.getCustomers().catch(() => null),
        api.getEmployees().catch(() => null),
        api.getBankAccounts().catch(() => null),
      ]);

      if (prodData) {
        setProducts(prodData);
      }
      if (custData) {
        setCustomers(custData.filter((c: any) => !c.isSupplier));
      }
      if (empData) {
        setEmployees(empData);
        if (empData.length > 0) {
          setSelectedEmployeeId(empData[0].id);
        }
      }
      if (bankData) {
        const defaultAcc = bankData.find((acc: any) => acc.isDefault);
        setBankAccount(defaultAcc || bankData[0] || null);
      }
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadData();
  }, []);

  const getSubtotal = () => {
    return cart.reduce((sum, item) => sum + (item.product.price * item.quantity), 0);
  };

  const getTotal = () => {
    const sub = getSubtotal();
    return Math.max(0, sub - discount);
  };

  const orderTotal = getTotal();
  const effectivePaidAmount = debtMode ? paidAmount : orderTotal;

  const selectedCustomer = customers.find(c => c.id === selectedCustomerId);
  const displayCustomerName = selectedCustomerId === 'walk-in' ? 'Khách vãng lai' : (selectedCustomer ? `${selectedCustomer.name}${selectedCustomer.phone ? ` (${selectedCustomer.phone})` : ''}` : '');

  const filteredCustomersList = useMemo(() => {
    return customers.filter(c =>
      matchVietnamese(c.name, customerSearch) ||
      matchVietnamese(c.phone || '', customerSearch)
    );
  }, [customers, customerSearch]);

  // Debounced QR code state to prevent flickering when modifying cart
  const [debouncedQrAmount, setDebouncedQrAmount] = useState<number>(0);
  const [debouncedQrDescription, setDebouncedQrDescription] = useState<string>('');

  useEffect(() => {
    const handler = setTimeout(() => {
      setDebouncedQrAmount(effectivePaidAmount);
      setDebouncedQrDescription(buildVietQrAddInfoFromItems('pos-preview', cart.map(c => ({
        name: c.displayName || c.product.name,
        quantity: c.quantity,
        unitPrice: c.product.price,
      }))));
    }, 400);

    return () => {
      clearTimeout(handler);
    };
  }, [cart, paymentType, debtMode, paidAmount, discount]);

  const addToCart = (product: Product) => {
    const existing = cart.find(item => item.product.id === product.id);
    if (existing) {
      if (product.itemType === 'MIX') return;
      setCart(cart.map(item => item.product.id === product.id ? { ...item, quantity: item.quantity + 1 } : item));
    } else {
      if (product.itemType === 'MIX') {
        setCart([...cart, { product, quantity: 0, mixItems: [], displayName: product.name, unitCost: 0 }]);
      } else {
        setCart([...cart, { product, quantity: 1 }]);
      }
    }
  };

  const updateQuantity = (productId: string, quantity: number) => {
    if (quantity <= 0) {
      setCart(cart.filter(item => item.product.id !== productId));
    } else {
      setCart(cart.map(item => item.product.id === productId ? { ...item, quantity } : item));
    }
  };

  const addRawToMix = (mixProductId: string, raw: Product) => {
    setCart(cart.map(item => {
      if (item.product.id !== mixProductId) return item;
      const mixItems = item.mixItems ? [...item.mixItems] : [];
      const existing = mixItems.find(m => m.rawProductId === raw.id);
      if (!existing) {
        mixItems.push({
          rawProductId: raw.id,
          rawName: raw.name,
          rawUnit: raw.unit,
          rawQty: 0,
          rawUnitCost: raw.costPrice,
        });
      }
      const totalQty = mixItems.reduce((sum, m) => sum + m.rawQty, 0);
      const totalCost = mixItems.reduce((sum, m) => sum + (m.rawQty * m.rawUnitCost), 0);
      return {
        ...item,
        mixItems,
        quantity: totalQty,
        unitCost: totalQty <= 0 ? 0 : totalCost / totalQty
      };
    }));
    setMixProductSelectOpen(null);
  };

  const updateRawQtyInMix = (mixProductId: string, rawProductId: string, qty: number) => {
    setCart(cart.map(item => {
      if (item.product.id !== mixProductId) return item;
      const mixItems = (item.mixItems || []).map(m =>
        m.rawProductId === rawProductId ? { ...m, rawQty: Math.max(0, qty) } : m
      );
      const totalQty = mixItems.reduce((sum, m) => sum + m.rawQty, 0);
      const totalCost = mixItems.reduce((sum, m) => sum + (m.rawQty * m.rawUnitCost), 0);
      return {
        ...item,
        mixItems,
        quantity: totalQty,
        unitCost: totalQty <= 0 ? 0 : totalCost / totalQty
      };
    }));
  };

  const removeRawFromMix = (mixProductId: string, rawProductId: string) => {
    setCart(cart.map(item => {
      if (item.product.id !== mixProductId) return item;
      const mixItems = (item.mixItems || []).filter(m => m.rawProductId !== rawProductId);
      const totalQty = mixItems.reduce((sum, m) => sum + m.rawQty, 0);
      const totalCost = mixItems.reduce((sum, m) => sum + (m.rawQty * m.rawUnitCost), 0);
      return {
        ...item,
        mixItems,
        quantity: totalQty,
        unitCost: totalQty <= 0 ? 0 : totalCost / totalQty
      };
    }));
  };

  const validateBeforeCheckout = () => {
    if (cart.length === 0) return;
    const neededRaw: Record<string, { name: string; unit: string; currentStock: number; required: number }> = {};
    for (const item of cart) {
      if (item.product.itemType === 'MIX') {
        const mixItems = item.mixItems || [];
        for (const m of mixItems) {
          if (m.rawQty <= 0) continue;
          const p = products.find(prod => prod.id === m.rawProductId);
          if (!p) continue;
          if (!neededRaw[p.id]) {
            neededRaw[p.id] = { name: p.name, unit: p.unit, currentStock: p.currentStock, required: 0 };
          }
          neededRaw[p.id].required += m.rawQty;
        }
      } else {
        const p = item.product;
        if (!neededRaw[p.id]) {
          neededRaw[p.id] = { name: p.name, unit: p.unit, currentStock: p.currentStock, required: 0 };
        }
        neededRaw[p.id].required += item.quantity;
      }
    }

    const oosList = Object.entries(neededRaw)
      .map(([id, data]) => ({ id, ...data }))
      .filter(item => item.currentStock < item.required);

    if (oosList.length > 0) {
      setOutOfStockItems(oosList);
      setStockWarningOpen(true);
      return;
    }

    // 2. Check sell price below RAW cost for MIX
    const mixWarnings: any[] = [];
    for (const item of cart) {
      if (item.product.itemType === 'MIX') {
        const mixItems = item.mixItems || [];
        let rawSellTotal = 0;
        for (const m of mixItems) {
          const rawProd = products.find(p => p.id === m.rawProductId);
          if (rawProd) {
            rawSellTotal += m.rawQty * rawProd.price;
          }
        }
        const mixTotal = item.product.price * item.quantity;
        if (rawSellTotal > 0 && mixTotal + 0.000001 < rawSellTotal) {
          mixWarnings.push({
            name: item.displayName || item.product.name,
            price: mixTotal,
            rawSellTotal,
          });
        }
      }
    }

    if (mixWarnings.length > 0) {
      setMixPriceWarnings(mixWarnings);
      setMixWarningOpen(true);
      return;
    }

    // Open Checkout
    openCheckout();
  };

  const openCheckout = () => {
    if (!debtMode) setPaidAmount(getTotal());
    setCheckoutModalOpen(true);
  };

  const handleUpdateStockQuick = async (id: string, newStock: number) => {
    try {
      await api.updateProduct(id, { currentStock: newStock });
      const prodData = await api.getProducts().catch(() => null);
      if (prodData) {
        setProducts(prodData);
        setCart(cart.map(item => {
          const updatedProd = prodData.find((p: any) => p.id === item.product.id);
          return updatedProd ? { ...item, product: updatedProd } : item;
        }));
      }
      setOutOfStockItems(prev => prev.map(item =>
        item.id === id ? { ...item, currentStock: newStock } : item
      ).filter(item => item.currentStock < item.required));
    } catch (err) {
      alert('Không thể cập nhật tồn kho');
    }
  };

  const handleCheckoutSubmit = async () => {
    setSubmitting(true);
    const total = getTotal();
    const subtotal = getSubtotal();
    const customer = selectedCustomerId === 'walk-in' ? null : customers.find(c => c.id === selectedCustomerId);
    const employee = selectedEmployeeId ? employees.find(e => e.id === selectedEmployeeId) : null;

    const saleData = {
      id: 'web-sale-' + Math.random().toString(36).substr(2, 9),
      createdAt: new Date().toISOString(),
      customerId: customer?.id || null,
      customerName: customer?.name || 'Khách vãng lai',
      employeeId: employee?.id || null,
      employeeName: employee?.name || null,
      discount: discount,
      paidAmount: effectivePaidAmount,
      paymentType: paymentType,
      totalCost: cart.reduce((sum, item) => sum + ((item.unitCost || item.product.costPrice) * item.quantity), 0),
      note: note,
      items: cart.map(item => ({
        productId: item.product.id,
        name: item.product.name,
        unitPrice: item.product.price,
        unitCost: item.unitCost || item.product.costPrice,
        quantity: item.quantity,
        unit: item.product.unit,
        itemType: item.product.itemType,
        displayName: item.displayName || null,
        mixItemsJson: item.mixItems ? JSON.stringify(item.mixItems) : null,
        updatedAt: new Date().toISOString(),
      })),
    };

    try {
      await api.createSale(saleData);

      setCompletedOrder({
        ...saleData,
        subtotal,
        total,
      });

      // Clear Cart
      setCart([]);
      setDiscount(0);
      setNote('');
      setDebtMode(false);
      setSelectedCustomerId('walk-in');
      setCheckoutModalOpen(false);
      setReceiptModalOpen(true);
    } catch (err) {
      alert('Lỗi tạo đơn hàng: ' + (err instanceof Error ? err.message : String(err)));
    } finally {
      setSubmitting(false);
    }
  };

  const getVietQrDescription = (saleId: string, items: Array<{ name: string; quantity: number; unitPrice: number }>) => {
    return buildVietQrAddInfoFromItems(saleId, items);
  };

  const getPosQrAmount = () => {
    const total = getTotal();
    return effectivePaidAmount > 0 ? effectivePaidAmount : total;
  };

  const filteredProducts = products.filter(p =>
    matchVietnamese(p.name, searchQuery)
  );

  const filteredMobileProducts = products.filter(p =>
    matchVietnamese(p.name, mobileProductSearch)
  );

  const formatCurrency = (val: number) => {
    return new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(val);
  };

  const rawProductsOnly = products.filter(p => p.itemType === 'RAW');

  return (
    <div className="flex-1 lg:h-[calc(100vh-140px)] min-h-0 flex flex-col lg:flex-row gap-4 lg:gap-6 overflow-hidden">
      {/* Left side: Product catalog (Desktop only) */}
      <div className="hidden lg:flex flex-1 flex-col bg-slate-900 border border-white/5 rounded-2xl p-6 overflow-hidden">
        {/* Search & Voice Order */}
        <div className="relative mb-6 flex gap-2">
          <div className="relative flex-1">
            <input
              type="text"
              className="input pl-10"
              placeholder="Tìm sản phẩm bán..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
            <span className="absolute left-3.5 top-3.5 text-slate-500">🔍</span>
          </div>
          <button
            onClick={() => setVoiceModalOpen(true)}
            className="btn btn-primary px-4 flex items-center justify-center gap-1.5 shadow-glow cursor-pointer text-xs shrink-0"
            title="Lên đơn bằng giọng nói"
          >
            <span>🎤</span> Lên đơn AI
          </button>
        </div>

        {/* Product Grid */}
        <div className="flex-1 overflow-y-auto pr-2 grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-4">
          {loading ? (
            <div className="col-span-full py-12 text-center text-slate-500">
              Đang tải danh mục sản phẩm...
            </div>
          ) : filteredProducts.length === 0 ? (
            <div className="col-span-full py-12 text-center text-slate-500">
              Không tìm thấy sản phẩm nào
            </div>
          ) : (
            filteredProducts.map((p) => (
              <button
                key={p.id}
                onClick={() => addToCart(p)}
                className="card bg-slate-950/40 border-white/5 hover:border-indigo-500/30 text-left p-4 flex flex-col justify-between h-36 transition-all hover:scale-[1.02]"
              >
                <div>
                  <h4 className="font-semibold text-white text-sm line-clamp-2">{p.name}</h4>
                  <span className="text-[10px] text-slate-400 mt-1 block">Tồn: {p.currentStock} {p.unit}</span>
                </div>
                <div className="flex justify-between items-center mt-2">
                  <span className="text-[10px] px-1.5 py-0.5 rounded bg-slate-800 text-slate-400 font-semibold uppercase">
                    {p.itemType === 'RAW' ? 'Hàng thô' : 'Pha chế'}
                  </span>
                  <span className="font-bold text-indigo-300 text-sm">{formatCurrency(p.price)}</span>
                </div>
              </button>
            ))
          )}
        </div>
      </div>

      {/* Right side: Cart / Invoice Checkout */}
      <div className="w-full lg:w-[min(100%,28rem)] lg:shrink-0 flex flex-col bg-slate-900 border border-white/5 rounded-2xl p-4 lg:p-5 min-h-0 overflow-y-auto">
        <div className="flex justify-between items-center mb-4">
          <h3 className="font-bold text-white text-base flex items-center gap-2">
            <span>🛒</span> Giỏ hàng ({cart.reduce((sum, item) => sum + item.quantity, 0)})
          </h3>
          <button
            onClick={() => setVoiceModalOpen(true)}
            className="lg:hidden btn btn-primary py-1 px-3 text-xs flex items-center gap-1 shadow-glow cursor-pointer"
          >
            <span>🎤</span> Đơn AI
          </button>
        </div>

        {/* Mobile quick action bar: select customer, employee, add product */}
        <div className="lg:hidden grid grid-cols-2 gap-2.5 mb-4 shrink-0">
          <button
            type="button"
            onClick={() => setMobileCustomerModalOpen(true)}
            className="flex flex-col items-start p-3 bg-slate-950/40 border border-white/5 hover:border-indigo-500/30 rounded-xl text-left"
          >
            <span className="text-[9px] font-bold text-slate-500 uppercase tracking-wider">Khách hàng</span>
            <span className="text-xs font-bold text-indigo-300 truncate mt-1 w-full">
              👤 {selectedCustomerId === 'walk-in' ? 'Khách vãng lai' : customers.find(c => c.id === selectedCustomerId)?.name}
            </span>
          </button>

          <button
            type="button"
            onClick={() => setMobileEmployeeModalOpen(true)}
            className="flex flex-col items-start p-3 bg-slate-950/40 border border-white/5 hover:border-indigo-500/30 rounded-xl text-left"
          >
            <span className="text-[9px] font-bold text-slate-500 uppercase tracking-wider">Nhân viên</span>
            <span className="text-xs font-bold text-cyan-300 truncate mt-1 w-full">
              💼 {selectedEmployeeId ? employees.find(e => e.id === selectedEmployeeId)?.name : 'Chưa chọn'}
            </span>
          </button>

          <button
            type="button"
            onClick={() => setMobileProductModalOpen(true)}
            className="col-span-2 btn btn-primary py-2.5 font-bold shadow-glow flex items-center justify-center gap-2 mt-1 cursor-pointer text-xs"
          >
            ➕ Thêm sản phẩm
          </button>
        </div>

        {/* Selected Items */}
        <div className="flex-1 overflow-y-auto pr-1 space-y-3 mb-6">
          {cart.length === 0 ? (
            <div className="h-full flex flex-col items-center justify-center text-center py-12">
              <span className="text-4xl mb-3">🧺</span>
              <p className="text-xs text-slate-500">Chưa có sản phẩm nào được chọn</p>
            </div>
          ) : (
            cart.map((item) => (
              <div key={item.product.id} className="flex flex-col bg-slate-950/30 border border-white/5 p-4 rounded-none gap-2.5">
                <div className="flex justify-between items-center w-full">
                  <div className="min-w-0 flex-1">
                    <p className="text-base font-bold text-white truncate">{item.product.name}</p>
                    <p className="text-sm text-slate-400 mt-1">
                      {formatCurrency(item.product.price)} {item.product.itemType === 'RAW' ? `x ${item.quantity}` : ' (MIX)'}
                    </p>
                  </div>

                  {/* Quantity Control for RAW */}
                  {item.product.itemType === 'RAW' ? (
                    <div className="flex items-center gap-2 shrink-0">
                      <button
                        onClick={() => updateQuantity(item.product.id, item.quantity - 1)}
                        className="w-9 h-9 sm:w-8 sm:h-8 rounded-none bg-slate-800 hover:bg-slate-700 text-slate-200 text-base flex items-center justify-center font-bold"
                      >
                        -
                      </button>
                      <span className="text-base font-extrabold text-white w-8 text-center">{item.quantity}</span>
                      <button
                        onClick={() => updateQuantity(item.product.id, item.quantity + 1)}
                        className="w-9 h-9 sm:w-8 sm:h-8 rounded-none bg-slate-800 hover:bg-slate-700 text-slate-200 text-base flex items-center justify-center font-bold"
                      >
                        +
                      </button>
                    </div>
                  ) : (
                    <button
                      onClick={() => updateQuantity(item.product.id, 0)}
                      className="text-rose-400 hover:text-rose-300 text-sm py-1.5 px-3 border border-rose-500/20 bg-rose-500/5 rounded-none font-bold cursor-pointer"
                    >
                      Xóa
                    </button>
                  )}
                </div>

                {/* MIX Configuration */}
                {item.product.itemType === 'MIX' && (
                  <div className="mt-2 pl-2 border-l border-indigo-500/30 space-y-2">
                    <input
                      type="text"
                      className="input py-1 text-xs sm:text-sm h-8 rounded-none"
                      placeholder="Tên hiển thị hóa đơn (tùy chọn)"
                      value={item.displayName || ''}
                      onChange={(e) => {
                        const val = e.target.value;
                        setCart(cart.map(c => c.product.id === item.product.id ? { ...c, displayName: val } : c));
                      }}
                    />

                    {/* Raw materials list */}
                    <div className="space-y-1.5">
                      {(item.mixItems || []).map((m, idx) => (
                        <div key={idx} className="flex justify-between items-center gap-2 text-xs text-slate-400">
                          <span className="truncate flex-1">{m.rawName}</span>
                          <div className="flex items-center gap-1">
                            <input
                              type="number"
                              className="input py-0.5 px-1 h-7 w-14 text-center text-xs bg-slate-900 border-white/5 rounded-none"
                              value={m.rawQty || ''}
                              onChange={(e) => updateRawQtyInMix(item.product.id, m.rawProductId, Number(e.target.value))}
                            />
                            <span>{m.rawUnit}</span>
                            <button
                              onClick={() => removeRawFromMix(item.product.id, m.rawProductId)}
                              className="text-rose-400 hover:text-white px-1 text-sm cursor-pointer"
                            >
                              ✕
                            </button>
                          </div>
                        </div>
                      ))}
                    </div>

                    <button
                      onClick={() => setMixProductSelectOpen(item.product.id)}
                      className="btn btn-secondary py-1.5 text-xs rounded-none w-full flex items-center justify-center gap-1 cursor-pointer"
                    >
                      ➕ Thêm nguyên liệu RAW
                    </button>
                  </div>
                )}
              </div>
            ))
          )}
        </div>

        {/* Customer & Discount Form */}
        <div className="border-t border-slate-800 pt-4 space-y-3.5 text-sm">
          {/* Employee */}
          <div className="hidden lg:block">
            <label className="block text-[11px] font-bold text-slate-400 uppercase tracking-wider mb-1.5">Nhân viên bán hàng</label>
            <select
              className="input text-xs"
              value={selectedEmployeeId}
              onChange={(e) => setSelectedEmployeeId(e.target.value)}
            >
              <option value="">Chọn nhân viên...</option>
              {employees.map(emp => (
                <option key={emp.id} value={emp.id}>{emp.name} ({emp.id})</option>
              ))}
            </select>
          </div>

          {/* Customer */}
          <div className="hidden lg:block">
            <div className="flex justify-between items-center mb-1.5">
              <label className="block text-[11px] font-bold text-slate-400 uppercase tracking-wider">Khách hàng</label>
              <button
                type="button"
                onClick={() => setQuickAddCustomerOpen(true)}
                className="text-[10px] text-indigo-400 hover:text-indigo-300 font-bold uppercase tracking-wider flex items-center gap-1 transition-colors"
              >
                ➕ Thêm nhanh
              </button>
            </div>
            <div className="relative">
              <input
                type="text"
                className="input text-xs pr-8 cursor-pointer bg-slate-950/40 border-white/5 focus:border-indigo-500/50"
                placeholder="Tìm khách hàng theo tên, SĐT..."
                value={customerDropdownOpen ? customerSearch : displayCustomerName}
                onFocus={() => {
                  setCustomerSearch('');
                  setCustomerDropdownOpen(true);
                }}
                onChange={(e) => setCustomerSearch(e.target.value)}
                onBlur={() => {
                  // Delay closing to allow onMouseDown on options to fire
                  setTimeout(() => setCustomerDropdownOpen(false), 200);
                }}
              />
              <span className="absolute right-3 top-3 text-slate-500 text-[10px] pointer-events-none">
                {customerDropdownOpen ? '▲' : '▼'}
              </span>

              {customerDropdownOpen && (
                <div className="absolute z-50 w-full mt-1 bg-[var(--color-bg-secondary)] border border-[var(--color-border)] rounded-xl shadow-xl max-h-56 overflow-y-auto p-1.5 space-y-0.5 backdrop-blur-md">
                  <div
                    className="px-3.5 py-2.5 text-sm hover:bg-indigo-500/10 cursor-pointer text-[var(--color-text-secondary)] transition-colors"
                    onMouseDown={() => {
                      setSelectedCustomerId('walk-in');
                      setCustomerDropdownOpen(false);
                    }}
                  >
                    Khách vãng lai
                  </div>
                  {filteredCustomersList.length === 0 ? (
                    <div className="px-3.5 py-2.5 text-sm text-slate-500">Không tìm thấy khách hàng nào</div>
                  ) : (
                    filteredCustomersList.map(c => (
                      <div
                        key={c.id}
                        className="px-3.5 py-2.5 text-sm hover:bg-indigo-500/10 cursor-pointer text-[var(--color-text)] transition-colors"
                        onMouseDown={() => {
                          setSelectedCustomerId(c.id);
                          setCustomerDropdownOpen(false);
                        }}
                      >
                        <p className="font-semibold">{c.name}</p>
                        {c.phone && <p className="text-[11px] text-[var(--color-text-secondary)] mt-0.5">{c.phone}</p>}
                      </div>
                    ))
                  )}
                </div>
              )}
            </div>
          </div>

          {/* Discount */}
          <div>
            <label className="block text-[11px] font-bold text-slate-400 uppercase tracking-wider mb-1.5">Giảm giá (VNĐ)</label>
            <input
              type="number"
              className="input text-xs"
              placeholder="0 đ"
              value={discount === 0 ? '' : discount}
              onChange={(e) => setDiscount(Number(e.target.value))}
            />
          </div>

          {/* Payment Type */}
          <div>
            <label className="block text-[11px] font-bold text-slate-400 uppercase tracking-wider mb-1.5">Phương thức thanh toán</label>
            <div className="grid grid-cols-2 gap-2">
              <button
                type="button"
                onClick={() => setPaymentType('CASH')}
                className={`btn py-2 text-xs font-semibold ${paymentType === 'CASH'
                    ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30'
                    : 'bg-slate-950/40 text-slate-500 border border-white/5'
                  }`}
              >
                💵 Tiền mặt
              </button>
              <button
                type="button"
                onClick={() => setPaymentType('BANK')}
                className={`btn py-2 text-xs font-semibold ${paymentType === 'BANK'
                    ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30'
                    : 'bg-slate-950/40 text-slate-500 border border-white/5'
                  }`}
              >
                🏦 Chuyển khoản
              </button>
            </div>
          </div>

          {/* Paid Amount */}
          <div>
            <label className="block text-[11px] font-bold text-slate-400 uppercase tracking-wider mb-1.5">Số tiền khách trả (VNĐ)</label>
            <input
              type="number"
              className="input text-xs"
              value={debtMode ? paidAmount : orderTotal || ''}
              onChange={(e) => {
                const val = Number(e.target.value);
                setPaidAmount(val);
                setDebtMode(val < orderTotal);
              }}
            />
            <div className="flex flex-wrap gap-2 mt-2">
              <button
                type="button"
                onClick={() => { setDebtMode(true); setPaidAmount(0); }}
                className="btn py-1 px-2.5 text-[10px] font-semibold bg-rose-500/10 text-rose-400 border border-rose-500/20 hover:bg-rose-500/20 transition-all rounded-lg"
              >
                Nợ tất
              </button>
              <button
                type="button"
                onClick={() => { setDebtMode(false); setPaidAmount(orderTotal); }}
                className="btn py-1 px-2.5 text-[10px] font-semibold bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 hover:bg-emerald-500/20 transition-all rounded-lg"
              >
                Trả hết
              </button>
              {[50000, 100000, 200000, 500000].map(val => (
                <button
                  key={val}
                  type="button"
                  onClick={() => { setPaidAmount(val); setDebtMode(val < orderTotal); }}
                  className="btn py-1 px-2.5 text-[10px] font-semibold bg-slate-800 text-slate-300 border border-white/5 hover:bg-slate-700 transition-all rounded-lg"
                >
                  {val / 1000}k
                </button>
              ))}
            </div>
            {effectivePaidAmount < orderTotal && (
              <div className="mt-2 p-2.5 rounded-lg bg-amber-500/10 border border-amber-500/20 text-amber-400 text-[10px] leading-relaxed">
                Còn nợ: <strong>{formatCurrency(orderTotal - effectivePaidAmount)}</strong>
                {selectedCustomerId === 'walk-in' && (
                  <span className="block mt-1 text-rose-400 font-bold">* Phải chọn khách hàng cụ thể để ghi nợ!</span>
                )}
              </div>
            )}
          </div>

          {/* VietQR live preview when bank transfer selected */}
          {paymentType === 'BANK' && cart.length > 0 && (debouncedQrAmount > 0 || orderTotal > 0) && (
            <div className="bg-slate-950/30 p-3 rounded-xl border border-white/5">
              <VietQrDisplay
                bank={bankAccount}
                amount={debouncedQrAmount}
                description={debouncedQrDescription}
                size="pos"
              />
            </div>
          )}

          {/* Summary pricing */}
          <div className="bg-slate-950/30 p-3.5 rounded-xl space-y-2 border border-white/5">
            <div className="flex justify-between text-xs text-slate-400">
              <span>Tạm tính</span>
              <span>{formatCurrency(getSubtotal())}</span>
            </div>
            <div className="flex justify-between text-xs text-slate-400">
              <span>Giảm giá</span>
              <span className="text-rose-400">-{formatCurrency(discount)}</span>
            </div>
            <div className="flex justify-between font-bold text-sm text-white border-t border-slate-800 pt-2">
              <span>Tổng cộng</span>
              <span className="text-cyan-400 text-base">{formatCurrency(getTotal())}</span>
            </div>
          </div>

          <button
            onClick={validateBeforeCheckout}
            disabled={cart.length === 0 || (effectivePaidAmount < orderTotal && selectedCustomerId === 'walk-in')}
            className="btn btn-primary w-full btn-lg font-bold shadow-glow disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Thanh toán
          </button>
        </div>
      </div>
      <VoiceOrderModal
        isOpen={voiceModalOpen}
        onClose={() => setVoiceModalOpen(false)}
        products={products}
        customers={customers}
        onApply={handleApplyVoiceOrder}
      />

      <Modal
        open={!!mixProductSelectOpen}
        onClose={() => setMixProductSelectOpen(null)}
        title="Chọn nguyên liệu RAW"
        maxWidth="max-w-sm"
      >
        <div className="max-h-60 overflow-y-auto space-y-2">
          {rawProductsOnly.map(p => (
            <button
              key={p.id}
              onClick={() => mixProductSelectOpen && addRawToMix(mixProductSelectOpen, p)}
              className="w-full text-left p-2.5 rounded-xl border border-white/5 hover:border-indigo-500/30 bg-slate-950/40 text-xs font-semibold text-white flex justify-between items-center"
            >
              <span>{p.name}</span>
              <span className="text-[10px] text-slate-400">Tồn: {p.currentStock} {p.unit}</span>
            </button>
          ))}
          {rawProductsOnly.length === 0 && (
            <p className="text-center text-xs text-slate-500 py-4">Chưa có sản phẩm RAW nào</p>
          )}
        </div>
      </Modal>

      <Modal
        open={stockWarningOpen}
        onClose={() => setStockWarningOpen(false)}
        title={<span className="text-rose-400">⚠️ Tồn kho không đủ</span>}
        maxWidth="max-w-md"
      >
        <div className="space-y-4 text-xs text-slate-300">
          <p>Một số sản phẩm hoặc nguyên liệu có số lượng tồn kho thấp hơn lượng cần xuất đơn hàng:</p>
          <div className="space-y-3 max-h-48 overflow-y-auto">
            {outOfStockItems.map((item, idx) => (
              <div key={idx} className="p-3 bg-slate-950/40 rounded-xl border border-white/5 flex justify-between items-center">
                <div>
                  <p className="font-semibold text-white">{item.name}</p>
                  <p className="text-[10px] text-slate-500 mt-1">
                    Cần: {item.required} {item.unit} | Tồn hiện tại: {item.currentStock} {item.unit}
                  </p>
                </div>
                <div className="flex items-center gap-2">
                  <input
                    type="number"
                    defaultValue={item.required}
                    id={`oos-adjust-${item.id}`}
                    className="input h-7 w-16 text-center text-xs"
                  />
                  <button
                    onClick={() => {
                      const input = document.getElementById(`oos-adjust-${item.id}`) as HTMLInputElement;
                      if (input) handleUpdateStockQuick(item.id, Number(input.value));
                    }}
                    className="btn btn-primary h-7 px-2 text-[10px]"
                  >
                    Cập nhật
                  </button>
                </div>
              </div>
            ))}
          </div>
          <div className="flex justify-end gap-3 pt-4 border-t border-slate-800">
            <button type="button" onClick={() => setStockWarningOpen(false)} className="btn btn-secondary text-xs">Hủy đơn</button>
            <button
              type="button"
              onClick={() => { setStockWarningOpen(false); openCheckout(); }}
              className="btn btn-primary text-xs bg-amber-500 hover:bg-amber-600 shadow-glow"
            >
              Bỏ qua & Tiếp tục
            </button>
          </div>
        </div>
      </Modal>

      <Modal
        open={mixWarningOpen}
        onClose={() => setMixWarningOpen(false)}
        title={<span className="text-amber-500">⚠️ Cảnh báo giá bán MIX</span>}
        maxWidth="max-w-md"
      >
        <div className="space-y-4 text-xs text-slate-300">
          <p>Có sản phẩm MIX có giá bán thấp hơn tổng giá bán lẻ của nguyên liệu cấu thành:</p>
          <div className="space-y-2">
            {mixPriceWarnings.map((w, idx) => (
              <div key={idx} className="p-3 bg-slate-950/40 rounded-xl border border-white/5 flex justify-between text-slate-300">
                <span className="font-semibold text-white">{w.name}</span>
                <span>{formatCurrency(w.price)} &lt; {formatCurrency(w.rawSellTotal)}</span>
              </div>
            ))}
          </div>
          <p>Bạn vẫn muốn lưu hóa đơn?</p>
          <div className="flex justify-end gap-3 pt-4 border-t border-slate-800">
            <button type="button" onClick={() => setMixWarningOpen(false)} className="btn btn-secondary text-xs">Quay lại</button>
            <button
              type="button"
              onClick={() => { setMixWarningOpen(false); openCheckout(); }}
              className="btn btn-primary text-xs shadow-glow"
            >
              Vẫn lưu
            </button>
          </div>
        </div>
      </Modal>

      <Modal
        open={checkoutModalOpen}
        onClose={() => setCheckoutModalOpen(false)}
        title="Xác nhận thanh toán"
        maxWidth="max-w-md"
      >
        <div className="space-y-4">
          <div className="bg-slate-950/40 p-4 rounded-xl space-y-2 text-sm">
            <div className="flex justify-between text-slate-400">
              <span>Khách hàng:</span>
              <span className="text-white font-semibold">
                {selectedCustomerId === 'walk-in' ? 'Khách vãng lai' : customers.find(c => c.id === selectedCustomerId)?.name}
              </span>
            </div>
            <div className="flex justify-between text-slate-400">
              <span>Tổng tiền đơn:</span>
              <span className="text-white font-semibold">{formatCurrency(orderTotal)}</span>
            </div>
            <div className="flex justify-between text-slate-400">
              <span>Khách trả:</span>
              <span className="text-emerald-400 font-semibold">{formatCurrency(effectivePaidAmount)}</span>
            </div>
            {effectivePaidAmount < orderTotal && (
              <div className="flex justify-between text-amber-400 font-bold">
                <span>Còn nợ:</span>
                <span>{formatCurrency(orderTotal - effectivePaidAmount)}</span>
              </div>
            )}
          </div>

          {effectivePaidAmount < orderTotal && selectedCustomerId === 'walk-in' && (
            <div className="p-3.5 rounded-lg bg-rose-500/10 border border-rose-500/20 text-rose-400 text-xs">
              * Có nợ thì bắt buộc phải chọn khách hàng cụ thể! Khách vãng lai không được ghi nợ.
            </div>
          )}

          <div>
            <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Ghi chú đơn hàng</label>
            <textarea
              className="input min-h-[60px]"
              placeholder="Ghi chú thêm thông tin..."
              value={note}
              onChange={(e) => setNote(e.target.value)}
            />
          </div>

          <div className="flex justify-end gap-3 pt-4 border-t border-slate-800">
            <button type="button" onClick={() => setCheckoutModalOpen(false)} className="btn btn-secondary text-xs" disabled={submitting}>Hủy</button>
            <button
              onClick={handleCheckoutSubmit}
              className="btn btn-primary text-xs shadow-glow"
              disabled={submitting || (effectivePaidAmount < orderTotal && selectedCustomerId === 'walk-in')}
            >
              {submitting ? 'Đang tạo đơn...' : 'Xác nhận tạo đơn'}
            </button>
          </div>
        </div>
      </Modal>

      <Modal
        open={receiptModalOpen && !!completedOrder}
        onClose={() => setReceiptModalOpen(false)}
        title="Hóa đơn thanh toán"
        maxWidth={
          completedOrder?.paymentType === 'BANK' && completedOrder.paidAmount > 0 && completedOrder.total - completedOrder.paidAmount <= 0
            ? 'max-w-2xl'
            : 'max-w-sm'
        }
      >
        {completedOrder && (
          <>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6 items-start">
              <div className="bg-white text-black p-5 rounded-lg font-mono text-xs space-y-4 shadow-inner">
                <div className="text-center space-y-1">
                  <h4 className="font-bold text-sm">MARKET VENDOR APPS</h4>
                  <p className="text-[10px] text-zinc-500">Đồng hành cùng tiểu thương Việt</p>
                  <p className="text-[9px] text-zinc-500">ĐT: 0987.654.321</p>
                </div>

                <div className="border-t border-dashed border-zinc-300 my-2"></div>

                <div className="space-y-1">
                  <p>Số HĐ: {completedOrder.id.slice(-6).toUpperCase()}</p>
                  <p>Khách hàng: {completedOrder.customerName}</p>
                  {completedOrder.employeeName && <p>Nhân viên: {completedOrder.employeeName}</p>}
                  <p>Ngày tạo: {new Date(completedOrder.createdAt).toLocaleDateString('vi-VN')} {new Date(completedOrder.createdAt).toLocaleTimeString('vi-VN')}</p>
                </div>

                <div className="border-t border-dashed border-zinc-300 my-2"></div>

                {/* Items list */}
                <div className="space-y-1.5">
                  <div className="flex justify-between font-bold">
                    <span className="w-1/2 font-bold text-black">Tên SP</span>
                    <span className="w-1/6 text-right font-bold text-black">SL</span>
                    <span className="w-1/3 text-right font-bold text-black">T.Tiền</span>
                  </div>
                  {completedOrder.items.map((item: any, idx: number) => (
                    <div key={idx} className="flex justify-between text-zinc-700">
                      <span className="w-1/2 truncate">{item.name}</span>
                      <span className="w-1/6 text-right">{item.quantity}</span>
                      <span className="w-1/3 text-right">{formatCurrency(item.unitPrice * item.quantity)}</span>
                    </div>
                  ))}
                </div>

                <div className="border-t border-dashed border-zinc-300 my-2"></div>

                <div className="space-y-1 text-right text-zinc-700">
                  <div className="flex justify-between">
                    <span>Tạm tính:</span>
                    <span>{formatCurrency(completedOrder.subtotal)}</span>
                  </div>
                  <div className="flex justify-between text-zinc-500">
                    <span>Giảm giá:</span>
                    <span>-{formatCurrency(completedOrder.discount)}</span>
                  </div>
                  <div className="flex justify-between font-bold text-black">
                    <span>Tổng tiền:</span>
                    <span>{formatCurrency(completedOrder.total)}</span>
                  </div>
                  <div className="flex justify-between text-zinc-700 font-medium">
                    <span>Khách trả:</span>
                    <span>{formatCurrency(completedOrder.paidAmount)}</span>
                  </div>
                  {completedOrder.total - completedOrder.paidAmount > 0 && (
                    <div className="flex justify-between font-bold text-rose-600">
                      <span>Còn nợ:</span>
                      <span>{formatCurrency(completedOrder.total - completedOrder.paidAmount)}</span>
                    </div>
                  )}
                </div>

                <div className="border-t border-dashed border-zinc-300 my-2"></div>

                <div className="text-center font-bold text-[10px] text-zinc-500">
                  CẢM ƠN QUÝ KHÁCH & HẸN GẶP LẠI!
                </div>
              </div>

              {completedOrder.paymentType === 'BANK' && completedOrder.paidAmount > 0 && (
                <div className="p-4 bg-slate-950/40 rounded-xl border border-white/5">
                  <VietQrDisplay
                    bank={bankAccount}
                    amount={completedOrder.paidAmount}
                    description={getVietQrDescription(completedOrder.id, completedOrder.items.map((item: any) => ({
                      name: item.name,
                      quantity: item.quantity,
                      unitPrice: item.unitPrice,
                    })))}
                  />
                </div>
              )}
            </div>

            <div className="flex justify-end gap-3 pt-6 border-t border-slate-800 mt-6">
              <button
                onClick={async () => {
                  if (completedOrder) {
                    await shareReceiptImage({
                      id: completedOrder.id,
                      createdAt: completedOrder.createdAt,
                      customerName: completedOrder.customerName,
                      employeeName: completedOrder.employeeName,
                      items: completedOrder.items,
                      discount: completedOrder.discount,
                      subtotal: completedOrder.subtotal,
                      total: completedOrder.total,
                      paidAmount: completedOrder.paidAmount,
                      paymentType: completedOrder.paymentType,
                    });
                  }
                }}
                className="btn btn-secondary text-xs border-indigo-500/20 text-indigo-300 bg-indigo-500/5 hover:bg-indigo-500/10"
              >
                📱 Chia sẻ ảnh HĐ
              </button>
              <button onClick={() => window.print()} className="btn btn-secondary text-xs">🖨️ In hóa đơn</button>
              <button onClick={() => setReceiptModalOpen(false)} className="btn btn-primary text-xs shadow-glow">Hoàn thành</button>
            </div>
          </>
        )}
      </Modal>

      {/* Quick Add Customer Modal */}
      <Modal open={quickAddCustomerOpen} onClose={() => setQuickAddCustomerOpen(false)} title="Thêm khách hàng nhanh" maxWidth="max-w-md">
        <form onSubmit={handleQuickAddCustomerSubmit} className="space-y-4 text-sm">
          <div>
            <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Tên khách hàng *</label>
            <input
              type="text"
              required
              className="input"
              placeholder="Nhập tên khách hàng..."
              value={newCustName}
              onChange={(e) => setNewCustName(e.target.value)}
            />
          </div>
          <div>
            <div className="flex justify-between items-center mb-2">
              <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider">Số điện thoại</label>
              <button
                type="button"
                onClick={handlePickContact}
                className="text-xs text-indigo-400 hover:text-indigo-300 font-semibold flex items-center gap-1.5 transition-colors"
              >
                📱 Chọn từ danh bạ
              </button>
            </div>
            <input
              type="tel"
              className="input"
              placeholder="Nhập số điện thoại..."
              value={newCustPhone}
              onChange={(e) => setNewCustPhone(e.target.value)}
            />
          </div>
          <div className="flex justify-end gap-3 pt-4 border-t border-slate-800">
            <button
              type="button"
              onClick={() => setQuickAddCustomerOpen(false)}
              className="btn btn-secondary text-xs"
              disabled={quickAddSubmitting}
            >
              Hủy
            </button>
            <button
              type="submit"
              className="btn btn-primary text-xs shadow-glow"
              disabled={quickAddSubmitting}
            >
              {quickAddSubmitting ? 'Đang thêm...' : 'Thêm khách hàng'}
            </button>
          </div>
        </form>
      </Modal>

      {/* Mobile Select Customer Modal */}
      <Modal
        open={mobileCustomerModalOpen}
        onClose={() => setMobileCustomerModalOpen(false)}
        title="Chọn khách hàng"
        maxWidth="max-w-md"
      >
        <div className="space-y-4">
          <div className="flex gap-2">
            <div className="relative flex-1">
              <input
                type="text"
                className="input pl-9 text-xs"
                placeholder="Tìm tên, SĐT khách..."
                value={customerSearch}
                onChange={(e) => setCustomerSearch(e.target.value)}
              />
              <span className="absolute left-3 top-3 text-[10px] text-slate-500">🔍</span>
            </div>
            <button
              onClick={() => {
                setMobileCustomerModalOpen(false);
                setQuickAddCustomerOpen(true);
              }}
              className="btn btn-primary text-xs shrink-0 px-3 flex items-center justify-center gap-1 cursor-pointer"
            >
              ➕ Thêm
            </button>
          </div>

          <div className="max-h-80 overflow-y-auto divide-y divide-white/5 border border-white/5 rounded-none bg-slate-950/20">
            <button
              onClick={() => {
                setSelectedCustomerId('walk-in');
                setMobileCustomerModalOpen(false);
              }}
              className={`w-full text-left px-4 py-3.5 text-sm sm:text-base font-semibold transition-colors flex justify-between items-center ${selectedCustomerId === 'walk-in' ? 'bg-indigo-500/10 text-indigo-300' : 'text-slate-300'
                }`}
            >
              <span>Khách vãng lai</span>
              {selectedCustomerId === 'walk-in' && <span className="text-sm sm:text-base font-bold">✓</span>}
            </button>
            {filteredCustomersList.map(c => {
              const isSelected = c.id === selectedCustomerId;
              return (
                <button
                  key={c.id}
                  onClick={() => {
                    setSelectedCustomerId(c.id);
                    setMobileCustomerModalOpen(false);
                  }}
                  className={`w-full text-left px-4 py-3.5 text-sm sm:text-base transition-colors flex justify-between items-center ${isSelected ? 'bg-indigo-500/10 text-indigo-300' : 'text-white'
                    }`}
                >
                  <div>
                    <p className="font-bold text-sm sm:text-base text-white">{c.name}</p>
                    {c.phone && <p className="text-xs text-slate-400 mt-1">📞 {c.phone}</p>}
                  </div>
                  {isSelected && <span className="text-sm sm:text-base font-bold">✓</span>}
                </button>
              );
            })}
            {filteredCustomersList.length === 0 && (
              <p className="text-center text-sm text-slate-500 py-6">Không tìm thấy khách hàng nào</p>
            )}
          </div>
        </div>
      </Modal>

      {/* Mobile Select Employee Modal */}
      <Modal
        open={mobileEmployeeModalOpen}
        onClose={() => setMobileEmployeeModalOpen(false)}
        title="Chọn nhân viên bán hàng"
        maxWidth="max-w-md"
      >
        <div className="max-h-80 overflow-y-auto divide-y divide-white/5 border border-white/5 rounded-none bg-slate-950/20">
          <button
            onClick={() => {
              setSelectedEmployeeId('');
              setMobileEmployeeModalOpen(false);
            }}
            className={`w-full text-left px-4 py-3.5 text-sm sm:text-base font-semibold transition-colors flex justify-between items-center ${!selectedEmployeeId ? 'bg-indigo-500/10 text-indigo-300' : 'text-slate-300'
              }`}
          >
            <span>Không chọn nhân viên</span>
            {!selectedEmployeeId && <span className="text-sm sm:text-base font-bold">✓</span>}
          </button>
          {employees.map(emp => {
            const isSelected = emp.id === selectedEmployeeId;
            return (
              <button
                key={emp.id}
                onClick={() => {
                  setSelectedEmployeeId(emp.id);
                  setMobileEmployeeModalOpen(false);
                }}
                className={`w-full text-left px-4 py-3.5 text-sm sm:text-base transition-colors flex justify-between items-center ${isSelected ? 'bg-indigo-500/10 text-indigo-300' : 'text-white'
                  }`}
              >
                <div>
                  <p className="font-bold text-sm sm:text-base text-white">{emp.name}</p>
                  <p className="text-xs text-slate-500 mt-1">ID: {emp.id}</p>
                </div>
                {isSelected && <span className="text-sm sm:text-base font-bold">✓</span>}
              </button>
            );
          })}
        </div>
      </Modal>

      {/* Mobile Select Product Modal */}
      <Modal
        open={mobileProductModalOpen}
        onClose={() => setMobileProductModalOpen(false)}
        title="Chọn sản phẩm"
        maxWidth="max-w-md"
      >
        <div className="space-y-4">
          <div className="flex gap-2">
            <div className="relative flex-1">
              <input
                type="text"
                className="input pl-9 text-xs"
                placeholder="Tìm tên sản phẩm..."
                value={mobileProductSearch}
                onChange={(e) => setMobileProductSearch(e.target.value)}
              />
              <span className="absolute left-3 top-3 text-[10px] text-slate-500">🔍</span>
            </div>
            <button
              onClick={() => {
                setMobileProductModalOpen(false);
                setVoiceModalOpen(true);
              }}
              className="btn btn-secondary text-xs shrink-0 px-2.5 flex items-center justify-center cursor-pointer"
              title="Lên đơn bằng giọng nói"
            >
              🎤 AI
            </button>
          </div>

          <div className="max-h-96 overflow-y-auto divide-y divide-white/5 border border-white/5 rounded-none bg-slate-950/20">
            {filteredMobileProducts.map(p => {
              const cartItem = cart.find(c => c.product.id === p.id);
              const qty = cartItem ? cartItem.quantity : 0;
              return (
                <div
                  key={p.id}
                  className="px-4 py-3 flex justify-between items-center gap-3 hover:bg-white/5"
                >
                  <div className="min-w-0 flex-1">
                    <p className="font-bold text-sm sm:text-base text-white truncate">{p.name}</p>
                    <div className="flex items-center gap-2 mt-1">
                      <span className="text-[10px] px-1.5 py-0.5 rounded-none bg-slate-800 text-slate-400 font-semibold uppercase">
                        {p.itemType === 'RAW' ? 'Hàng thô' : 'Pha chế'}
                      </span>
                      <span className="text-xs text-slate-400">Tồn: {p.currentStock} {p.unit}</span>
                    </div>
                  </div>

                  <div className="flex flex-col items-end gap-2 shrink-0">
                    <span className="font-bold text-indigo-300 text-sm sm:text-base">{formatCurrency(p.price)}</span>

                    {qty > 0 ? (
                      <div className="flex items-center gap-1.5 bg-slate-900 border border-white/10 rounded-none p-0.5">
                        <button
                          onClick={() => updateQuantity(p.id, qty - 1)}
                          className="w-8 h-8 rounded-none bg-slate-800 text-slate-200 text-base flex items-center justify-center font-bold"
                        >
                          -
                        </button>
                        <span className="text-sm font-bold text-white w-7 text-center">{qty}</span>
                        <button
                          onClick={() => updateQuantity(p.id, qty + 1)}
                          className="w-8 h-8 rounded-none bg-slate-800 text-slate-200 text-base flex items-center justify-center font-bold"
                        >
                          +
                        </button>
                      </div>
                    ) : (
                      <button
                        onClick={() => addToCart(p)}
                        className="btn btn-primary h-8 px-4 py-0 text-xs sm:text-sm shadow-glow rounded-none cursor-pointer"
                      >
                        Thêm
                      </button>
                    )}
                  </div>
                </div>
              );
            })}
            {filteredMobileProducts.length === 0 && (
              <p className="text-center text-sm text-slate-500 py-8">Không tìm thấy sản phẩm nào</p>
            )}
          </div>

          <div className="flex justify-end pt-2 border-t border-slate-800">
            <button
              onClick={() => setMobileProductModalOpen(false)}
              className="btn btn-secondary w-full text-xs cursor-pointer"
            >
              Đóng
            </button>
          </div>
        </div>
      </Modal>
    </div>
  );
}
