import 'package:uuid/uuid.dart';

enum ProductItemType { raw, mix }

class Product {
  final String id;
  String name;
  double price;
  double costPrice; // Giá vốn
  double currentStock; // Tồn hiện tại
  String unit; // e.g., kg, cái, bó
  String? barcode;
  String? imagePath;
  bool isActive;
  ProductItemType itemType;
  bool isStocked;

  Product({
    String? id,
    required this.name,
    required this.price,
    this.costPrice = 0, // Giá vốn mặc định là 0
    this.currentStock = 0, // Tồn hiện tại mặc định là 0
    required this.unit,
    this.barcode,
    this.imagePath,
    this.isActive = true,
    this.itemType = ProductItemType.raw,
    bool? isStocked,
  })  : id = id ?? const Uuid().v4(),
        isStocked = isStocked ?? true;

  static ProductItemType _parseItemType(dynamic v) {
    final s = (v?.toString() ?? '').toUpperCase().trim();
    if (s == 'MIX') return ProductItemType.mix;
    return ProductItemType.raw;
  }

  static String _itemTypeToDb(ProductItemType t) {
    switch (t) {
      case ProductItemType.mix:
        return 'MIX';
      case ProductItemType.raw:
        return 'RAW';
    }
  }

  static double _parseDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  factory Product.fromMap(Map<String, dynamic> map) => Product(
        id: map['id']?.toString() ?? '',
        name: map['name']?.toString() ?? '',
        price: _parseDouble(map['price']),
        costPrice: _parseDouble(map['costPrice'] ?? map['cost_price']),
        currentStock: _parseDouble(map['currentStock'] ?? map['current_stock']),
        unit: map['unit']?.toString() ?? '',
        barcode: map['barcode']?.toString(),
        imagePath: map['imagePath']?.toString() ?? map['image_path']?.toString(),
        isActive: map['isActive'] == 1 || map['isActive'] == true || map['isActive'] == '1',
        itemType: _parseItemType(map['itemType'] ?? map['item_type']),
        isStocked: map['isStocked'] == null ? true : (map['isStocked'] == 1 || map['isStocked'] == true || map['isStocked'] == '1'),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'price': price,
        'costPrice': costPrice,
        'currentStock': currentStock,
        'unit': unit,
        'barcode': barcode,
        'imagePath': imagePath,
        'isActive': isActive ? 1 : 0,
        'itemType': _itemTypeToDb(itemType),
        'isStocked': isStocked ? 1 : 0,
      };
}
