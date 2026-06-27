import { formatCurrency, formatDateTime } from './format';

export interface ReceiptItem {
  name: string;
  quantity: number;
  unitPrice: number;
  unit?: string;
}

export interface ReceiptData {
  id: string;
  createdAt: string;
  customerName: string;
  employeeName?: string | null;
  items: ReceiptItem[];
  discount: number;
  subtotal?: number;
  total: number;
  paidAmount: number;
  paymentType?: string;
}

/**
 * Draws the receipt onto a canvas element with thermal printer styling
 */
export function drawReceiptToCanvas(canvas: HTMLCanvasElement, order: ReceiptData) {
  const ctx = canvas.getContext('2d');
  if (!ctx) return;

  const width = 400;
  const padding = 20;
  let y = padding;

  const items = order.items || [];
  
  // Calculate dynamic heights
  const headerHeight = 70; // Title, subtitle, hotline
  const detailsHeight = 85 + (order.employeeName ? 20 : 0);
  const itemsHeaderHeight = 30;
  const itemsHeight = items.length * 35;
  const totalsHeight = 110 + (order.total - order.paidAmount > 0 ? 25 : 0);
  const footerHeight = 50;
  
  const totalHeight = padding * 2 + headerHeight + detailsHeight + itemsHeaderHeight + itemsHeight + totalsHeight + footerHeight;
  
  canvas.width = width;
  canvas.height = totalHeight;
  
  // Fill background with solid white
  ctx.fillStyle = '#FFFFFF';
  ctx.fillRect(0, 0, width, totalHeight);
  
  // Draw outer dashed/fine border
  ctx.strokeStyle = '#E4E4E7';
  ctx.lineWidth = 1;
  ctx.strokeRect(4, 4, width - 8, totalHeight - 8);

  ctx.fillStyle = '#000000';
  ctx.textAlign = 'center';
  
  // Title
  ctx.font = 'bold 18px Courier New, Courier, monospace';
  y += 24;
  ctx.fillText('MARKET VENDOR APPS', width / 2, y);
  
  // Subtitle
  ctx.font = '11px Courier New, Courier, monospace';
  ctx.fillStyle = '#52525B';
  y += 18;
  ctx.fillText('Đồng hành cùng tiểu thương Việt', width / 2, y);
  y += 16;
  ctx.fillText('ĐT: 0987.654.321', width / 2, y);
  
  // Separator line
  const drawDashedLine = (yPos: number) => {
    ctx.strokeStyle = '#71717A';
    ctx.lineWidth = 1;
    ctx.setLineDash([4, 4]);
    ctx.beginPath();
    ctx.moveTo(padding, yPos);
    ctx.lineTo(width - padding, yPos);
    ctx.stroke();
    ctx.setLineDash([]); // Reset
  };

  y += 16;
  drawDashedLine(y);
  
  // Details
  ctx.fillStyle = '#000000';
  ctx.textAlign = 'left';
  ctx.font = '12px Courier New, Courier, monospace';
  
  y += 22;
  ctx.fillText(`Số HĐ:      ${order.id.slice(-6).toUpperCase()}`, padding, y);
  y += 20;
  ctx.fillText(`Khách hàng: ${order.customerName}`, padding, y);
  
  if (order.employeeName) {
    y += 20;
    ctx.fillText(`Nhân viên:  ${order.employeeName}`, padding, y);
  }
  
  y += 20;
  ctx.fillText(`Ngày tạo:   ${formatDateTime(order.createdAt)}`, padding, y);
  
  y += 12;
  drawDashedLine(y);
  
  // Items Header
  ctx.font = 'bold 12px Courier New, Courier, monospace';
  y += 22;
  ctx.fillText('Tên SP', padding, y);
  ctx.textAlign = 'right';
  ctx.fillText('SL', width - padding - 130, y);
  ctx.fillText('T.Tiền', width - padding, y);
  
  // Draw Items
  ctx.font = '12px Courier New, Courier, monospace';
  items.forEach((item) => {
    y += 25;
    ctx.textAlign = 'left';
    
    // Truncate name if too long
    const maxNameLen = 20;
    let nameText = item.name;
    if (nameText.length > maxNameLen) {
      nameText = nameText.slice(0, maxNameLen - 3) + '...';
    }
    ctx.fillText(nameText, padding, y);
    
    ctx.textAlign = 'right';
    const qtyUnit = item.unit ? `${item.quantity} ${item.unit}` : `${item.quantity}`;
    ctx.fillText(qtyUnit, width - padding - 130, y);
    ctx.fillText(formatCurrency(item.unitPrice * item.quantity), width - padding, y);
  });
  
  y += 12;
  drawDashedLine(y);
  
  // Totals
  ctx.textAlign = 'left';
  ctx.font = '12px Courier New, Courier, monospace';
  
  y += 22;
  ctx.fillText('Tạm tính:', padding, y);
  ctx.textAlign = 'right';
  const subtotalVal = order.subtotal || (order.total + (order.discount || 0));
  ctx.fillText(formatCurrency(subtotalVal), width - padding, y);
  
  y += 20;
  ctx.textAlign = 'left';
  ctx.fillText('Giảm giá:', padding, y);
  ctx.textAlign = 'right';
  ctx.fillText(`-${formatCurrency(order.discount || 0)}`, width - padding, y);
  
  y += 24;
  ctx.textAlign = 'left';
  ctx.font = 'bold 14px Courier New, Courier, monospace';
  ctx.fillText('Tổng cộng:', padding, y);
  ctx.textAlign = 'right';
  ctx.fillText(formatCurrency(order.total), width - padding, y);
  
  y += 22;
  ctx.textAlign = 'left';
  ctx.font = '12px Courier New, Courier, monospace';
  ctx.fillText('Khách trả:', padding, y);
  ctx.textAlign = 'right';
  ctx.fillText(formatCurrency(order.paidAmount), width - padding, y);
  
  const debt = order.total - order.paidAmount;
  if (debt > 0) {
    y += 20;
    ctx.textAlign = 'left';
    ctx.font = 'bold 12px Courier New, Courier, monospace';
    ctx.fillStyle = '#DC2626'; // Red for debt
    ctx.fillText('Còn nợ:', padding, y);
    ctx.textAlign = 'right';
    ctx.fillText(formatCurrency(debt), width - padding, y);
    ctx.fillStyle = '#000000'; // Reset
  }
  
  y += 16;
  drawDashedLine(y);
  
  // Footer
  y += 28;
  ctx.fillStyle = '#71717A';
  ctx.textAlign = 'center';
  ctx.font = 'bold 11px Courier New, Courier, monospace';
  ctx.fillText('CẢM ƠN QUÝ KHÁCH & HẸN GẶP LẠI!', width / 2, y);
}

/**
 * Downloads the receipt image directly
 */
export function downloadReceiptImage(canvas: HTMLCanvasElement, filenameId: string) {
  try {
    const dataUrl = canvas.toDataURL('image/png');
    const link = document.createElement('a');
    link.download = `receipt-${filenameId.slice(-6).toUpperCase()}.png`;
    link.href = dataUrl;
    link.click();
  } catch (err) {
    console.error('Download receipt image failed', err);
    alert('Không thể tải ảnh hóa đơn xuống.');
  }
}

/**
 * Generates and shares or downloads the receipt
 */
export async function shareReceiptImage(order: ReceiptData): Promise<boolean> {
  // Create offscreen canvas
  const canvas = document.createElement('canvas');
  drawReceiptToCanvas(canvas, order);

  if (typeof navigator !== 'undefined' && navigator.share && navigator.canShare) {
    try {
      const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/png'));
      if (!blob) throw new Error('Blob generation failed');
      
      const file = new File([blob], `receipt-${order.id.slice(-6).toUpperCase()}.png`, { type: 'image/png' });
      
      if (navigator.canShare({ files: [file] })) {
        await navigator.share({
          files: [file],
          title: `Hóa đơn #${order.id.slice(-6).toUpperCase()}`,
          text: `Hóa đơn mua hàng từ Market Vendor Apps. Mã đơn: #${order.id.slice(-6).toUpperCase()}`
        });
        return true;
      } else {
        console.warn('Sharing this file type is not supported by the browser.');
      }
    } catch (err) {
      console.warn('Share API error, fallback to download', err);
    }
  }

  // Fallback download
  downloadReceiptImage(canvas, order.id);
  return false;
}
