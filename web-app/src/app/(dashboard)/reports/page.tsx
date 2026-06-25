'use client';

import React, { useEffect, useState } from 'react';
import api from '@/lib/api';

interface Employee {
  id: string;
  name: string;
}

interface Product {
  id: string;
  name: string;
  unit: string;
  barcode?: string;
  price: number;
  costPrice: number;
  currentStock: number;
  isActive: boolean;
  itemType: 'RAW' | 'MIX';
  updatedAt?: string;
  deviceId?: string;
  isSynced?: boolean;
}

interface Customer {
  id: string;
  name: string;
  phone?: string;
  note?: string;
  isSupplier: boolean;
  updatedAt?: string;
  deviceId?: string;
  isSynced?: boolean;
}

interface DebtPayment {
  paymentId?: string;
  id?: string;
  debtId: string;
  debtType?: string;
  partyId?: string;
  partyName?: string;
  amount: number;
  paymentType: string;
  note?: string;
  createdAt: string;
  isSynced?: boolean;
}

interface Debt {
  id: string;
  customerId?: string;
  customerName?: string;
  partyId?: string;
  partyName?: string;
  initialAmount: number;
  amount: number; // remain
  createdAt: string;
  dueDate?: string;
  note?: string;
  isPaid: boolean;
  paidAt?: string;
  updatedAt?: string;
  sourceType?: string;
  sourceId?: string;
  payments?: DebtPayment[];
}

interface Expense {
  id: string;
  occurredAt: string;
  amount: number;
  category: string;
  note?: string;
  expenseDocUploaded?: boolean;
  expenseDocFileId?: string;
  expenseDocUpdatedAt?: string;
  updatedAt?: string;
}

interface PurchaseItem {
  productId: string;
  productName: string;
  quantity: number;
  unitCost: number;
  totalCost: number;
}

interface PurchaseOrder {
  id: string;
  createdAt: string;
  supplierName: string;
  supplierPhone?: string;
  note?: string;
  totalCost: number;
  updatedAt?: string;
  items?: PurchaseItem[];
}

interface SaleItem {
  productId: string;
  name: string;
  unitPrice: number;
  unitCost: number;
  quantity: number;
  unit: string;
  itemType: string;
  displayName?: string;
  mixItemsJson?: string;
}

interface Sale {
  id: string;
  createdAt: string;
  customerId?: string;
  customerName?: string;
  employeeId?: string;
  employeeName?: string;
  discount: number;
  paidAmount: number;
  paymentType: string;
  totalCost: number;
  note?: string;
  items: SaleItem[];
}

interface DashboardKpiData {
  totalRevenue: number;
  totalDiscount: number;
  netRevenue: number;
  totalCost: number;
  grossProfit: number;
  cashRevenue: number;
  bankRevenue: number;
  outstandingDebt: number;
  totalExpenses: number;
  expenseReasonable: number;
  expenseOutsideBusiness: number;
  totalOwe: number;
  totalOwed: number;
  netProfit: number;
  cashPaid: number;
  bankPaid: number;
  productCount: number;
  customerCount: number;
  saleCount: number;
}

interface TopProduct {
  name: string;
  unit: string;
  quantity: number;
  totalRev: number;
}

interface ExpenseRatio {
  category: string;
  amount: number;
  percentage: number;
}

interface RevenueChartItem {
  date: string;
  revenue: number;
  cost: number;
  count: number;
  profit: number;
  expenses: number;
  netProfit: number;
}

export default function ReportsPage() {
  const [startDate, setStartDate] = useState<string>(() => {
    const d = new Date();
    return new Date(d.getFullYear(), d.getMonth(), 1).toISOString().split('T')[0];
  });
  const [endDate, setEndDate] = useState<string>(() => {
    return new Date().toISOString().split('T')[0];
  });
  const [selectedEmployeeId, setSelectedEmployeeId] = useState<string>('');
  const [employees, setEmployees] = useState<Employee[]>([]);

  // Chart aggregation
  const [groupBy, setGroupBy] = useState<'day' | 'month' | 'year'>('day');

  // API Data
  const [kpis, setKpis] = useState<DashboardKpiData | null>(null);
  const [topProducts, setTopProducts] = useState<TopProduct[]>([]);
  const [expenseRatios, setExpenseRatios] = useState<ExpenseRatio[]>([]);
  const [revenueData, setRevenueData] = useState<RevenueChartItem[]>([]);
  
  const [loading, setLoading] = useState(true);
  const [exporting, setExporting] = useState(false);

  // Active chart hover tooltip index
  const [hoveredChartIdx, setHoveredChartIdx] = useState<number | null>(null);
  const [hoveredPieIdx, setHoveredPieIdx] = useState<number | null>(null);

  useEffect(() => {
    // Load employee list
    api.getEmployees().then(setEmployees).catch(() => {});
  }, []);

  const fetchData = async () => {
    try {
      setLoading(true);
      const params = {
        startDate,
        endDate,
        ...(selectedEmployeeId && { employeeId: selectedEmployeeId }),
      };

      const [kpiRes, topRes, ratioRes, revRes] = await Promise.all([
        api.getDashboard(params),
        api.fetch<TopProduct[]>(`/api/reports/top-products?startDate=${startDate}&endDate=${endDate}${selectedEmployeeId ? `&employeeId=${selectedEmployeeId}` : ''}`),
        api.fetch<ExpenseRatio[]>(`/api/reports/expenses-ratio?startDate=${startDate}&endDate=${endDate}`),
        api.getRevenueReport({ ...params, groupBy }),
      ]);

      if (kpiRes) setKpis(kpiRes);
      if (topRes) setTopProducts(topRes);
      if (ratioRes) setExpenseRatios(ratioRes);
      if (revRes) setRevenueData(revRes);
    } catch (err) {
      console.error('Failed to load report data:', err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, [startDate, endDate, selectedEmployeeId, groupBy]);

  const formatCurrency = (val: number) => {
    return new Intl.NumberFormat('vi-VN', { style: 'currency', currency: 'VND' }).format(val);
  };

  // XML spreadsheet helpers
  const cleanXml = (val: any) => {
    if (val === null || val === undefined) return '';
    return String(val)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&apos;');
  };

  const xmlCell = (val: any, type: 'String' | 'Number' = 'String') => {
    return `<Cell><Data ss:Type="${type}">${cleanXml(val)}</Data></Cell>`;
  };

  const exportAllSheetsExcel = async () => {
    try {
      setExporting(true);
      
      const params = {
        startDate,
        endDate,
      };

      // Fetch all tables for details (we grab full tables to perform client-side matching)
      const [
        customers,
        products,
        debts,
        expenses,
        sales,
        purchasesHistory,
        purchasesOrders,
      ] = await Promise.all([
        api.getCustomers().catch(() => []),
        api.getProducts().catch(() => []),
        api.getDebts().catch(() => []),
        api.getExpenses(params).catch(() => []),
        api.getSales(params).catch(() => []),
        api.getPurchaseHistory(params).catch(() => []),
        api.getPurchases().catch(() => []),
      ]);

      // Parse opening stocks month and year
      const startD = new Date(startDate);
      const year = startD.getFullYear();
      const month = startD.getMonth() + 1;
      
      const openingStocks = await api.getOpeningStocks(year, month).catch(() => []);

      // Index tables
      const productsById: Record<string, Product> = {};
      products.forEach((p: Product) => { productsById[p.id] = p; });

      // Gather debt payments
      const debtPayments: DebtPayment[] = [];
      const debtPaidById: Record<string, number> = {};
      const debtSourceById: Record<string, { sourceType?: string; sourceId?: string }> = {};

      debts.forEach((d: Debt) => {
        debtPaidById[d.id] = 0;
        debtSourceById[d.id] = { sourceType: d.sourceType, sourceId: d.sourceId };
        if (d.payments) {
          d.payments.forEach(p => {
            const amt = Number(p.amount);
            debtPaidById[d.id] = (debtPaidById[d.id] || 0) + amt;
            
            // Check date bounds for historical list
            const payDate = new Date(p.createdAt);
            if (payDate >= new Date(startDate) && payDate <= new Date(endDate + 'T23:59:59')) {
              debtPayments.push({
                ...p,
                partyId: d.customerId || d.partyId,
                partyName: d.customerName || d.partyName,
                debtType: d.sourceType === 'sale' ? 'Khách nợ' : 'Nợ NCC',
              });
            }
          });
        }
      });

      // Calculate Opening, Import and Export stock within month
      const monthStart = new Date(year, month - 1, 1);
      const monthEnd = new Date(year, month, 0, 23, 59, 59, 999);

      const openingByProductId: Record<string, number> = {};
      openingStocks.forEach((op: any) => {
        openingByProductId[op.productId] = Number(op.openingStock || 0);
      });

      const importQtyByProductId: Record<string, number> = {};
      purchasesHistory.forEach((ph: any) => {
        const d = new Date(ph.createdAt);
        if (d >= monthStart && d <= monthEnd) {
          const pid = ph.productId;
          importQtyByProductId[pid] = (importQtyByProductId[pid] || 0) + Number(ph.quantity || 0);
        }
      });

      const exportQtyByProductId: Record<string, number> = {};
      // Calculate export quantities including MIX decomposition
      sales.forEach((s: Sale) => {
        const d = new Date(s.createdAt);
        if (d >= monthStart && d <= monthEnd) {
          s.items.forEach((it: SaleItem) => {
            if (it.itemType === 'MIX') {
              if (it.mixItemsJson) {
                try {
                  const mixItems = JSON.parse(it.mixItemsJson);
                  if (Array.isArray(mixItems)) {
                    mixItems.forEach((m: any) => {
                      const rq = Number(m.rawQty || 0) * Number(it.quantity || 1);
                      if (rq > 0) {
                        exportQtyByProductId[m.rawProductId] = (exportQtyByProductId[m.rawProductId] || 0) + rq;
                      }
                    });
                  }
                } catch (_) {}
              }
            } else {
              exportQtyByProductId[it.productId] = (exportQtyByProductId[it.productId] || 0) + Number(it.quantity || 0);
            }
          });
        }
      });

      // Build XML sheets
      let xml = `<?xml version="1.0"?>
<?mso-application progid="Excel.Sheet"?>
<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"
 xmlns:o="urn:schemas-microsoft-com:office:office"
 xmlns:x="urn:schemas-microsoft-com:office:excel"
 xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet"
 xmlns:html="http://www.w3.org/TR/REC-html40">
 <Styles>
  <Style ss:ID="Header">
   <Font ss:FontName="Arial" ss:Bold="1" ss:Color="#FFFFFF"/>
   <Interior ss:Color="#4F46E5" ss:Pattern="Solid"/>
  </Style>
  <Style ss:ID="Total">
   <Font ss:FontName="Arial" ss:Bold="1"/>
   <Interior ss:Color="#F1F5F9" ss:Pattern="Solid"/>
  </Style>
 </Styles>`;

      // ─── 1. SHEET CUSTOMERS ─────────────────────────────
      xml += `\n <Worksheet ss:Name="list khách hàng">
  <Table>
   <Row ss:StyleID="Header">
    ${xmlCell('ID')}${xmlCell('Tên')}${xmlCell('Số điện thoại')}${xmlCell('Ghi chú')}${xmlCell('Là nhà cung cấp')}${xmlCell('Ngày cập nhật')}
   </Row>`;
      customers.forEach((c: Customer) => {
        xml += `\n   <Row>
    ${xmlCell(c.id)}${xmlCell(c.name)}${xmlCell(c.phone || '')}${xmlCell(c.note || '')}${xmlCell(c.isSupplier ? 'Đúng' : 'Không')}${xmlCell(c.updatedAt || '')}
   </Row>`;
      });
      xml += `\n  </Table>
 </Worksheet>`;

      // ─── 2. SHEET PRODUCTS ──────────────────────────────
      xml += `\n <Worksheet ss:Name="list sản phẩm">
  <Table>
   <Row ss:StyleID="Header">
    ${xmlCell('ID')}${xmlCell('Tên sản phẩm')}${xmlCell('Đơn vị')}${xmlCell('Mã vạch')}${xmlCell('Giá bán')}${xmlCell('Giá vốn')}${xmlCell('Tồn kho')}${xmlCell('Hoạt động')}${xmlCell('Phân loại')}
   </Row>`;
      products.forEach((p: Product) => {
        xml += `\n   <Row>
    ${xmlCell(p.id)}${xmlCell(p.name)}${xmlCell(p.unit)}${xmlCell(p.barcode || '')}${xmlCell(p.price, 'Number')}${xmlCell(p.costPrice, 'Number')}${xmlCell(p.currentStock, 'Number')}${xmlCell(p.isActive ? 'Đang bán' : 'Ngừng bán')}${xmlCell(p.itemType)}
   </Row>`;
      });
      xml += `\n  </Table>
 </Worksheet>`;

      // ─── 3. SHEET DEBTS ─────────────────────────────────
      xml += `\n <Worksheet ss:Name="list công nợ">
  <Table>
   <Row ss:StyleID="Header">
    ${xmlCell('Mã công nợ')}${xmlCell('Tên khách/Đối tác')}${xmlCell('Số nợ ban đầu')}${xmlCell('Đã trả')}${xmlCell('Còn lại')}${xmlCell('Ngày nợ')}${xmlCell('Hạn trả')}${xmlCell('Nguồn gốc')}${xmlCell('Trạng thái')}
   </Row>`;
      let sumInitial = 0;
      let sumPaid = 0;
      let sumRemain = 0;
      debts.forEach((d: Debt) => {
        const initial = Number(d.initialAmount || d.amount || 0);
        const paid = debtPaidById[d.id] || 0;
        const remain = Number(d.amount || 0);

        sumInitial += initial;
        sumPaid += paid;
        sumRemain += remain;

        xml += `\n   <Row>
    ${xmlCell(d.id)}${xmlCell(d.customerName || d.partyName || 'Khách lẻ')}${xmlCell(initial, 'Number')}${xmlCell(paid, 'Number')}${xmlCell(remain, 'Number')}${xmlCell(d.createdAt)}${xmlCell(d.dueDate || '')}${xmlCell(d.sourceType ? `${d.sourceType} (${d.sourceId})` : 'Tự ghi nợ')}${xmlCell(d.isPaid ? 'Đã thanh toán' : 'Chưa trả')}
   </Row>`;
      });
      // Append Total Row
      xml += `\n   <Row ss:StyleID="Total">
    ${xmlCell('')}${xmlCell('TỔNG')}${xmlCell(sumInitial, 'Number')}${xmlCell(sumPaid, 'Number')}${xmlCell(sumRemain, 'Number')}${xmlCell('')}${xmlCell('')}${xmlCell('')}${xmlCell('')}
   </Row>`;
      xml += `\n  </Table>
 </Worksheet>`;

      // ─── 4. SHEET DEBT PAYMENTS ────────────────────────
      xml += `\n <Worksheet ss:Name="lịch sử trả nợ">
  <Table>
   <Row ss:StyleID="Header">
    ${xmlCell('Mã thanh toán')}${xmlCell('Mã công nợ')}${xmlCell('Loại công nợ')}${xmlCell('Tên đối tác')}${xmlCell('Số tiền trả')}${xmlCell('Phương thức')}${xmlCell('Ghi chú')}${xmlCell('Ngày trả')}
   </Row>`;
      debtPayments.forEach((p: DebtPayment) => {
        xml += `\n   <Row>
    ${xmlCell(p.id || p.paymentId || '')}${xmlCell(p.debtId)}${xmlCell(p.debtType || '')}${xmlCell(p.partyName || 'Khách lẻ')}${xmlCell(p.amount, 'Number')}${xmlCell(p.paymentType)}${xmlCell(p.note || '')}${xmlCell(p.createdAt)}
   </Row>`;
      });
      xml += `\n  </Table>
 </Worksheet>`;

      // ─── 5. SHEET EXPENSES ─────────────────────────────
      xml += `\n <Worksheet ss:Name="list chi phí">
  <Table>
   <Row ss:StyleID="Header">
    ${xmlCell('Mã chi phí')}${xmlCell('Ngày chi')}${xmlCell('Số tiền')}${xmlCell('Danh mục')}${xmlCell('Ghi chú')}
   </Row>`;
      expenses.forEach((e: Expense) => {
        xml += `\n   <Row>
    ${xmlCell(e.id)}${xmlCell(e.occurredAt)}${xmlCell(e.amount, 'Number')}${xmlCell(e.category)}${xmlCell(e.note || '')}
   </Row>`;
      });
      xml += `\n  </Table>
 </Worksheet>`;

      // ─── 6. SHEET PURCHASE HISTORY ─────────────────────
      xml += `\n <Worksheet ss:Name="lịch sử nhập kho">
  <Table>
   <Row ss:StyleID="Header">
    ${xmlCell('Mã nhập')}${xmlCell('Ngày nhập')}${xmlCell('Mã SP')}${xmlCell('Tên sản phẩm')}${xmlCell('Số lượng')}${xmlCell('Đơn giá vốn')}${xmlCell('Thành tiền')}${xmlCell('Nhà cung cấp')}${xmlCell('Ghi chú')}
   </Row>`;
      purchasesHistory.forEach((ph: any) => {
        xml += `\n   <Row>
    ${xmlCell(ph.id)}${xmlCell(ph.createdAt)}${xmlCell(ph.productId)}${xmlCell(ph.productName)}${xmlCell(ph.quantity, 'Number')}${xmlCell(ph.unitCost, 'Number')}${xmlCell(ph.totalCost, 'Number')}${xmlCell(ph.supplierName || 'NCC vãng lai')}${xmlCell(ph.note || '')}
   </Row>`;
      });
      xml += `\n  </Table>
 </Worksheet>`;

      // ─── 7. SHEET EXPORT HISTORY ─────────────────────
      xml += `\n <Worksheet ss:Name="lịch sử xuất kho">
  <Table>
   <Row ss:StyleID="Header">
    ${xmlCell('Mã đơn hàng')}${xmlCell('Ngày xuất')}${xmlCell('Tên khách')}${xmlCell('Nhân viên')}${xmlCell('Mã SP')}${xmlCell('Tên sản phẩm')}${xmlCell('Đơn vị')}${xmlCell('Số lượng')}${xmlCell('Đơn giá bán')}${xmlCell('Doanh thu')}${xmlCell('Giá vốn')}${xmlCell('Tổng vốn')}${xmlCell('Phân loại')}
   </Row>`;
      sales.forEach((s: Sale) => {
        s.items.forEach((it: SaleItem) => {
          if (it.itemType === 'MIX' && it.mixItemsJson) {
            try {
              const mixItems = JSON.parse(it.mixItemsJson);
              if (Array.isArray(mixItems)) {
                // Decompose MIX to RAW products snapped
                const mixQty = Number(it.quantity || 1);
                const mixPrice = Number(it.unitPrice || 0);
                
                let rawSellTotal = 0;
                mixItems.forEach((m: any) => {
                  const rawP = productsById[m.rawProductId];
                  rawSellTotal += Number(m.rawQty || 0) * (rawP?.price || 0);
                });

                const factor = rawSellTotal <= 0 ? 0 : (mixPrice * mixQty) / rawSellTotal;

                mixItems.forEach((m: any) => {
                  const rawP = productsById[m.rawProductId];
                  const rawPrice = rawP?.price || 0;
                  const unitPriceSnap = rawPrice * factor;
                  const lineTotalSnap = unitPriceSnap * Number(m.rawQty || 0);
                  const lineCostTotalSnap = Number(m.rawUnitCost || 0) * Number(m.rawQty || 0);

                  xml += `\n   <Row>
    ${xmlCell(s.id)}${xmlCell(s.createdAt)}${xmlCell(s.customerName || 'Khách vãng lai')}${xmlCell(s.employeeName || '')}${xmlCell(m.rawProductId)}${xmlCell(m.rawName)}${xmlCell(m.rawUnit)}${xmlCell(Number(m.rawQty || 0) * mixQty, 'Number')}${xmlCell(unitPriceSnap, 'Number')}${xmlCell(lineTotalSnap * mixQty, 'Number')}${xmlCell(m.rawUnitCost, 'Number')}${xmlCell(lineCostTotalSnap * mixQty, 'Number')}${xmlCell('MIX-DECOMPOSED')}
   </Row>`;
                });
              }
            } catch (_) {}
          } else {
            const qty = Number(it.quantity || 0);
            const price = Number(it.unitPrice || 0);
            const cost = Number(it.unitCost || 0);
            xml += `\n   <Row>
    ${xmlCell(s.id)}${xmlCell(s.createdAt)}${xmlCell(s.customerName || 'Khách vãng lai')}${xmlCell(s.employeeName || '')}${xmlCell(it.productId)}${xmlCell(it.name)}${xmlCell(it.unit)}${xmlCell(qty, 'Number')}${xmlCell(price, 'Number')}${xmlCell(qty * price, 'Number')}${xmlCell(cost, 'Number')}${xmlCell(qty * cost, 'Number')}${xmlCell('RAW')}
   </Row>`;
          }
        });
      });
      xml += `\n  </Table>
 </Worksheet>`;

      // ─── 8. SHEET LIST ORDER SALES ────────────────────
      xml += `\n <Worksheet ss:Name="list đơn hàng">
  <Table>
   <Row ss:StyleID="Header">
    ${xmlCell('Mã đơn hàng')}${xmlCell('Ngày bán')}${xmlCell('Khách hàng')}${xmlCell('Nhân viên')}${xmlCell('Doanh thu gộp')}${xmlCell('Giảm giá')}${xmlCell('Doanh thu thuần')}${xmlCell('Tổng vốn')}${xmlCell('Đã trả ban đầu')}${xmlCell('Còn nợ')}${xmlCell('Phương thức')}${xmlCell('Ghi chú')}
   </Row>`;
      sales.forEach((s: Sale) => {
        const subtotal = s.items.reduce((sum, item) => sum + (Number(item.unitPrice) * Number(item.quantity)), 0);
        const discount = Number(s.discount || 0);
        const net = subtotal - discount;
        const remainDebt = Math.max(0, net - Number(s.paidAmount || 0));

        xml += `\n   <Row>
    ${xmlCell(s.id)}${xmlCell(s.createdAt)}${xmlCell(s.customerName || 'Khách lẻ')}${xmlCell(s.employeeName || '')}${xmlCell(subtotal, 'Number')}${xmlCell(discount, 'Number')}${xmlCell(net, 'Number')}${xmlCell(s.totalCost, 'Number')}${xmlCell(s.paidAmount, 'Number')}${xmlCell(remainDebt, 'Number')}${xmlCell(s.paymentType)}${xmlCell(s.note || '')}
   </Row>`;
      });
      xml += `\n  </Table>
 </Worksheet>`;

      // ─── 9. SHEET OPENING STOCK ──────────────────────
      xml += `\n <Worksheet ss:Name="list tồn đầu kỳ">
  <Table>
   <Row ss:StyleID="Header">
    ${xmlCell('Năm')}${xmlCell('Tháng')}${xmlCell('Mã sản phẩm')}${xmlCell('Tên sản phẩm')}${xmlCell('Đơn vị')}${xmlCell('Số lượng tồn đầu')}
   </Row>`;
      products.forEach((p: Product) => {
        const opStock = openingByProductId[p.id] || 0;
        xml += `\n   <Row>
    ${xmlCell(year, 'Number')}${xmlCell(month, 'Number')}${xmlCell(p.id)}${xmlCell(p.name)}${xmlCell(p.unit)}${xmlCell(opStock, 'Number')}
   </Row>`;
      });
      xml += `\n  </Table>
 </Worksheet>`;

      // ─── 10. SHEET CLOSING STOCK ─────────────────────
      xml += `\n <Worksheet ss:Name="list tồn cuối kỳ">
  <Table>
   <Row ss:StyleID="Header">
    ${xmlCell('Năm')}${xmlCell('Tháng')}${xmlCell('Mã SP')}${xmlCell('Tên sản phẩm')}${xmlCell('Đơn vị')}${xmlCell('Tồn đầu')}${xmlCell('Nhập trong kỳ')}${xmlCell('Xuất trong kỳ')}${xmlCell('Tồn cuối')}${xmlCell('Giá vốn')}${xmlCell('Trị giá tồn (vốn)')}${xmlCell('Giá bán')}${xmlCell('Trị giá tồn (bán)')}
   </Row>`;
      products.forEach((p: Product) => {
        const opStock = openingByProductId[p.id] || 0;
        const imp = importQtyByProductId[p.id] || 0;
        const exp = exportQtyByProductId[p.id] || 0;
        const ending = opStock + imp - exp;

        xml += `\n   <Row>
    ${xmlCell(year, 'Number')}${xmlCell(month, 'Number')}${xmlCell(p.id)}${xmlCell(p.name)}${xmlCell(p.unit)}${xmlCell(opStock, 'Number')}${xmlCell(imp, 'Number')}${xmlCell(exp, 'Number')}${xmlCell(ending, 'Number')}${xmlCell(p.costPrice, 'Number')}${xmlCell(ending * p.costPrice, 'Number')}${xmlCell(p.price, 'Number')}${xmlCell(ending * p.price, 'Number')}
   </Row>`;
      });
      xml += `\n  </Table>
 </Worksheet>`;

      // Close Excel File XML structure
      xml += `\n</Workbook>`;

      // Trigger download
      const blob = new Blob([xml], { type: 'application/vnd.ms-excel;charset=utf-8;' });
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      const ts = new Date().toISOString().replace(/[-:T.]/g, '').slice(0, 14);
      link.setAttribute("href", url);
      link.setAttribute("download", `bao_cao_tong_hop_${ts}.xls`);
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
    } catch (err) {
      alert('Có lỗi xảy ra khi xuất Excel: ' + (err instanceof Error ? err.message : String(err)));
    } finally {
      setExporting(false);
    }
  };

  // Pie chart calculation helper
  const drawPieChart = () => {
    if (expenseRatios.length === 0) {
      return (
        <div className="h-full flex items-center justify-center text-slate-500 text-xs">
          Không có dữ liệu chi phí hợp lý để vẽ biểu đồ
        </div>
      );
    }

    const R = 75;
    let cumulativePercent = 0;

    const slices = expenseRatios.map((item, idx) => {
      const startPercent = cumulativePercent;
      cumulativePercent += item.percentage / 100;
      const endPercent = cumulativePercent;

      // Calculate circle coordinates
      // Offset by -90deg (or -0.25 percent) to start drawing from the top
      const getCoords = (p: number) => {
        const angle = 2 * Math.PI * (p - 0.25);
        return [Math.cos(angle) * R, Math.sin(angle) * R];
      };

      const [sx, sy] = getCoords(startPercent);
      const [ex, ey] = getCoords(endPercent);

      const largeArc = item.percentage > 50 ? 1 : 0;
      const path = `M 0 0 L ${sx} ${sy} A ${R} ${R} 0 ${largeArc} 1 ${ex} ${ey} Z`;

      // HSL Colors spread
      const color = `hsl(${(idx * (360 / expenseRatios.length)) % 360}, 75%, 55%)`;

      return {
        path,
        color,
        category: item.category,
        percentage: item.percentage,
        amount: item.amount,
      };
    });

    return (
      <div className="flex flex-col sm:flex-row items-center gap-6">
        {/* SVG Circle */}
        <div className="relative w-44 h-44 shrink-0">
          <svg viewBox="-90 -90 180 180" className="w-full h-full transform -rotate-90">
            {slices.map((s, idx) => (
              <path
                key={idx}
                d={s.path}
                fill={s.color}
                className="transition-all duration-300 hover:opacity-90 cursor-pointer origin-center hover:scale-105"
                onMouseEnter={() => setHoveredPieIdx(idx)}
                onMouseLeave={() => setHoveredPieIdx(null)}
              />
            ))}
          </svg>

          {/* Interactive Tooltip in center */}
          <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none text-center p-4 bg-slate-950/20 rounded-full backdrop-blur-[1px]">
            {hoveredPieIdx !== null ? (
              <>
                <span className="text-[10px] text-slate-400 truncate max-w-[120px] font-bold">{expenseRatios[hoveredPieIdx].category}</span>
                <span className="text-xs font-bold text-white mt-0.5">{expenseRatios[hoveredPieIdx].percentage.toFixed(1)}%</span>
                <span className="text-[9px] text-slate-500 mt-0.5">{formatCurrency(expenseRatios[hoveredPieIdx].amount)}</span>
              </>
            ) : (
              <>
                <span className="text-[10px] text-slate-500 font-semibold">Tổng chi phí</span>
                <span className="text-xs font-extrabold text-indigo-300 mt-0.5">
                  {formatCurrency(kpis?.expenseReasonable || 0)}
                </span>
              </>
            )}
          </div>
        </div>

        {/* Legend */}
        <div className="flex-1 space-y-2 text-xs w-full max-h-48 overflow-y-auto pr-1">
          {slices.map((s, idx) => (
            <div
              key={idx}
              className={`flex items-center justify-between p-1.5 rounded-lg transition-all ${
                hoveredPieIdx === idx ? 'bg-slate-800/40 border-l-2 border-indigo-500 pl-2' : ''
              }`}
              onMouseEnter={() => setHoveredPieIdx(idx)}
              onMouseLeave={() => setHoveredPieIdx(null)}
            >
              <div className="flex items-center gap-2 min-w-0">
                <span className="w-2.5 h-2.5 rounded shrink-0" style={{ backgroundColor: s.color }}></span>
                <span className="text-slate-300 truncate font-medium">{s.category}</span>
              </div>
              <span className="font-semibold text-slate-400 text-[10px] shrink-0">
                {formatCurrency(s.amount)} ({s.percentage.toFixed(1)}%)
              </span>
            </div>
          ))}
        </div>
      </div>
    );
  };

  // SVG Bar/Line Chart details
  const drawBarLineChart = () => {
    if (revenueData.length === 0) {
      return (
        <div className="h-64 flex items-center justify-center text-slate-500 text-xs">
          Không có dữ liệu giao dịch trong khoảng thời gian này
        </div>
      );
    }

    const W = 620;
    const H = 280;
    const margin = { top: 20, right: 30, bottom: 40, left: 65 };

    const innerW = W - margin.left - margin.right;
    const innerH = H - margin.top - margin.bottom;

    // Find min and max for scaling
    const vals = revenueData.flatMap(d => [d.revenue, d.profit, d.netProfit, 0]);
    let maxY = Math.max(...vals, 100000);
    let minY = Math.min(...vals, 0);

    const diff = maxY - minY;
    maxY += diff * 0.05;
    minY -= diff * 0.05;
    if (minY > 0) minY = 0;

    const getY = (val: number) => {
      const r = (val - minY) / (maxY - minY);
      return margin.top + innerH * (1 - r);
    };

    const bandW = innerW / revenueData.length;
    const getX = (idx: number) => {
      return margin.left + idx * bandW + bandW / 2;
    };

    const y0 = getY(0);

    // Format dates for chart labels
    const formatLabel = (dateStr: string) => {
      if (groupBy === 'year') return dateStr;
      if (groupBy === 'month') {
        const parts = dateStr.split('-');
        return parts.length >= 2 ? `${parts[1]}/${parts[0]}` : dateStr;
      }
      // Day
      const parts = dateStr.split('-');
      return parts.length >= 3 ? `${parts[2]}/${parts[1]}` : dateStr;
    };

    // Construct Line Path for netProfit
    const linePathPoints = revenueData.map((d, idx) => {
      return `${getX(idx)},${getY(d.netProfit)}`;
    });
    const lineD = linePathPoints.length > 1 ? `M ${linePathPoints.join(' L ')}` : '';

    return (
      <div className="relative w-full overflow-x-auto">
        <svg viewBox={`0 0 ${W} ${H}`} className="w-full min-w-[550px] overflow-visible">
          {/* Horizontal Grid lines */}
          {[0, 0.25, 0.5, 0.75, 1].map((r, i) => {
            const gridVal = minY + (maxY - minY) * r;
            const y = getY(gridVal);
            return (
              <g key={i} className="opacity-40">
                <line
                  x1={margin.left}
                  y1={y}
                  x2={W - margin.right}
                  y2={y}
                  stroke="var(--color-border)"
                  strokeDasharray="4"
                  strokeWidth="0.8"
                />
                <text
                  x={margin.left - 8}
                  y={y + 3}
                  textAnchor="end"
                  fill="var(--color-text-muted)"
                  className="text-[9px] font-sans"
                >
                  {formatCurrency(gridVal).replace(' ₫', '')}
                </text>
              </g>
            );
          })}

          {/* Zero Line */}
          <line
            x1={margin.left}
            y1={y0}
            x2={W - margin.right}
            y2={y0}
            stroke="var(--color-text-muted)"
            strokeWidth="1.2"
            opacity="0.7"
          />

          {/* Bars */}
          {revenueData.map((d, idx) => {
            const xCent = getX(idx);
            const colW = Math.max(4, Math.min(16, bandW * 0.3));

            // Revenue bar
            const revY = getY(d.revenue);
            const revH = Math.abs(y0 - revY);
            const revYPos = Math.min(y0, revY);

            // Gross Profit bar
            const profY = getY(d.profit);
            const profH = Math.abs(y0 - profY);
            const profYPos = Math.min(y0, profY);

            return (
              <g key={idx}>
                {/* Revenue (Blueish) */}
                <rect
                  x={xCent - colW - 1}
                  y={revYPos}
                  width={colW}
                  height={Math.max(1, revH)}
                  fill="url(#revGrad)"
                  rx="1.5"
                  className="transition-all duration-300 cursor-pointer hover:brightness-110"
                  onMouseEnter={() => setHoveredChartIdx(idx)}
                  onMouseLeave={() => setHoveredChartIdx(null)}
                />
                {/* Gross Profit (Purple) */}
                <rect
                  x={xCent + 1}
                  y={profYPos}
                  width={colW}
                  height={Math.max(1, profH)}
                  fill="url(#profGrad)"
                  rx="1.5"
                  className="transition-all duration-300 cursor-pointer hover:brightness-110"
                  onMouseEnter={() => setHoveredChartIdx(idx)}
                  onMouseLeave={() => setHoveredChartIdx(null)}
                />

                {/* X Axis Labels */}
                {idx % Math.max(1, Math.floor(revenueData.length / 8)) === 0 && (
                  <text
                    x={xCent}
                    y={H - margin.bottom + 16}
                    textAnchor="middle"
                    fill="var(--color-text-secondary)"
                    className="text-[9px] font-semibold"
                  >
                    {formatLabel(d.date)}
                  </text>
                )}
              </g>
            );
          })}

          {/* Line: Net Profit (Emerald) */}
          {lineD && (
            <path
              d={lineD}
              fill="none"
              stroke="var(--color-success)"
              strokeWidth="2.5"
              className="drop-shadow-[0_2px_4px_rgba(16,185,129,0.3)]"
            />
          )}

          {/* Line Nodes */}
          {revenueData.map((d, idx) => {
            const x = getX(idx);
            const y = getY(d.netProfit);
            return (
              <circle
                key={idx}
                cx={x}
                cy={y}
                r={hoveredChartIdx === idx ? 5.5 : 3.5}
                fill="#10b981"
                stroke="#0f172a"
                strokeWidth="1.5"
                className="transition-all duration-200 cursor-pointer"
                onMouseEnter={() => setHoveredChartIdx(idx)}
                onMouseLeave={() => setHoveredChartIdx(null)}
              />
            );
          })}

          {/* Gradients Definitions */}
          <defs>
            <linearGradient id="revGrad" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#4f46e5" />
              <stop offset="100%" stopColor="#6366f1" stopOpacity="0.4" />
            </linearGradient>
            <linearGradient id="profGrad" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#06b6d4" />
              <stop offset="100%" stopColor="#0891b2" stopOpacity="0.4" />
            </linearGradient>
          </defs>
        </svg>

        {/* Hover Tooltip Overlay */}
        {hoveredChartIdx !== null && revenueData[hoveredChartIdx] && (
          <div className="absolute top-2 left-1/2 transform -translate-x-1/2 glass p-3 rounded-xl border border-white/10 text-[10px] space-y-1 z-30 pointer-events-none shadow-xl animate-fade-in">
            <p className="font-bold text-white mb-1 border-b border-white/5 pb-1">
              {formatLabel(revenueData[hoveredChartIdx].date)}
            </p>
            <p className="flex justify-between gap-6 text-indigo-300">
              <span>Doanh thu:</span>
              <span className="font-bold">{formatCurrency(revenueData[hoveredChartIdx].revenue)}</span>
            </p>
            <p className="flex justify-between gap-6 text-cyan-300">
              <span>LN Gộp:</span>
              <span className="font-bold">{formatCurrency(revenueData[hoveredChartIdx].profit)}</span>
            </p>
            <p className="flex justify-between gap-6 text-emerald-400">
              <span>LN Ròng:</span>
              <span className="font-bold">{formatCurrency(revenueData[hoveredChartIdx].netProfit)}</span>
            </p>
            <p className="flex justify-between gap-6 text-slate-400">
              <span>Chi phí:</span>
              <span className="font-bold">{formatCurrency(revenueData[hoveredChartIdx].expenses)}</span>
            </p>
          </div>
        )}
      </div>
    );
  };

  return (
    <div className="space-y-8 animate-fade-in-up">
      {/* Header */}
      <div className="flex flex-col md:flex-row justify-between items-start md:items-center gap-6">
        <div>
          <h2 className="text-2xl font-bold text-gradient font-sans">Báo cáo hoạt động chi tiết</h2>
          <p className="text-xs text-slate-400">Phân tích chuyên sâu 14 KPIs tài chính, biểu đồ SVG tương tác và xuất file Excel 12 sheet dữ liệu</p>
        </div>

        {/* Global Date & Employee Filters */}
        <div className="flex flex-wrap items-center gap-3 w-full md:w-auto">
          {/* Employee Picker */}
          <div className="flex items-center gap-1.5 shrink-0">
            <span className="text-[11px] font-bold text-slate-400 uppercase tracking-wider">Nhân viên:</span>
            <select
              className="input py-1.5 px-3 text-xs w-40 bg-slate-900 border-white/5 h-9"
              value={selectedEmployeeId}
              onChange={(e) => setSelectedEmployeeId(e.target.value)}
            >
              <option value="">Tất cả nhân viên</option>
              {employees.map(emp => (
                <option key={emp.id} value={emp.id}>{emp.name}</option>
              ))}
            </select>
          </div>

          {/* Date Picker Range */}
          <div className="flex items-center gap-2">
            <input
              type="date"
              className="input py-1.5 px-2 text-xs w-32 bg-slate-900 border-white/5 h-9"
              value={startDate}
              onChange={(e) => setStartDate(e.target.value)}
            />
            <span className="text-slate-500 text-xs">➔</span>
            <input
              type="date"
              className="input py-1.5 px-2 text-xs w-32 bg-slate-900 border-white/5 h-9"
              value={endDate}
              onChange={(e) => setEndDate(e.target.value)}
            />
          </div>

          {/* Export Button */}
          <button
            onClick={exportAllSheetsExcel}
            disabled={exporting}
            className="btn btn-primary px-4 py-1.5 text-xs font-semibold cursor-pointer shadow-glow flex items-center gap-1.5 h-9"
          >
            {exporting ? '⏳ Đang tạo...' : '📥 Xuất Excel 12 Sheet'}
          </button>
        </div>
      </div>

      {loading ? (
        <div className="py-24 text-center text-slate-500 text-xs">
          Đang truy vấn dữ liệu báo cáo từ database thực tế...
        </div>
      ) : (
        <>
          {/* 14 KPIs Dashboard Grid */}
          <div className="space-y-4">
            <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider">Tóm tắt 14 KPIs kinh doanh</h3>
            <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
              {/* Doanh thu gộp */}
              <div className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all">
                <span className="text-[10px] text-slate-500 font-bold uppercase">1. Doanh thu gộp</span>
                <span className="text-base font-extrabold text-white mt-1.5">{formatCurrency(kpis?.totalRevenue || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Tổng tiền mặt bán hàng gốc</span>
              </div>

              {/* Giảm giá */}
              <div className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all">
                <span className="text-[10px] text-slate-500 font-bold uppercase">2. Tổng giảm giá</span>
                <span className="text-base font-extrabold text-amber-500 mt-1.5">-{formatCurrency(kpis?.totalDiscount || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Chiết khấu trực tiếp trên bill</span>
              </div>

              {/* Doanh thu thuần */}
              <div className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all">
                <span className="text-[10px] text-slate-500 font-bold uppercase">3. Doanh thu thuần</span>
                <span className="text-base font-extrabold text-indigo-400 mt-1.5">{formatCurrency(kpis?.netRevenue || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Doanh thu gộp - giảm giá</span>
              </div>

              {/* Giá vốn */}
              <div className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all">
                <span className="text-[10px] text-slate-500 font-bold uppercase">4. Tổng giá vốn</span>
                <span className="text-base font-extrabold text-slate-300 mt-1.5">{formatCurrency(kpis?.totalCost || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Gồm giá thô và MIX phân rã</span>
              </div>

              {/* Lợi nhuận gộp */}
              <div className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all">
                <span className="text-[10px] text-slate-500 font-bold uppercase">5. Lợi nhuận gộp</span>
                <span className="text-base font-extrabold text-cyan-400 mt-1.5">{formatCurrency(kpis?.grossProfit || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Doanh thu thuần - giá vốn</span>
              </div>

              {/* Thu tiền mặt */}
              <div className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all">
                <span className="text-[10px] text-slate-500 font-bold uppercase">6. Thu TM (Đơn hàng)</span>
                <span className="text-base font-extrabold text-emerald-400 mt-1.5">{formatCurrency(kpis?.cashRevenue || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Tiền mặt đơn + Thu nợ gốc</span>
              </div>

              {/* Thu chuyển khoản */}
              <div className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all">
                <span className="text-[10px] text-slate-500 font-bold uppercase">7. Thu CK (Đơn hàng)</span>
                <span className="text-base font-extrabold text-sky-400 mt-1.5">{formatCurrency(kpis?.bankRevenue || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Banking đơn + Thu nợ chuyển khoản</span>
              </div>

              {/* Nợ phát sinh */}
              <div className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all">
                <span className="text-[10px] text-slate-500 font-bold uppercase">8. Nợ bán hàng còn lại</span>
                <span className="text-base font-extrabold text-rose-400 mt-1.5">{formatCurrency(kpis?.outstandingDebt || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Nợ chưa thu từ các đơn trong kỳ</span>
              </div>

              {/* Tổng chi phí */}
              <div className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all">
                <span className="text-[10px] text-slate-500 font-bold uppercase">9. Tổng chi phí</span>
                <span className="text-base font-extrabold text-rose-300 mt-1.5">{formatCurrency(kpis?.totalExpenses || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Mọi khoản chi phát sinh</span>
              </div>

              {/* Chi phí hợp lý */}
              <div className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all">
                <span className="text-[10px] text-slate-500 font-bold uppercase">10. Chi phí hợp lý</span>
                <span className="text-base font-extrabold text-slate-200 mt-1.5">{formatCurrency(kpis?.expenseReasonable || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Chi phí kinh doanh phục vụ vận hành</span>
              </div>

              {/* Ngoài kinh doanh */}
              <div className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all">
                <span className="text-[10px] text-slate-500 font-bold uppercase">11. Chi tiêu ngoài KD</span>
                <span className="text-base font-extrabold text-purple-400 mt-1.5">{formatCurrency(kpis?.expenseOutsideBusiness || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Rút vốn chi cá nhân</span>
              </div>

              {/* Nợ phải trả */}
              <div className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all">
                <span className="text-[10px] text-slate-500 font-bold uppercase">12. Nợ phải trả (Owe)</span>
                <span className="text-base font-extrabold text-orange-400 mt-1.5">{formatCurrency(kpis?.totalOwe || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Tiền nợ NCC còn lại lũy kế</span>
              </div>

              {/* Nợ phải thu */}
              <div className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all">
                <span className="text-[10px] text-slate-500 font-bold uppercase">13. Nợ phải thu (Owed)</span>
                <span className="text-base font-extrabold text-yellow-500 mt-1.5">{formatCurrency(kpis?.totalOwed || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Tiền khách nợ tôi lũy kế</span>
              </div>

              {/* Lợi nhuận ròng */}
              <div className="card bg-gradient-to-tr from-indigo-500/10 to-cyan-500/10 border-indigo-500/20 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all shadow-md">
                <span className="text-[10px] text-indigo-300 font-extrabold uppercase">14. Lợi nhuận ròng</span>
                <span className="text-lg font-black text-emerald-400 mt-1.5">{formatCurrency(kpis?.netProfit || 0)}</span>
                <span className="text-[9px] text-slate-400 mt-1">Lợi nhuận gộp - chi phí hợp lý</span>
              </div>
            </div>
          </div>

          {/* Charts & Breakdown panels */}
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            {/* Revenue Area Chart */}
            <div className="lg:col-span-2 card bg-slate-900 border-white/5 space-y-4">
              <div className="flex justify-between items-center flex-wrap gap-4">
                <h4 className="font-bold text-white text-sm">Biểu đồ biến động doanh thu & lợi nhuận</h4>
                
                {/* Chart aggregation toggles */}
                <div className="flex bg-slate-950/60 p-0.5 rounded-lg border border-white/5">
                  {['day', 'month', 'year'].map((g) => (
                    <button
                      key={g}
                      onClick={() => setGroupBy(g as any)}
                      className={`px-3 py-1 text-[10px] font-bold rounded-md transition-all cursor-pointer capitalize ${
                        groupBy === g
                          ? 'bg-indigo-500/20 text-indigo-300 border border-indigo-500/20'
                          : 'text-slate-500 hover:text-slate-300'
                      }`}
                    >
                      {g === 'day' ? 'Ngày' : g === 'month' ? 'Tháng' : 'Năm'}
                    </button>
                  ))}
                </div>
              </div>

              {/* Render SVG chart */}
              <div className="pt-2">
                {drawBarLineChart()}
              </div>

              {/* Legend & explanations */}
              <div className="flex justify-center gap-6 text-[10px] font-semibold border-t border-white/5 pt-4">
                <div className="flex items-center gap-2">
                  <span className="w-3 h-3 rounded bg-indigo-600"></span>
                  <span className="text-slate-400">Doanh thu</span>
                </div>
                <div className="flex items-center gap-2">
                  <span className="w-3 h-3 rounded bg-cyan-500"></span>
                  <span className="text-slate-400">Lợi nhuận gộp</span>
                </div>
                <div className="flex items-center gap-2">
                  <span className="w-3.5 h-1 rounded bg-[#10b981]"></span>
                  <span className="text-slate-400">Lợi nhuận ròng (Đường kẻ)</span>
                </div>
              </div>
            </div>

            {/* Expenses breakdown circular pie chart */}
            <div className="card bg-slate-900 border-white/5 flex flex-col justify-between min-h-[340px]">
              <div>
                <h4 className="font-bold text-white text-sm">Tỷ trọng chi phí hợp lý</h4>
                <p className="text-[10px] text-slate-500 mt-1">Phân tích tỷ lệ phần trăm giữa các danh mục chi tiêu hoạt động</p>
              </div>

              <div className="py-4">
                {drawPieChart()}
              </div>

              <div className="border-t border-white/5 pt-3.5 text-center text-[9px] text-slate-500">
                * Chi tiêu ngoài kinh doanh rút vốn cá nhân không được tính vào biểu đồ này
              </div>
            </div>
          </div>

          {/* Top Selling Products list */}
          <div className="card bg-slate-900 border-white/5 space-y-4">
            <h4 className="font-bold text-white text-sm">Top 10 sản phẩm bán chạy nhất</h4>
            
            {topProducts.length === 0 ? (
              <div className="py-12 text-center text-slate-500 text-xs">
                Không tìm thấy thông tin sản phẩm bán chạy nào trong khoảng thời gian này
              </div>
            ) : (
              <div className="space-y-3.5">
                {topProducts.map((p, idx) => {
                  const maxQty = Math.max(...topProducts.map(tp => tp.quantity), 1);
                  const ratio = (p.quantity / maxQty) * 100;
                  return (
                    <div key={idx} className="flex items-center gap-4 text-xs">
                      {/* Rank badge */}
                      <span className="w-6 font-bold text-slate-600 text-center">
                        {idx + 1}
                      </span>
                      
                      {/* Name & details */}
                      <div className="w-44 truncate text-slate-300 font-medium">
                        {p.name} <span className="text-[10px] text-slate-500">({p.unit})</span>
                      </div>

                      {/* Progress Bar Gauge */}
                      <div className="flex-1 bg-slate-950/60 h-3 rounded-full overflow-hidden relative">
                        <div
                          style={{ width: `${ratio}%` }}
                          className="bg-gradient-to-r from-indigo-600 to-cyan-500 h-full rounded-full transition-all duration-500"
                        ></div>
                      </div>

                      {/* Stats */}
                      <div className="w-32 text-right shrink-0">
                        <span className="font-bold text-white">{p.quantity} bán</span>
                        <span className="text-[10px] text-indigo-400 font-semibold ml-2 block sm:inline">
                          {formatCurrency(p.totalRev)}
                        </span>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </>
      )}
    </div>
  );
}
