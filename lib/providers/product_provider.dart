import 'package:flutter/foundation.dart';
import '../models/product.dart';
import '../services/database_service.dart';
import 'package:string_similarity/string_similarity.dart';
import '../utils/string_utils.dart';

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

  // Tìm sản phẩm theo tên (không phân biệt hoa thường, dấu)
Product? findByName(String name, {double threshold = 0.5}) {
  if (name.isEmpty) return null;
    
  final normalizedSearch = StringUtils.normalize(name);
    
  // Nếu tìm thấy kết quả chính xác thì trả về luôn
  try {
    return _products.firstWhere(
      (p) => StringUtils.normalize(p.name) == normalizedSearch,
    );
  } catch (_) {
    // Nếu không tìm thấy chính xác, sử dụng fuzzy matching
    if (_products.isEmpty) return null;
      
    // Tìm sản phẩm có tên giống nhất
    final matches = _products.map((p) {
      print('search:'+ normalizedSearch + ', productname: '+ StringUtils.normalize(p.name));
      final similarity = StringSimilarity.compareTwoStrings(
        normalizedSearch, 
        StringUtils.normalize(p.name)
      );
      return {'product': p, 'similarity': similarity};
    }).toList()
      ..sort((a, b) => (b['similarity'] as double).compareTo(a['similarity'] as double));
    // Lấy kết quả có độ tương đồng cao nhất
    final bestMatch = matches.first;
    if ((bestMatch['similarity'] as double) >= threshold) {
      return bestMatch['product'] as Product;
    }
      
    return null;
  }
}
}