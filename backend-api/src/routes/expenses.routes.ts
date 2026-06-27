import { Router, Response } from 'express';
import { v4 as uuidv4 } from 'uuid';
import prisma from '../config/database.js';
import { authMiddleware, AuthRequest } from '../middleware/auth.js';

const router = Router();
router.use(authMiddleware);

const notDeleted = { deletedAt: null };

// ─── GET /api/expenses ────────────────────────────────
router.get('/', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const { category, search, startDate, endDate } = req.query;
    const where: any = { userId, ...notDeleted };

    if (category && category !== 'all') where.category = String(category);
    if (startDate || endDate) {
      where.occurredAt = {};
      if (startDate) where.occurredAt.gte = new Date(String(startDate));
      if (endDate) {
        const end = new Date(String(endDate));
        end.setHours(23, 59, 59, 999);
        where.occurredAt.lte = end;
      }
    }
    if (search) {
      where.note = { contains: String(search), mode: 'insensitive' };
    }

    const expenses = await prisma.expense.findMany({
      where,
      orderBy: { occurredAt: 'desc' },
    });

    res.json({ data: expenses });
  } catch (error) {
    console.error('Get expenses error:', error);
    res.status(500).json({ error: 'Failed to get expenses' });
  }
});

// ─── POST /api/expenses ──────────────────────────────
router.post('/', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const { 
      occurredAt, amount, category, note,
      expenseDocUploaded, expenseDocFileId, expenseDocUpdatedAt
    } = req.body;

    if (!occurredAt || !amount || !category) {
      res.status(400).json({ error: 'occurredAt, amount, and category are required' });
      return;
    }

    const expense = await prisma.expense.create({
      data: {
        userId,
        id: uuidv4(),
        occurredAt: new Date(occurredAt),
        amount,
        category,
        note: note || null,
        expenseDocUploaded: !!expenseDocUploaded,
        expenseDocFileId: expenseDocFileId || null,
        expenseDocUpdatedAt: expenseDocUpdatedAt ? new Date(expenseDocUpdatedAt) : null,
        updatedAt: new Date(),
      },
    });

    res.status(201).json({ data: expense });
  } catch (error) {
    console.error('Create expense error:', error);
    res.status(500).json({ error: 'Failed to create expense' });
  }
});

// ─── PUT /api/expenses/:id ───────────────────────────
router.put('/:id', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const { 
      occurredAt, amount, category, note,
      expenseDocUploaded, expenseDocFileId, expenseDocUpdatedAt 
    } = req.body;

    const expense = await prisma.expense.update({
      where: { userId_id: { userId, id: req.params.id } },
      data: {
        ...(occurredAt !== undefined && { occurredAt: new Date(occurredAt) }),
        ...(amount !== undefined && { amount }),
        ...(category !== undefined && { category }),
        ...(note !== undefined && { note }),
        ...(expenseDocUploaded !== undefined && { expenseDocUploaded }),
        ...(expenseDocFileId !== undefined && { expenseDocFileId }),
        ...(expenseDocUpdatedAt !== undefined && { expenseDocUpdatedAt: expenseDocUpdatedAt ? new Date(expenseDocUpdatedAt) : null }),
        updatedAt: new Date(),
      },
    });

    res.json({ data: expense });
  } catch (error) {
    console.error('Update expense error:', error);
    res.status(500).json({ error: 'Failed to update expense' });
  }
});

// ─── DELETE /api/expenses/:id ────────────────────────
router.delete('/:id', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    await prisma.expense.update({
      where: { userId_id: { userId: req.user!.userId, id: req.params.id } },
      data: { deletedAt: new Date(), updatedAt: new Date() },
    });

    res.json({ message: 'Expense deleted' });
  } catch (error) {
    console.error('Delete expense error:', error);
    res.status(500).json({ error: 'Failed to delete expense' });
  }
});

export default router;
