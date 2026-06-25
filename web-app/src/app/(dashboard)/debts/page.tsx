'use client';

import React, { useEffect, useState } from 'react';
import api from '@/lib/api';

interface DebtPayment {
  uuid: string;
  amount: number;
  note?: string;
  createdAt: string;
}

interface Debt {
  id: string;
  createdAt: string;
  type: number; // 0 = oweOthers (Tôi nợ), 1 = othersOweMe (Khách nợ)
  partyId: string;
  partyName: string;
  initialAmount: number;
  amount: number;
  description?: string;
  dueDate?: string;
  settled: boolean;
  payments: DebtPayment[];
}

export default function DebtsPage() {
  const [debts, setDebts] = useState<Debt[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [typeTab, setTypeTab] = useState<1 | 0>(1); // Default to "othersOweMe" (Khách nợ mình)

  // Payment Modal State
  const [paymentModalOpen, setPaymentModalOpen] = useState(false);
  const [selectedDebt, setSelectedDebt] = useState<Debt | null>(null);
  const [payAmount, setPayAmount] = useState<number>(0);
  const [payNote, setPayNote] = useState('');
  const [submittingPayment, setSubmittingPayment] = useState(false);

  // Standalone Debt Modal State
  const [addDebtModalOpen, setAddDebtModalOpen] = useState(false);
  const [partyName, setPartyName] = useState('');
  const [debtAmount, setDebtAmount] = useState(0);
  const [debtDesc, setDebtDesc] = useState('');
  const [dueDate, setDueDate] = useState('');
  const [submittingDebt, setSubmittingDebt] = useState(false);

  const fetchDebts = async () => {
    try {
      setLoading(true);
      const data = await api.getDebts();
      setDebts(data);
    } catch (err) {
      console.warn('Could not fetch debts, using demo data', err);
      // Demo debts
      setDebts([
        {
          id: 'debt-1',
          createdAt: new Date(Date.now() - 86400000 * 5).toISOString(),
          type: 1, // othersOweMe
          partyId: 'c-1',
          partyName: 'Chị Lan Chợ Lớn',
          initialAmount: 500000,
          amount: 320000, // Paid 180k
          description: 'Nợ mua cà phê sỉ ngày 20/06',
          dueDate: new Date(Date.now() + 86400000 * 5).toISOString(),
          settled: false,
          payments: [
            { uuid: 'p-1', amount: 180000, note: 'Trả trước tiền mặt', createdAt: new Date(Date.now() - 86400000 * 3).toISOString() }
          ]
        },
        {
          id: 'debt-2',
          createdAt: new Date(Date.now() - 86400000 * 2).toISOString(),
          type: 1, // othersOweMe
          partyId: 'c-2',
          partyName: 'Anh Hùng Đại Lý',
          initialAmount: 700000,
          amount: 700000,
          description: 'Nợ từ đơn hàng #F89E2',
          settled: false,
          payments: []
        },
        {
          id: 'debt-3',
          createdAt: new Date(Date.now() - 86400000 * 10).toISOString(),
          type: 0, // oweOthers
          partyId: 's-1',
          partyName: 'Hạt Cà Phê Trung Nguyên',
          initialAmount: 3000000,
          amount: 1500000, // Paid 1.5M
          description: 'Nợ tiền hàng cà phê robusta bao 50kg',
          dueDate: new Date(Date.now() - 86400000).toISOString(), // Quá hạn
          settled: false,
          payments: [
            { uuid: 'p-2', amount: 1500000, note: 'Chuyển khoản cọc', createdAt: new Date(Date.now() - 86400000 * 9).toISOString() }
          ]
        }
      ]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchDebts();
  }, []);

  const openPaymentModal = (d: Debt) => {
    setSelectedDebt(d);
    setPayAmount(d.amount);
    setPayNote('');
    setPaymentModalOpen(true);
  };

  const handlePaymentSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedDebt || payAmount <= 0) return;
    setSubmittingPayment(true);

    const paymentPayload = {
      amount: Number(payAmount),
      note: payNote || null,
      paymentType: 'CASH',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };

    try {
      try {
        await api.addDebtPayment(selectedDebt.id, paymentPayload);
      } catch (err) {
        console.warn('API error saving payment, applying local modification', err);
      }

      // Locally apply
      setDebts(debts.map(d => {
        if (d.id === selectedDebt.id) {
          const newAmount = Math.max(0, d.amount - payAmount);
          const mockPay: DebtPayment = {
            uuid: 'mock-pay-' + Math.random().toString(36).substr(2, 9),
            amount: payAmount,
            note: payNote,
            createdAt: new Date().toISOString()
          };
          return {
            ...d,
            amount: newAmount,
            settled: newAmount === 0,
            payments: [...d.payments, mockPay]
          };
        }
        return d;
      }));

      setPaymentModalOpen(false);
    } catch (err) {
      alert('Không thể thanh toán công nợ');
    } finally {
      setSubmittingPayment(false);
    }
  };

  const handleAddDebtSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!partyName.trim() || debtAmount <= 0) return;
    setSubmittingDebt(true);

    const newDebt: Debt = {
      id: 'mock-debt-' + Math.random().toString(36).substr(2, 9),
      createdAt: new Date().toISOString(),
      type: typeTab,
      partyId: 'custom-' + Math.random().toString(36).substr(2, 5),
      partyName: partyName,
      initialAmount: Number(debtAmount),
      amount: Number(debtAmount),
      description: debtDesc || undefined,
      dueDate: dueDate ? new Date(dueDate).toISOString() : undefined,
      settled: false,
      payments: []
    };

    // Normally would call api.createDebt, here we add locally
    setDebts([newDebt, ...debts]);
    setAddDebtModalOpen(false);
    setSubmittingDebt(false);
    
    // Clear Form
    setPartyName('');
    setDebtAmount(0);
    setDebtDesc('');
    setDueDate('');
  };

  const formatCurrency = (val: number) => {
    return new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(val);
  };

  const filteredDebts = debts.filter(d => {
    const matchesSearch = d.partyName.toLowerCase().includes(search.toLowerCase());
    const matchesTab = d.type === typeTab && !d.settled; // Only show active debts on tab
    return matchesSearch && matchesTab;
  });

  return (
    <div className="space-y-8 animate-fade-in-up">
      {/* Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h2 className="text-2xl font-bold text-white font-sans">Sổ ghi nợ</h2>
          <p className="text-sm text-slate-400">Theo dõi công nợ chi tiết của khách hàng & nhà cung cấp</p>
        </div>
        <button
          onClick={() => setAddDebtModalOpen(true)}
          className="btn btn-primary shadow-glow flex items-center gap-2"
        >
          ➕ Ghi nợ mới
        </button>
      </div>

      {/* Tab Filter and Search */}
      <div className="grid grid-cols-1 md:grid-cols-12 gap-4">
        {/* Search */}
        <div className="md:col-span-8 relative">
          <input
            type="text"
            className="input pl-10"
            placeholder="Tìm theo tên đối tác..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
          <span className="absolute left-3.5 top-3.5 text-slate-500">🔍</span>
        </div>

        {/* Tab Selection */}
        <div className="md:col-span-4 flex gap-2">
          <button
            onClick={() => setTypeTab(1)}
            className={`btn flex-1 text-xs font-semibold ${
              typeTab === 1
                ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30'
                : 'bg-slate-900 text-slate-400 border border-white/5'
            }`}
          >
            📉 Khách nợ tôi
          </button>
          <button
            onClick={() => setTypeTab(0)}
            className={`btn flex-1 text-xs font-semibold ${
              typeTab === 0
                ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30'
                : 'bg-slate-900 text-slate-400 border border-white/5'
            }`}
          >
            📈 Tôi nợ NCC
          </button>
        </div>
      </div>

      {/* Debts Table */}
      <div className="card bg-slate-900 border-white/5 overflow-hidden p-0">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm border-collapse">
            <thead>
              <tr className="border-b border-slate-800 text-slate-500 font-bold text-xs uppercase tracking-wider bg-slate-950/20">
                <th className="py-4 px-6">Ngày ghi nợ</th>
                <th className="py-4 px-6">Đối tác</th>
                <th className="py-4 px-6">Nội dung nợ</th>
                <th className="py-4 px-6 text-right">Tổng nợ ban đầu</th>
                <th className="py-4 px-6 text-right">Số nợ còn lại</th>
                <th className="py-4 px-6 text-center">Hạn thanh toán</th>
                <th className="py-4 px-6 text-right">Thao tác</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800 text-slate-300">
              {loading ? (
                <tr>
                  <td colSpan={7} className="py-8 text-center text-slate-500">
                    Đang tải danh sách công nợ...
                  </td>
                </tr>
              ) : filteredDebts.length === 0 ? (
                <tr>
                  <td colSpan={7} className="py-8 text-center text-slate-500">
                    Không có khoản nợ nào trong mục này
                  </td>
                </tr>
              ) : (
                filteredDebts.map((d) => {
                  const isOverdue = d.dueDate && new Date(d.dueDate) < new Date();
                  return (
                    <tr key={d.id} className="hover:bg-white/5 transition-colors">
                      <td className="py-4 px-6 text-slate-400 text-xs">
                        {new Date(d.createdAt).toLocaleDateString('vi-VN')}
                      </td>
                      <td className="py-4 px-6 font-semibold text-white">{d.partyName}</td>
                      <td className="py-4 px-6 text-slate-400 text-xs max-w-xs truncate">{d.description || '-'}</td>
                      <td className="py-4 px-6 text-right font-medium">{formatCurrency(d.initialAmount)}</td>
                      <td className="py-4 px-6 text-right font-bold text-amber-500">{formatCurrency(d.amount)}</td>
                      <td className="py-4 px-6 text-center">
                        {d.dueDate ? (
                          <span className={`px-2 py-0.5 rounded text-[10px] font-bold ${
                            isOverdue ? 'bg-rose-500/10 text-rose-400 shadow-[0_0_8px_rgba(239,68,68,0.2)]' : 'bg-slate-800 text-slate-400'
                          }`}>
                            {new Date(d.dueDate).toLocaleDateString('vi-VN')} {isOverdue && '(Quá hạn)'}
                          </span>
                        ) : (
                          <span className="text-slate-500 text-xs">-</span>
                        )}
                      </td>
                      <td className="py-4 px-6 text-right">
                        <button
                          onClick={() => openPaymentModal(d)}
                          className="text-indigo-400 hover:text-indigo-300 text-xs font-semibold"
                        >
                          Trả nợ
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

      {/* Pay Debt Modal */}
      {paymentModalOpen && selectedDebt && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in">
          <div className="glass w-full max-w-md rounded-2xl border border-white/10 shadow-2xl p-6 relative animate-fade-in-up">
            <div className="flex justify-between items-center mb-6">
              <h3 className="text-xl font-bold text-white">Thanh toán công nợ</h3>
              <button onClick={() => setPaymentModalOpen(false)} className="text-slate-400 hover:text-white text-lg">✕</button>
            </div>

            <form onSubmit={handlePaymentSubmit} className="space-y-4">
              <div className="bg-slate-950/40 p-4 rounded-xl space-y-2 text-sm border border-white/5">
                <div className="flex justify-between text-slate-400">
                  <span>Đối tác nợ:</span>
                  <span className="text-white font-semibold">{selectedDebt.partyName}</span>
                </div>
                <div className="flex justify-between text-slate-400">
                  <span>Số nợ hiện tại:</span>
                  <span className="text-amber-500 font-bold">{formatCurrency(selectedDebt.amount)}</span>
                </div>
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Số tiền thanh toán (VNĐ)</label>
                <input
                  type="number"
                  className="input font-bold"
                  value={payAmount === 0 ? '' : payAmount}
                  onChange={(e) => setPayAmount(Math.min(selectedDebt.amount, Number(e.target.value)))}
                />
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Ghi chú thanh toán</label>
                <input
                  type="text"
                  className="input"
                  placeholder="Ví dụ: Trả đợt 1..."
                  value={payNote}
                  onChange={(e) => setPayNote(e.target.value)}
                />
              </div>

              <div className="flex justify-end gap-3 pt-4 border-t border-slate-800">
                <button
                  type="button"
                  onClick={() => setPaymentModalOpen(false)}
                  className="btn btn-secondary text-xs"
                  disabled={submittingPayment}
                >
                  Hủy
                </button>
                <button
                  type="submit"
                  className="btn btn-primary text-xs shadow-glow"
                  disabled={submittingPayment}
                >
                  {submittingPayment ? 'Đang lưu...' : 'Thanh toán'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Add Standalone Debt Modal */}
      {addDebtModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in">
          <div className="glass w-full max-w-md rounded-2xl border border-white/10 shadow-2xl p-6 relative animate-fade-in-up">
            <div className="flex justify-between items-center mb-6">
              <h3 className="text-xl font-bold text-white">Ghi nhận khoản nợ mới</h3>
              <button onClick={() => setAddDebtModalOpen(false)} className="text-slate-400 hover:text-white text-lg">✕</button>
            </div>

            <form onSubmit={handleAddDebtSubmit} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Tên đối tác ghi nợ</label>
                <input
                  type="text"
                  className="input"
                  placeholder="Nhập tên đối tác..."
                  value={partyName}
                  onChange={(e) => setPartyName(e.target.value)}
                />
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Số tiền nợ (VNĐ)</label>
                <input
                  type="number"
                  className="input"
                  value={debtAmount === 0 ? '' : debtAmount}
                  onChange={(e) => setDebtAmount(Number(e.target.value))}
                />
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Nội dung / Mô tả nợ</label>
                <input
                  type="text"
                  className="input"
                  placeholder="Ví dụ: Nợ mua đá bia..."
                  value={debtDesc}
                  onChange={(e) => setDebtDesc(e.target.value)}
                />
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Hạn trả nợ (nếu có)</label>
                <input
                  type="date"
                  className="input text-xs"
                  value={dueDate}
                  onChange={(e) => setDueDate(e.target.value)}
                />
              </div>

              <div className="flex justify-end gap-3 pt-4 border-t border-slate-800">
                <button
                  type="button"
                  onClick={() => setAddDebtModalOpen(false)}
                  className="btn btn-secondary text-xs"
                  disabled={submittingDebt}
                >
                  Hủy
                </button>
                <button
                  type="submit"
                  className="btn btn-primary text-xs shadow-glow"
                  disabled={submittingDebt}
                >
                  {submittingDebt ? 'Đang tạo...' : 'Ghi nợ'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
