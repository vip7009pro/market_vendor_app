'use client';

import React, { useEffect, useState } from 'react';
import { createPortal } from 'react-dom';

interface ModalProps {
  open: boolean;
  onClose: () => void;
  children: React.ReactNode;
  title?: React.ReactNode;
  maxWidth?: string;
  className?: string;
  contentClassName?: string;
  closeOnBackdrop?: boolean;
}

export default function Modal({
  open,
  onClose,
  children,
  title,
  maxWidth = 'max-w-md',
  className = '',
  contentClassName = '',
  closeOnBackdrop = true,
}: ModalProps) {
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  useEffect(() => {
    if (!open) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => {
      document.body.style.overflow = prev;
      window.removeEventListener('keydown', onKey);
    };
  }, [open, onClose]);

  if (!open || !mounted) return null;

  return createPortal(
    <div
      className={`fixed inset-0 z-[200] flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm ${className}`}
      onClick={(e) => {
        if (closeOnBackdrop && e.target === e.currentTarget) onClose();
      }}
    >
      <div
        className={`glass w-full ${maxWidth} rounded-2xl border border-white/10 shadow-2xl p-6 relative max-h-[90vh] overflow-y-auto ${contentClassName}`}
        role="dialog"
        aria-modal="true"
      >
        {title !== undefined && (
          <div className="flex justify-between items-center mb-6">
            <div className="text-xl font-bold text-white">{title}</div>
            <button
              type="button"
              onClick={onClose}
              className="text-slate-400 hover:text-white text-lg leading-none"
              aria-label="Đóng"
            >
              ✕
            </button>
          </div>
        )}
        {children}
      </div>
    </div>,
    document.body
  );
}
