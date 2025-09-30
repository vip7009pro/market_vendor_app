import 'package:uuid/uuid.dart';

class Product {
  final String id;
  String name;
  double price;
  double costPrice; // Giá vốn
  String unit; // e.g., kg, cái, bó
  String? barcode;
  bool isActive;

  Product({
    String? id,
    required this.name,
    required this.price,
    this.costPrice = 0, // Giá vốn mặc định là 0
    required this.unit,
    this.barcode,
    this.isActive = true,
  }) : id = id ?? const Uuid().v4();

  factory Product.fromMap(Map<String, dynamic> map) => Product(
        id: map['id'],
        name: map['name'],
        price: (map['price'] as num).toDouble(),
        costPrice: map['costPrice'] != null ? (map['costPrice'] as num).toDouble() : 0,
        unit: map['unit'],
        barcode: map['barcode'],
        isActive: map['isActive'] == 1 || map['isActive'] == true,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'price': price,
        'costPrice': costPrice,
        'unit': unit,
        'barcode': barcode,
        'isActive': isActive ? 1 : 0,
      };
}
