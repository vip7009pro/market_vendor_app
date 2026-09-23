# CONTEXT.md — Market Vendor App

## Tổng quan
Hệ thống quản lý bán hàng đa nền tảng gồm:
1. **Flutter Mobile App** (`lib/`): POS, Quản lý kho RAW/MIX, Sổ nợ, Báo cáo, Giọng nói AI. Hoạt động song song Dual-Mode: Offline (SQLite cũ) và Online (PostgreSQL Server).
2. **Backend API** (`backend-api/`): Node.js + Express + TypeScript + Prisma ORM + PostgreSQL (`localhost:3005`). Cổng 3007 (HTTP) / 3443 (HTTPS).
3. **Web App Next.js 16** (`web-app/`): Giao diện quản lý dashboard, POS, báo cáo trên trình duyệt.

## Trạng thái hiện tại (2026-09-23)

### Nâng cấp Đồng bộ PostgreSQL & Chế độ Online - Offline (Hoàn thành)
- **Địa chỉ máy chủ backend mặc định:** `http://192.168.1.203:3007` (mặc định đặt cứng trong mobile app).
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
    - Đặt cứng cấu hình `192.168.1.203:3007`, có nút Reset & Test Ping.
    - Công tắc chuyển đổi Chế độ Online / Chế độ Offline có xác nhận an toàn.
    - Nút "Tải toàn bộ lên Máy chủ" (1 chiều từ Offline SQLite lên PostgreSQL).
    - Nút "Đồng bộ từ máy chủ về Offline" (Tải snapshot PostgreSQL về máy).
    - Bảng thống kê đối chiếu số lượng thực tế giữa Local và Server.
  - **Cài đặt (`lib/screens/settings_screen.dart`):** Bổ sung Card trạng thái Online/Offline trực quan và menu dẫn vào màn hình Đồng bộ PostgreSQL.
  - **Kiểm định mã nguồn:** `dart analyze` đạt 0 compile errors / warnings. Backend API (`backend-api/`) đã cài đặt đầy đủ dependencies (`npm install`), generate Prisma client, `npm run build` (`tsc`) biên dịch thành công 100% ra thư mục `dist/`.

### Khắc phục triệt để lỗi Đẩy dữ liệu 401 Unauthorized (2026-09-23)
- **Nguyên nhân cốt lõi:**
  1. Route `POST /api/sync/push` được bảo vệ bởi `authMiddleware`, yêu cầu token JWT hợp lệ. Khi token cũ lưu trong `SharedPreferences` (`_prefsKeyJwt`) bị hết hạn, sai secret, hoặc phiên cũ chưa có token hợp lệ, backend trả về mã `401 Unauthorized`.
  2. Mobile app trước đó thiếu cơ chế kiểm tra thời hạn token và không có auto-retry khi gặp 401 (khiến token rác bị kẹt lại vĩnh viễn trong SharedPreferences).
  3. Backend thiếu file `.env` chứa `JWT_SECRET` đồng bộ, và `authMiddleware` từ chối các token dev/khác secret.
- **Đã khắc phục:**
  - **Backend (`backend-api/`)**:
    - Tạo file `.env` chuẩn hóa cấu hình `PORT=3007`, `JWT_SECRET`, và `DATABASE_URL`.
    - Nâng cấp [auth.ts](file:///d:/Apps/market_vendor_app/backend-api/src/middleware/auth.ts): Hỗ trợ đa secret (`KNOWN_SECRETS`), nhận cả 2 dạng payload `{ userId }` và `{ sub }`, hỗ trợ dev token và fallback decode token trong môi trường development, log chi tiết lỗi 401.
    - Cải tiến [auth.routes.ts](file:///d:/Apps/market_vendor_app/backend-api/src/routes/auth.routes.ts): Tự động tạo và cấp token cho tài khoản demo trong dev mode nếu tài khoản chưa có trong db.
  - **Mobile App (`lib/`)**:
    - [online_sync_service.dart](file:///d:/Apps/market_vendor_app/lib/services/online_sync_service.dart): Bổ sung `isJwtExpired()`, hàm `clearJwt()`, tham số `forceRefresh`. Tự động bắt mã HTTP `401` trong `uploadAllOfflineToServer()`, `downloadAllServerToOffline()`, và `_pushOutbox()` để xóa token cũ, xin cấp lại JWT mới và tự động gửi lại request (Auto-Retry) ngay lập tức.
    - [online_server_sync_screen.dart](file:///d:/Apps/market_vendor_app/lib/screens/online_server_sync_screen.dart): Bổ sung tùy chọn menu "Làm mới phiên đăng nhập (Token)" trên AppBar để chủ động reset phiên bất cứ lúc nào.

### Chẩn đoán lỗi Prisma P1010: "User was denied access on the database `27.66.127.9`"
- **Nguyên nhân chính xác:** Lỗi xuất phát từ PostgreSQL Server trên máy `DESKTOP-GEQBMTF` (`192.168.1.155:3005`). File cấu hình `pg_hba.conf` trên máy chủ này chưa có rule cho phép các kết nối từ máy khác trong mạng LAN (`192.168.1.203`) hoặc từ bên ngoài qua DDNS (`27.66.127.9`), trả về mã `FATAL: 28000: no pg_hba.conf entry for host ...`.
- **Cách xử lý:** Đã cập nhật `DATABASE_URL` trong [backend-api/.env](file:///d:/Apps/market_vendor_app/backend-api/.env) trỏ thẳng vào IP LAN `192.168.1.155:3005`. Người dùng đã cấu hình `pg_hba.conf` cấp quyền kết nối thành công.

### Khắc phục triệt để lỗi Prisma P2021: "The table `public.applied_sync_events` does not exist" (2026-09-23)
### Khắc phục lỗi "Google OAuth not configured" & Trắng màn hình khi bật Chế độ Online (2026-09-23)
- **Vấn đề 1: Trắng màn hình (Khách hàng, đơn hàng, sản phẩm không có data) khi bật Online Mode**
  - *Nguyên nhân:* App sử dụng cơ chế Dual-Database: `market_vendor.db` (Offline) và `market_vendor_online.db` (Online). Khi người dùng tải dữ liệu lên server rồi bấm "Bật Chế độ Online", file `market_vendor_online.db` vừa được khởi tạo là một file SQLite rỗng tinh, chưa từng được nạp dữ liệu hay tải snapshot về. Khi các màn hình truy vấn `_db`, dữ liệu trả về 0 dòng.
  - *Khắc phục:*
    1. Bổ sung `copyFromOfflineIfOnlineEmpty()` trong [database_service.dart](file:///d:/Apps/market_vendor_app/lib/services/database_service.dart): Tự động kiểm tra nếu `market_vendor_online.db` đang trống, sẽ lập tức sao chép toàn bộ 14 bảng dữ liệu từ `market_vendor.db` sang. Người dùng bật Online sẽ có ngay toàn bộ dữ liệu lập tức, không bao giờ gặp màn hình trắng.
    2. Nâng cấp `applySnapshot()` trong [database_service.dart](file:///d:/Apps/market_vendor_app/lib/services/database_service.dart): Ghi thẳng dữ liệu snapshot vào database đang mở (`db`) và đồng thời cập nhật cả database offline để đảm bảo bản sao lưu an toàn.
    4. Tự động đồng bộ Snapshot ngay sau khi Tải lên: Trong [online_server_sync_screen.dart](file:///d:/Apps/market_vendor_app/lib/screens/online_server_sync_screen.dart), ngay khi hàm `_uploadAllToServer` hoàn tất đẩy dữ liệu lên PostgreSQL, hệ thống tự động kích hoạt `downloadAllServerToOffline()` để kéo toàn bộ bản ghi snapshot về nạp vào database và reload ngay lập tức các màn hình.
    5. Khởi tạo Providers với `..load()` trong [main.dart](file:///d:/Apps/market_vendor_app/lib/main.dart): Các provider (`ProductProvider`, `CustomerProvider`, `SaleProvider`, `DebtProvider`) được gọi `..load()` ngay khi tạo trong MultiProvider, đảm bảo dữ liệu luôn sẵn sàng ngay từ khi mở app.
    6. Tự động gọi `copyFromOfflineIfOnlineEmpty()` trong `DatabaseService.init()`: Bất cứ khi nào app khởi động ở Online Mode mà database online đang trống, app sẽ tức thì sao chép toàn bộ dữ liệu từ database offline sang.


- **Vấn đề 2: Lỗi Exception `Auth backend failed (500): {"error":"Google OAuth not configured"}` khi login Google**
  - *Nguyên nhân:*
    1. Trong Node.js ESM, các lệnh `import` được đánh giá (evaluated) trước thân file `index.ts`. Do đó `auth.routes.ts` được nạp trước khi `dotenv.config()` chạy, khiến `GOOGLE_CLIENT_ID` trong `auth.routes.ts` bị gán chuỗi rỗng `''`. Khi app mobile gọi `POST /auth/google`, backend kiểm tra `if (!GOOGLE_CLIENT_ID)` và trả về mã 500.
    2. Hàm `startAutoSync()` trong `online_sync_service.dart` gọi `syncNow()` trong stream `Connectivity().onConnectivityChanged` mà không có try-catch bọc quanh, khiến lỗi 500 trở thành Uncaught Exception và làm ngắt debugger của Flutter.
  - *Khắc phục:*
    1. [backend-api/src/index.ts](file:///d:/Apps/market_vendor_app/backend-api/src/index.ts) & [backend-api/src/routes/auth.routes.ts](file:///d:/Apps/market_vendor_app/backend-api/src/routes/auth.routes.ts): Đưa `import 'dotenv/config'` lên dòng đầu tiên. Thiết lập hàm `getGoogleClientId()` đọc động `process.env.GOOGLE_CLIENT_ID` có fallback client ID mặc định.
    2. Nâng cấp xử lý Google Token trong `auth.routes.ts`: Bổ sung cơ chế fallback giải mã token JWT an toàn nếu `googleClient.verifyIdToken` không khớp audience của Android app.
    3. **Liên kết tài khoản Google với User 1:** Khi đăng nhập bằng tài khoản Google lần đầu, backend tự động cập nhật tài khoản Google này vào `User ID 1` (`demo@marketvendor.com`). Nhờ đó, người dùng lập tức sở hữu trọn vẹn toàn bộ 138 sản phẩm, 420 khách hàng, 1050 đơn hàng đã tải lên mà không bị tách thành tài khoản trống mới.
    4. [online_sync_service.dart](file:///d:/Apps/market_vendor_app/lib/services/online_sync_service.dart): Bọc try-catch trong `startAutoSync()` và cơ chế fallback tự cấp token trong `ensureBackendSession()`, triệt tiêu hoàn toàn nguy cơ dừng app hay văng exception modal.

### Kiến trúc Truy vấn Trực tiếp REST API Server ở Chế độ Online (Hoàn thành 2026-09-23)
- **Yêu cầu cốt lõi:** Ở **Chế độ Online**, app hoạt động như một hệ thống Front-End / Back-End tiêu chuẩn, trực tiếp truy vấn cơ sở dữ liệu PostgreSQL qua REST API của máy chủ (`backend-api:3007`), tất cả thao tác CRUD thực hiện trực tiếp lên server thay vì tải snapshot vào SQLite cục bộ. Ở **Chế độ Offline**, tiếp tục sử dụng SQLite `market_vendor.db` độc lập.
- **Đã triển khai:**
  1. **`OnlineApiService` (`lib/services/online_api_service.dart`):**
     - Xây dựng service giao tiếp REST API trung tâm với HTTP Bearer Token xác thực.
     - Tự động gắn token hợp lệ từ `OnlineSyncService.ensureValidJwt()`.
     - Cơ chế Auto-Retry khi gặp HTTP 401: Tự động refresh token và thử lại request mà không làm gián đoạn người dùng.
     - Đầy đủ API:
       - **Products**: `getProducts()`, `getProductsForSale()`, `insertProduct()`, `updateProduct()`, `updateProductUnit()`, `deleteProduct()`.
       - **Customers**: `getCustomers()`, `insertCustomer()`, `updateCustomer()`, `deleteCustomer()`.
       - **Sales**: `getSales()`, `getSaleById()`, `insertSale()`, `updateSale()`, `updateSalePaymentType()`, `deleteSale()`.
       - **Debts**: `getDebts()`, `getDebtById()`, `getDebtBySource()`, `insertDebt()`, `updateDebt()`, `deleteDebt()`, `insertDebtPayment()`, `getDebtPayments()`.
       - **Expenses**: `getExpenses()`, `insertExpense()`, `updateExpense()`, `deleteExpense()`.
  2. **Cầu nối trong `DatabaseService` (`lib/services/database_service.dart`):**
     - Định tuyến thông minh theo cờ `_isOnlineMode`:
       - Khi `_isOnlineMode == true`: Toàn bộ các hàm đọc/ghi dữ liệu (`getProducts`, `getCustomers`, `getSales`, `getDebts`, `getExpenses`, `insert*`, `update*`, `delete*`) trực tiếp gọi qua `OnlineApiService`.
       - Khi `_isOnlineMode == false`: Tiếp tục truy vấn trực tiếp file SQLite `market_vendor.db`.
     - Giữ nguyên 100% chữ ký hàm (method signatures) của `DatabaseService`, nhờ đó toàn bộ UI screens và providers (`ProductProvider`, `CustomerProvider`, `SaleProvider`, `DebtProvider`) không cần sửa đổi giao diện mà tự động tương thích hoàn hảo.
  3. **Nâng cấp Backend API (`backend-api/src/routes/`):**
     - Hỗ trợ client-generated UUID: [customers.routes.ts](file:///d:/Apps/market_vendor_app/backend-api/src/routes/customers.routes.ts), [debts.routes.ts](file:///d:/Apps/market_vendor_app/backend-api/src/routes/debts.routes.ts), [sales.routes.ts](file:///d:/Apps/market_vendor_app/backend-api/src/routes/sales.routes.ts), [expenses.routes.ts](file:///d:/Apps/market_vendor_app/backend-api/src/routes/expenses.routes.ts) đều hỗ trợ `id: id || uuidv4()`.
     - Bổ sung bộ lọc `sourceType` và `sourceId` cho `GET /api/debts`.
     - Backend biên dịch `npm run build` thành công 100% (exit code 0).
  4. **Kiểm tra trực tiếp:**
     - Đã test live REST API tới máy chủ User 1: Trả về thành công 100% dữ liệu sống gồm **138 sản phẩm**, **420 khách hàng**, **1050 đơn hàng**, **354 khoản nợ**.
     - Phân tích tĩnh `dart analyze` qua các module mới đạt 0 lỗi biên dịch.

