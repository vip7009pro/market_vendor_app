import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';

dotenv.config();

import authRoutes from './routes/auth.routes.js';
import productsRoutes from './routes/products.routes.js';
import customersRoutes from './routes/customers.routes.js';
import salesRoutes from './routes/sales.routes.js';
import debtsRoutes from './routes/debts.routes.js';
import purchasesRoutes from './routes/purchases.routes.js';
import expensesRoutes from './routes/expenses.routes.js';
import settingsRoutes from './routes/settings.routes.js';
import reportsRoutes from './routes/reports.routes.js';
import syncRoutes from './routes/sync.routes.js';
import { errorHandler } from './middleware/errorHandler.js';

const app = express();
const PORT = parseInt(process.env.PORT || '3007', 10);
const FRONTEND_URL = process.env.FRONTEND_URL || 'http://localhost:3001';

// ─── Middleware ───────────────────────────────────────
app.use(cors({
  origin: [FRONTEND_URL, 'http://localhost:3000', 'http://localhost:3001'],
  credentials: true,
}));
app.use(express.json({ limit: '12mb' }));

// ─── Health check ────────────────────────────────────
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// ─── Routes ──────────────────────────────────────────
app.use('/auth', authRoutes);
app.use('/api/products', productsRoutes);
app.use('/api/customers', customersRoutes);
app.use('/api/sales', salesRoutes);
app.use('/api/debts', debtsRoutes);
app.use('/api/purchases', purchasesRoutes);
app.use('/api/expenses', expensesRoutes);
app.use('/api/settings', settingsRoutes);
app.use('/api/reports', reportsRoutes);
app.use('/api/sync', syncRoutes);

// ─── Error handler ───────────────────────────────────
app.use(errorHandler);

// ─── Start server ────────────────────────────────────
app.listen(PORT, () => {
  console.log(`\n🚀 Market Vendor API running on http://localhost:${PORT}`);
  console.log(`📊 Health check: http://localhost:${PORT}/health`);
  console.log(`🔐 Auth: POST http://localhost:${PORT}/auth/login`);
  console.log(`📦 Products: http://localhost:${PORT}/api/products`);
  console.log(`\nFrontend URL: ${FRONTEND_URL}\n`);
});

export default app;
