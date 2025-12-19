import 'package:uuid/uuid.dart';

class SaleItem {
  final String productId;
  String name;
  double unitPrice;
  double unitCost; // Add unit cost field
  double quantity;
  String unit;
  String? itemType;
  String? displayName;
  String? mixItemsJson;

  SaleItem({
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.unitCost,
    required this.quantity,
    required this.unit,
    this.itemType,
    this.displayName,
    this.mixItemsJson,
  });

  double get total => unitPrice * quantity;
  double get totalCost => unitCost * quantity;

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'name': name,
        'unitPrice': unitPrice,
        'unitCost': unitCost,
        'quantity': quantity,
        'unit': unit,
        'itemType': itemType,
        'displayName': displayName,
        'mixItemsJson': mixItemsJson,
      };

  factory SaleItem.fromMap(Map<String, dynamic> map) => SaleItem(
        productId: map['productId'],
        name: map['name'],
        unitPrice: (map['unitPrice'] as num).toDouble(),
        unitCost: (map['unitCost'] as num?)?.toDouble() ?? 0.0,
        quantity: (map['quantity'] as num).toDouble(),
        unit: map['unit'],
        itemType: map['itemType']?.toString(),
        displayName: map['displayName']?.toString(),
        mixItemsJson: map['mixItemsJson']?.toString(),
      );
}

class Sale {
  final String id;
  final DateTime createdAt;
  String? customerId;
  String? customerName;
  List<SaleItem> items;
  double discount; // absolute amount (VND)
  double paidAmount; // amount paid now
  String? note;
  double totalCost; // Thêm trường totalCost từ database

  Sale({
    String? id,
    DateTime? createdAt,
    this.customerId,
    this.customerName,
    required this.items,
    this.discount = 0,
    this.paidAmount = 0,
    this.note,
    this.totalCost = 0.0, // Đảm bảo giá trị mặc định là 0.0
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  double get subtotal => items.fold(0, (p, e) => p + e.total);
  double get total => (subtotal - discount).clamp(0, double.infinity);
  double get debt => (total - paidAmount).clamp(0, double.infinity);
  // Sử dụng totalCost từ database thay vì tính lại
  // double get totalCost => items.fold(0, (p, e) => p + (e.unitCost * e.quantity));

  Map<String, dynamic> toMap() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'customerId': customerId,
        'customerName': customerName,
        'items': items.map((e) => e.toMap()).toList(),
        'discount': discount,
        'paidAmount': paidAmount,
        'note': note,
        'totalCost': totalCost, // Thêm totalCost vào map
      };

  factory Sale.fromMap(Map<String, dynamic> map) {
    // Kiểm tra và xử lý null cho totalCost
    final totalCostValue = map['totalCost'];
    final totalCost = totalCostValue != null ? (totalCostValue as num).toDouble() : 0.0;

    return Sale(
      id: map['id'],
      createdAt: DateTime.parse(map['createdAt']),
      customerId: map['customerId'],
      customerName: map['customerName'],
      items: (map['items'] as List).map((e) => SaleItem.fromMap(e)).toList(),
      discount: (map['discount'] as num).toDouble(),
      paidAmount: (map['paidAmount'] as num).toDouble(),
      note: map['note'],
      totalCost: totalCost, // Sử dụng giá trị đã kiểm tra
    );
  }
}