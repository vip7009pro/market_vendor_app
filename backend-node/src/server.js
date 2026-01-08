import express from 'express';
import cors from 'cors';
import { Pool } from 'pg';
import { OAuth2Client } from 'google-auth-library';
import jwt from 'jsonwebtoken';
import dotenv from 'dotenv';
import { v4 as uuidv4 } from 'uuid';

dotenv.config();

const app = express();
app.use(cors());
app.use(express.json({ limit: '12mb' }));

//console.log('process.env', process.env);
const {
  PORT = '3006',
  DATABASE_URL,
  PGHOST,
  PGPORT,
  PGUSER,
  PGPASSWORD,
  PGDATABASE,
  GOOGLE_CLIENT_ID,
  JWT_SECRET,
} = process.env;

if (!GOOGLE_CLIENT_ID) {
  throw new Error('Missing env GOOGLE_CLIENT_ID');
}
if (!JWT_SECRET) {
  throw new Error('Missing env JWT_SECRET');
}

const poolConfig = (() => {
  const url = (DATABASE_URL ?? '').trim();
  if (url) {
    return { connectionString: url };
  }

  const host = (PGHOST ?? '').trim();
  const user = (PGUSER ?? '').trim();
  const password = (PGPASSWORD ?? '').trim();
  const database = (PGDATABASE ?? '').trim();
  const portRaw = (PGPORT ?? '').trim();
  const port = portRaw ? Number.parseInt(portRaw, 10) : 5432;

  if (!host || !user || !password || !database) {
    throw new Error(
      'Missing Postgres env. Provide DATABASE_URL=postgres://user:pass@host:port/dbname OR provide PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE'
    );
  }
  if (Number.isNaN(port)) {
    throw new Error('Invalid PGPORT (must be a number)');
  }

  return {
    host,
    port,
    user,
    password,
    database,
  };
})();

const pool = new Pool(poolConfig);
const googleClient = new OAuth2Client(GOOGLE_CLIENT_ID);

function parseIsoOrNull(v) {
  if (!v || typeof v !== 'string') return null;
  const d = new Date(v);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString();
}

async function upsertLww({
  client,
  table,
  userId,
  id,
  updatedAt,
  columns,
  columnCasts,
  primaryKey = 'id', // Allow custom primary key
}) {
  // columns: { db_col: value }
  const keys = Object.keys(columns);
  const colNames = ['user_id', primaryKey, ...keys, 'updated_at'];
  const values = [userId, id, ...keys.map((k) => columns[k]), updatedAt];

  const casts = columnCasts || {};
  const placeholders = values
      .map((_, i) => {
        const idx = i + 1;
        if (idx === 1 || idx === 2 || idx === values.length) return `$${idx}`;
        const keyIndex = idx - 3;
        const key = keys[keyIndex];
        const cast = key ? casts[key] : null;
        return cast ? `$${idx}::${cast}` : `$${idx}`;
      })
      .join(', ');

  // Build SET clause and LWW WHERE condition - all tables support soft delete now
  const setPairs = [...keys.map((k) => `${k} = EXCLUDED.${k}`), 'updated_at = EXCLUDED.updated_at', 'deleted_at = NULL'];

  const sql = `
    INSERT INTO ${table} (${colNames.join(', ')})
    VALUES (${placeholders})
    ON CONFLICT (user_id, ${primaryKey})
    DO UPDATE SET ${setPairs.join(', ')}
    WHERE ${table}.updated_at IS NULL OR EXCLUDED.updated_at > ${table}.updated_at
  `;
  await client.query(sql, values);
}

async function deleteLww({ client, table, userId, id, deletedAt }) {
  // All tables support soft delete now
  const sql = `
    UPDATE ${table}
    SET deleted_at = $3
    WHERE user_id = $1 AND id = $2
      AND (updated_at IS NULL OR $3 > updated_at)
  `;
  await client.query(sql, [userId, id, deletedAt]);
}

async function upsertDebtPaymentLww({ client, userId, uuid, updatedAt, columns }) {
  const sql = `
    INSERT INTO debt_payments (
      user_id,
      uuid,
      debt_id,
      amount,
      note,
      payment_type,
      created_at,
      updated_at,
      deleted_at
    )
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NULL)
    ON CONFLICT (user_id, uuid)
    DO UPDATE SET
      debt_id = EXCLUDED.debt_id,
      amount = EXCLUDED.amount,
      note = EXCLUDED.note,
      payment_type = EXCLUDED.payment_type,
      created_at = EXCLUDED.created_at,
      updated_at = EXCLUDED.updated_at,
      deleted_at = NULL
    WHERE debt_payments.updated_at IS NULL OR EXCLUDED.updated_at > debt_payments.updated_at
  `;

  await client.query(sql, [
    userId,
    uuid,
    columns.debt_id,
    columns.amount,
    columns.note,
    columns.payment_type,
    columns.created_at,
    updatedAt,
  ]);
}

async function applyEvent({ client, userId, ev }) {
  const { entity, entityId, op, payload, clientUpdatedAt } = ev || {};
  const updatedAt = parseIsoOrNull(clientUpdatedAt) || new Date().toISOString();
  if (!entity || !entityId || !op) return;

  // MVP mapping: payload keys follow camelCase from Flutter.
  // Server uses snake_case columns.
  const p = payload || {};

  if (op === 'delete') {
    const deletedAt = updatedAt;
    switch (entity) {
      case 'products':
      case 'customers':
      case 'sales':
      case 'debts':
      case 'debt_payments':
      case 'purchase_orders':
      case 'purchase_history':
      case 'expenses':
      case 'employees':
      case 'vietqr_bank_accounts':
        return deleteLww({ client, table: entity, userId, id: entityId, deletedAt });
      default:
        return;
    }
  }

  if (op !== 'upsert') return;

  switch (entity) {
    case 'products':
      return upsertLww({
        client,
        table: 'products',
        userId,
        id: entityId,
        updatedAt,
        columns: {
          name: p.name ?? '',
          price: p.price ?? 0,
          cost_price: p.costPrice ?? 0,
          current_stock: p.currentStock ?? 0,
          unit: p.unit ?? '',
          barcode: p.barcode ?? null,
          is_active: (p.isActive ?? 1) == 1 ? 1 : 0,
          item_type: p.itemType ?? 'RAW',
          is_stocked: (p.isStocked ?? 1) == 1 ? 1 : 0,
          image_path: p.imagePath ?? null,
        },
        columnCasts: {
          is_active: 'INTEGER',
          is_stocked: 'INTEGER',
        },
      });

    case 'customers':
      return upsertLww({
        client,
        table: 'customers',
        userId,
        id: entityId,
        updatedAt,
        columns: {
          name: p.name ?? '',
          phone: p.phone ?? null,
          note: p.note ?? null,
          is_supplier: (p.isSupplier ?? 0) == 1 ? 1 : 0,
        },
        columnCasts: {
          is_supplier: 'INTEGER',
        },
      });

    case 'employees':
      return upsertLww({
        client,
        table: 'employees',
        userId,
        id: entityId,
        updatedAt,
        columns: {
          name: p.name ?? '',
        },
      });

    case 'expenses':
      return upsertLww({
        client,
        table: 'expenses',
        userId,
        id: entityId,
        updatedAt,
        columns: {
          occurred_at: parseIsoOrNull(p.occurredAt) || updatedAt,
          amount: p.amount ?? 0,
          category: p.category ?? '',
          note: p.note ?? null,
          expense_doc_uploaded: (p.expenseDocUploaded ?? 0) == 1 ? 1 : 0,
          expense_doc_file_id: p.expenseDocFileId ?? null,
          expense_doc_updated_at: parseIsoOrNull(p.expenseDocUpdatedAt),
        },
        columnCasts: {
          expense_doc_uploaded: 'INTEGER',
        },
      });

    case 'purchase_orders':
      return upsertLww({
        client,
        table: 'purchase_orders',
        userId,
        id: entityId,
        updatedAt,
        columns: {
          created_at: parseIsoOrNull(p.createdAt) || updatedAt,
          supplier_name: p.supplierName ?? null,
          supplier_phone: p.supplierPhone ?? null,
          discount_type: p.discountType ?? 'AMOUNT',
          discount_value: p.discountValue ?? 0,
          paid_amount: p.paidAmount ?? 0,
          note: p.note ?? null,
          purchase_doc_uploaded: (p.purchaseDocUploaded ?? 0) == 1 ? 1 : 0,
          purchase_doc_file_id: p.purchaseDocFileId ?? null,
          purchase_doc_updated_at: parseIsoOrNull(p.purchaseDocUpdatedAt),
        },
        columnCasts: {
          purchase_doc_uploaded: 'INTEGER',
        },
      });

    case 'purchase_history':
      return upsertLww({
        client,
        table: 'purchase_history',
        userId,
        id: entityId,
        updatedAt,
        columns: {
          created_at: parseIsoOrNull(p.createdAt) || updatedAt,
          product_id: p.productId ?? '',
          product_name: p.productName ?? '',
          quantity: p.quantity ?? 0,
          unit_cost: p.unitCost ?? 0,
          total_cost: p.totalCost ?? 0,
          paid_amount: p.paidAmount ?? 0,
          supplier_name: p.supplierName ?? null,
          supplier_phone: p.supplierPhone ?? null,
          note: p.note ?? null,
          purchase_doc_uploaded: (p.purchaseDocUploaded ?? 0) == 1 ? 1 : 0,
          purchase_doc_file_id: p.purchaseDocFileId ?? null,
          purchase_doc_updated_at: parseIsoOrNull(p.purchaseDocUpdatedAt),
          purchase_order_id: p.purchaseOrderId ?? null,
        },
        columnCasts: {
          purchase_doc_uploaded: 'INTEGER',
        },
      });

    case 'debts':
      return upsertLww({
        client,
        table: 'debts',
        userId,
        id: entityId,
        updatedAt,
        columns: {
          created_at: parseIsoOrNull(p.createdAt) || updatedAt,
          type: p.type ?? 0,
          party_id: p.partyId ?? '',
          party_name: p.partyName ?? '',
          initial_amount: p.initialAmount ?? 0,
          amount: p.amount ?? 0,
          description: p.description ?? null,
          due_date: parseIsoOrNull(p.dueDate),
          settled: (p.settled ?? 0) == 1 ? 1 : 0,
          source_type: p.sourceType ?? null,
          source_id: p.sourceId ?? null,
        },
        columnCasts: {
          settled: 'INTEGER',
        },
      });

    case 'debt_payments':
      return upsertDebtPaymentLww({
        client,
        userId,
        uuid: entityId,
        updatedAt,
        columns: {
          debt_id: p.debtId,
          amount: p.amount ?? 0,
          note: p.note ?? null,
          payment_type: p.paymentType ?? null,
          created_at: parseIsoOrNull(p.createdAt) || updatedAt,
        },
      });

    case 'sales':
      return upsertLww({
        client,
        table: 'sales',
        userId,
        id: entityId,
        updatedAt,
        columns: {
          created_at: parseIsoOrNull(p.createdAt) || updatedAt,
          customer_id: p.customerId ?? null,
          customer_name: p.customerName ?? null,
          employee_id: p.employeeId ?? null,
          employee_name: p.employeeName ?? null,
          discount: p.discount ?? 0,
          paid_amount: p.paidAmount ?? 0,
          payment_type: p.paymentType ?? null,
          total_cost: p.totalCost ?? 0,
          note: p.note ?? null,
        },
      });

    case 'vietqr_bank_accounts':
      return upsertLww({
        client,
        table: 'vietqr_bank_accounts',
        userId,
        id: entityId,
        updatedAt,
        columns: {
          bank_api_id: p.bankApiId ?? null,
          name: p.name ?? null,
          code: p.code ?? null,
          bin: p.bin ?? null,
          short_name: p.shortName ?? p.short_name ?? null,
          logo: p.logo ?? null,
          transfer_supported: p.transferSupported == null ? null : (p.transferSupported == 1 ? 1 : 0),
          lookup_supported: p.lookupSupported == null ? null : (p.lookupSupported == 1 ? 1 : 0),
          support: p.support ?? null,
          is_transfer: p.isTransfer == null ? null : (p.isTransfer == 1 ? 1 : 0),
          swift_code: p.swift_code ?? p.swiftCode ?? null,
          account_no: p.accountNo ?? '',
          account_name: p.accountName ?? '',
          is_default: (p.isDefault ?? 0) == 1 ? 1 : 0,
        },
        columnCasts: {
          transfer_supported: 'INTEGER',
          lookup_supported: 'INTEGER',
          is_transfer: 'INTEGER',
          is_default: 'INTEGER',
        },
      });

    default:
      return;
  }
}

function signJwt({ userId }) {
  return jwt.sign({ sub: userId }, JWT_SECRET, { expiresIn: '30d' });
}

async function authMiddleware(req, res, next) {
  const h = req.headers.authorization || '';
  const m = /^Bearer\s+(.+)$/.exec(h);
  if (!m) return res.status(401).json({ error: 'missing_token' });
  try {
    const payload = jwt.verify(m[1], JWT_SECRET);
    req.userId = payload.sub;
    return next();
  } catch (e) {
    return res.status(401).json({ error: 'invalid_token' });
  }
}

app.get('/health1', (_req, res) => {
  res.json({ ok: true });
});

app.post('/auth/google', async (req, res) => {
  const { idToken, deviceId } = req.body || {};
  if (!idToken || typeof idToken !== 'string') {
    return res.status(400).json({ error: 'missing_idToken' });
  }
  if (!deviceId || typeof deviceId !== 'string') {
    return res.status(400).json({ error: 'missing_deviceId' });
  }

  const ticket = await googleClient.verifyIdToken({
    idToken,
    audience: GOOGLE_CLIENT_ID,
  });
  const p = ticket.getPayload();
  if (!p?.sub) return res.status(401).json({ error: 'invalid_google_token' });

  const googleSub = p.sub;
  const email = p.email || null;
  const name = p.name || null;
  const photoUrl = p.picture || null;

  const client = await pool.connect();
  try {
    const now = new Date().toISOString();
    const upsert = await client.query(
      `
      INSERT INTO users (google_sub, email, name, photo_url, created_at, updated_at)
      VALUES ($1, $2, $3, $4, $5, $5)
      ON CONFLICT (google_sub)
      DO UPDATE SET email = EXCLUDED.email,
                    name = EXCLUDED.name,
                    photo_url = EXCLUDED.photo_url,
                    updated_at = EXCLUDED.updated_at
      RETURNING id
      `,
      [googleSub, email, name, photoUrl, now],
    );
    const userId = upsert.rows[0].id;
    const token = signJwt({ userId });
    return res.json({ token, userId });
  } finally {
    client.release();
  }
});

app.post('/sync/push', authMiddleware, async (req, res) => {
  // MVP: apply events to entity tables using LWW, and append to sync_events for pull.
  const { deviceId, events } = req.body || {};
  console.log('Push request:', { deviceId, eventCount: events?.length });
  
  if (!deviceId || typeof deviceId !== 'string') {
    return res.status(400).json({ error: 'missing_deviceId' });
  }
  if (!Array.isArray(events)) {
    return res.status(400).json({ error: 'missing_events' });
  }

  const userId = req.userId;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const accepted = [];
    for (const ev of events) {
      const { entity, entityId, op, payload, clientUpdatedAt, eventUuid } = ev || {};
      console.log('Processing event:', { entity, entityId, op, eventUuid });
      
      if (!entity || !entityId || !op || !clientUpdatedAt) {
        console.log('Skipping invalid event:', { entity, entityId, op, clientUpdatedAt });
        continue;
      }

      // Idempotency: if eventUuid provided and already exists, skip.
      if (eventUuid) {
        const exist = await client.query(
          'SELECT 1 FROM sync_events WHERE user_id = $1 AND event_uuid = $2 LIMIT 1',
          [userId, eventUuid],
        );
        if (exist.rowCount > 0) {
          console.log('Event already exists, skipping:', eventUuid);
          continue;
        }
      }

      try {
        await applyEvent({ client, userId, ev: { entity, entityId, op, payload, clientUpdatedAt } });
        console.log('Event applied successfully:', { entity, entityId });
      } catch (applyError) {
        console.error('Error applying event:', { entity, entityId, error: applyError.message });
        throw applyError;
      }

      const r = await client.query(
        `
        INSERT INTO sync_events (user_id, device_id, entity, entity_id, op, payload, client_updated_at, event_uuid)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        RETURNING event_id
        `,
        [userId, deviceId, entity, entityId, op, payload ?? null, clientUpdatedAt, eventUuid ?? null],
      );
      accepted.push(r.rows[0].event_id);
    }
    await client.query('COMMIT');
    console.log('Push completed:', { acceptedCount: accepted.length });
    return res.json({ ok: true, acceptedEventIds: accepted });
  } catch (e) {
    await client.query('ROLLBACK');
    console.error('Push failed:', { error: e.message, stack: e.stack });
    return res.status(500).json({ error: 'push_failed', details: e.message });
  } finally {
    client.release();
  }
});

app.get('/sync/pull', authMiddleware, async (req, res) => {
  const cursorRaw = (req.query.cursor ?? '0').toString();
  const cursor = Number.isFinite(Number(cursorRaw)) ? Number(cursorRaw) : 0;
  const limitRaw = (req.query.limit ?? '500').toString();
  const limit = Math.min(Math.max(parseInt(limitRaw, 10) || 500, 1), 2000);

  const userId = req.userId;
  const r = await pool.query(
    `
    SELECT event_id, device_id, entity, entity_id, op, payload, client_updated_at, server_received_at, event_uuid
    FROM sync_events
    WHERE user_id = $1 AND event_id > $2
    ORDER BY event_id ASC
    LIMIT $3
    `,
    [userId, cursor, limit],
  );
  const nextCursor = r.rows.length ? r.rows[r.rows.length - 1].event_id : cursor;
  return res.json({ cursor: nextCursor, events: r.rows });
});

app.get('/health', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    return res.json({ ok: true, db: true });
  } catch (e) {
    return res.status(500).json({ ok: false, db: false, error: String(e) });
  }
});

app.listen(Number(PORT), () => {
  console.log(`API listening on :${PORT}`);

  (async () => {
    try {
      await pool.query('SELECT 1');
      console.log('DB connection: OK');
    } catch (e) {
      console.error('DB connection: ERROR', e);
    }
  })();
});
