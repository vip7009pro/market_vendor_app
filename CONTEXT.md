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
- **PWA & Offline**: Tích hợp Service Worker (`sw.js`) và Manifest (`manifest.ts`) cho phép ứng dụng Next.js hoạt động offline và hiển thị giao diện POS ngay cả khi mất mạng. Cấu hình loại trừ các yêu cầu không thuộc HTTP/HTTPS (như `chrome-extension://` từ các tiện ích Chrome) để tránh lỗi vòng lặp Cache Storage unsupport.
- Biên dịch: Build tĩnh Next.js hoạt động hoàn hảo 100% không có lỗi type-checking.

### 3. Đồng bộ hóa toàn diện Web ↔ Mobile (Phase 6 - ĐÃ HOÀN THÀNH)
- **API Backend**: Nâng cấp các API backend cho Báo cáo (Reports) & Dashboard để hỗ trợ lọc theo nhân viên (`employeeId`), tính toán đầy đủ 14 KPIs thực tế, `/top-products`, `/expenses-ratio` (tỉ trọng chi phí), và gom nhóm doanh thu theo ngày/tháng/năm tại `/revenue`. Bổ sung endpoint `/opening-stocks` để lấy dữ liệu tồn đầu kỳ.
- **Logic POS Bán hàng**: Đồng bộ logic công nợ (chặn nợ Khách vãng lai, gán nhanh số tiền khách trả, dropdown chọn nhân viên bán hàng) và sinh VietQR tự động khi thanh toán BANK thành công. Tích hợp cảnh báo tồn kho (cho phép cập nhật nhanh) và cảnh báo bán dưới giá RAW của MIX.
- **Reports & Dashboard**:
  - Dashboard Web loại bỏ mock data, tự động truyền date hôm nay và tính toán động tổng tiền hóa đơn từ order items.
  - Trang Báo cáo (Reports) Web hiển thị đủ 14 KPIs thực tế, bộ lọc Date Range và nhân viên, vẽ Pie Chart SVG tỷ trọng chi phí tương tác, vẽ Bar/Line Chart SVG doanh thu/lợi nhuận/lợi nhuận ròng có hover tooltip, danh sách Top 10 sản phẩm có progress bar tỉ lệ.
  - Tích hợp tính năng **Xuất báo cáo Excel tổng hợp (12 Sheet XML Spreadsheet)** client-side tải xuống dữ liệu đầy đủ (khách hàng, sản phẩm, công nợ, lịch sử trả nợ, chi phí, lịch sử nhập kho, lịch sử xuất kho, list đơn hàng, tồn đầu kỳ, tồn cuối kỳ...) khớp 100% với mobile app.

### 4. Tìm kiếm Tiếng Việt, Quản lý Tồn kho & Chi tiết Báo cáo (Phase 7 - ĐÃ HOÀN THÀNH)
- **Chuẩn hóa tìm kiếm Tiếng Việt (Vietnamese diacritics search)**:
  - Tạo tiện ích `web-app/src/lib/text.ts` hỗ trợ loại bỏ dấu Tiếng Việt, so khớp chữ cái đầu (`getInitials`) phục vụ tìm kiếm nhanh (giống trên Flutter mobile).
  - Tích hợp hàm `matchVietnamese` vào ô tìm kiếm ở tất cả màn hình: POS, Lịch sử bán hàng, Lịch sử nhập hàng, Sản phẩm, Khách hàng, Công nợ, Chi phí và ô tìm kiếm sản phẩm trong dialog.
- **Giao diện POS**: Điều chỉnh grid danh sách sản phẩm thành 4 cột trên desktop để hiển thị trực quan hơn.
- **Sản phẩm & Quản lý Kho**:
  - Tách trang Sản phẩm làm 3 sub-tabs: Tồn kho, Lịch sử nhập kho, Lịch sử xuất kho RAW.
  - Hàng MIX không hiển thị số lượng tồn kho (hiển thị `—`) vì không quản lý tồn trực tiếp (tất cả quy về nguyên liệu thô RAW).
  - Tab nhập kho hiển thị chi tiết lịch sử mua hàng, tab xuất kho RAW hiển thị lịch sử xuất bán (bao gồm cả phân rã nguyên liệu cấu thành món MIX).
  - Tích hợp các widget tính tổng số lượng, tổng tiền/giá vốn/thành tiền thay đổi động theo bộ lọc thời gian & sản phẩm.
  - Bổ sung nút **"Cập nhật tồn đầu kỳ"** mở modal cho phép chọn Tháng-Năm để nhập số dư tồn đầu kỳ (tồn đầu tháng) cho sản phẩm (upsert qua composite key `userId_productId_year_month`).
- **Nâng cấp Báo cáo (Reports)**:
  - Bổ sung thêm 4 chỉ số KPIs tồn kho (Tồn đầu kỳ, Nhập trong kỳ, Xuất trong kỳ, Tồn cuối kỳ) nâng tổng số KPIs lên **18**.
  - Bổ sung section mới "Dòng tiền thực thu trong kỳ (Tiền thực tế nhận & Thu nợ)" chứa 3 widgets: Tổng thực thu, Thu TM, Thu CK. Dữ liệu tính toán từ các luồng thanh toán thực tế (checkout + thu nợ khách hàng) phát sinh trong khoảng ngày lọc.
  - Tích hợp modal xem chi tiết giao dịch gốc (**Backdata Grid**) cho cả 18 KPIs + 3 widgets thực thu mới (hỗ trợ kind `total_paid`). Sửa logic backdata cash/bank để lọc đúng luồng nợ khách hàng (d.type = 1).
  - Tối ưu hóa Pie Chart chi phí (tăng size vòng tròn lên `w-56`, căn giữa và xếp danh mục chú thích legends xuống dưới dạng grid 2 cột gọn gàng).
  - Tách biệt luồng fetch dữ liệu biểu đồ và KPIs chính, loại bỏ hoàn toàn hiện tượng trắng trang giật nhấp nháy khi thay đổi bộ lọc biểu đồ Doanh thu (Day/Month/Year).
- **Tối ưu hóa UI/UX toàn hệ thống**:
  - Khắc phục lỗi icon kính lúp che đè chữ nhập bằng cách ghi đè `.input.pl-10` trong CSS.
  - Sửa lỗi select dropdown bị che mất chữ sau khi chọn bằng cách reset padding đứng nhỏ hơn (`0.375rem`), ẩn arrow mặc định (`appearance: none`) và thiết lập arrow SVG tùy chỉnh mượt mà.
  - Thiết lập chiều cao linh hoạt tự co giãn theo viewport cho các bảng MUI DataGrid (dính xuống bottom trên desktop: `calc(100vh - ...px)`) và các trang sử dụng `MasterDetailLayout` (Sales, Purchases, Debts) có chiều cao dynamic 100% độc lập scrolling.

### 5. Danh bạ máy & Chia sẻ hóa đơn trên Web di động (Phase 8 - ĐÃ HOÀN THÀNH)
- **Truy cập Danh bạ di động**:
  - Sử dụng Contact Picker API (`navigator.contacts.select`) để thêm nhanh khách hàng bằng cách chọn từ danh bạ gốc của điện thoại trong modal thêm đối tác tại `/customers`.
  - Tích hợp hàm chuẩn hóa số điện thoại tự động chuyển đổi mã vùng quốc gia `+84` / `84` thành `0` và loại bỏ ký tự đặc biệt.
- **Chia sẻ hóa đơn di động (PNG)**:
  - Viết module `web-app/src/lib/receiptShare.ts` vẽ hóa đơn trực tiếp lên HTML5 Canvas với font monospace `Courier New` phong cách máy in nhiệt cao cấp, tính toán chiều cao hóa đơn tự động.
  - Sử dụng Web Share API (`navigator.share`) chia sẻ file ảnh PNG trực tiếp đến các ứng dụng mạng xã hội (Zalo, Messenger, Telegram...).
  - Tích hợp fallback tự động tải ảnh xuống nếu trình duyệt không hỗ trợ Web Share API (ví dụ trên desktop).
  - Tích hợp nút **"📱 Chia sẻ ảnh HĐ"** tại modal thanh toán thành công của POS (`/pos`) và màn hình chi tiết đơn hàng lịch sử bán (`/sales`).
- **Hỗ trợ truy cập mạng nội bộ LAN (`192.168.1.136`) & Tên miền custom (`cmsvina4285.com:3001`)**:
  - Cấu hình `allowedDevOrigins` trong [next.config.ts](file:///g:/NODEJS/market_vendor_app/web-app/next.config.ts) để cho phép kết nối Webpack HMR WebSocket trên trình duyệt di động qua mạng nội bộ hoặc qua tên miền custom mà không bị chặn bảo mật cross-origin.
  - Tự động hóa việc phân giải URL API thông qua hàm `getApiUrl()` trong [api.ts](file:///g:/NODEJS/market_vendor_app/web-app/src/lib/api.ts) để phát hiện hostname và giao thức (HTTP/HTTPS) động tại thời điểm chạy (client-side), tránh lỗi Mixed Content và chuyển hướng cuộc gọi chính xác sang IP hoặc tên miền custom trên cổng `3007`.
  - Thêm tên miền `cmsvina4285.com` và các cổng tương ứng (cả giao thức `http://` và `https://`) vào danh sách CORS allowed origins trong [index.ts](file:///g:/NODEJS/market_vendor_app/backend-api/src/index.ts).
- **Cấu hình HTTPS/SSL local cho dev & production**:
  - Thêm script `"dev:ssl"` vào [package.json](file:///g:/NODEJS/market_vendor_app/web-app/package.json) để chạy server Next.js dev qua giao thức HTTPS sử dụng các file chứng chỉ SSL trong thư mục `ssl/`.
  - Tích hợp module `https` và `fs` trong [index.ts](file:///g:/NODEJS/market_vendor_app/backend-api/src/index.ts) để tự động khởi chạy server backend dạng HTTPS bảo mật khi phát hiện cấu hình đường dẫn tệp tin chứng chỉ trong `.env`, tự động fallback về server HTTP thông thường nếu cấu hình rỗng hoặc thiếu file.
  - Bảo mật bằng cách bỏ qua thư mục `ssl/` và các đuôi tệp tin khóa `.key`, `.crt`, `.pem` trong file [.gitignore](file:///g:/NODEJS/market_vendor_app/.gitignore) gốc.
- **Tối ưu hóa giao diện POS (Khử nháy & Debounce QR)**:
  - Loại bỏ double re-rendering bằng cách tính toán đồng thì `effectivePaidAmount` tại thời điểm render thay vì dùng `useEffect` bất đồng bộ để cập nhật `paidAmount`.
  - Tích hợp cơ chế trễ (debounce) 400ms khi sinh mã QR VietQR preview, ngăn chặn việc tải lại ảnh liên tục từ API bên ngoài khi người dùng click thay đổi số lượng giỏ hàng nhanh chóng, giúp giao diện POS hoàn toàn mượt mà.
- **Bảo mật Cấu hình AI API Key & Đổ Model Động**:
  - Di chuyển việc lưu trữ API key (Google Gemini, OpenRouter) và Provider đang hoạt động lên cơ sở dữ liệu PostgreSQL (lưu tập trung bảo mật vào bảng `sync_state`), đồng bộ qua API của backend tại `/api/settings/ai`.
  - Hỗ trợ tự động gọi API chính thức của Google Gemini và OpenRouter để lấy danh sách models khả dụng ngay khi có API Key hợp lệ, đổ trực tiếp vào dropdown cho người dùng lựa chọn thay vì danh sách hardcode tĩnh.
  - Lưu trữ model đã chọn vào `localStorage` của trình duyệt để giữ cấu hình hiển thị riêng biệt và linh hoạt cho từng loại thiết bị. Giao diện Voice POS tự động nạp cấu hình khóa từ DB trước khi chạy phân tích giọng nói.

### 6. Chỉnh sửa Đơn hàng, Chứng từ Đính kèm & Nâng cao UI/UX (Phase 9 - ĐÃ HOÀN THÀNH)
- **Chuẩn hóa Autocomplete & Chọn nhanh từ danh bạ**:
  - Tích hợp ô tìm kiếm Autocomplete tùy chỉnh dạng dropdown mượt mà thay thế hoàn toàn cho thẻ `<select>` mặc định tại POS (`/pos`) và Nhập hàng (`/purchases`), hỗ trợ tìm kiếm Tiếng Việt không dấu và số điện thoại.
  - Tích hợp nút **"Chọn từ danh bạ"** di động (W3C Contact Picker API) tại dialog thêm nhanh khách hàng POS và Nhà cung cấp ở trang Nhập hàng.
- **Tải lên & Quản lý chứng từ đính kèm (PDF/Ảnh)**:
  - Tạo route `POST /api/upload` hỗ trợ chuyển đổi tệp tin Base64 thành luồng Buffer và lưu file vật lý vào thư mục `/uploads`.
  - Phục vụ static file uploads qua backend API.
  - Tích hợp tính năng tải lên chứng từ đính kèm cho Đơn nhập hàng (`/purchases`) và Chi phí hoạt động (`/expenses`) hiển thị trực quan liên kết xem tệp tin/chứng từ gốc.
- **Chỉnh sửa & Xóa Chi phí hoạt động**:
  - Hỗ trợ thao tác cập nhật (Edit) và xóa bỏ (Delete) chi phí hoạt động trực tiếp trên giao diện DataGrid thông qua nút hành động, đồng bộ API.
- **Cân đối Tồn kho & Công nợ tự động**:
  - Cập nhật backend routes `PUT /api/sales/:id` và `PUT /api/purchases/orders/:id` tự động hoàn trả số dư tồn kho cũ, áp dụng lượng mới (phân rã cả nguyên liệu thô RAW cấu thành sản phẩm MIX đối với đơn bán hàng) và tự cân đối, chỉnh sửa hoặc xóa hóa đơn công nợ liên quan của khách hàng/nhà cung cấp.
  - Thiết kế hộp thoại Chỉnh sửa Đơn bán hàng và Đơn nhập hàng trực quan đầy đủ trên frontend Web.
- **Hiển thị giao dịch gốc trong Sổ ghi nợ**:
  - Khi click chọn khoản nợ bất kỳ, Web-app tự động tải thông tin hóa đơn bán hàng (`Sale`) hoặc hóa đơn nhập kho (`PurchaseOrder`) liên kết, hiển thị chi tiết danh sách mặt hàng, số lượng và tổng tiền của đơn hàng đó ngay trên bảng lịch sử trả nợ.
- **Tối ưu hóa hóa đơn chia sẻ (PNG)**:
  - Nâng cấp hệ số tỷ lệ Canvas lên `3` (scale x3) giúp hóa đơn PNG tải về hoặc chia sẻ qua Zalo/Messenger đạt độ sắc nét tuyệt đối, không còn bị mờ nhòe font chữ in nhiệt trên di động.

### 7. Giao diện Di động Nâng cao & Đa Giao diện (Themes) (Phase 10 - ĐÃ HOÀN THÀNH)
- **Thanh điều hướng dưới (Bottom Navigation Bar) & Nút tiện ích Header di động**:
  - Thiết kế và đưa vào sử dụng thanh điều hướng cố định phía dưới màn hình trên giao diện di động (`fixed bottom-0 left-0 right-0 z-50`), hỗ trợ cuộn vuốt ngang mượt mà (`overflow-x-auto whitespace-nowrap scrollbar-none snap-x`) để hiển thị đầy đủ 10 mục của menu hệ thống.
  - Loại bỏ nút hamburger menu co rút và menu dropdown che đè giao diện trước đây giúp việc thao tác bằng một tay trên điện thoại thuận tiện hơn.
  - Bổ sung 2 nút biểu tượng tắt nhanh dạng tròn gọn gàng ngay trên **Mobile Headerbar**: Nút Tạo đơn mới (🛒) sử dụng gradient màu của theme, và nút Đăng xuất (🚪) viền màu nổi bật, giải quyết triệt để vấn đề thiếu hụt nút đăng xuất/tạo đơn khi chạy trên màn hình điện thoại.
  - Đồng thời thu gọn kích thước nút "Tạo đơn mới" và "Đăng xuất" trên **Desktop Headerbar** về dạng biểu tượng (icon buttons) gọn gàng có chú thích (tooltips), tối giản hóa diện tích tiêu đề trên máy tính.
  - Điều chỉnh khoảng đệm chân trang (`pb-24`) cho container hiển thị nội dung chính trên thiết bị di động để tránh bị thanh điều hướng dưới che lấp dữ liệu.
- **Tối ưu hóa giao diện POS di động**:
  - Ẩn danh sách sản phẩm dạng lưới cồng kềnh trên màn hình di động, mở rộng 100% diện tích màn hình để tập trung hoàn toàn vào hiển thị Giỏ hàng và thông tin thanh toán.
  - Chuyển đổi cơ chế chọn Khách hàng, Nhân viên bán hàng và nút Thêm sản phẩm sang các hộp thoại (Modal/Dialog) chọn nhanh dạng danh sách trực quan, hỗ trợ tìm kiếm theo tiếng Việt chuẩn hóa và nút "Thêm nhanh" đối tác/sản phẩm mới trực tiếp.
  - Phóng to cỡ chữ tên mặt hàng (`text-sm font-bold`) và nâng kích thước các nút cộng/trừ số lượng (`w-9 h-9`) để thao tác ngón tay chính xác hơn, không bị bấm nhầm.
- **Tính năng thay đổi Giao diện đa sắc màu (Themes)**:
  - Thiết kế và hỗ trợ 9 bộ biến số màu sắc CSS chủ đạo gồm 4 theme sáng có độ tương phản cao (Hồng mộng mơ, Gió mùa xuân, Bầu trời xanh, Sương sớm) và 5 theme tối (Midnight, Thiên nhiên, Biển xanh, Hoàng hôn, Lavender).
  - Thêm tab "Giao diện" trong trang Cài đặt (`/settings`) hiển thị các thẻ màu xem trước trực quan giúp người dùng nhấp chọn thay đổi màu sắc ngay lập tức mà không cần tải lại trang.
  - Nhúng đoạn mã script nhỏ đồng thì tại thẻ `<head>` của `layout.tsx` để đọc `localStorage` và gán class theme trên tag `<html>` trước khi trình duyệt vẽ giao diện (avoid FOUC), triệt tiêu hoàn toàn hiện tượng nháy màu khó chịu khi chuyển tiếp trang.
  - Bổ sung quy tắc ghi đè thông minh trong [globals.css](file:///g:/NODEJS/market_vendor_app/web-app/src/app/globals.css) tự động chuyển đổi các màu nền/màu chữ/đường viền hardcoded của Tailwind (ví dụ `bg-slate-900`, `bg-[#0f172a]`, `border-white/5`...) sang màu sắc tương ứng của theme hiện tại.
  - Đồng bộ hóa toàn diện màu nền và độ tương phản của bảng dữ liệu DataGrid trong [AppDataGrid.tsx](file:///g:/NODEJS/market_vendor_app/web-app/src/components/ui/AppDataGrid.tsx) theo biến CSS (nền header, nền grid, dòng cuộn, màu chữ và phân trang), đảm bảo chữ viết luôn hiển thị sắc nét có độ tương phản cao dễ đọc trên cả theme sáng lẫn theme tối.
  - Chuẩn hóa thiết kế cho tất cả các hộp tìm kiếm Autocomplete/Dropdown tùy chỉnh trong ứng dụng: Thêm khoảng đệm bao quanh (`p-1.5`) cho container ngoài, loại bỏ hoàn toàn bo góc ở danh sách item bên trong (để phẳng/sharp), và tăng kích thước phông chữ lên `text-sm sm:text-base` giúp đọc thông tin dễ dàng hơn và tránh bị lẹm viền ngoài.
  - Đồng thời, loại bỏ hoàn toàn bo góc (để phẳng/sharp) và tăng cỡ chữ cho tất cả các danh sách/bảng phần tử quan trọng:
    - Danh sách sản phẩm được chọn thêm trong giỏ hàng POS (các card sản phẩm bỏ bo góc, tăng cỡ tên mặt hàng lên `text-base` và giá tiền lên `text-sm`, bỏ bo góc các nút tăng/giảm và nút xóa).
    - Hộp thoại chọn Khách hàng, chọn Nhân viên và chọn Sản phẩm trên giao diện di động (bỏ bo góc các khung danh sách cuộn, chuyển cỡ chữ tên khách/nhân viên lên `text-sm sm:text-base` rõ nét).
    - Bảng sản phẩm được thêm trong dialog Nhập hàng (chuyển sang phông chữ lớn `text-sm` cho toàn bảng, bỏ bo góc các nút cộng/trừ số lượng và ô nhập liệu).


