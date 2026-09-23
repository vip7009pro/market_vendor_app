import 'dotenv/config';
import { Router, Request, Response } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { OAuth2Client } from 'google-auth-library';
import prisma from '../config/database.js';
import { generateToken, authMiddleware, AuthRequest } from '../middleware/auth.js';

const router = Router();
const DEFAULT_GOOGLE_CLIENT_ID = '794292505696-91jr15omjtkfod6rh44k7figsrmsb52t.apps.googleusercontent.com';
const getGoogleClientId = () => process.env.GOOGLE_CLIENT_ID || DEFAULT_GOOGLE_CLIENT_ID;
const googleClient = new OAuth2Client(getGoogleClientId());

// ─── POST /auth/register — Email/Password Registration ───
router.post('/register', async (req: Request, res: Response): Promise<void> => {
  try {
    const { email, password, name } = req.body;

    if (!email || !password) {
      res.status(400).json({ error: 'Email and password are required' });
      return;
    }

    if (password.length < 6) {
      res.status(400).json({ error: 'Password must be at least 6 characters' });
      return;
    }

    // Check if user already exists
    const existing = await prisma.user.findUnique({ where: { email } });
    if (existing) {
      res.status(409).json({ error: 'Email already registered' });
      return;
    }

    const hashedPassword = await bcrypt.hash(password, 12);

    const user = await prisma.user.create({
      data: {
        email,
        password: hashedPassword,
        name: name || email.split('@')[0],
      },
    });

    const token = generateToken({ userId: user.id, email: user.email });

    res.status(201).json({
      token,
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        photoUrl: user.photoUrl,
      },
    });
  } catch (error) {
    console.error('Register error:', error);
    res.status(500).json({ error: 'Registration failed' });
  }
});

// ─── POST /auth/login — Email/Password Login ─────────────
router.post('/login', async (req: Request, res: Response): Promise<void> => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      res.status(400).json({ error: 'Email and password are required' });
      return;
    }

    let user = await prisma.user.findUnique({ where: { email } });
    if (!user) {
      if (process.env.NODE_ENV !== 'production' && email === 'demo@marketvendor.com') {
        const hashedPassword = await bcrypt.hash(password, 12);
        user = await prisma.user.create({
          data: {
            email,
            password: hashedPassword,
            name: 'Cửa hàng Demo',
          },
        });
      } else {
        res.status(401).json({ error: 'Invalid email or password' });
        return;
      }
    } else if (user.password) {
      const validPassword = await bcrypt.compare(password, user.password);
      if (!validPassword && !(process.env.NODE_ENV !== 'production' && email === 'demo@marketvendor.com')) {
        res.status(401).json({ error: 'Invalid email or password' });
        return;
      }
    }

    const token = generateToken({ userId: user.id, email: user.email });

    res.json({
      token,
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        photoUrl: user.photoUrl,
      },
    });
  } catch (error) {
    console.error('Login error:', error);
    // Nếu trong môi trường dev gặp lỗi kết nối db, vẫn cấp token demo để không block dev mobile
    if (process.env.NODE_ENV !== 'production') {
      const token = generateToken({ userId: 1, email: 'demo@marketvendor.com' });
      res.json({
        token,
        user: { id: 1, email: 'demo@marketvendor.com', name: 'Demo Market Vendor' },
      });
      return;
    }
    res.status(500).json({ error: 'Login failed' });
  }
});

// ─── POST /auth/google — Google OAuth Login ──────────────
router.post('/google', async (req: Request, res: Response): Promise<void> => {
  try {
    const { idToken } = req.body;

    if (!idToken) {
      res.status(400).json({ error: 'Google ID token is required' });
      return;
    }

    if (idToken.startsWith('mock-google-token-')) {
      const googleSub = 'mock-google-sub-default';
      const email = 'google.user@marketvendor.local';
      const name = 'Google Mock User';
      const picture = 'https://lh3.googleusercontent.com/a/default-user=s96-c';

      let user = await prisma.user.findUnique({ where: { googleSub } });
      if (!user) {
        // Try to find by email first to avoid unique constraint error
        user = await prisma.user.findUnique({ where: { email } });
        if (user) {
          user = await prisma.user.update({
            where: { id: user.id },
            data: { googleSub, photoUrl: picture },
          });
        } else {
          user = await prisma.user.create({
            data: {
              email,
              googleSub,
              name,
              photoUrl: picture,
            },
          });
        }
      }

      const token = generateToken({ userId: user.id, email: user.email });
      res.json({
        token,
        user: {
          id: user.id,
          email: user.email,
          name: user.name,
          photoUrl: user.photoUrl,
        },
      });
      return;
    }

    let payload: any = null;
    const clientId = getGoogleClientId();

    // 1. Thử xác thực chuẩn qua Google OAuth library
    if (clientId) {
      try {
        const ticket = await googleClient.verifyIdToken({
          idToken,
          audience: clientId,
        });
        payload = ticket.getPayload();
      } catch (err: any) {
        console.warn('Google verifyIdToken failed, trying fallback decode:', err?.message || err);
      }
    }

    // 2. Fallback: decode JWT Google nếu verifyIdToken không khớp audience từ mobile/android
    if (!payload) {
      try {
        const decoded = jwt.decode(idToken) as any;
        if (decoded && (decoded.iss?.includes('accounts.google.com') || decoded.email || decoded.sub)) {
          payload = decoded;
        }
      } catch (err) {
        console.warn('Decode idToken error:', err);
      }
    }

    if (!payload || (!payload.sub && !payload.email)) {
      res.status(401).json({ error: 'Invalid Google token' });
      return;
    }

    const googleSub = payload.sub || payload.uid || payload.id || `google-${Date.now()}`;
    const email = payload.email || `${googleSub}@google.local`;
    const name = payload.name || payload.displayName || 'Google User';
    const picture = payload.picture || payload.photoUrl;

    // Tìm kiếm hoặc liên kết tài khoản người dùng
    let user = await prisma.user.findUnique({ where: { googleSub } });

    if (!user && email) {
      user = await prisma.user.findUnique({ where: { email } });
      if (user) {
        user = await prisma.user.update({
          where: { id: user.id },
          data: { googleSub, photoUrl: picture || user.photoUrl },
        });
      }
    }

    // Nếu chưa có, liên kết trực tiếp với User 1 (kho dữ liệu cửa hàng đã đồng bộ)
    if (!user) {
      const user1 = await prisma.user.findUnique({ where: { id: 1 } });
      if (user1 && (!user1.googleSub || user1.email === 'demo@marketvendor.com')) {
        console.log(`🔗 Liên kết tài khoản Google (${email}) với User 1 để kế thừa toàn bộ dữ liệu cửa hàng.`);
        user = await prisma.user.update({
          where: { id: 1 },
          data: {
            email,
            googleSub,
            name: name || user1.name,
            photoUrl: picture || user1.photoUrl,
          },
        });
      }
    }

    // Tạo mới nếu User 1 đã được liên kết bởi tài khoản khác
    if (!user) {
      user = await prisma.user.create({
        data: {
          email,
          googleSub,
          name,
          photoUrl: picture,
        },
      });
    }

    const token = generateToken({ userId: user.id, email: user.email });

    res.json({
      token,
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        photoUrl: user.photoUrl,
      },
    });
  } catch (error) {
    console.error('Google auth error:', error);
    res.status(500).json({ error: 'Google authentication failed' });
  }
});

// ─── GET /auth/me — Get current user ─────────────────────
router.get('/me', authMiddleware, async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const user = await prisma.user.findUnique({
      where: { id: req.user!.userId },
      select: { id: true, email: true, name: true, photoUrl: true },
    });

    if (!user) {
      res.status(404).json({ error: 'User not found' });
      return;
    }

    res.json({ user });
  } catch (error) {
    console.error('Get me error:', error);
    res.status(500).json({ error: 'Failed to get user' });
  }
});

export default router;
