-- schema.sql (Option A)
-- Sync-optimized PostgreSQL schema.
-- Notes:
-- - Entity tables are scoped by user_id.
-- - LWW conflict resolution uses updated_at.
-- - Soft delete uses deleted_at.
-- - No local-only columns like isSynced/deviceId in entity tables.

CREATE TABLE IF NOT EXISTS users (
  id BIGSERIAL PRIMARY KEY,
  google_sub TEXT NOT NULL UNIQUE,
  email TEXT,
  name TEXT,
  photo_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sync_events (
  event_id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id TEXT NOT NULL,
  entity TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  op TEXT NOT NULL CHECK (op IN ('upsert', 'delete')),
  payload JSONB,
  client_updated_at TIMESTAMPTZ NOT NULL,
  server_received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  event_uuid TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_sync_events_user_event_uuid
  ON sync_events(user_id, event_uuid)
  WHERE event_uuid IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_sync_events_user_event_id ON sync_events(user_id, event_id);
CREATE INDEX IF NOT EXISTS idx_sync_events_user_entity ON sync_events(user_id, entity);

CREATE TABLE IF NOT EXISTS products (
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  name TEXT NOT NULL,
  price NUMERIC NOT NULL,
  cost_price NUMERIC NOT NULL DEFAULT 0,
  current_stock NUMERIC NOT NULL DEFAULT 0,
  unit TEXT NOT NULL,
  barcode TEXT,
  is_active INTEGER NOT NULL DEFAULT 1,
  item_type TEXT NOT NULL DEFAULT 'RAW',
  is_stocked INTEGER NOT NULL DEFAULT 1,
  image_path TEXT,
  updated_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, id)
);

CREATE TABLE IF NOT EXISTS customers (
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  name TEXT NOT NULL,
  phone TEXT,
  note TEXT,
  is_supplier INTEGER NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, id)
);

CREATE TABLE IF NOT EXISTS employees (
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  name TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, id)
);

CREATE TABLE IF NOT EXISTS sales (
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  customer_id TEXT,
  customer_name TEXT,
  employee_id TEXT,
  employee_name TEXT,
  discount NUMERIC NOT NULL DEFAULT 0,
  paid_amount NUMERIC NOT NULL DEFAULT 0,
  payment_type TEXT,
  total_cost NUMERIC NOT NULL DEFAULT 0,
  note TEXT,
  updated_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, id)
);

CREATE TABLE IF NOT EXISTS sale_items (
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  sale_id TEXT NOT NULL,
  product_id TEXT,
  name TEXT NOT NULL,
  unit_price NUMERIC NOT NULL,
  unit_cost NUMERIC NOT NULL DEFAULT 0,
  quantity NUMERIC NOT NULL,
  unit TEXT NOT NULL,
  item_type TEXT,
  display_name TEXT,
  mix_items_json TEXT,
  updated_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, id)
);

CREATE INDEX IF NOT EXISTS idx_sale_items_user_sale ON sale_items(user_id, sale_id);

CREATE TABLE IF NOT EXISTS debts (
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  type INTEGER NOT NULL,
  party_id TEXT NOT NULL,
  party_name TEXT NOT NULL,
  initial_amount NUMERIC NOT NULL DEFAULT 0,
  amount NUMERIC NOT NULL,
  description TEXT,
  due_date TIMESTAMPTZ,
  settled INTEGER NOT NULL DEFAULT 0,
  source_type TEXT,
  source_id TEXT,
  updated_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, id)
);

CREATE TABLE IF NOT EXISTS debt_payments (
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  uuid TEXT NOT NULL,
  debt_id TEXT NOT NULL,
  amount NUMERIC NOT NULL,
  note TEXT,
  payment_type TEXT,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, uuid)
);

CREATE INDEX IF NOT EXISTS idx_debt_payments_user_debt ON debt_payments(user_id, debt_id);

CREATE TABLE IF NOT EXISTS purchase_orders (
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  supplier_name TEXT,
  supplier_phone TEXT,
  discount_type TEXT NOT NULL DEFAULT 'AMOUNT',
  discount_value NUMERIC NOT NULL DEFAULT 0,
  paid_amount NUMERIC NOT NULL DEFAULT 0,
  note TEXT,
  purchase_doc_uploaded INTEGER NOT NULL DEFAULT 0,
  purchase_doc_file_id TEXT,
  purchase_doc_updated_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, id)
);

CREATE TABLE IF NOT EXISTS purchase_history (
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL,
  product_id TEXT NOT NULL,
  product_name TEXT NOT NULL,
  quantity NUMERIC NOT NULL,
  unit_cost NUMERIC NOT NULL DEFAULT 0,
  total_cost NUMERIC NOT NULL DEFAULT 0,
  paid_amount NUMERIC NOT NULL DEFAULT 0,
  supplier_name TEXT,
  supplier_phone TEXT,
  note TEXT,
  purchase_doc_uploaded INTEGER NOT NULL DEFAULT 0,
  purchase_doc_file_id TEXT,
  purchase_doc_updated_at TIMESTAMPTZ,
  purchase_order_id TEXT,
  updated_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, id)
);

CREATE TABLE IF NOT EXISTS expenses (
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL,
  amount NUMERIC NOT NULL,
  category TEXT NOT NULL,
  note TEXT,
  expense_doc_uploaded INTEGER NOT NULL DEFAULT 0,
  expense_doc_file_id TEXT,
  expense_doc_updated_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, id)
);

CREATE TABLE IF NOT EXISTS vietqr_bank_accounts (
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  id TEXT NOT NULL,
  bank_api_id INTEGER,
  name TEXT,
  code TEXT,
  bin TEXT,
  short_name TEXT,
  logo TEXT,
  transfer_supported INTEGER,
  lookup_supported INTEGER,
  support INTEGER,
  is_transfer INTEGER,
  swift_code TEXT,
  account_no TEXT NOT NULL,
  account_name TEXT NOT NULL,
  is_default INTEGER NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, id)
);
