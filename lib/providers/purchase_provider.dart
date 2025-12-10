import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../services/in_app_purchase_service.dart';

/// Provider for managing in-app purchase state
class PurchaseProvider with ChangeNotifier {
  final InAppPurchaseService _purchaseService = InAppPurchaseService();

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  bool get isStoreAvailable => _purchaseService.isAvailable;
  bool get isPremiumUser => _purchaseService.isPremiumUser;
  bool get purchasePending => _purchaseService.purchasePending;
  List<ProductDetails> get products => _purchaseService.products;
  String? get queryProductError => _purchaseService.queryProductError;

  String? _lastError;
  String? get lastError => _lastError;

  String? _lastSuccessMessage;
  String? get lastSuccessMessage => _lastSuccessMessage;

  /// Initialize the purchase provider
  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('PurchaseProvider already initialized');
      return;
    }

    debugPrint('Initializing PurchaseProvider...');
    
    // Set up callbacks
    _purchaseService.onPurchaseSuccess = _handlePurchaseSuccess;
    _purchaseService.onPurchaseError = _handlePurchaseError;
    _purchaseService.onPurchaseUpdate = () {
      notifyListeners();
    };

    // Initialize the service
    await _purchaseService.initialize();
    
    _isInitialized = true;
    notifyListeners();
    debugPrint('PurchaseProvider initialized');
  }

  /// Handle successful purchase
  void _handlePurchaseSuccess(PurchaseDetails purchaseDetails) {
    debugPrint('Purchase successful: ${purchaseDetails.productID}');
    _lastError = null;
    _lastSuccessMessage = 'Mua hàng thành công! Bạn đã mở khóa tính năng premium.';
    notifyListeners();
  }

  /// Handle purchase error
  void _handlePurchaseError(String error) {
    debugPrint('Purchase error: $error');
    _lastError = error;
    _lastSuccessMessage = null;
    notifyListeners();
  }

  /// Clear messages
  void clearMessages() {
    _lastError = null;
    _lastSuccessMessage = null;
    notifyListeners();
  }

  /// Purchase a product
  Future<bool> purchaseProduct(ProductDetails product) async {
    clearMessages();
    return await _purchaseService.purchaseProduct(product);
  }

  /// Restore purchases
  Future<void> restorePurchases() async {
    clearMessages();
    await _purchaseService.restorePurchases();
    notifyListeners();
  }

  /// Reload products
  Future<void> reloadProducts() async {
    await _purchaseService.loadProducts();
    notifyListeners();
  }

  /// Check premium status
  Future<bool> checkPremiumStatus() async {
    final status = await _purchaseService.checkPremiumStatus();
    notifyListeners();
    return status;
  }

  /// Get product by ID
  ProductDetails? getProductById(String productId) {
    return _purchaseService.getProductById(productId);
  }

  /// Get the backup/restore product
  ProductDetails? get backupRestoreProduct {
    return getProductById(InAppPurchaseService.premiumBackupProductId);
  }

  /// Get monthly subscription product
  ProductDetails? get monthlyProduct {
    return getProductById(InAppPurchaseService.premiumMonthlyProductId);
  }

  /// Get yearly subscription product
  ProductDetails? get yearlyProduct {
    return getProductById(InAppPurchaseService.premiumYearlyProductId);
  }

  @override
  void dispose() {
    _purchaseService.dispose();
    super.dispose();
  }
}
