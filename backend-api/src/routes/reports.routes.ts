import { Router, Response } from 'express';
import prisma from '../config/database.js';
import { authMiddleware, AuthRequest } from '../middleware/auth.js';

const router = Router();
router.use(authMiddleware);

const notDeleted = { deletedAt: null };

// ─── GET /api/reports/dashboard ──────────────────────
// KPIs for dashboard: total revenue, profit, debts, expenses
router.get('/dashboard', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const { startDate, endDate } = req.query;

    let dateFilter: any = {};
    if (startDate || endDate) {
      dateFilter.createdAt = {};
      if (startDate) dateFilter.createdAt.gte = new Date(String(startDate));
      if (endDate) {
        const end = new Date(String(endDate));
        end.setHours(23, 59, 59, 999);
        dateFilter.createdAt.lte = end;
      }
    }

    // Sales stats
    const sales = await prisma.sale.findMany({
      where: { userId, ...notDeleted, ...dateFilter },
      select: { paidAmount: true, discount: true, totalCost: true },
    });

    const saleItems = await prisma.saleItem.findMany({
      where: {
        userId,
        ...notDeleted,
        sale: { ...notDeleted, ...dateFilter },
      },
      select: { unitPrice: true, quantity: true },
    });

    const totalRevenue = saleItems.reduce((sum, item) => sum + Number(item.unitPrice) * Number(item.quantity), 0);
    const totalDiscount = sales.reduce((sum, s) => sum + Number(s.discount), 0);
    const netRevenue = totalRevenue - totalDiscount;
    const totalCost = sales.reduce((sum, s) => sum + Number(s.totalCost), 0);
    const grossProfit = netRevenue - totalCost;

    // Expenses
    let expenseDateFilter: any = {};
    if (startDate || endDate) {
      expenseDateFilter.occurredAt = {};
      if (startDate) expenseDateFilter.occurredAt.gte = new Date(String(startDate));
      if (endDate) {
        const end = new Date(String(endDate));
        end.setHours(23, 59, 59, 999);
        expenseDateFilter.occurredAt.lte = end;
      }
    }

    const expenses = await prisma.expense.findMany({
      where: { userId, ...notDeleted, ...expenseDateFilter },
      select: { amount: true },
    });
    const totalExpenses = expenses.reduce((sum, e) => sum + Number(e.amount), 0);
    const netProfit = grossProfit - totalExpenses;

    // Active debts
    const debtsOwe = await prisma.debt.findMany({
      where: { userId, ...notDeleted, settled: false, type: 0 },
      select: { amount: true },
    });
    const debtsOwed = await prisma.debt.findMany({
      where: { userId, ...notDeleted, settled: false, type: 1 },
      select: { amount: true },
    });

    const totalOwe = debtsOwe.reduce((sum, d) => sum + Number(d.amount), 0);
    const totalOwed = debtsOwed.reduce((sum, d) => sum + Number(d.amount), 0);

    // Counts
    const [productCount, customerCount, saleCount] = await Promise.all([
      prisma.product.count({ where: { userId, ...notDeleted, isActive: true } }),
      prisma.customer.count({ where: { userId, ...notDeleted } }),
      prisma.sale.count({ where: { userId, ...notDeleted, ...dateFilter } }),
    ]);

    res.json({
      data: {
        totalRevenue,
        totalDiscount,
        netRevenue,
        totalCost,
        grossProfit,
        totalExpenses,
        netProfit,
        totalOwe,      // Tiền tôi nợ
        totalOwed,     // Tiền nợ tôi
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

// ─── GET /api/reports/revenue — Revenue by day ───────
router.get('/revenue', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const { startDate, endDate } = req.query;

    if (!startDate || !endDate) {
      res.status(400).json({ error: 'startDate and endDate are required' });
      return;
    }

    const start = new Date(String(startDate));
    const end = new Date(String(endDate));
    end.setHours(23, 59, 59, 999);

    const sales = await prisma.sale.findMany({
      where: {
        userId,
        ...notDeleted,
        createdAt: { gte: start, lte: end },
      },
      include: { items: { where: notDeleted } },
      orderBy: { createdAt: 'asc' },
    });

    // Group by date
    const byDay: Record<string, { revenue: number; cost: number; count: number; profit: number }> = {};
    for (const sale of sales) {
      const day = sale.createdAt.toISOString().split('T')[0];
      if (!byDay[day]) byDay[day] = { revenue: 0, cost: 0, count: 0, profit: 0 };

      const subtotal = sale.items.reduce((s, it) => s + Number(it.unitPrice) * Number(it.quantity), 0);
      const revenue = subtotal - Number(sale.discount);

      byDay[day].revenue += revenue;
      byDay[day].cost += Number(sale.totalCost);
      byDay[day].count += 1;
      byDay[day].profit += revenue - Number(sale.totalCost);
    }

    const result = Object.entries(byDay).map(([date, data]) => ({ date, ...data }));

    res.json({ data: result });
  } catch (error) {
    console.error('Revenue report error:', error);
    res.status(500).json({ error: 'Failed to generate revenue report' });
  }
});

export default router;
