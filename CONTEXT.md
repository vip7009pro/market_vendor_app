# CONTEXT.md — Market Vendor App

## Tổng quan
Ứng dụng Flutter quản lý bán hàng, ghi nợ cho tiểu thương. Hoạt động offline, hỗ trợ đồng bộ Google Drive.

## Trạng thái hiện tại (2026-04-11)

### Thay đổi gần nhất: Tìm kiếm không dấu + Nút micro AI thêm sản phẩm

**1. Fix tìm kiếm tiếng Việt không dấu** trong `voice_order_screen.dart`
- Product picker bottomsheet giờ dùng `TextNormalizer.normalize()` thay vì `toLowerCase()`
- Có thể tìm "nuoc" → ra "nước ngọt"

**2. Widget `VoiceProductInputDialog`** (`lib/widgets/voice_product_input_dialog.dart`) — MỚI
- Dialog dùng chung cho phép thêm sản phẩm bằng giọng nói
- UI: Nút Record + Ô text + Switch Auto/Manual + Nút "Xử lý AI"
- Dùng `speech_to_text` (vi_VN) + `AiProviderService.sendChatCompletion()`
- AI parse giọng nói → JSON schema: `{name, price, costPrice, unit, currentStock, barcode}`
- Trả về `VoiceProductResult` → tự điền vào form thêm sản phẩm
- Auto mode: nói xong tự gửi AI (lưu SharedPreferences key `voice_product_auto_send`)

**3. Tích hợp nút micro 🎤** vào dialog "Thêm sản phẩm" tại 3 màn hình:
- `voice_order_screen.dart` — `_addQuickProductDialog()` (title row + mic button)
- `sale_screen.dart` — `_addQuickProductDialog()` (refactored StatefulBuilder lên AlertDialog level)
- `product_list_screen.dart` — `_showProductDialog()` (chỉ hiện khi thêm mới, không hiện khi sửa)

### Thay đổi trước đó: Thêm Google Gemini AI Provider

**`lib/services/ai_provider_service.dart`** (MỚI)
- Singleton service quản lý AI provider config (provider, model, apiKey)
- Hỗ trợ 2 nhà cung cấp: `OpenRouter` và `Google Gemini`
- SharedPreferences keys: `ai_provider`, `ai_model`, `ai_api_key_openrouter`, `ai_api_key_google`
- Mặc định: **Provider = Google Gemini**, **Model = `models/gemma-4-31b-it`**
- Xử lý thinking model (Gemma-4): skip `parts` có `"thought": true`

**`lib/screens/ai_provider_settings_screen.dart`** (MỚI)
- Màn hình cài đặt AI Provider
- Chọn provider, model (fetch từ API), nhập API key

**`lib/screens/settings_screen.dart`** (SỬA)
- Thêm thẻ "Chọn AI" vào grid "Tính năng nhanh"

**`lib/screens/voice_order_screen.dart`** (SỬA)
- Dùng `AiProviderService` thay hardcode OpenRouter
- Thêm `TextNormalizer` cho product picker search
- Thêm nút micro trong dialog thêm sản phẩm

### Cấu trúc thư mục chính
```
lib/
├── main.dart
├── app_init.dart
├── models/          # Customer, Product, Sale, Debt ...
├── providers/       # State management (Provider pattern)
├── screens/         # Các màn hình UI
├── services/        # Business logic services
│   ├── ai_provider_service.dart
│   ├── database_service.dart
│   ├── drive_sync_service.dart
│   └── ...
├── theme/
├── utils/
│   ├── text_normalizer.dart   # Bỏ dấu tiếng Việt
│   ├── string_utils.dart      # Normalize cho AI matching
│   └── ...
└── widgets/
    └── voice_product_input_dialog.dart  ← MỚI
```

### Dependencies quan trọng
- `flutter` SDK ^3.7.2
- `provider` ^6.1.1 (state management)
- `sqflite` (local database)
- `http` ^1.2.2 (HTTP calls — dùng trong ai_provider_service)
- `shared_preferences` ^2.2.2 (local config)
- `speech_to_text` ^7.3.0 (nhận dạng giọng nói)
- `firebase_core`, `firebase_auth`, `cloud_firestore` (đăng nhập, sync)
