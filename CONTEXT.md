# CONTEXT.md — Market Vendor App

## Tổng quan
Hệ thống quản lý bán hàng đa nền tảng gồm:
1. **Flutter Mobile App** (`lib/`): POS, Quản lý kho RAW/MIX, Sổ nợ, Báo cáo, Giọng nói AI. Hoạt động song song Dual-Mode: Offline (SQLite cũ) và Online (PostgreSQL Server).
2. **Backend API** (`backend-api/`): Node.js + Express + TypeScript + Prisma ORM + PostgreSQL (`localhost:3005`). Cổng 3007 (HTTP) / 3443 (HTTPS).
3. **Web App Next.js 16** (`web-app/`): Giao diện quản lý dashboard, POS, báo cáo trên trình duyệt.

## Trạng thái hiện tại (2026-09-23)

### Nâng cấp Đồng bộ PostgreSQL & Chế độ Online - Offline (Hoàn thành)
- **Địa chỉ máy chủ backend mặc định:** `http://14.160.33.94:3007` (mặc định đặt cứng trong mobile app).
- **Backend API (`backend-api/`)**:
  - Khởi chạy song song HTTP trên `0.0.0.0:3007` và HTTPS trên cổng phụ `3443`.
  - Hỗ trợ cả 2 tiền tố route: `/api/sync/*` và `/sync/*`.
  - Hoàn thiện xử lý đồng bộ trọn vẹn **13/13 bảng** (bổ sung `store_info`, `product_opening_stocks`, `debt_reminder_settings`).
  - Thêm endpoint `GET /api/sync/snapshot` phục vụ tải toàn bộ dữ liệu máy chủ về thiết bị.
  - Đã seed data và kiểm thử thành công: 20 SP, 12 KH, 102 đơn bán, 40 khoản nợ.
- **Mobile App (`lib/`)**:
  - **Khắc phục triệt để lag/chậm:** Thêm SQLite Migration v34 bổ sung 6 Indexes quan trọng (`idx_sale_items_saleId`, `idx_debt_payments_debtId`, `idx_sales_createdAt`, `idx_debts_partyId`, `idx_purchase_history_orderId`, `idx_outbox_status`). Loại bỏ hoàn toàn lỗi N+1 queries trong `getSales()` (gom nhóm truy vấn gom 1 query).
  - **Cơ chế Dual-Database bảo toàn dữ liệu:** Tách biệt `market_vendor.db` (Offline) và `market_vendor_online.db` (Online). Khi chuyển sang Online, toàn bộ dữ liệu offline cũ vẫn lưu giữ 100% trên máy. Khi chuyển lại Offline, app lập tức nạp lại nguyên vẹn kho dữ liệu offline cũ.
  - **Màn hình Đồng bộ PostgreSQL (`lib/screens/online_server_sync_screen.dart`):**
    - Đặt cứng cấu hình `14.160.33.94:3007`, có nút Reset & Test Ping.
    - Công tắc chuyển đổi Chế độ Online / Chế độ Offline có xác nhận an toàn.
    - Nút "Tải toàn bộ lên Máy chủ" (1 chiều từ Offline SQLite lên PostgreSQL).
    - Nút "Đồng bộ từ máy chủ về Offline" (Tải snapshot PostgreSQL về máy).
    - Bảng thống kê đối chiếu số lượng thực tế giữa Local và Server.
  - **Cài đặt (`lib/screens/settings_screen.dart`):** Bổ sung Card trạng thái Online/Offline trực quan và menu dẫn vào màn hình Đồng bộ PostgreSQL.
  - **Kiểm định mã nguồn:** `dart analyze` đạt 0 compile errors / warnings. Backend API hoàn thiện error handler tránh crash EADDRINUSE cho cổng phụ 3443, build và chạy thành công trên port 3007.
