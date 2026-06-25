import { Router, Response } from 'express';
import { v4 as uuidv4 } from 'uuid';
import prisma from '../config/database.js';
import { authMiddleware, AuthRequest } from '../middleware/auth.js';

const router = Router();
router.use(authMiddleware);

const notDeleted = { deletedAt: null };

// ─── GET /api/customers ───────────────────────────────
router.get('/', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const { search, supplier } = req.query;
    const userId = req.user!.userId;

    const where: any = { userId, ...notDeleted };
    if (supplier !== undefined) where.isSupplier = supplier === 'true';
    if (search) {
      where.OR = [
        { name: { contains: String(search), mode: 'insensitive' } },
        { phone: { contains: String(search), mode: 'insensitive' } },
      ];
    }

    const customers = await prisma.customer.findMany({
      where,
      orderBy: { name: 'asc' },
    });

    res.json({ data: customers });
  } catch (error) {
    console.error('Get customers error:', error);
    res.status(500).json({ error: 'Failed to get customers' });
  }
});

// ─── GET /api/customers/:id ──────────────────────────
router.get('/:id', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const customer = await prisma.customer.findUnique({
      where: { userId_id: { userId: req.user!.userId, id: req.params.id } },
    });

    if (!customer || customer.deletedAt) {
      res.status(404).json({ error: 'Customer not found' });
      return;
    }

    res.json({ data: customer });
  } catch (error) {
    console.error('Get customer error:', error);
    res.status(500).json({ error: 'Failed to get customer' });
  }
});

// ─── POST /api/customers ─────────────────────────────
router.post('/', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const { name, phone, note, isSupplier } = req.body;

    if (!name) {
      res.status(400).json({ error: 'name is required' });
      return;
    }

    const customer = await prisma.customer.create({
      data: {
        userId,
        id: uuidv4(),
        name,
        phone: phone || null,
        note: note || null,
        isSupplier: isSupplier || false,
        updatedAt: new Date(),
      },
    });

    res.status(201).json({ data: customer });
  } catch (error) {
    console.error('Create customer error:', error);
    res.status(500).json({ error: 'Failed to create customer' });
  }
});

// ─── PUT /api/customers/:id ──────────────────────────
router.put('/:id', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const { name, phone, note, isSupplier } = req.body;

    const customer = await prisma.customer.update({
      where: { userId_id: { userId, id: req.params.id } },
      data: {
        ...(name !== undefined && { name }),
        ...(phone !== undefined && { phone }),
        ...(note !== undefined && { note }),
        ...(isSupplier !== undefined && { isSupplier }),
        updatedAt: new Date(),
      },
    });

    res.json({ data: customer });
  } catch (error) {
    console.error('Update customer error:', error);
    res.status(500).json({ error: 'Failed to update customer' });
  }
});

// ─── DELETE /api/customers/:id ───────────────────────
router.delete('/:id', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;

    await prisma.customer.update({
      where: { userId_id: { userId, id: req.params.id } },
      data: { deletedAt: new Date(), updatedAt: new Date() },
    });

    res.json({ message: 'Customer deleted' });
  } catch (error) {
    console.error('Delete customer error:', error);
    res.status(500).json({ error: 'Failed to delete customer' });
  }
});

export default router;
