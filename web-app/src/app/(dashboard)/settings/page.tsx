'use client';

import React, { useState } from 'react';

interface Employee {
  id: string;
  name: string;
  role: string;
  phone?: string;
  isActive: boolean;
}

interface BankAccount {
  id: string;
  bankName: string;
  accountNo: string;
  accountName: string;
  isDefault: boolean;
}

export default function SettingsPage() {
  const [activeTab, setActiveTab] = useState<'STORE' | 'BANK' | 'EMPLOYEE'>('STORE');

  // Store Settings State
  const [storeName, setStoreName] = useState('Market Vendor Coffee');
  const [storePhone, setStorePhone] = useState('0987.654.321');
  const [storeAddress, setStoreAddress] = useState('123 Đường Ba Tháng Hai, Quận 10, TP. Hồ Chí Minh');
  const [storeSaveSuccess, setStoreSaveSuccess] = useState(false);

  // Bank Accounts Settings State
  const [banks, setBanks] = useState<BankAccount[]>([
    { id: 'b-1', bankName: 'Vietcombank', accountNo: '1012345678', accountName: 'NGUYEN VAN A', isDefault: true },
    { id: 'b-2', bankName: 'MB Bank', accountNo: '9999123456', accountName: 'NGUYEN VAN A', isDefault: false },
  ]);
  const [bankModalOpen, setBankModalOpen] = useState(false);
  const [bankName, setBankName] = useState('Techcombank');
  const [accountNo, setAccountNo] = useState('');
  const [accountName, setAccountName] = useState('');

  // Employees Settings State
  const [employees, setEmployees] = useState<Employee[]>([
    { id: 'e-1', name: 'Nguyễn Văn B', role: 'Bán hàng ca sáng', phone: '0911222333', isActive: true },
    { id: 'e-2', name: 'Trần Thị C', role: 'Bán hàng ca tối', phone: '0944555666', isActive: true },
  ]);
  const [empModalOpen, setEmpModalOpen] = useState(false);
  const [empName, setEmpName] = useState('');
  const [empRole, setEmpRole] = useState('Nhân viên bán hàng');
  const [empPhone, setEmpPhone] = useState('');

  const handleSaveStore = (e: React.FormEvent) => {
    e.preventDefault();
    setStoreSaveSuccess(true);
    setTimeout(() => setStoreSaveSuccess(false), 3000);
  };

  const handleAddBank = (e: React.FormEvent) => {
    e.preventDefault();
    if (!accountNo.trim() || !accountName.trim()) return;

    const newBank: BankAccount = {
      id: 'mock-bank-' + Math.random().toString(36).substr(2, 9),
      bankName,
      accountNo,
      accountName: accountName.toUpperCase(),
      isDefault: banks.length === 0,
    };

    setBanks([...banks, newBank]);
    setBankModalOpen(false);
    setAccountNo('');
    setAccountName('');
  };

  const handleSetDefaultBank = (id: string) => {
    setBanks(banks.map(b => ({ ...b, isDefault: b.id === id })));
  };

  const handleDeleteBank = (id: string) => {
    setBanks(banks.filter(b => b.id !== id));
  };

  const handleAddEmployee = (e: React.FormEvent) => {
    e.preventDefault();
    if (!empName.trim()) return;

    const newEmp: Employee = {
      id: 'mock-emp-' + Math.random().toString(36).substr(2, 9),
      name: empName,
      role: empRole,
      phone: empPhone || undefined,
      isActive: true,
    };

    setEmployees([...employees, newEmp]);
    setEmpModalOpen(false);
    setEmpName('');
    setEmpPhone('');
  };

  const handleToggleEmployeeActive = (id: string) => {
    setEmployees(employees.map(e => e.id === id ? { ...e, isActive: !e.isActive } : e));
  };

  return (
    <div className="space-y-8 animate-fade-in-up">
      {/* Header */}
      <div>
        <h2 className="text-2xl font-bold text-white font-sans">Cấu hình hệ thống</h2>
        <p className="text-sm text-slate-400">Thiết lập thông tin cửa hàng, ngân hàng VietQR & nhân viên</p>
      </div>

      {/* Tabs */}
      <div className="flex border-b border-slate-800">
        <button
          onClick={() => setActiveTab('STORE')}
          className={`px-6 py-3 font-semibold text-sm border-b-2 transition-all ${
            activeTab === 'STORE'
              ? 'border-indigo-500 text-indigo-300'
              : 'border-transparent text-slate-400 hover:text-slate-200'
          }`}
        >
          🏪 Thông tin cửa hàng
        </button>
        <button
          onClick={() => setActiveTab('BANK')}
          className={`px-6 py-3 font-semibold text-sm border-b-2 transition-all ${
            activeTab === 'BANK'
              ? 'border-indigo-500 text-indigo-300'
              : 'border-transparent text-slate-400 hover:text-slate-200'
          }`}
        >
          🏦 Tài khoản VietQR
        </button>
        <button
          onClick={() => setActiveTab('EMPLOYEE')}
          className={`px-6 py-3 font-semibold text-sm border-b-2 transition-all ${
            activeTab === 'EMPLOYEE'
              ? 'border-indigo-500 text-indigo-300'
              : 'border-transparent text-slate-400 hover:text-slate-200'
          }`}
        >
          👥 Quản lý nhân viên
        </button>
      </div>

      {/* Content panel */}
      <div className="card bg-slate-900 border-white/5 p-6">
        {activeTab === 'STORE' && (
          <form onSubmit={handleSaveStore} className="space-y-5 max-w-xl">
            {storeSaveSuccess && (
              <div className="p-3 rounded bg-emerald-500/10 border border-emerald-500/20 text-emerald-400 text-xs">
                ✓ Lưu thông tin cửa hàng thành công!
              </div>
            )}
            
            <div>
              <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Tên cửa hàng</label>
              <input
                type="text"
                className="input"
                value={storeName}
                onChange={(e) => setStoreName(e.target.value)}
              />
            </div>

            <div>
              <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Số điện thoại liên hệ</label>
              <input
                type="text"
                className="input font-mono"
                value={storePhone}
                onChange={(e) => setStorePhone(e.target.value)}
              />
            </div>

            <div>
              <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Địa chỉ cửa hàng</label>
              <input
                type="text"
                className="input"
                value={storeAddress}
                onChange={(e) => setStoreAddress(e.target.value)}
              />
            </div>

            <button type="submit" className="btn btn-primary text-xs shadow-glow">
              Lưu thay đổi
            </button>
          </form>
        )}

        {activeTab === 'BANK' && (
          <div className="space-y-6">
            <div className="flex justify-between items-center">
              <h3 className="font-bold text-white text-base">Tài khoản thanh toán ngân hàng</h3>
              <button onClick={() => setBankModalOpen(true)} className="btn btn-primary text-xs shadow-glow">
                ➕ Thêm tài khoản
              </button>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
              {banks.map((b) => (
                <div key={b.id} className="card bg-slate-950/40 border-white/5 relative p-5 flex flex-col justify-between group">
                  {b.isDefault && (
                    <span className="absolute top-4 right-4 bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 px-2 py-0.5 rounded text-[9px] font-bold uppercase tracking-wider">
                      Mặc định
                    </span>
                  )}
                  
                  <div className="space-y-2">
                    <p className="text-xs font-bold text-slate-500 uppercase tracking-widest">{b.bankName}</p>
                    <p className="text-lg font-bold text-white font-mono">{b.accountNo}</p>
                    <p className="text-xs text-slate-300 font-semibold">{b.accountName}</p>
                  </div>

                  <div className="flex justify-between items-center mt-5 pt-3 border-t border-slate-800 text-xs">
                    {!b.isDefault ? (
                      <button
                        onClick={() => handleSetDefaultBank(b.id)}
                        className="text-slate-400 hover:text-white"
                      >
                        Đặt làm mặc định
                      </button>
                    ) : (
                      <span className="text-slate-600 italic">Đang dùng mặc định</span>
                    )}

                    <button
                      onClick={() => handleDeleteBank(b.id)}
                      className="text-rose-400 hover:text-rose-300 font-semibold"
                    >
                      Xóa
                    </button>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {activeTab === 'EMPLOYEE' && (
          <div className="space-y-6">
            <div className="flex justify-between items-center">
              <h3 className="font-bold text-white text-base">Quản lý tài khoản nhân viên</h3>
              <button onClick={() => setEmpModalOpen(true)} className="btn btn-primary text-xs shadow-glow">
                ➕ Thêm nhân viên
              </button>
            </div>

            <div className="overflow-x-auto">
              <table className="w-full text-left text-sm border-collapse">
                <thead>
                  <tr className="border-b border-slate-800 text-slate-500 font-bold text-xs uppercase tracking-wider bg-slate-950/20">
                    <th className="py-4 px-6">Tên nhân viên</th>
                    <th className="py-4 px-6">Vị trí / Ca làm việc</th>
                    <th className="py-4 px-6">Số điện thoại</th>
                    <th className="py-4 px-6 text-center">Trạng thái</th>
                    <th className="py-4 px-6 text-right">Thao tác</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-800 text-slate-300">
                  {employees.map((e) => (
                    <tr key={e.id} className="hover:bg-white/5 transition-colors">
                      <td className="py-4 px-6 font-semibold text-white">{e.name}</td>
                      <td className="py-4 px-6 text-slate-400 text-xs">{e.role}</td>
                      <td className="py-4 px-6 text-slate-300 font-mono text-xs">{e.phone || '-'}</td>
                      <td className="py-4 px-6 text-center">
                        <span className={`px-2 py-0.5 rounded text-[10px] font-bold ${
                          e.isActive ? 'bg-emerald-500/10 text-emerald-400' : 'bg-slate-800 text-slate-500'
                        }`}>
                          {e.isActive ? 'Đang hoạt động' : 'Tạm khóa'}
                        </span>
                      </td>
                      <td className="py-4 px-6 text-right">
                        <button
                          onClick={() => handleToggleEmployeeActive(e.id)}
                          className={`text-xs font-semibold ${
                            e.isActive ? 'text-rose-400 hover:text-rose-300' : 'text-emerald-400 hover:text-emerald-300'
                          }`}
                        >
                          {e.isActive ? 'Khóa tài khoản' : 'Kích hoạt'}
                        </button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </div>

      {/* Add Bank Modal */}
      {bankModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in">
          <div className="glass w-full max-w-md rounded-2xl border border-white/10 shadow-2xl p-6 relative animate-fade-in-up">
            <div className="flex justify-between items-center mb-6">
              <h3 className="text-xl font-bold text-white">Thêm tài khoản ngân hàng</h3>
              <button onClick={() => setBankModalOpen(false)} className="text-slate-400 hover:text-white text-lg">✕</button>
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
                </select>
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Số tài khoản</label>
                <input
                  type="text"
                  className="input font-mono"
                  placeholder="Nhập số tài khoản..."
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
                  value={accountName}
                  onChange={(e) => setAccountName(e.target.value)}
                />
              </div>

              <div className="flex justify-end gap-3 pt-4 border-t border-slate-800">
                <button
                  type="button"
                  onClick={() => setBankModalOpen(false)}
                  className="btn btn-secondary text-xs"
                >
                  Hủy
                </button>
                <button
                  type="submit"
                  className="btn btn-primary text-xs shadow-glow"
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
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm animate-fade-in">
          <div className="glass w-full max-w-md rounded-2xl border border-white/10 shadow-2xl p-6 relative animate-fade-in-up">
            <div className="flex justify-between items-center mb-6">
              <h3 className="text-xl font-bold text-white">Thêm tài khoản nhân viên</h3>
              <button onClick={() => setEmpModalOpen(false)} className="text-slate-400 hover:text-white text-lg">✕</button>
            </div>

            <form onSubmit={handleAddEmployee} className="space-y-4">
              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Tên nhân viên</label>
                <input
                  type="text"
                  className="input"
                  placeholder="Nhập tên nhân viên..."
                  value={empName}
                  onChange={(e) => setEmpName(e.target.value)}
                />
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Vị trí / Ca trực</label>
                <input
                  type="text"
                  className="input"
                  placeholder="Ví dụ: Bán hàng ca sáng..."
                  value={empRole}
                  onChange={(e) => setEmpRole(e.target.value)}
                />
              </div>

              <div>
                <label className="block text-xs font-bold text-slate-400 uppercase tracking-wider mb-2">Số điện thoại</label>
                <input
                  type="text"
                  className="input font-mono"
                  placeholder="Nhập số điện thoại nhân viên..."
                  value={empPhone}
                  onChange={(e) => setEmpPhone(e.target.value)}
                />
              </div>

              <div className="flex justify-end gap-3 pt-4 border-t border-slate-800">
                <button
                  type="button"
                  onClick={() => setEmpModalOpen(false)}
                  className="btn btn-secondary text-xs"
                >
                  Hủy
                </button>
                <button
                  type="submit"
                  className="btn btn-primary text-xs shadow-glow"
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
