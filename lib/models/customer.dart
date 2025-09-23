import 'package:uuid/uuid.dart';

class Customer {
  final String id;
  String name;
  String? phone;
  String? note;
  bool isSupplier; // true: supplier (tôi nợ); false: customer (nợ tôi)

  Customer({
    String? id,
    required this.name,
    this.phone,
    this.note,
    this.isSupplier = false,
  }) : id = id ?? const Uuid().v4();

  factory Customer.fromMap(Map<String, dynamic> map) => Customer(
        id: map['id'],
        name: map['name'],
        phone: map['phone'],
        note: map['note'],
        isSupplier: map['isSupplier'] == 1 || map['isSupplier'] == true,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'note': note,
        'isSupplier': isSupplier ? 1 : 0,
      };
}
