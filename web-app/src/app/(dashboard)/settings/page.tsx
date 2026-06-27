'use client';

import React, { useState, useEffect, useMemo } from 'react';
import { GridColDef } from '@mui/x-data-grid';
import api from '@/lib/api';
import { fetchAvailableModels, presetModels } from '@/lib/ai';
import Modal from '@/components/ui/Modal';
import VietQrDisplay from '@/components/ui/VietQrDisplay';
import AppDataGrid from '@/components/ui/AppDataGrid';
import { VIETQR_BANKS } from '@/lib/vietqr';

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
  const [activeTab, setActiveTab] = useState<'STORE' | 'BANK' | 'EMPLOYEE' | 'AI' | 'THEME'>('STORE');
  const [currentTheme, setCurrentTheme] = useState('midnight');

  // Store Settings State
  const [storeName, setStoreName] = useState('');
  const [storePhone, setStorePhone] = useState('');
  const [storeAddress, setStoreAddress] = useState('');
  const [storeSaveSuccess, setStoreSaveSuccess] = useState(false);

  // Bank Accounts Settings State
  const [banks, setBanks] = useState<BankAccount[]>([]);
  const [bankModalOpen, setBankModalOpen] = useState(false);
  const [bankName, setBankName] = useState('Vietcombank');
  const [bankCode, setBankCode] = useState('VCB');
  const [bankBin, setBankBin] = useState('970436');
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
  const [modelsList, setModelsList] = useState<any[]>([]);
  const [fetchingModels, setFetchingModels] = useState(false);

  // Common State
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  // Load data based on active tab
  useEffect(() => {
    fetchData();
  }, [activeTab]);

  useEffect(() => {
    // Load selected AI model & theme from localStorage on client mount
    if (typeof window !== 'undefined') {
      const savedModel = localStorage.getItem('ai_model');
      if (savedModel) {
        setAiModel(savedModel);
      }
      const savedTheme = localStorage.getItem('app_theme') || 'midnight';
      setCurrentTheme(savedTheme);
    }
  }, []);

  // Fetch available models dynamically when provider or API key changes
  useEffect(() => {
    const key = aiProvider === 'google' ? googleKey : openrouterKey;
    if (!key) {
      setModelsList(presetModels(aiProvider));
      return;
    }

    let active = true;
    const loadModels = async () => {
      setFetchingModels(true);
      const list = await fetchAvailableModels(aiProvider, key);
      if (active) {
        setModelsList(list);
        setFetchingModels(false);
      }
    };

    loadModels();
    return () => {
      active = false;
    };
  }, [aiProvider, googleKey, openrouterKey]);

  const fetchData = async () => {
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
      } else if (activeTab === 'AI') {
        const ai = await api.getAiSettings();
        if (ai) {
          const provider = (ai.provider || 'google') as 'google' | 'openrouter';
          setAiProvider(provider);
          setGoogleKey(ai.googleKey || '');
          setOpenrouterKey(ai.openrouterKey || '');
          
          const savedModel = localStorage.getItem('ai_model');
          if (savedModel) {
            setAiModel(savedModel);
          } else {
            setAiModel(provider === 'google' ? 'models/gemini-1.5-flash' : 'google/gemma-3-27b-it:free');
          }
        }
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
        code: bankCode,
        bin: bankBin,
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

  const handleSaveAiSettings = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    try {
      await api.updateAiSettings({
        provider: aiProvider,
        googleKey,
        openrouterKey,
      });

      if (typeof window !== 'undefined') {
        localStorage.setItem('ai_provider', aiProvider);
        localStorage.setItem('ai_model', aiModel);
      }

      setAiSaveSuccess(true);
      setTimeout(() => setAiSaveSuccess(false), 3000);
    } catch (err: any) {
      console.error('Failed to save AI settings:', err);
      setError('Lưu cấu hình AI thất bại: ' + err.message);
    }
  };

  const employeeRows = useMemo(() => employees.map((e) => ({
    id: e.id,
    code: e.id,
    name: e.name,
    position: 'Nhân viên bán hàng',
    status: 'Đang hoạt động',
  })), [employees]);

  const employeeColumns: GridColDef[] = useMemo(() => [
    { field: 'code', headerName: 'Mã NV', width: 100 },
    { field: 'name', headerName: 'Tên', flex: 1, minWidth: 140 },
    { field: 'position', headerName: 'Vị trí', width: 160 },
    { field: 'status', headerName: 'Trạng thái', width: 120 },
    {
      field: 'actions',
      headerName: '',
      width: 80,
      sortable: false,
      renderCell: (params) => (
        <button
          onClick={() => handleDeleteEmployee(String(params.id))}
          className="text-rose-400 text-xs font-semibold h-full"
        >
          Xóa
        </button>
      ),
    },
  ], []);

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
        <button
          onClick={() => setActiveTab('THEME')}
          className={`px-6 py-3 font-semibold text-sm border-b-2 transition-all cursor-pointer ${
            activeTab === 'THEME'
              ? 'border-indigo-500 text-indigo-300'
              : 'border-transparent text-slate-400 hover:text-slate-200'
          }`}
        >
          🎨 Giao diện
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
                  <div key={b.id} className="card bg-slate-950/40 border-white/5 relative p-5 flex flex-col gap-4 group">
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

                    <div className="border-t border-slate-800 pt-4">
                      <VietQrDisplay
                        bank={b}
                        staticQr
                        size="xl"
                        showBankInfo={false}
                      />
                    </div>

                    <div className="flex justify-end items-center pt-1 border-t border-slate-800 text-xs">
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
              <AppDataGrid rows={employeeRows} columns={employeeColumns} height={360} />
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

            <div>
              <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">
                {aiProvider === 'google' ? 'Gemini Model' : 'OpenRouter Model'}
                {fetchingModels && <span className="text-[10px] text-indigo-400 ml-2 animate-pulse">(Đang lấy danh sách từ API...)</span>}
              </label>
              <select
                className="input"
                value={aiModel}
                onChange={(e) => setAiModel(e.target.value)}
              >
                {modelsList.map((m) => (
                  <option key={m.id} value={m.id}>{m.name}</option>
                ))}
                {modelsList.length === 0 && (
                  <option value={aiModel}>{aiModel}</option>
                )}
              </select>
            </div>

            {aiProvider === 'google' ? (
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
            ) : (
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
            )}

            <button type="submit" className="btn btn-primary text-xs shadow-glow cursor-pointer">
              Lưu cấu hình AI
            </button>
          </form>
         )}

        {activeTab === 'THEME' && (
          <div className="space-y-6">
            <div>
              <h3 className="text-sm font-bold text-white uppercase tracking-wider mb-1">Chọn giao diện ứng dụng</h3>
              <p className="text-xs text-slate-400">Thay đổi màu sắc chủ đạo và cách hiển thị của toàn bộ hệ thống</p>
            </div>
            
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-4">
              {[
                { name: 'midnight', label: 'Midnight (Tối)', colors: ['#6366f1', '#06b6d4', '#0f172a'] },
                { name: 'light', label: 'Hồng mộng mơ (Sáng)', colors: ['#d82d8b', '#ff85c4', '#fff4fa'] },
                { name: 'spring', label: 'Gió mùa xuân (Sáng)', colors: ['#2e7d32', '#66bb6a', '#f1f8e9'] },
                { name: 'sky', label: 'Bầu trời xanh (Sáng)', colors: ['#0288d1', '#29b6f6', '#e1f5fe'] },
                { name: 'mist', label: 'Sương sớm (Sáng)', colors: ['#475569', '#cbd5e1', '#f8fafc'] },
                { name: 'nature', label: 'Thiên nhiên (Tối)', colors: ['#2e7d32', '#66bb6a', '#0f1c11'] },
                { name: 'ocean', label: 'Biển xanh (Tối)', colors: ['#0077b6', '#00b4d8', '#051329'] },
                { name: 'sunset', label: 'Hoàng hôn (Tối)', colors: ['#e65100', '#ff9100', '#1f0f08'] },
                { name: 'lavender', label: 'Lavender (Tối)', colors: ['#7c4dff', '#b388ff', '#0e0a1a'] }
              ].map((theme) => {
                const isSelected = theme.name === currentTheme;
                return (
                  <button
                    key={theme.name}
                    type="button"
                    onClick={() => {
                      setCurrentTheme(theme.name);
                      localStorage.setItem('app_theme', theme.name);
                      const isLight = ['light', 'spring', 'sky', 'mist'].indexOf(theme.name) !== -1;
                      document.documentElement.className = 'theme-' + theme.name + ' ' + (isLight ? 'light' : 'dark');
                    }}
                    className={`p-4 rounded-2xl border text-left flex flex-col justify-between h-32 transition-all cursor-pointer ${
                      isSelected 
                        ? 'border-indigo-500 bg-indigo-500/10 shadow-glow shadow-indigo-500/5' 
                        : 'border-white/5 bg-slate-950/40 hover:border-white/20'
                    }`}
                  >
                    <div className="flex justify-between items-start w-full">
                      <span className="text-xs font-bold text-white">{theme.label}</span>
                      {isSelected && <span className="text-indigo-400 text-sm">✓</span>}
                    </div>
                    
                    <div className="flex gap-1.5 mt-4">
                      {theme.colors.map((c, idx) => (
                        <span 
                          key={idx} 
                          className="w-5 h-5 rounded-full border border-white/10" 
                          style={{ backgroundColor: c }}
                        />
                      ))}
                    </div>
                  </button>
                );
              })}
            </div>
          </div>
        )}
      </div>

      <Modal open={bankModalOpen} onClose={() => setBankModalOpen(false)} title="Thêm tài khoản ngân hàng" maxWidth="max-w-md">
            <form onSubmit={handleAddBank} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Tên ngân hàng</label>
                <select
                  className="input"
                  value={bankName}
                  onChange={(e) => {
                    const selected = VIETQR_BANKS.find(b => b.shortName === e.target.value);
                    if (selected) {
                      setBankName(selected.shortName);
                      setBankCode(selected.code);
                      setBankBin(selected.bin);
                    }
                  }}
                >
                  {VIETQR_BANKS.map((b) => (
                    <option key={b.code} value={b.shortName}>{b.shortName}</option>
                  ))}
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
      </Modal>

      <Modal open={empModalOpen} onClose={() => setEmpModalOpen(false)} title="Thêm nhân viên mới" maxWidth="max-w-md">
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
      </Modal>
    </div>
  );
}
