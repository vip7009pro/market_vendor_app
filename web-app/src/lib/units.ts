const STORAGE_KEY = 'mv_last_product_unit';
const CUSTOM_UNITS_KEY = 'mv_custom_product_units';

export const COMMON_UNITS = ['cái', 'ly', 'lon', 'chai', 'gói', 'kg', 'gram', 'hộp', 'thùng', 'ổ', 'túi', 'bịch'];

export function getLastUsedUnit(): string {
  if (typeof window === 'undefined') return 'cái';
  return localStorage.getItem(STORAGE_KEY) || 'cái';
}

export function saveLastUsedUnit(unit: string): void {
  if (typeof window === 'undefined' || !unit.trim()) return;
  localStorage.setItem(STORAGE_KEY, unit.trim());
}

export function getCustomUnits(): string[] {
  if (typeof window === 'undefined') return [];
  try {
    const raw = localStorage.getItem(CUSTOM_UNITS_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch {
    return [];
  }
}

export function saveCustomUnit(unit: string): void {
  if (typeof window === 'undefined' || !unit.trim()) return;
  const trimmed = unit.trim();
  const existing = getCustomUnits();
  if (!existing.includes(trimmed) && !COMMON_UNITS.includes(trimmed)) {
    localStorage.setItem(CUSTOM_UNITS_KEY, JSON.stringify([trimmed, ...existing].slice(0, 20)));
  }
  saveLastUsedUnit(trimmed);
}

export function getAllUnitOptions(): string[] {
  const custom = getCustomUnits();
  const merged = [...custom, ...COMMON_UNITS];
  return [...new Set(merged)];
}
