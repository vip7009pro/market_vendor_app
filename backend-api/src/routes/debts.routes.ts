import { Router, Response } from 'express';
import { v4 as uuidv4 } from 'uuid';
import prisma from '../config/database.js';
import { authMiddleware, AuthRequest } from '../middleware/auth.js';

const router = Router();
router.use(authMiddleware);

const notDeleted = { deletedAt: null };

// ─── GET /api/debts ───────────────────────────────────
router.get('/', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const { type, settled, search } = req.query;
    const where: any = { userId, ...notDeleted };

    if (type !== undefined) where.type = parseInt(String(type));
    if (settled !== undefined) where.settled = settled === 'true';
    if (search) {
      where.OR = [
        { partyName: { contains: String(search), mode: 'insensitive' } },
        { description: { contains: String(search), mode: 'insensitive' } },
      ];
    }

    const debts = await prisma.debt.findMany({
      where,
      include: { payments: { where: notDeleted, orderBy: { createdAt: 'desc' } } },
      orderBy: { createdAt: 'desc' },
    });

    res.json({ data: debts });
  } catch (error) {
    console.error('Get debts error:', error);
    res.status(500).json({ error: 'Failed to get debts' });
  }
});

// ─── GET /api/debts/:id ──────────────────────────────
router.get('/:id', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const debt = await prisma.debt.findUnique({
      where: { userId_id: { userId: req.user!.userId, id: req.params.id } },
      include: { payments: { where: notDeleted, orderBy: { createdAt: 'desc' } } },
    });

    if (!debt || debt.deletedAt) {
      res.status(404).json({ error: 'Debt not found' });
      return;
    }

    res.json({ data: debt });
  } catch (error) {
    console.error('Get debt error:', error);
    res.status(500).json({ error: 'Failed to get debt' });
  }
});

// ─── POST /api/debts ─────────────────────────────────
router.post('/', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const { type, partyId, partyName, amount, description, dueDate, sourceType, sourceId, createdAt } = req.body;

    if (type === undefined || !partyId || !partyName || amount === undefined) {
      res.status(400).json({ error: 'type, partyId, partyName, and amount are required' });
      return;
    }

    const debt = await prisma.debt.create({
      data: {
        userId,
        id: uuidv4(),
        createdAt: createdAt ? new Date(createdAt) : new Date(),
        type,
        partyId,
        partyName,
        initialAmount: amount,
        amount,
        description: description || null,
        dueDate: dueDate ? new Date(dueDate) : null,
        sourceType: sourceType || null,
        sourceId: sourceId || null,
        updatedAt: new Date(),
      },
    });

    res.status(201).json({ data: debt });
  } catch (error) {
    console.error('Create debt error:', error);
    res.status(500).json({ error: 'Failed to create debt' });
  }
});

// ─── PUT /api/debts/:id ──────────────────────────────
router.put('/:id', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const { type, partyId, partyName, initialAmount, amount, description, dueDate, settled, sourceType, sourceId } = req.body;

    const debt = await prisma.debt.update({
      where: { userId_id: { userId, id: req.params.id } },
      data: {
        ...(type !== undefined && { type }),
        ...(partyId !== undefined && { partyId }),
        ...(partyName !== undefined && { partyName }),
        ...(initialAmount !== undefined && { initialAmount }),
        ...(amount !== undefined && { amount }),
        ...(description !== undefined && { description }),
        ...(dueDate !== undefined && { dueDate: dueDate ? new Date(dueDate) : null }),
        ...(settled !== undefined && { settled }),
        ...(sourceType !== undefined && { sourceType }),
        ...(sourceId !== undefined && { sourceId }),
        updatedAt: new Date(),
      },
    });

    res.json({ data: debt });
  } catch (error) {
    console.error('Update debt error:', error);
    res.status(500).json({ error: 'Failed to update debt' });
  }
});

// ─── DELETE /api/debts/:id (soft delete + cascade payments) ──
router.delete('/:id', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const debtId = req.params.id;
    const now = new Date();

    await prisma.$transaction(async (tx) => {
      // Soft delete payments
      await tx.debtPayment.updateMany({
        where: { userId, debtId, ...notDeleted },
        data: { deletedAt: now, updatedAt: now },
      });

      // Soft delete debt
      await tx.debt.update({
        where: { userId_id: { userId, id: debtId } },
        data: { deletedAt: now, updatedAt: now },
      });

      await tx.auditLog.create({
        data: { userId, entity: 'debt', entityId: debtId, action: 'delete', at: now },
      });
    });

    res.json({ message: 'Debt deleted' });
  } catch (error) {
    console.error('Delete debt error:', error);
    res.status(500).json({ error: 'Failed to delete debt' });
  }
});

// ─── POST /api/debts/:id/payments — Add payment ─────
router.post('/:id/payments', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const debtId = req.params.id;
    const { amount, note, paymentType, createdAt } = req.body;

    if (!amount || amount <= 0) {
      res.status(400).json({ error: 'amount must be positive' });
      return;
    }

    const now = new Date();

    await prisma.$transaction(async (tx) => {
      // Create payment
      await tx.debtPayment.create({
        data: {
          userId,
          uuid: uuidv4(),
          debtId,
          amount,
          note: note || null,
          paymentType: paymentType || null,
          createdAt: createdAt ? new Date(createdAt) : now,
          updatedAt: now,
        },
      });

      // Update debt remaining amount
      const debt = await tx.debt.findUnique({
        where: { userId_id: { userId, id: debtId } },
      });
      if (!debt) throw new Error('Debt not found');

      const newAmount = Math.max(0, Number(debt.amount) - amount);
      await tx.debt.update({
        where: { userId_id: { userId, id: debtId } },
        data: {
          amount: newAmount,
          settled: newAmount <= 0,
          updatedAt: now,
        },
      });

      await tx.auditLog.create({
        data: {
          userId,
          entity: 'debt_payment',
          entityId: debtId,
          action: 'create',
          at: now,
          payload: JSON.stringify({ amount, note }),
        },
      });
    });

    const updated = await prisma.debt.findUnique({
      where: { userId_id: { userId, id: debtId } },
      include: { payments: { where: notDeleted, orderBy: { createdAt: 'desc' } } },
    });

    res.status(201).json({ data: updated });
  } catch (error) {
    console.error('Add payment error:', error);
    res.status(500).json({ error: 'Failed to add payment' });
  }
});

export default router;
