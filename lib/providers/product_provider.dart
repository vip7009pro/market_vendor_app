import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../services/database_service.dart';

class ProductProvider with ChangeNotifier {
  final List<Product> _products = [];

  List<Product> get products => List.unmodifiable(_products);

  Future<void> load() async {
    final data = await DatabaseService.instance.getProducts();
    _products
      ..clear()
      ..addAll(data);
    notifyListeners();
  }

  Future<void> add(Product p) async {
    _products.add(p);
    notifyListeners();
    await DatabaseService.instance.insertProduct(p);
  }

  Future<void> update(Product p) async {
    final idx = _products.indexWhere((e) => e.id == p.id);
    if (idx != -1) {
      _products[idx] = p;
      notifyListeners();
      await DatabaseService.instance.updateProduct(p);
    }
  }

  Future<void> delete(String productId) async {
    _products.removeWhere((p) => p.id == productId);
    notifyListeners();
    await DatabaseService.instance.deleteProductHard(productId);
  }

  Product? findByBarcode(String barcode) {
    try {
      return _products.firstWhere((e) => e.barcode == barcode);
    } catch (_) {
      return null;
    }
  }
}
