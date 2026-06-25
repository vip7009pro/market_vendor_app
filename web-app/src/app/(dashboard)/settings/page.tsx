'use client';

import React, { useState, useEffect } from 'react';
import api from '@/lib/api';

interface Employee {
  id: string;
  name: string;
}

interface BankAccount {
  id: string;
  name: string;
  accountNo: string;
  accountName: string;
  isDefault: boolean;
}

export default function SettingsPage() {
  const [activeTab, setActiveTab] = useState<'STORE' | 'BANK' | 'EMPLOYEE' | 'AI'>('STORE');

  // Store Settings State
  const [storeName, setStoreName] = useState('');
  const [storePhone, setStorePhone] = useState('');
  const [storeAddress, setStoreAddress] = useState('');
  const [storeSaveSuccess, setStoreSaveSuccess] = useState(false);

  // Bank Accounts Settings State
  const [banks, setBanks] = useState<BankAccount[]>([]);
  const [bankModalOpen, setBankModalOpen] = useState(false);
  const [bankName, setBankName] = useState('Vietcombank');
  const [accountNo, setAccountNo] = useState('');
  const [accountName, setAccountName] = useState('');

  // Employees Settings State
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [empModalOpen, setEmpModalOpen] = useState(false);
  const [empName, setEmpName] = useState('');

  // AI Settings State
  const [aiProvider, setAiProvider] = useState<'google' | 'openrouter'>('google');
  const [aiModel, setAiModel] = useState('models/gemini-1.5-flash');
  const [googleKey, setGoogleKey] = useState('');
  const [openrouterKey, setOpenrouterKey] = useState('');
  const [aiSaveSuccess, setAiSaveSuccess] = useState(false);

  // Common State
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  // Load data based on active tab
  useEffect(() => {
    fetchData();
  }, [activeTab]);

  useEffect(() => {
    // Load AI settings from localStorage on client mount
    if (typeof window !== 'undefined') {
      const provider = localStorage.getItem('ai_provider') as 'google' | 'openrouter' || 'google';
      setAiProvider(provider);
      setAiModel(localStorage.getItem('ai_model') || (provider === 'google' ? 'models/gemini-1.5-flash' : 'google/gemma-3-27b-it:free'));
      setGoogleKey(localStorage.getItem('ai_api_key_google') || '');
      setOpenrouterKey(localStorage.getItem('ai_api_key_openrouter') || '');
    }
  }, []);

  const fetchData = async () => {
    if (activeTab === 'AI') return;
    setLoading(true);
    setError('');
    try {
      if (activeTab === 'STORE') {
        const store = await api.getStoreInfo();
        if (store) {
          setStoreName(store.name || '');
          setStorePhone(store.phone || '');
          setStoreAddress(store.address || '');
        }
      } else if (activeTab === 'BANK') {
        const bankData = await api.getBankAccounts();
        setBanks(bankData || []);
      } else if (activeTab === 'EMPLOYEE') {
        const empData = await api.getEmployees();
        setEmployees(empData || []);
      }
    } catch (err: any) {
      console.error('Failed to fetch settings:', err);
      setError('Không thể kết nối với API backend. Vui lòng kiểm tra lại server.');
    } finally {
      setLoading(false);
    }
  };

  const handleSaveStore = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!storeName.trim() || !storePhone.trim() || !storeAddress.trim()) {
      setError('Vui lòng nhập đầy đủ thông tin bắt buộc (Tên, SĐT, Địa chỉ)');
      return;
    }
    setError('');
    try {
      await api.updateStoreInfo({
        name: storeName,
        phone: storePhone,
        address: storeAddress,
      });
      setStoreSaveSuccess(true);
      setTimeout(() => setStoreSaveSuccess(false), 3000);
    } catch (err: any) {
      setError('Lưu thông tin cửa hàng thất bại: ' + err.message);
    }
  };

  const handleAddBank = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!accountNo.trim() || !accountName.trim()) return;

    try {
      await api.createBankAccount({
        name: bankName,
        shortName: bankName,
        accountNo,
        accountName: accountName.toUpperCase(),
        isDefault: banks.length === 0,
      });
      setBankModalOpen(false);
      setAccountNo('');
      setAccountName('');
      fetchData();
    } catch (err: any) {
      alert('Thêm tài khoản ngân hàng thất bại: ' + err.message);
    }
  };

  const handleDeleteBank = async (id: string) => {
    if (!confirm('Bạn có chắc chắn muốn xóa tài khoản ngân hàng này?')) return;
    try {
      await api.deleteBankAccount(id);
      fetchData();
    } catch (err: any) {
      alert('Xóa tài khoản ngân hàng thất bại: ' + err.message);
    }
  };

  const handleAddEmployee = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!empName.trim()) return;

    try {
      await api.createEmployee({
        name: empName,
      });
      setEmpModalOpen(false);
      setEmpName('');
      fetchData();
    } catch (err: any) {
      alert('Thêm nhân viên thất bại: ' + err.message);
    }
  };

  const handleDeleteEmployee = async (id: string) => {
    if (!confirm('Bạn có chắc chắn muốn xóa nhân viên này?')) return;
    try {
      await api.deleteEmployee(id);
      fetchData();
    } catch (err: any) {
      alert('Xóa nhân viên thất bại: ' + err.message);
    }
  };

  const handleSaveAiSettings = (e: React.FormEvent) => {
    e.preventDefault();
    localStorage.setItem('ai_provider', aiProvider);
    localStorage.setItem('ai_model', aiModel);
    localStorage.setItem('ai_api_key_google', googleKey);
    localStorage.setItem('ai_api_key_openrouter', openrouterKey);
    setAiSaveSuccess(true);
    setTimeout(() => setAiSaveSuccess(false), 3000);
  };

  return (
    <div className="space-y-8 animate-fade-in-up">
      {/* Header */}
      <div>
        <h2 className="text-2xl font-bold text-white font-sans">Cấu hình hệ thống</h2>
        <p className="text-sm text-slate-400">Thiết lập thông tin cửa hàng, tài khoản ngân hàng VietQR, danh sách nhân viên và cấu hình AI</p>
      </div>

      {/* Error alert */}
      {error && (
        <div className="p-4 rounded-xl bg-rose-500/10 border border-rose-500/20 text-rose-400 text-sm">
          ⚠️ {error}
        </div>
      )}

      {/* Tabs */}
      <div className="flex border-b border-slate-800">
        <button
          onClick={() => setActiveTab('STORE')}
          className={`px-6 py-3 font-semibold text-sm border-b-2 transition-all cursor-pointer ${
            activeTab === 'STORE'
              ? 'border-indigo-500 text-indigo-300'
              : 'border-transparent text-slate-400 hover:text-slate-200'
          }`}
        >
          🏪 Thông tin cửa hàng
        </button>
        <button
          onClick={() => setActiveTab('BANK')}
          className={`px-6 py-3 font-semibold text-sm border-b-2 transition-all cursor-pointer ${
            activeTab === 'BANK'
              ? 'border-indigo-500 text-indigo-300'
              : 'border-transparent text-slate-400 hover:text-slate-200'
          }`}
        >
          🏦 Tài khoản VietQR
        </button>
        <button
          onClick={() => setActiveTab('EMPLOYEE')}
          className={`px-6 py-3 font-semibold text-sm border-b-2 transition-all cursor-pointer ${
            activeTab === 'EMPLOYEE'
              ? 'border-indigo-500 text-indigo-300'
              : 'border-transparent text-slate-400 hover:text-slate-200'
          }`}
        >
          👥 Quản lý nhân viên
        </button>
        <button
          onClick={() => setActiveTab('AI')}
          className={`px-6 py-3 font-semibold text-sm border-b-2 transition-all cursor-pointer ${
            activeTab === 'AI'
              ? 'border-indigo-500 text-indigo-300'
              : 'border-transparent text-slate-400 hover:text-slate-200'
          }`}
        >
          🤖 Cấu hình AI
        </button>
      </div>

      {/* Content panel */}
      <div className="card bg-slate-900 border-white/5 p-6 min-h-[300px] relative">
        {loading && (
          <div className="absolute inset-0 bg-slate-900/60 backdrop-blur-xs flex items-center justify-center z-10 rounded-2xl">
            <span className="text-indigo-400 animate-pulse font-semibold">Đang tải dữ liệu...</span>
          </div>
        )}

        {activeTab === 'STORE' && (
          <form onSubmit={handleSaveStore} className="space-y-5 max-w-xl">
            {storeSaveSuccess && (
              <div className="p-3 rounded bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-xs">
                ✓ Lưu thông tin cửa hàng thành công!
              </div>
            )}
            
            <div>
              <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Tên cửa hàng *</label>
              <input
                type="text"
                className="input"
                required
                value={storeName}
                onChange={(e) => setStoreName(e.target.value)}
                placeholder="Nhập tên cửa hàng..."
              />
            </div>

            <div>
              <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Số điện thoại liên hệ *</label>
              <input
                type="text"
                className="input font-mono"
                required
                value={storePhone}
                onChange={(e) => setStorePhone(e.target.value)}
                placeholder="Nhập số điện thoại..."
              />
            </div>

            <div>
              <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Địa chỉ cửa hàng *</label>
              <input
                type="text"
                className="input"
                required
                value={storeAddress}
                onChange={(e) => setStoreAddress(e.target.value)}
                placeholder="Nhập địa chỉ cửa hàng..."
              />
            </div>

            <button type="submit" className="btn btn-primary text-xs shadow-glow cursor-pointer">
              Lưu thay đổi
            </button>
          </form>
        )}

        {activeTab === 'BANK' && (
          <div className="space-y-6">
            <div className="flex justify-between items-center">
              <h3 className="font-bold text-white text-base">Tài khoản thanh toán VietQR</h3>
              <button onClick={() => setBankModalOpen(true)} className="btn btn-primary text-xs shadow-glow cursor-pointer">
                ➕ Thêm tài khoản
              </button>
            </div>

            {banks.length === 0 ? (
              <div className="text-center py-12 text-slate-500">
                Chưa có tài khoản ngân hàng nào được thiết lập. Hãy thêm mới để tích hợp hiển thị mã QR thanh toán nhanh khi bán hàng POS.
              </div>
            ) : (
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
                {banks.map((b) => (
                  <div key={b.id} className="card bg-slate-950/40 border-white/5 relative p-5 flex flex-col justify-between group">
                    {b.isDefault && (
                      <span className="absolute top-4 right-4 bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 px-2 py-0.5 rounded text-[9px] font-bold uppercase tracking-wider">
                        Mặc định
                      </span>
                    )}
                    
                    <div className="space-y-2">
                      <p className="text-xs font-bold text-indigo-400 uppercase tracking-widest">{b.name}</p>
                      <p className="text-lg font-bold text-white font-mono">{b.accountNo}</p>
                      <p className="text-xs text-slate-300 font-semibold">{b.accountName}</p>
                    </div>

                    <div className="flex justify-end items-center mt-5 pt-3 border-t border-slate-800 text-xs">
                      <button
                        onClick={() => handleDeleteBank(b.id)}
                        className="text-rose-400 hover:text-rose-300 font-semibold cursor-pointer"
                      >
                        Xóa tài khoản
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {activeTab === 'EMPLOYEE' && (
          <div className="space-y-6">
            <div className="flex justify-between items-center">
              <h3 className="font-bold text-white text-base">Quản lý nhân viên</h3>
              <button onClick={() => setEmpModalOpen(true)} className="btn btn-primary text-xs shadow-glow cursor-pointer">
                ➕ Thêm nhân viên
              </button>
            </div>

            {employees.length === 0 ? (
              <div className="text-center py-12 text-slate-500">
                Chưa có nhân viên nào. Tạo nhân viên để phân công và ghi nhận hóa đơn bán hàng theo người bán.
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-left text-sm border-collapse">
                  <thead>
                    <tr className="border-b border-slate-800 text-slate-500 font-bold text-xs uppercase tracking-wider bg-slate-950/20">
                      <th className="py-4 px-6">Mã nhân viên</th>
                      <th className="py-4 px-6">Tên nhân viên</th>
                      <th className="py-4 px-6">Vị trí / Ca làm việc</th>
                      <th className="py-4 px-6 text-center">Trạng thái</th>
                      <th className="py-4 px-6 text-right">Thao tác</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-800 text-slate-300">
                    {employees.map((e) => (
                      <tr key={e.id} className="hover:bg-white/5 transition-colors">
                        <td className="py-4 px-6 font-mono text-xs text-indigo-400 font-bold">{e.id}</td>
                        <td className="py-4 px-6 font-semibold text-white">{e.name}</td>
                        <td className="py-4 px-6 text-slate-400 text-xs">Nhân viên bán hàng</td>
                        <td className="py-4 px-6 text-center">
                          <span className="px-2 py-0.5 rounded text-[10px] font-bold bg-emerald-500/10 text-emerald-400">
                            Đang hoạt động
                          </span>
                        </td>
                        <td className="py-4 px-6 text-right">
                          <button
                            onClick={() => handleDeleteEmployee(e.id)}
                            className="text-xs font-semibold text-rose-400 hover:text-rose-300 cursor-pointer"
                          >
                            Xóa
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        )}

        {activeTab === 'AI' && (
          <form onSubmit={handleSaveAiSettings} className="space-y-5 max-w-xl">
            {aiSaveSuccess && (
              <div className="p-3 rounded bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-xs">
                ✓ Lưu cấu hình AI thành công!
              </div>
            )}

            <div>
              <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">AI Provider</label>
              <div className="flex gap-4">
                <label className="flex items-center gap-2 text-white cursor-pointer text-sm">
                  <input
                    type="radio"
                    name="aiProvider"
                    value="google"
                    checked={aiProvider === 'google'}
                    onChange={() => {
                      setAiProvider('google');
                      setAiModel('models/gemini-1.5-flash');
                    }}
                    className="accent-indigo-500"
                  />
                  Google Gemini
                </label>
                <label className="flex items-center gap-2 text-white cursor-pointer text-sm">
                  <input
                    type="radio"
                    name="aiProvider"
                    value="openrouter"
                    checked={aiProvider === 'openrouter'}
                    onChange={() => {
                      setAiProvider('openrouter');
                      setAiModel('google/gemma-3-27b-it:free');
                    }}
                    className="accent-indigo-500"
                  />
                  OpenRouter
                </label>
              </div>
            </div>

            {aiProvider === 'google' ? (
              <>
                <div>
                  <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Gemini Model</label>
                  <select
                    className="input"
                    value={aiModel}
                    onChange={(e) => setAiModel(e.target.value)}
                  >
                    <option value="models/gemini-2.0-flash">Gemini 2.0 Flash</option>
                    <option value="models/gemini-2.0-flash-lite">Gemini 2.0 Flash Lite</option>
                    <option value="models/gemini-1.5-flash">Gemini 1.5 Flash</option>
                    <option value="models/gemma-4-31b-it">Gemma 4 31B IT</option>
                  </select>
                </div>
                <div>
                  <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Google API Key</label>
                  <input
                    type="password"
                    className="input font-mono"
                    placeholder="AIzaSy..."
                    value={googleKey}
                    onChange={(e) => setGoogleKey(e.target.value)}
                  />
                </div>
              </>
            ) : (
              <>
                <div>
                  <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">OpenRouter Model</label>
                  <select
                    className="input"
                    value={aiModel}
                    onChange={(e) => setAiModel(e.target.value)}
                  >
                    <option value="google/gemma-3-27b-it:free">Google Gemma 3 27B IT (free)</option>
                    <option value="nvidia/nemotron-3-nano-30b-a3b:free">NVIDIA Nemotron 3 (free)</option>
                    <option value="deepseek/deepseek-chat-v3-0324:free">DeepSeek Chat V3 (free)</option>
                    <option value="meta-llama/llama-4-maverick:free">Meta Llama 4 Maverick (free)</option>
                  </select>
                </div>
                <div>
                  <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">OpenRouter API Key</label>
                  <input
                    type="password"
                    className="input font-mono"
                    placeholder="sk-or-v1-..."
                    value={openrouterKey}
                    onChange={(e) => setOpenrouterKey(e.target.value)}
                  />
                </div>
              </>
            )}

            <button type="submit" className="btn btn-primary text-xs shadow-glow cursor-pointer">
              Lưu cấu hình AI
            </button>
          </form>
        )}
      </div>

      {/* Add Bank Modal */}
      {bankModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-xs animate-fade-in">
          <div className="glass w-full max-w-md rounded-2xl border border-white/10 shadow-2xl p-6 relative animate-fade-in-up">
            <div className="flex justify-between items-center mb-6">
              <h3 className="text-xl font-bold text-white">Thêm tài khoản ngân hàng</h3>
              <button onClick={() => setBankModalOpen(false)} className="text-slate-400 hover:text-white text-lg cursor-pointer">✕</button>
            </div>

            <form onSubmit={handleAddBank} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Tên ngân hàng</label>
                <select
                  className="input"
                  value={bankName}
                  onChange={(e) => setBankName(e.target.value)}
                >
                  <option value="Vietcombank">Vietcombank</option>
                  <option value="Techcombank">Techcombank</option>
                  <option value="MB Bank">MB Bank</option>
                  <option value="Vietinbank">Vietinbank</option>
                  <option value="ACB">ACB</option>
                  <option value="BIDV">BIDV</option>
                  <option value="Agribank">Agribank</option>
                </select>
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Số tài khoản</label>
                <input
                  type="text"
                  className="input font-mono"
                  placeholder="Nhập số tài khoản..."
                  required
                  value={accountNo}
                  onChange={(e) => setAccountNo(e.target.value)}
                />
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Tên chủ tài khoản (Không dấu)</label>
                <input
                  type="text"
                  className="input"
                  placeholder="Ví dụ: NGUYEN VAN A"
                  required
                  value={accountName}
                  onChange={(e) => setAccountName(e.target.value)}
                />
              </div>

              <div className="flex justify-end gap-3 pt-4 border-t border-slate-800">
                <button
                  type="button"
                  onClick={() => setBankModalOpen(false)}
                  className="btn btn-secondary text-xs cursor-pointer"
                >
                  Hủy
                </button>
                <button
                  type="submit"
                  className="btn btn-primary text-xs shadow-glow cursor-pointer"
                >
                  Thêm tài khoản
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Add Employee Modal */}
      {empModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-xs animate-fade-in">
          <div className="glass w-full max-w-md rounded-2xl border border-white/10 shadow-2xl p-6 relative animate-fade-in-up">
            <div className="flex justify-between items-center mb-6">
              <h3 className="text-xl font-bold text-white">Thêm nhân viên mới</h3>
              <button onClick={() => setEmpModalOpen(false)} className="text-slate-400 hover:text-white text-lg cursor-pointer">✕</button>
            </div>

            <form onSubmit={handleAddEmployee} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Tên nhân viên</label>
                <input
                  type="text"
                  className="input"
                  placeholder="Nhập họ và tên nhân viên..."
                  required
                  value={empName}
                  onChange={(e) => setEmpName(e.target.value)}
                />
              </div>

              <div className="flex justify-end gap-3 pt-4 border-t border-slate-800">
                <button
                  type="button"
                  onClick={() => setEmpModalOpen(false)}
                  className="btn btn-secondary text-xs cursor-pointer"
                >
                  Hủy
                </button>
                <button
                  type="submit"
                  className="btn btn-primary text-xs shadow-glow cursor-pointer"
                >
                  Thêm nhân viên
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </div>
  );
}
