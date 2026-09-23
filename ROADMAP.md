# ROADMAP.md — Kế hoạch phát triển & di chuyển hệ thống

## Tiến độ các giai đoạn (Tối đa 80 dòng - Cập nhật 2026-09-23)

### 📌 Các Phase nền tảng & Nghiệp vụ đã hoàn thành
- [x] **PHASE 1 - 5**: DB PostgreSQL, API Auth/CRUD, Next.js Web App, POS, Lịch sử bán, Sổ nợ, Nhập kho, Chi phí, Báo cáo KPIs, Sync 2 chiều cơ bản.
- [x] **PHASE 6 - 8**: Đồng bộ 14 KPIs Dashboard, Tìm kiếm Tiếng Việt không dấu, Tồn kho RAW/MIX, Chi tiết Backdata, Danh bạ di động, Chia sẻ hóa đơn Canvas PNG, HTTPS/SSL, Debounce QR.
- [x] **PHASE 9 - 10**: Chỉnh sửa đơn bán/nhập cân đối kho nợ, Upload chứng từ, Mobile Bottom Navigation Bar, Flat Card Layout, Đa theme sắc màu, Export Excel .xlsx SheetJS.
- [x] **PHASE 11**: Chuẩn hóa Google Play Store (Billing 8.0.0+, 16KB Page Size NDK r28, Xóa bỏ broad media permissions, Version code 39).

---

### 🚀 PHASE 12: Đồng bộ PostgreSQL & Chế độ Online - Offline Mobile (ĐÃ HOÀN THÀNH)
- [x] **12.1 Tối ưu hiệu năng Mobile & Trị dứt điểm giật lag**:
  - [x] Thêm SQLite Migration v34: 6 chỉ mục (indexes) trên `sale_items`, `debt_payments`, `sales`, `debts`, `purchase_history`, `outbox`.
  - [x] Xóa bỏ triệt để lỗi N+1 queries trong `getSales()`: gom nhóm truy vấn items 1 lần.
  - [x] Bổ sung dọn dẹp log cũ (`cleanOldLogs`).
- [x] **12.2 Backend API Đồng bộ Toàn diện 13/13 bảng**:
  - [x] Cấu hình `127.0.0.1:3005` trong `backend-api/.env` tránh loopback DNS.
  - [x] Bổ sung xử lý 3 bảng còn thiếu: `store_info`, `product_opening_stocks`, `debt_reminder_settings`.
  - [x] Endpoint `GET /api/sync/snapshot` truy vấn snapshot toàn bộ 13 bảng.
  - [x] Dual-route alias `/sync` và `/api/sync`; dual-protocol HTTP `0.0.0.0:3007` & HTTPS `3443`.
- [x] **12.3 Kiến trúc Dual-Database Mobile & An toàn dữ liệu**:
  - [x] Cơ chế Dual-DB: `market_vendor.db` (Offline) & `market_vendor_online.db` (Online).
  - [x] Chuyển đổi Online/Offline an toàn tuyệt đối: Dữ liệu offline cũ giữ nguyên 100% trên máy.
  - [x] Bật/tắt chế độ Online tức thì, tự động nạp lại dữ liệu cũ khi quay về offline.
- [x] **12.4 Màn hình Đồng bộ PostgreSQL (`OnlineServerSyncScreen`)**:
  - [x] Đặt cứng mặc định địa chỉ máy chủ `http://14.160.33.94:3007`, có nút Reset & Test Ping.
  - [x] Nút Tải lên máy chủ 1 chiều (Upload SQLite ➔ PostgreSQL).
  - [x] Nút Đồng bộ về máy (Download Snapshot PostgreSQL ➔ SQLite Offline).
  - [x] Đối chiếu số lượng trực quan 5 bảng chính và hiển thị trạng thái tại `SettingsScreen`.
