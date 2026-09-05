# Báo cáo Đánh giá Điều kiện Đồng bộ 2 Chiều (Online - Offline, Đa Thiết bị)

Tài liệu này đánh giá tính tương thích của Schema Database hiện tại giữa **Flutter Mobile (SQLite v33)** và **Web Backend (PostgreSQL / Prisma)**. Đồng thời chỉ ra các lỗi kiến trúc, thiếu sót kỹ thuật cần bổ sung trước khi có thể bắt đầu triển khai đồng bộ hóa hai chiều (Two-Way Sync) an toàn và tin cậy trên nhiều thiết bị.

---

## I. Tổng Quan Trạng Thái Hiện Tại

Hiện tại, mã nguồn đã có:
1.  **SQLite Database** trên di động (`lib/services/database_service.dart`) quản lý dữ liệu offline.
2.  **PostgreSQL Database Schema** (`backend-api/prisma/schema.prisma`) quản lý dữ liệu online.
3.  **OnlineSyncService** trên mobile (`lib/services/online_sync_service.dart`) hỗ trợ Push/Pull dữ liệu qua API.
4.  **SyncService** trên backend (`backend-api/src/services/sync.service.ts`) xử lý nhận sự kiện (push) áp dụng logic LWW (Last-Write-Wins) và trả sự kiện (pull) dựa trên Cursor (`eventId`).

Tuy nhiên, **HỆ THỐNG CHƯA ĐỦ ĐIỀU KIỆN** để chạy đồng bộ 2 chiều đa thiết bị một cách an toàn. Có nhiều lỗi nghiêm trọng về cấu trúc khóa, thiếu sót sự kiện và bất tương thích trường dữ liệu có thể gây **mất dữ liệu, trùng lặp dữ liệu, hoặc xung đột ghi đè** giữa các máy khách.

---

## II. Các Vấn Đề Tương Thích & Lỗi Thiết Kế Chi Tiết

### 🚨 1. Lỗi Nghiêm Trọng: Đơn Web CRUD Không Tạo Sự Kiện Đồng Bộ (Sync Events)
*   **Hiện trạng:** Khi người dùng thao tác trên Web App Next.js (ví dụ: tạo sản phẩm mới, sửa giá, lên đơn POS, cập nhật công nợ), các API Router của backend (`products.routes.ts`, `sales.routes.ts`, `debts.routes.ts`...) thực hiện ghi trực tiếp vào các bảng PostgreSQL thông qua Prisma.
*   **Lỗi:** Các API này **hoàn toàn không ghi nhận sự kiện** vào bảng `sync_events`.
*   **Hậu quả:** 
    *   Bảng `sync_events` chỉ nhận được sự kiện khi có một thiết bị Mobile *Push* lên.
    *   Khi thiết bị Mobile khác gọi API *Pull* (`/api/sync/pull`), nó chỉ kéo được các sự kiện do các máy Mobile khác đẩy lên.
    *   **Mọi thay đổi thực hiện từ giao diện Web App sẽ vĩnh viễn không bao giờ được đồng bộ về các thiết bị di động**.
*   **Giải pháp:** Bổ sung logic tạo bản ghi vào `sync_events` (với `deviceId: 'web'`) trong tất cả các API route ghi dữ liệu (POST/PUT/DELETE) của backend.

---

### 🚨 2. Lỗi Xung Đột Khóa: Trùng Lặp & Ghi Đè Dữ Liệu Bảng `debt_payments`
*   **Hiện trạng:** Bảng `debt_payments` dùng để ghi nhận các đợt thanh toán nợ:
    *   **SQLite:** `id INTEGER PRIMARY KEY AUTOINCREMENT`, `uuid TEXT` (không có ràng buộc `UNIQUE` hay chỉ mục độc bản nào trên SQLite).
    *   **PostgreSQL:** Không có cột `id` kiểu số, khóa chính là `@@id([userId, uuid])`.
*   **Lỗi:** 
    1.  Khi Mobile *Pull* sự kiện `debt_payments` từ server về, nó thực hiện:
        ```dart
        final toInsert = Map<String, dynamic>.from(p);
        toInsert['uuid'] = entityId;
        toInsert['isSynced'] = 1;
        await db.insert('debt_payments', toInsert, conflictAlgorithm: ConflictAlgorithm.replace);
        ```
    2.  Vì `uuid` ở local SQLite **không phải là Khóa chính** và cũng **không có ràng buộc UNIQUE**, câu lệnh `insert` với `ConflictAlgorithm.replace` sẽ **luôn tạo ra một dòng mới** với một ID tự tăng (`id`) mới, thay vì cập nhật dòng cũ có cùng `uuid`! Điều này trực tiếp gây **trùng lặp thanh toán nợ** mỗi lần sync.
    3.  Tệ hơn, nếu payload `p` được tải từ server có chứa trường `id` (kiểu số tự tăng của thiết bị khác đẩy lên), câu lệnh `insert` trên sẽ ghi đè vào dòng có `id` trùng khớp ở local của thiết bị hiện tại (dù 2 bản ghi này hoàn toàn khác nhau về `uuid` và nội dung!). Điều này gây **ghi đè mất mát dữ liệu** nghiêm trọng.
*   **Giải pháp:**
    *   **Cách A:** Chuyển khóa chính của `debt_payments` trên SQLite thành `uuid TEXT PRIMARY KEY` (bỏ cột `id` số tự tăng).
    *   **Cách B:** Trong hàm `pullAndApply` trên Mobile, trước khi insert phải query kiểm tra xem `uuid` đã tồn tại chưa. Nếu có, thực hiện `update` theo `uuid`. Nếu chưa, mới thực hiện `insert` và xóa trường `id` khỏi payload để SQLite tự sinh.

---

### ⚠️ 3. Bất Tương Thích Tên Trường (Field Casing Mismatch) Bảng `vietqr_bank_accounts`
*   **Hiện trạng:** 
    *   Trong SQLite: Bảng chứa cột tên là `swift_code` (snake_case) và cột `short_name` (snake_case).
    *   Trong PostgreSQL (Prisma): Model định nghĩa thuộc tính `swiftCode` và `shortName` (camelCase) và dùng `@map("swift_code")` để lưu vào DB.
*   **Lỗi:** 
    *   Khi backend trả sự kiện về qua API pull, nó serialize đối tượng Prisma sang JSON, do đó keys trả về sẽ là `swiftCode` và `shortName` (camelCase).
    *   Khi Mobile gọi `db.insert('vietqr_bank_accounts', toInsert, ...)`, thư viện `sqflite` sẽ báo lỗi (hoặc bỏ qua) vì trong bảng SQLite chỉ có cột `swift_code` chứ không có cột `swiftCode`.
*   **Giải pháp:** Chuẩn hóa lại tên trường trong SQLite thành camelCase giống các bảng khác, hoặc thực hiện mapping / rename keys trước khi ghi vào SQLite trên Mobile.

---

### ⚠️ 4. Các Bảng Chưa Được Đồng Bộ (Missing Entity Sync)
Hiện tại, có 3 bảng nghiệp vụ đã có cấu trúc ở cả hai phía nhưng **bị bỏ sót** trong danh sách đồng bộ của `OnlineSyncService` trên Mobile:
1.  **`store_info`**: Lưu thông tin cửa hàng, hotline, địa chỉ, tài khoản ngân hàng nhận VietQR. (Không đồng bộ dẫn đến việc thiết lập cửa hàng ở máy này không áp dụng cho máy khác).
2.  **`product_opening_stocks`**: Lưu số lượng tồn kho đầu kỳ (đầu tháng) phục vụ báo cáo. (Không đồng bộ dẫn đến báo cáo tồn kho giữa Web và Mobile lệch nhau).
3.  **`debt_reminder_settings`**: Lưu trạng thái tắt/mở thông báo nhắc nợ của từng khách hàng.

*   **Giải pháp:** Đưa 3 thực thể này vào mảng `_syncEntities` và viết các hàm xử lý tương ứng trong `online_sync_service.dart` và `sync.service.ts`.

---

### ⚠️ 5. Sự Khác Biệt Loại Dữ Liệu (Float vs Decimal) & Đồng Bộ Tệp Tin (File Sync)
*   **Số thập phân (Decimal vs Float):** SQLite lưu kiểu `REAL` (Float), PostgreSQL lưu kiểu `Numeric` (Decimal). Khi đồng bộ cần ép kiểu cẩn thận để tránh lỗi làm tròn (ví dụ `100.0000000001` thay vì `100`). Hiện tại backend đã dùng `Number(p.field)` để ép kiểu về float trên JS, tạm thời chấp nhận được nhưng cần giám sát.
*   **Đồng Bộ Tệp Tin Đính Kèm (Document/Photo Sync):**
    *   Sản phẩm có `imagePath`, Đơn nhập hàng có `purchaseDocFileId`, Chi phí có `expenseDocFileId` lưu đường dẫn file cục bộ (local path).
    *   Khi đồng bộ database sang thiết bị khác, các đường dẫn này trở nên vô nghĩa (bị lỗi broken image / missing file) vì file vật lý chưa được tải lên server và kéo về thiết bị mới.
    *   **Giải pháp:** Phải có cơ chế tải ảnh/file lên Cloud Storage hoặc API `/api/upload` của backend và đồng bộ URL của file thay vì local file path.

---

### 🚨 6. Lỗi Kết Nối: Sai Cổng (Port) và Sai Đường Dẫn (Route Paths) trên Mobile
*   **Hiện trạng:** 
    *   **Mobile (`online_sync_service.dart`):**
        *   Cổng mặc định đang là `3006` (`return 'http://10.0.2.2:3006'`).
        *   Các URL gọi API đẩy/kéo được nối cứng là: `/sync/push` và `/sync/pull`.
    *   **Backend Mới (`backend-api`):**
        *   Cổng mặc định hoạt động là `3007` (hoặc cấu hình qua biến môi trường `PORT`).
        *   Các API sync được mount tại đường dẫn `/api/sync` trong [index.ts](file:///g:/NODEJS/market_vendor_app/backend-api/src/index.ts#L65). Do đó, URL chính xác trên server là: `/api/sync/push` và `/api/sync/pull`.
*   **Hậu quả:** Mobile khi chạy sync sẽ cố gắng gọi `http://10.0.2.2:3006/sync/push` và `http://10.0.2.2:3006/sync/pull` dẫn tới lỗi **không thể kết nối** (do sai cổng) hoặc trả về lỗi **404 Not Found** (do sai đường dẫn `/sync` thay vì `/api/sync`).
*   **Giải pháp:**
    *   Cập nhật cổng mặc định trong hàm `_baseUrl()` của Mobile thành `3007`.
    *   Sửa các đường dẫn API sync trong `online_sync_service.dart` thành `/api/sync/push` và `/api/sync/pull`.


---

## III. Bảng So Sánh Chi Tiết Schema Của Các Thực Thể Chính

| Thực thể (Table) | Khóa chính SQLite (Mobile) | Khóa chính PostgreSQL (Server) | Đánh giá tính tương thích | Khắc phục cần thiết |
| :--- | :--- | :--- | :--- | :--- |
| **products** | `id` (TEXT UUID) | `(userId, id)` (Int, String) | Khớp tốt | Không |
| **customers** | `id` (TEXT UUID) | `(userId, id)` (Int, String) | Khớp tốt | Không |
| **employees** | `id` (TEXT UUID) | `(userId, id)` (Int, String) | Khớp tốt | Không |
| **sales** | `id` (TEXT UUID) | `(userId, id)` (Int, String) | Khớp tốt | Không |
| **sale_items** | `id` (INT Autoincrement) | `(userId, id)` (Int, String) | Đồng bộ gián tiếp qua `sales` | Không (đã remove ID khi apply) |
| **debts** | `id` (TEXT UUID) | `(userId, id)` (Int, String) | Khớp tốt | Không |
| **debt_payments** | `id` (INT Autoincrement) | `(userId, uuid)` (Int, String) | **🚨 Lỗi nghiêm trọng** | Chuyển SQLite PK sang `uuid` hoặc fix logic apply |
| **purchase_orders** | `id` (TEXT UUID) | `(userId, id)` (Int, String) | Khớp tốt | Không |
| **purchase_history**| `id` (TEXT UUID) | `(userId, id)` (Int, String) | Khớp tốt | Không |
| **expenses** | `id` (TEXT UUID) | `(userId, id)` (Int, String) | Khớp tốt | Không |
| **vietqr_bank_accounts**| `id` (TEXT UUID)| `(userId, id)` (Int, String) | **⚠️ Casing Mismatch** | Đổi tên cột SQLite `swift_code` thành `swiftCode` |
| **store_info** | `id` (INT) | `(userId, id)` (Int, Int) | **⚠️ Chưa đồng bộ** | Thêm vào danh sách thực thể đồng bộ |
| **product_opening_stocks**| `(productId, year, month)`| `(userId, productId, year, month)`| **⚠️ Chưa đồng bộ** | Thêm vào danh sách thực thể đồng bộ |
| **debt_reminder_settings**| `debtId` (TEXT) | `(userId, debtId)` (Int, String) | **⚠️ Chưa đồng bộ** | Thêm vào danh sách thực thể đồng bộ |

---

## IV. Kế Hoạch Triển Khai Nâng Cấp Đồng Bộ Chi Tiết

Dưới đây là các bước cụ thể cần thực hiện để hoàn thiện hệ thống đồng bộ 2 chiều đa thiết bị hoạt động ổn định:

### Bước 1: Sửa lỗi cấu hình kết nối, khóa và kiểu dữ liệu trên Mobile (SQLite)
1.  **Cập nhật cấu hình API Endpoint trong `online_sync_service.dart`**:
    *   Sửa cổng mặc định trong hàm `_baseUrl()` từ `3006` thành `3007` (khớp với server backend mới).
    *   Sửa các đường dẫn kết nối trong `_pushOutbox` và `_pullAndApply` từ `/sync/push` thành `/api/sync/push`, và `/sync/pull` thành `/api/sync/pull`.
2.  **Viết Migration v34 trong `database_service.dart`**:
    *   Tạo bảng tạm `debt_payments_new` với khóa chính là `uuid TEXT PRIMARY KEY` (thay thế cho cột `id` số tự tăng). Sao chép dữ liệu từ bảng cũ sang bảng mới, đổi tên bảng mới thành `debt_payments`.
    *   Đổi tên cột `swift_code` thành `swiftCode` và `short_name` thành `shortName` trong bảng `vietqr_bank_accounts` để tương thích hoàn toàn với Prisma payload.
3.  **Cập nhật các câu lệnh SQL CRUD tương ứng**:
    *   Tìm và sửa các hàm CRUD liên quan đến `debt_payments` trong `database_service.dart` để chèn/sửa dữ liệu theo `uuid` thay vì sử dụng `id` kiểu số tự tăng.


### Bước 2: Bổ sung cơ chế phát sinh Sự Kiện Đồng Bộ trên Web Backend
1.  **Tạo Hàm Helper ghi nhận sự kiện (`SyncService.recordEvent`)**:
    *   Viết hàm tĩnh trên server nhận vào `userId`, `entity`, `entityId`, `op`, `payload` và tự động ghi vào bảng `sync_events` với `deviceId = 'web'`.
2.  **Tích hợp vào các Backend Routes**:
    *   Chèn lời gọi `SyncService.recordEvent` vào các endpoint:
        *   `POST/PUT/DELETE /api/products`
        *   `POST/PUT/DELETE /api/customers`
        *   `POST/PUT/DELETE /api/sales` (bao gồm cả update tồn kho và công nợ phát sinh)
        *   `POST/PUT/DELETE /api/debts`
        *   `POST/PUT /api/debts/:id/payments`
        *   `POST/PUT/DELETE /api/expenses`
        *   `POST/PUT/DELETE /api/purchases/orders`
        *   `POST/PUT/DELETE /api/employees`
        *   `POST/PUT/DELETE /api/settings/vietqr`
        *   `POST/PUT /api/settings/store`

### Bước 3: Đồng bộ bổ sung các thực thể còn thiếu
1.  **Cập nhật trên Flutter Mobile (`OnlineSyncService`)**:
    *   Đưa `store_info`, `product_opening_stocks`, và `debt_reminder_settings` vào danh sách `_syncEntities`.
    *   Cập nhật hàm `_enqueueOutboxFromUnsynced` để quét 3 bảng này và đẩy lên outbox.
    *   Cập nhật hàm `_pullAndApply` để tiếp nhận sự kiện của 3 bảng này và cập nhật vào SQLite cục bộ theo cơ chế LWW.
2.  **Cập nhật trên Backend (`SyncService.ts`)**:
    *   Thêm các case xử lý upsert cho `store_info`, `product_opening_stocks`, và `debt_reminder_settings` tương tự các thực thể khác.

### Bước 4: Kiểm thử và Vận hành
1.  **Kiểm thử cục bộ (Local Testing)**:
    *   Chạy đồng thời 1 Web App Next.js và 2 máy giả lập Android (hoặc 1 Android + 1 iOS).
    *   Tạo dữ liệu trên Web ➔ Kiểm tra xem 2 máy di động có nhận được sau khi Pull tự động.
    *   Tạo dữ liệu offline trên máy di động 1 ➔ Bật mạng ➔ Kiểm tra xem Web và máy di động 2 có cập nhật đúng.
2.  **Kích hoạt Auto Sync**:
    *   Bỏ comment dòng gọi `OnlineSyncService.startAutoSync` và `syncNow` trong `app_init.dart` để kích hoạt đồng bộ tự động mỗi khi app khởi động hoặc khi có kết nối mạng trở lại.

---

## V. Đánh Giá Khả Năng Khôi Phục Bản Sao Lưu Cũ (Restore Backup)

Khi cập nhật ứng dụng lên phiên bản mới (ví dụ áp dụng Migration v34 sửa đổi khóa chính SQLite), việc người dùng khôi phục lại các bản sao lưu cũ (được tạo từ phiên bản app v33 trở về trước) là một nghiệp vụ bắt buộc phải hoạt động ổn định. Dưới đây là phân tích luồng kỹ thuật và các rủi ro liên quan:

### 1. Luồng kỹ thuật khi khôi phục (Restore Flow)
1.  **Thay thế vật lý:** Khi khôi phục từ Google Drive, `DriveSyncService` sẽ tải tệp tin zip xuống, đóng kết nối DB hiện tại (`DatabaseService.instance.close()`), giải nén và ghi đè trực tiếp tệp tin `market_vendor.db` cũ vào bộ nhớ thiết bị.
2.  **Tự động chạy Migration nâng cấp:** Sau khi thay thế tệp, app gọi `DatabaseService.instance.reinitialize()`, kích hoạt lại `openDatabase`. Do file DB được khôi phục có phiên bản cũ (v33 hoặc nhỏ hơn) trong khi code App mới yêu cầu phiên bản cao hơn (v34), SQLite sẽ tự động chạy hàm `_migrateDatabase` theo tuần tự (từ v33 lên v34). Do đó, cấu trúc bảng cũ sẽ được tự động nâng cấp đồng bộ với mã nguồn mới trước khi người dùng thực hiện bất kỳ truy vấn nào.
3.  **Hồi phục trạng thái đồng bộ qua Cursor:** 
    *   Con trỏ cursor đồng bộ (`online_sync_cursor` trong bảng `sync_state`) sẽ được khôi phục về giá trị cũ tại thời điểm sao lưu (ví dụ: `cursor = 100`).
    *   Khi ứng dụng kích hoạt sync sau khi khôi phục, nó sẽ thực hiện `pull` toàn bộ các sự kiện từ server có `eventId > 100`.
    *   Nhờ cơ chế so sánh timestamp **LWW (Last-Write-Wins)** ở client, tất cả các thay đổi mới hơn trên server (đã được thực hiện online sau thời điểm sao lưu) sẽ tự động được kéo xuống và cập nhật đè lên dữ liệu cũ vừa khôi phục.
    *   Các sự kiện chưa đồng bộ (`isSynced = 0`) tại thời điểm sao lưu sẽ tự động được đẩy (`push`) lại lên server. Do server có cơ chế kiểm tra tính trùng lặp sự kiện (Idempotency check) dựa trên `eventUuid`, server sẽ bỏ qua các sự kiện trùng lặp này một cách an toàn và phản hồi thành công để client đánh dấu `isSynced = 1`.

### 2. Các rủi ro tiềm ẩn & Giải pháp khắc phục bổ sung

Để đảm bảo việc khôi phục bản sao lưu cũ 100% không gây lỗi, chúng ta cần bổ sung các biện pháp phòng ngừa sau vào kế hoạch triển khai:

*   **⚠️ Rủi ro trùng lặp hoặc vi phạm khóa chính khi chạy Migration v34 nâng cấp `debt_payments`:**
    *   *Chi tiết:* Bản sao lưu cũ (v33) chứa bảng `debt_payments` có khóa chính số tự tăng `id`, trường `uuid` có thể bị `NULL` ở một số dòng cũ (nếu bản sao lưu quá cũ từ trước v27) hoặc chứa các giá trị `uuid` trùng lặp do lỗi ghi đè trước đây. Khi chạy migration v34 để chuyển `uuid` làm Khóa chính (`PRIMARY KEY`), SQLite sẽ báo lỗi `Constraint violation` và treo app nếu phát hiện dữ liệu vi phạm.
    *   *Giải pháp bổ sung vào kế hoạch:* Trong migration v34, trước khi copy dữ liệu sang bảng mới:
        1. Cập nhật các dòng có `uuid IS NULL` hoặc rỗng bằng cách sinh UUID ngẫu nhiên (`uuid.v4()`).
        2. Quét kiểm tra trùng lặp `uuid`. Nếu phát hiện trùng lặp `uuid`, thực hiện sinh lại `uuid` mới cho dòng trùng lặp đó để đảm bảo tính độc bản trước khi khai báo khóa chính.
*   **⚠️ Rủi ro khôi phục tệp DB phiên bản mới vào App phiên bản cũ (Hạ cấp ứng dụng):**
    *   *Chi tiết:* Nếu người dùng khôi phục bản sao lưu được tạo ở app v34 vào thiết bị chạy app v33, hàm `onDowngrade` của SQLite đang được cấu hình bỏ qua nâng cấp (skip) để tránh mất dữ liệu. Tuy nhiên, app v33 sẽ bị crash khi thực hiện các câu lệnh truy vấn SQL cũ (ví dụ: truy vấn bằng `id` thay vì `uuid` trên bảng `debt_payments`, hoặc lỗi thiếu cột trong bảng `vietqr_bank_accounts`).
    *   *Giải pháp bổ sung vào kế hoạch:* Thêm cảnh báo người dùng trên giao diện khôi phục: *"Không khôi phục các bản sao lưu được tạo từ phiên bản ứng dụng mới hơn vào phiên bản hiện tại để tránh lỗi hệ thống."*
*   **⚠️ Mất cấu hình cục bộ không đồng bộ:**
    *   *Chi tiết:* Bảng `sync_state` lưu trữ API key của AI (Google Gemini, OpenRouter) không nằm trong danh mục đồng bộ online. Khi khôi phục bản sao lưu, cấu hình AI sẽ bị đưa về trạng thái tại thời điểm sao lưu.
    *   *Giải pháp bổ sung vào kế hoạch:* Thêm thông báo lưu ý người dùng có thể cần thiết lập lại các thông số cấu hình AI và cấu hình máy in nhiệt sau khi khôi phục thành công.

