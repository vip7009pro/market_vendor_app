'use client';

import React from 'react';
import { BankAccountForQr, getVietQrStaticUrl, getVietQrUrl, isBankAccountQrReady } from '@/lib/vietqr';
import { formatCurrency } from '@/lib/format';

interface VietQrDisplayProps {
  bank: BankAccountForQr | null | undefined;
  amount?: number;
  description?: string;
  staticQr?: boolean;
  size?: 'sm' | 'md' | 'lg' | 'xl' | 'pos';
  showBankInfo?: boolean;
}

export default function VietQrDisplay({
  bank,
  amount = 0,
  description = '',
  staticQr = false,
  size = 'md',
  showBankInfo = true,
}: VietQrDisplayProps) {
  if (!isBankAccountQrReady(bank)) {
    return (
      <div className="py-8 text-center text-xs text-slate-500">
        ⚠️ Chưa cấu hình tài khoản ngân hàng VietQR. Vào Cài đặt → Tài khoản VietQR để thêm và chọn mặc định.
      </div>
    );
  }

  const url = staticQr
    ? getVietQrStaticUrl(bank!)
    : getVietQrUrl(bank!, amount, description);

  const sizeClass =
    size === 'sm' ? 'w-40 h-40'
    : size === 'lg' ? 'w-72 h-72'
    : size === 'xl' ? 'w-80 h-80'
    : size === 'pos' ? 'w-full max-w-[280px] aspect-square'
    : 'w-56 h-56';

  return (
    <div className="flex flex-col items-center justify-center text-center space-y-3">
      <p className="text-xs font-bold text-white uppercase tracking-wider">
        {staticQr ? 'QR chuyển khoản (tự nhập số tiền)' : 'Quét QR chuyển khoản'}
      </p>
      <img
        src={url}
        alt="Mã QR VietQR"
        className={`${sizeClass} object-contain rounded-lg border border-white/10 bg-white p-2`}
      />
      {staticQr && (
        <p className="text-[10px] text-slate-400 max-w-xs">
          Khách quét QR và tự nhập số tiền, nội dung chuyển khoản trên app ngân hàng.
        </p>
      )}
      {showBankInfo && (
        <div className="text-xs text-slate-300">
          {bank!.name && <p className="font-semibold">{bank!.name}</p>}
          <p>
            STK: <strong className="text-indigo-400 font-mono">{bank!.accountNo}</strong>
          </p>
          <p className="text-[10px] text-slate-500 mt-1 uppercase">Chủ TK: {bank!.accountName}</p>
          {!staticQr && amount > 0 && (
            <p className="text-emerald-400 font-bold mt-1">{formatCurrency(amount)}</p>
          )}
        </div>
      )}
    </div>
  );
}
