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

### Dependencies quan trọng
- `flutter` SDK ^3.7.2
- `provider` ^6.1.1 (state management)
- `sqflite` (local database)
- `http` ^1.2.2 (HTTP calls — dùng trong ai_provider_service)
- `shared_preferences` ^2.2.2 (local config)
- `speech_to_text` ^7.3.0 (nhận dạng giọng nói)
- `firebase_core`, `firebase_auth`, `cloud_firestore` (đăng nhập, sync)
- `image_picker` (chụp/chọn ảnh sản phẩm)
- `intl` (format số, ngày)
