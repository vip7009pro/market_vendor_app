import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import https from 'https';
import fs from 'fs';
import path from 'path';

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
  origin: [
    FRONTEND_URL, 
    'http://localhost:3000', 
    'http://localhost:3001',
    'https://localhost:3001',
    'http://192.168.1.136:3001',
    'https://192.168.1.136:3001',
    'http://cmsvina4285.com',
    'http://cmsvina4285.com:3001',
    'https://cmsvina4285.com',
    'https://cmsvina4285.com:3001'
  ],
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
const sslKeyPath = process.env.SSL_KEY_PATH;
const sslCertPath = process.env.SSL_CERT_PATH;
const sslCaPath = process.env.SSL_CA_PATH;

const isSslEnabled = sslKeyPath && sslCertPath && fs.existsSync(sslKeyPath) && fs.existsSync(sslCertPath);

if (isSslEnabled) {
  try {
    const sslOptions: any = {
      key: fs.readFileSync(path.resolve(sslKeyPath)),
      cert: fs.readFileSync(path.resolve(sslCertPath)),
    };
    if (sslCaPath && fs.existsSync(sslCaPath)) {
      sslOptions.ca = fs.readFileSync(path.resolve(sslCaPath));
    }
    
    const server = https.createServer(sslOptions, app);
    server.listen(PORT, () => {
      console.log(`\n🚀 Market Vendor API running securely on HTTPS on port ${PORT}`);
      console.log(`📊 Health check: https://localhost:${PORT}/health`);
      console.log(`\nFrontend URL: ${FRONTEND_URL}\n`);
    });
  } catch (err) {
    console.error('Lỗi khi cấu hình SSL cho backend. Đang fallback sang HTTP...', err);
    startHttpServer();
  }
} else {
  startHttpServer();
}

function startHttpServer() {
  app.listen(PORT, () => {
    console.log(`\n🚀 Market Vendor API running on http://localhost:${PORT}`);
    console.log(`📊 Health check: http://localhost:${PORT}/health`);
    console.log(`🔐 Auth: POST http://localhost:${PORT}/auth/login`);
    console.log(`📦 Products: http://localhost:${PORT}/api/products`);
    console.log(`\nFrontend URL: ${FRONTEND_URL}\n`);
  });
}

export default app;
