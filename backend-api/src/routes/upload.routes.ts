import { Router, Response } from 'express';
import { v4 as uuidv4 } from 'uuid';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { authMiddleware, AuthRequest } from '../middleware/auth.js';

const router = Router();
router.use(authMiddleware);

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// POST /api/upload
router.post('/', async (req: AuthRequest, res: Response): Promise<void> => {
  try {
    const { fileData, fileName } = req.body;
    if (!fileData) {
      res.status(400).json({ error: 'fileData is required' });
      return;
    }

    // Extract base64 binary content
    const base64Data = fileData.replace(/^data:.*;base64,/, "");
    const buffer = Buffer.from(base64Data, 'base64');

    // Create uploads directory in project root
    const uploadsDir = path.join(__dirname, '../../uploads');
    if (!fs.existsSync(uploadsDir)) {
      fs.mkdirSync(uploadsDir, { recursive: true });
    }

    // Generate unique name keeping extension
    const ext = path.extname(fileName || 'file.bin') || '.bin';
    const uniqueName = `${uuidv4()}${ext}`;
    const filePath = path.join(uploadsDir, uniqueName);

    // Save to disk
    fs.writeFileSync(filePath, buffer);

    res.status(201).json({
      data: {
        filePath: `uploads/${uniqueName}`,
        fileName: uniqueName
      }
    });
  } catch (error) {
    console.error('File upload route error:', error);
    res.status(500).json({ error: 'Failed to upload file' });
  }
});

export default router;
