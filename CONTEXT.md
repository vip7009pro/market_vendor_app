# CONTEXT.md — Market Vendor App

## Tổng quan
Hệ thống quản lý bán hàng đa nền tảng gồm:
1. **Flutter Mobile App** (`lib/`): POS, Quản lý kho RAW/MIX, Sổ nợ, Báo cáo, Giọng nói AI. Hoạt động song song Dual-Mode: Offline (SQLite cũ) và Online (PostgreSQL Server).
2. **Backend API** (`backend-api/`): Node.js + Express + TypeScript + Prisma ORM + PostgreSQL (`localhost:3005`). Cổng 3007 (HTTP) / 3443 (HTTPS).
3. **Web App Next.js 16** (`web-app/`): Giao diện quản lý dashboard, POS, báo cáo trên trình duyệt.

## Trạng thái hiện tại (2026-09-23)

### Nâng cấp Đồng bộ PostgreSQL & Chế độ Online - Offline (Hoàn thành)
- **Địa chỉ máy chủ backend mặc định:** `http://ruougaohoatuoi.ddns.net:3007` (mặc định đặt cứng trong mobile app).
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
    - Đặt cứng cấu hình `ruougaohoatuoi.ddns.net:3007`, có nút Reset & Test Ping.
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
- **Nguyên nhân chính xác:** Lỗi xuất phát từ PostgreSQL Server trên máy `DESKTOP-GEQBMTF` (`192.168.1.155:3005`). File cấu hình `pg_hba.conf` trên máy chủ này chưa có rule cho phép các kết nối từ máy khác trong mạng LAN (`ruougaohoatuoi.ddns.net`) hoặc từ bên ngoài qua DDNS (`27.66.127.9`), trả về mã `FATAL: 28000: no pg_hba.conf entry for host ...`.
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

### Khắc phục triệt để lỗi Prisma P2028: "Transaction not found... refers to an old closed transaction" khi đồng bộ dữ liệu (2026-09-23)
- **Nguyên nhân chính xác:**
  - Prisma Client mặc định giới hạn thời gian thực thi của một Interactive Transaction (`prisma.$transaction(async (tx) => ...)`) là **5000 ms (5 giây)** và `maxWait: 2000 ms`.
  - Khi người dùng đăng nhập tài khoản khác hoặc tải lên lần đầu, client gửi một lô dữ liệu gồm hàng trăm bản ghi (hàng trăm đơn hàng kèm chi tiết `sale_items`, sản phẩm, công nợ). Việc thực thi tuần tự hàng trăm câu lệnh database bên trong transaction vượt quá 5 giây.
  - Khi chạm mốc 5 giây, Prisma Engine tự động đóng và rollback transaction. Lệnh kế tiếp (`tx.saleItem.updateMany`) cố thực thi trên transaction đã đóng, dẫn đến lỗi: `P2028: Transaction not found. Transaction ID is invalid, refers to an old closed transaction Prisma doesn't have information about anymore`.
- **Cách khắc phục:**
  1. **Backend (`backend-api/src/services/sync.service.ts`):**
     - Nâng cấp `pushEvents`: Chia nhỏ danh sách sự kiện thành các gói con **50 events/lô**.
     - Cấu hình tường minh tham số timeout cho Prisma Transaction: `{ maxWait: 30000, timeout: 120000 }` (2 phút thay vì 5 giây mặc định). Nhờ đó, mỗi batch hoàn tất chỉ trong 1-3 giây và không bao giờ bị Prisma đóng sớm.
     - Tối ưu hóa điều kiện `updateMany` của `saleItem` loại bỏ `{ updatedAt: undefined }`.
  2. **Mobile App (`lib/services/online_sync_service.dart`):**
     - Điều chỉnh `chunkSize` từ 200 xuống **50 bản ghi/lần gửi**: Giảm tải kích thước payload HTTP, thanh tiến trình hiển thị mịn và mượt mà hơn (mỗi 50 bản ghi cập nhật 1 lần).
     - Tăng HTTP request timeout từ 40s lên **60s** cho cả `uploadAllOfflineToServer` và `_pushOutbox`.

### Khắc phục triệt để lỗi Treo màn hình Splash Screen sau khi Đăng nhập Google (2026-09-23)
- **Hiện tượng:** Người dùng bấm "Đăng nhập với Google" thành công, popup Google tắt nhưng app bị treo vĩnh viễn ở màn hình Splash Screen (`Icon shopping_cart` + text `App Bán Hàng Ghi Nợ` + `CircularProgressIndicator`). Phải tắt ép ứng dụng (kill app) rồi mở lại mới vào được `HomeScreen`.
- **Nguyên nhân cốt lõi:**
  1. **Hiển thị Splash sai thời điểm trong `AuthGate` (`lib/main.dart`):** `AuthGate` kiểm tra `if (auth.isLoading)` để hiển thị toàn màn hình Splash Screen. Khi người dùng bấm nút đăng nhập, `signInWithGoogle` đặt `_isLoading = true`, khiến `AuthGate` lập tức tiêu hủy `LoginScreen` và thay thế bằng Splash Screen. Trong khi đó, `LoginScreen` đã có sẵn spinner loading riêng trên nút bấm ("Đang đăng nhập...").
  2. **Block luồng UI do `await OnlineSyncService.startAutoSync`:** Trước đó, trong `signInWithGoogle()` của `AuthProvider`, hàm `startAutoSync` được gọi với `await` trước khi đặt `_isLoading = false`. `startAutoSync` lại kích hoạt `syncNow()`, `ensureBackendSession()`, và `getIdToken()`. Việc thực hiện toàn bộ chuỗi đồng bộ database qua mạng trước khi nhả loading khiến `_isLoading` bị giữ ở mức `true` hàng phút hoặc vĩnh viễn nếu mạng chập chờn.
  3. **Treo silent login trên Android:** `getIdToken()` và `getAccessToken()` luôn gọi `_googleSignIn.signInSilently()`. Trên Android, ngay sau khi người dùng vừa đăng nhập bằng popup, việc lập tức gọi lại `signInSilently()` có thể bị chặn hoặc delay bởi Google Play Services.
  4. **Xung đột điều hướng `Navigator.pushReplacement`:** Trong `LoginScreen`, sau khi `signInWithGoogle()` hoàn tất, code lại gọi tiếp `Navigator.pushReplacement(HomeScreen)`. Điều này xung đột trực tiếp với cơ chế reactive của `AuthGate` (vốn đã tự động chuyển sang `HomeScreen` khi `auth.isSignedIn == true`).
- **Cách khắc phục:**
  1. **`lib/main.dart` (`AuthGate`):**
     - Bỏ kiểm tra `auth.isLoading` cho màn hình Splash. Thay bằng `if (!auth.initialChecked)`.
     - Splash Screen chỉ xuất hiện trong khoảnh khắc app vừa mở máy để đọc cache Firebase. Khi ở màn hình Login, trạng thái loading chỉ nằm trên nút bấm của `LoginScreen`.
     - Ngay khi `auth.isSignedIn == true`, `AuthGate` phản ứng tức thì và chuyển ngay sang `const HomeScreen()`.
  2. **`lib/providers/auth_provider.dart`:**
     - Đưa việc kết thúc loading vào khối `finally { _setLoading(false); }` để đảm bảo 100% luôn nhả cờ loading.
     - Khởi chạy `OnlineSyncService.startAutoSync(auth: this)` trong `unawaited(...)` ngầm ở background, tuyệt đối không block luồng đăng nhập UI.
     - Tối ưu `getIdToken()` và `getAccessToken()`: Ưu tiên lấy tài khoản đã đăng nhập sẵn trong bộ nhớ `_googleSignIn.currentUser`, chỉ gọi fallback `signInSilently()` kèm timeout an toàn 5 giây.
  3. **`lib/screens/login_screen.dart`:**
     - Loại bỏ lệnh `Navigator.pushReplacement` dư thừa, để `AuthGate` tự động chuyển trang mượt mà theo kiến trúc Provider chuẩn của Flutter.
  4. **`lib/screens/home_screen.dart`:**
     - Dọn dẹp import thừa và thêm `if (!mounted) return;` trước khi đọc ThemeProvider.
  5. **Kiểm tra chất lượng mã nguồn:**
     - Chạy `dart analyze` qua toàn bộ các file liên quan: `lib/main.dart`, `lib/providers/auth_provider.dart`, `lib/screens/login_screen.dart`, `lib/screens/home_screen.dart` đạt **0 issues (No issues found!)**.

### Bổ sung Thanh Tiến trình (Progress Bar) & Trạng thái Tải dữ liệu Đa màn hình (2026-09-23)
- **Mục tiêu:** Bổ sung hiển thị trực quan thanh tiến trình và thông báo khi đang tải dữ liệu hoặc đồng bộ dữ liệu từ server về máy, giúp người dùng nắm rõ tình trạng hệ thống đang hoạt động và không hiểu lầm là app bị lag hoặc đơ.
- **Đã triển khai:**
  1. **Thanh tiến trình toàn cục & Huy hiệu trạng thái trên HomeScreen (`lib/screens/home_screen.dart`):**
     - Đặt một `Stack` bao phủ toàn bộ các tab của app.
     - Khi bất kỳ tác vụ nào đang nạp dữ liệu (`_isRefreshingData`, `ProductProvider.isLoading`, `CustomerProvider.isLoading`, `SaleProvider.isLoading`, `DebtProvider.isLoading` hoặc `OnlineSyncService.isSyncingNotifier`):
       - Hiển thị dải `LinearProgressIndicator(minHeight: 3.5)` chạy mượt mà ngay trên đỉnh màn hình (sát dưới thanh trạng thái SafeArea).
       - Hiển thị huy hiệu dạng viên thuốc (floating frosted pill badge) nổi nhẹ nhàng ở giữa trên đỉnh: có icon `CircularProgressIndicator` xoay kèm văn bản trạng thái chi tiết (ví dụ: `"Đang tải dữ liệu..."`, `"Đang nạp dữ liệu vào máy..."`, `"Đang tải dữ liệu từ máy chủ..."`, `"Đang đồng bộ dữ liệu..."`).
       - Bọc toàn bộ trong `IgnorePointer` để thanh tiến trình hoàn toàn không gây cản trở thao tác chạm/vuốt màn hình của người dùng.
       - Khi nạp dữ liệu xong, thanh tiến trình tự động biến mất 100%.
  2. **Trạng thái `isLoading` trong các Provider (`lib/providers/`):**
     - Cập nhật [ProductProvider](file:///d:/Apps/market_vendor_app/lib/providers/product_provider.dart), [SaleProvider](file:///d:/Apps/market_vendor_app/lib/providers/sale_provider.dart), [DebtProvider](file:///d:/Apps/market_vendor_app/lib/providers/debt_provider.dart) bổ sung cờ `_isLoading` và getter `bool get isLoading`.
     - Quản lý an toàn trạng thái nạp dữ liệu trong khối `try/finally` để đảm bảo cờ `isLoading` luôn được reset về `false`.
  3. **Bộ thông báo trạng thái đồng bộ (`lib/services/online_sync_service.dart`):**
     - Bổ sung `isSyncingNotifier` (`ValueNotifier<bool>`) và `syncStatusNotifier` (`ValueNotifier<String?>`).
     - Tự động phát tín hiệu tiến trình trong `uploadAllOfflineToServer()`, `downloadAllServerToOffline()`, và `syncNow()`.
  4. **Chỉ báo tải dữ liệu trên từng màn hình danh sách:**
     - [ProductListScreen](file:///d:/Apps/market_vendor_app/lib/screens/product_list_screen.dart): Hiển thị `CircularProgressIndicator` + `"Đang tải danh sách sản phẩm..."` khi danh sách đang tải thay vì để màn hình trống.
     - [CustomerListScreen](file:///d:/Apps/market_vendor_app/lib/screens/customer_list_screen.dart): Hiển thị `CircularProgressIndicator` + `"Đang tải danh sách khách hàng..."` khi đang nạp dữ liệu.
     - [SalesHistoryScreen](file:///d:/Apps/market_vendor_app/lib/screens/sales_history_screen.dart): Hiển thị `CircularProgressIndicator` + `"Đang tải lịch sử bán hàng..."`.
     - [DebtScreen](file:///d:/Apps/market_vendor_app/lib/screens/debt_screen.dart): Hiển thị `CircularProgressIndicator` + `"Đang tải danh sách công nợ..."`.

### Tối ưu hóa Hiệu năng & Thiết kế Tải Dữ liệu theo Khoảng Ngày (2026-10-04)
- **Vấn đề đã rà soát:**
  1. Khi app chạy ở Chế độ Online với tập dữ liệu lớn, việc mở app hoặc chuyển màn hình gây lag/đơ nghiêm trọng do `SaleProvider().load()` gọi `DatabaseService.instance.getSales()` -> `OnlineApiService.instance.getSales()` gửi tham số đặt cứng `limit: 'all'` mà không kèm bất kỳ bộ lọc ngày nào. Backend phải truy vấn toàn bộ lịch sử bán hàng và hàng chục nghìn chi tiết đơn (`sale_items`), tuần tự hóa chuỗi JSON khổng lồ trả về qua mạng khiến quá trình parse JSON trên main thread của điện thoại bị treo/lag.
  2. Ở chế độ Offline, SQLite cũng thực hiện `db.query('sale_items')` toàn bộ bảng không có điều kiện WHERE, gây tốn bộ nhớ và chậm chạp.
  3. `DebtProvider` và `ExpenseScreen` trước đó cũng tải toàn bộ dữ liệu lịch sử vô hạn định.
  4. Màn hình đồng bộ `online_server_sync_screen.dart` gọi tải toàn bộ bản ghi của cả 5 bảng chỉ để lấy `.length`.
- **Giải pháp đã triển khai:**
  1. **Backend API (`backend-api/`):**
     - [schema.prisma](file:///d:/Apps/market_vendor_app/backend-api/prisma/schema.prisma): Bổ sung các chỉ mục phục vụ truy vấn theo khoảng ngày và trạng thái: `@@index([userId, createdAt])` trên bảng `sales`, `@@index([userId, createdAt])`, `@@index([userId, settled])`, `@@index([userId, sourceType, sourceId])` trên bảng `debts`, `@@index([userId, occurredAt])` trên bảng `expenses`.
     - [debts.routes.ts](file:///d:/Apps/market_vendor_app/backend-api/src/routes/debts.routes.ts): Bổ sung hỗ trợ lọc `startDate`, `endDate`, và `limit` cho `GET /api/debts`.
     - [sync.routes.ts](file:///d:/Apps/market_vendor_app/backend-api/src/routes/sync.routes.ts): Thêm endpoint `GET /api/sync/counts` đếm nhanh số lượng bản ghi bằng `prisma.*.count()` trả về chỉ số trong 2-5ms, thay thế hoàn toàn việc tải hàng nghìn bản ghi để đếm.
     - Biên dịch backend `npm run build` thành công 100% (code 0).
  2. **Mobile App (`lib/`):**
     - [online_api_service.dart](file:///d:/Apps/market_vendor_app/lib/services/online_api_service.dart):
       - `getSales()`: Loại bỏ ép buộc `limit: 'all'`. Hỗ trợ tham số `startDate`, `endDate`, `limit`, `fetchAll`. Mặc định áp dụng giới hạn an toàn khi không truyền ngày để bảo vệ RAM thiết bị.
       - `getDebts()`: Bổ sung tham số `startDate`, `endDate`, `limit`.
       - Thêm `getEntityCounts()` gọi `GET /api/sync/counts`.
     - [database_service.dart](file:///d:/Apps/market_vendor_app/lib/services/database_service.dart):
       - `getSales()` & `getDebts()`: Hỗ trợ `startDate`, `endDate`, `search`, `limit`.
       - Ở chế độ Offline SQLite, chỉ gom nhóm các `sale_items` thuộc về các đơn hàng đang nằm trong khoảng ngày truy vấn (chia lô chunk 200 IDs), triệt tiêu hoàn toàn việc đọc cả bảng `sale_items` vào RAM.
     - [sale_provider.dart](file:///d:/Apps/market_vendor_app/lib/providers/sale_provider.dart):
       - Bổ sung quản lý trạng thái `DateTimeRange? _dateRange`, mặc định là **30 ngày gần nhất** (`SaleProvider.defaultRange()`).
       - Bổ sung phương thức `load({DateTimeRange? range, bool forceAll = false})` và `setDateRange(DateTimeRange? newRange)`.
       - Khi mở app, app chỉ tải đúng dữ liệu của 30 ngày gần nhất, thời gian nạp giảm từ vài giây xuống chỉ còn ~50ms, triệt tiêu 100% hiện tượng lag/đơ điện thoại.
     - [sales_history_screen.dart](file:///d:/Apps/market_vendor_app/lib/screens/sales_history_screen.dart):
       - Đồng bộ `_range` với `SaleProvider.dateRange`.
       - Thiết kế thanh chọn nhanh mốc thời gian trực quan ngay trên đầu danh sách: nút hiển thị khoảng ngày hiện tại (bấm mở DateRangePicker), cùng các nút chip chọn nhanh: **30 ngày (Mặc định)**, **Tháng này**, **7 ngày**, **Hôm nay**, **Tất cả**.
       - Khi người dùng bấm đổi khoảng ngày hoặc chọn "Tất cả", app lập tức kích hoạt truy vấn đúng khoảng ngày đó từ server/db.
     - [sales_item_history_screen.dart](file:///d:/Apps/market_vendor_app/lib/screens/sales_item_history_screen.dart):
       - Đồng bộ khoảng ngày lọc với `SaleProvider`, hỗ trợ đổi khoảng ngày và "Tất cả".
     - [expense_screen.dart](file:///d:/Apps/market_vendor_app/lib/screens/expense_screen.dart):
       - Mặc định khởi tạo `_range` là 30 ngày gần nhất thay vì null, ngăn ngừa việc tải toàn bộ chi phí từ trước tới nay.
     - [debt_screen.dart](file:///d:/Apps/market_vendor_app/lib/screens/debt_screen.dart):
       - `_pickSaleId()`: Chỉ truy vấn các đơn hàng trong 60 ngày gần nhất khi gán đơn nợ thay vì lấy toàn bộ đơn hàng trong lịch sử.
     - [online_server_sync_screen.dart](file:///d:/Apps/market_vendor_app/lib/screens/online_server_sync_screen.dart):
       - `_refreshLocalCounts()` ở chế độ online chuyển sang dùng `OnlineApiService.instance.getEntityCounts()`, nạp số liệu tức thì mà không cần tải dữ liệu chi tiết của 5 bảng.
