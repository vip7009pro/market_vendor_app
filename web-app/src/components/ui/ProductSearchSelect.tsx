'use client';

import React, { useEffect, useMemo, useRef, useState } from 'react';
import { matchVietnamese } from '@/lib/text';

interface ProductOption {
  id: string;
  name: string;
  unit?: string;
  currentStock?: number;
  costPrice?: number;
}

interface ProductSearchSelectProps {
  products: ProductOption[];
  value: string;
  onChange: (productId: string) => void;
  onSelect?: (product: ProductOption) => void;
  placeholder?: string;
}

export default function ProductSearchSelect({
  products,
  value,
  onChange,
  onSelect,
  placeholder = 'Gõ tên sản phẩm để tìm...',
}: ProductSearchSelectProps) {
  const [query, setQuery] = useState('');
  const [open, setOpen] = useState(false);
  const [highlight, setHighlight] = useState(0);
  const containerRef = useRef<HTMLDivElement>(null);

  const selected = products.find((p) => p.id === value);

  const filtered = useMemo(() => {
    const q = query.trim();
    if (!q) return products.slice(0, 20);
    return products.filter((p) => matchVietnamese(p.name, q)).slice(0, 20);
  }, [products, query]);

  useEffect(() => {
    if (selected) setQuery(selected.name);
  }, [selected?.id]);

  useEffect(() => {
    const onDocClick = (e: MouseEvent) => {
      if (!containerRef.current?.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', onDocClick);
    return () => document.removeEventListener('mousedown', onDocClick);
  }, []);

  const pick = (p: ProductOption) => {
    onChange(p.id);
    onSelect?.(p);
    setQuery(p.name);
    setOpen(false);
  };

  const onKeyDown = (e: React.KeyboardEvent) => {
    if (!open && (e.key === 'ArrowDown' || e.key === 'Enter')) {
      setOpen(true);
      return;
    }
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setHighlight((h) => Math.min(h + 1, filtered.length - 1));
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setHighlight((h) => Math.max(h - 1, 0));
    } else if (e.key === 'Enter') {
      e.preventDefault();
      if (filtered[highlight]) pick(filtered[highlight]);
    } else if (e.key === 'Escape') {
      setOpen(false);
    }
  };

  return (
    <div ref={containerRef} className="relative">
      <input
        type="text"
        className="input text-xs w-full"
        placeholder={placeholder}
        value={query}
        onChange={(e) => {
          setQuery(e.target.value);
          setOpen(true);
          setHighlight(0);
          if (!e.target.value) onChange('');
        }}
        onFocus={() => setOpen(true)}
        onKeyDown={onKeyDown}
      />
      {open && filtered.length > 0 && (
        <div className="absolute z-50 mt-1 w-full max-h-48 overflow-y-auto rounded-xl border border-[var(--color-border)] bg-[var(--color-bg-secondary)] p-1.5 shadow-2xl space-y-0.5">
          {filtered.map((p, idx) => (
            <button
              key={p.id}
              type="button"
              className={`w-full text-left px-3 py-2.5 text-sm sm:text-base flex justify-between gap-2 transition-colors ${
                idx === highlight ? 'bg-indigo-500/20 text-indigo-300' : 'text-[var(--color-text)] hover:bg-[var(--color-bg-elevated)]'
              }`}
              onMouseEnter={() => setHighlight(idx)}
              onClick={() => pick(p)}
            >
              <span className="truncate font-semibold">{p.name}</span>
              <span className="text-slate-500 shrink-0 text-xs">
                {p.currentStock !== undefined ? `Tồn: ${p.currentStock} ${p.unit || ''}` : ''}
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
