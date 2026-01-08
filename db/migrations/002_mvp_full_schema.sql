-- 002_mvp_full_schema.sql
-- MVP schema to mirror current Flutter SQLite tables (server-side)

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Add idempotency to sync_events
ALTER TABLE IF EXISTS sync_events
  ADD COLUMN IF NOT EXISTS event_uuid UUID;

CREATE UNIQUE INDEX IF NOT EXISTS ux_sync_events_user_event_uuid
  ON sync_events(user_id, event_uuid)
  WHERE event_uuid IS NOT NULL;

-- Common note:
-- Each entity table is scoped by user_id (1 Google account = 1 store).
-- LWW conflict resolution is based on updated_at.

CREATE TABLE IF NOT EXISTS products (
  id UUID NOT NULL,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  price NUMERIC NOT NULL DEFAULT 0,
  cost_price NUMERIC NOT NULL DEFAULT 0,
  current_stock NUMERIC NOT NULL DEFAULT 0,
  unit TEXT NOT NULL,
  barcode TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  item_type TEXT NOT NULL DEFAULT 'RAW',
  is_stocked BOOLEAN NOT NULL DEFAULT TRUE,
  image_path TEXT,
  updated_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, id)
);

CREATE INDEX IF NOT EXISTS idx_products_user_updated ON products(user_id, updated_at);

CREATE TABLE IF NOT EXISTS customers (
  id UUID NOT NULL,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  phone TEXT,
  note TEXT,
  is_supplier BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, id)
);

CREATE INDEX IF NOT EXISTS idx_customers_user_updated ON customers(user_id, updated_at);

-- Sales: store items as JSONB for MVP to avoid local sale_items integer-id mismatch.
CREATE TABLE IF NOT EXISTS sales (
  id UUID NOT NULL,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL,
  customer_id UUID,
  customer_name TEXT,
  employee_id UUID,
  employee_name TEXT,
  discount NUMERIC NOT NULL DEFAULT 0,
  paid_amount NUMERIC NOT NULL DEFAULT 0,
  payment_type TEXT,
  total_cost NUMERIC NOT NULL DEFAULT 0,
  note TEXT,
  items JSONB NOT NULL DEFAULT '[]'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, id)
);

CREATE INDEX IF NOT EXISTS idx_sales_user_updated ON sales(user_id, updated_at);

CREATE TABLE IF NOT EXISTS debts (
  id UUID NOT NULL,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL,
  type INT NOT NULL,
  party_id TEXT NOT NULL,
  party_name TEXT NOT NULL,
  initial_amount NUMERIC NOT NULL DEFAULT 0,
  amount NUMERIC NOT NULL DEFAULT 0,
  description TEXT,
  due_date TIMESTAMPTZ,
  settled BOOLEAN NOT NULL DEFAULT FALSE,
  source_type TEXT,
  source_id TEXT,
  updated_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, id)
);

CREATE INDEX IF NOT EXISTS idx_debts_user_updated ON debts(user_id, updated_at);

CREATE TABLE IF NOT EXISTS debt_payments (
  id UUID NOT NULL,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  debt_id UUID NOT NULL,
  amount NUMERIC NOT NULL,
  note TEXT,
  payment_type TEXT,
  created_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, id)
);

CREATE INDEX IF NOT EXISTS idx_debt_payments_user_updated ON debt_payments(user_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_debt_payments_user_debt ON debt_payments(user_id, debt_id);

CREATE TABLE IF NOT EXISTS purchase_orders (
  id UUID NOT NULL,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL,
  supplier_name TEXT,
  supplier_phone TEXT,
  discount_type TEXT NOT NULL DEFAULT 'AMOUNT',
  discount_value NUMERIC NOT NULL DEFAULT 0,
  paid_amount NUMERIC NOT NULL DEFAULT 0,
  note TEXT,
  purchase_doc_uploaded BOOLEAN NOT NULL DEFAULT FALSE,
  purchase_doc_file_id TEXT,
  purchase_doc_updated_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, id)
);

CREATE INDEX IF NOT EXISTS idx_purchase_orders_user_updated ON purchase_orders(user_id, updated_at);

CREATE TABLE IF NOT EXISTS purchase_history (
  id UUID NOT NULL,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL,
  product_id UUID NOT NULL,
  product_name TEXT NOT NULL,
  quantity NUMERIC NOT NULL,
  unit_cost NUMERIC NOT NULL DEFAULT 0,
  total_cost NUMERIC NOT NULL DEFAULT 0,
  paid_amount NUMERIC NOT NULL DEFAULT 0,
  supplier_name TEXT,
  supplier_phone TEXT,
  note TEXT,
  purchase_doc_uploaded BOOLEAN NOT NULL DEFAULT FALSE,
  purchase_doc_file_id TEXT,
  purchase_doc_updated_at TIMESTAMPTZ,
  purchase_order_id UUID,
  updated_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, id)
);

CREATE INDEX IF NOT EXISTS idx_purchase_history_user_updated ON purchase_history(user_id, updated_at);

CREATE TABLE IF NOT EXISTS expenses (
  id UUID NOT NULL,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  occurred_at TIMESTAMPTZ NOT NULL,
  amount NUMERIC NOT NULL,
  category TEXT NOT NULL,
  note TEXT,
  expense_doc_uploaded BOOLEAN NOT NULL DEFAULT FALSE,
  expense_doc_file_id TEXT,
  expense_doc_updated_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, id)
);

CREATE INDEX IF NOT EXISTS idx_expenses_user_updated ON expenses(user_id, updated_at);

CREATE TABLE IF NOT EXISTS employees (
  id UUID NOT NULL,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, id)
);

CREATE INDEX IF NOT EXISTS idx_employees_user_updated ON employees(user_id, updated_at);

CREATE TABLE IF NOT EXISTS store_info (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  address TEXT NOT NULL,
  phone TEXT NOT NULL,
  tax_code TEXT,
  email TEXT,
  bank_name TEXT,
  bank_account TEXT,
  updated_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS product_opening_stocks (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  product_id UUID NOT NULL,
  year INT NOT NULL,
  month INT NOT NULL,
  opening_stock NUMERIC NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (user_id, product_id, year, month)
);

CREATE TABLE IF NOT EXISTS debt_reminder_settings (
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  debt_id UUID NOT NULL,
  muted BOOLEAN NOT NULL DEFAULT FALSE,
  last_notified_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, debt_id)
);

CREATE TABLE IF NOT EXISTS vietqr_bank_accounts (
  id UUID NOT NULL,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  bank_api_id INT,
  name TEXT,
  code TEXT,
  bin TEXT,
  short_name TEXT,
  logo TEXT,
  transfer_supported BOOLEAN,
  lookup_supported BOOLEAN,
  support INT,
  is_transfer BOOLEAN,
  swift_code TEXT,
  account_no TEXT NOT NULL,
  account_name TEXT NOT NULL,
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL,
  deleted_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, id)
);

CREATE INDEX IF NOT EXISTS idx_vietqr_bank_accounts_user_updated ON vietqr_bank_accounts(user_id, updated_at);
