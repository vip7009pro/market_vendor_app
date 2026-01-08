-- Backend PostgreSQL Schema for Market Vendor App

-- Users table for Google OAuth authentication
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    google_sub TEXT UNIQUE NOT NULL,
    email TEXT,
    name TEXT,
    photo_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Sync events table for online synchronization
CREATE TABLE IF NOT EXISTS sync_events (
    event_id BIGSERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id TEXT NOT NULL,
    entity TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    op TEXT NOT NULL CHECK (op IN ('upsert', 'delete')),
    payload JSONB,
    client_updated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    server_received_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    event_uuid TEXT UNIQUE
);

-- Indexes for better performance
CREATE INDEX IF NOT EXISTS idx_sync_events_user_cursor ON sync_events(user_id, event_id);
CREATE INDEX IF NOT EXISTS idx_sync_events_user_entity ON sync_events(user_id, entity);
CREATE INDEX IF NOT EXISTS idx_sync_events_device ON sync_events(device_id);
CREATE INDEX IF NOT EXISTS idx_sync_events_uuid ON sync_events(event_uuid);

-- Products table
CREATE TABLE IF NOT EXISTS products (
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    name TEXT NOT NULL,
    price REAL NOT NULL,
    cost_price REAL NOT NULL DEFAULT 0,
    current_stock REAL NOT NULL DEFAULT 0,
    unit TEXT NOT NULL,
    barcode TEXT,
    is_active INTEGER NOT NULL DEFAULT 1,
    item_type TEXT NOT NULL DEFAULT 'RAW',
    is_stocked INTEGER NOT NULL DEFAULT 1,
    image_path TEXT,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    device_id TEXT,
    deleted_at TIMESTAMP WITH TIME ZONE, -- Soft delete support
    PRIMARY KEY (user_id, id)
);

-- Customers table
CREATE TABLE IF NOT EXISTS customers (
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    name TEXT NOT NULL,
    phone TEXT,
    note TEXT,
    is_supplier INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    device_id TEXT,
    deleted_at TIMESTAMP WITH TIME ZONE, -- Soft delete support
    PRIMARY KEY (user_id, id)
);

-- Sales table
CREATE TABLE IF NOT EXISTS sales (
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    customer_id TEXT,
    customer_name TEXT,
    employee_id TEXT,
    employee_name TEXT,
    discount REAL NOT NULL DEFAULT 0,
    paid_amount REAL NOT NULL DEFAULT 0,
    payment_type TEXT,
    total_cost REAL NOT NULL DEFAULT 0,
    note TEXT,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    device_id TEXT,
    deleted_at TIMESTAMP WITH TIME ZONE, -- Soft delete support
    PRIMARY KEY (user_id, id)
);

-- Sale items table
CREATE TABLE IF NOT EXISTS sale_items (
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    id SERIAL PRIMARY KEY,
    sale_id TEXT NOT NULL,
    product_id TEXT,
    name TEXT NOT NULL,
    unit_price REAL NOT NULL,
    unit_cost REAL NOT NULL DEFAULT 0,
    quantity REAL NOT NULL,
    unit TEXT NOT NULL,
    item_type TEXT,
    display_name TEXT,
    mix_items_json TEXT,
    deleted_at TIMESTAMP WITH TIME ZONE, -- Soft delete support
    FOREIGN KEY (user_id, sale_id) REFERENCES sales(user_id, id) ON DELETE CASCADE
);

-- Debts table
CREATE TABLE IF NOT EXISTS debts (
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    type INTEGER NOT NULL,
    party_id TEXT NOT NULL,
    party_name TEXT NOT NULL,
    initial_amount REAL NOT NULL DEFAULT 0,
    amount REAL NOT NULL,
    description TEXT,
    due_date TIMESTAMP WITH TIME ZONE,
    settled INTEGER NOT NULL DEFAULT 0,
    source_type TEXT,
    source_id TEXT,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    device_id TEXT,
    deleted_at TIMESTAMP WITH TIME ZONE, -- Soft delete support
    PRIMARY KEY (user_id, id)
);

-- Debt payments table
CREATE TABLE IF NOT EXISTS debt_payments (
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    id SERIAL PRIMARY KEY, -- Keep integer id for compatibility with SQLite
    uuid TEXT NOT NULL, -- UUID for sync
    debt_id TEXT NOT NULL,
    amount REAL NOT NULL,
    note TEXT,
    payment_type TEXT,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE,
    deleted_at TIMESTAMP WITH TIME ZONE, -- Soft delete support
    UNIQUE (user_id, uuid),
    FOREIGN KEY (user_id, debt_id) REFERENCES debts(user_id, id) ON DELETE CASCADE
);

-- Expenses table
CREATE TABLE IF NOT EXISTS expenses (
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    occurred_at TIMESTAMP WITH TIME ZONE NOT NULL,
    amount REAL NOT NULL,
    category TEXT NOT NULL,
    note TEXT,
    expense_doc_uploaded INTEGER NOT NULL DEFAULT 0,
    expense_doc_file_id TEXT,
    expense_doc_updated_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    device_id TEXT,
    deleted_at TIMESTAMP WITH TIME ZONE, -- Soft delete support
    PRIMARY KEY (user_id, id)
);

-- Employees table
CREATE TABLE IF NOT EXISTS employees (
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    name TEXT NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    device_id TEXT,
    deleted_at TIMESTAMP WITH TIME ZONE, -- Soft delete support
    PRIMARY KEY (user_id, id)
);

-- Purchase orders table
CREATE TABLE IF NOT EXISTS purchase_orders (
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    supplier_name TEXT,
    supplier_phone TEXT,
    discount_type TEXT NOT NULL DEFAULT 'AMOUNT',
    discount_value REAL NOT NULL DEFAULT 0,
    paid_amount REAL NOT NULL DEFAULT 0,
    note TEXT,
    purchase_doc_uploaded INTEGER NOT NULL DEFAULT 0,
    purchase_doc_file_id TEXT,
    purchase_doc_updated_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    device_id TEXT,
    deleted_at TIMESTAMP WITH TIME ZONE, -- Soft delete support
    PRIMARY KEY (user_id, id)
);

-- Purchase history table
CREATE TABLE IF NOT EXISTS purchase_history (
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL,
    product_id TEXT NOT NULL,
    product_name TEXT NOT NULL,
    quantity REAL NOT NULL,
    unit_cost REAL NOT NULL DEFAULT 0,
    total_cost REAL NOT NULL DEFAULT 0,
    paid_amount REAL NOT NULL DEFAULT 0,
    supplier_name TEXT,
    supplier_phone TEXT,
    note TEXT,
    purchase_doc_uploaded INTEGER NOT NULL DEFAULT 0,
    purchase_doc_file_id TEXT,
    purchase_doc_updated_at TIMESTAMP WITH TIME ZONE,
    purchase_order_id TEXT,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    device_id TEXT,
    deleted_at TIMESTAMP WITH TIME ZONE, -- Soft delete support
    PRIMARY KEY (user_id, id)
);

-- VietQR bank accounts table
CREATE TABLE IF NOT EXISTS vietqr_bank_accounts (
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
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
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL,
    device_id TEXT,
    deleted_at TIMESTAMP WITH TIME ZONE, -- Soft delete support
    PRIMARY KEY (user_id, id)
);
