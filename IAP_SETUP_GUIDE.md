# Hướng dẫn cấu hình In-App Purchase (IAP)

## Tổng quan
Ứng dụng đã được tích hợp tính năng mua hàng trong ứng dụng (In-App Purchase) để mở khóa các tính năng premium như:
- Sao lưu dữ liệu lên Google Drive
- Khôi phục dữ liệu từ Google Drive
- Đồng bộ tự động
- Hỗ trợ ưu tiên

## Cấu trúc code

### 1. Service Layer
- **File**: `lib/services/in_app_purchase_service.dart`
- **Chức năng**: Quản lý kết nối với Google Play Store/App Store, xử lý giao dịch mua hàng

### 2. Provider Layer
- **File**: `lib/providers/purchase_provider.dart`
- **Chức năng**: Quản lý state của IAP, cung cấp interface cho UI

### 3. UI Integration
- **File**: `lib/screens/settings_screen.dart`
- **Chức năng**: Hiển thị trạng thái premium, dialog mua hàng, kiểm tra quyền truy cập

## Cấu hình Google Play Console

### Bước 1: Tạo sản phẩm IAP

1. Đăng nhập vào [Google Play Console](https://play.google.com/console)
2. Chọn ứng dụng của bạn
3. Vào **Monetize** > **In-app products**
4. Tạo các sản phẩm sau:

#### Sản phẩm 1: Premium Backup & Restore (One-time purchase)
- **Product ID**: `premium_backup_restore`
- **Name**: Premium Backup & Restore
- **Description**: Mở khóa tính năng sao lưu và khôi phục dữ liệu lên Google Drive
- **Price**: Tự chọn (ví dụ: 49,000 VND)
- **Status**: Active

#### Sản phẩm 2: Premium Monthly (Subscription - Optional)
- **Product ID**: `premium_monthly`
- **Name**: Premium Monthly Subscription
- **Description**: Gói premium hàng tháng với tất cả tính năng
- **Price**: Tự chọn (ví dụ: 29,000 VND/tháng)
- **Billing period**: 1 month
- **Status**: Active

#### Sản phẩm 3: Premium Yearly (Subscription - Optional)
- **Product ID**: `premium_yearly`
- **Name**: Premium Yearly Subscription
- **Description**: Gói premium hàng năm với tất cả tính năng (tiết kiệm hơn)
- **Price**: Tự chọn (ví dụ: 299,000 VND/năm)
- **Billing period**: 1 year
- **Status**: Active

### Bước 2: Cấu hình License Testing

1. Vào **Setup** > **License testing**
2. Thêm email tài khoản Google để test
3. Chọn license response: **RESPOND_NORMALLY**

### Bước 3: Tạo Closed Testing Track

1. Vào **Testing** > **Closed testing**
2. Tạo track mới hoặc sử dụng Internal testing
3. Upload APK/AAB đã build
4. Thêm tester vào danh sách

## Cấu hình App Store Connect (iOS)

### Bước 1: Tạo In-App Purchase

1. Đăng nhập vào [App Store Connect](https://appstoreconnect.apple.com)
2. Chọn app của bạn
3. Vào **Features** > **In-App Purchases**
4. Tạo các sản phẩm tương tự như trên Google Play

### Bước 2: Sandbox Testing

1. Vào **Users and Access** > **Sandbox Testers**
2. Tạo tài khoản sandbox để test

## Testing

### Test trên Android

1. Build và upload APK lên Internal Testing:
   ```bash
   flutter build appbundle --release
   ```

2. Cài đặt app từ Internal Testing track

3. Đăng nhập bằng tài khoản test đã thêm trong License Testing

4. Thử mua sản phẩm - sẽ không bị charge tiền thật

### Test trên iOS

1. Build app:
   ```bash
   flutter build ios --release
   ```

2. Cài đặt qua TestFlight

3. Đăng xuất tài khoản App Store thật

4. Khi mua hàng, đăng nhập bằng Sandbox account

## Cập nhật Product IDs

Nếu bạn muốn thay đổi Product IDs, cập nhật trong file:
`lib/services/in_app_purchase_service.dart`

```dart
// Product IDs
static const String premiumBackupProductId = 'your_product_id_here';
static const String premiumMonthlyProductId = 'your_monthly_id_here';
static const String premiumYearlyProductId = 'your_yearly_id_here';
```

## Xác thực giao dịch (Production)

⚠️ **QUAN TRỌNG**: Trong production, bạn cần implement backend verification để xác thực giao dịch.

Cập nhật method `_verifyPurchase` trong `in_app_purchase_service.dart`:

```dart
Future<bool> _verifyPurchase(PurchaseDetails purchaseDetails) async {
  // TODO: Send to your backend for verification
  final response = await http.post(
    Uri.parse('https://your-backend.com/verify-purchase'),
    body: {
      'purchaseToken': purchaseDetails.verificationData.serverVerificationData,
      'productId': purchaseDetails.productID,
    },
  );
  
  return response.statusCode == 200;
}
```

## Lưu ý

1. **Không hardcode giá**: Luôn lấy giá từ store thông qua `ProductDetails.price`

2. **Xử lý restore purchases**: App đã tự động restore purchases khi khởi động

3. **Kiểm tra kết nối**: App kiểm tra `isAvailable` trước khi hiển thị IAP

4. **Local storage**: Trạng thái premium được lưu trong SharedPreferences

5. **Testing**: Luôn test kỹ trên cả Android và iOS trước khi release

## Troubleshooting

### Lỗi "Product not found"
- Kiểm tra Product ID có đúng không
- Đảm bảo sản phẩm đã được Active trong console
- Đợi vài giờ sau khi tạo sản phẩm mới

### Lỗi "Store not available"
- Kiểm tra thiết bị có kết nối internet
- Đảm bảo Google Play Services được cài đặt (Android)
- Kiểm tra app đã được upload lên testing track

### Purchase không hoàn thành
- Kiểm tra log để xem lỗi cụ thể
- Đảm bảo `completePurchase()` được gọi
- Kiểm tra tài khoản test có hợp lệ

## Hỗ trợ

Tham khảo thêm:
- [Flutter In-App Purchase Plugin](https://pub.dev/packages/in_app_purchase)
- [Google Play Billing](https://developer.android.com/google/play/billing)
- [Apple In-App Purchase](https://developer.apple.com/in-app-purchase/)
