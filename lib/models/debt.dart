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
  double initialAmount;
  double amount;
  String? description;
  DateTime? dueDate;
  bool settled;
  String? sourceType; // 'sale' | 'purchase'
  String? sourceId; // id of sale or purchase_history

  Debt({
    String? id,
    DateTime? createdAt,
    required this.type,
    required this.partyId,
    required this.partyName,
    double? initialAmount,
    required this.amount,
    this.description,
    this.dueDate,
    this.settled = false,
    this.sourceType,
    this.sourceId,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        initialAmount = initialAmount ?? amount;

  static double _parseDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  factory Debt.fromMap(Map<String, dynamic> map) {
    final t = (map['type'] is num) ? (map['type'] as num).toInt() : int.tryParse(map['type']?.toString() ?? '0') ?? 0;
    final debtType = (t == 0) ? DebtType.oweOthers : DebtType.othersOweMe;
    final amountVal = _parseDouble(map['amount']);
    final initialVal = (map['initialAmount'] != null || map['initial_amount'] != null)
        ? _parseDouble(map['initialAmount'] ?? map['initial_amount'])
        : amountVal;

    return Debt(
      id: map['id']?.toString() ?? '',
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now(),
      type: debtType,
      partyId: map['partyId']?.toString() ?? map['party_id']?.toString() ?? '',
      partyName: map['partyName']?.toString() ?? map['party_name']?.toString() ?? '',
      initialAmount: initialVal,
      amount: amountVal,
      description: map['description']?.toString(),
      dueDate: map['dueDate'] != null ? DateTime.tryParse(map['dueDate'].toString()) : null,
      settled: map['settled'] == 1 || map['settled'] == true || map['settled'] == '1',
      sourceType: map['sourceType']?.toString() ?? map['source_type']?.toString(),
      sourceId: map['sourceId']?.toString() ?? map['source_id']?.toString(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'type': type == DebtType.oweOthers ? 0 : 1,
        'partyId': partyId,
        'partyName': partyName,
        'initialAmount': initialAmount,
        'amount': amount,
        'description': description,
        'dueDate': dueDate?.toIso8601String(),
        'settled': settled,
        'sourceType': sourceType,
        'sourceId': sourceId,
      };
}
