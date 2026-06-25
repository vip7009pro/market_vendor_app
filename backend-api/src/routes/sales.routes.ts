import { Router, Response } from 'express';
import { v4 as uuidv4 } from 'uuid';
import { Decimal } from '@prisma/client/runtime/library';
import prisma from '../config/database.js';
import { authMiddleware, AuthRequest } from '../middleware/auth.js';

const router = Router();
router.use(authMiddleware);

const notDeleted = { deletedAt: null };

// ─── GET /api/sales ───────────────────────────────────
router.get('/', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const { startDate, endDate, search, page = '1', limit = '50' } = req.query;

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
        { customerName: { contains: String(search), mode: 'insensitive' } },
        { employeeName: { contains: String(search), mode: 'insensitive' } },
        { note: { contains: String(search), mode: 'insensitive' } },
      ];
    }

    const skip = (parseInt(String(page)) - 1) * parseInt(String(limit));

    const [sales, total] = await Promise.all([
      prisma.sale.findMany({
        where,
        include: {
          items: { where: notDeleted },
        },
        orderBy: { createdAt: 'desc' },
        skip,
        take: parseInt(String(limit)),
      }),
      prisma.sale.count({ where }),
    ]);

    res.json({ data: sales, total, page: parseInt(String(page)), limit: parseInt(String(limit)) });
  } catch (error) {
    console.error('Get sales error:', error);
    res.status(500).json({ error: 'Failed to get sales' });
  }
});

// ─── GET /api/sales/:id ──────────────────────────────
router.get('/:id', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const sale = await prisma.sale.findUnique({
      where: { userId_id: { userId: req.user!.userId, id: req.params.id } },
      include: { items: { where: notDeleted } },
    });

    if (!sale || sale.deletedAt) {
      res.status(404).json({ error: 'Sale not found' });
      return;
    }

    res.json({ data: sale });
  } catch (error) {
    console.error('Get sale error:', error);
    res.status(500).json({ error: 'Failed to get sale' });
  }
});

// ─── POST /api/sales — Create sale with stock deduction ──
// Replicates insertSale logic from database_service.dart:3272-3393
router.post('/', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const {
      customerId, customerName, employeeId, employeeName,
      items, discount = 0, paidAmount = 0, paymentType, note, createdAt,
    } = req.body;

    if (!items || !Array.isArray(items) || items.length === 0) {
      res.status(400).json({ error: 'items are required' });
      return;
    }

    const saleId = uuidv4();
    const now = new Date();
    const saleCreatedAt = createdAt ? new Date(createdAt) : now;

    // Calculate totalCost (replicates Dart logic)
    // RAW items: use costPrice from products table
    // MIX items: use unitCost from the item
    const rawProductIds = items
      .filter((it: any) => (it.itemType || '').toUpperCase() !== 'MIX')
      .map((it: any) => it.productId)
      .filter(Boolean);

    const productMap: Record<string, number> = {};
    if (rawProductIds.length > 0) {
      const products = await prisma.product.findMany({
        where: { userId, id: { in: rawProductIds }, ...notDeleted },
        select: { id: true, costPrice: true },
      });
      for (const p of products) {
        productMap[p.id] = Number(p.costPrice);
      }
    }

    let totalCost = 0;
    const saleItems: any[] = [];
    const stockChanges: Record<string, number> = {};

    for (const item of items) {
      const itemType = (item.itemType || '').toUpperCase().trim();
      let snapUnitCost: number;

      if (itemType === 'MIX') {
        snapUnitCost = item.unitCost || 0;
        totalCost += snapUnitCost * (item.quantity || 0);

        // Parse mixItemsJson to deduct raw materials stock
        if (item.mixItemsJson) {
          try {
            const mixItems = typeof item.mixItemsJson === 'string'
              ? JSON.parse(item.mixItemsJson)
              : item.mixItemsJson;
            if (Array.isArray(mixItems)) {
              for (const mi of mixItems) {
                const rid = mi.rawProductId;
                if (!rid) continue;
                const rq = Number(mi.rawQty) || 0;
                stockChanges[rid] = (stockChanges[rid] || 0) + rq;
              }
            }
          } catch {}
        }
      } else {
        snapUnitCost = item.unitCost > 0 ? item.unitCost : (productMap[item.productId] || 0);
        totalCost += (productMap[item.productId] || snapUnitCost) * (item.quantity || 0);

        // Direct stock deduction for RAW items
        if (item.productId) {
          stockChanges[item.productId] = (stockChanges[item.productId] || 0) + (item.quantity || 0);
        }
      }

      saleItems.push({
        userId,
        id: uuidv4(),
        saleId,
        productId: item.productId || null,
        name: item.name,
        unitPrice: item.unitPrice,
        unitCost: snapUnitCost,
        quantity: item.quantity,
        unit: item.unit,
        itemType: item.itemType || null,
        displayName: item.displayName || null,
        mixItemsJson: typeof item.mixItemsJson === 'object' ? JSON.stringify(item.mixItemsJson) : (item.mixItemsJson || null),
        updatedAt: now,
      });
    }

    const totalSelling = items.reduce((sum: number, item: any) => sum + (Number(item.unitPrice) * Number(item.quantity)), 0);
    const netSellingPrice = Math.max(0, totalSelling - Number(discount));
    const debtAmount = netSellingPrice - Number(paidAmount);

    // Transaction: create sale + items + deduct stock + create debt
    await prisma.$transaction(async (tx) => {
      // Create sale
      await tx.sale.create({
        data: {
          userId,
          id: saleId,
          createdAt: saleCreatedAt,
          customerId: customerId || null,
          customerName: customerName || null,
          employeeId: employeeId || null,
          employeeName: employeeName || null,
          discount,
          paidAmount,
          paymentType: paymentType || null,
          totalCost,
          note: note || null,
          updatedAt: now,
        },
      });

      // Create sale items
      await tx.saleItem.createMany({ data: saleItems });

      // Deduct stock
      for (const [productId, qty] of Object.entries(stockChanges)) {
        await tx.product.update({
          where: { userId_id: { userId, id: productId } },
          data: {
            currentStock: { decrement: qty },
            updatedAt: now,
          },
        });
      }

      // Auto-create debt if paidAmount < netSellingPrice and customerId is provided
      if (debtAmount > 0 && customerId) {
        await tx.debt.create({
          data: {
            userId,
            id: uuidv4(),
            createdAt: saleCreatedAt,
            type: 1, // othersOweMe
            partyId: customerId,
            partyName: customerName || 'Khách hàng',
            initialAmount: debtAmount,
            amount: debtAmount,
            description: `Nợ tự động từ đơn hàng ${saleId.slice(0, 8).toUpperCase()}`,
            sourceType: 'sale',
            sourceId: saleId,
            updatedAt: now,
          },
        });
      }

      // Audit log
      await tx.auditLog.create({
        data: {
          userId,
          entity: 'sale',
          entityId: saleId,
          action: 'create',
          at: now,
          payload: JSON.stringify({ totalCost, discount, paidAmount }),
        },
      });
    });

    // Fetch the created sale with items
    const sale = await prisma.sale.findUnique({
      where: { userId_id: { userId, id: saleId } },
      include: { items: { where: notDeleted } },
    });

    res.status(201).json({ data: sale });
  } catch (error) {
    console.error('Create sale error:', error);
    res.status(500).json({ error: 'Failed to create sale' });
  }
});

// ─── DELETE /api/sales/:id (soft delete + restore stock) ──
// Replicates deleteSale logic from database_service.dart:3585-3618
router.delete('/:id', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const saleId = req.params.id;
    const now = new Date();

    // Get sale items to restore stock
    const saleItems = await prisma.saleItem.findMany({
      where: { userId, saleId, ...notDeleted },
    });

    // Calculate stock to restore
    const stockRestore: Record<string, number> = {};
    for (const item of saleItems) {
      const itemType = (item.itemType || '').toUpperCase().trim();
      if (itemType === 'MIX' && item.mixItemsJson) {
        try {
          const mixItems = JSON.parse(item.mixItemsJson);
          if (Array.isArray(mixItems)) {
            for (const mi of mixItems) {
              const rid = mi.rawProductId;
              if (!rid) continue;
              const rq = Number(mi.rawQty) || 0;
              stockRestore[rid] = (stockRestore[rid] || 0) + rq;
            }
          }
        } catch {}
      } else if (item.productId) {
        stockRestore[item.productId] = (stockRestore[item.productId] || 0) + Number(item.quantity);
      }
    }

    await prisma.$transaction(async (tx) => {
      // Soft delete sale items
      await tx.saleItem.updateMany({
        where: { userId, saleId, ...notDeleted },
        data: { deletedAt: now, updatedAt: now },
      });

      // Soft delete sale
      await tx.sale.update({
        where: { userId_id: { userId, id: saleId } },
        data: { deletedAt: now, updatedAt: now },
      });

      // Soft delete corresponding debt
      await tx.debt.updateMany({
        where: { userId, sourceType: 'sale', sourceId: saleId, deletedAt: null },
        data: { deletedAt: now, updatedAt: now },
      });

      // Restore stock
      for (const [productId, qty] of Object.entries(stockRestore)) {
        await tx.product.update({
          where: { userId_id: { userId, id: productId } },
          data: {
            currentStock: { increment: qty },
            updatedAt: now,
          },
        });
      }

      await tx.auditLog.create({
        data: { userId, entity: 'sale', entityId: saleId, action: 'delete', at: now },
      });
    });

    res.json({ message: 'Sale deleted and stock restored' });
  } catch (error) {
    console.error('Delete sale error:', error);
    res.status(500).json({ error: 'Failed to delete sale' });
  }
});

export default router;
