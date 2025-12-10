import 'dart:async';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to handle in-app purchases for premium features
class InAppPurchaseService {
  static final InAppPurchaseService _instance = InAppPurchaseService._internal();
  factory InAppPurchaseService() => _instance;
  InAppPurchaseService._internal();

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  
  // Product IDs - Replace these with your actual product IDs from Google Play Console / App Store Connect
  static const String premiumBackupProductId = 'unlock_backup_restore';
  static const String premiumMonthlyProductId = 'premium_monthly';
  static const String premiumYearlyProductId = 'premium_yearly';
  
  // All available product IDs
  static const Set<String> _productIds = {
    premiumBackupProductId,
    premiumMonthlyProductId,
    premiumYearlyProductId,
  };

  // Available products
  List<ProductDetails> _products = [];
  List<ProductDetails> get products => _products;

  // Purchase status
  bool _isAvailable = false;
  bool get isAvailable => _isAvailable;

  bool _purchasePending = false;
  bool get purchasePending => _purchasePending;

  String? _queryProductError;
  String? get queryProductError => _queryProductError;

  // Premium status
  bool _isPremiumUser = false;
  bool get isPremiumUser => _isPremiumUser;

  // Callbacks
  Function(PurchaseDetails)? onPurchaseSuccess;
  Function(String)? onPurchaseError;
  Function()? onPurchaseUpdate;

  /// Initialize the in-app purchase service
  Future<void> initialize() async {
    debugPrint('Initializing InAppPurchaseService...');
    
    // Check if the store is available
    _isAvailable = await _inAppPurchase.isAvailable();
    debugPrint('Store available: $_isAvailable');

    if (!_isAvailable) {
      debugPrint('In-app purchase not available on this device');
      return;
    }

    // Listen to purchase updates
    _subscription = _inAppPurchase.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () {
        debugPrint('Purchase stream done');
        _subscription.cancel();
      },
      onError: (error) {
        debugPrint('Purchase stream error: $error');
      },
    );

    // Load products
    await loadProducts();
    
    // Restore previous purchases
    await restorePurchases();
  }

  /// Load available products from the store
  Future<void> loadProducts() async {
    if (!_isAvailable) {
      debugPrint('Store not available, cannot load products');
      return;
    }

    debugPrint('Loading products: $_productIds');
    final ProductDetailsResponse response = await _inAppPurchase.queryProductDetails(_productIds);

    if (response.notFoundIDs.isNotEmpty) {
      debugPrint('Products not found: ${response.notFoundIDs}');
      _queryProductError = 'Một số sản phẩm không tìm thấy: ${response.notFoundIDs.join(", ")}';
    }

    if (response.error != null) {
      debugPrint('Error loading products: ${response.error}');
      _queryProductError = response.error!.message;
      return;
    }

    _products = response.productDetails;
    debugPrint('Loaded ${_products.length} products');
    for (var product in _products) {
      debugPrint('Product: ${product.id} - ${product.title} - ${product.price}');
    }
  }

  /// Purchase a product
  Future<bool> purchaseProduct(ProductDetails product) async {
    if (!_isAvailable) {
      onPurchaseError?.call('Cửa hàng không khả dụng');
      return false;
    }

    debugPrint('Purchasing product: ${product.id}');
    _purchasePending = true;
    onPurchaseUpdate?.call();

    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
    
    try {
      bool success;
      if (product.id == premiumBackupProductId || 
          product.id == premiumMonthlyProductId || 
          product.id == premiumYearlyProductId) {
        // Non-consumable or subscription purchase
        success = await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
      } else {
        success = await _inAppPurchase.buyConsumable(purchaseParam: purchaseParam);
      }
      
      if (!success) {
        _purchasePending = false;
        onPurchaseUpdate?.call();
        onPurchaseError?.call('Không thể bắt đầu giao dịch mua hàng');
      }
      
      return success;
    } catch (e) {
      debugPrint('Error purchasing product: $e');
      _purchasePending = false;
      onPurchaseUpdate?.call();
      onPurchaseError?.call('Lỗi khi mua: $e');
      return false;
    }
  }

  /// Handle purchase updates from the stream
  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) async {
    debugPrint('Purchase update received: ${purchaseDetailsList.length} items');
    
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      debugPrint('Processing purchase: ${purchaseDetails.productID} - ${purchaseDetails.status}');
      
      if (purchaseDetails.status == PurchaseStatus.pending) {
        _purchasePending = true;
        onPurchaseUpdate?.call();
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          debugPrint('Purchase error: ${purchaseDetails.error}');
          _purchasePending = false;
          onPurchaseError?.call(purchaseDetails.error?.message ?? 'Lỗi không xác định');
          onPurchaseUpdate?.call();
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
                   purchaseDetails.status == PurchaseStatus.restored) {
          // Verify purchase (in production, verify with your backend)
          final bool valid = await _verifyPurchase(purchaseDetails);
          
          if (valid) {
            debugPrint('Purchase verified successfully');
            await _deliverProduct(purchaseDetails);
            _purchasePending = false;
            onPurchaseSuccess?.call(purchaseDetails);
            onPurchaseUpdate?.call();
          } else {
            debugPrint('Purchase verification failed');
            _purchasePending = false;
            onPurchaseError?.call('Xác minh giao dịch thất bại');
            onPurchaseUpdate?.call();
          }
        }

        // Complete the purchase
        if (purchaseDetails.pendingCompletePurchase) {
          debugPrint('Completing purchase: ${purchaseDetails.productID}');
          await _inAppPurchase.completePurchase(purchaseDetails);
        }
      }
    }
  }

  /// Verify purchase (implement backend verification in production)
  Future<bool> _verifyPurchase(PurchaseDetails purchaseDetails) async {
    // TODO: In production, send the purchase details to your backend for verification
    // For now, we'll just return true for demo purposes
    debugPrint('Verifying purchase: ${purchaseDetails.productID}');
    
    // Simulate verification delay
    await Future.delayed(const Duration(milliseconds: 500));
    
    return true;
  }

  /// Deliver the purchased product
  Future<void> _deliverProduct(PurchaseDetails purchaseDetails) async {
    debugPrint('Delivering product: ${purchaseDetails.productID}');
    
    // Save purchase status to local storage
    final prefs = await SharedPreferences.getInstance();
    
    if (purchaseDetails.productID == premiumBackupProductId ||
        purchaseDetails.productID == premiumMonthlyProductId ||
        purchaseDetails.productID == premiumYearlyProductId) {
      await prefs.setBool('is_premium_user', true);
      await prefs.setString('premium_product_id', purchaseDetails.productID);
      await prefs.setString('purchase_date', DateTime.now().toIso8601String());
      _isPremiumUser = true;
      debugPrint('Premium status activated');
    }
  }

  /// Restore previous purchases
  Future<void> restorePurchases() async {
    if (!_isAvailable) {
      debugPrint('Store not available, cannot restore purchases');
      return;
    }

    debugPrint('Restoring purchases...');
    
    try {
      await _inAppPurchase.restorePurchases();
      
      // Also check local storage
      final prefs = await SharedPreferences.getInstance();
      _isPremiumUser = prefs.getBool('is_premium_user') ?? false;
      debugPrint('Premium status from local storage: $_isPremiumUser');
    } catch (e) {
      debugPrint('Error restoring purchases: $e');
      onPurchaseError?.call('Lỗi khi khôi phục giao dịch: $e');
    }
  }

  /// Check if user has premium access
  Future<bool> checkPremiumStatus() async {
    final prefs = await SharedPreferences.getInstance();
    _isPremiumUser = prefs.getBool('is_premium_user') ?? false;
    return _isPremiumUser;
  }

  /// Get product by ID
  ProductDetails? getProductById(String productId) {
    try {
      return _products.firstWhere((product) => product.id == productId);
    } catch (e) {
      return null;
    }
  }

  /// Dispose the service
  void dispose() {
    debugPrint('Disposing InAppPurchaseService');
    _subscription.cancel();
  }
}

