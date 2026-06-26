'use client';

import React, { useEffect, useMemo, useState } from 'react';
import { GridColDef } from '@mui/x-data-grid';
import api from '@/lib/api';
import Modal from '@/components/ui/Modal';
import AppDataGrid from '@/components/ui/AppDataGrid';
import { getAllUnitOptions, getLastUsedUnit, saveCustomUnit, saveLastUsedUnit } from '@/lib/units';
import { formatCurrency, formatDateTime } from '@/lib/format';
import { matchVietnamese } from '@/lib/text';

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
  const [activeTab, setActiveTab] = useState<'inventory' | 'imports' | 'exports'>('inventory');

  // Sub-tab 1: Tồn kho
  const [products, setProducts] = useState<Product[]>([]);
  const [loadingProducts, setLoadingProducts] = useState(true);
  const [searchInventory, setSearchInventory] = useState('');
  const [typeFilter, setTypeFilter] = useState<'ALL' | 'RAW' | 'MIX'>('ALL');

  // Sub-tab 2: Lịch sử nhập kho
  const [imports, setImports] = useState<any[]>([]);
  const [loadingImports, setLoadingImports] = useState(false);
  const [searchImport, setSearchImport] = useState('');
  const [importStartDate, setImportStartDate] = useState(
    new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString().split('T')[0]
  );
  const [importEndDate, setImportEndDate] = useState(new Date().toISOString().split('T')[0]);

  // Sub-tab 3: Lịch sử xuất kho RAW
  const [exports, setExports] = useState<any[]>([]);
  const [loadingExports, setLoadingExports] = useState(false);
  const [searchExport, setSearchExport] = useState('');
  const [exportStartDate, setExportStartDate] = useState(
    new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString().split('T')[0]
  );
  const [exportEndDate, setExportEndDate] = useState(new Date().toISOString().split('T')[0]);

  // Product Add / Edit Modal State
  const [modalOpen, setModalOpen] = useState(false);
  const [editingProduct, setEditingProduct] = useState<Product | null>(null);

  // Product Form State
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

  // Opening stock modal states
  const [openingStockModalOpen, setOpeningStockModalOpen] = useState(false);
  const [openingStockMonth, setOpeningStockMonth] = useState(new Date().getMonth() + 1);
  const [openingStockYear, setOpeningStockYear] = useState(new Date().getFullYear());
  const [openingStocks, setOpeningStocks] = useState<Record<string, string>>({});
  const [savingOpeningStock, setSavingOpeningStock] = useState(false);

  // Fetch Products
  const fetchProducts = async () => {
    try {
      setLoadingProducts(true);
      const data = await api.getProducts();
      setProducts(data || []);
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
      setLoadingProducts(false);
    }
  };

  // Fetch Imports (Purchase history)
  const fetchImports = async () => {
    try {
      setLoadingImports(true);
      const data = await api.getPurchaseHistory({
        startDate: importStartDate,
        endDate: importEndDate,
      });
      setImports(data || []);
    } catch (err) {
      console.warn('Could not fetch imports history', err);
      setImports([]);
    } finally {
      setLoadingImports(false);
    }
  };

  // Fetch Exports (RAW exports)
  const fetchExports = async () => {
    try {
      setLoadingExports(true);
      const data = await api.getExportHistory({
        startDate: exportStartDate,
        endDate: exportEndDate,
      });
      setExports(data || []);
    } catch (err) {
      console.warn('Could not fetch exports history', err);
      setExports([]);
    } finally {
      setLoadingExports(false);
    }
  };

  // Handle active tab switching & date range updates
  useEffect(() => {
    if (activeTab === 'inventory') {
      fetchProducts();
    } else if (activeTab === 'imports') {
      fetchImports();
    } else if (activeTab === 'exports') {
      fetchExports();
    }
  }, [activeTab, importStartDate, importEndDate, exportStartDate, exportEndDate]);

  useEffect(() => {
    setUnitOptions(getAllUnitOptions());
  }, []);

  // Fetch opening stocks on month/year/open changes
  useEffect(() => {
    if (openingStockModalOpen) {
      loadOpeningStocks(openingStockMonth, openingStockYear);
    }
  }, [openingStockModalOpen, openingStockMonth, openingStockYear]);

  const loadOpeningStocks = async (month: number, year: number) => {
    try {
      const existing = await api.getOpeningStocks(year, month);
      const stocksMap: Record<string, string> = {};
      
      // Default to 0 for RAW products
      products.forEach((p) => {
        if (p.itemType === 'RAW') {
          stocksMap[p.id] = '0';
        }
      });

      if (Array.isArray(existing)) {
        existing.forEach((row: any) => {
          stocksMap[row.productId] = String(Number(row.openingStock || 0));
        });
      }
      setOpeningStocks(stocksMap);
    } catch (err) {
      console.warn('Could not fetch opening stocks', err);
    }
  };

  const handlePreFillOpeningStocks = () => {
    const stocksMap = { ...openingStocks };
    products.forEach((p) => {
      if (p.itemType === 'RAW') {
        stocksMap[p.id] = String(Number(p.currentStock || 0));
      }
    });
    setOpeningStocks(stocksMap);
  };

  const handleSaveOpeningStocks = async () => {
    try {
      setSavingOpeningStock(true);
      await Promise.all(
        Object.entries(openingStocks).map(([productId, val]) =>
          api.updateOpeningStock({
            productId,
            year: openingStockYear,
            month: openingStockMonth,
            openingStock: Number(val || 0),
          })
        )
      );
      setOpeningStockModalOpen(false);
      alert('Đã cập nhật tồn đầu kỳ thành công!');
    } catch (err) {
      alert('Lỗi cập nhật tồn đầu kỳ: ' + (err instanceof Error ? err.message : String(err)));
    } finally {
      setSavingOpeningStock(false);
    }
  };

  // Add / Edit product handlers
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
        try {
          await api.updateProduct(editingProduct.id, payload);
        } catch {
          // Local fallback
        }
        setProducts(products.map(p => p.id === editingProduct.id ? { ...p, ...payload } : p));
      } else {
        let newP;
        try {
          newP = await api.createProduct(payload);
        } catch {
          newP = {
            id: 'mock-' + Math.random().toString(36).substr(2, 9),
            ...payload
          };
        }
        setProducts([newP, ...products]);
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

  // Inventory logic
  const filteredProducts = useMemo(() => {
    return products.filter((p) => {
      const matchesSearch = matchVietnamese(p.name, searchInventory) || 
                            (p.barcode && p.barcode.includes(searchInventory));
      const matchesType = typeFilter === 'ALL' || p.itemType === typeFilter;
      return matchesSearch && matchesType;
    });
  }, [products, searchInventory, typeFilter]);

  const productRows = useMemo(() => {
    return filteredProducts.map((p) => ({
      id: p.id,
      name: p.name,
      barcode: p.barcode || '—',
      itemType: p.itemType === 'RAW' ? 'Hàng thô' : 'Pha chế',
      costPrice: Number(p.costPrice),
      price: Number(p.price),
      currentStock: p.itemType === 'MIX' ? '—' : Number(p.currentStock),
      unit: p.unit,
      isActive: p.isActive,
    }));
  }, [filteredProducts]);

  const productColumns: GridColDef[] = useMemo(() => [
    { field: 'name', headerName: 'Tên SP', flex: 1, minWidth: 160 },
    { field: 'itemType', headerName: 'Loại', width: 100 },
    { field: 'costPrice', headerName: 'Giá vốn', width: 120, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
    { field: 'price', headerName: 'Giá bán', width: 120, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
    { field: 'currentStock', headerName: 'Tồn kho', width: 90, align: 'center', headerAlign: 'center' },
    { field: 'unit', headerName: 'ĐVT', width: 70 },
    {
      field: 'actions',
      headerName: '',
      width: 110,
      sortable: false,
      renderCell: (params) => {
        const p = products.find((x) => x.id === params.id);
        if (!p) return null;
        return (
          <div className="flex gap-3.5 h-full items-center">
            <button onClick={() => openEditModal(p)} className="text-indigo-400 text-xs font-semibold hover:text-indigo-300">Sửa</button>
            <button onClick={() => handleDelete(p.id)} className="text-rose-400 text-xs font-semibold hover:text-rose-300">Xóa</button>
          </div>
        );
      },
    },
  ], [products]);

  // Import history logic
  const filteredImports = useMemo(() => {
    return imports.filter((item) => {
      return matchVietnamese(item.productName || '', searchImport) ||
             matchVietnamese(item.supplierName || '', searchImport) ||
             matchVietnamese(item.note || '', searchImport);
    });
  }, [imports, searchImport]);

  const importRows = useMemo(() => {
    return filteredImports.map((item) => ({
      id: item.id,
      createdAt: item.createdAt,
      productName: item.productName,
      supplierName: item.supplierName || '—',
      quantity: Number(item.quantity),
      unitCost: Number(item.unitCost),
      totalCost: Number(item.totalCost),
      note: item.note || '—',
    }));
  }, [filteredImports]);

  const importColumns: GridColDef[] = useMemo(() => [
    { field: 'createdAt', headerName: 'Thời gian', width: 140, valueFormatter: (v) => formatDateTime(String(v)) },
    { field: 'productName', headerName: 'Tên nguyên liệu/SP', flex: 1, minWidth: 150 },
    { field: 'supplierName', headerName: 'Nhà cung cấp', width: 140 },
    { field: 'quantity', headerName: 'Số lượng', width: 100, type: 'number', align: 'center', headerAlign: 'center' },
    { field: 'unitCost', headerName: 'Đơn giá nhập', width: 120, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
    { field: 'totalCost', headerName: 'Thành tiền', width: 130, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
    { field: 'note', headerName: 'Ghi chú', width: 130 },
  ], []);

  const totalImportQuantity = useMemo(() => {
    return filteredImports.reduce((sum, item) => sum + Number(item.quantity || 0), 0);
  }, [filteredImports]);

  const totalImportCost = useMemo(() => {
    return filteredImports.reduce((sum, item) => sum + Number(item.totalCost || 0), 0);
  }, [filteredImports]);

  // Export history logic
  const filteredExports = useMemo(() => {
    return exports.filter((item) => {
      return matchVietnamese(item.productName || '', searchExport) ||
             matchVietnamese(item.customerName || '', searchExport) ||
             matchVietnamese(item.employeeName || '', searchExport) ||
             matchVietnamese(item.saleId || '', searchExport);
    });
  }, [exports, searchExport]);

  const exportRows = useMemo(() => {
    return filteredExports.map((item) => ({
      id: item.id,
      createdAt: item.createdAt,
      productName: item.productName,
      customerName: item.customerName || '—',
      employeeName: item.employeeName || '—',
      quantity: Number(item.quantity),
      unitCost: Number(item.unitCost),
      totalCost: Number(item.totalCost),
      itemType: item.itemType === 'MIX' ? 'Từ món MIX' : 'Hàng thô',
      saleId: item.saleId,
    }));
  }, [filteredExports]);

  const exportColumns: GridColDef[] = useMemo(() => [
    { field: 'createdAt', headerName: 'Thời gian', width: 140, valueFormatter: (v) => formatDateTime(String(v)) },
    { field: 'productName', headerName: 'Nguyên liệu RAW', flex: 1, minWidth: 150 },
    { field: 'customerName', headerName: 'Khách hàng', width: 130 },
    { field: 'employeeName', headerName: 'Nhân viên', width: 110 },
    { field: 'quantity', headerName: 'SL xuất', width: 90, type: 'number', align: 'center', headerAlign: 'center' },
    { field: 'unitCost', headerName: 'Đơn giá vốn', width: 110, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
    { field: 'totalCost', headerName: 'Trị giá xuất', width: 120, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
    { field: 'itemType', headerName: 'Kiểu xuất', width: 110, align: 'center' },
    {
      field: 'saleId',
      headerName: 'Mã đơn',
      width: 100,
      valueFormatter: (v) => v ? `#${String(v).slice(-6).toUpperCase()}` : '—',
    },
  ], []);

  const totalExportQuantity = useMemo(() => {
    return filteredExports.reduce((sum, item) => sum + Number(item.quantity || 0), 0);
  }, [filteredExports]);

  const totalExportCost = useMemo(() => {
    return filteredExports.reduce((sum, item) => sum + Number(item.totalCost || 0), 0);
  }, [filteredExports]);

  // Main UI render
  return (
    <div className="space-y-6 animate-fade-in-up">
      {/* Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h2 className="text-2xl font-bold text-white font-sans">Quản lý kho hàng & sản phẩm</h2>
          <p className="text-sm text-slate-400">Xem tồn kho hiện tại, lịch sử nhập hàng và lịch sử xuất hàng thô</p>
        </div>
        <div className="flex gap-2 shrink-0">
          <button
            onClick={() => setOpeningStockModalOpen(true)}
            className="btn btn-secondary flex items-center gap-1.5 text-xs font-semibold cursor-pointer py-2 px-3 border border-white/5 bg-slate-900 text-slate-300 rounded-xl hover:bg-slate-800 hover:text-white"
          >
            📋 Đầu kỳ
          </button>
          <button
            onClick={openAddModal}
            className="btn btn-primary shadow-glow flex items-center gap-2 py-2 px-4 rounded-xl text-xs font-semibold"
          >
            ➕ Thêm sản phẩm
          </button>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex border-b border-slate-800 gap-1.5 pb-px">
        <button
          onClick={() => setActiveTab('inventory')}
          className={`px-4 py-2.5 text-xs font-bold transition-all border-b-2 ${
            activeTab === 'inventory'
              ? 'border-indigo-500 text-indigo-400'
              : 'border-transparent text-slate-500 hover:text-slate-300'
          }`}
        >
          📦 Tồn kho hiện tại
        </button>
        <button
          onClick={() => setActiveTab('imports')}
          className={`px-4 py-2.5 text-xs font-bold transition-all border-b-2 ${
            activeTab === 'imports'
              ? 'border-indigo-500 text-indigo-400'
              : 'border-transparent text-slate-500 hover:text-slate-300'
          }`}
        >
          📥 Lịch sử nhập kho
        </button>
        <button
          onClick={() => setActiveTab('exports')}
          className={`px-4 py-2.5 text-xs font-bold transition-all border-b-2 ${
            activeTab === 'exports'
              ? 'border-indigo-500 text-indigo-400'
              : 'border-transparent text-slate-500 hover:text-slate-300'
          }`}
        >
          📤 Lịch sử xuất kho RAW
        </button>
      </div>

      {/* Tab Contents */}
      {activeTab === 'inventory' && (
        <div className="space-y-4">
          {/* Filters */}
          <div className="grid grid-cols-1 md:grid-cols-12 gap-4">
            <div className="md:col-span-8 relative">
              <input
                type="text"
                className="input pl-10 text-xs"
                placeholder="Tìm theo tên sản phẩm hoặc mã vạch..."
                value={searchInventory}
                onChange={(e) => setSearchInventory(e.target.value)}
              />
              <span className="absolute left-3.5 top-3 text-slate-500 text-xs">🔍</span>
            </div>

            <div className="md:col-span-4 flex gap-2">
              {['ALL', 'RAW', 'MIX'].map((t) => (
                <button
                  key={t}
                  onClick={() => setTypeFilter(t as any)}
                  className={`btn flex-1 py-2 text-xs font-semibold ${
                    typeFilter === t
                      ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30'
                      : 'bg-slate-900 text-slate-400 border border-white/5 hover:bg-slate-800'
                  }`}
                >
                  {t === 'ALL' ? 'Tất cả' : t === 'RAW' ? 'Hàng thô' : 'Hàng pha chế'}
                </button>
              ))}
            </div>
          </div>

          <AppDataGrid rows={productRows} columns={productColumns} loading={loadingProducts} height={520} />
        </div>
      )}

      {activeTab === 'imports' && (
        <div className="space-y-5">
          {/* Summary widgets */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div className="bg-slate-900/50 p-4.5 rounded-2xl border border-white/5 flex flex-col justify-between">
              <span className="text-[10px] uppercase font-bold text-slate-400 tracking-wider">Tổng lượng nhập</span>
              <span className="text-xl font-bold text-white mt-1.5">{totalImportQuantity.toLocaleString('vi-VN')}</span>
              <span className="text-[10px] text-slate-500 mt-0.5">Số lượng nguyên vật liệu đã nhập trong bộ lọc</span>
            </div>
            <div className="bg-slate-900/50 p-4.5 rounded-2xl border border-white/5 flex flex-col justify-between">
              <span className="text-[10px] uppercase font-bold text-slate-400 tracking-wider">Tổng tiền nhập</span>
              <span className="text-xl font-bold text-emerald-400 mt-1.5">{formatCurrency(totalImportCost)}</span>
              <span className="text-[10px] text-slate-500 mt-0.5">Tổng giá trị đơn hàng nhập kho trong bộ lọc</span>
            </div>
          </div>

          {/* Filters */}
          <div className="grid grid-cols-1 md:grid-cols-12 gap-4 items-center">
            <div className="md:col-span-5 relative">
              <input
                type="text"
                className="input pl-10 text-xs"
                placeholder="Tìm theo sản phẩm, nhà cung cấp, ghi chú..."
                value={searchImport}
                onChange={(e) => setSearchImport(e.target.value)}
              />
              <span className="absolute left-3.5 top-3 text-slate-500 text-xs">🔍</span>
            </div>

            <div className="md:col-span-7 flex flex-wrap gap-2 items-center justify-end text-xs text-slate-400">
              <div className="flex items-center gap-1.5">
                <span>Từ:</span>
                <input
                  type="date"
                  className="input py-1 px-2.5 w-32 text-xs"
                  value={importStartDate}
                  onChange={(e) => setImportStartDate(e.target.value)}
                />
              </div>
              <div className="flex items-center gap-1.5">
                <span>Đến:</span>
                <input
                  type="date"
                  className="input py-1 px-2.5 w-32 text-xs"
                  value={importEndDate}
                  onChange={(e) => setImportEndDate(e.target.value)}
                />
              </div>
            </div>
          </div>

          <AppDataGrid rows={importRows} columns={importColumns} loading={loadingImports} height={420} />
        </div>
      )}

      {activeTab === 'exports' && (
        <div className="space-y-5">
          {/* Summary widgets */}
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div className="bg-slate-900/50 p-4.5 rounded-2xl border border-white/5 flex flex-col justify-between">
              <span className="text-[10px] uppercase font-bold text-slate-400 tracking-wider">Tổng lượng xuất</span>
              <span className="text-xl font-bold text-white mt-1.5">{totalExportQuantity.toLocaleString('vi-VN')}</span>
              <span className="text-[10px] text-slate-500 mt-0.5">Số lượng thô đã xuất (bao gồm cả pha chế)</span>
            </div>
            <div className="bg-slate-900/50 p-4.5 rounded-2xl border border-white/5 flex flex-col justify-between">
              <span className="text-[10px] uppercase font-bold text-slate-400 tracking-wider">Tổng trị giá xuất (Giá vốn)</span>
              <span className="text-xl font-bold text-amber-400 mt-1.5">{formatCurrency(totalExportCost)}</span>
              <span className="text-[10px] text-slate-500 mt-0.5">Tổng trị giá vốn đã xuất khỏi kho hàng</span>
            </div>
          </div>

          {/* Filters */}
          <div className="grid grid-cols-1 md:grid-cols-12 gap-4 items-center">
            <div className="md:col-span-5 relative">
              <input
                type="text"
                className="input pl-10 text-xs"
                placeholder="Tìm theo sản phẩm, khách hàng, mã đơn..."
                value={searchExport}
                onChange={(e) => setSearchExport(e.target.value)}
              />
              <span className="absolute left-3.5 top-3 text-slate-500 text-xs">🔍</span>
            </div>

            <div className="md:col-span-7 flex flex-wrap gap-2 items-center justify-end text-xs text-slate-400">
              <div className="flex items-center gap-1.5">
                <span>Từ:</span>
                <input
                  type="date"
                  className="input py-1 px-2.5 w-32 text-xs"
                  value={exportStartDate}
                  onChange={(e) => setExportStartDate(e.target.value)}
                />
              </div>
              <div className="flex items-center gap-1.5">
                <span>Đến:</span>
                <input
                  type="date"
                  className="input py-1 px-2.5 w-32 text-xs"
                  value={exportEndDate}
                  onChange={(e) => setExportEndDate(e.target.value)}
                />
              </div>
            </div>
          </div>

          <AppDataGrid rows={exportRows} columns={exportColumns} loading={loadingExports} height={420} />
        </div>
      )}

      {/* Opening Stock Modal */}
      <Modal
        open={openingStockModalOpen}
        onClose={() => setOpeningStockModalOpen(false)}
        title={`Cập nhật tồn đầu kỳ: Tháng ${openingStockMonth}/${openingStockYear}`}
        maxWidth="max-w-xl"
      >
        <div className="space-y-4">
          <div className="flex items-center gap-4 bg-slate-950/40 p-3 rounded-xl border border-white/5">
            <div className="flex-1 flex gap-2">
              <div className="flex-1">
                <label className="block text-[10px] text-slate-500 uppercase font-bold mb-1">Tháng</label>
                <select
                  value={openingStockMonth}
                  onChange={(e) => setOpeningStockMonth(Number(e.target.value))}
                  className="input py-1 text-xs h-9"
                >
                  {Array.from({ length: 12 }, (_, i) => (
                    <option key={i + 1} value={i + 1}>{i + 1}</option>
                  ))}
                </select>
              </div>
              <div className="flex-1">
                <label className="block text-[10px] text-slate-500 uppercase font-bold mb-1">Năm</label>
                <select
                  value={openingStockYear}
                  onChange={(e) => setOpeningStockYear(Number(e.target.value))}
                  className="input py-1 text-xs h-9"
                >
                  {Array.from({ length: 11 }, (_, i) => {
                    const y = new Date().getFullYear() - 5 + i;
                    return <option key={y} value={y}>{y}</option>;
                  })}
                </select>
              </div>
            </div>
            <button
              onClick={handlePreFillOpeningStocks}
              className="btn btn-secondary text-xs h-9 mt-4.5 cursor-pointer hover:bg-slate-800"
            >
              🪄 Lấy tồn hiện tại cho tất cả
            </button>
          </div>

          {/* Product Input List */}
          <div className="max-h-[300px] overflow-y-auto space-y-2 pr-1 border border-white/5 rounded-xl p-3 bg-slate-950/20">
            {products.filter(p => p.itemType === 'RAW').length === 0 ? (
              <div className="text-center text-slate-500 text-xs py-8">Chưa có sản phẩm RAW nào để thiết lập</div>
            ) : (
              products
                .filter((p) => p.itemType === 'RAW')
                .map((p) => (
                  <div key={p.id} className="flex justify-between items-center py-2 border-b border-white/5 last:border-b-0 text-xs">
                    <div>
                      <p className="font-semibold text-white">{p.name}</p>
                      <p className="text-[10px] text-slate-500">Đơn vị: {p.unit}</p>
                    </div>
                    <div className="flex items-center gap-2">
                      <span className="text-[10px] text-slate-400">Tồn đầu kỳ:</span>
                      <input
                        type="number"
                        className="input py-1 px-2 text-xs w-24 text-right h-8"
                        value={openingStocks[p.id] ?? '0'}
                        onChange={(e) =>
                          setOpeningStocks({
                            ...openingStocks,
                            [p.id]: e.target.value,
                          })
                        }
                      />
                    </div>
                  </div>
                ))
            )}
          </div>

          <div className="flex justify-end gap-3 pt-3 border-t border-slate-800">
            <button
              type="button"
              onClick={() => setOpeningStockModalOpen(false)}
              className="btn btn-secondary text-xs"
            >
              Hủy
            </button>
            <button
              onClick={handleSaveOpeningStocks}
              disabled={savingOpeningStock}
              className="btn btn-primary text-xs shadow-glow disabled:opacity-50"
            >
              {savingOpeningStock ? 'Đang lưu...' : 'Lưu tồn đầu kỳ'}
            </button>
          </div>
        </div>
      </Modal>

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

        <form onSubmit={handleSubmit} className="space-y-4 text-xs">
          <div>
            <label className="block text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-2">Tên sản phẩm</label>
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
              <label className="block text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-2">Giá vốn (VNĐ)</label>
              <input
                type="number"
                className="input"
                value={costPrice === 0 ? '' : costPrice}
                onChange={(e) => setCostPrice(Number(e.target.value))}
              />
            </div>
            <div>
              <label className="block text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-2">Giá bán (VNĐ)</label>
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
              <label className="block text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-2">Số lượng ban đầu</label>
              <input
                type="number"
                className="input"
                value={currentStock}
                onChange={(e) => setCurrentStock(Number(e.target.value))}
                disabled={itemType === 'MIX'} // MIX item has no stock
              />
            </div>
            <div>
              <label className="block text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-2">Đơn vị tính</label>
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
            <label className="block text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-2">Mã vạch / Barcode (nếu có)</label>
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
              <label className="block text-[10px] font-bold text-slate-400 uppercase tracking-wider mb-2">Phân loại hàng</label>
              <select
                className="input"
                value={itemType}
                onChange={(e) => {
                  const val = e.target.value as any;
                  setItemType(val);
                  if (val === 'MIX') {
                    setCurrentStock(0);
                  }
                }}
              >
                <option value="RAW">Hàng thô (lon, chai)</option>
                <option value="MIX">Pha chế (ly, tách, dĩa)</option>
              </select>
            </div>

            <div className="flex items-center justify-around border border-white/5 rounded-lg bg-slate-950/20 px-4">
              <label className="flex items-center gap-2 cursor-pointer text-[11px] font-semibold text-slate-400">
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
