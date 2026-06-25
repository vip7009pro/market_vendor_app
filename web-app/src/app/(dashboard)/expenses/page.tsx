'use client';

import React, { useEffect, useMemo, useState } from 'react';
import { GridColDef } from '@mui/x-data-grid';
import api from '@/lib/api';
import Modal from '@/components/ui/Modal';
import AppDataGrid from '@/components/ui/AppDataGrid';
import { formatCurrency, formatDateTime } from '@/lib/format';

interface Expense {
  id: string;
  name: string;
  amount: number;
  category: string;
  createdAt: string;
  note?: string;
}

function normalizeExpense(raw: any): Expense {
  const createdAt = raw.occurredAt || raw.createdAt || new Date().toISOString();
  const note = raw.note || '';
  const category = raw.category || 'OTHER';
  return {
    id: raw.id,
    name: raw.name || note || category || 'Chi phí',
    amount: Number(raw.amount) || 0,
    category,
    createdAt: typeof createdAt === 'string' ? createdAt : new Date(createdAt).toISOString(),
    note: note || undefined,
  };
}

const EXPENSE_CATEGORIES = [
  { value: 'MATERIALS', label: 'Nguyên liệu nhập khẩu' },
  { value: 'RENT', label: 'Tiền thuê mặt bằng' },
  { value: 'UTILITIES', label: 'Điện, nước, internet' },
  { value: 'SALARY', label: 'Lương nhân viên' },
  { value: 'MARKETING', label: 'Quảng cáo, tiếp thị' },
  { value: 'OTHER', label: 'Chi phí khác' },
];

export default function ExpensesPage() {
  const [expenses, setExpenses] = useState<Expense[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [categoryFilter, setCategoryFilter] = useState('ALL');

  // Add Expense Modal Form State
  const [modalOpen, setModalOpen] = useState(false);
  const [name, setName] = useState('');
  const [amount, setAmount] = useState(0);
  const [category, setCategory] = useState('MATERIALS');
  const [note, setNote] = useState('');
  const [errorMsg, setErrorMsg] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const fetchExpenses = async () => {
    try {
      setLoading(true);
      const data = await api.getExpenses();
      setExpenses((Array.isArray(data) ? data : []).map(normalizeExpense));
    } catch (err) {
      console.warn('Could not fetch expenses, using demo data', err);
      // Demo expenses
      setExpenses([
        { id: 'exp-1', name: 'Tiền đá viên làm mát', amount: 35000, category: 'MATERIALS', createdAt: new Date().toISOString(), note: 'Nhận từ xe giao đá lẻ' },
        { id: 'exp-2', name: 'Thanh toán tiền điện tháng 6', amount: 1200000, category: 'UTILITIES', createdAt: new Date(Date.now() - 86400000).toISOString() },
        { id: 'exp-3', name: 'Lương hỗ trợ nhân viên part-time', amount: 4500000, category: 'SALARY', createdAt: new Date(Date.now() - 86400000 * 3).toISOString(), note: 'Lương tuần 2 tháng 6' },
      ]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchExpenses();
  }, []);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMsg('');

    if (!name.trim() || amount <= 0) {
      setErrorMsg('Vui lòng điền tên chi phí và số tiền hợp lệ');
      return;
    }

    setSubmitting(true);
    const payload = {
      occurredAt: new Date().toISOString(),
      amount: Number(amount),
      category,
      note: name.trim() || note || undefined,
      updatedAt: new Date().toISOString(),
    };

    try {
      try {
        const newExp = await api.createExpense(payload);
        setExpenses([normalizeExpense(newExp), ...expenses]);
      } catch (err) {
        console.warn('API error creating expense, applying local fallback', err);
        const mockNew: Expense = {
          id: 'mock-exp-' + Math.random().toString(36).substr(2, 9),
          name: name.trim() || category,
          amount: Number(amount),
          category,
          createdAt: payload.occurredAt,
          note: note || undefined,
        };
        setExpenses([mockNew, ...expenses]);
      }
      setModalOpen(false);
      setName('');
      setAmount(0);
      setCategory('MATERIALS');
      setNote('');
    } catch (err: any) {
      setErrorMsg(err.message || 'Lỗi khi ghi chi phí');
    } finally {
      setSubmitting(false);
    }
  };

  const getCategoryLabel = (val: string) => {
    return EXPENSE_CATEGORIES.find(c => c.value === val)?.label || val || 'Khác';
  };

  const filteredExpenses = expenses.filter(e => {
    const searchText = (e.name || e.note || e.category || '').toLowerCase();
    const matchesSearch = searchText.includes(search.toLowerCase());
    const matchesCategory = categoryFilter === 'ALL' || e.category === categoryFilter;
    return matchesSearch && matchesCategory;
  });

  const expenseRows = useMemo(() => filteredExpenses.map((e) => ({
    id: e.id,
    createdAt: e.createdAt,
    categoryLabel: getCategoryLabel(e.category),
    name: e.name,
    note: e.note || '—',
    amount: e.amount,
  })), [filteredExpenses]);

  const expenseColumns: GridColDef[] = useMemo(() => [
    { field: 'createdAt', headerName: 'Thời gian', width: 140, valueFormatter: (v) => formatDateTime(String(v)) },
    { field: 'categoryLabel', headerName: 'Hạng mục', width: 150 },
    { field: 'name', headerName: 'Tên chi phí', flex: 1, minWidth: 140 },
    { field: 'note', headerName: 'Ghi chú', flex: 1, minWidth: 120 },
    { field: 'amount', headerName: 'Số tiền', width: 120, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
  ], []);

  return (
    <div className="space-y-8 animate-fade-in-up">
      {/* Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h2 className="text-2xl font-bold text-white font-sans">Chi phí hoạt động</h2>
          <p className="text-sm text-slate-400">Ghi nhận các khoản chi tiêu vận hành cửa hàng</p>
        </div>
        <button
          onClick={() => setModalOpen(true)}
          className="btn btn-primary shadow-glow flex items-center gap-2"
        >
          ➕ Ghi chi phí mới
        </button>
      </div>

      {/* Summary Stat */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
        <div className="card bg-slate-900 border-white/5 flex items-center gap-4">
          <div className="w-12 h-12 rounded-xl bg-rose-500/10 flex items-center justify-center text-xl text-rose-400">
            💸
          </div>
          <div>
            <p className="text-xs text-slate-500 font-semibold uppercase tracking-wider">Tổng chi hôm nay</p>
            <h3 className="text-xl font-bold text-white mt-1">
              {formatCurrency(expenses
                .filter(e => new Date(e.createdAt).toDateString() === new Date().toDateString())
                .reduce((sum, e) => sum + e.amount, 0)
              )}
            </h3>
          </div>
        </div>

        <div className="card bg-slate-900 border-white/5 flex items-center gap-4">
          <div className="w-12 h-12 rounded-xl bg-indigo-500/10 flex items-center justify-center text-xl text-indigo-400">
            📆
          </div>
          <div>
            <p className="text-xs text-slate-500 font-semibold uppercase tracking-wider">Tổng chi tháng này</p>
            <h3 className="text-xl font-bold text-white mt-1">
              {formatCurrency(expenses.reduce((sum, e) => sum + e.amount, 0))}
            </h3>
          </div>
        </div>
      </div>

      {/* Filter and Search */}
      <div className="grid grid-cols-1 md:grid-cols-12 gap-4">
        {/* Search */}
        <div className="md:col-span-8 relative">
          <input
            type="text"
            className="input pl-10"
            placeholder="Tìm theo tên chi phí..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          <span className="absolute left-3.5 top-3.5 text-slate-500">🔍</span>
        </div>

        {/* Category Filter */}
        <div className="md:col-span-4">
          <select
            className="input text-xs"
            value={categoryFilter}
            onChange={(e) => setCategoryFilter(e.target.value)}
          >
            <option value="ALL">Tất cả hạng mục chi</option>
            {EXPENSE_CATEGORIES.map(c => (
              <option key={c.value} value={c.value}>{c.label}</option>
            ))}
          </select>
        </div>
      </div>

      <AppDataGrid rows={expenseRows} columns={expenseColumns} loading={loading} height={480} />

      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title="Ghi nhận khoản chi mới" maxWidth="max-w-md">

            {errorMsg && (
              <div className="mb-4 p-3 rounded bg-rose-500/10 border border-rose-500/20 text-rose-400 text-xs">
                ⚠️ {errorMsg}
              </div>
            )}

            <form onSubmit={handleSubmit} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Tên chi phí</label>
                <input
                  type="text"
                  className="input"
                  placeholder="Ví dụ: Tiền mua cốc nhựa, đá bia..."
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                />
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Số tiền chi (VNĐ)</label>
                <input
                  type="number"
                  className="input"
                  value={amount === 0 ? '' : amount}
                  onChange={(e) => setAmount(Number(e.target.value))}
                />
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Hạng mục chi</label>
                <select
                  className="input"
                  value={category}
                  onChange={(e) => setCategory(e.target.value)}
                >
                  {EXPENSE_CATEGORIES.map(c => (
                    <option key={c.value} value={c.value}>{c.label}</option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Ghi chú thêm</label>
                <textarea
                  className="input min-h-[60px]"
                  placeholder="Ghi chú chi tiết mua cho mục đích gì..."
                  value={note}
                  onChange={(e) => setNote(e.target.value)}
                />
              </div>

              <div className="flex justify-end gap-3 pt-4 border-t border-slate-800">
                <button
                  type="button"
                  onClick={() => setModalOpen(false)}
                  className="btn btn-secondary text-xs"
                  disabled={submitting}
                >
                  Hủy
                </button>
                <button
                  type="submit"
                  className="btn btn-primary text-xs shadow-glow"
                  disabled={submitting}
                >
                  {submitting ? 'Đang lưu...' : 'Ghi nhận chi'}
                </button>
              </div>
            </form>
      </Modal>
    </div>
  );
}
