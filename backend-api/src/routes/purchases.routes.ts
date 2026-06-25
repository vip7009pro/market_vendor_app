import { Router, Response } from 'express';
import { v4 as uuidv4 } from 'uuid';
import prisma from '../config/database.js';
import { authMiddleware, AuthRequest } from '../middleware/auth.js';

const router = Router();
router.use(authMiddleware);

const notDeleted = { deletedAt: null };

// ═══ PURCHASE ORDERS ═══════════════════════════════════

// GET /api/purchases/orders
router.get('/orders', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const { search, startDate, endDate } = req.query;
    const where: any = { userId, ...notDeleted };

    if (startDate || endDate) {
      where.createdAt = {};
      if (startDate) where.createdAt.gte = new Date(String(startDate));
      if (endDate) {
        const end = new Date(String(endDate));
        end.setHours(23, 59, 59, 999);
        where.createdAt.lte = end;
      }
    }

    if (search) {
      where.OR = [
        { supplierName: { contains: String(search), mode: 'insensitive' } },
        { note: { contains: String(search), mode: 'insensitive' } },
      ];
    }

    const orders = await prisma.purchaseOrder.findMany({
      where,
      include: { items: { where: notDeleted } },
      orderBy: { createdAt: 'desc' },
    });

    res.json({ data: orders });
  } catch (error) {
    console.error('Get purchase orders error:', error);
    res.status(500).json({ error: 'Failed to get purchase orders' });
  }
});

// POST /api/purchases/orders
router.post('/orders', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const {
      supplierName, supplierPhone, discountType = 'AMOUNT',
      discountValue = 0, paidAmount = 0, note, items, createdAt,
    } = req.body;

    const orderId = uuidv4();
    const now = new Date();

    await prisma.$transaction(async (tx) => {
      await tx.purchaseOrder.create({
        data: {
          userId,
          id: orderId,
          createdAt: createdAt ? new Date(createdAt) : now,
          supplierName: supplierName || null,
          supplierPhone: supplierPhone || null,
          discountType: discountType.toUpperCase() === 'PERCENT' ? 'PERCENT' : 'AMOUNT',
          discountValue,
          paidAmount,
          note: note || null,
          updatedAt: now,
        },
      });

      // Create purchase history items and add stock
      if (items && Array.isArray(items)) {
        for (const item of items) {
          const totalCost = (item.quantity || 0) * (item.unitCost || 0);
          await tx.purchaseHistory.create({
            data: {
              userId,
              id: uuidv4(),
              createdAt: createdAt ? new Date(createdAt) : now,
              productId: item.productId,
              productName: item.productName,
              quantity: item.quantity,
              unitCost: item.unitCost || 0,
              totalCost,
              paidAmount: item.paidAmount || 0,
              supplierName: supplierName || null,
              supplierPhone: supplierPhone || null,
              note: item.note || null,
              purchaseOrderId: orderId,
              updatedAt: now,
            },
          });

          // Add stock
          await tx.product.update({
            where: { userId_id: { userId, id: item.productId } },
            data: {
              currentStock: { increment: item.quantity || 0 },
              updatedAt: now,
            },
          });
        }
      }
    });

    const order = await prisma.purchaseOrder.findUnique({
      where: { userId_id: { userId, id: orderId } },
      include: { items: { where: notDeleted } },
    });

    res.status(201).json({ data: order });
  } catch (error) {
    console.error('Create purchase order error:', error);
    res.status(500).json({ error: 'Failed to create purchase order' });
  }
});

// DELETE /api/purchases/orders/:id
router.delete('/orders/:id', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const orderId = req.params.id;
    const now = new Date();

    // Get items to reverse stock
    const items = await prisma.purchaseHistory.findMany({
      where: { userId, purchaseOrderId: orderId, ...notDeleted },
    });

    await prisma.$transaction(async (tx) => {
      // Reverse stock for each item
      for (const item of items) {
        if (Number(item.quantity) > 0) {
          await tx.product.update({
            where: { userId_id: { userId, id: item.productId } },
            data: {
              currentStock: { decrement: Number(item.quantity) },
              updatedAt: now,
            },
          });
        }

        await tx.purchaseHistory.update({
          where: { userId_id: { userId, id: item.id } },
          data: { deletedAt: now, updatedAt: now },
        });
      }

      // Delete related debts
      const debts = await tx.debt.findMany({
        where: { userId, sourceType: 'purchase', sourceId: orderId, ...notDeleted },
      });
      for (const debt of debts) {
        await tx.debtPayment.updateMany({
          where: { userId, debtId: debt.id, ...notDeleted },
          data: { deletedAt: now, updatedAt: now },
        });
        await tx.debt.update({
          where: { userId_id: { userId, id: debt.id } },
          data: { deletedAt: now, updatedAt: now },
        });
      }

      // Delete order
      await tx.purchaseOrder.update({
        where: { userId_id: { userId, id: orderId } },
        data: { deletedAt: now, updatedAt: now },
      });
    });

    res.json({ message: 'Purchase order deleted and stock reversed' });
  } catch (error) {
    console.error('Delete purchase order error:', error);
    res.status(500).json({ error: 'Failed to delete purchase order' });
  }
});

// ═══ PURCHASE HISTORY (standalone) ═════════════════════

// GET /api/purchases/history
router.get('/history', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const { search, startDate, endDate } = req.query;
    const where: any = { userId, ...notDeleted };

    if (startDate || endDate) {
      where.createdAt = {};
      if (startDate) where.createdAt.gte = new Date(String(startDate));
      if (endDate) {
        const end = new Date(String(endDate));
        end.setHours(23, 59, 59, 999);
        where.createdAt.lte = end;
      }
    }

    if (search) {
      where.OR = [
        { productName: { contains: String(search), mode: 'insensitive' } },
        { supplierName: { contains: String(search), mode: 'insensitive' } },
        { note: { contains: String(search), mode: 'insensitive' } },
      ];
    }

    const history = await prisma.purchaseHistory.findMany({
      where,
      orderBy: { createdAt: 'desc' },
    });

    res.json({ data: history });
  } catch (error) {
    console.error('Get purchase history error:', error);
    res.status(500).json({ error: 'Failed to get purchase history' });
  }
});

export default router;
