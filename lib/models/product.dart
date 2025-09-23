import 'package:uuid/uuid.dart';

class Product {
  final String id;
  String name;
  double price;
  String unit; // e.g., kg, cái, bó
  String? barcode;
  bool isActive;

  Product({
    String? id,
    required this.name,
    required this.price,
    required this.unit,
    this.barcode,
    this.isActive = true,
  }) : id = id ?? const Uuid().v4();

  factory Product.fromMap(Map<String, dynamic> map) => Product(
        id: map['id'],
        name: map['name'],
        price: (map['price'] as num).toDouble(),
        unit: map['unit'],
        barcode: map['barcode'],
        isActive: map['isActive'] == 1 || map['isActive'] == true,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'price': price,
        'unit': unit,
        'barcode': barcode,
        'isActive': isActive ? 1 : 0,
      };
}
