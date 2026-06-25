import { Router, Response } from 'express';
import { authMiddleware, AuthRequest } from '../middleware/auth.js';
import { SyncService } from '../services/sync.service.js';

const router = Router();
router.use(authMiddleware);

// POST /api/sync/push
router.post('/push', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const { deviceId, events } = req.body;

    if (!deviceId) {
      res.status(400).json({ error: 'deviceId is required' });
      return;
    }

    if (!Array.isArray(events)) {
      res.status(400).json({ error: 'events array is required' });
      return;
    }

    const insertedCount = await SyncService.pushEvents(userId, deviceId, events);
    res.json({ success: true, pushed: insertedCount });
  } catch (error: any) {
    console.error('Push error:', error);
    res.status(500).json({ error: 'Sync push failed: ' + error.message });
  }
});

// GET /api/sync/pull
router.get('/pull', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const userId = req.user!.userId;
    const cursor = parseInt(req.query.cursor as string) || 0;
    const limit = parseInt(req.query.limit as string) || 500;

    const result = await SyncService.pullEvents(userId, cursor, limit);
    res.json(result);
  } catch (error: any) {
    console.error('Pull error:', error);
    res.status(500).json({ error: 'Sync pull failed: ' + error.message });
  }
});

export default router;
