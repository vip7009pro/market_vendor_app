'use client';

import React, { useEffect, useMemo, useState } from 'react';
import { GridColDef } from '@mui/x-data-grid';
import api from '@/lib/api';
import Modal from '@/components/ui/Modal';
import AppDataGrid from '@/components/ui/AppDataGrid';
import { getAllUnitOptions, getLastUsedUnit, saveCustomUnit, saveLastUsedUnit } from '@/lib/units';
import { formatCurrency } from '@/lib/format';

interface Product {
  id: string;
  name: string;
  price: number;
  costPrice: number;
  currentStock: number;
  unit: string;
  barcode?: string;
  isActive: boolean;
  itemType: 'RAW' | 'MIX';
  isStocked: boolean;
}

export default function ProductsPage() {
  const [products, setProducts] = useState<Product[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [typeFilter, setTypeFilter] = useState<'ALL' | 'RAW' | 'MIX'>('ALL');
  
  // Modal State
  const [modalOpen, setModalOpen] = useState(false);
  const [editingProduct, setEditingProduct] = useState<Product | null>(null);
  
  // Form State
  const [name, setName] = useState('');
  const [price, setPrice] = useState(0);
  const [costPrice, setCostPrice] = useState(0);
  const [currentStock, setCurrentStock] = useState(0);
  const [unit, setUnit] = useState('cái');
  const [barcode, setBarcode] = useState('');
  const [itemType, setItemType] = useState<'RAW' | 'MIX'>('RAW');
  const [isStocked, setIsStocked] = useState(true);
  const [isActive, setIsActive] = useState(true);
  const [errorMsg, setErrorMsg] = useState('');
  const [unitMode, setUnitMode] = useState<'select' | 'custom'>('select');
  const [customUnit, setCustomUnit] = useState('');
  const [unitOptions, setUnitOptions] = useState<string[]>([]);

  const fetchProducts = async () => {
    try {
      setLoading(true);
      const data = await api.getProducts();
      setProducts(data);
    } catch (err) {
      console.warn('Could not fetch products, using demo data', err);
      setProducts([
        { id: '1', name: 'Cà phê sữa đá', price: 25000, costPrice: 12000, currentStock: 80, unit: 'ly', barcode: '8931234567890', isActive: true, itemType: 'MIX', isStocked: true },
        { id: '2', name: 'Cà phê đen đá', price: 20000, costPrice: 10000, currentStock: 120, unit: 'ly', barcode: '8931234567891', isActive: true, itemType: 'MIX', isStocked: true },
        { id: '3', name: 'Nước ngọt Coca Cola', price: 15000, costPrice: 10500, currentStock: 24, unit: 'lon', barcode: '8930001010101', isActive: true, itemType: 'RAW', isStocked: true },
        { id: '4', name: 'Trà đào cam sả', price: 35000, costPrice: 15000, currentStock: 15, unit: 'ly', barcode: '', isActive: true, itemType: 'MIX', isStocked: true },
        { id: '5', name: 'Bánh mì thịt nướng', price: 20000, costPrice: 11000, currentStock: 0, unit: 'ổ', barcode: '', isActive: true, itemType: 'MIX', isStocked: true },
        { id: '6', name: 'Khăn giấy ướt', price: 5000, costPrice: 2000, currentStock: 150, unit: 'gói', barcode: '8932020202020', isActive: true, itemType: 'RAW', isStocked: true },
      ]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchProducts();
    setUnitOptions(getAllUnitOptions());
  }, []);

  const openAddModal = () => {
    setEditingProduct(null);
    setName('');
    setPrice(0);
    setCostPrice(0);
    setCurrentStock(0);
    const lastUnit = getLastUsedUnit();
    setUnit(lastUnit);
    setUnitMode('select');
    setCustomUnit('');
    setBarcode('');
    setItemType('RAW');
    setIsStocked(true);
    setIsActive(true);
    setErrorMsg('');
    setModalOpen(true);
  };

  const openEditModal = (p: Product) => {
    setEditingProduct(p);
    setName(p.name);
    setPrice(p.price);
    setCostPrice(p.costPrice);
    setCurrentStock(p.currentStock);
    const opts = getAllUnitOptions();
    setUnitOptions(opts);
    if (opts.includes(p.unit)) {
      setUnit(p.unit);
      setUnitMode('select');
    } else {
      setUnit(p.unit);
      setUnitMode('custom');
      setCustomUnit(p.unit);
    }
    setBarcode(p.barcode || '');
    setItemType(p.itemType);
    setIsStocked(p.isStocked);
    setIsActive(p.isActive);
    setErrorMsg('');
    setModalOpen(true);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMsg('');
    
    if (!name.trim()) {
      setErrorMsg('Vui lòng điền tên sản phẩm');
      return;
    }

    const finalUnit = unitMode === 'custom' ? customUnit.trim() : unit;
    if (!finalUnit) {
      setErrorMsg('Vui lòng chọn hoặc nhập đơn vị tính');
      return;
    }

    if (unitMode === 'custom') {
      saveCustomUnit(finalUnit);
    } else {
      saveLastUsedUnit(finalUnit);
    }
    setUnitOptions(getAllUnitOptions());

    const payload = {
      name,
      price: Number(price),
      costPrice: Number(costPrice),
      currentStock: Number(currentStock),
      unit: finalUnit,
      barcode: barcode || undefined,
      itemType,
      isStocked,
      isActive,
      updatedAt: new Date().toISOString(),
    };

    try {
      if (editingProduct) {
        // update
        try {
          await api.updateProduct(editingProduct.id, payload);
        } catch {
          // Fallback local update
          setProducts(products.map(p => p.id === editingProduct.id ? { ...p, ...payload } : p));
        }
      } else {
        // create
        try {
          const newP = await api.createProduct(payload);
          setProducts([newP, ...products]);
        } catch {
          // Fallback local create
          const mockNew: Product = {
            id: 'mock-' + Math.random().toString(36).substr(2, 9),
            ...payload
          };
          setProducts([mockNew, ...products]);
        }
      }
      setModalOpen(false);
    } catch (err: any) {
      setErrorMsg(err.message || 'Lỗi khi lưu sản phẩm');
    }
  };

  const handleDelete = async (id: string) => {
    if (!confirm('Bạn có chắc chắn muốn xóa sản phẩm này không?')) return;
    try {
      try {
        await api.deleteProduct(id);
      } catch {
        // Fallback local delete
      }
      setProducts(products.filter(p => p.id !== id));
    } catch (err) {
      alert('Không thể xóa sản phẩm');
    }
  };

  const formatCurrencyLocal = formatCurrency;

  const filteredProducts = products.filter(p => {
    const matchesSearch = p.name.toLowerCase().includes(search.toLowerCase()) || 
                          (p.barcode && p.barcode.includes(search));
    const matchesType = typeFilter === 'ALL' || p.itemType === typeFilter;
    return matchesSearch && matchesType;
  });

  const productRows = useMemo(() => filteredProducts.map((p) => ({
    id: p.id,
    name: p.name,
    barcode: p.barcode || '',
    itemType: p.itemType === 'RAW' ? 'Hàng thô' : 'Pha chế',
    costPrice: Number(p.costPrice),
    price: Number(p.price),
    currentStock: Number(p.currentStock),
    unit: p.unit,
    isActive: p.isActive,
  })), [filteredProducts]);

  const productColumns: GridColDef[] = useMemo(() => [
    { field: 'name', headerName: 'Tên SP', flex: 1, minWidth: 160 },
    { field: 'itemType', headerName: 'Loại', width: 90 },
    { field: 'costPrice', headerName: 'Giá vốn', width: 110, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrencyLocal(Number(v)) },
    { field: 'price', headerName: 'Giá bán', width: 110, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrencyLocal(Number(v)) },
    { field: 'currentStock', headerName: 'Tồn', width: 70, align: 'center', headerAlign: 'center' },
    { field: 'unit', headerName: 'ĐVT', width: 60 },
    {
      field: 'actions',
      headerName: '',
      width: 120,
      sortable: false,
      renderCell: (params) => {
        const p = products.find((x) => x.id === params.id);
        if (!p) return null;
        return (
          <div className="flex gap-2 h-full items-center">
            <button onClick={() => openEditModal(p)} className="text-indigo-400 text-xs font-semibold">Sửa</button>
            <button onClick={() => handleDelete(p.id)} className="text-rose-400 text-xs font-semibold">Xóa</button>
          </div>
        );
      },
    },
  ], [products]);

  return (
    <div className="space-y-8 animate-fade-in-up">
      {/* Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h2 className="text-2xl font-bold text-white font-sans">Danh mục sản phẩm</h2>
          <p className="text-sm text-slate-400">Quản lý kho hàng, giá vốn, giá bán sản phẩm</p>
        </div>
        <button
          onClick={openAddModal}
          className="btn btn-primary shadow-glow flex items-center gap-2"
        >
          ➕ Thêm sản phẩm
        </button>
      </div>

      {/* Filter and Search */}
      <div className="grid grid-cols-1 md:grid-cols-12 gap-4">
        {/* Search */}
        <div className="md:col-span-8 relative">
          <input
            type="text"
            className="input pl-10"
            placeholder="Tìm theo tên sản phẩm hoặc mã vạch..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          <span className="absolute left-3.5 top-3.5 text-slate-500">🔍</span>
        </div>

        {/* Filter */}
        <div className="md:col-span-4 flex gap-2">
          {['ALL', 'RAW', 'MIX'].map((t) => (
            <button
              key={t}
              onClick={() => setTypeFilter(t as any)}
              className={`btn flex-1 text-xs font-semibold ${
                typeFilter === t
                  ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30'
                  : 'bg-slate-900 text-slate-400 border border-white/5'
              }`}
            >
              {t === 'ALL' ? 'Tất cả' : t === 'RAW' ? 'Hàng thô' : 'Hàng pha chế'}
            </button>
          ))}
        </div>
      </div>

      <AppDataGrid rows={productRows} columns={productColumns} loading={loading} height={560} />

      {/* Add / Edit Modal */}
      <Modal
        open={modalOpen}
        onClose={() => setModalOpen(false)}
        title={editingProduct ? 'Sửa sản phẩm' : 'Thêm sản phẩm mới'}
        maxWidth="max-w-lg"
      >
        {errorMsg && (
          <div className="mb-4 p-3 rounded bg-rose-500/10 border border-rose-500/20 text-rose-400 text-xs">
            ⚠️ {errorMsg}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Tên sản phẩm</label>
                <input
                  type="text"
                  className="input"
                  placeholder="Ví dụ: Cà phê sữa đá"
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                />
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Giá vốn (VNĐ)</label>
                  <input
                    type="number"
                    className="input"
                    value={costPrice === 0 ? '' : costPrice}
                    onChange={(e) => setCostPrice(Number(e.target.value))}
                  />
                </div>
                <div>
                  <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Giá bán (VNĐ)</label>
                  <input
                    type="number"
                    className="input"
                    value={price === 0 ? '' : price}
                    onChange={(e) => setPrice(Number(e.target.value))}
                  />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Số lượng ban đầu</label>
                  <input
                    type="number"
                    className="input"
                    value={currentStock}
                    onChange={(e) => setCurrentStock(Number(e.target.value))}
                  />
                </div>
                <div>
                  <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Đơn vị tính</label>
                  {unitMode === 'select' ? (
                    <div className="space-y-2">
                      <select
                        className="input"
                        value={unit}
                        onChange={(e) => {
                          if (e.target.value === '__custom__') {
                            setUnitMode('custom');
                            setCustomUnit('');
                          } else {
                            setUnit(e.target.value);
                          }
                        }}
                      >
                        {unitOptions.map((u) => (
                          <option key={u} value={u}>{u}</option>
                        ))}
                        <option value="__custom__">+ Thêm đơn vị mới...</option>
                      </select>
                    </div>
                  ) : (
                    <div className="flex gap-2">
                      <input
                        type="text"
                        className="input flex-1"
                        placeholder="Nhập đơn vị mới..."
                        value={customUnit}
                        onChange={(e) => setCustomUnit(e.target.value)}
                      />
                      <button
                        type="button"
                        onClick={() => {
                          setUnitMode('select');
                          setCustomUnit('');
                        }}
                        className="btn btn-secondary text-xs shrink-0"
                      >
                        Chọn có sẵn
                      </button>
                    </div>
                  )}
                </div>
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Mã vạch / Barcode (nếu có)</label>
                <input
                  type="text"
                  className="input"
                  placeholder="Quét hoặc nhập mã vạch..."
                  value={barcode}
                  onChange={(e) => setBarcode(e.target.value)}
                />
              </div>

              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Phân loại hàng</label>
                  <select
                    className="input"
                    value={itemType}
                    onChange={(e) => setItemType(e.target.value as any)}
                  >
                    <option value="RAW">Hàng thô (lon, chai)</option>
                    <option value="MIX">Pha chế (ly, tách, dĩa)</option>
                  </select>
                </div>

                <div className="flex items-center justify-around border border-white/5 rounded-lg bg-slate-950/20 px-4">
                  <label className="flex items-center gap-2 cursor-pointer text-xs font-semibold text-slate-400">
                    <input
                      type="checkbox"
                      checked={isActive}
                      onChange={(e) => setIsActive(e.target.checked)}
                      className="w-4 h-4 accent-indigo-500"
                    />
                    Đang kinh doanh
                  </label>
                </div>
              </div>

              <div className="flex justify-end gap-3 pt-4 border-t border-slate-800">
                <button
                  type="button"
                  onClick={() => setModalOpen(false)}
                  className="btn btn-secondary text-xs"
                >
                  Hủy
                </button>
                <button
                  type="submit"
                  className="btn btn-primary text-xs shadow-glow"
                >
                  Lưu sản phẩm
                </button>
              </div>
            </form>
      </Modal>
    </div>
  );
}
