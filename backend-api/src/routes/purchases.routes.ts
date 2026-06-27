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

    let totalCost = 0;
    if (items && Array.isArray(items)) {
      for (const item of items) {
        totalCost += (item.quantity || 0) * (item.unitCost || 0);
      }
    }

    let finalPrice = totalCost;
    if (discountType.toUpperCase() === 'PERCENT') {
      finalPrice = Math.max(0, totalCost * (1 - Number(discountValue) / 100));
    } else {
      finalPrice = Math.max(0, totalCost - Number(discountValue));
    }
    const unpaidAmount = finalPrice - Number(paidAmount);

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
          const itemTotalCost = (item.quantity || 0) * (item.unitCost || 0);
          await tx.purchaseHistory.create({
            data: {
              userId,
              id: uuidv4(),
              createdAt: createdAt ? new Date(createdAt) : now,
              productId: item.productId,
              productName: item.productName,
              quantity: item.quantity,
              unitCost: item.unitCost || 0,
              totalCost: itemTotalCost,
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

      // Auto-create debt if unpaidAmount > 0 and supplierName is provided
      if (unpaidAmount > 0 && supplierName) {
        let supplierId = uuidv4();
        const existingSupplier = await tx.customer.findFirst({
          where: { userId, name: supplierName, isSupplier: true, deletedAt: null },
        });
        if (existingSupplier) {
          supplierId = existingSupplier.id;
        }

        await tx.debt.create({
          data: {
            userId,
            id: uuidv4(),
            createdAt: createdAt ? new Date(createdAt) : now,
            type: 0, // oweOthers
            partyId: supplierId,
            partyName: supplierName,
            initialAmount: unpaidAmount,
            amount: unpaidAmount,
            description: `Nợ tự động từ đơn nhập hàng ${orderId.slice(0, 8).toUpperCase()}`,
            sourceType: 'purchase',
            sourceId: orderId,
            updatedAt: now,
          },
        });
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

// GET /api/purchases/orders/:id
router.get('/orders/:id', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const order = await prisma.purchaseOrder.findUnique({
      where: { userId_id: { userId, id: req.params.id } },
      include: { items: { where: notDeleted } },
    });

    if (!order || order.deletedAt) {
      res.status(404).json({ error: 'Purchase order not found' });
      return;
    }

    res.json({ data: order });
  } catch (error) {
    console.error('Get purchase order error:', error);
    res.status(500).json({ error: 'Failed to get purchase order' });
  }
});

// PUT /api/purchases/orders/:id
router.put('/orders/:id', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const orderId = req.params.id;
    const {
      supplierName, supplierPhone, discountType = 'AMOUNT',
      discountValue = 0, paidAmount = 0, note, items, createdAt,
      purchaseDocUploaded, purchaseDocFileId, purchaseDocUpdatedAt
    } = req.body;

    const now = new Date();

    // 1. Fetch the existing order and its items
    const existingOrder = await prisma.purchaseOrder.findUnique({
      where: { userId_id: { userId, id: orderId } },
      include: { items: { where: notDeleted } },
    });

    if (!existingOrder || existingOrder.deletedAt) {
      res.status(404).json({ error: 'Purchase order not found' });
      return;
    }

    let totalCost = 0;
    if (items && Array.isArray(items)) {
      for (const item of items) {
        totalCost += (item.quantity || 0) * (item.unitCost || 0);
      }
    }

    let finalPrice = totalCost;
    if (discountType.toUpperCase() === 'PERCENT') {
      finalPrice = Math.max(0, totalCost * (1 - Number(discountValue) / 100));
    } else {
      finalPrice = Math.max(0, totalCost - Number(discountValue));
    }
    const unpaidAmount = finalPrice - Number(paidAmount);

    await prisma.$transaction(async (tx) => {
      // 2. Reverse stock of old items
      for (const oldItem of existingOrder.items) {
        if (Number(oldItem.quantity) > 0) {
          await tx.product.update({
            where: { userId_id: { userId, id: oldItem.productId } },
            data: {
              currentStock: { decrement: Number(oldItem.quantity) },
              updatedAt: now,
            },
          });
        }
      }

      // 3. Mark old items as deleted
      await tx.purchaseHistory.updateMany({
        where: { userId, purchaseOrderId: orderId, ...notDeleted },
        data: { deletedAt: now, updatedAt: now },
      });

      // 4. Create new items and increment stock
      if (items && Array.isArray(items)) {
        for (const item of items) {
          const itemTotalCost = (item.quantity || 0) * (item.unitCost || 0);
          await tx.purchaseHistory.create({
            data: {
              userId,
              id: uuidv4(),
              createdAt: createdAt ? new Date(createdAt) : existingOrder.createdAt,
              productId: item.productId,
              productName: item.productName,
              quantity: item.quantity,
              unitCost: item.unitCost || 0,
              totalCost: itemTotalCost,
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

      // 5. Update purchase order details
      await tx.purchaseOrder.update({
        where: { userId_id: { userId, id: orderId } },
        data: {
          supplierName: supplierName || null,
          supplierPhone: supplierPhone || null,
          discountType: discountType.toUpperCase() === 'PERCENT' ? 'PERCENT' : 'AMOUNT',
          discountValue,
          paidAmount,
          note: note || null,
          createdAt: createdAt ? new Date(createdAt) : existingOrder.createdAt,
          ...(purchaseDocUploaded !== undefined && { purchaseDocUploaded }),
          ...(purchaseDocFileId !== undefined && { purchaseDocFileId }),
          ...(purchaseDocUpdatedAt !== undefined && { purchaseDocUpdatedAt: purchaseDocUpdatedAt ? new Date(purchaseDocUpdatedAt) : null }),
          updatedAt: now,
        },
      });

      // 6. Handle Debt Adjustment
      const existingDebt = await tx.debt.findFirst({
        where: { userId, sourceType: 'purchase', sourceId: orderId, deletedAt: null },
      });

      if (unpaidAmount > 0 && supplierName) {
        let supplierId = uuidv4();
        const existingSupplier = await tx.customer.findFirst({
          where: { userId, name: supplierName, isSupplier: true, deletedAt: null },
        });
        if (existingSupplier) {
          supplierId = existingSupplier.id;
        }

        if (existingDebt) {
          await tx.debt.update({
            where: { userId_id: { userId, id: existingDebt.id } },
            data: {
              partyId: supplierId,
              partyName: supplierName,
              initialAmount: unpaidAmount,
              amount: unpaidAmount,
              updatedAt: now,
            },
          });
        } else {
          await tx.debt.create({
            data: {
              userId,
              id: uuidv4(),
              createdAt: createdAt ? new Date(createdAt) : existingOrder.createdAt,
              type: 0, // oweOthers
              partyId: supplierId,
              partyName: supplierName,
              initialAmount: unpaidAmount,
              amount: unpaidAmount,
              description: `Nợ tự động từ đơn nhập hàng ${orderId.slice(0, 8).toUpperCase()}`,
              sourceType: 'purchase',
              sourceId: orderId,
              updatedAt: now,
            },
          });
        }
      } else {
        // Delete debt if it exists since it's now fully paid or has no supplier
        if (existingDebt) {
          await tx.debtPayment.updateMany({
            where: { userId, debtId: existingDebt.id, deletedAt: null },
            data: { deletedAt: now, updatedAt: now },
          });
          await tx.debt.update({
            where: { userId_id: { userId, id: existingDebt.id } },
            data: { deletedAt: now, updatedAt: now },
          });
        }
      }
    });

    const updatedOrder = await prisma.purchaseOrder.findUnique({
      where: { userId_id: { userId, id: orderId } },
      include: { items: { where: notDeleted } },
    });

    res.json({ data: updatedOrder });
  } catch (error) {
    console.error('Update purchase order error:', error);
    res.status(500).json({ error: 'Failed to update purchase order' });
  }
});

export default router;
