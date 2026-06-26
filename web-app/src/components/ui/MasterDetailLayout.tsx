'use client';

import React from 'react';

interface MasterDetailLayoutProps {
  list: React.ReactNode;
  detail: React.ReactNode;
  detailTitle?: string;
  detailEmpty?: React.ReactNode;
  showDetail?: boolean;
}

export default function MasterDetailLayout({
  list,
  detail,
  detailTitle = 'Chi tiết',
  detailEmpty,
  showDetail = true,
}: MasterDetailLayoutProps) {
  return (
    <div className="grid grid-cols-1 xl:grid-cols-12 gap-4 flex-1 min-h-[400px] lg:h-[calc(100vh-270px)] mt-6">
      <div className="xl:col-span-7 h-full flex flex-col min-h-[400px]">{list}</div>
      <div className="xl:col-span-5 h-full">
        <div className="card bg-slate-900 border-white/5 h-full flex flex-col overflow-hidden">
          <div className="px-5 py-4 border-b border-slate-800 shrink-0">
            <h3 className="font-bold text-white text-sm">{detailTitle}</h3>
          </div>
          <div className="flex-1 overflow-y-auto p-5">
            {showDetail ? detail : (detailEmpty || (
              <div className="h-full flex items-center justify-center text-slate-500 text-sm text-center py-12">
                Chọn một dòng trong bảng để xem chi tiết
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
