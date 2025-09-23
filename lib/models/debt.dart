import 'package:uuid/uuid.dart';

enum DebtType {
  oweOthers, // Tiền tôi nợ (to suppliers)
  othersOweMe, // Tiền nợ tôi (from customers)
}

class Debt {
  final String id;
  final DateTime createdAt;
  DebtType type;
  String partyId; // customer or supplier id
  String partyName;
  double amount;
  String? description;
  DateTime? dueDate;
  bool settled;

  Debt({
    String? id,
    DateTime? createdAt,
    required this.type,
    required this.partyId,
    required this.partyName,
    required this.amount,
    this.description,
    this.dueDate,
    this.settled = false,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();
}
