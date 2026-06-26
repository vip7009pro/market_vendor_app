import { Router, Response } from 'express';
import prisma from '../config/database.js';
import { authMiddleware, AuthRequest } from '../middleware/auth.js';

const router = Router();
router.use(authMiddleware);

const notDeleted = { deletedAt: null };

// ─── GET /api/reports/dashboard ──────────────────────
// KPIs for dashboard and detailed reports
router.get('/dashboard', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const { startDate, endDate, employeeId } = req.query;

    const start = startDate ? new Date(String(startDate)) : new Date(new Date().getFullYear(), new Date().getMonth(), 1);
    const end = endDate ? new Date(String(endDate)) : new Date();
    end.setHours(23, 59, 59, 999);

    // 1. Sales filters
    const saleWhere: any = {
      userId,
      ...notDeleted,
      createdAt: {
        gte: start,
        lte: end,
      },
    };
    if (employeeId) {
      saleWhere.employeeId = String(employeeId);
    }

    const sales = await prisma.sale.findMany({
      where: saleWhere,
      include: {
        items: { where: notDeleted },
      },
    });

    // 2. Calculate Revenue, cost and profit from sales
    let totalRevenue = 0;
    let totalDiscount = 0;
    let totalCost = 0;

    for (const sale of sales) {
      const discount = Number(sale.discount || 0);
      totalDiscount += discount;
      totalCost += Number(sale.totalCost || 0);
      
      const subtotal = sale.items.reduce((sum, item) => sum + (Number(item.unitPrice) * Number(item.quantity)), 0);
      totalRevenue += subtotal;
    }

    const netRevenue = totalRevenue - totalDiscount;
    const grossProfit = netRevenue - totalCost;

    // 3. Calculate Cash and Bank revenue, outstanding debt from those sales in period
    const saleIds = sales.map(s => s.id);
    let cashRevenue = 0;
    let bankRevenue = 0;
    let outstandingDebt = 0;

    for (const sale of sales) {
      const paid = Number(sale.paidAmount || 0);
      if (paid > 0) {
        const type = (sale.paymentType || '').toLowerCase();
        if (type === 'cash') {
          cashRevenue += paid;
        } else {
          bankRevenue += paid; // Default to bank if not cash
        }
      }
    }

    if (saleIds.length > 0) {
      const debts = await prisma.debt.findMany({
        where: {
          userId,
          ...notDeleted,
          sourceType: 'sale',
          sourceId: { in: saleIds },
        },
        include: {
          payments: { where: notDeleted },
        },
      });

      for (const d of debts) {
        outstandingDebt += Number(d.amount); // amount column stores the current unpaid balance

        for (const p of d.payments) {
          const pAmount = Number(p.amount);
          const pType = (p.paymentType || '').toLowerCase();
          if (pType === 'cash') {
            cashRevenue += pAmount;
          } else {
            bankRevenue += pAmount;
          }
        }
      }
    }

    // 4. Calculate Expenses
    const expenseWhere: any = {
      userId,
      ...notDeleted,
      occurredAt: {
        gte: start,
        lte: end,
      },
    };

    const expenses = await prisma.expense.findMany({
      where: expenseWhere,
    });

    let totalExpenses = 0;
    let expenseOutsideBusiness = 0;

    for (const e of expenses) {
      const amount = Number(e.amount || 0);
      totalExpenses += amount;
      if (e.category === 'Chi tiêu ngoài kinh doanh') {
        expenseOutsideBusiness += amount;
      }
    }

    const expenseReasonable = totalExpenses - expenseOutsideBusiness;
    const netProfit = grossProfit - expenseReasonable;

    // 5. Total outstanding debts (cumulative, not bounded by date)
    const totalOweFilter: any = { userId, ...notDeleted, settled: false, type: 0 };
    const totalOwedFilter: any = { userId, ...notDeleted, settled: false, type: 1 };
    if (employeeId) {
      // For customer debts (type 1), we can filter by employeeId of associated sales if exists
      // But typically employeeId isn't stored in debts directly. We can filter debts linked to sales of this employee
      const employeeSales = await prisma.sale.findMany({
        where: { userId, employeeId: String(employeeId), ...notDeleted },
        select: { id: true },
      });
      const empSaleIds = employeeSales.map(s => s.id);
      totalOwedFilter.OR = [
        { sourceType: 'sale', sourceId: { in: empSaleIds } },
        { sourceType: { not: 'sale' } }, // Keep custom debts
      ];
    }

    const [debtsOwe, debtsOwed] = await Promise.all([
      prisma.debt.findMany({ where: totalOweFilter, select: { amount: true } }),
      prisma.debt.findMany({ where: totalOwedFilter, select: { amount: true } }),
    ]);

    const totalOwe = debtsOwe.reduce((sum, d) => sum + Number(d.amount), 0); // Tiền tôi nợ đối tác (oweOthers)
    const totalOwed = debtsOwed.reduce((sum, d) => sum + Number(d.amount), 0); // Tiền khách nợ tôi (othersOweMe)

    // 6. Cash and Bank paid in period (based on payment date)
    let cashPaid = 0;
    let bankPaid = 0;

    // Cash/bank from direct sales payments in period
    for (const sale of sales) {
      const paid = Number(sale.paidAmount || 0);
      if (paid > 0) {
        const type = (sale.paymentType || '').toLowerCase();
        if (type === 'cash') {
          cashPaid += paid;
        } else {
          bankPaid += paid;
        }
      }
    }

    // Cash/bank from debt payments in period
    const empSaleIdsInPeriod = employeeId 
      ? await prisma.sale.findMany({
          where: { userId, employeeId: String(employeeId), ...notDeleted },
          select: { id: true }
        }).then(list => list.map(s => s.id))
      : [];

    const debtPaymentWhere: any = {
      userId,
      ...notDeleted,
      createdAt: {
        gte: start,
        lte: end,
      },
      debt: {
        ...notDeleted,
        sourceType: 'sale',
        ...(employeeId ? { sourceId: { in: empSaleIdsInPeriod } } : {}),
      },
    };

    const debtPayments = await prisma.debtPayment.findMany({
      where: debtPaymentWhere,
      select: { amount: true, paymentType: true },
    });

    for (const dp of debtPayments) {
      const amount = Number(dp.amount || 0);
      const type = (dp.paymentType || '').toLowerCase();
      if (type === 'cash') {
        cashPaid += amount;
      } else {
        bankPaid += amount;
      }
    }

    // 7. Entity counts
    const [productCount, customerCount, saleCount] = await Promise.all([
      prisma.product.count({ where: { userId, ...notDeleted, isActive: true } }),
      prisma.customer.count({ where: { userId, ...notDeleted } }),
      prisma.sale.count({ where: { userId, ...notDeleted, ...saleWhere } }),
    ]);

    res.json({
      data: {
        totalRevenue,               // Doanh thu gộp
        totalDiscount,              // Giảm giá
        netRevenue,                 // Doanh thu thuần
        totalCost,                  // Giá vốn
        grossProfit,                // Lợi nhuận gộp
        cashRevenue,                // Thu tiền mặt (Bán hàng + Thu nợ) của các đơn hàng trong kỳ
        bankRevenue,                // Thu chuyển khoản (Bán hàng + Thu nợ) của các đơn hàng trong kỳ
        outstandingDebt,            // Nợ bán hàng còn lại phát sinh từ các đơn hàng trong kỳ
        totalExpenses,              // Tổng chi phí
        expenseReasonable,          // Chi phí hợp lý (trừ chi tiêu ngoài kd)
        expenseOutsideBusiness,     // Chi tiêu ngoài kinh doanh
        totalOwe,                   // Nợ tôi phải trả (oweOthers)
        totalOwed,                  // Nợ khách phải trả tôi (othersOweMe)
        netProfit,                  // Lợi nhuận ròng = Lợi nhuận gộp - Chi phí hợp lý
        cashPaid,                   // Thu tiền mặt thực tế phát sinh trong khoảng thời gian chọn
        bankPaid,                   // Thu chuyển khoản thực tế phát sinh trong khoảng thời gian chọn
        productCount,
        customerCount,
        saleCount,
      },
    });
  } catch (error) {
    console.error('Dashboard report error:', error);
    res.status(500).json({ error: 'Failed to generate dashboard report' });
  }
});

// ─── GET /api/reports/top-products ───────────────────
router.get('/top-products', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const { startDate, endDate, employeeId, limit = '10' } = req.query;

    const start = startDate ? new Date(String(startDate)) : new Date(new Date().getFullYear(), new Date().getMonth(), 1);
    const end = endDate ? new Date(String(endDate)) : new Date();
    end.setHours(23, 59, 59, 999);

    const saleWhere: any = {
      userId,
      ...notDeleted,
      createdAt: { gte: start, lte: end },
    };
    if (employeeId) {
      saleWhere.employeeId = String(employeeId);
    }

    const saleItems = await prisma.saleItem.findMany({
      where: {
        userId,
        ...notDeleted,
        sale: saleWhere,
      },
      select: {
        productId: true,
        name: true,
        unit: true,
        unitPrice: true,
        quantity: true,
        itemType: true,
        displayName: true,
        mixItemsJson: true,
      },
    });

    const productAgg: Record<string, { name: string; unit: string; quantity: number; totalRev: number }> = {};

    for (const item of saleItems) {
      const type = (item.itemType || '').toUpperCase().trim();
      const displayName = (type === 'MIX' && item.displayName) ? item.displayName.trim() : item.name;
      const key = item.productId || displayName;

      if (!productAgg[key]) {
        productAgg[key] = {
          name: displayName,
          unit: item.unit || 'cái',
          quantity: 0,
          totalRev: 0,
        };
      }

      const qty = Number(item.quantity || 0);
      productAgg[key].quantity += qty;
      productAgg[key].totalRev += qty * Number(item.unitPrice || 0);
    }

    const result = Object.values(productAgg)
      .sort((a, b) => b.quantity - a.quantity || b.totalRev - a.totalRev)
      .slice(0, parseInt(String(limit)));

    res.json({ data: result });
  } catch (error) {
    console.error('Top products report error:', error);
    res.status(500).json({ error: 'Failed to generate top products report' });
  }
});

// ─── GET /api/reports/expenses-ratio ─────────────────
router.get('/expenses-ratio', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const { startDate, endDate } = req.query;

    const start = startDate ? new Date(String(startDate)) : new Date(new Date().getFullYear(), new Date().getMonth(), 1);
    const end = endDate ? new Date(String(endDate)) : new Date();
    end.setHours(23, 59, 59, 999);

    const expenses = await prisma.expense.findMany({
      where: {
        userId,
        ...notDeleted,
        occurredAt: { gte: start, lte: end },
        category: { not: 'Chi tiêu ngoài kinh doanh' },
      },
      select: { amount: true, category: true },
    });

    const categoryAgg: Record<string, number> = {};
    let totalReasonable = 0;

    for (const e of expenses) {
      const amount = Number(e.amount || 0);
      const cat = e.category.trim();
      categoryAgg[cat] = (categoryAgg[cat] || 0) + amount;
      totalReasonable += amount;
    }

    const result = Object.entries(categoryAgg).map(([category, amount]) => {
      const percentage = totalReasonable > 0 ? (amount / totalReasonable) * 100 : 0;
      return {
        category,
        amount,
        percentage,
      };
    }).sort((a, b) => b.amount - a.amount);

    res.json({ data: result, total: totalReasonable });
  } catch (error) {
    console.error('Expenses ratio report error:', error);
    res.status(500).json({ error: 'Failed to generate expenses ratio report' });
  }
});

// ─── GET /api/reports/revenue — Grouped revenue & profit ───
router.get('/revenue', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const { startDate, endDate, employeeId, groupBy = 'day' } = req.query;

    if (!startDate || !endDate) {
      res.status(400).json({ error: 'startDate and endDate are required' });
      return;
    }

    const start = new Date(String(startDate));
    const end = new Date(String(endDate));
    end.setHours(23, 59, 59, 999);

    const saleWhere: any = {
      userId,
      ...notDeleted,
      createdAt: { gte: start, lte: end },
    };
    if (employeeId) {
      saleWhere.employeeId = String(employeeId);
    }

    const sales = await prisma.sale.findMany({
      where: saleWhere,
      include: { items: { where: notDeleted } },
      orderBy: { createdAt: 'asc' },
    });

    const expenseWhere: any = {
      userId,
      ...notDeleted,
      occurredAt: { gte: start, lte: end },
    };
    const expenses = await prisma.expense.findMany({
      where: expenseWhere,
    });

    const groupedData: Record<string, { revenue: number; cost: number; count: number; profit: number; expenses: number; netProfit: number }> = {};

    // Group Sales
    for (const sale of sales) {
      let groupKey = '';
      const date = sale.createdAt;
      
      if (groupBy === 'year') {
        groupKey = `${date.getFullYear()}`;
      } else if (groupBy === 'month') {
        groupKey = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
      } else {
        groupKey = date.toISOString().split('T')[0]; // day
      }

      if (!groupedData[groupKey]) {
        groupedData[groupKey] = { revenue: 0, cost: 0, count: 0, profit: 0, expenses: 0, netProfit: 0 };
      }

      const subtotal = sale.items.reduce((s, it) => s + Number(it.unitPrice) * Number(it.quantity), 0);
      const revenue = subtotal - Number(sale.discount || 0);

      groupedData[groupKey].revenue += revenue;
      groupedData[groupKey].cost += Number(sale.totalCost || 0);
      groupedData[groupKey].count += 1;
      groupedData[groupKey].profit += (revenue - Number(sale.totalCost || 0));
      groupedData[groupKey].netProfit += (revenue - Number(sale.totalCost || 0));
    }

    // Group Expenses (Chi phí hợp lý)
    for (const e of expenses) {
      if (e.category === 'Chi tiêu ngoài kinh doanh') continue;
      
      let groupKey = '';
      const date = e.occurredAt;
      
      if (groupBy === 'year') {
        groupKey = `${date.getFullYear()}`;
      } else if (groupBy === 'month') {
        groupKey = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
      } else {
        groupKey = date.toISOString().split('T')[0]; // day
      }

      if (!groupedData[groupKey]) {
        groupedData[groupKey] = { revenue: 0, cost: 0, count: 0, profit: 0, expenses: 0, netProfit: 0 };
      }

      const amount = Number(e.amount || 0);
      groupedData[groupKey].expenses += amount;
      groupedData[groupKey].netProfit -= amount;
    }

    const result = Object.entries(groupedData).map(([date, data]) => ({
      date,
      ...data,
    })).sort((a, b) => a.date.localeCompare(b.date));

    res.json({ data: result });
  } catch (error) {
    console.error('Revenue report error:', error);
    res.status(500).json({ error: 'Failed to generate revenue report' });
  }
});

// ─── GET /api/reports/opening-stocks ─────────────────
router.get('/opening-stocks', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const { year, month } = req.query;
    
    if (!year || !month) {
      res.status(400).json({ error: 'year and month are required' });
      return;
    }

    const rows = await prisma.productOpeningStock.findMany({
      where: {
        userId,
        year: parseInt(String(year)),
        month: parseInt(String(month)),
      },
    });

    res.json({ data: rows });
  } catch (error) {
    console.error('Get opening stocks error:', error);
    res.status(500).json({ error: 'Failed to get opening stocks' });
  }
});

// ─── POST /api/reports/opening-stocks ────────────────
router.post('/opening-stocks', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const { productId, year, month, openingStock } = req.body;

    if (!productId || !year || !month) {
      res.status(400).json({ error: 'productId, year, month are required' });
      return;
    }

    const row = await prisma.productOpeningStock.upsert({
      where: {
        userId_productId_year_month: {
          userId,
          productId,
          year: parseInt(String(year)),
          month: parseInt(String(month)),
        }
      },
      update: {
        openingStock: Number(openingStock),
        updatedAt: new Date(),
      },
      create: {
        userId,
        productId,
        year: parseInt(String(year)),
        month: parseInt(String(month)),
        openingStock: Number(openingStock),
        updatedAt: new Date(),
      }
    });

    res.json({ data: row });
  } catch (error) {
    console.error('Update opening stock error:', error);
    res.status(500).json({ error: 'Failed to update opening stock' });
  }
});

// ─── GET /api/reports/export-history ────────────────
router.get('/export-history', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const { search, startDate, endDate } = req.query;

    const where: any = {
      userId,
      ...notDeleted,
    };

    if (startDate || endDate) {
      where.sale = {
        createdAt: {},
      };
      if (startDate) where.sale.createdAt.gte = new Date(String(startDate));
      if (endDate) {
        const end = new Date(String(endDate));
        end.setHours(23, 59, 59, 999);
        where.sale.createdAt.lte = end;
      }
    }

    const saleItems = await prisma.saleItem.findMany({
      where,
      include: {
        sale: true,
      },
      orderBy: {
        updatedAt: 'desc',
      },
    });

    const exportRows: any[] = [];

    for (const item of saleItems) {
      if (item.sale.deletedAt) continue;
      const itemType = (item.itemType || '').toUpperCase().trim();
      const saleCreatedAt = item.sale.createdAt.toISOString();
      const customerName = item.sale.customerName || 'Khách vãng lai';

      if (itemType === 'MIX') {
        const mixJson = (item.mixItemsJson || '').trim();
        if (!mixJson) continue;
        try {
          const decoded = JSON.parse(mixJson);
          if (Array.isArray(decoded)) {
            for (const e of decoded) {
              const rid = (e.rawProductId || '').trim();
              if (!rid) continue;
              const rq = Number(e.rawQty || 0) * Number(item.quantity);
              const ruc = Number(e.rawUnitCost || 0);

              if (search) {
                const s = String(search).toLowerCase();
                const matches = e.rawName.toLowerCase().includes(s) ||
                                customerName.toLowerCase().includes(s) ||
                                item.saleId.toLowerCase().includes(s);
                if (!matches) continue;
              }

              exportRows.push({
                id: `${item.id}-${rid}`,
                saleId: item.saleId,
                createdAt: saleCreatedAt,
                customerName,
                employeeName: item.sale.employeeName || '—',
                productId: rid,
                productName: e.rawName,
                unit: e.rawUnit || '—',
                quantity: rq,
                unitPrice: null,
                totalPrice: null,
                unitCost: ruc,
                totalCost: rq * ruc,
                itemType: 'MIX',
              });
            }
          }
        } catch (_) {
          continue;
        }
      } else {
        const pid = item.productId;
        if (!pid) continue;
        const qty = Number(item.quantity || 0);
        const unitPrice = Number(item.unitPrice || 0);
        const unitCost = Number(item.unitCost || 0);

        if (search) {
          const s = String(search).toLowerCase();
          const matches = item.name.toLowerCase().includes(s) ||
                          customerName.toLowerCase().includes(s) ||
                          item.saleId.toLowerCase().includes(s);
          if (!matches) continue;
        }

        exportRows.push({
          id: item.id,
          saleId: item.saleId,
          createdAt: saleCreatedAt,
          customerName,
          employeeName: item.sale.employeeName || '—',
          productId: pid,
          productName: item.name,
          unit: item.unit,
          quantity: qty,
          unitPrice,
          totalPrice: qty * unitPrice,
          unitCost,
          totalCost: qty * unitCost,
          itemType: 'RAW',
        });
      }
    }

    res.json({ data: exportRows });
  } catch (error) {
    console.error('Get export history error:', error);
    res.status(500).json({ error: 'Failed to get export history' });
  }
});

export default router;
