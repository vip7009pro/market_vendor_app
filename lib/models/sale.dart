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

  static double _parseDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  factory SaleItem.fromMap(Map<String, dynamic> map) => SaleItem(
        productId: map['productId']?.toString() ?? '',
        name: map['name']?.toString() ?? '',
        unitPrice: _parseDouble(map['unitPrice'] ?? map['unit_price']),
        unitCost: _parseDouble(map['unitCost'] ?? map['unit_cost']),
        quantity: _parseDouble(map['quantity']),
        unit: map['unit']?.toString() ?? '',
        itemType: map['itemType']?.toString() ?? map['item_type']?.toString(),
        displayName: map['displayName']?.toString() ?? map['display_name']?.toString(),
        mixItemsJson: map['mixItemsJson']?.toString() ?? map['mix_items_json']?.toString(),
      );
}

class Sale {
  final String id;
  final DateTime createdAt;
  String? customerId;
  String? customerName;
  String? employeeId;
  String? employeeName;
  List<SaleItem> items;
  double discount; // absolute amount (VND)
  double paidAmount; // amount paid now
  String? paymentType; // 'cash' | 'bank' | null
  String? note;
  double totalCost; // Thêm trường totalCost từ database

  Sale({
    String? id,
    DateTime? createdAt,
    this.customerId,
    this.customerName,
    this.employeeId,
    this.employeeName,
    required this.items,
    this.discount = 0,
    this.paidAmount = 0,
    this.paymentType,
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
        'employeeId': employeeId,
        'employeeName': employeeName,
        'items': items.map((e) => e.toMap()).toList(),
        'discount': discount,
        'paidAmount': paidAmount,
        'paymentType': paymentType,
        'note': note,
        'totalCost': totalCost, // Thêm totalCost vào map
      };

  static double _parseDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  factory Sale.fromMap(Map<String, dynamic> map) {
    final totalCost = _parseDouble(map['totalCost'] ?? map['total_cost']);
    final rawItems = map['items'];
    final itemsList = (rawItems is List)
        ? rawItems.whereType<Map>().map((e) => SaleItem.fromMap(Map<String, dynamic>.from(e))).toList()
        : <SaleItem>[];

    return Sale(
      id: map['id']?.toString() ?? '',
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now(),
      customerId: map['customerId']?.toString() ?? map['customer_id']?.toString(),
      customerName: map['customerName']?.toString() ?? map['customer_name']?.toString(),
      employeeId: map['employeeId']?.toString() ?? map['employee_id']?.toString(),
      employeeName: map['employeeName']?.toString() ?? map['employee_name']?.toString(),
      items: itemsList,
      discount: _parseDouble(map['discount']),
      paidAmount: _parseDouble(map['paidAmount'] ?? map['paid_amount']),
      paymentType: map['paymentType']?.toString() ?? map['payment_type']?.toString(),
      note: map['note']?.toString(),
      totalCost: totalCost,
    );
  }
}