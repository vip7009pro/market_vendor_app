import { Router, Response } from 'express';
import { v4 as uuidv4 } from 'uuid';
import prisma from '../config/database.js';
import { authMiddleware, AuthRequest } from '../middleware/auth.js';

const router = Router();
router.use(authMiddleware);

const notDeleted = { deletedAt: null };

// ─── GET /api/products ────────────────────────────────
router.get('/', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const { search, type, active } = req.query;
    const userId = req.user!.userId;

    const where: any = { userId, ...notDeleted };
    if (type) where.itemType = String(type).toUpperCase();
    if (active !== undefined) where.isActive = active === 'true';
    if (search) {
      where.OR = [
        { name: { contains: String(search), mode: 'insensitive' } },
        { barcode: { contains: String(search), mode: 'insensitive' } },
      ];
    }

    const products = await prisma.product.findMany({
      where,
      orderBy: { name: 'asc' },
    });

    res.json({ data: products });
  } catch (error) {
    console.error('Get products error:', error);
    res.status(500).json({ error: 'Failed to get products' });
  }
});

// ─── GET /api/products/:id ────────────────────────────
router.get('/:id', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const product = await prisma.product.findUnique({
      where: { userId_id: { userId: req.user!.userId, id: req.params.id } },
    });

    if (!product || product.deletedAt) {
      res.status(404).json({ error: 'Product not found' });
      return;
    }

    res.json({ data: product });
  } catch (error) {
    console.error('Get product error:', error);
    res.status(500).json({ error: 'Failed to get product' });
  }
});

// ─── POST /api/products ──────────────────────────────
router.post('/', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const { name, price, costPrice, unit, barcode, isActive, itemType, isStocked, imagePath, currentStock } = req.body;

    if (!name || price === undefined || !unit) {
      res.status(400).json({ error: 'name, price, and unit are required' });
      return;
    }

    const product = await prisma.product.create({
      data: {
        userId,
        id: uuidv4(),
        name,
        price,
        costPrice: costPrice || 0,
        currentStock: currentStock || 0,
        unit,
        barcode: barcode || null,
        isActive: isActive !== false,
        itemType: itemType || 'RAW',
        isStocked: isStocked !== false,
        imagePath: imagePath || null,
        updatedAt: new Date(),
      },
    });

    res.status(201).json({ data: product });
  } catch (error) {
    console.error('Create product error:', error);
    res.status(500).json({ error: 'Failed to create product' });
  }
});

// ─── PUT /api/products/:id ───────────────────────────
router.put('/:id', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const { name, price, costPrice, unit, barcode, isActive, itemType, isStocked, imagePath, currentStock } = req.body;

    const product = await prisma.product.update({
      where: { userId_id: { userId, id: req.params.id } },
      data: {
        ...(name !== undefined && { name }),
        ...(price !== undefined && { price }),
        ...(costPrice !== undefined && { costPrice }),
        ...(currentStock !== undefined && { currentStock }),
        ...(unit !== undefined && { unit }),
        ...(barcode !== undefined && { barcode }),
        ...(isActive !== undefined && { isActive }),
        ...(itemType !== undefined && { itemType }),
        ...(isStocked !== undefined && { isStocked }),
        ...(imagePath !== undefined && { imagePath }),
        updatedAt: new Date(),
      },
    });

    res.json({ data: product });
  } catch (error) {
    console.error('Update product error:', error);
    res.status(500).json({ error: 'Failed to update product' });
  }
});

// ─── DELETE /api/products/:id (soft delete) ──────────
router.delete('/:id', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;

    await prisma.product.update({
      where: { userId_id: { userId, id: req.params.id } },
      data: { deletedAt: new Date(), updatedAt: new Date() },
    });

    res.json({ message: 'Product deleted' });
  } catch (error) {
    console.error('Delete product error:', error);
    res.status(500).json({ error: 'Failed to delete product' });
  }
});

export default router;
