/**
 * Vietnamese text normalization utilities.
 * Ported from mobile `lib/utils/text_normalizer.dart` and `lib/screens/sale_screen.dart`.
 */

const DIACRITICS_MAP: Record<string, string> = {
  'a': 'àáạảãâầấậẩẫăằắặẳẵ',
  'A': 'ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴ',
  'e': 'èéẹẻẽêềếệểễ',
  'E': 'ÈÉẸẺẼÊỀẾỆỂỄ',
  'i': 'ìíịỉĩ',
  'I': 'ÌÍỊỈĨ',
  'o': 'òóọỏõôồốộổỗơờớợởỡ',
  'O': 'ÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠ',
  'u': 'ùúụủũưừứựửữ',
  'U': 'ÙÚỤỦŨƯỪỨỰỬỮ',
  'y': 'ỳýỵỷỹ',
  'Y': 'ỲÝỴỶỸ',
  'd': 'đ',
  'D': 'Đ',
};

// Pre-build reverse lookup for performance
const _charMap: Record<string, string> = {};
for (const [base, chars] of Object.entries(DIACRITICS_MAP)) {
  for (const ch of chars) {
    _charMap[ch] = base;
  }
}

/**
 * Remove Vietnamese diacritics from a string.
 * "Cà phê sữa đá" → "Ca phe sua da"
 */
export function removeDiacritics(str: string): string {
  let result = '';
  for (const ch of str) {
    result += _charMap[ch] ?? ch;
  }
  return result;
}

/**
 * Normalize Vietnamese text: trim, collapse whitespace, remove diacritics, lowercase.
 * "  Cà Phê  Sữa  Đá  " → "ca phe sua da"
 */
export function normalize(input: string): string {
  const trimmed = input.trim().replace(/\s+/g, ' ');
  return removeDiacritics(trimmed).toLowerCase();
}

/**
 * Get initials (first letter of each word) from normalized text.
 * "Cà phê sữa đá" → "cpsd"
 */
export function getInitials(str: string): string {
  const normalized = normalize(str);
  const words = normalized.split(/\s+/).filter(w => w.length > 0);
  return words.map(w => w[0]).join('');
}

/**
 * Match Vietnamese text against a query.
 * Supports:
 *  - Exact match (with diacritics)
 *  - Normalized match (without diacritics)
 *  - Initials match ("cpsd" matches "Cà phê sữa đá")
 *
 * @param text - The text to search in
 * @param query - The search query
 * @returns true if text matches query
 */
export function matchVietnamese(text: string, query: string): boolean {
  if (!query || !query.trim()) return true;
  const q = query.trim().toLowerCase();
  
  // 1. Direct lowercase match (preserves diacritics)
  if (text.toLowerCase().includes(q)) return true;
  
  // 2. Normalized match (both sides stripped of diacritics)
  const normalizedText = normalize(text);
  const normalizedQuery = normalize(query);
  if (normalizedText.includes(normalizedQuery)) return true;
  
  // 3. Initials match (e.g., "cpsd" matches "Cà phê sữa đá")
  if (normalizedQuery.length >= 2) {
    const initials = getInitials(text);
    if (initials.includes(normalizedQuery)) return true;
  }
  
  return false;
}
