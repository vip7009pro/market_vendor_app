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



