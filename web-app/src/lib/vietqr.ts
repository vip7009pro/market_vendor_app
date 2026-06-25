export interface BankAccountForQr {
  bin?: string | null;
  code?: string | null;
  accountNo: string;
  accountName: string;
  name?: string | null;
}

export const VIETQR_BANKS: Array<{
  name: string;
  code: string;
  bin: string;
  shortName: string;
}> = [
  { name: 'Ngân hàng TMCP Ngoại thương Việt Nam', code: 'VCB', bin: '970436', shortName: 'Vietcombank' },
  { name: 'Ngân hàng TMCP Kỹ thương Việt Nam', code: 'TCB', bin: '970407', shortName: 'Techcombank' },
  { name: 'Ngân hàng TMCP Quân đội', code: 'MB', bin: '970422', shortName: 'MB Bank' },
  { name: 'Ngân hàng TMCP Công thương Việt Nam', code: 'CTG', bin: '970415', shortName: 'Vietinbank' },
  { name: 'Ngân hàng TMCP Á Châu', code: 'ACB', bin: '970416', shortName: 'ACB' },
  { name: 'Ngân hàng TMCP Đầu tư và Phát triển Việt Nam', code: 'BIDV', bin: '970418', shortName: 'BIDV' },
  { name: 'Ngân hàng Nông nghiệp và Phát triển Nông thôn Việt Nam', code: 'VBA', bin: '970405', shortName: 'Agribank' },
  { name: 'Ngân hàng TMCP Sài Gòn Thương Tín', code: 'STB', bin: '970403', shortName: 'Sacombank' },
  { name: 'Ngân hàng TMCP Phát triển TP.HCM', code: 'HDB', bin: '970437', shortName: 'HDBank' },
  { name: 'Ngân hàng TMCP Tiên Phong', code: 'TPB', bin: '970423', shortName: 'TPBank' },
  { name: 'Ngân hàng TMCP Việt Nam Thịnh Vượng', code: 'VPB', bin: '970432', shortName: 'VPBank' },
];

export function getBankBin(bankName: string): string {
  const normalized = bankName.trim().toLowerCase();
  const found = VIETQR_BANKS.find(
    (b) =>
      b.shortName.toLowerCase() === normalized ||
      b.name.toLowerCase().includes(normalized) ||
      b.code.toLowerCase() === normalized
  );
  return found?.bin || '';
}

export function sanitizeVietQrAddInfo(text: string): string {
  return text
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-zA-Z0-9\s=xX\-]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function last5DigitsOfId(id: string): string {
  const digits = id.replace(/\D/g, '');
  if (digits.length >= 5) return digits.slice(-5);
  const raw = id.trim();
  if (raw.length >= 5) return raw.slice(-5);
  return raw;
}

export function buildVietQrAddInfoFromItems(
  saleId: string,
  items: Array<{ name: string; quantity: number; unitPrice: number }>
): string {
  const parts = items.map((it) => {
    const name = sanitizeVietQrAddInfo(it.name);
    return `${name} x${it.quantity}=${Math.round(it.unitPrice * it.quantity)}`;
  });
  const tail = last5DigitsOfId(saleId);
  const raw = `${tail ? `${tail} ` : ''}Noi dung: ${parts.join('; ')}`;
  let safe = sanitizeVietQrAddInfo(raw);
  if (safe.length > 50) safe = `${safe.slice(0, 47)}...`;
  return safe;
}

export function getVietQrStaticUrl(bank: BankAccountForQr, template = 'compact2'): string {
  const bankId = (bank.bin || bank.code || '').trim();
  const accountNo = bank.accountNo.trim();
  const accountName = encodeURIComponent(bank.accountName.trim());
  if (!bankId || !accountNo) return '';
  return `https://img.vietqr.io/image/${bankId}-${accountNo}-${template}.png?accountName=${accountName}`;
}

export function getVietQrUrl(
  bank: BankAccountForQr,
  amount: number,
  description: string,
  template = 'compact2'
): string {
  const bankId = (bank.bin || bank.code || '').trim();
  const accountNo = bank.accountNo.trim();
  const accountName = encodeURIComponent(bank.accountName.trim());
  const addInfo = encodeURIComponent(sanitizeVietQrAddInfo(description));
  if (!bankId || !accountNo) return '';
  return `https://img.vietqr.io/image/${bankId}-${accountNo}-${template}.png?amount=${Math.round(amount)}&addInfo=${addInfo}&accountName=${accountName}`;
}

export function isBankAccountQrReady(bank: BankAccountForQr | null | undefined): boolean {
  if (!bank) return false;
  const bankId = (bank.bin || bank.code || '').trim();
  return Boolean(bankId && bank.accountNo?.trim() && bank.accountName?.trim());
}
