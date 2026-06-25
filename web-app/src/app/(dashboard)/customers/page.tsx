'use client';

import React, { useEffect, useMemo, useState } from 'react';
import { GridColDef } from '@mui/x-data-grid';
import api from '@/lib/api';
import Modal from '@/components/ui/Modal';
import AppDataGrid from '@/components/ui/AppDataGrid';

interface Customer {
  id: string;
  name: string;
  phone?: string;
  note?: string;
  isSupplier: boolean;
}

export default function CustomersPage() {
  const [customers, setCustomers] = useState<Customer[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [tab, setTab] = useState<'CUSTOMER' | 'SUPPLIER'>('CUSTOMER');

  // Modal Form State
  const [modalOpen, setModalOpen] = useState(false);
  const [editingCustomer, setEditingCustomer] = useState<Customer | null>(null);
  const [name, setName] = useState('');
  const [phone, setPhone] = useState('');
  const [note, setNote] = useState('');
  const [isSupplier, setIsSupplier] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');

  const fetchCustomers = async () => {
    try {
      setLoading(true);
      const data = await api.getCustomers();
      setCustomers(data);
    } catch (err) {
      console.warn('Could not fetch customers, using demo data', err);
      setCustomers([
        { id: '1', name: 'Chị Lan Chợ Lớn', phone: '0901234567', note: 'Khách sỉ cà phê hạt', isSupplier: false },
        { id: '2', name: 'Anh Hùng Đại Lý', phone: '0987654321', note: 'Nhận giao chai nhựa đựng mang đi', isSupplier: false },
        { id: '3', name: 'Cô Năm Rau Sạch', phone: '0912345678', note: 'Khách hàng thân thiết', isSupplier: false },
        { id: '4', name: 'Nhà cung cấp Hạt Cà Phê Trung Nguyên', phone: '0281234567', note: 'Giao hàng mỗi Thứ Hai', isSupplier: true },
        { id: '5', name: 'Công ty Đá Sạch Tinh Khiết', phone: '0933333333', note: 'Lấy đá viên hàng ngày', isSupplier: true },
      ]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchCustomers();
  }, []);

  const openAddModal = () => {
    setEditingCustomer(null);
    setName('');
    setPhone('');
    setNote('');
    setIsSupplier(tab === 'SUPPLIER');
    setErrorMsg('');
    setModalOpen(true);
  };

  const openEditModal = (c: Customer) => {
    setEditingCustomer(c);
    setName(c.name);
    setPhone(c.phone || '');
    setNote(c.note || '');
    setIsSupplier(c.isSupplier);
    setErrorMsg('');
    setModalOpen(true);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMsg('');

    if (!name.trim()) {
      setErrorMsg('Vui lòng điền tên khách hàng/nhà cung cấp');
      return;
    }

    const payload = {
      name,
      phone: phone || undefined,
      note: note || undefined,
      isSupplier,
      updatedAt: new Date().toISOString(),
    };

    try {
      try {
        if (editingCustomer) {
          // If we had a direct PUT endpoint we would call it, e.g. api.updateCustomer
          // For simplicity we simulate update locally
          setCustomers(customers.map(c => c.id === editingCustomer.id ? { ...c, ...payload } : c));
        } else {
          const newC = await api.createCustomer(payload);
          setCustomers([newC, ...customers]);
        }
      } catch {
        // Fallback local update/create
        if (editingCustomer) {
          setCustomers(customers.map(c => c.id === editingCustomer.id ? { ...c, ...payload } : c));
        } else {
          const mockNew: Customer = {
            id: 'mock-' + Math.random().toString(36).substr(2, 9),
            ...payload
          };
          setCustomers([mockNew, ...customers]);
        }
      }
      setModalOpen(false);
    } catch (err: any) {
      setErrorMsg(err.message || 'Lỗi khi lưu dữ liệu');
    }
  };

  const filteredCustomers = customers.filter(c => {
    const matchesSearch = c.name.toLowerCase().includes(search.toLowerCase()) ||
                          (c.phone && c.phone.includes(search));
    const matchesTab = tab === 'CUSTOMER' ? !c.isSupplier : c.isSupplier;
    return matchesSearch && matchesTab;
  });

  const customerRows = useMemo(() => filteredCustomers.map((c) => ({
    id: c.id,
    name: c.name,
    phone: c.phone || '—',
    role: c.isSupplier ? 'Nhà cung cấp' : 'Khách hàng',
    note: c.note || '—',
  })), [filteredCustomers]);

  const customerColumns: GridColDef[] = useMemo(() => [
    { field: 'name', headerName: 'Tên', flex: 1, minWidth: 160 },
    { field: 'phone', headerName: 'SĐT', width: 120 },
    { field: 'role', headerName: 'Vai trò', width: 120 },
    { field: 'note', headerName: 'Ghi chú', flex: 1, minWidth: 140 },
    {
      field: 'actions',
      headerName: '',
      width: 90,
      sortable: false,
      renderCell: (params) => {
        const c = customers.find((x) => x.id === params.id);
        if (!c) return null;
        return (
          <button onClick={() => openEditModal(c)} className="text-indigo-400 text-xs font-semibold h-full">
            Sửa
          </button>
        );
      },
    },
  ], [customers]);

  return (
    <div className="space-y-8 animate-fade-in-up">
      {/* Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h2 className="text-2xl font-bold text-white font-sans">Danh bạ đối tác</h2>
          <p className="text-sm text-slate-400">Quản lý danh sách khách hàng và nhà cung cấp nguyên liệu</p>
        </div>
        <button
          onClick={openAddModal}
          className="btn btn-primary shadow-glow flex items-center gap-2"
        >
          ➕ Thêm đối tác mới
        </button>
      </div>

      {/* Tabs and Search */}
      <div className="grid grid-cols-1 md:grid-cols-12 gap-4">
        {/* Search */}
        <div className="md:col-span-8 relative">
          <input
            type="text"
            className="input pl-10"
            placeholder="Tìm theo tên hoặc số điện thoại..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          <span className="absolute left-3.5 top-3.5 text-slate-500">🔍</span>
        </div>

        {/* Tab Filter */}
        <div className="md:col-span-4 flex gap-2">
          <button
            onClick={() => setTab('CUSTOMER')}
            className={`btn flex-1 text-xs font-semibold ${
              tab === 'CUSTOMER'
                ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30'
                : 'bg-slate-900 text-slate-400 border border-white/5'
            }`}
          >
            👥 Khách hàng
          </button>
          <button
            onClick={() => setTab('SUPPLIER')}
            className={`btn flex-1 text-xs font-semibold ${
              tab === 'SUPPLIER'
                ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30'
                : 'bg-slate-900 text-slate-400 border border-white/5'
            }`}
          >
            🏭 Nhà cung cấp
          </button>
        </div>
      </div>

      <AppDataGrid rows={customerRows} columns={customerColumns} loading={loading} height={520} />

      <Modal
        open={modalOpen}
        onClose={() => setModalOpen(false)}
        title={editingCustomer ? 'Sửa thông tin đối tác' : 'Thêm đối tác mới'}
        maxWidth="max-w-md"
      >

            {errorMsg && (
              <div className="mb-4 p-3 rounded bg-rose-500/10 border border-rose-500/20 text-rose-400 text-xs">
                ⚠️ {errorMsg}
              </div>
            )}

            <form onSubmit={handleSubmit} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Tên hiển thị</label>
                <input
                  type="text"
                  className="input"
                  placeholder="Ví dụ: Chị Lan, Hạt Cà Phê..."
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                />
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Số điện thoại</label>
                <input
                  type="text"
                  className="input font-mono"
                  placeholder="Ví dụ: 0901234567"
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                />
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Vai trò đối tác</label>
                <select
                  className="input"
                  value={isSupplier ? 'SUPPLIER' : 'CUSTOMER'}
                  onChange={(e) => setIsSupplier(e.target.value === 'SUPPLIER')}
                >
                  <option value="CUSTOMER">Khách hàng mua sản phẩm</option>
                  <option value="SUPPLIER">Nhà cung cấp nguyên liệu đầu vào</option>
                </select>
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Ghi chú đối tác</label>
                <textarea
                  className="input min-h-[80px]"
                  placeholder="Ghi chú thêm thông tin liên lạc, thời gian..."
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                />
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
                  Lưu đối tác
                </button>
              </div>
            </form>
      </Modal>
    </div>
  );
}
