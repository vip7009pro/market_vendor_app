import { Router, Response } from 'express';
import { v4 as uuidv4 } from 'uuid';
import prisma from '../config/database.js';
import { authMiddleware, AuthRequest } from '../middleware/auth.js';

const router = Router();
router.use(authMiddleware);

const notDeleted = { deletedAt: null };

// ═══ EMPLOYEES ═════════════════════════════════════════

// GET /api/settings/employees
router.get('/employees', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const employees = await prisma.employee.findMany({
      where: { userId: req.user!.userId, ...notDeleted },
      orderBy: { id: 'asc' },
    });
    res.json({ data: employees });
  } catch (error) {
    res.status(500).json({ error: 'Failed to get employees' });
  }
});

// POST /api/settings/employees
router.post('/employees', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const { name } = req.body;
    if (!name) { res.status(400).json({ error: 'name is required' }); return; }

    // Generate next employee ID (NV0001, NV0002, ...)
    const existing = await prisma.employee.findMany({
      where: { userId, ...notDeleted },
      select: { id: true },
    });
    let maxNum = 0;
    for (const e of existing) {
      const digits = e.id.replace(/\D/g, '');
      const n = parseInt(digits);
      if (!isNaN(n) && n > maxNum) maxNum = n;
    }
    const employeeId = `NV${String(maxNum + 1).padStart(4, '0')}`;

    const employee = await prisma.employee.create({
      data: { userId, id: employeeId, name, updatedAt: new Date() },
    });
    res.status(201).json({ data: employee });
  } catch (error) {
    res.status(500).json({ error: 'Failed to create employee' });
  }
});

// PUT /api/settings/employees/:id
router.put('/employees/:id', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const { name } = req.body;
    const employee = await prisma.employee.update({
      where: { userId_id: { userId: req.user!.userId, id: req.params.id } },
      data: { name, updatedAt: new Date() },
    });
    res.json({ data: employee });
  } catch (error) {
    res.status(500).json({ error: 'Failed to update employee' });
  }
});

// DELETE /api/settings/employees/:id
router.delete('/employees/:id', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    await prisma.employee.update({
      where: { userId_id: { userId: req.user!.userId, id: req.params.id } },
      data: { deletedAt: new Date(), updatedAt: new Date() },
    });
    res.json({ message: 'Employee deleted' });
  } catch (error) {
    res.status(500).json({ error: 'Failed to delete employee' });
  }
});

// ═══ STORE INFO ════════════════════════════════════════

// GET /api/settings/store
router.get('/store', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const store = await prisma.storeInfo.findFirst({
      where: { userId: req.user!.userId },
    });
    res.json({ data: store });
  } catch (error) {
    res.status(500).json({ error: 'Failed to get store info' });
  }
});

// PUT /api/settings/store
router.put('/store', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const { name, address, phone, taxCode, email, bankName, bankAccount } = req.body;

    if (!name || !address || !phone) {
      res.status(400).json({ error: 'name, address, and phone are required' });
      return;
    }

    const store = await prisma.storeInfo.upsert({
      where: { userId_id: { userId, id: 1 } },
      update: { name, address, phone, taxCode, email, bankName, bankAccount, updatedAt: new Date() },
      create: { userId, id: 1, name, address, phone, taxCode, email, bankName, bankAccount, updatedAt: new Date() },
    });
    res.json({ data: store });
  } catch (error) {
    res.status(500).json({ error: 'Failed to update store info' });
  }
});

// ═══ VIETQR BANK ACCOUNTS ══════════════════════════════

// GET /api/settings/bank-accounts
router.get('/bank-accounts', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const accounts = await prisma.vietqrBankAccount.findMany({
      where: { userId: req.user!.userId, ...notDeleted },
      orderBy: [{ isDefault: 'desc' }, { updatedAt: 'desc' }],
    });
    res.json({ data: accounts });
  } catch (error) {
    res.status(500).json({ error: 'Failed to get bank accounts' });
  }
});

// POST /api/settings/bank-accounts
router.post('/bank-accounts', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const data = req.body;
    const now = new Date();

    if (data.isDefault) {
      await prisma.vietqrBankAccount.updateMany({
        where: { userId },
        data: { isDefault: false, updatedAt: now },
      });
    }

    const account = await prisma.vietqrBankAccount.create({
      data: {
        userId,
        id: data.id || uuidv4(),
        bankApiId: data.bankApiId,
        name: data.name,
        code: data.code,
        bin: data.bin,
        shortName: data.shortName,
        logo: data.logo,
        transferSupported: data.transferSupported,
        lookupSupported: data.lookupSupported,
        support: data.support,
        isTransfer: data.isTransfer,
        swiftCode: data.swiftCode,
        accountNo: data.accountNo,
        accountName: data.accountName,
        isDefault: data.isDefault || false,
        updatedAt: now,
      },
    });
    res.status(201).json({ data: account });
  } catch (error) {
    res.status(500).json({ error: 'Failed to create bank account' });
  }
});

// DELETE /api/settings/bank-accounts/:id
router.delete('/bank-accounts/:id', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    await prisma.vietqrBankAccount.update({
      where: { userId_id: { userId: req.user!.userId, id: req.params.id } },
      data: { deletedAt: new Date(), updatedAt: new Date() },
    });
    res.json({ message: 'Bank account deleted' });
  } catch (error) {
    res.status(500).json({ error: 'Failed to delete bank account' });
  }
});

export default router;
