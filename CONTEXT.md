# CONTEXT.md — Market Vendor App

## Tổng quan
Ứng dụng Flutter quản lý bán hàng, ghi nợ cho tiểu thương. Hoạt động offline, hỗ trợ đồng bộ Google Drive.

## Trạng thái hiện tại (2026-04-12)

### Tính năng AI đã triển khai

**1. Multi-provider AI Service** (`lib/services/ai_provider_service.dart`)
- Singleton `AiProviderService` quản lý config qua `SharedPreferences`
- Hỗ trợ 2 provider: **OpenRouter** và **Google Gemini**
- SharedPreferences keys: `ai_provider`, `ai_model`, `ai_api_key_openrouter`, `ai_api_key_google`
- Mặc định: **Google Gemini / `models/gemma-4-31b-it`**
- Fallback OpenRouter key đã xoá (rỗng) — người dùng phải tự nhập key
- Xử lý thinking model (Gemma-4): skip `parts` có `"thought": true`, lấy part cuối không phải thought
- `sendChatCompletion(prompt)` — gọi API đúng provider đang chọn
- `fetchModels(provider)` — fetch danh sách model từ API

**2. AI Provider Settings UI** (`lib/screens/ai_provider_settings_screen.dart`)
- SegmentedButton chọn provider
- Dropdown model (fetch từ API) + FilterChip "Nhập model tuỳ chỉnh"
- TextField API key cho Google và OpenRouter (obscure + toggle)
- Card tóm tắt cấu hình hiện tại
- Entry point: thẻ "Chọn AI" trong grid "Tính năng nhanh" của `settings_screen.dart`

**3. Lên đơn bằng giọng nói** (`lib/screens/voice_order_screen.dart`)
- `_processWithAI()` dùng `AiProviderService` (không còn hardcode key/model)
- Product picker bottomsheet hỗ trợ tìm kiếm tiếng Việt không dấu (`TextNormalizer.normalize()`)

**4. Thêm sản phẩm bằng giọng nói** (`lib/widgets/voice_product_input_dialog.dart`)
- Widget dialog dùng chung, gọi qua `VoiceProductInputDialog.show(context)`
- UI: Nút Record + Ô text editable + Switch Auto/Manual + Nút "Xử lý AI"
- Dùng `speech_to_text` (vi_VN) + `AiProviderService.sendChatCompletion()`
- AI parse → JSON schema: `{name, price, costPrice, unit, currentStock, barcode}`
- Trả `VoiceProductResult` → tự điền form thêm sản phẩm
- Auto mode lưu `SharedPreferences` key `voice_product_auto_send`
- Tích hợp nút 🎤 vào dialog "Thêm sản phẩm" tại 3 màn hình:
  - `voice_order_screen.dart` — `_addQuickProductDialog()`
  - `sale_screen.dart` — `_addQuickProductDialog()`
  - `product_list_screen.dart` — `_showProductDialog()` (chỉ khi thêm mới)

### Cấu trúc thư mục chính
```
lib/
├── main.dart
├── app_init.dart
├── models/          # Customer, Product, Sale, Debt ...
├── providers/       # State management (Provider pattern)
├── screens/
│   ├── ai_provider_settings_screen.dart
│   ├── product_list_screen.dart
│   ├── sale_screen.dart
│   ├── settings_screen.dart
│   ├── voice_order_screen.dart
│   └── ...
├── services/
│   ├── ai_provider_service.dart
│   ├── database_service.dart
│   ├── drive_sync_service.dart
│   ├── product_image_service.dart
│   └── ...
├── theme/
├── utils/
│   ├── text_normalizer.dart   # Bỏ dấu tiếng Việt (dùng cho search)
│   ├── string_utils.dart      # Normalize cho AI matching
│   ├── number_input_formatter.dart
│   ├── contact_serializer.dart
│   └── ...
└── widgets/
    └── voice_product_input_dialog.dart
```

### Dependencies quan trọng (Mobile)
- `flutter` SDK ^3.7.2
- `provider` ^6.1.1 (state management)
- `sqflite` (local database)
- `http` ^1.2.2 (HTTP calls)
- `shared_preferences` ^2.2.2 (local config)
- `speech_to_text` ^7.3.0 (nhận dạng giọng nói)
- `firebase_core`, `firebase_auth`, `cloud_firestore` (đăng nhập, sync)
- `image_picker` (chụp/chọn ảnh sản phẩm)
- `intl` (format số, ngày)

### Nâng cấp giao diện hóa đơn & Chia sẻ (2026-05-10)
- **lib/screens/receipt_preview_screen.dart**:
  - Khắc phục lỗi bố cục bị bóp méo trên màn hình bằng `InteractiveViewer(constrained: false)`.
  - Khắc phục lỗi chia sẻ ảnh (PNG) bị cắt thiếu khi hóa đơn dài bằng `screenshotController.captureFromWidget()`.
  - Thiết kế lại file PDF chia sẻ chuẩn chuyên nghiệp sử dụng thư viện `pdf`.
  - Cải tiến typography và layout cho các khổ in nhiệt hiển thị đẹp mắt, chuyên nghiệp hơn.
  - Rút gọn mã đơn hàng hiển thị (12 ký tự) trên giao diện nhưng giữ nguyên mã trong QR.
  - Sửa lỗi share PNG bị bóp chiều ngang và mất nội dung bằng cách đẩy widget Screenshot vào trong InteractiveViewer.

### Sửa lỗi Google Play Store 16KB Page Size (2026-05-10) - Giải pháp triệt để
- **Flutter SDK**: Nâng cấp lên phiên bản **3.41.9 (Stable)** để đảm bảo engine hỗ trợ 16KB page size.
- **Android Toolchain**: 
  - Cài đặt và sử dụng **Android NDK r28 (28.2.13676358)**.
  - Cập nhật **android/app/build.gradle.kts**:
    - Thiết lập `ndkVersion = "28.2.13676358"`.
    - Cấu hình `packaging { jniLibs { useLegacyPackaging = false } }` để căn lề thư viện native đúng chuẩn 16KB trong AAB.
    - Tăng `minSdk = 23` (yêu cầu bởi các bản Firebase mới).
- **Dependencies**:
  - Nâng cấp bộ **Firebase** (`firebase_core`, `firebase_auth`, `cloud_firestore`) lên bản mới nhất hỗ trợ 16KB.
  - Pin (giữ nguyên) các package khác như `google_sign_in`, `fl_chart`, `flutter_contacts`, `file_picker` ở các phiên bản ổn định để tránh lỗi biên dịch do thay đổi API, nhưng vẫn hưởng lợi từ việc đóng gói (packaging) 16KB của Gradle 8.7+.
- **Build**: Đã tạo thành công file `app-release.aab` sạch, hỗ trợ Android 15+.
- **Lưu ý**: Gỡ bỏ hoàn toàn các workaround cũ như `extractNativeLibs="true"` vì không còn được Play Store chấp nhận cho API 35+.

## Trạng thái Web Migration (2026-06-25)

### Sửa lỗi & cải tiến Web (2026-06-25)
- **Dialog/Modal căn giữa**: Tạo component `Modal` dùng React Portal (`document.body`) — khắc phục dialog bị đẩy lên cao/che khuất do render trong container scroll của layout dashboard.
- **POS (`/pos`)**: Hiển thị ô **Số tiền khách trả** trực tiếp trên giỏ hàng (mặc định = tổng đơn), nút nhanh **Nợ tất / Trả hết**, tự động ghi công nợ khi trả thiếu. Preview **VietQR** khi chọn Chuyển khoản.
- **Nhập hàng (`/purchases`)**: Mặc định số tiền đã trả = tổng đơn, nút **Nợ tất / Trả hết**, tự động ghi nợ nhà cung cấp.
- **Sản phẩm (`/products`)**: Sửa lỗi không nhập được giá vốn (binding sai `price`). Dropdown đơn vị tính với localStorage lưu đơn vị gần nhất + tùy chọn thêm đơn vị mới.
- **VietQR**: Thư viện `lib/vietqr.ts` + component `VietQrDisplay`. Cài đặt hiển thị QR preview (có mã BIN ngân hàng). Lịch sử bán hiển thị QR thu nợ/chuyển khoản.
- **Seed data**: Script `backend-api/prisma/seed.ts` — tài khoản `demo@marketvendor.com` / `demo123456`, 20 SP, 8 KH, 4 NCC, ~102 đơn bán, 15 đơn nhập, 30 chi phí.

### 1. Backend API (`backend-api/`)
- Kiến trúc Node.js + Express + TypeScript + Prisma ORM.
- Database: PostgreSQL `market_vendor_web` (localhost:3005).
- Tách biệt hoàn toàn với `backend-node` cũ. Schema khớp 100% với SQLite v33 của mobile.
- API Endpoints đã hoàn thiện:
  - Auth (`/auth/register`, `/auth/login`, `/auth/me`, `/auth/google`) hỗ trợ Email/Password, Google OAuth thực tế và Mock Google Login cho môi trường phát triển local (đã sửa lỗi Unique constraint failed khi trùng email).
  - CRUD sản phẩm, khách hàng, đơn hàng, công nợ, chi phí, báo cáo dashboard.
  - Tự động hóa logic kho hàng (trừ thô/phối trộn) và tự động ghi nợ khi thanh toán thiếu.
  - **Đồng bộ dữ liệu (`/api/sync/push`, `/api/sync/pull`)**: Triển khai giải pháp đồng bộ 2 chiều (LWW - Last-Write-Wins) bằng Prisma, hỗ trợ lưu trữ lịch sử sự kiện đồng bộ (`sync_events`) và xử lý xung đột dữ liệu tối ưu giữa di động và máy chủ web.

### 2. Web App Next.js (`web-app/`)
- Thiết kế bằng Next.js 16 (App Router), React 19, TypeScript và CSS Variables (tối ưu hóa HSL Dark/Light theme, glassmorphism, micro-animations).
- Trang đã triển khai & tối ưu hóa compile:
  - **Landing Page (`/`)**: Trình diễn tính năng chuyên nghiệp, bảng giá gói dịch vụ, kêu gọi hành động.
  - **Auth (`/login`)**: Tích hợp Login/Register với trạng thái lưu token qua LocalStorage, bảo mật bằng Suspense boundary cho pre-render. Tích hợp Google Sign-In thực tế (Google Identity Services) hiển thị popup chọn tài khoản Google của thiết bị.
  - **Dashboard layout & Home (`/dashboard`)**: Sidebar/Header responsive, hiển thị các chỉ số KPIs (Doanh thu, số đơn, chi phí, nợ khách hàng) cùng bảng giao dịch gần đây.
  - **POS Bán hàng (`/pos`)**: Thao tác tạo đơn, chọn khách hàng, giảm giá trực tiếp, tính toán và in hóa đơn/ghi nợ tự động. Tích hợp thêm nút **🎤 Lên đơn AI** mở modal Lên đơn hàng bằng giọng nói.
  - **Lên đơn bằng giọng nói (`VoiceOrderModal`)**: Sử dụng Web Speech API để nhận diện giọng nói tiếng Việt trực tiếp trên trình duyệt, kết nối Client-side AI parser với API Gemini/OpenRouter của người dùng để phân tích cú pháp đơn hàng JSON và tự động map sản phẩm/khách hàng vào giỏ hàng POS.
  - **Quản lý sản phẩm (`/products`)**: CRUD đầy đủ phân loại RAW/MIX, giá vốn, giá bán, số lượng tồn kho.
  - **Khách hàng (`/customers`)**: Danh bạ đối tác lọc riêng Khách hàng & Nhà cung cấp.
  - **Lịch sử bán hàng (`/sales`)**: Chi tiết hóa đơn và hủy/hoàn trả đơn hàng.
  - **Sổ ghi nợ (`/debts`)**: Quản lý thu nợ (khách nợ) và trả nợ (nợ nhà cung cấp).
  - **Chi phí (`/expenses`)**: Ghi chép và lọc các loại chi phí hoạt động.
  - **Báo cáo (`/reports`)**: Biểu đồ doanh thu/lợi nhuận động theo Tuần/Tháng/Năm, danh sách mặt hàng bán chạy. Bổ sung tính năng **Xuất báo cáo Excel (CSV)** chi tiết.
  - **Cài đặt (`/settings`)**: Thiết lập thông tin cửa hàng, tài khoản ngân hàng VietQR, quản lý tài khoản nhân viên (kết nối trực tiếp API backend). Thêm tab **Cấu hình AI** để quản lý API key và model của người dùng.
- **PWA & Offline**: Tích hợp Service Worker (`sw.js`) và Manifest (`manifest.ts`) cho phép ứng dụng Next.js hoạt động offline và hiển thị giao diện POS ngay cả khi mất mạng.
- Biên dịch: Build tĩnh Next.js hoạt động hoàn hảo 100% không có lỗi type-checking.

### 3. Đồng bộ hóa toàn diện Web ↔ Mobile (Phase 6 - ĐÃ HOÀN THÀNH)
- **API Backend**: Nâng cấp các API backend cho Báo cáo (Reports) & Dashboard để hỗ trợ lọc theo nhân viên (`employeeId`), tính toán đầy đủ 14 KPIs thực tế, `/top-products`, `/expenses-ratio` (tỉ trọng chi phí), và gom nhóm doanh thu theo ngày/tháng/năm tại `/revenue`. Bổ sung endpoint `/opening-stocks` để lấy dữ liệu tồn đầu kỳ.
- **Logic POS Bán hàng**: Đồng bộ logic công nợ (chặn nợ Khách vãng lai, gán nhanh số tiền khách trả, dropdown chọn nhân viên bán hàng) và sinh VietQR tự động khi thanh toán BANK thành công. Tích hợp cảnh báo tồn kho (cho phép cập nhật nhanh) và cảnh báo bán dưới giá RAW của MIX.
- **Reports & Dashboard**:
  - Dashboard Web loại bỏ mock data, tự động truyền date hôm nay và tính toán động tổng tiền hóa đơn từ order items.
  - Trang Báo cáo (Reports) Web hiển thị đủ 14 KPIs thực tế, bộ lọc Date Range và nhân viên, vẽ Pie Chart SVG tỷ trọng chi phí tương tác, vẽ Bar/Line Chart SVG doanh thu/lợi nhuận/lợi nhuận ròng có hover tooltip, danh sách Top 10 sản phẩm có progress bar tỉ lệ.
  - Tích hợp tính năng **Xuất báo cáo Excel tổng hợp (12 Sheet XML Spreadsheet)** client-side tải xuống dữ liệu đầy đủ (khách hàng, sản phẩm, công nợ, lịch sử trả nợ, chi phí, lịch sử nhập kho, lịch sử xuất kho, list đơn hàng, tồn đầu kỳ, tồn cuối kỳ...) khớp 100% với mobile app.
