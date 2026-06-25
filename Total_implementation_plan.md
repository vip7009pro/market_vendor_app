# Full-Stack Web Migration: Flutter → Next.js + New Backend + PostgreSQL

## Tổng quan

Chuyển đổi toàn bộ hệ thống quản lý bán hàng từ Flutter mobile sang hệ thống full-stack web, bao gồm:
- **Backend mới** (Node.js/Express, thư mục `backend-api/`) — khác với `backend-node` cũ, chỉ tham khảo
- **PostgreSQL DB mới** (`market_vendor_web`) — schema khớp 100% với mobile SQLite v33
- **Web app Next.js 16** (`web-app/`) — landing page + hệ thống bán hàng đầy đủ

## User Review Required

> [!IMPORTANT]
> **Tạo DB mới**: Backend mới sẽ kết nối tới database PostgreSQL **mới** tên `market_vendor_web`, không ảnh hưởng DB cũ.

> [!IMPORTANT]
> **Backend mới tách biệt**: Thư mục `backend-api/` hoàn toàn mới, tham khảo `backend-node/` nhưng viết lại từ đầu với kiến trúc tốt hơn (modular, route splitting, Prisma ORM).

> [!WARNING]
> **Next.js 16**: Sẽ sử dụng `next@latest` (hiện tại là v16+ với App Router, React 19, Turbopack). Cần Node.js >= 18.18.

## Open Questions

> [!IMPORTANT]
> 1. **Auth method cho web**: Tiếp tục dùng Google OAuth giống mobile? Hay cần thêm email/password?
> 2. **Hosting dự kiến**: Deploy ở đâu? (Vercel cho Next.js, VPS cho backend, hoặc tất cả cùng VPS?)
> 3. **PostgreSQL connection**: Kết nối DB local (localhost:5432) hay remote server? Cung cấp thông tin kết nối DB.
> 4. **Data migration**: Có cần tool để migrate dữ liệu từ mobile SQLite/DB cũ sang DB mới không?

---

## Database Schema Analysis — Mobile SQLite v33

Từ [database_service.dart](file:///g:/NODEJS/market_vendor_app/lib/services/database_service.dart), hệ thống mobile hiện có **20 bảng**:

### Entity Tables (cần chuyển sang PostgreSQL)
| # | Table | PK | Mô tả |
|---|-------|----|----|
| 1 | `products` | `id TEXT` | Sản phẩm (RAW/MIX), giá bán, giá vốn, tồn kho |
| 2 | `customers` | `id TEXT` | Khách hàng/nhà cung cấp |
| 3 | `sales` | `id TEXT` | Đơn bán hàng |
| 4 | `sale_items` | `id INTEGER AUTOINCREMENT` | Chi tiết đơn bán (FK→sales) |
| 5 | `debts` | `id TEXT` | Công nợ (oweOthers/othersOweMe) |
| 6 | `debt_payments` | `id INTEGER AUTOINCREMENT` + `uuid TEXT` | Thanh toán công nợ |
| 7 | `purchase_orders` | `id TEXT` | Đơn nhập hàng (header) |
| 8 | `purchase_history` | `id TEXT` | Chi tiết nhập hàng (line items) |
| 9 | `expenses` | `id TEXT` | Chi phí |
| 10 | `employees` | `id TEXT` | Nhân viên |
| 11 | `vietqr_bank_accounts` | `id TEXT` | Tài khoản ngân hàng VietQR |
| 12 | `store_info` | `id INTEGER` | Thông tin cửa hàng |

### Support Tables
| # | Table | Mô tả |
|---|-------|----|
| 13 | `product_opening_stocks` | Tồn đầu kỳ theo tháng |
| 14 | `debt_reminder_settings` | Cài đặt nhắc nợ |
| 15 | `deleted_entities` | Tracking soft delete cho sync |
| 16 | `audit_logs` | Nhật ký thay đổi |
| 17 | `sync_logs` | Log đồng bộ |
| 18 | `outbox` | Outbox pattern cho sync |
| 19 | `sync_state` | Trạng thái sync (key-value) |
| 20 | `applied_sync_events` | Idempotency cho pull sync |

### Mobile Screens → Web Pages mapping
| Mobile Screen | Web Page | Priority |
|---|---|---|
| `login_screen.dart` | `/login` | P0 |
| `home_screen.dart` | `/dashboard` | P0 |
| `sale_screen.dart` | `/pos` (Point of Sale) | P0 |
| `sales_history_screen.dart` | `/sales` | P0 |
| `product_list_screen.dart` | `/products` | P0 |
| `customer_list_screen.dart` + `customer_form_screen.dart` | `/customers` | P1 |
| `debt_screen.dart` + `debt_detail_screen.dart` + `debt_form_screen.dart` | `/debts` | P1 |
| `purchase_order_list/create/detail_screen.dart` | `/purchases` | P1 |
| `purchase_history_screen.dart` | `/purchases/history` | P1 |
| `expense_screen.dart` | `/expenses` | P1 |
| `report_screen.dart` + `inventory_report_screen.dart` | `/reports` | P2 |
| `employee_management_screen.dart` | `/settings/employees` | P2 |
| `store_info_screen.dart` | `/settings/store` | P2 |
| `vietqr_bank_accounts_screen.dart` | `/settings/bank-accounts` | P2 |
| `settings_screen.dart` | `/settings` | P2 |
| N/A (new) | `/` Landing Page | P0 |

---

## Proposed Changes — Phân Phase

### **PHASE 1: Foundation** (Backend + DB + Auth + Landing)
> Mục tiêu: Dựng nền tảng — Backend API, DB schema, Auth, Landing page, Login

---

#### Component 1: PostgreSQL Schema

##### [NEW] `backend-api/prisma/schema.prisma`
Schema Prisma khớp 100% mobile SQLite v33, chuyển đổi:
- `TEXT` → `String`
- `REAL` → `Float` / `Decimal`
- `INTEGER` (boolean) → `Boolean`
- `AUTOINCREMENT` → `autoincrement()`
- Thêm `userId` (multi-tenant) cho tất cả entity tables
- Sử dụng `@@id([userId, id])` cho composite primary key
- `TIMESTAMPTZ` cho thời gian
- snake_case naming convention (PostgreSQL standard)

Bao gồm tất cả 20 bảng từ mobile:
```
users, products, customers, sales, sale_items, debts, debt_payments,
purchase_orders, purchase_history, expenses, employees,
vietqr_bank_accounts, store_info, product_opening_stocks,
debt_reminder_settings, deleted_entities, audit_logs, sync_logs,
outbox, sync_state, applied_sync_events
```

---

#### Component 2: Backend API

##### [NEW] `backend-api/` directory structure
```
backend-api/
├── prisma/
│   └── schema.prisma
├── src/
│   ├── index.ts                  # Express entry point
│   ├── config/
│   │   └── database.ts           # Prisma client singleton
│   ├── middleware/
│   │   ├── auth.ts               # JWT + Google OAuth verify
│   │   └── errorHandler.ts       # Global error handler
│   ├── routes/
│   │   ├── auth.routes.ts        # POST /auth/google, /auth/refresh
│   │   ├── products.routes.ts    # CRUD products
│   │   ├── customers.routes.ts   # CRUD customers
│   │   ├── sales.routes.ts       # CRUD sales + sale_items
│   │   ├── debts.routes.ts       # CRUD debts + debt_payments
│   │   ├── purchases.routes.ts   # CRUD purchase_orders + history
│   │   ├── expenses.routes.ts    # CRUD expenses
│   │   ├── employees.routes.ts   # CRUD employees
│   │   ├── reports.routes.ts     # Aggregated reports
│   │   ├── settings.routes.ts    # store_info, bank_accounts
│   │   └── sync.routes.ts        # Mobile sync (push/pull)
│   ├── services/
│   │   ├── auth.service.ts
│   │   ├── product.service.ts
│   │   ├── sale.service.ts       # Business logic: stock deduction, totalCost calc
│   │   ├── debt.service.ts       # Business logic: payment tracking, settlement
│   │   ├── purchase.service.ts   # Business logic: stock addition, order-debt sync
│   │   ├── expense.service.ts
│   │   ├── report.service.ts     # Revenue, profit, inventory reports
│   │   └── sync.service.ts       # Two-way sync logic
│   └── utils/
│       ├── validators.ts
│       └── helpers.ts
├── package.json
├── tsconfig.json
├── .env.example
└── Dockerfile
```

**Tính năng backend:**
- **TypeScript** + Express + Prisma ORM
- Google OAuth2 login → JWT token
- REST API CRUD cho tất cả entities
- Business logic khớp 100% mobile:
  - Bán hàng → trừ tồn kho (RAW trực tiếp, MIX → trừ nguyên liệu)
  - Nhập hàng → cộng tồn kho
  - Công nợ → tự động link từ sale/purchase
  - Báo cáo doanh thu, lợi nhuận, tồn kho
- Sync API giữ nguyên (tương thích mobile)

---

#### Component 3: Next.js Web App

##### [NEW] `web-app/` directory structure (Next.js 16, App Router)
```
web-app/
├── src/
│   ├── app/
│   │   ├── layout.tsx            # Root layout + providers
│   │   ├── page.tsx              # Landing page (/)
│   │   ├── login/page.tsx        # Login page
│   │   ├── (dashboard)/          # Authenticated layout group
│   │   │   ├── layout.tsx        # Sidebar + header layout
│   │   │   ├── dashboard/page.tsx
│   │   │   ├── pos/page.tsx      # Point of Sale
│   │   │   ├── sales/page.tsx
│   │   │   ├── products/page.tsx
│   │   │   ├── customers/page.tsx
│   │   │   ├── debts/page.tsx
│   │   │   ├── purchases/page.tsx
│   │   │   ├── expenses/page.tsx
│   │   │   ├── reports/page.tsx
│   │   │   └── settings/
│   │   │       ├── page.tsx
│   │   │       ├── store/page.tsx
│   │   │       ├── employees/page.tsx
│   │   │       └── bank-accounts/page.tsx
│   │   └── globals.css
│   ├── components/
│   │   ├── ui/                   # Shared UI components
│   │   ├── layout/               # Header, Sidebar, Footer
│   │   ├── landing/              # Landing page sections
│   │   ├── pos/                  # POS-specific components
│   │   ├── products/
│   │   ├── customers/
│   │   ├── sales/
│   │   ├── debts/
│   │   ├── purchases/
│   │   ├── expenses/
│   │   └── reports/
│   ├── lib/
│   │   ├── api.ts                # API client (fetch wrapper)
│   │   ├── auth.ts               # Auth context/hooks
│   │   ├── utils.ts              # Formatters, helpers
│   │   └── types.ts              # TypeScript types (mirror Dart models)
│   └── hooks/
│       ├── useAuth.ts
│       ├── useProducts.ts
│       ├── useSales.ts
│       └── ...
├── public/
│   └── images/
├── package.json
├── next.config.ts
├── tsconfig.json
└── tailwind.config.ts            # (nếu user chọn Tailwind)
```

**Phase 1 web features:**
- ✅ Landing page chuyên nghiệp (hero, features, pricing, CTA)
- ✅ Login with Google
- ✅ Dashboard tổng quan (KPIs, charts)
- ✅ Responsive design (mobile-first)

---

### **PHASE 2: Core Business** (Bán hàng + Sản phẩm + Khách hàng)
> Mục tiêu: Chức năng bán hàng cốt lõi hoạt động trên web

| Task | Tương ứng mobile |
|------|-----------------|
| Quản lý sản phẩm (CRUD, RAW/MIX, ảnh, barcode, tồn kho) | `product_list_screen.dart` |
| Quản lý khách hàng/nhà cung cấp | `customer_list_screen.dart`, `customer_form_screen.dart` |
| POS — Tạo đơn bán hàng | `sale_screen.dart` |
| Lịch sử bán hàng (filter, search, edit, delete) | `sales_history_screen.dart`, `sale_edit_screen.dart` |
| Xem/In hóa đơn | `receipt_preview_screen.dart` |

**Business logic cần replicate:**
- Tính `totalCost` khi tạo sale (RAW → từ `costPrice`, MIX → từ `unitCost`)
- Trừ tồn kho khi bán (RAW trực tiếp, MIX → trừ nguyên liệu qua `mixItemsJson`)
- Hoàn tồn kho khi xóa/sửa đơn
- `paymentType`: cash/bank
- Discount dạng số tuyệt đối (VND)
- Ghi nhân viên bán hàng

---

### **PHASE 3: Công nợ + Nhập hàng + Chi phí**
> Mục tiêu: Quản lý tài chính đầy đủ

| Task | Tương ứng mobile |
|------|-----------------|
| Công nợ (oweOthers / othersOweMe) | `debt_screen.dart`, `debt_detail_screen.dart` |
| Thanh toán công nợ | `debt_detail_screen.dart` |
| Tạo công nợ từ sale/purchase | `debt_form_screen.dart` |
| Nhắc nợ | `debt_reminder_settings` |
| Đơn nhập hàng (purchase orders) | `purchase_order_*_screen.dart` |
| Lịch sử nhập hàng | `purchase_history_screen.dart` |
| Chi phí (expenses) | `expense_screen.dart` |

**Business logic:**
- Auto-create debt khi bán thiếu (`paidAmount < total`)
- `syncPurchaseOrderDebt` — tự động cập nhật debt khi sửa purchase order
- `deletePurchaseOrder` — cascade delete: debt payments → debts → purchase_history + hoàn tồn
- `initialAmount` tracking cho debt payments
- VietQR bank accounts cho thanh toán

---

### **PHASE 4: Báo cáo + Settings**
> Mục tiêu: Dashboard thông minh, báo cáo chi tiết

| Task | Tương ứng mobile |
|------|-----------------|
| Báo cáo doanh thu/lợi nhuận | `report_screen.dart` |
| Báo cáo tồn kho | `inventory_report_screen.dart` |
| Tồn đầu kỳ / Kiểm kê | `product_opening_stocks` table |
| Quản lý nhân viên | `employee_management_screen.dart` |
| Thông tin cửa hàng | `store_info_screen.dart` |
| Tài khoản ngân hàng | `vietqr_bank_accounts_screen.dart` |
| Cài đặt hệ thống | `settings_screen.dart` |

---

### **PHASE 5: Sync + Advanced Features**
> Mục tiêu: Đồng bộ mobile ↔ web, tính năng nâng cao

| Task | Mô tả |
|------|-------|
| Two-way sync API | Push/pull giữa mobile SQLite ↔ PostgreSQL |
| Voice order (AI) | Port `voice_order_screen.dart` → web |
| Export PDF/Excel | Hóa đơn, báo cáo |
| PWA support | Offline-capable web app |

---

## Technology Stack

| Layer | Technology |
|-------|-----------|
| **Frontend** | Next.js 16, React 19, TypeScript, CSS Variables + custom design system |
| **Backend** | Node.js, Express, TypeScript, Prisma ORM |
| **Database** | PostgreSQL 16, DB name: `market_vendor_web` |
| **Auth** | Google OAuth2 → JWT |
| **Build** | Turbopack (Next.js 16 default) |

---

## Verification Plan

### Automated Tests
- `npx prisma db push` — verify schema creates all tables
- `npm run build` — verify Next.js builds without errors
- `npm run dev` — verify backend starts and connects to DB

### Manual Verification
- Tạo tài khoản test qua Google OAuth
- CRUD products, sales, debts
- Verify stock adjustment logic
- Compare business logic output with mobile app

---

## Execution Order

```
Phase 1 (Foundation) — bắt đầu ngay
├── 1.1 Prisma schema + DB migration
├── 1.2 Backend API (auth + basic CRUD)
├── 1.3 Next.js project setup
├── 1.4 Landing page
└── 1.5 Login + Dashboard skeleton

Phase 2 (Core Business) — sau Phase 1
├── 2.1 Products CRUD + API
├── 2.2 Customers CRUD + API
├── 2.3 POS (Point of Sale)
└── 2.4 Sales history

Phase 3 (Finance) — sau Phase 2
├── 3.1 Debts + payments
├── 3.2 Purchase orders + history
└── 3.3 Expenses

Phase 4 (Reports + Settings) — sau Phase 3
├── 4.1 Revenue/profit reports
├── 4.2 Inventory reports
└── 4.3 Settings pages

Phase 5 (Advanced) — sau Phase 4
├── 5.1 Mobile sync
├── 5.2 AI features
└── 5.3 PWA + export
```
