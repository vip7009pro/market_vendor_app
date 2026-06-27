# ROADMAP.md — Kế hoạch di chuyển sang Web App

Tài liệu này theo dõi tiến độ các phase của dự án chuyển đổi từ mobile app sang Web App (Next.js 16 + Node.js API + PostgreSQL).

---

## 🚀 Bản Đồ Đường Đi (Roadmap)

### 📌 PHASE 1: Nền tảng (Foundation) - ĐÃ HOÀN THÀNH
- [x] **1.1 Cơ sở dữ liệu & Prisma Schema**
  - [x] Tạo DB PostgreSQL mới `market_vendor_web`
  - [x] Tạo `schema.prisma` khớp 100% SQLite v33 của mobile (20 bảng)
- [x] **1.2 Backend API cơ bản**
  - [x] Khởi tạo dự án Node.js + TypeScript
  - [x] Cơ chế mã hóa JWT và xác thực
  - [x] Thực tế hóa chức năng Đăng ký/Đăng nhập Google (Google Identity Services) và mock local
- [x] **1.3 Cài đặt Web App Next.js 16**
  - [x] Khởi tạo Next.js 16 App Router + React 19 + TypeScript + CSS Variables
- [x] **1.4 Landing Page chuyên nghiệp**
  - [x] Thiết kế giao diện landing page hiện đại, responsive hoàn hảo trên di động (375px)
- [x] **1.5 Login & Dashboard Skeleton**
  - [x] Tích hợp trang `/login`
  - [x] Thiết kế khung `/dashboard` (Sidebar + Topbar + Báo cáo nhanh KPIs + Đăng xuất)
  - [x] Khắc phục lỗi Prerender / Suspense khi build Next.js

---

### 📦 PHASE 2: Nghiệp vụ cốt lõi (Core Business) - ĐÃ HOÀN THÀNH
- [x] **2.1 Sửa lỗi TypeScript & Build Backend**
  - [x] Khắc phục toàn bộ các lỗi gán kiểu dữ liệu (`string | string[]` sang `string`) để backend build thành công `npm run build`
- [x] **2.2 Quản lý sản phẩm (Products CRUD)**
  - [x] Hỗ trợ phân loại RAW/MIX, quản lý giá vốn, giá bán, tồn kho thực tế
  - [x] Tích hợp API backend tương ứng
- [x] **2.3 Quản lý khách hàng / nhà cung cấp**
  - [x] Bộ lọc khách hàng và đối tác
  - [x] API backend quản lý thông tin khách hàng
- [x] **2.4 Giao dịch POS (Point of Sale)**
  - [x] POS tạo đơn hàng, tự động trừ tồn kho (RAW/MIX)
  - [x] Tích hợp in hóa đơn và tự động ghi nhận công nợ khi trả thiếu
- [x] **2.5 Lịch sử bán hàng (Sales History)**
  - [x] Danh sách hóa đơn, chi tiết hóa đơn, chức năng hủy/hoàn đơn

---

### 💰 PHASE 3: Tài chính & Quản lý (Finance & Log) - ĐÃ HOÀN THÀNH
- [x] **3.1 Quản lý công nợ (Debts & Payments)**
  - [x] Sổ ghi nợ: khách nợ cửa hàng (`othersOweMe`) và cửa hàng nợ đối tác (`oweOthers`)
  - [x] Ghi nhận thanh toán nợ từng lần, liên kết tự động từ hóa đơn
- [x] **3.2 Đơn nhập hàng & lịch sử (Purchase Orders)**
  - [x] Nhập kho sản phẩm, cộng tồn kho thực tế
  - [x] Tự động cập nhật công nợ nhà cung cấp
- [x] **3.3 Quản lý chi phí (Expenses)**
  - [x] Phân loại và ghi nhận các chi phí hoạt động của cửa hàng

---

### 📊 PHASE 4: Báo cáo & Cấu hình (Reports & Settings) - ĐÃ HOÀN THÀNH
- [x] **4.1 Báo cáo doanh thu & lợi nhuận**
  - [x] Biểu đồ trực quan so sánh doanh thu/lợi nhuận theo ngày, tuần, tháng, năm
- [x] **4.2 Báo cáo tồn kho & Kiểm kê**
  - [x] Cảnh báo hết hàng, tồn kho trị giá bao nhiêu
- [x] **4.3 Cài đặt cửa hàng & Tài khoản**
  - [x] Thông tin cửa hàng, tài khoản ngân hàng VietQR cho POS
  - [x] Quản lý tài khoản nhân viên phân quyền

---

### 🔄 PHASE 5: Đồng bộ & Nâng cao (Sync & AI) - ĐÃ HOÀN THÀNH
- [x] **5.1 API Đồng bộ hai chiều (Two-way sync API)**
  - [x] API Push/Pull đồng bộ dữ liệu giữa Mobile App SQLite ↔ Web PostgreSQL
- [x] **5.2 AI hỗ trợ bằng giọng nói**
  - [x] Chuyển chức năng "Lên đơn bằng giọng nói" từ Flutter mobile sang giao diện Web sử dụng AI Provider
- [x] **5.3 Hỗ trợ PWA & Xuất báo cáo**
  - [x] Cấu hình PWA hoạt động offline, xuất báo cáo PDF/Excel

---

### 🔄 PHASE 6: Đồng bộ hóa toàn diện Web ↔ Mobile (Dashboard, POS, Reports) - ĐÃ HOÀN THÀNH
- [x] **6.1 Cập nhật API Backend cho Dashboard & Reports**
  - [x] Hỗ trợ lọc theo `employeeId`, tính toán đầy đủ các chỉ số cash/bank thực thu, nợ phát sinh và gom nhóm dữ liệu theo ngày/tháng/năm cho biểu đồ.
- [x] **6.2 Đồng bộ logic POS Bán hàng & Công nợ**
  - [x] Khóa nợ Khách vãng lai, thêm các nút chọn nhanh số tiền khách trả, dropdown chọn nhân viên bán hàng, hiển thị VietQR tự động khi thanh toán BANK thành công (không nợ).
- [x] **6.3 Tích hợp cảnh báo tồn kho và cảnh báo giá bán MIX tại POS**
  - [x] Cảnh báo tồn kho không đủ (cho cập nhật nhanh) và cảnh báo bán dưới giá nguyên liệu RAW của MIX giống mobile.
- [x] **6.4 Nâng cấp trang Báo cáo (Reports) Web**
  - [x] Hiển thị 14 KPIs giống hệt mobile, bộ lọc nâng cao, vẽ biểu đồ tròn/biểu đồ cột SVG tương tác, danh sách Top sản phẩm bán chạy có progress bar và xuất CSV đầy đủ dữ liệu.
- [x] **6.5 Cập nhật Dashboard Web**
  - [x] Loại bỏ mock data fallback, sử dụng dữ liệu thực tế hôm nay qua filter date, tính toán động tổng đơn hàng.

---

### 🔍 PHASE 7: Tìm kiếm Tiếng Việt, Quản lý Tồn kho & Chi tiết Báo cáo (Phase 7 - ĐÃ HOÀN THÀNH)
- [x] **7.1 Chuẩn hóa tìm kiếm Tiếng Việt (Vietnamese diacritics search)**
  - [x] Tạo tiện ích dùng chung `text.ts` thực hiện loại bỏ dấu và so khớp chính xác/tên viết tắt (initials).
  - [x] Áp dụng tìm kiếm chuẩn hóa cho tất cả các màn hình: POS, Lịch sử bán hàng, Sản phẩm, Khách hàng, Công nợ, Chi phí và modal chọn nhanh sản phẩm.
- [x] **7.2 Cải tiến layout POS**
  - [x] Chuyển đổi lưới sản phẩm (grid) tại POS thành 4 cột trên màn hình desktop.
- [x] **7.3 Tách tab và quản lý tồn kho Sản phẩm**
  - [x] Ẩn thông số tồn kho trực tiếp đối với sản phẩm MIX (hiển thị `—`).
  - [x] Tạo 3 sub-tabs trong trang sản phẩm: Tồn kho, Lịch sử nhập kho (RAW purchases), Lịch sử xuất kho RAW (bao gồm cả phân rã nguyên liệu MIX).
  - [x] Tích hợp các widget tổng hợp số lượng và giá trị (giá vốn, thành tiền) tự động tính toán theo bộ lọc.
  - [x] Thêm tính năng cập nhật số dư tồn đầu kỳ (tồn đầu tháng) cho sản phẩm.
- [x] **7.4 Nâng cấp Báo cáo & Chi tiết giao dịch (Backdata)**
  - [x] Bổ sung phần "Tổng quan tồn kho" gồm 4 thẻ chỉ số: Tồn đầu, Nhập trong kỳ, Xuất trong kỳ, Tồn cuối kỳ.
  - [x] Tích hợp modal xem chi tiết giao dịch gốc (Backdata Grid) cho toàn bộ 18 chỉ số KPIs báo cáo.
  - [x] Thêm 3 widgets dòng tiền thực thu thực tế (Tổng thu, Thu TM, Thu CK) phát sinh trong kỳ cùng modal backdata chi tiết.
- [x] **7.5 Tối ưu hóa UI/UX & Khắc phục lỗi hiển thị**
  - [x] Sửa lỗi icon kính lúp che đè chữ nhập trong các ô tìm kiếm.
  - [x] Thiết lập chiều cao linh hoạt tự động co giãn theo viewport cho các bảng MUI DataGrid (dính xuống bottom của desktop).
  - [x] Sửa lỗi dropdown select bị che mất chữ sau khi chọn bằng cách reset padding đứng và thiết lập custom arrow SVG.
  - [x] Tối ưu hóa Pie Chart chi phí to ra, legends chuyển xuống dưới dạng grid 2 cột.
  - [x] Tách luồng render biểu đồ và KPIs, loại bỏ triệt để hiện tượng trắng trang nhấp nháy khi đổi bộ lọc biểu đồ.

---

### 📱 PHASE 8: Danh bạ máy & Chia sẻ Hóa đơn trên Web di động - ĐÃ HOÀN THÀNH
- [x] **8.1 Truy cập Danh bạ Điện thoại di động gốc**
  - [x] Sử dụng W3C Contact Picker API để chọn liên lạc trực tiếp từ thiết bị.
  - [x] Chuẩn hóa số điện thoại tự động chuyển `+84` / `84` thành đầu số `0`.
- [x] **8.2 Vẽ và Chia sẻ Hóa đơn ảnh (PNG)**
  - [x] Viết tiện ích Canvas vẽ hóa đơn dạng nhiệt chuyên nghiệp, tính toán chiều cao tự động.
  - [x] Sử dụng Web Share API chia sẻ ảnh hóa đơn đến các ứng dụng khác (Zalo, Messenger...).
  - [x] Cơ chế Fallback tự động tải file ảnh hóa đơn nếu trình duyệt không hỗ trợ Web Share API.
- [x] **8.3 Hỗ trợ truy cập mạng nội bộ LAN & Tên miền custom**
  - [x] Cấu hình `allowedDevOrigins` cho Webpack HMR trên IP LAN và tên miền `cmsvina4285.com:3001` để tránh lỗi chặn kết nối WebSocket.
  - [x] Tự động phân giải địa chỉ `API_URL` dựa trên hostname trình duyệt để cuộc gọi API hướng đúng về máy chủ dev từ thiết bị di động.
  - [x] Thêm tên miền custom `cmsvina4285.com` và `cmsvina4285.com:3001` vào allowed CORS origins của backend API.
- [x] **8.4 Cài đặt HTTPS/SSL cho dev & production**
  - [x] Cấu hình script khởi chạy `dev:ssl` cho Next.js dev server sử dụng custom SSL certs.
  - [x] Tích hợp module HTTPS cho Express backend để tự động khởi chạy secure server nếu phát hiện chứng chỉ SSL.
  - [x] Loại bỏ các tệp tin chứng chỉ SSL ra khỏi Git bằng cách cập nhật `.gitignore` gốc.
- [x] **8.5 Tối ưu hóa hiệu năng POS & Cải tiến Cấu hình AI Bảo mật**
  - [x] Khử nháy màn hình POS bằng cách đồng bộ paidAmount khi render và thêm cơ chế Debounce 400ms cho QR preview.
  - [x] Chuyển đổi lưu trữ AI API Keys lên cơ sở dữ liệu (lưu tập trung tại bảng `sync_state`).
  - [x] Tự động tải danh sách Model thực tế từ API chính thức (Google/OpenRouter) dựa trên API Key.
  - [x] Lưu trữ model đã lựa chọn vào localStorage riêng biệt của từng thiết bị.

---

### 📝 PHASE 9: Chỉnh sửa Đơn hàng, Chứng từ Đính kèm & Nâng cao UI/UX - ĐÃ HOÀN THÀNH
- [x] **9.1 Chọn Khách hàng Autocomplete & Thêm nhanh**
  - [x] Thay thế dropdown khách hàng trong POS bằng ô tìm kiếm Autocomplete hỗ trợ tìm bằng cả tên có dấu, không dấu và số điện thoại.
  - [x] Thêm nút "Thêm nhanh" khách hàng trực tiếp tại màn hình POS mở Dialog điền thông tin và hỗ trợ nút "Chọn từ danh bạ" (W3C Contact Picker API).
- [x] **9.2 Autocomplete & Danh bạ trong Nhập hàng**
  - [x] Áp dụng ô tìm kiếm Autocomplete cho Nhà cung cấp trong hộp thoại Nhập hàng.
  - [x] Hỗ trợ nút chọn thông tin Nhà cung cấp trực tiếp từ Danh bạ điện thoại di động (Contact Picker API).
- [x] **9.3 Tải lên Chứng từ Đính kèm (Hóa đơn/PDF/Hình ảnh)**
  - [x] Tạo API `POST /api/upload` tiếp nhận ảnh/file PDF mã hóa Base64 và lưu trữ an toàn trong thư mục phục vụ static `/uploads`.
  - [x] Cho phép tải lên chứng từ đính kèm (dạng ảnh hoặc file PDF) cho Đơn nhập hàng trong trang Nhập hàng & Kho vận.
  - [x] Cho phép tải lên chứng từ đính kèm trực tiếp trong hộp thoại Thêm/Sửa chi phí tại trang Chi phí hoạt động.
- [x] **9.4 Chỉnh sửa & Xóa Chi phí hoạt động**
  - [x] Tích hợp các nút hành động Sửa (✏️) và Xóa (🗑️) cho mỗi dòng chi phí hoạt động.
  - [x] Hộp thoại sửa hiển thị đầy đủ thông tin chi tiết của chi phí và cho phép thay đổi file chứng từ đính kèm hoặc xóa bỏ.
- [x] **9.5 Chỉnh sửa Đơn Nhập hàng & Tự động cân đối kho/nợ**
  - [x] Tạo API `PUT /api/purchases/orders/:id` tự động tính toán chênh lệch tồn kho (trả lại số lượng cũ, trừ đi số lượng mới của sản phẩm RAW) và tự điều chỉnh công nợ Supplier nợ đối tác liên quan.
  - [x] Thiết kế hộp thoại Chỉnh sửa Đơn nhập hàng hoàn chỉnh, cho phép sửa nhà cung cấp, giảm giá, số tiền đã trả và danh sách mặt hàng nhập.
- [x] **9.6 Chỉnh sửa Đơn Bán hàng & Tự động cân đối kho/nợ**
  - [x] Tạo API `PUT /api/sales/:id` hoàn trả nguyên liệu (bao gồm cả nguyên liệu thành phần RAW tạo nên sản phẩm MIX) của đơn cũ, trừ tồn kho cho đơn mới và tự động điều chỉnh, xóa bỏ hoặc tạo mới hóa đơn công nợ của khách hàng.
  - [x] Hộp thoại sửa đơn bán hàng trực quan, cho phép thêm bớt sản phẩm, sửa số lượng, giá bán và cập nhật thông tin trả trước của khách hàng.
- [x] **9.7 Hiển thị thông tin Đơn hàng trong Lịch sử Công nợ**
  - [x] Tự động tải thông tin giao dịch gốc (Sale Order hoặc Purchase Order) khi người dùng chọn một khoản nợ trong Sổ ghi nợ.
  - [x] Hiển thị chi tiết danh sách mặt hàng, số lượng và tổng tiền của đơn hàng tương ứng ngay phía trên lịch sử thanh toán nợ của khoản nợ đó.
- [x] **9.8 Nâng cao độ sắc nét ảnh Hóa đơn Chia sẻ**
  - [x] Nâng cấp tỷ lệ vẽ Canvas lên 3x (const scale = 3) giúp ảnh hóa đơn xuất ra đạt độ phân giải cao, rõ nét từng chữ, không bị mờ vỡ hình khi phóng to trên thiết bị di động.

---

### 🎨 PHASE 10: Giao diện Di động Nâng cao & Đa Giao diện (Themes) - ĐÃ HOÀN THÀNH
- [x] **10.1 Thanh điều hướng dưới (Bottom Navigation Bar) cho di động**
  - [x] Thêm thanh điều hướng cố định phía dưới màn hình trên di động dạng cuộn ngang để thuận tiện thao tác một tay.
  - [x] Ẩn nút menu hamburger và menu dropdown cũ trên di động.
- [x] **10.2 Tối ưu hóa giao diện POS cho di động**
  - [x] Chuyển đổi chọn Khách hàng, Nhân viên và chọn Sản phẩm thành các Modal chọn nhanh dạng danh sách trực quan.
  - [x] Tăng kích thước phông chữ và kích thước nút bấm tăng/giảm số lượng trong giỏ hàng để dễ dàng bấm chạm bằng ngón tay.
- [x] **10.3 Tính năng thay đổi giao diện đa sắc màu (Themes)**
  - [x] Định nghĩa 6 giao diện màu sắc trong CSS Variables: Midnight (Mặc định), Hồng mộng mơ (Light), Thiên nhiên, Biển xanh, Hoàng hôn, Lavender.
  - [x] Tích hợp phần chọn Giao diện trong trang Cài đặt, tự động lưu lựa chọn vào localStorage và áp dụng tức thời cho toàn app.
  - [x] Đồng bộ hóa load theme từ client-side bằng thẻ `<script>` nhúng trong `<head>` tránh hiện tượng nháy màu khi tải trang.



