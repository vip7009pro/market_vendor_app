'use client';

import React, { useEffect, useMemo, useState } from 'react';
import { GridColDef, GridRowParams } from '@mui/x-data-grid';
import api from '@/lib/api';
import Modal from '@/components/ui/Modal';
import AppDataGrid, { toRowSelectionModel } from '@/components/ui/AppDataGrid';
import MasterDetailLayout from '@/components/ui/MasterDetailLayout';
import { formatCurrency, formatDateTime } from '@/lib/format';
import { matchVietnamese } from '@/lib/text';

interface DebtPayment {
  uuid: string;
  amount: number;
  note?: string;
  paymentType?: string;
  createdAt: string;
}

interface Debt {
  id: string;
  createdAt: string;
  type: number;
  partyId: string;
  partyName: string;
  initialAmount: number;
  amount: number;
  description?: string;
  dueDate?: string;
  settled: boolean;
  sourceType?: string;
  sourceId?: string;
  payments: DebtPayment[];
}

function normalizeDebt(raw: any): Debt {
  const payments = (raw.payments || []).map((p: any) => ({
    uuid: p.uuid,
    amount: Number(p.amount),
    note: p.note,
    paymentType: p.paymentType,
    createdAt: p.createdAt,
  }));
  return {
    id: raw.id,
    createdAt: raw.createdAt,
    type: Number(raw.type),
    partyId: raw.partyId,
    partyName: raw.partyName,
    initialAmount: Number(raw.initialAmount),
    amount: Number(raw.amount),
    description: raw.description,
    dueDate: raw.dueDate,
    settled: Boolean(raw.settled),
    sourceType: raw.sourceType,
    sourceId: raw.sourceId,
    payments,
  };
}

export default function DebtsPage() {
  const [debts, setDebts] = useState<Debt[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [typeTab, setTypeTab] = useState<1 | 0>(1);
  const [selectedDebt, setSelectedDebt] = useState<Debt | null>(null);
  const [linkedOrderDetails, setLinkedOrderDetails] = useState<any | null>(null);
  const [loadingLinkedOrder, setLoadingLinkedOrder] = useState(false);

  const [paymentModalOpen, setPaymentModalOpen] = useState(false);
  const [payAmount, setPayAmount] = useState(0);
  const [payNote, setPayNote] = useState('');
  const [submittingPayment, setSubmittingPayment] = useState(false);

  const [addDebtModalOpen, setAddDebtModalOpen] = useState(false);
  const [partyName, setPartyName] = useState('');
  const [debtAmount, setDebtAmount] = useState(0);
  const [debtDesc, setDebtDesc] = useState('');
  const [dueDate, setDueDate] = useState('');
  const [submittingDebt, setSubmittingDebt] = useState(false);

  const [linkModalOpen, setLinkModalOpen] = useState(false);
  const [linkSourceType, setLinkSourceType] = useState<'sale' | 'purchase'>('sale');
  const [linkSourceId, setLinkSourceId] = useState('');
  const [linkOptions, setLinkOptions] = useState<Array<{ id: string; label: string }>>([]);
  const [submittingLink, setSubmittingLink] = useState(false);

  const fetchDebts = async () => {
    try {
      setLoading(true);
      const data = await api.getDebts();
      setDebts((Array.isArray(data) ? data : []).map(normalizeDebt));
    } catch (err) {
      console.warn('Could not fetch debts', err);
      setDebts([]);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchDebts();
  }, []);

  useEffect(() => {
    if (selectedDebt && selectedDebt.sourceId && selectedDebt.sourceType) {
      const sourceId = selectedDebt.sourceId;
      const sourceType = selectedDebt.sourceType;
      const fetchLinkedOrder = async () => {
        try {
          setLoadingLinkedOrder(true);
          setLinkedOrderDetails(null);
          if (sourceType === 'sale') {
            const sale = await api.getSaleById(sourceId);
            setLinkedOrderDetails({ ...sale, _orderType: 'sale' });
          } else if (sourceType === 'purchase') {
            const purchase = await api.getPurchaseById(sourceId);
            setLinkedOrderDetails({ ...purchase, _orderType: 'purchase' });
          }
        } catch (err) {
          console.error('Error loading linked order details:', err);
          setLinkedOrderDetails(null);
        } finally {
          setLoadingLinkedOrder(false);
        }
      };
      fetchLinkedOrder();
    } else {
      setLinkedOrderDetails(null);
    }
  }, [selectedDebt]);

  const filteredDebts = useMemo(() => {
    return debts.filter((d) => {
      const matchesSearch =
        matchVietnamese(d.partyName, search) ||
        matchVietnamese(d.description || '', search) ||
        matchVietnamese(d.sourceId || '', search);
      return matchesSearch && d.type === typeTab && !d.settled;
    });
  }, [debts, search, typeTab]);

  const rows = useMemo(() => filteredDebts.map((d) => {
    const paid = Math.max(0, d.initialAmount - d.amount);
    return {
      id: d.id,
      createdAt: d.createdAt,
      partyName: d.partyName,
      description: d.description || '—',
      initialAmount: d.initialAmount,
      paidAmount: paid,
      remainingAmount: d.amount,
      dueDate: d.dueDate,
      sourceType: d.sourceType,
      sourceId: d.sourceId,
    };
  }), [filteredDebts]);

  const columns: GridColDef[] = [
    { field: 'createdAt', headerName: 'Ngày ghi', width: 110, valueFormatter: (v) => new Date(v).toLocaleDateString('vi-VN') },
    { field: 'partyName', headerName: 'Đối tác', flex: 1, minWidth: 140 },
    { field: 'description', headerName: 'Nội dung', flex: 1, minWidth: 160 },
    { field: 'initialAmount', headerName: 'Nợ ban đầu', width: 120, type: 'number', align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
    { field: 'paidAmount', headerName: 'Đã trả', width: 110, type: 'number', align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
    { field: 'remainingAmount', headerName: 'Còn lại', width: 110, type: 'number', align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
    {
      field: 'sourceId',
      headerName: 'Liên kết',
      width: 100,
      valueGetter: (_v, row) => row.sourceId ? `#${String(row.sourceId).slice(-6).toUpperCase()}` : '—',
    },
  ];

  const onRowClick = (params: GridRowParams) => {
    const d = debts.find((x) => x.id === params.id);
    if (d) setSelectedDebt(d);
  };

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
    try {
      const updated = await api.addDebtPayment(selectedDebt.id, {
        amount: Number(payAmount),
        note: payNote || null,
        paymentType: 'CASH',
      });
      const normalized = normalizeDebt(updated);
      setDebts(debts.map((d) => (d.id === normalized.id ? normalized : d)));
      setSelectedDebt(normalized);
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
    try {
      const created = await api.createDebt({
        type: typeTab,
        partyId: 'manual-' + Date.now(),
        partyName: partyName.trim(),
        amount: Number(debtAmount),
        description: debtDesc || null,
        dueDate: dueDate || null,
      });
      const normalized = normalizeDebt(created);
      setDebts([normalized, ...debts]);
      setSelectedDebt(normalized);
      setAddDebtModalOpen(false);
      setPartyName('');
      setDebtAmount(0);
      setDebtDesc('');
      setDueDate('');
    } catch {
      alert('Không thể tạo công nợ');
    } finally {
      setSubmittingDebt(false);
    }
  };

  const openLinkModal = async (d: Debt) => {
    setSelectedDebt(d);
    const st = d.type === 1 ? 'sale' : 'purchase';
    setLinkSourceType(st);
    setLinkSourceId(d.sourceId || '');
    setLinkModalOpen(true);
    try {
      if (st === 'sale') {
        const sales = await api.getSales();
        setLinkOptions((sales || []).slice(0, 100).map((s: any) => ({
          id: s.id,
          label: `${new Date(s.createdAt).toLocaleDateString('vi-VN')} — ${s.customerName} (#${s.id.slice(-6).toUpperCase()})`,
        })));
      } else {
        const orders = await api.getPurchases();
        setLinkOptions((orders || []).slice(0, 100).map((o: any) => ({
          id: o.id,
          label: `${new Date(o.createdAt).toLocaleDateString('vi-VN')} — ${o.supplierName} (#${o.id.slice(-6).toUpperCase()})`,
        })));
      }
    } catch {
      setLinkOptions([]);
    }
  };

  const handleLinkSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!selectedDebt || !linkSourceId) return;
    setSubmittingLink(true);
    try {
      const updated = await api.updateDebt(selectedDebt.id, {
        sourceType: linkSourceType,
        sourceId: linkSourceId,
      });
      const fresh = await api.getDebt(selectedDebt.id).catch(() => updated);
      const normalized = normalizeDebt({ ...selectedDebt, ...fresh, payments: fresh.payments ?? selectedDebt.payments });
      setDebts(debts.map((d) => (d.id === normalized.id ? normalized : d)));
      setSelectedDebt(normalized);
      setLinkModalOpen(false);
    } catch {
      alert('Không thể gán giao dịch');
    } finally {
      setSubmittingLink(false);
    }
  };

  const paidTotal = selectedDebt ? Math.max(0, selectedDebt.initialAmount - selectedDebt.amount) : 0;

  return (
    <div className="space-y-6 animate-fade-in-up">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div>
          <h2 className="text-2xl font-bold text-white">Sổ ghi nợ</h2>
          <p className="text-sm text-slate-400">Theo dõi công nợ, lịch sử trả nợ và gán đơn hàng</p>
        </div>
        <button onClick={() => setAddDebtModalOpen(true)} className="btn btn-primary shadow-glow">➕ Ghi nợ mới</button>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-12 gap-4">
        <div className="md:col-span-8 relative">
          <input className="input pl-10" placeholder="Tìm theo tên đối tác, nội dung, mã đơn..." value={search} onChange={(e) => setSearch(e.target.value)} />
          <span className="absolute left-3.5 top-3.5 text-slate-500">🔍</span>
        </div>
        <div className="md:col-span-4 flex gap-2">
          <button onClick={() => setTypeTab(1)} className={`btn flex-1 text-xs font-semibold ${typeTab === 1 ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30' : 'bg-slate-900 text-slate-400 border border-white/5'}`}>📉 Khách nợ tôi</button>
          <button onClick={() => setTypeTab(0)} className={`btn flex-1 text-xs font-semibold ${typeTab === 0 ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/30' : 'bg-slate-900 text-slate-400 border border-white/5'}`}>📈 Tôi nợ NCC</button>
        </div>
      </div>

      <MasterDetailLayout
        detailTitle={selectedDebt ? `Chi tiết — ${selectedDebt.partyName}` : 'Chi tiết công nợ'}
        showDetail={!!selectedDebt}
        list={
          <AppDataGrid
            rows={rows}
            columns={columns}
            loading={loading}
            height="100%"
            onRowClick={onRowClick}
            rowSelectionModel={toRowSelectionModel(selectedDebt ? [selectedDebt.id] : [])}
          />
        }
        detail={selectedDebt && (
          <div className="space-y-5 text-sm">
            <div className="grid grid-cols-2 gap-3 text-xs">
              <div className="bg-slate-950/40 p-3 rounded-xl border border-white/5">
                <p className="text-slate-500">Nợ ban đầu</p>
                <p className="font-bold text-white mt-1">{formatCurrency(selectedDebt.initialAmount)}</p>
              </div>
              <div className="bg-slate-950/40 p-3 rounded-xl border border-white/5">
                <p className="text-slate-500">Đã trả</p>
                <p className="font-bold text-emerald-400 mt-1">{formatCurrency(paidTotal)}</p>
              </div>
              <div className="bg-slate-950/40 p-3 rounded-xl border border-white/5">
                <p className="text-slate-500">Còn lại</p>
                <p className="font-bold text-amber-400 mt-1">{formatCurrency(selectedDebt.amount)}</p>
              </div>
              <div className="bg-slate-950/40 p-3 rounded-xl border border-white/5">
                <p className="text-slate-500">Hạn trả</p>
                <p className="font-bold text-white mt-1">{selectedDebt.dueDate ? new Date(selectedDebt.dueDate).toLocaleDateString('vi-VN') : '—'}</p>
              </div>
            </div>

            {selectedDebt.description && (
              <p className="text-xs text-slate-400"><span className="text-slate-500">Mô tả:</span> {selectedDebt.description}</p>
            )}

            <div className="text-xs text-slate-400">
              <span className="text-slate-500">Liên kết:</span>{' '}
              {selectedDebt.sourceId
                ? `${selectedDebt.sourceType === 'sale' ? 'Bán hàng' : selectedDebt.sourceType === 'purchase' ? 'Nhập hàng' : selectedDebt.sourceType} #${selectedDebt.sourceId.slice(-6).toUpperCase()}`
                : 'Chưa gán đơn'}
            </div>

            <div className="flex flex-wrap gap-2">
              <button onClick={() => openPaymentModal(selectedDebt)} className="btn btn-primary text-xs" disabled={selectedDebt.amount <= 0}>Trả nợ</button>
              <button onClick={() => openLinkModal(selectedDebt)} className="btn btn-secondary text-xs">Gán đơn hàng</button>
            </div>

            {/* Linked order details */}
            {loadingLinkedOrder && (
              <div className="text-xs text-slate-500 italic">Đang tải thông tin đơn hàng liên kết...</div>
            )}
            
            {!loadingLinkedOrder && linkedOrderDetails && (
              <div className="bg-slate-950/20 border border-white/5 rounded-xl p-3.5 space-y-3">
                <div className="flex justify-between items-center pb-2 border-b border-white/5">
                  <h4 className="text-[11px] font-bold text-slate-400 uppercase tracking-wider">
                    {linkedOrderDetails._orderType === 'sale' ? '🛒 Chi tiết Đơn Bán Hàng' : '📦 Chi tiết Đơn Nhập Hàng'}
                  </h4>
                  <span className="text-[10px] bg-indigo-500/10 text-indigo-400 font-bold px-2 py-0.5 rounded">
                    #{linkedOrderDetails.id.slice(-6).toUpperCase()}
                  </span>
                </div>
                
                <div className="space-y-1.5 max-h-32 overflow-y-auto pr-1">
                  {(linkedOrderDetails.items || []).map((it: any, idx: number) => {
                    const price = Number(it.unitPrice || it.unitCost || 0);
                    const qty = Number(it.quantity || 0);
                    return (
                      <div key={idx} className="flex justify-between items-center text-xs">
                        <span className="text-slate-300 truncate max-w-[160px]">{it.name || it.productName}</span>
                        <span className="text-slate-500 text-[10px]">{qty} x {it.unit || 'cái'}</span>
                        <span className="text-slate-300 font-medium">{formatCurrency(price * qty)}</span>
                      </div>
                    );
                  })}
                </div>
                
                <div className="pt-2 border-t border-white/5 text-[11px] space-y-1 text-slate-400">
                  <div className="flex justify-between">
                    <span>Tổng tiền đơn:</span>
                    <span className="text-white font-semibold">
                      {formatCurrency(Number(linkedOrderDetails.total || (linkedOrderDetails.items || []).reduce((sum: number, it: any) => sum + (Number(it.unitPrice || it.unitCost || 0) * Number(it.quantity || 0)), 0)) - Number(linkedOrderDetails.discount || 0))}
                    </span>
                  </div>
                  <div className="flex justify-between">
                    <span>Đã trả lúc mua:</span>
                    <span className="text-emerald-400 font-medium">{formatCurrency(Number(linkedOrderDetails.paidAmount || 0))}</span>
                  </div>
                </div>
              </div>
            )}

            <div>
              <h4 className="text-xs font-bold text-slate-500 uppercase tracking-wider mb-2">Lịch sử thanh toán ({selectedDebt.payments.length})</h4>
              {selectedDebt.payments.length === 0 ? (
                <p className="text-xs text-slate-500 italic">Chưa có lần trả nợ nào</p>
              ) : (
                <div className="space-y-2 max-h-64 overflow-y-auto">
                  {selectedDebt.payments.map((p) => (
                    <div key={p.uuid} className="flex justify-between items-start p-2.5 bg-slate-950/30 rounded-lg border border-white/5 text-xs">
                      <div>
                        <p className="font-semibold text-emerald-400">{formatCurrency(p.amount)}</p>
                        <p className="text-slate-500 mt-0.5">{formatDateTime(p.createdAt)}</p>
                        {p.note && <p className="text-slate-400 mt-1">{p.note}</p>}
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        )}
      />

      <Modal open={paymentModalOpen && !!selectedDebt} onClose={() => setPaymentModalOpen(false)} title="Thanh toán công nợ" maxWidth="max-w-md">
        {selectedDebt && (
          <form onSubmit={handlePaymentSubmit} className="space-y-4">
            <div className="bg-slate-950/40 p-4 rounded-xl space-y-2 text-sm border border-white/5">
              <div className="flex justify-between text-slate-400"><span>Đối tác:</span><span className="text-white font-semibold">{selectedDebt.partyName}</span></div>
              <div className="flex justify-between text-slate-400"><span>Còn nợ:</span><span className="text-amber-500 font-bold">{formatCurrency(selectedDebt.amount)}</span></div>
            </div>
            <div>
              <label className="block text-xs font-bold text-slate-400 uppercase mb-2">Số tiền thanh toán</label>
              <input type="number" className="input font-bold" value={payAmount || ''} onChange={(e) => setPayAmount(Math.min(selectedDebt.amount, Number(e.target.value)))} />
            </div>
            <div>
              <label className="block text-xs font-bold text-slate-400 uppercase mb-2">Ghi chú</label>
              <input type="text" className="input" value={payNote} onChange={(e) => setPayNote(e.target.value)} />
            </div>
            <div className="flex justify-end gap-3 pt-4 border-t border-slate-800">
              <button type="button" onClick={() => setPaymentModalOpen(false)} className="btn btn-secondary text-xs">Hủy</button>
              <button type="submit" className="btn btn-primary text-xs" disabled={submittingPayment}>{submittingPayment ? 'Đang lưu...' : 'Thanh toán'}</button>
            </div>
          </form>
        )}
      </Modal>

      <Modal open={addDebtModalOpen} onClose={() => setAddDebtModalOpen(false)} title="Ghi nhận khoản nợ mới" maxWidth="max-w-md">
        <form onSubmit={handleAddDebtSubmit} className="space-y-4">
          <div>
            <label className="block text-xs font-bold text-slate-400 uppercase mb-2">Tên đối tác</label>
            <input className="input" value={partyName} onChange={(e) => setPartyName(e.target.value)} />
          </div>
          <div>
            <label className="block text-xs font-bold text-slate-400 uppercase mb-2">Số tiền nợ</label>
            <input type="number" className="input" value={debtAmount || ''} onChange={(e) => setDebtAmount(Number(e.target.value))} />
          </div>
          <div>
            <label className="block text-xs font-bold text-slate-400 uppercase mb-2">Mô tả</label>
            <input className="input" value={debtDesc} onChange={(e) => setDebtDesc(e.target.value)} />
          </div>
          <div>
            <label className="block text-xs font-bold text-slate-400 uppercase mb-2">Hạn trả</label>
            <input type="date" className="input text-xs" value={dueDate} onChange={(e) => setDueDate(e.target.value)} />
          </div>
          <div className="flex justify-end gap-3 pt-4 border-t border-slate-800">
            <button type="button" onClick={() => setAddDebtModalOpen(false)} className="btn btn-secondary text-xs">Hủy</button>
            <button type="submit" className="btn btn-primary text-xs" disabled={submittingDebt}>Ghi nợ</button>
          </div>
        </form>
      </Modal>

      <Modal open={linkModalOpen && !!selectedDebt} onClose={() => setLinkModalOpen(false)} title="Gán giao dịch cho công nợ" maxWidth="max-w-md">
        {selectedDebt && (
          <form onSubmit={handleLinkSubmit} className="space-y-4">
            <p className="text-xs text-slate-400">
              Gán {selectedDebt.type === 1 ? 'hóa đơn bán' : 'phiếu nhập'} cho khoản nợ của <strong className="text-white">{selectedDebt.partyName}</strong>
            </p>
            <div>
              <label className="block text-xs font-bold text-slate-400 uppercase mb-2">Chọn giao dịch</label>
              <select className="input text-xs" value={linkSourceId} onChange={(e) => setLinkSourceId(e.target.value)} required>
                <option value="">-- Chọn --</option>
                {linkOptions.map((o) => (
                  <option key={o.id} value={o.id}>{o.label}</option>
                ))}
              </select>
            </div>
            <div className="flex justify-end gap-3 pt-4 border-t border-slate-800">
              <button type="button" onClick={() => setLinkModalOpen(false)} className="btn btn-secondary text-xs">Hủy</button>
              <button type="submit" className="btn btn-primary text-xs" disabled={submittingLink || !linkSourceId}>Gán đơn</button>
            </div>
          </form>
        )}
      </Modal>
    </div>
  );
}
