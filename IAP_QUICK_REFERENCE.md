# In-App Purchase - Quick Reference

## 🚀 Cách sử dụng trong code

### Kiểm tra user có premium không

```dart
final purchaseProvider = context.read<PurchaseProvider>();
if (purchaseProvider.isPremiumUser) {
  // User có premium, cho phép sử dụng tính năng
} else {
  // User chưa có premium, hiển thị dialog nâng cấp
}
```

### Hiển thị dialog mua hàng

```dart
// Trong Settings Screen đã có sẵn method
await _showPurchaseDialog(context);

// Hoặc tự implement
final product = purchaseProvider.backupRestoreProduct;
if (product != null) {
  await purchaseProvider.purchaseProduct(product);
}
```

### Kiểm tra và yêu cầu premium

```dart
// Trong Settings Screen đã có sẵn method
final hasPremium = await _checkPremiumAccess(context);
if (hasPremium) {
  // Thực hiện tính năng premium
}
```

### Restore purchases

```dart
final purchaseProvider = context.read<PurchaseProvider>();
await purchaseProvider.restorePurchases();
```

## 📦 Product IDs

```dart
// Trong InAppPurchaseService
static const String premiumBackupProductId = 'premium_backup_restore';
static const String premiumMonthlyProductId = 'premium_monthly';
static const String premiumYearlyProductId = 'premium_yearly';
```

## 🎯 Key Properties

```dart
// PurchaseProvider
purchaseProvider.isPremiumUser          // bool - User có premium không
purchaseProvider.isStoreAvailable       // bool - Store có sẵn không
purchaseProvider.purchasePending        // bool - Đang xử lý giao dịch
purchaseProvider.products               // List<ProductDetails> - Danh sách sản phẩm
purchaseProvider.lastError              // String? - Lỗi gần nhất
purchaseProvider.lastSuccessMessage     // String? - Thông báo thành công
```

## 🔧 Common Tasks

### Thêm tính năng premium mới

1. Kiểm tra premium trong method:
```dart
Future<void> myPremiumFeature() async {
  final purchaseProvider = context.read<PurchaseProvider>();
  
  if (!purchaseProvider.isPremiumUser) {
    // Hiển thị dialog yêu cầu nâng cấp
    final shouldUpgrade = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tính năng Premium'),
        content: const Text('Tính năng này yêu cầu tài khoản Premium'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Nâng cấp'),
          ),
        ],
      ),
    );
    
    if (shouldUpgrade == true) {
      await _showPurchaseDialog(context);
    }
    return;
  }
  
  // Thực hiện tính năng premium
  // ...
}
```

2. Thêm visual indicator (badge, icon, etc.):
```dart
ListTile(
  title: const Text('My Premium Feature'),
  trailing: purchaseProvider.isPremiumUser 
    ? const Icon(Icons.check_circle, color: Colors.green)
    : const Icon(Icons.lock_outline),
  onTap: () => myPremiumFeature(),
)
```

### Thay đổi Product ID

1. Mở `lib/services/in_app_purchase_service.dart`
2. Sửa constants:
```dart
static const String premiumBackupProductId = 'your_new_product_id';
```
3. Tạo sản phẩm tương ứng trong Google Play Console / App Store Connect

### Debug IAP

1. Enable debug logging:
```dart
// Trong InAppPurchaseService
debugPrint('Purchase update: $purchaseDetails');
```

2. Check store availability:
```dart
final purchaseProvider = context.read<PurchaseProvider>();
print('Store available: ${purchaseProvider.isStoreAvailable}');
print('Products loaded: ${purchaseProvider.products.length}');
```

3. Check premium status:
```dart
final isPremium = await purchaseProvider.checkPremiumStatus();
print('Is premium user: $isPremium');
```

## 🐛 Common Issues

### Issue: "Product not found"
**Solution**: 
- Đợi vài giờ sau khi tạo product
- Kiểm tra Product ID đúng chính xác
- Đảm bảo product đã Active

### Issue: "Store not available"
**Solution**:
- Kiểm tra internet connection
- Đảm bảo Google Play Services installed (Android)
- Test trên real device, không phải emulator

### Issue: Purchase không complete
**Solution**:
- Check `completePurchase()` được gọi
- Check log để xem error message
- Verify tài khoản test hợp lệ

### Issue: Premium status không persist
**Solution**:
- Check SharedPreferences có lưu được không
- Call `restorePurchases()` khi app start
- Verify purchase được deliver đúng

## 📱 Testing Checklist

- [ ] Test mua sản phẩm lần đầu
- [ ] Test restore purchases
- [ ] Test khi mất mạng
- [ ] Test cancel purchase
- [ ] Test với tài khoản test
- [ ] Test trên real device
- [ ] Test premium features hoạt động đúng
- [ ] Test UI update sau khi mua
- [ ] Test app restart vẫn giữ premium status

## 🔐 Security Checklist

- [ ] Verify purchases trên server (production)
- [ ] Không hardcode sensitive data
- [ ] Encrypt local storage data
- [ ] Implement proper error handling
- [ ] Log purchases cho audit trail
- [ ] Handle refunds properly

## 📊 Analytics Events (Recommended)

```dart
// Track khi user xem purchase dialog
analytics.logEvent(name: 'view_premium_offer');

// Track khi user bắt đầu purchase
analytics.logEvent(name: 'begin_checkout', parameters: {
  'product_id': product.id,
  'price': product.price,
});

// Track khi purchase thành công
analytics.logEvent(name: 'purchase', parameters: {
  'product_id': purchaseDetails.productID,
  'transaction_id': purchaseDetails.purchaseID,
});

// Track khi user restore purchases
analytics.logEvent(name: 'restore_purchases');
```

## 🎨 UI Components

### Premium Badge
```dart
Widget buildPremiumBadge() {
  return Consumer<PurchaseProvider>(
    builder: (context, purchaseProvider, _) {
      if (!purchaseProvider.isPremiumUser) return const SizedBox();
      
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.amber,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.workspace_premium, size: 16, color: Colors.white),
            SizedBox(width: 4),
            Text('PREMIUM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    },
  );
}
```

### Lock Overlay
```dart
Widget buildFeatureWithLock({
  required Widget child,
  required bool isPremium,
  required VoidCallback onUpgrade,
}) {
  return Stack(
    children: [
      child,
      if (!isPremium)
        Positioned.fill(
          child: Container(
            color: Colors.black54,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock, size: 48, color: Colors.white),
                  const SizedBox(height: 8),
                  const Text('Tính năng Premium', style: TextStyle(color: Colors.white)),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: onUpgrade,
                    child: const Text('Nâng cấp'),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}
```

## 📞 Support

- **Documentation**: `IAP_SETUP_GUIDE.md`
- **Implementation**: `IAP_IMPLEMENTATION_SUMMARY.md`
- **Flutter Plugin**: https://pub.dev/packages/in_app_purchase
