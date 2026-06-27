'use client';

import React, { useEffect, useState, useMemo } from 'react';
import api from '@/lib/api';
import AppDataGrid from '@/components/ui/AppDataGrid';
import { GridColDef } from '@mui/x-data-grid';
import { matchVietnamese } from '@/lib/text';
import Modal from '@/components/ui/Modal';
import { formatCurrency, formatDateTime } from '@/lib/format';
import * as XLSX from 'xlsx';

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

  // Inventory summary metrics
  const [inventorySummary, setInventorySummary] = useState({
    openingQty: 0,
    openingCost: 0,
    openingSell: 0,
    importQty: 0,
    importCost: 0,
    importSell: 0,
    exportQty: 0,
    exportCost: 0,
    exportSell: 0,
    endingQty: 0,
    endingCost: 0,
    endingSell: 0,
  });

  // Backdata modal state
  const [backdataModalOpen, setBackdataModalOpen] = useState(false);
  const [backdataKind, setBackdataKind] = useState<string | null>(null);
  const [backdataTitle, setBackdataTitle] = useState('');
  const [backdataLoading, setBackdataLoading] = useState(false);
  const [backdataRows, setBackdataRows] = useState<any[]>([]);

  // Chart loading state to prevent full-page flashes
  const [chartLoading, setChartLoading] = useState(false);

  useEffect(() => {
    // Load employee list
    api.getEmployees().then(setEmployees).catch(() => {});
  }, []);

  const fetchRevenueDataOnly = async () => {
    try {
      setChartLoading(true);
      const params = {
        startDate,
        endDate,
        ...(selectedEmployeeId && { employeeId: selectedEmployeeId }),
        groupBy,
      };
      const revRes = await api.getRevenueReport(params);
      if (revRes) setRevenueData(revRes);
    } catch (err) {
      console.error('Failed to load chart data:', err);
    } finally {
      setChartLoading(false);
    }
  };

  const fetchData = async () => {
    try {
      setLoading(true);
      const params = {
        startDate,
        endDate,
        ...(selectedEmployeeId && { employeeId: selectedEmployeeId }),
      };

      const startD = new Date(startDate);
      const year = startD.getFullYear();
      const month = startD.getMonth() + 1;

      const [kpiRes, topRes, ratioRes, productsRes, openingRes, importsRes, exportsRes] = await Promise.all([
        api.getDashboard(params),
        api.fetch<TopProduct[]>(`/api/reports/top-products?startDate=${startDate}&endDate=${endDate}${selectedEmployeeId ? `&employeeId=${selectedEmployeeId}` : ''}`),
        api.fetch<ExpenseRatio[]>(`/api/reports/expenses-ratio?startDate=${startDate}&endDate=${endDate}`),
        api.getProducts().catch(() => []),
        api.getOpeningStocks(year, month).catch(() => []),
        api.getPurchaseHistory({ startDate, endDate }).catch(() => []),
        api.getExportHistory({ startDate, endDate }).catch(() => []),
      ]);

      if (kpiRes) setKpis(kpiRes);
      if (topRes) setTopProducts(topRes);
      if (ratioRes) setExpenseRatios(ratioRes);

      // Compute Inventory Summary
      const productsList = productsRes || [];
      const openingList = openingRes || [];
      const importsList = importsRes || [];
      const exportsList = exportsRes || [];

      const productsById = Object.fromEntries(productsList.map((p: any) => [p.id, p]));
      const openingStocksMap = Object.fromEntries(openingList.map((op: any) => [op.productId, Number(op.openingStock || 0)]));

      // 1. Opening
      let openingQty = 0;
      let openingCost = 0;
      let openingSell = 0;
      productsList.forEach((p: any) => {
        if (p.itemType === 'RAW') {
          const qty = openingStocksMap[p.id] || 0;
          openingQty += qty;
          openingCost += qty * Number(p.costPrice || 0);
          openingSell += qty * Number(p.price || 0);
        }
      });

      // 2. Import
      let importQty = 0;
      let importCost = 0;
      let importSell = 0;
      importsList.forEach((ph: any) => {
        const qty = Number(ph.quantity || 0);
        importQty += qty;
        importCost += Number(ph.totalCost || 0);
        const prod = productsById[ph.productId];
        if (prod) {
          importSell += qty * Number(prod.price || 0);
        }
      });

      // 3. Export
      let exportQty = 0;
      let exportCost = 0;
      let exportSell = 0;
      exportsList.forEach((ex: any) => {
        const qty = Number(ex.quantity || 0);
        exportQty += qty;
        exportCost += Number(ex.totalCost || 0);
        exportSell += Number(ex.totalPrice || 0);
      });

      // 4. Ending
      const endingQty = openingQty + importQty - exportQty;
      const endingCost = openingCost + importCost - exportCost;
      const endingSell = openingSell + importSell - exportSell;

      setInventorySummary({
        openingQty,
        openingCost,
        openingSell,
        importQty,
        importCost,
        importSell,
        exportQty,
        exportCost,
        exportSell,
        endingQty,
        endingCost,
        endingSell,
      });

    } catch (err) {
      console.error('Failed to load report data:', err);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
  }, [startDate, endDate, selectedEmployeeId]);

  useEffect(() => {
    fetchRevenueDataOnly();
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

      // ─── 1. SHEET CUSTOMERS ─────────────────────────────
      const customersSheet = customers.map((c: Customer) => ({
        'ID': c.id,
        'Tên': c.name,
        'Số điện thoại': c.phone || '',
        'Ghi chú': c.note || '',
        'Là nhà cung cấp': c.isSupplier ? 'Đúng' : 'Không',
        'Ngày cập nhật': c.updatedAt || ''
      }));

      // ─── 2. SHEET PRODUCTS ──────────────────────────────
      const productsSheet = products.map((p: Product) => ({
        'ID': p.id,
        'Tên sản phẩm': p.name,
        'Đơn vị': p.unit,
        'Mã vạch': p.barcode || '',
        'Giá bán': p.price,
        'Giá vốn': p.costPrice,
        'Tồn kho': p.currentStock,
        'Hoạt động': p.isActive ? 'Đang bán' : 'Ngừng bán',
        'Phân loại': p.itemType
      }));

      // ─── 3. SHEET DEBTS ─────────────────────────────────
      const debtsSheet = debts.map((d: Debt) => {
        const initial = Number(d.initialAmount || d.amount || 0);
        const paid = debtPaidById[d.id] || 0;
        const remain = Number(d.amount || 0);
        return {
          'Mã công nợ': d.id,
          'Tên khách/Đối tác': d.customerName || d.partyName || 'Khách lẻ',
          'Số nợ ban đầu': initial,
          'Đã trả': paid,
          'Còn lại': remain,
          'Ngày nợ': d.createdAt,
          'Hạn trả': d.dueDate || '',
          'Nguồn gốc': d.sourceType ? `${d.sourceType} (${d.sourceId})` : 'Tự ghi nợ',
          'Trạng thái': d.isPaid ? 'Đã thanh toán' : 'Chưa trả'
        };
      });

      // ─── 4. SHEET DEBT PAYMENTS ────────────────────────
      const debtPaymentsSheet = debtPayments.map((p: DebtPayment) => ({
        'Mã thanh toán': p.id || p.paymentId || '',
        'Mã công nợ': p.debtId,
        'Loại công nợ': p.debtType || '',
        'Tên đối tác': p.partyName || 'Khách lẻ',
        'Số tiền trả': p.amount,
        'Phương thức': p.paymentType,
        'Ghi chú': p.note || '',
        'Ngày trả': p.createdAt
      }));

      // ─── 5. SHEET EXPENSES ─────────────────────────────
      const expensesSheet = expenses.map((e: Expense) => ({
        'Mã chi phí': e.id,
        'Ngày chi': e.occurredAt,
        'Số tiền': e.amount,
        'Danh mục': e.category,
        'Ghi chú': e.note || ''
      }));

      // ─── 6. SHEET PURCHASE HISTORY ─────────────────────
      const purchaseHistorySheet = purchasesHistory.map((ph: any) => ({
        'Mã nhập': ph.id,
        'Ngày nhập': ph.createdAt,
        'Mã SP': ph.productId,
        'Tên sản phẩm': ph.productName,
        'Số lượng': ph.quantity,
        'Đơn giá vốn': ph.unitCost,
        'Thành tiền': ph.totalCost,
        'Nhà cung cấp': ph.supplierName || 'NCC vãng lai',
        'Ghi chú': ph.note || ''
      }));

      // ─── 7. SHEET EXPORT HISTORY ─────────────────────
      const exportHistorySheet: any[] = [];
      sales.forEach((s: Sale) => {
        s.items.forEach((it: SaleItem) => {
          if (it.itemType === 'MIX' && it.mixItemsJson) {
            try {
              const mixItems = JSON.parse(it.mixItemsJson);
              if (Array.isArray(mixItems)) {
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

                  exportHistorySheet.push({
                    'Mã đơn hàng': s.id,
                    'Ngày xuất': s.createdAt,
                    'Tên khách': s.customerName || 'Khách vãng lai',
                    'Nhân viên': s.employeeName || '',
                    'Mã SP': m.rawProductId,
                    'Tên sản phẩm': m.rawName,
                    'Đơn vị': m.rawUnit,
                    'Số lượng': Number(m.rawQty || 0) * mixQty,
                    'Đơn giá bán': unitPriceSnap,
                    'Doanh thu': lineTotalSnap * mixQty,
                    'Giá vốn': m.rawUnitCost,
                    'Tổng vốn': lineCostTotalSnap * mixQty,
                    'Phân loại': 'MIX-DECOMPOSED'
                  });
                });
              }
            } catch (_) {}
          } else {
            const qty = Number(it.quantity || 0);
            const price = Number(it.unitPrice || 0);
            const cost = Number(it.unitCost || 0);
            exportHistorySheet.push({
              'Mã đơn hàng': s.id,
              'Ngày xuất': s.createdAt,
              'Tên khách': s.customerName || 'Khách vãng lai',
              'Nhân viên': s.employeeName || '',
              'Mã SP': it.productId,
              'Tên sản phẩm': it.name,
              'Đơn vị': it.unit,
              'Số lượng': qty,
              'Đơn giá bán': price,
              'Doanh thu': qty * price,
              'Giá vốn': cost,
              'Tổng vốn': qty * cost,
              'Phân loại': 'RAW'
            });
          }
        });
      });

      // ─── 8. SHEET LIST ORDER SALES ────────────────────
      const salesOrdersSheet = sales.map((s: Sale) => {
        const subtotal = s.items.reduce((sum, item) => sum + (Number(item.unitPrice) * Number(item.quantity)), 0);
        const discount = Number(s.discount || 0);
        const net = subtotal - discount;
        const remainDebt = Math.max(0, net - Number(s.paidAmount || 0));

        return {
          'Mã đơn hàng': s.id,
          'Ngày bán': s.createdAt,
          'Khách hàng': s.customerName || 'Khách lẻ',
          'Nhân viên': s.employeeName || '',
          'Doanh thu gộp': subtotal,
          'Giảm giá': discount,
          'Doanh thu thuần': net,
          'Tổng vốn': s.totalCost,
          'Đã trả ban đầu': s.paidAmount,
          'Còn nợ': remainDebt,
          'Phương thức': s.paymentType,
          'Ghi chú': s.note || ''
        };
      });

      // ─── 9. SHEET OPENING STOCK ──────────────────────
      const openingStockSheet = products.map((p: Product) => {
        const opStock = openingByProductId[p.id] || 0;
        return {
          'Năm': year,
          'Tháng': month,
          'Mã sản phẩm': p.id,
          'Tên sản phẩm': p.name,
          'Đơn vị': p.unit,
          'Số lượng tồn đầu': opStock
        };
      });

      // ─── 10. SHEET CLOSING STOCK ─────────────────────
      const closingStockSheet = products.map((p: Product) => {
        const opStock = openingByProductId[p.id] || 0;
        const imp = importQtyByProductId[p.id] || 0;
        const exp = exportQtyByProductId[p.id] || 0;
        const ending = opStock + imp - exp;

        return {
          'Năm': year,
          'Tháng': month,
          'Mã SP': p.id,
          'Tên sản phẩm': p.name,
          'Đơn vị': p.unit,
          'Tồn đầu': opStock,
          'Nhập trong kỳ': imp,
          'Xuất trong kỳ': exp,
          'Tồn cuối': ending,
          'Giá vốn': p.costPrice,
          'Trị giá tồn (vốn)': ending * p.costPrice,
          'Giá bán': p.price,
          'Trị giá tồn (bán)': ending * p.price
        };
      });

      // Create workbook using SheetJS
      const wb = XLSX.utils.book_new();

      const addSheet = (data: any[], name: string) => {
        const ws = XLSX.utils.json_to_sheet(data);
        if (data.length > 0) {
          const maxLen = data.reduce((w, r) => {
            Object.keys(r).forEach((key) => {
              w[key] = Math.max(w[key] || 0, String(r[key] || '').length, key.length);
            });
            return w;
          }, {} as Record<string, number>);
          ws['!cols'] = Object.keys(maxLen).map(key => ({ wch: Math.min(50, maxLen[key] + 3) }));
        }
        XLSX.utils.book_append_sheet(wb, ws, name);
      };

      addSheet(customersSheet, "list khách hàng");
      addSheet(productsSheet, "list sản phẩm");
      addSheet(debtsSheet, "list công nợ");
      addSheet(debtPaymentsSheet, "lịch sử trả nợ");
      addSheet(expensesSheet, "list chi phí");
      addSheet(purchaseHistorySheet, "lịch sử nhập kho");
      addSheet(exportHistorySheet, "lịch sử xuất kho");
      addSheet(salesOrdersSheet, "list đơn hàng");
      addSheet(openingStockSheet, "list tồn đầu kỳ");
      addSheet(closingStockSheet, "list tồn cuối kỳ");

      const ts = new Date().toISOString().replace(/[-:T.]/g, '').slice(0, 14);
      XLSX.writeFile(wb, `bao_cao_tong_hop_${ts}.xlsx`);
    } catch (err) {
      alert('Có lỗi xảy ra khi xuất Excel: ' + (err instanceof Error ? err.message : String(err)));
    } finally {
      setExporting(false);
    }
  };

  const exportBackdataExcel = () => {
    try {
      const cols = getBackdataColumns();
      
      const formattedRows = backdataRows.map(row => {
        const obj: Record<string, any> = {};
        cols.forEach(col => {
          let val = '';
          if (col.valueGetter) {
            val = (col.valueGetter as any)(row[col.field], row, col, {} as any);
          } else {
            val = row[col.field];
          }

          if (col.valueFormatter && val !== null && val !== undefined) {
            obj[col.headerName || col.field] = (col.valueFormatter as any)(val);
          } else {
            obj[col.headerName || col.field] = val;
          }
        });
        return obj;
      });

      const ws = XLSX.utils.json_to_sheet(formattedRows);
      const wb = XLSX.utils.book_new();
      XLSX.utils.book_append_sheet(wb, ws, "Chi tiết KPI");

      if (formattedRows.length > 0) {
        const maxLen = formattedRows.reduce((w, r) => {
          Object.keys(r).forEach((key) => {
            w[key] = Math.max(w[key] || 0, String(r[key] || '').length, key.length);
          });
          return w;
        }, {} as Record<string, number>);
        ws['!cols'] = Object.keys(maxLen).map(key => ({ wch: Math.min(50, maxLen[key] + 3) }));
      }

      const cleanTitle = (backdataTitle || 'bao_cao')
        .toLowerCase()
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
        .replace(/đ/g, 'd')
        .replace(/[^a-z0-9_]/g, '_');

      XLSX.writeFile(wb, `${cleanTitle}.xlsx`);
    } catch (err) {
      alert('Lỗi xuất Excel: ' + (err instanceof Error ? err.message : String(err)));
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
      <div className="flex flex-col items-center gap-6 justify-center">
        {/* SVG Circle */}
        <div className="relative w-56 h-56 shrink-0">
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
          <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none text-center p-6 bg-slate-950/20 rounded-full backdrop-blur-[1px]">
            {hoveredPieIdx !== null ? (
              <>
                <span className="text-[10px] text-slate-400 truncate max-w-[140px] font-bold">{expenseRatios[hoveredPieIdx].category}</span>
                <span className="text-sm font-bold text-white mt-0.5">{expenseRatios[hoveredPieIdx].percentage.toFixed(1)}%</span>
                <span className="text-[10px] text-slate-500 mt-0.5">{formatCurrency(expenseRatios[hoveredPieIdx].amount)}</span>
              </>
            ) : (
              <>
                <span className="text-[10px] text-slate-500 font-semibold">Tổng chi phí</span>
                <span className="text-sm font-extrabold text-indigo-300 mt-0.5">
                  {formatCurrency(kpis?.expenseReasonable || 0)}
                </span>
              </>
            )}
          </div>
        </div>

        {/* Legend Grid */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 text-xs w-full max-h-60 overflow-y-auto pr-1">
          {slices.map((s, idx) => (
            <div
              key={idx}
              className={`flex items-center justify-between p-2 rounded-lg transition-all ${
                hoveredPieIdx === idx ? 'bg-slate-800/40 border-l-2 border-indigo-500 pl-2.5' : 'bg-slate-950/20 border border-white/5'
              }`}
              onMouseEnter={() => setHoveredPieIdx(idx)}
              onMouseLeave={() => setHoveredPieIdx(null)}
            >
              <div className="flex items-center gap-2 min-w-0">
                <span className="w-2.5 h-2.5 rounded shrink-0" style={{ backgroundColor: s.color }}></span>
                <span className="text-slate-300 truncate font-medium">{s.category}</span>
              </div>
              <span className="font-semibold text-slate-400 text-[10px] shrink-0 ml-4">
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

  const openBackdata = async (kind: string, title: string) => {
    setBackdataKind(kind);
    setBackdataTitle(title);
    setBackdataModalOpen(true);
    setBackdataLoading(true);
    try {
      const params = { startDate, endDate };
      if (kind === 'revenue' || kind === 'discount' || kind === 'net_revenue' || kind === 'profit' || kind === 'net_profit') {
        const sales = await api.getSales(params);
        setBackdataRows(sales || []);
      } else if (kind === 'cost' || kind === 'export_history') {
        const exports = await api.getExportHistory(params);
        setBackdataRows(exports || []);
      } else if (kind === 'cash' || kind === 'bank' || kind === 'total_paid') {
        const [sales, debts] = await Promise.all([
          api.getSales(params),
          api.getDebts(),
        ]);
        const pmts: any[] = [];
        sales.forEach((s: any) => {
          const paid = Number(s.paidAmount || 0);
          if (paid > 0) {
            const isCash = (s.paymentType || '').toLowerCase() === 'cash';
            if (
              kind === 'total_paid' ||
              (kind === 'cash' && isCash) ||
              (kind === 'bank' && !isCash)
            ) {
              pmts.push({
                id: `sale-${s.id}`,
                createdAt: s.createdAt,
                type: 'Bán hàng',
                description: `Thanh toán đơn hàng #${s.id.slice(-6).toUpperCase()}`,
                party: s.customerName || 'Khách vãng lai',
                amount: paid,
                paymentType: s.paymentType === 'CASH' ? 'Tiền mặt' : 'Chuyển khoản',
              });
            }
          }
        });
        debts.forEach((d: any) => {
          if (d.type === 1 && d.payments) { // d.type === 1 are customer nợ (othersOweMe)
            d.payments.forEach((p: any) => {
              const payDate = new Date(p.createdAt);
              const startLimit = new Date(startDate);
              const endLimit = new Date(endDate + 'T23:59:59');
              if (payDate >= startLimit && payDate <= endLimit) {
                const isCash = (p.paymentType || '').toLowerCase() === 'cash';
                if (
                  kind === 'total_paid' ||
                  (kind === 'cash' && isCash) ||
                  (kind === 'bank' && !isCash)
                ) {
                  pmts.push({
                    id: `debt-${p.uuid || p.id}`,
                    createdAt: p.createdAt,
                    type: 'Thu nợ',
                    description: `Khách trả nợ: ${d.partyName}`,
                    party: d.partyName,
                    amount: Number(p.amount),
                    paymentType: p.paymentType === 'CASH' ? 'Tiền mặt' : 'Chuyển khoản',
                  });
                }
              }
            });
          }
        });
        pmts.sort((a, b) => b.createdAt.localeCompare(a.createdAt));
        setBackdataRows(pmts);
      } else if (kind === 'outstanding') {
        const sales = await api.getSales(params);
        const outstandingSales = sales.filter((s: any) => {
          const subtotal = s.items.reduce((sum: number, item: any) => sum + (Number(item.unitPrice) * Number(item.quantity)), 0);
          const total = Math.max(0, subtotal - Number(s.discount || 0));
          return total - Number(s.paidAmount || 0) > 0;
        });
        setBackdataRows(outstandingSales);
      } else if (kind === 'expenses' || kind === 'expense_reasonable' || kind === 'expense_outside') {
        const expenses = await api.getExpenses(params);
        let filtered = expenses || [];
        if (kind === 'expense_reasonable') {
          filtered = filtered.filter((e: any) => e.category !== 'Chi tiêu ngoài kinh doanh');
        } else if (kind === 'expense_outside') {
          filtered = filtered.filter((e: any) => e.category === 'Chi tiêu ngoài kinh doanh');
        }
        setBackdataRows(filtered);
      } else if (kind === 'owe' || kind === 'owed') {
        const debts = await api.getDebts();
        const typeTab = kind === 'owe' ? 0 : 1;
        const filtered = debts.filter((d: any) => d.type === typeTab && !d.settled);
        setBackdataRows(filtered);
      } else if (kind === 'opening_stock') {
        const [products, openingStocks] = await Promise.all([
          api.getProducts(),
          api.getOpeningStocks(new Date(startDate).getFullYear(), new Date(startDate).getMonth() + 1),
        ]);
        const openingMap = Object.fromEntries(openingStocks.map((o: any) => [o.productId, Number(o.openingStock || 0)]));
        const rows = products.filter((p: any) => p.itemType === 'RAW').map((p: any) => {
          const qty = openingMap[p.id] || 0;
          return {
            id: p.id,
            productName: p.name,
            unit: p.unit,
            quantity: qty,
            unitCost: Number(p.costPrice),
            totalCost: qty * Number(p.costPrice),
            unitPrice: Number(p.price),
            totalPrice: qty * Number(p.price),
          };
        });
        setBackdataRows(rows);
      } else if (kind === 'import_history') {
        const imports = await api.getPurchaseHistory(params);
        setBackdataRows(imports || []);
      } else if (kind === 'ending_stock') {
        const startD = new Date(startDate);
        const year = startD.getFullYear();
        const month = startD.getMonth() + 1;
        const [products, openingStocks, imports, exports] = await Promise.all([
          api.getProducts(),
          api.getOpeningStocks(year, month),
          api.getPurchaseHistory(params),
          api.getExportHistory(params),
        ]);
        const openingMap = Object.fromEntries(openingStocks.map((o: any) => [o.productId, Number(o.openingStock || 0)]));
        const importMap: Record<string, number> = {};
        imports.forEach((im: any) => {
          importMap[im.productId] = (importMap[im.productId] || 0) + Number(im.quantity);
        });
        const exportMap: Record<string, number> = {};
        exports.forEach((ex: any) => {
          exportMap[ex.productId] = (exportMap[ex.productId] || 0) + Number(ex.quantity);
        });
        const rows = products.filter((p: any) => p.itemType === 'RAW').map((p: any) => {
          const opening = openingMap[p.id] || 0;
          const importQty = importMap[p.id] || 0;
          const exportQty = exportMap[p.id] || 0;
          const ending = opening + importQty - exportQty;
          return {
            id: p.id,
            productName: p.name,
            unit: p.unit,
            opening,
            importQty,
            exportQty,
            ending,
            unitCost: Number(p.costPrice),
            totalCost: ending * Number(p.costPrice),
          };
        });
        setBackdataRows(rows);
      }
    } catch (err) {
      console.warn('Failed to load backdata', err);
      setBackdataRows([]);
    } finally {
      setBackdataLoading(false);
    }
  };

  const getBackdataColumns = (): GridColDef[] => {
    switch (backdataKind) {
      case 'revenue':
      case 'discount':
      case 'net_revenue':
      case 'profit':
      case 'net_profit':
        return [
          { field: 'createdAt', headerName: 'Thời gian', width: 140, valueFormatter: (v) => formatDateTime(String(v)) },
          { field: 'customerName', headerName: 'Khách hàng', flex: 1, minWidth: 120 },
          { field: 'employeeName', headerName: 'Nhân viên', width: 110 },
          {
            field: 'subtotal',
            headerName: 'Tạm tính',
            width: 110,
            align: 'right',
            headerAlign: 'right',
            valueGetter: (_, row) => {
              const sub = (row.items || []).reduce((sum: number, it: any) => sum + Number(it.unitPrice || 0) * Number(it.quantity || 0), 0);
              return sub;
            },
            valueFormatter: (v) => formatCurrency(Number(v))
          },
          { field: 'discount', headerName: 'Giảm giá', width: 90, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
          {
            field: 'total',
            headerName: 'Tổng cộng',
            width: 110,
            align: 'right',
            headerAlign: 'right',
            valueGetter: (_, row) => {
              const sub = (row.items || []).reduce((sum: number, it: any) => sum + Number(it.unitPrice || 0) * Number(it.quantity || 0), 0);
              return Math.max(0, sub - Number(row.discount || 0));
            },
            valueFormatter: (v) => formatCurrency(Number(v))
          },
          { field: 'paidAmount', headerName: 'Đã trả', width: 100, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
          {
            field: 'debt',
            headerName: 'Còn nợ',
            width: 100,
            align: 'right',
            headerAlign: 'right',
            valueGetter: (_, row) => {
              const sub = (row.items || []).reduce((sum: number, it: any) => sum + Number(it.unitPrice || 0) * Number(it.quantity || 0), 0);
              const total = Math.max(0, sub - Number(row.discount || 0));
              return Math.max(0, total - Number(row.paidAmount || 0));
            },
            valueFormatter: (v) => formatCurrency(Number(v))
          },
          { field: 'paymentType', headerName: 'Hình thức', width: 100, valueFormatter: (v) => v === 'CASH' ? '💵 Tiền mặt' : '🏦 Banking' },
        ];
      case 'cost':
      case 'export_history':
        return [
          { field: 'createdAt', headerName: 'Thời gian', width: 140, valueFormatter: (v) => formatDateTime(String(v)) },
          { field: 'productName', headerName: 'Tên SP/Nguyên liệu', flex: 1, minWidth: 140 },
          { field: 'quantity', headerName: 'Số lượng', width: 85, align: 'center', headerAlign: 'center' },
          { field: 'unitCost', headerName: 'Giá vốn', width: 110, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
          { field: 'totalCost', headerName: 'Trị giá vốn', width: 120, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
          { field: 'itemType', headerName: 'Kiểu xuất', width: 110, valueFormatter: (v) => v === 'MIX' ? 'Từ món MIX' : 'Hàng thô' },
          { field: 'customerName', headerName: 'Khách hàng', width: 120 },
          {
            field: 'saleId',
            headerName: 'Mã đơn',
            width: 90,
            valueFormatter: (v) => v ? `#${String(v).slice(-6).toUpperCase()}` : '—',
          },
        ];
      case 'cash':
      case 'bank':
      case 'total_paid':
        return [
          { field: 'createdAt', headerName: 'Thời gian', width: 140, valueFormatter: (v) => formatDateTime(String(v)) },
          { field: 'type', headerName: 'Hạng mục', width: 110 },
          { field: 'description', headerName: 'Nội dung', flex: 1, minWidth: 150 },
          { field: 'party', headerName: 'Đối tác', width: 130 },
          { field: 'amount', headerName: 'Số tiền', width: 120, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
          { field: 'paymentType', headerName: 'Hình thức', width: 100 },
        ];
      case 'outstanding':
        return [
          { field: 'createdAt', headerName: 'Thời gian', width: 140, valueFormatter: (v) => formatDateTime(String(v)) },
          {
            field: 'id',
            headerName: 'Mã đơn',
            width: 100,
            valueFormatter: (v) => v ? `#${String(v).slice(-6).toUpperCase()}` : '—',
          },
          { field: 'customerName', headerName: 'Khách hàng', flex: 1, minWidth: 130 },
          {
            field: 'total',
            headerName: 'Tổng đơn',
            width: 110,
            align: 'right',
            headerAlign: 'right',
            valueGetter: (_, row) => {
              const sub = (row.items || []).reduce((sum: number, it: any) => sum + Number(it.unitPrice || 0) * Number(it.quantity || 0), 0);
              return Math.max(0, sub - Number(row.discount || 0));
            },
            valueFormatter: (v) => formatCurrency(Number(v))
          },
          { field: 'paidAmount', headerName: 'Đã trả', width: 100, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
          {
            field: 'debt',
            headerName: 'Còn nợ',
            width: 100,
            align: 'right',
            headerAlign: 'right',
            valueGetter: (_, row) => {
              const sub = (row.items || []).reduce((sum: number, it: any) => sum + Number(it.unitPrice || 0) * Number(it.quantity || 0), 0);
              const total = Math.max(0, sub - Number(row.discount || 0));
              return Math.max(0, total - Number(row.paidAmount || 0));
            },
            valueFormatter: (v) => formatCurrency(Number(v))
          },
        ];
      case 'expenses':
      case 'expense_reasonable':
      case 'expense_outside':
        return [
          { field: 'occurredAt', headerName: 'Thời gian', width: 140, valueFormatter: (v) => formatDateTime(String(v)) },
          { field: 'name', headerName: 'Tên chi phí', flex: 1, minWidth: 140 },
          { field: 'category', headerName: 'Hạng mục', width: 150 },
          { field: 'amount', headerName: 'Số tiền', width: 120, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
          { field: 'note', headerName: 'Ghi chú', width: 140 },
        ];
      case 'owe':
      case 'owed':
        return [
          { field: 'createdAt', headerName: 'Ngày ghi', width: 110, valueFormatter: (v) => new Date(v).toLocaleDateString('vi-VN') },
          { field: 'partyName', headerName: 'Đối tác', flex: 1, minWidth: 140 },
          { field: 'description', headerName: 'Nội dung', flex: 1, minWidth: 150 },
          { field: 'initialAmount', headerName: 'Nợ ban đầu', width: 110, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
          { field: 'amount', headerName: 'Còn lại', width: 110, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
          { field: 'dueDate', headerName: 'Hạn trả', width: 110, valueFormatter: (v) => v ? new Date(v).toLocaleDateString('vi-VN') : '—' },
        ];
      case 'opening_stock':
        return [
          { field: 'productName', headerName: 'Tên nguyên liệu/SP thô', flex: 1, minWidth: 160 },
          { field: 'unit', headerName: 'ĐVT', width: 70, align: 'center', headerAlign: 'center' },
          { field: 'quantity', headerName: 'Tồn đầu kỳ', width: 110, align: 'center', headerAlign: 'center' },
          { field: 'unitCost', headerName: 'Đơn giá vốn', width: 110, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
          { field: 'totalCost', headerName: 'Tổng trị giá vốn', width: 120, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
          { field: 'unitPrice', headerName: 'Đơn giá bán', width: 110, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
          { field: 'totalPrice', headerName: 'Tổng trị giá bán', width: 120, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
        ];
      case 'import_history':
        return [
          { field: 'createdAt', headerName: 'Thời gian', width: 140, valueFormatter: (v) => formatDateTime(String(v)) },
          { field: 'productName', headerName: 'Tên sản phẩm', flex: 1, minWidth: 150 },
          { field: 'supplierName', headerName: 'Nhà cung cấp', width: 140 },
          { field: 'quantity', headerName: 'SL nhập', width: 90, align: 'center', headerAlign: 'center' },
          { field: 'unitCost', headerName: 'Giá nhập', width: 110, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
          { field: 'totalCost', headerName: 'Thành tiền', width: 120, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
          { field: 'note', headerName: 'Ghi chú', width: 130 },
        ];
      case 'ending_stock':
        return [
          { field: 'productName', headerName: 'Tên nguyên liệu/SP thô', flex: 1, minWidth: 160 },
          { field: 'unit', headerName: 'ĐVT', width: 70, align: 'center', headerAlign: 'center' },
          { field: 'opening', headerName: 'Tồn đầu kỳ', width: 95, align: 'center', headerAlign: 'center' },
          { field: 'importQty', headerName: 'Nhập trong kỳ', width: 95, align: 'center', headerAlign: 'center' },
          { field: 'exportQty', headerName: 'Xuất trong kỳ', width: 95, align: 'center', headerAlign: 'center' },
          { field: 'ending', headerName: 'Tồn cuối kỳ', width: 95, align: 'center', headerAlign: 'center' },
          { field: 'unitCost', headerName: 'Giá vốn', width: 110, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
          { field: 'totalCost', headerName: 'Tổng trị giá vốn', width: 125, align: 'right', headerAlign: 'right', valueFormatter: (v) => formatCurrency(Number(v)) },
        ];
      default:
        return [];
    }
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
            <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider">Tóm tắt 14 KPIs kinh doanh (Click để xem chi tiết)</h3>
            <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
              {/* Doanh thu gộp */}
              <div
                onClick={() => openBackdata('revenue', '1. Chi tiết doanh thu gộp')}
                className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all cursor-pointer hover:border-indigo-500/40 hover:bg-slate-900/80"
              >
                <span className="text-[10px] text-slate-500 font-bold uppercase">1. Doanh thu gộp</span>
                <span className="text-base font-extrabold text-white mt-1.5">{formatCurrency(kpis?.totalRevenue || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Tổng tiền mặt bán hàng gốc</span>
              </div>

              {/* Giảm giá */}
              <div
                onClick={() => openBackdata('discount', '2. Chi tiết giảm giá')}
                className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all cursor-pointer hover:border-indigo-500/40 hover:bg-slate-900/80"
              >
                <span className="text-[10px] text-slate-500 font-bold uppercase">2. Tổng giảm giá</span>
                <span className="text-base font-extrabold text-amber-500 mt-1.5">-{formatCurrency(kpis?.totalDiscount || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Chiết khấu trực tiếp trên bill</span>
              </div>

              {/* Doanh thu thuần */}
              <div
                onClick={() => openBackdata('net_revenue', '3. Chi tiết doanh thu thuần')}
                className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all cursor-pointer hover:border-indigo-500/40 hover:bg-slate-900/80"
              >
                <span className="text-[10px] text-slate-500 font-bold uppercase">3. Doanh thu thuần</span>
                <span className="text-base font-extrabold text-indigo-400 mt-1.5">{formatCurrency(kpis?.netRevenue || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Doanh thu gộp - giảm giá</span>
              </div>

              {/* Giá vốn */}
              <div
                onClick={() => openBackdata('cost', '4. Chi tiết giá vốn')}
                className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all cursor-pointer hover:border-indigo-500/40 hover:bg-slate-900/80"
              >
                <span className="text-[10px] text-slate-500 font-bold uppercase">4. Tổng giá vốn</span>
                <span className="text-base font-extrabold text-slate-300 mt-1.5">{formatCurrency(kpis?.totalCost || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Gồm giá thô và MIX phân rã</span>
              </div>

              {/* Lợi nhuận gộp */}
              <div
                onClick={() => openBackdata('profit', '5. Chi tiết lợi nhuận gộp')}
                className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all cursor-pointer hover:border-indigo-500/40 hover:bg-slate-900/80"
              >
                <span className="text-[10px] text-slate-500 font-bold uppercase">5. Lợi nhuận gộp</span>
                <span className="text-base font-extrabold text-cyan-400 mt-1.5">{formatCurrency(kpis?.grossProfit || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Doanh thu thuần - giá vốn</span>
              </div>

              {/* Thu tiền mặt */}
              <div
                onClick={() => openBackdata('cash', '6. Chi tiết thu tiền mặt')}
                className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all cursor-pointer hover:border-indigo-500/40 hover:bg-slate-900/80"
              >
                <span className="text-[10px] text-slate-500 font-bold uppercase">6. Thu TM (Đơn hàng)</span>
                <span className="text-base font-extrabold text-emerald-400 mt-1.5">{formatCurrency(kpis?.cashRevenue || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Tiền mặt đơn + Thu nợ gốc</span>
              </div>

              {/* Thu chuyển khoản */}
              <div
                onClick={() => openBackdata('bank', '7. Chi tiết thu chuyển khoản')}
                className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all cursor-pointer hover:border-indigo-500/40 hover:bg-slate-900/80"
              >
                <span className="text-[10px] text-slate-500 font-bold uppercase">7. Thu CK (Đơn hàng)</span>
                <span className="text-base font-extrabold text-sky-400 mt-1.5">{formatCurrency(kpis?.bankRevenue || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Banking đơn + Thu nợ chuyển khoản</span>
              </div>

              {/* Nợ phát sinh */}
              <div
                onClick={() => openBackdata('outstanding', '8. Chi tiết nợ bán hàng còn lại')}
                className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all cursor-pointer hover:border-indigo-500/40 hover:bg-slate-900/80"
              >
                <span className="text-[10px] text-slate-500 font-bold uppercase">8. Nợ bán hàng còn lại</span>
                <span className="text-base font-extrabold text-rose-400 mt-1.5">{formatCurrency(kpis?.outstandingDebt || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Nợ chưa thu từ các đơn trong kỳ</span>
              </div>

              {/* Tổng chi phí */}
              <div
                onClick={() => openBackdata('expenses', '9. Chi tiết tổng chi phí')}
                className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all cursor-pointer hover:border-indigo-500/40 hover:bg-slate-900/80"
              >
                <span className="text-[10px] text-slate-500 font-bold uppercase">9. Tổng chi phí</span>
                <span className="text-base font-extrabold text-rose-300 mt-1.5">{formatCurrency(kpis?.totalExpenses || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Mọi khoản chi phát sinh</span>
              </div>

              {/* Chi phí hợp lý */}
              <div
                onClick={() => openBackdata('expense_reasonable', '10. Chi tiết chi phí hợp lý')}
                className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all cursor-pointer hover:border-indigo-500/40 hover:bg-slate-900/80"
              >
                <span className="text-[10px] text-slate-500 font-bold uppercase">10. Chi phí hợp lý</span>
                <span className="text-base font-extrabold text-slate-200 mt-1.5">{formatCurrency(kpis?.expenseReasonable || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Chi phí kinh doanh phục vụ vận hành</span>
              </div>

              {/* Ngoài kinh doanh */}
              <div
                onClick={() => openBackdata('expense_outside', '11. Chi tiết chi tiêu ngoài kinh doanh')}
                className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all cursor-pointer hover:border-indigo-500/40 hover:bg-slate-900/80"
              >
                <span className="text-[10px] text-slate-500 font-bold uppercase">11. Chi tiêu ngoài KD</span>
                <span className="text-base font-extrabold text-purple-400 mt-1.5">{formatCurrency(kpis?.expenseOutsideBusiness || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Rút vốn chi cá nhân</span>
              </div>

              {/* Nợ phải trả */}
              <div
                onClick={() => openBackdata('owe', '12. Chi tiết nợ phải trả (Owe)')}
                className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all cursor-pointer hover:border-indigo-500/40 hover:bg-slate-900/80"
              >
                <span className="text-[10px] text-slate-500 font-bold uppercase">12. Nợ phải trả (Owe)</span>
                <span className="text-base font-extrabold text-orange-400 mt-1.5">{formatCurrency(kpis?.totalOwe || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Tiền nợ NCC còn lại lũy kế</span>
              </div>

              {/* Nợ phải thu */}
              <div
                onClick={() => openBackdata('owed', '13. Chi tiết nợ phải thu (Owed)')}
                className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all cursor-pointer hover:border-indigo-500/40 hover:bg-slate-900/80"
              >
                <span className="text-[10px] text-slate-500 font-bold uppercase">13. Nợ phải thu (Owed)</span>
                <span className="text-base font-extrabold text-yellow-500 mt-1.5">{formatCurrency(kpis?.totalOwed || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Tiền khách nợ tôi lũy kế</span>
              </div>

              {/* Lợi nhuận ròng */}
              <div
                onClick={() => openBackdata('net_profit', '14. Chi tiết lợi nhuận ròng')}
                className="card bg-gradient-to-tr from-indigo-500/10 to-cyan-500/10 border-indigo-500/20 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all shadow-md cursor-pointer hover:border-indigo-500/40 hover:brightness-110"
              >
                <span className="text-[10px] text-indigo-300 font-extrabold uppercase">14. Lợi nhuận ròng</span>
                <span className="text-lg font-black text-emerald-400 mt-1.5">{formatCurrency(kpis?.netProfit || 0)}</span>
                <span className="text-[9px] text-slate-400 mt-1">Lợi nhuận gộp - chi phí hợp lý</span>
              </div>
            </div>
          </div>

          {/* Dòng tiền thực thu trong kỳ */}
          <div className="space-y-4">
            <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider">Dòng tiền thực thu trong kỳ (Tiền thực tế nhận & Thu nợ)</h3>
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
              {/* Tổng thực thu */}
              <div
                onClick={() => openBackdata('total_paid', 'Chi tiết Tổng thực thu trong kỳ')}
                className="card bg-gradient-to-tr from-indigo-500/10 to-emerald-500/10 border-indigo-500/20 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all cursor-pointer hover:border-indigo-500/40 hover:bg-slate-900/80"
              >
                <span className="text-[10px] text-indigo-300 font-bold uppercase">Tổng thực thu (trong kỳ)</span>
                <span className="text-base font-extrabold text-white mt-1.5">{formatCurrency((kpis?.cashPaid || 0) + (kpis?.bankPaid || 0))}</span>
                <span className="text-[9px] text-slate-500 mt-1">Tổng tiền mặt + Chuyển khoản thực nhận</span>
              </div>

              {/* Thu TM trong kỳ */}
              <div
                onClick={() => openBackdata('cash', 'Chi tiết Thu tiền mặt thực tế trong kỳ')}
                className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all cursor-pointer hover:border-indigo-500/40 hover:bg-slate-900/80"
              >
                <span className="text-[10px] text-slate-500 font-bold uppercase">Thu TM (Thực tế trong kỳ)</span>
                <span className="text-base font-extrabold text-emerald-400 mt-1.5">{formatCurrency(kpis?.cashPaid || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Tiền mặt từ đơn hàng và thu nợ</span>
              </div>

              {/* Thu CK trong kỳ */}
              <div
                onClick={() => openBackdata('bank', 'Chi tiết Thu chuyển khoản thực tế trong kỳ')}
                className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all cursor-pointer hover:border-indigo-500/40 hover:bg-slate-900/80"
              >
                <span className="text-[10px] text-slate-500 font-bold uppercase">Thu CK (Thực tế trong kỳ)</span>
                <span className="text-base font-extrabold text-sky-400 mt-1.5">{formatCurrency(kpis?.bankPaid || 0)}</span>
                <span className="text-[9px] text-slate-500 mt-1">Banking từ đơn hàng và thu nợ</span>
              </div>
            </div>
          </div>

          {/* Tổng quan tồn kho RAW */}
          <div className="space-y-4">
            <h3 className="text-xs font-bold text-slate-400 uppercase tracking-wider">Tổng quan tồn kho RAW (Click để xem chi tiết)</h3>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
              {/* Tồn đầu kỳ */}
              <div
                onClick={() => openBackdata('opening_stock', 'Chi tiết tồn đầu kỳ')}
                className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all cursor-pointer hover:border-indigo-500/40 hover:bg-slate-900/80"
              >
                <span className="text-[10px] text-slate-500 font-bold uppercase">Tồn đầu kỳ</span>
                <span className="text-base font-extrabold text-white mt-1.5">{inventorySummary.openingQty.toLocaleString('vi-VN')}</span>
                <div className="flex justify-between items-center text-[9px] text-slate-500 mt-1.5 border-t border-white/5 pt-1.5">
                  <span>Vốn: {formatCurrency(inventorySummary.openingCost)}</span>
                  <span>Bán: {formatCurrency(inventorySummary.openingSell)}</span>
                </div>
              </div>

              {/* Nhập trong kỳ */}
              <div
                onClick={() => openBackdata('import_history', 'Chi tiết nhập kho trong kỳ')}
                className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all cursor-pointer hover:border-indigo-500/40 hover:bg-slate-900/80"
              >
                <span className="text-[10px] text-slate-500 font-bold uppercase">Nhập trong kỳ</span>
                <span className="text-base font-extrabold text-emerald-400 mt-1.5">+{inventorySummary.importQty.toLocaleString('vi-VN')}</span>
                <div className="flex justify-between items-center text-[9px] text-slate-500 mt-1.5 border-t border-white/5 pt-1.5">
                  <span>Vốn: {formatCurrency(inventorySummary.importCost)}</span>
                  <span>Bán: {formatCurrency(inventorySummary.importSell)}</span>
                </div>
              </div>

              {/* Xuất trong kỳ */}
              <div
                onClick={() => openBackdata('export_history', 'Chi tiết xuất kho trong kỳ')}
                className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all cursor-pointer hover:border-indigo-500/40 hover:bg-slate-900/80"
              >
                <span className="text-[10px] text-slate-500 font-bold uppercase">Xuất trong kỳ</span>
                <span className="text-base font-extrabold text-rose-400 mt-1.5">-{inventorySummary.exportQty.toLocaleString('vi-VN')}</span>
                <div className="flex justify-between items-center text-[9px] text-slate-500 mt-1.5 border-t border-white/5 pt-1.5">
                  <span>Vốn: {formatCurrency(inventorySummary.exportCost)}</span>
                  <span>Bán: {formatCurrency(inventorySummary.exportSell)}</span>
                </div>
              </div>

              {/* Tồn cuối kỳ */}
              <div
                onClick={() => openBackdata('ending_stock', 'Chi tiết tồn cuối kỳ')}
                className="card bg-slate-900/50 border-white/5 p-4 flex flex-col justify-between hover:scale-[1.02] transition-all cursor-pointer hover:border-indigo-500/40 hover:bg-slate-900/80"
              >
                <span className="text-[10px] text-slate-500 font-bold uppercase">Tồn cuối kỳ</span>
                <span className="text-base font-extrabold text-indigo-400 mt-1.5">{inventorySummary.endingQty.toLocaleString('vi-VN')}</span>
                <div className="flex justify-between items-center text-[9px] text-slate-500 mt-1.5 border-t border-white/5 pt-1.5">
                  <span>Vốn: {formatCurrency(inventorySummary.endingCost)}</span>
                  <span>Bán: {formatCurrency(inventorySummary.endingSell)}</span>
                </div>
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

      {/* Backdata Modal */}
      <Modal
        open={backdataModalOpen}
        onClose={() => setBackdataModalOpen(false)}
        title={backdataTitle}
        maxWidth="max-w-5xl"
      >
        <div className="space-y-4">
          <div className="flex justify-between items-center text-xs text-slate-400">
            <span>Khoảng thời gian: {startDate} ➔ {endDate}</span>
            <span>Tổng cộng: {backdataRows.length} bản ghi</span>
          </div>

          <div className="border border-white/5 rounded-xl overflow-hidden bg-slate-950/20">
            <AppDataGrid
              rows={backdataRows}
              columns={getBackdataColumns()}
              loading={backdataLoading}
              height={450}
            />
          </div>

          <div className="flex justify-end gap-3 pt-2">
            <button
              onClick={exportBackdataExcel}
              disabled={backdataRows.length === 0}
              className="btn btn-primary text-xs py-2 px-4 rounded-xl font-semibold shadow-glow cursor-pointer flex items-center gap-1.5"
            >
              📥 Xuất file Excel
            </button>
            <button
              onClick={() => setBackdataModalOpen(false)}
              className="btn btn-secondary text-xs py-2 px-4 rounded-xl font-semibold hover:bg-slate-800 cursor-pointer"
            >
              Đóng
            </button>
          </div>
        </div>
      </Modal>
    </div>
  );
}
