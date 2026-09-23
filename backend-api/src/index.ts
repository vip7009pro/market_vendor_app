import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import https from 'https';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

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
import uploadRoutes from './routes/upload.routes.js';
import { errorHandler } from './middleware/errorHandler.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

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
    'https://cmsvina4285.com:3001',
    'http://10.0.0.2',
    'http://localhost'

  ],
  credentials: true,
}));
app.use(express.json({ limit: '12mb' }));
app.use('/uploads', express.static(path.join(__dirname, '../uploads')));

// ─── Health check ────────────────────────────────────
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});
app.get('/api/health', (req, res) => {
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
app.use('/sync', syncRoutes);
app.use('/api/upload', uploadRoutes);

// ─── Error handler ───────────────────────────────────
app.use(errorHandler);

// ─── Start server ────────────────────────────────────
const sslKeyPath = process.env.SSL_KEY_PATH;
const sslCertPath = process.env.SSL_CERT_PATH;
const sslCaPath = process.env.SSL_CA_PATH;

// Khởi chạy HTTP server trên 0.0.0.0:PORT cho mobile và mạng nội bộ
const server = app.listen(PORT, '0.0.0.0', () => {
  console.log(`\n🚀 Market Vendor API running on http://0.0.0.0:${PORT}`);
  console.log(`📊 Health check: http://localhost:${PORT}/health`);
  console.log(`🔐 Auth: POST http://localhost:${PORT}/auth/login`);
  console.log(`📦 Products: http://localhost:${PORT}/api/products`);
  console.log(`Frontend URL: ${FRONTEND_URL}\n`);
});

server.on('error', (err: any) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`❌ Cổng HTTP ${PORT} đã bị chiếm dụng bởi một tiến trình khác.`);
  } else {
    console.error('❌ Lỗi khởi chạy HTTP server:', err);
  }
});

// Nếu cấu hình chứng chỉ SSL, khởi chạy song song HTTPS server trên SSL_PORT (mặc định 3443)
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
    const sslPort = parseInt(process.env.SSL_PORT || '3443', 10);
    const httpsServer = https.createServer(sslOptions, app);

    httpsServer.on('error', (err: any) => {
      if (err.code === 'EADDRINUSE') {
        console.warn(`⚠️ Cổng HTTPS phụ ${sslPort} đã bị chiếm dụng (EADDRINUSE). Server HTTP cổng ${PORT} vẫn hoạt động bình thường.`);
      } else {
        console.warn('⚠️ Lỗi HTTPS server phụ:', err.message);
      }
    });

    httpsServer.listen(sslPort, '0.0.0.0', () => {
      console.log(`🔒 Market Vendor API running on HTTPS on port ${sslPort}`);
    });
  } catch (err) {
    console.warn('Lỗi cấu hình SSL phụ:', err);
  }
}

export default app;
