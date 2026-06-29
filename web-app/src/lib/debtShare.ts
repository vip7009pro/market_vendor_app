import { formatCurrency, formatDateTime } from './format';

export interface DebtPayment {
  uuid: string;
  amount: number;
  note?: string;
  paymentType?: string;
  createdAt: string;
}

export interface DebtData {
  id: string;
  createdAt: string;
  type: number; // 1: Khách nợ tôi, 0: Tôi nợ NCC
  partyName: string;
  initialAmount: number;
  amount: number;
  description?: string;
  dueDate?: string;
  payments: DebtPayment[];
}

export interface LinkedOrderData {
  id: string;
  _orderType: 'sale' | 'purchase';
  items?: Array<{
    name?: string;
    productName?: string;
    unitPrice?: number;
    unitCost?: number;
    quantity: number;
    unit?: string;
  }>;
  total?: number;
  discount?: number;
  paidAmount?: number;
}

export interface StoreInfo {
  name?: string;
  phone?: string;
}

/**
 * Draws the debt report onto a canvas element
 */
export function drawDebtToCanvas(
  canvas: HTMLCanvasElement,
  debt: DebtData,
  linkedOrder?: LinkedOrderData | null,
  store?: StoreInfo | null
) {
  const ctx = canvas.getContext('2d');
  if (!ctx) return;

  const scale = 3;
  const width = 420;
  const padding = 20;
  let y = padding;

  const storeName = store?.name || 'MARKET VENDOR APPS';
  const storePhone = store?.phone || '0987.654.321';

  // Calculate dynamic heights
  const headerHeight = 70;
  const partnerDetailsHeight = 100 + (debt.dueDate ? 20 : 0) + (debt.description ? 20 : 0);
  
  let linkedOrderHeight = 0;
  if (linkedOrder) {
    linkedOrderHeight = 50 + (linkedOrder.items || []).length * 40 + 40; 
  }
  
  let paymentsHeight = 0;
  if (debt.payments && debt.payments.length > 0) {
    paymentsHeight = 40 + debt.payments.length * 35;
  }
  
  const totalsHeight = 110;
  const footerHeight = 40;
  
  const totalHeight = padding * 2 + headerHeight + partnerDetailsHeight + linkedOrderHeight + paymentsHeight + totalsHeight + footerHeight;
  
  canvas.width = width * scale;
  canvas.height = totalHeight * scale;
  
  ctx.scale(scale, scale);
  
  // Fill background
  ctx.fillStyle = '#FFFFFF';
  ctx.fillRect(0, 0, width, totalHeight);
  
  // Draw border
  ctx.strokeStyle = '#E4E4E7';
  ctx.lineWidth = 1;
  ctx.strokeRect(4, 4, width - 8, totalHeight - 8);

  ctx.fillStyle = '#000000';
  ctx.textAlign = 'center';
  
  // Title / Store Name
  ctx.font = 'bold 16px system-ui, -apple-system, sans-serif';
  y += 24;
  ctx.fillText(storeName.toUpperCase(), width / 2, y);
  
  // Subtitle
  ctx.font = '11px system-ui, -apple-system, sans-serif';
  ctx.fillStyle = '#52525B';
  y += 18;
  ctx.fillText('ĐT: ' + storePhone, width / 2, y);
  y += 16;
  ctx.font = 'bold 13px system-ui, -apple-system, sans-serif';
  ctx.fillStyle = '#000000';
  ctx.fillText('GIẤY XÁC NHẬN CÔNG NỢ', width / 2, y);
  
  // Dash line
  const drawDashedLine = (yPos: number) => {
    ctx.strokeStyle = '#A1A1AA';
    ctx.lineWidth = 1;
    ctx.setLineDash([4, 4]);
    ctx.beginPath();
    ctx.moveTo(padding, yPos);
    ctx.lineTo(width - padding, yPos);
    ctx.stroke();
    ctx.setLineDash([]);
  };

  y += 16;
  drawDashedLine(y);
  
  // Partner info
  ctx.fillStyle = '#000000';
  ctx.textAlign = 'left';
  ctx.font = '12px system-ui, -apple-system, sans-serif';
  
  y += 22;
  ctx.fillText(`Đối tác:    ${debt.partyName}`, padding, y);
  y += 20;
  const typeText = debt.type === 1 ? 'Khách nợ cửa hàng (Phải thu)' : 'Cửa hàng nợ nhà cung cấp (Phải trả)';
  ctx.fillText(`Loại nợ:    ${typeText}`, padding, y);
  y += 20;
  ctx.fillText(`Ngày ghi:   ${formatDateTime(debt.createdAt)}`, padding, y);
  
  if (debt.dueDate) {
    y += 20;
    ctx.fillText(`Hạn trả:    ${new Date(debt.dueDate).toLocaleDateString('vi-VN')}`, padding, y);
  }
  
  if (debt.description) {
    y += 20;
    ctx.fillText(`Nội dung:   ${debt.description}`, padding, y);
  }
  
  y += 12;
  drawDashedLine(y);
  
  // Linked order
  if (linkedOrder) {
    ctx.font = 'bold 12px system-ui, -apple-system, sans-serif';
    y += 22;
    const orderTitle = linkedOrder._orderType === 'sale' ? 'ĐƠN BÀNG HÀNG LIÊN KẾT' : 'ĐƠN NHẬP HÀNG LIÊN KẾT';
    ctx.fillText(`${orderTitle} (#${linkedOrder.id.slice(-6).toUpperCase()})`, padding, y);
    
    // Items table header
    ctx.font = 'bold 11.5px system-ui, -apple-system, sans-serif';
    y += 20;
    ctx.fillText('Chi tiết sản phẩm', padding, y);
    ctx.textAlign = 'right';
    ctx.fillText('Thành tiền', width - padding, y);
    
    // Items list
    const items = linkedOrder.items || [];
    items.forEach(it => {
      y += 22;
      ctx.textAlign = 'left';
      ctx.font = 'bold 12px system-ui, -apple-system, sans-serif';
      ctx.fillStyle = '#000000';
      const name = it.name || it.productName || '';
      const truncatedName = name.length > 34 ? name.slice(0, 31) + '...' : name;
      ctx.fillText(truncatedName, padding, y);
      
      y += 18;
      ctx.font = '11px system-ui, -apple-system, sans-serif';
      ctx.fillStyle = '#52525B';
      const qtyUnit = it.unit ? `${it.quantity} ${it.unit}` : `${it.quantity}`;
      const price = Number(it.unitPrice || it.unitCost || 0);
      ctx.fillText(`${qtyUnit} x ${formatCurrency(price)}`, padding, y);
      
      ctx.textAlign = 'right';
      ctx.fillStyle = '#000000';
      ctx.fillText(formatCurrency(price * it.quantity), width - padding, y);
    });
    
    // Order totals
    y += 22;
    ctx.textAlign = 'left';
    ctx.fillText('Tổng giá trị đơn:', padding, y);
    ctx.textAlign = 'right';
    const orderTotal = linkedOrder.total || items.reduce((sum, it) => sum + (Number(it.unitPrice || it.unitCost || 0) * it.quantity), 0) - (linkedOrder.discount || 0);
    ctx.fillText(formatCurrency(orderTotal), width - padding, y);
    
    y += 18;
    ctx.textAlign = 'left';
    ctx.fillText('Đã trả lúc mua:', padding, y);
    ctx.textAlign = 'right';
    ctx.fillText(formatCurrency(linkedOrder.paidAmount || 0), width - padding, y);
    
    y += 12;
    drawDashedLine(y);
  }
  
  // Payment history
  if (debt.payments && debt.payments.length > 0) {
    ctx.font = 'bold 12px system-ui, -apple-system, sans-serif';
    ctx.textAlign = 'left';
    y += 22;
    ctx.fillText('LỊCH SỬ THANH TOÁN NỢ', padding, y);
    
    ctx.font = '11px system-ui, -apple-system, sans-serif';
    debt.payments.forEach((p, idx) => {
      y += 22;
      ctx.textAlign = 'left';
      ctx.fillText(`${idx + 1}. ${new Date(p.createdAt).toLocaleDateString('vi-VN')}`, padding, y);
      ctx.textAlign = 'right';
      ctx.fillText(formatCurrency(p.amount), width - padding, y);
      
      if (p.note) {
        y += 13;
        ctx.textAlign = 'left';
        ctx.fillStyle = '#71717A';
        ctx.fillText(`   Ghi chú: ${p.note}`, padding, y);
        ctx.fillStyle = '#000000';
      }
    });
    
    y += 12;
    drawDashedLine(y);
  }
  
  // Financial Totals
  ctx.textAlign = 'left';
  ctx.font = '12px system-ui, -apple-system, sans-serif';
  
  y += 22;
  ctx.fillText('Tổng nợ ban đầu:', padding, y);
  ctx.textAlign = 'right';
  ctx.fillText(formatCurrency(debt.initialAmount), width - padding, y);
  
  y += 20;
  ctx.textAlign = 'left';
  ctx.fillText('Đã trả:', padding, y);
  ctx.textAlign = 'right';
  ctx.fillText(formatCurrency(Math.max(0, debt.initialAmount - debt.amount)), width - padding, y);
  
  y += 24;
  ctx.textAlign = 'left';
  ctx.font = 'bold 13px system-ui, -apple-system, sans-serif';
  ctx.fillText('NỢ CÒN LẠI:', padding, y);
  ctx.textAlign = 'right';
  ctx.fillStyle = debt.type === 1 ? '#DC2626' : '#2563EB'; // Red for receivable, blue for payable
  ctx.fillText(formatCurrency(debt.amount), width - padding, y);
  ctx.fillStyle = '#000000';
  
  y += 16;
  drawDashedLine(y);
  
  // Footer
  y += 26;
  ctx.fillStyle = '#71717A';
  ctx.textAlign = 'center';
  ctx.font = 'italic 11px system-ui, -apple-system, sans-serif';
  ctx.fillText('Quý khách vui lòng thanh toán đúng hạn. Xin cảm ơn!', width / 2, y);
}

/**
 * Downloads the canvas as PNG
 */
export function downloadDebtImage(canvas: HTMLCanvasElement, filenameId: string) {
  try {
    const dataUrl = canvas.toDataURL('image/png');
    const link = document.createElement('a');
    link.download = `cong-no-${filenameId.slice(-6).toUpperCase()}.png`;
    link.href = dataUrl;
    link.click();
  } catch (err) {
    console.error('Download debt image failed', err);
    alert('Không thể tải ảnh công nợ xuống.');
  }
}

/**
 * Generates and shares or downloads the debt card
 */
export async function shareDebtImage(
  debt: DebtData,
  linkedOrder?: LinkedOrderData | null,
  store?: StoreInfo | null
): Promise<boolean> {
  const canvas = document.createElement('canvas');
  drawDebtToCanvas(canvas, debt, linkedOrder, store);

  if (typeof navigator !== 'undefined' && navigator.share && navigator.canShare) {
    try {
      const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/png'));
      if (!blob) throw new Error('Blob generation failed');
      
      const file = new File([blob], `cong-no-${debt.id.slice(-6).toUpperCase()}.png`, { type: 'image/png' });
      
      if (navigator.canShare({ files: [file] })) {
        await navigator.share({
          files: [file],
          title: `Công nợ đối tác: ${debt.partyName}`,
          text: `Thông tin công nợ đối tác ${debt.partyName}. Còn nợ: ${formatCurrency(debt.amount)}.`
        });
        return true;
      }
    } catch (err) {
      console.warn('Share API error, fallback to download', err);
    }
  }

  // Fallback download
  downloadDebtImage(canvas, debt.id);
  return false;
}
