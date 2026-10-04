import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/product.dart';
import '../models/customer.dart';
import '../models/sale.dart';
import '../models/debt.dart';
import 'encryption_service.dart';
import 'online_api_service.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._();
  DatabaseService._();

  Database? _db;
  Database get db => _db!;
  String? _deviceId;
  final Uuid _uuid = const Uuid();

  static bool _isOnlineMode = false;
  bool get isOnlineMode => _isOnlineMode;
  String get currentDbFileName => _isOnlineMode ? 'market_vendor_online.db' : 'market_vendor.db';
  
  // Lấy ID của thiết bị
  Future<String> get deviceId async {
    if (_deviceId == null) {
      final deviceInfo = DeviceInfoPlugin();
      try {
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          _deviceId = androidInfo.id;
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          _deviceId = iosInfo.identifierForVendor ?? _uuid.v4();
        } else {
          _deviceId = _uuid.v4();
        }
      } catch (e) {
        _deviceId = _uuid.v4();
      }
    }
    return _deviceId!;
  }

  // Close the current database connection
  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  Future<void> resetLocalDatabase() async {
    final dbPath = await getDatabasesPath();
    final filePath = p.join(dbPath, 'market_vendor.db');
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<bool> hasAnyData() async {
    final tables = <String>[
      'products',
      'customers',
      'sales',
      'debts',
      'purchase_history',
      'expenses',
    ];

    for (final t in tables) {
      try {
        final r = await db.rawQuery('SELECT COUNT(1) as c FROM $t WHERE (deletedAt IS NULL OR TRIM(deletedAt) = \'\')');
        final c = (r.isNotEmpty ? r.first['c'] : 0) as int?;
        if ((c ?? 0) > 0) return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  Future<List<String>> getUserTables() async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    final names = <String>[];
    for (final r in rows) {
      final n = (r['name']?.toString() ?? '').trim();
      if (n.isEmpty) continue;
      names.add(n);
    }
    return names;
  }

  Future<int> countRowsInTable(String table) async {
    final t = table.trim();
    if (t.isEmpty) return 0;
    final rows = await db.rawQuery('SELECT COUNT(1) as c FROM $t WHERE (deletedAt IS NULL OR TRIM(deletedAt) = \'\')');
    return (rows.isNotEmpty ? (rows.first['c'] as int?) : 0) ?? 0;
  }

  Future<int> countTotalRowsInTable(String table) async {
    final t = table.trim();
    if (t.isEmpty) return 0;
    final rows = await db.rawQuery('SELECT COUNT(1) as c FROM $t');
    return (rows.isNotEmpty ? (rows.first['c'] as int?) : 0) ?? 0;
  }

  Future<Map<String, int>> countRowsByTable(List<String> tables) async {
    final out = <String, int>{};
    for (final t in tables) {
      try {
        out[t] = await countRowsInTable(t);
      } catch (_) {
        out[t] = 0;
      }
    }
    return out;
  }

  Future<Map<String, int>> countTotalRowsByTable(List<String> tables) async {
    final out = <String, int>{};
    for (final t in tables) {
      try {
        out[t] = await countTotalRowsInTable(t);
      } catch (_) {
        out[t] = 0;
      }
    }
    return out;
  }

  Future<void> clearTables(List<String> tables) async {
    final unique = <String>{
      for (final t in tables)
        if (t.trim().isNotEmpty) t.trim(),
    }.toList();

    if (unique.isEmpty) return;

    final order = <String, int>{
      'sale_items': 1,
      'debt_payments': 2,
      'debts': 3,
      'sales': 4,
      'purchase_history': 5,
      'purchase_orders': 6,
      'expenses': 7,
      'product_opening_stocks': 8,
      'debt_reminder_settings': 9,
      'audit_logs': 10,
      'sync_logs': 11,
      'deleted_entities': 12,
      'employees': 13,
      'vietqr_bank_accounts': 14,
      'store_info': 15,
      'customers': 16,
      'products': 17,
    };

    unique.sort((a, b) => (order[a] ?? 999).compareTo(order[b] ?? 999));

    await db.transaction((txn) async {
      await txn.execute('PRAGMA foreign_keys = OFF');
      for (final t in unique) {
        await txn.delete(t);
      }
      await txn.execute('PRAGMA foreign_keys = ON');
    });
  }

  Future<String?> getSyncState(String key) async {
    final k = key.trim();
    if (k.isEmpty) return null;
    try {
      final rows = await db.query(
        'sync_state',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: [k],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first['value'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> setSyncState(String key, String value) async {
    final k = key.trim();
    if (k.isEmpty) return;
    await db.insert(
      'sync_state',
      {'key': k, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getStoreInfo() async {
    final rows = await db.query('store_info', limit: 1);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<void> upsertStoreInfo({
    required String name,
    required String address,
    required String phone,
    String? taxCode,
    String? email,
    String? bankName,
    String? bankAccount,
  }) async {
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'store_info',
      {
        'id': 1,
        'name': name,
        'address': address,
        'phone': phone,
        'taxCode': taxCode,
        'email': email,
        'bankName': bankName,
        'bankAccount': bankAccount,
        'updatedAt': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Lấy thởi gian đồng bộ cuối cùng
  Future<DateTime?> getLastSyncTime(String table) async {
    final result = await db.rawQuery(
      'SELECT MAX(updatedAt) as lastSync FROM $table WHERE isSynced = 1 AND (deletedAt IS NULL OR TRIM(deletedAt) = \'\')',
    );

    final lastSync = result.first['lastSync'] as String?;
    return lastSync != null ? DateTime.parse(lastSync) : null;
  }

  // Đánh dấu các bản ghi đã đồng bộ
  Future<void> markAsSynced(String table, List<String> ids) async {
    if (ids.isEmpty) return;

    await db.update(
      table,
      {'isSynced': 1},
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  }

  // Lấy các bản ghi chưa đồng bộ
  Future<List<Map<String, dynamic>>> getUnsyncedRecords(String table) async {
    return await db.query(
      table,
      where: 'isSynced = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = \'\')',
      whereArgs: [0], // 0 = false
    );
  }

  // Lấy danh sách các bản ghi đã bị xóa chưa đồng bộ
  Future<List<Map<String, dynamic>>> getUnsyncedDeletions() async {
    try {
      return await db.query(
        'deleted_entities',
        where: 'isSynced = ?',
        whereArgs: [0],
      );

    } catch (e) {
      developer.log('Error getting unsynced deletions: $e', error: e);
      return [];
    }
  }

  // Đánh dấu các bản ghi đã xóa là đã đồng bộ
  Future<void> markDeletionsAsSynced(List<Map<String, dynamic>> deletions) async {
    if (deletions.isEmpty) return;

    final batch = db.batch();

    for (final deletion in deletions) {
      batch.update(
        'deleted_entities',
        {'isSynced': 1},
        where: 'entityType = ? AND entityId = ?',
        whereArgs: [deletion['entityType'], deletion['entityId']],
      );
    }

    await batch.commit(noResult: true);
  }

  Future<double> getTotalPaidForDebt(String debtId) async {
    final id = debtId.trim();
    if (id.isEmpty) return 0.0;
    final rows = await db.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) as total FROM debt_payments WHERE debtId = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = \'\')',
      [id],
    );
    return (rows.isNotEmpty ? rows.first['total'] as num? : null)?.toDouble() ?? 0.0;
  }

  Future<Map<String, double>?> getSaleTotals(String saleId) async {
    final id = saleId.trim();
    if (id.isEmpty) return null;

    if (_isOnlineMode) {
      final sale = await OnlineApiService.instance.getSaleById(id);
      if (sale == null) return null;
      return {
        'subtotal': sale.subtotal,
        'discount': sale.discount,
        'total': sale.total,
        'paidAmount': sale.paidAmount,
        'debt': sale.debt,
      };
    }

    final saleRows = await db.query(
      'sales',
      columns: ['id', 'discount', 'paidAmount'],
      where: "id = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
      whereArgs: [id],
      limit: 1,
    );

    if (saleRows.isEmpty) return null;
    final sale = saleRows.first;
    final discount = (sale['discount'] as num?)?.toDouble() ?? 0.0;
    final paidAmount = (sale['paidAmount'] as num?)?.toDouble() ?? 0.0;

    final rows = await db.rawQuery(
      "SELECT COALESCE(SUM(unitPrice * quantity), 0) as subtotal FROM sale_items WHERE saleId = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
      [id],
    );

    final subtotal = (rows.isNotEmpty ? rows.first['subtotal'] as num? : null)?.toDouble() ?? 0.0;
    final total = (subtotal - discount).clamp(0.0, double.infinity).toDouble();
    return {
      'subtotal': subtotal,
      'discount': discount,
      'total': total,
      'paidAmount': paidAmount,
    };
  }

  Future<List<Map<String, dynamic>>> getSalesForSync() async {
    return db.query('sales', where: "(deletedAt IS NULL OR TRIM(deletedAt) = '')", orderBy: 'createdAt DESC');
  }

  Future<List<Map<String, dynamic>>> getCustomersForSync() async {
    return db.query('customers', where: "(deletedAt IS NULL OR TRIM(deletedAt) = '')", orderBy: 'name COLLATE NOCASE ASC');
  }

  Future<List<Map<String, dynamic>>> getDebtsForSync() async {
    return db.query('debts', where: "(deletedAt IS NULL OR TRIM(deletedAt) = '')", orderBy: 'createdAt DESC');
  }

  Future<void> _markEntityAsDeletedTxn(Transaction txn, String table, String id) async {
    final devId = await deviceId;
    await txn.insert(
      'deleted_entities',
      {
        'entityType': table,
        'entityId': id,
        'deletedAt': DateTime.now().toIso8601String(),
        'deviceId': devId,
        'isSynced': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Debt?> getDebtBySource({required String sourceType, required String sourceId}) async {
    if (_isOnlineMode) {
      return await OnlineApiService.instance.getDebtBySource(sourceType: sourceType, sourceId: sourceId);
    }
    final st = sourceType.trim();
    final sid = sourceId.trim();
    if (st.isEmpty || sid.isEmpty) return null;
    await EncryptionService.instance.init();
    final rows = await db.query(
      'debts',
      where: "sourceType = ? AND sourceId = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
      whereArgs: [st, sid],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final m = rows.first;
    final encryptedDesc = m['description'] as String?;
    final decryptedDesc = encryptedDesc != null ? await EncryptionService.instance.decrypt(encryptedDesc) : null;
    final t = (m['type'] as int?) ?? 0;
    final debtType = (t == 0) ? DebtType.oweOthers : DebtType.othersOweMe;
    return Debt(
      id: m['id'] as String,
      createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
      type: debtType,
      partyId: m['partyId'] as String,
      partyName: m['partyName'] as String,
      initialAmount: (m['initialAmount'] as num?)?.toDouble(),
      amount: (m['amount'] as num?)?.toDouble() ?? 0.0,
      description: decryptedDesc,
      dueDate: m['dueDate'] != null ? DateTime.tryParse(m['dueDate'] as String) : null,
      settled: ((m['settled'] as int?) ?? 0) == 1,
      sourceType: m['sourceType'] as String?,
      sourceId: m['sourceId'] as String?,
    );
  }

  Future<void> insertDebt(Debt d) async {
    if (_isOnlineMode) {
      await OnlineApiService.instance.insertDebt(d);
      return;
    }
    await EncryptionService.instance.init();
    final now = DateTime.now().toIso8601String();
    final encryptedDescription = d.description != null ? await EncryptionService.instance.encrypt(d.description!) : null;

    await db.insert(
      'debts',
      {
        'id': d.id,
        'createdAt': d.createdAt.toIso8601String(),
        'type': d.type == DebtType.oweOthers ? 0 : 1,
        'partyId': d.partyId,
        'partyName': d.partyName,
        'initialAmount': d.initialAmount,
        'amount': d.amount,
        'description': encryptedDescription,
        'dueDate': d.dueDate?.toIso8601String(),
        'settled': d.settled ? 1 : 0,
        'sourceType': d.sourceType,
        'sourceId': d.sourceId,
        'updatedAt': now,
        'deletedAt': null,
        'isSynced': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateDebt(Debt d) async {
    if (_isOnlineMode) {
      await OnlineApiService.instance.updateDebt(d);
      return;
    }
    await EncryptionService.instance.init();
    final now = DateTime.now().toIso8601String();
    final encryptedDescription = d.description != null ? await EncryptionService.instance.encrypt(d.description!) : null;
    await db.update(
      'debts',
      {
        'type': d.type == DebtType.oweOthers ? 0 : 1,
        'partyId': d.partyId,
        'partyName': d.partyName,
        'initialAmount': d.initialAmount,
        'amount': d.amount,
        'description': encryptedDescription,
        'dueDate': d.dueDate?.toIso8601String(),
        'settled': d.settled ? 1 : 0,
        'sourceType': d.sourceType,
        'sourceId': d.sourceId,
        'updatedAt': now,
        'isSynced': 0,
      },
      where: "id = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
      whereArgs: [d.id],
    );
  }

  Future<void> updateDebtWithCreatedAt(Debt d) async {
    if (_isOnlineMode) {
      await OnlineApiService.instance.updateDebt(d);
      return;
    }
    await EncryptionService.instance.init();
    final now = DateTime.now().toIso8601String();
    final encryptedDescription = d.description != null ? await EncryptionService.instance.encrypt(d.description!) : null;
    await db.update(
      'debts',
      {
        'createdAt': d.createdAt.toIso8601String(),
        'type': d.type == DebtType.oweOthers ? 0 : 1,
        'partyId': d.partyId,
        'partyName': d.partyName,
        'initialAmount': d.initialAmount,
        'amount': d.amount,
        'description': encryptedDescription,
        'dueDate': d.dueDate?.toIso8601String(),
        'settled': d.settled ? 1 : 0,
        'sourceType': d.sourceType,
        'sourceId': d.sourceId,
        'updatedAt': now,
        'isSynced': 0,
      },
      where: "id = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
      whereArgs: [d.id],
    );
  }

  Future<Debt?> getDebtById(String debtId) async {
    if (_isOnlineMode) {
      return await OnlineApiService.instance.getDebtById(debtId);
    }
    final id = debtId.trim();
    if (id.isEmpty) return null;
    await EncryptionService.instance.init();
    final rows = await db.query(
      'debts',
      where: "id = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final m = rows.first;
    final encryptedDesc = m['description'] as String?;
    final decryptedDesc = encryptedDesc != null ? await EncryptionService.instance.decrypt(encryptedDesc) : null;
    final t = (m['type'] as int?) ?? 0;
    final debtType = (t == 0) ? DebtType.oweOthers : DebtType.othersOweMe;
    return Debt(
      id: m['id'] as String,
      createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
      type: debtType,
      partyId: m['partyId'] as String,
      partyName: m['partyName'] as String,
      initialAmount: (m['initialAmount'] as num?)?.toDouble(),
      amount: (m['amount'] as num?)?.toDouble() ?? 0.0,
      description: decryptedDesc,
      dueDate: m['dueDate'] != null ? DateTime.tryParse(m['dueDate'] as String) : null,
      settled: ((m['settled'] as int?) ?? 0) == 1,
      sourceType: m['sourceType'] as String?,
      sourceId: m['sourceId'] as String?,
    );
  }

  Future<List<Debt>> getDebts({
    DateTime? startDate,
    DateTime? endDate,
    int? type,
    bool? settled,
    String? search,
    int? limit,
  }) async {
    if (_isOnlineMode) {
      return await OnlineApiService.instance.getDebts(
        type: type,
        settled: settled,
        search: search,
        startDate: startDate,
        endDate: endDate,
        limit: limit,
      );
    }
    await EncryptionService.instance.init();

    final whereClauses = <String>["(deletedAt IS NULL OR TRIM(deletedAt) = '')"];
    final whereArgs = <dynamic>[];

    if (startDate != null) {
      whereClauses.add("createdAt >= ?");
      whereArgs.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      final end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);
      whereClauses.add("createdAt <= ?");
      whereArgs.add(end.toIso8601String());
    }
    if (type != null) {
      whereClauses.add("type = ?");
      whereArgs.add(type);
    }
    if (settled != null) {
      whereClauses.add("settled = ?");
      whereArgs.add(settled ? 1 : 0);
    }
    if (search != null && search.trim().isNotEmpty) {
      whereClauses.add("(partyName LIKE ? OR description LIKE ?)");
      whereArgs.add('%${search.trim()}%');
      whereArgs.add('%${search.trim()}%');
    }

    final rows = await db.query(
      'debts',
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'createdAt DESC',
      limit: limit,
    );
    final out = <Debt>[];
    for (final m in rows) {
      final encryptedDesc = m['description'] as String?;
      final decryptedDesc = encryptedDesc != null ? await EncryptionService.instance.decrypt(encryptedDesc) : null;
      final t = (m['type'] as int?) ?? 0;
      final debtType = (t == 0) ? DebtType.oweOthers : DebtType.othersOweMe;
      out.add(
        Debt(
          id: m['id'] as String,
          createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
          type: debtType,
          partyId: m['partyId'] as String,
          partyName: m['partyName'] as String,
          initialAmount: (m['initialAmount'] as num?)?.toDouble(),
          amount: (m['amount'] as num?)?.toDouble() ?? 0.0,
          description: decryptedDesc,
          dueDate: m['dueDate'] != null ? DateTime.tryParse(m['dueDate'] as String) : null,
          settled: ((m['settled'] as int?) ?? 0) == 1,
          sourceType: m['sourceType'] as String?,
          sourceId: m['sourceId'] as String?,
        ),
      );
    }
    return out;
  }

  Future<List<Sale>> getSales({
    DateTime? startDate,
    DateTime? endDate,
    String? search,
    int? limit,
    bool fetchAll = false,
  }) async {
    if (_isOnlineMode) {
      return await OnlineApiService.instance.getSales(
        startDate: startDate,
        endDate: endDate,
        search: search,
        limit: limit,
        fetchAll: fetchAll,
      );
    }
    await EncryptionService.instance.init();

    final whereClauses = <String>["(deletedAt IS NULL OR TRIM(deletedAt) = '')"];
    final whereArgs = <dynamic>[];

    if (startDate != null) {
      whereClauses.add("createdAt >= ?");
      whereArgs.add(startDate.toIso8601String());
    }
    if (endDate != null) {
      final end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);
      whereClauses.add("createdAt <= ?");
      whereArgs.add(end.toIso8601String());
    }
    if (search != null && search.trim().isNotEmpty) {
      whereClauses.add("(customerName LIKE ? OR note LIKE ?)");
      whereArgs.add('%${search.trim()}%');
      whereArgs.add('%${search.trim()}%');
    }

    final salesRows = await db.query(
      'sales',
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'createdAt DESC',
      limit: limit,
    );
    if (salesRows.isEmpty) return [];

    // Tối ưu hóa: Chỉ lấy các sale_items thuộc về danh sách đơn bán hàng đang truy vấn
    final saleIds = salesRows
        .map((r) => r['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    final itemsBySaleId = <String, List<SaleItem>>{};

    if (saleIds.isNotEmpty) {
      const chunkSize = 200;
      for (var i = 0; i < saleIds.length; i += chunkSize) {
        final chunk = saleIds.sublist(
          i,
          (i + chunkSize > saleIds.length) ? saleIds.length : i + chunkSize,
        );
        final placeholders = List.filled(chunk.length, '?').join(',');
        final items = await db.query(
          'sale_items',
          where: "saleId IN ($placeholders) AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
          whereArgs: chunk,
        );
        for (final m in items) {
          final sId = (m['saleId']?.toString() ?? '').trim();
          if (sId.isEmpty) continue;
          (itemsBySaleId[sId] ??= []).add(SaleItem.fromMap({
            'productId': m['productId'],
            'name': m['name'],
            'unitPrice': m['unitPrice'],
            'unitCost': m['unitCost'],
            'quantity': m['quantity'],
            'unit': m['unit'],
            'itemType': m['itemType'],
            'displayName': m['displayName'],
            'mixItemsJson': m['mixItemsJson'],
          }));
        }
      }
    }

    final sales = <Sale>[];
    for (final row in salesRows) {
      try {
        final sid = (row['id']?.toString() ?? '').trim();
        if (sid.isEmpty) continue;
        final saleItems = itemsBySaleId[sid] ?? [];

        final note = row['note'] as String?;
        String? decryptedNote = note;
        if (note != null && note.isNotEmpty) {
          try {
            decryptedNote = await EncryptionService.instance.decrypt(note);
          } catch (_) {
            decryptedNote = note;
          }
        }
        final totalCost = (row['totalCost'] as num?)?.toDouble() ?? 0.0;
        sales.add(
          Sale(
            id: row['id'] as String,
            createdAt: DateTime.tryParse(row['createdAt'] as String? ?? '') ?? DateTime.now(),
            customerId: row['customerId'] as String?,
            customerName: row['customerName'] as String?,
            employeeId: row['employeeId'] as String?,
            employeeName: row['employeeName'] as String?,
            items: saleItems,
            discount: (row['discount'] as num?)?.toDouble() ?? 0.0,
            paidAmount: (row['paidAmount'] as num?)?.toDouble() ?? 0.0,
            paymentType: row['paymentType'] as String?,
            note: decryptedNote,
            totalCost: totalCost,
          ),
        );
      } catch (e) {
        developer.log('Error processing sale ${row['id']}: $e', error: e);
      }
    }

    return sales;
  }

  Future<List<Debt>> getDebtsToRemind() async {
    await EncryptionService.instance.init();
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final sevenDaysAgo = now.subtract(const Duration(days: 7));

    final rows = await db.rawQuery(
      '''
      SELECT
        d.id as id,
        d.createdAt as createdAt,
        d.type as type,
        d.partyId as partyId,
        d.partyName as partyName,
        d.initialAmount as initialAmount,
        d.amount as amount,
        d.description as description,
        d.dueDate as dueDate,
        d.settled as settled,
        d.sourceType as sourceType,
        d.sourceId as sourceId,
        s.muted as muted,
        s.lastNotifiedAt as lastNotifiedAt
      FROM debts d
      LEFT JOIN debt_reminder_settings s ON s.debtId = d.id
      WHERE (d.deletedAt IS NULL OR TRIM(d.deletedAt) = '')
        AND COALESCE(d.settled, 0) = 0
        AND COALESCE(d.amount, 0) > 0
        AND (COALESCE(s.muted, 0) = 0)
        AND (
          (d.dueDate IS NOT NULL AND d.dueDate <= ?)
          OR
          (d.dueDate IS NULL AND d.createdAt <= ?)
        )
        AND (
          s.lastNotifiedAt IS NULL
          OR TRIM(s.lastNotifiedAt) = ''
          OR s.lastNotifiedAt < ?
        )
      ORDER BY COALESCE(d.dueDate, d.createdAt) ASC
      ''',
      [todayEnd.toIso8601String(), sevenDaysAgo.toIso8601String(), todayStart.toIso8601String()],
    );

    final out = <Debt>[];
    for (final m in rows) {
      final encryptedDesc = m['description'] as String?;
      final decryptedDesc = encryptedDesc != null ? await EncryptionService.instance.decrypt(encryptedDesc) : null;
      final t = (m['type'] as int?) ?? 0;
      final debtType = (t == 0) ? DebtType.oweOthers : DebtType.othersOweMe;
      out.add(
        Debt(
          id: (m['id']?.toString() ?? '').trim(),
          createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
          type: debtType,
          partyId: (m['partyId']?.toString() ?? '').trim(),
          partyName: (m['partyName']?.toString() ?? '').trim(),
          initialAmount: (m['initialAmount'] as num?)?.toDouble(),
          amount: (m['amount'] as num?)?.toDouble() ?? 0.0,
          description: decryptedDesc,
          dueDate: m['dueDate'] != null ? DateTime.tryParse(m['dueDate'] as String) : null,
          settled: ((m['settled'] as int?) ?? 0) == 1,
          sourceType: m['sourceType'] as String?,
          sourceId: m['sourceId'] as String?,
        ),
      );
    }
    return out;
  }

  Future<void> markDebtNotifiedToday(String debtId) async {
    final id = debtId.trim();
    if (id.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'debt_reminder_settings',
      {
        'debtId': id,
        'muted': 0,
        'lastNotifiedAt': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> muteDebtReminder(String debtId) async {
    final id = debtId.trim();
    if (id.isEmpty) return;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'debt_reminder_settings',
      {
        'debtId': id,
        'muted': 1,
        'lastNotifiedAt': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Map<String, double> _saleStockOutByProductId(Sale s) {
    final qtyByProductId = <String, double>{};
    for (final it in s.items) {
      final t = (it.itemType ?? '').toUpperCase().trim();
      if (t == 'MIX') {
        final raw = (it.mixItemsJson ?? '').trim();
        if (raw.isEmpty) continue;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            for (final e in decoded) {
              if (e is Map) {
                final rid = e['rawProductId']?.toString();
                if (rid == null || rid.isEmpty) continue;
                final rq = (e['rawQty'] as num?)?.toDouble() ?? 0.0;
                qtyByProductId[rid] = (qtyByProductId[rid] ?? 0) + rq;
              }
            }
          }
        } catch (_) {
          continue;
        }
      } else {
        final pid = it.productId;
        qtyByProductId[pid] = (qtyByProductId[pid] ?? 0) + it.quantity;
      }
    }
    return qtyByProductId;
  }

  Future<void> backfillSaleItemsUnitCostFromProducts() async {
    try {
      await db.rawUpdate(
        '''
        UPDATE sale_items
        SET unitCost = (
          SELECT COALESCE(p.costPrice, 0)
          FROM products p
          WHERE p.id = sale_items.productId
        )
        WHERE (unitCost IS NULL OR unitCost <= 0)
          AND (deletedAt IS NULL OR TRIM(deletedAt) = '')
          AND productId IS NOT NULL
          AND TRIM(productId) != ''
          AND (itemType IS NULL OR UPPER(TRIM(itemType)) != 'MIX')
        ''',
      );
    } catch (e) {
      developer.log('Error backfilling sale_items.unitCost:', error: e);
      rethrow;
    }
  }

  Future<void> backfillDebtInitialAmounts() async {
    try {
      await db.rawUpdate(
        '''
        UPDATE debts
        SET initialAmount = amount + (
          SELECT COALESCE(SUM(dp.amount), 0)
          FROM debt_payments dp
          WHERE dp.debtId = debts.id
            AND (dp.deletedAt IS NULL OR TRIM(dp.deletedAt) = '')
        )
        WHERE (initialAmount IS NULL OR initialAmount <= 0)
          AND (deletedAt IS NULL OR TRIM(deletedAt) = '')
        ''',
      );
    } catch (e) {
      developer.log('Error backfilling debts.initialAmount:', error: e);
      rethrow;
    }
  }

  Future<String> insertPurchaseHistory({
    required String productId,
    required String productName,
    required double quantity,
    required double unitCost,
    double paidAmount = 0,
    String? supplierName,
    String? supplierPhone,
    String? note,
    DateTime? createdAt,
    String? purchaseOrderId,
  }) async {
    final now = DateTime.now();
    final created = createdAt ?? DateTime.now();
    final id = _uuid.v4();
    final totalCost = quantity * unitCost;

    await db.transaction((txn) async {
      await txn.insert(
        'purchase_history',
        {
          'id': id,
          'createdAt': created.toIso8601String(),
          'productId': productId,
          'productName': productName,
          'quantity': quantity,
          'unitCost': unitCost,
          'totalCost': totalCost,
          'paidAmount': paidAmount,
          'supplierName': supplierName,
          'supplierPhone': supplierPhone,
          'note': note,
          'purchaseDocUploaded': 0,
          'purchaseDocFileId': null,
          'purchaseDocUpdatedAt': null,
          'purchaseOrderId': purchaseOrderId,
          'updatedAt': now.toIso8601String(),
          'deletedAt': null,
          'isSynced': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.rawUpdate(
        'UPDATE products SET currentStock = currentStock + ?, updatedAt = ? WHERE id = ?',
        [quantity, now.toIso8601String(), productId],
      );
    });

    return id;
  }

  Future<void> updatePurchaseHistory({
    required String id,
    required String productId,
    required String productName,
    required double quantity,
    required double unitCost,
    required double paidAmount,
    String? supplierName,
    String? supplierPhone,
    String? note,
    DateTime? createdAt,
    String? purchaseOrderId,
  }) async {
    final now = DateTime.now();
    final totalCost = quantity * unitCost;

    await db.transaction((txn) async {
      final oldRows = await txn.query(
        'purchase_history',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (oldRows.isEmpty) {
        throw Exception('Purchase history not found');
      }
      final old = oldRows.first;
      final oldProductId = old['productId'] as String;
      final oldQty = (old['quantity'] as num?)?.toDouble() ?? 0;

      // Reverse old stock then apply new stock
      if (oldQty != 0) {
        await txn.rawUpdate(
          'UPDATE products SET currentStock = currentStock - ?, updatedAt = ? WHERE id = ?',
          [oldQty, now.toIso8601String(), oldProductId],
        );
      }
      if (quantity != 0) {
        await txn.rawUpdate(
          'UPDATE products SET currentStock = currentStock + ?, updatedAt = ? WHERE id = ?',
          [quantity, now.toIso8601String(), productId],
        );
      }

      await txn.update(
        'purchase_history',
        {
          if (createdAt != null) 'createdAt': createdAt.toIso8601String(),
          'productId': productId,
          'productName': productName,
          'quantity': quantity,
          'unitCost': unitCost,
          'totalCost': totalCost,
          'paidAmount': paidAmount,
          'supplierName': supplierName,
          'supplierPhone': supplierPhone,
          'note': note,
          'purchaseOrderId': purchaseOrderId,
          'updatedAt': now.toIso8601String(),
          'deletedAt': null,
          'isSynced': 0,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> deletePurchaseHistory(String id) async {
    final now = DateTime.now();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'purchase_history',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final r = rows.first;
      final productId = r['productId'] as String;
      final qty = (r['quantity'] as num?)?.toDouble() ?? 0;

      if (qty != 0) {
        await txn.rawUpdate(
          'UPDATE products SET currentStock = currentStock - ?, updatedAt = ? WHERE id = ?',
          [qty, now.toIso8601String(), productId],
        );
      }

      await txn.update(
        'purchase_history',
        {
          'deletedAt': now.toIso8601String(),
          'isSynced': 0,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<List<Map<String, dynamic>>> getPurchaseHistory({
    DateTimeRange? range,
    String? query,
  }) async {
    String? where;
    final whereArgs = <Object?>[];

    if (range != null) {
      final start = DateTime(range.start.year, range.start.month, range.start.day);
      final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59, 999);
      where = 'createdAt >= ? AND createdAt <= ?';
      whereArgs.addAll([start.toIso8601String(), end.toIso8601String()]);
    }

    if (query != null && query.trim().isNotEmpty) {
      final q = '%${query.trim()}%';
      if (where == null) {
        where = '(productName LIKE ? OR note LIKE ? OR supplierName LIKE ? OR supplierPhone LIKE ?)';
      } else {
        where = '$where AND (productName LIKE ? OR note LIKE ? OR supplierName LIKE ? OR supplierPhone LIKE ?)';
      }
      whereArgs.addAll([q, q, q, q]);
    }

    if (where == null) {
      where = "(deletedAt IS NULL OR TRIM(deletedAt) = '')";
    } else {
      where = "$where AND (deletedAt IS NULL OR TRIM(deletedAt) = '')";
    }

    return await db.query(
      'purchase_history',
      where: where,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'createdAt DESC',
    );
  }

  Future<void> markPurchaseDocUploaded({
    required String purchaseId,
    required String fileId,
  }) async {
    final now = DateTime.now();
    await db.update(
      'purchase_history',
      {
        'purchaseDocUploaded': 1,
        'purchaseDocFileId': fileId,
        'purchaseDocUpdatedAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [purchaseId],
    );
  }

  Future<void> clearPurchaseDoc({required String purchaseId}) async {
    final now = DateTime.now();
    await db.update(
      'purchase_history',
      {
        'purchaseDocUploaded': 0,
        'purchaseDocFileId': null,
        'purchaseDocUpdatedAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [purchaseId],
    );
  }

  Future<String> insertPurchaseOrder({
    DateTime? createdAt,
    String? supplierName,
    String? supplierPhone,
    required String discountType,
    required double discountValue,
    required double paidAmount,
    String? note,
    int purchaseDocUploaded = 0,
    String? purchaseDocFileId,
    String? purchaseDocUpdatedAt,
  }) async {
    final now = DateTime.now();
    final id = _uuid.v4();
    final dt = createdAt ?? DateTime.now();
    final dtType = discountType.toUpperCase().trim() == 'PERCENT' ? 'PERCENT' : 'AMOUNT';

    await db.insert(
      'purchase_orders',
      {
        'id': id,
        'createdAt': dt.toIso8601String(),
        'supplierName': supplierName,
        'supplierPhone': supplierPhone,
        'discountType': dtType,
        'discountValue': discountValue,
        'paidAmount': paidAmount,
        'note': note,
        'purchaseDocUploaded': purchaseDocUploaded,
        'purchaseDocFileId': purchaseDocFileId,
        'purchaseDocUpdatedAt': purchaseDocUpdatedAt,
        'updatedAt': now.toIso8601String(),
        'deletedAt': null,
        'isSynced': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return id;
  }

  Future<void> updatePurchaseOrder({
    required String id,
    DateTime? createdAt,
    String? supplierName,
    String? supplierPhone,
    required String discountType,
    required double discountValue,
    required double paidAmount,
    String? note,
  }) async {
    final now = DateTime.now();
    final dtType = discountType.toUpperCase().trim() == 'PERCENT' ? 'PERCENT' : 'AMOUNT';
    await db.update(
      'purchase_orders',
      {
        if (createdAt != null) 'createdAt': createdAt.toIso8601String(),
        'supplierName': supplierName,
        'supplierPhone': supplierPhone,
        'discountType': dtType,
        'discountValue': discountValue,
        'paidAmount': paidAmount,
        'note': note,
        'updatedAt': now.toIso8601String(),
        'deletedAt': null,
        'isSynced': 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markPurchaseOrderDocUploaded({
    required String purchaseOrderId,
    required String fileId,
  }) async {
    final now = DateTime.now();
    await db.update(
      'purchase_orders',
      {
        'purchaseDocUploaded': 1,
        'purchaseDocFileId': fileId,
        'purchaseDocUpdatedAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [purchaseOrderId],
    );
  }

  Future<void> clearPurchaseOrderDoc({required String purchaseOrderId}) async {
    final now = DateTime.now();
    await db.update(
      'purchase_orders',
      {
        'purchaseDocUploaded': 0,
        'purchaseDocFileId': null,
        'purchaseDocUpdatedAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [purchaseOrderId],
    );
  }

  Future<Map<String, dynamic>?> getPurchaseOrderById(String purchaseOrderId) async {
    final rows = await db.query(
      'purchase_orders',
      where: "id = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
      whereArgs: [purchaseOrderId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<List<Map<String, dynamic>>> getPurchaseOrders({
    DateTimeRange? range,
    String? query,
  }) async {
    String? where;
    final whereArgs = <Object?>[];

    if (range != null) {
      final start = DateTime(range.start.year, range.start.month, range.start.day);
      final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59, 999);
      where = 'createdAt >= ? AND createdAt <= ?';
      whereArgs.addAll([start.toIso8601String(), end.toIso8601String()]);
    }

    if (query != null && query.trim().isNotEmpty) {
      final q = '%${query.trim()}%';
      if (where == null) {
        where = '(note LIKE ? OR supplierName LIKE ? OR supplierPhone LIKE ?)';
      } else {
        where = '$where AND (note LIKE ? OR supplierName LIKE ? OR supplierPhone LIKE ?)';
      }
      whereArgs.addAll([q, q, q]);
    }

    if (where == null) {
      where = "(deletedAt IS NULL OR TRIM(deletedAt) = '')";
    } else {
      where = "$where AND (deletedAt IS NULL OR TRIM(deletedAt) = '')";
    }

    return db.query(
      'purchase_orders',
      where: where,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'createdAt DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getPurchaseHistoryByOrderId(String purchaseOrderId) async {
    return db.query(
      'purchase_history',
      where: "purchaseOrderId = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
      whereArgs: [purchaseOrderId],
      orderBy: 'createdAt DESC',
    );
  }

  Future<Map<String, double>?> getPurchaseOrderTotals(String purchaseOrderId) async {
    final order = await getPurchaseOrderById(purchaseOrderId);
    if (order == null) return null;

    final rows = await db.rawQuery(
      "SELECT SUM(totalCost) as subtotal FROM purchase_history WHERE purchaseOrderId = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
      [purchaseOrderId],
    );

    final subtotal = (rows.isNotEmpty ? rows.first['subtotal'] as num? : null)?.toDouble() ?? 0.0;

    final dtType = (order['discountType'] as String?)?.toUpperCase().trim() ?? 'AMOUNT';
    final dv = (order['discountValue'] as num?)?.toDouble() ?? 0.0;

    final discountAmount = (dtType == 'PERCENT')
        ? (subtotal * (dv / 100.0)).clamp(0.0, double.infinity).toDouble()
        : dv.clamp(0.0, double.infinity).toDouble();
    final total = (subtotal - discountAmount).clamp(0.0, double.infinity).toDouble();
    final paid = (order['paidAmount'] as num?)?.toDouble() ?? 0.0;
    final remainDebt = (total - paid).clamp(0.0, double.infinity).toDouble();

    return {
      'subtotal': subtotal,
      'discountAmount': discountAmount,
      'total': total,
      'paidAmount': paid,
      'remainDebt': remainDebt,
    };
  }

  Future<void> syncPurchaseOrderDebt({required String purchaseOrderId}) async {
    final order = await getPurchaseOrderById(purchaseOrderId);
    if (order == null) return;

    final totals = await getPurchaseOrderTotals(purchaseOrderId);
    final subtotal = totals?['subtotal'] ?? 0.0;
    final discountAmount = totals?['discountAmount'] ?? 0.0;
    final total = totals?['total'] ?? 0.0;
    final paidAmount = totals?['paidAmount'] ?? 0.0;
    final debtInitialAmount = totals?['remainDebt'] ?? 0.0;

    final supplierName = (order['supplierName'] as String?)?.trim();
    final note = (order['note'] as String?)?.trim();
    final createdAt = DateTime.tryParse(order['createdAt'] as String? ?? '') ?? DateTime.now();

    final lines = await getPurchaseHistoryByOrderId(purchaseOrderId);
    final fmtMoney = NumberFormat.decimalPattern('en_US');
    final fmtDate = DateFormat('dd/MM/yyyy HH:mm');

    final buf = StringBuffer();
    buf.write('Đơn nhập hàng');
    if (supplierName != null && supplierName.isNotEmpty) buf.write(' | NCC: $supplierName');
    buf.write('\nNgày: ${fmtDate.format(createdAt)}');
    if (note != null && note.isNotEmpty) buf.write('\nGhi chú: $note');
    buf.write('\n');

    for (final r in lines) {
      final name = (r['productName'] as String?)?.trim() ?? '';
      final qty = (r['quantity'] as num?)?.toDouble() ?? 0.0;
      final unitCost = (r['unitCost'] as num?)?.toDouble() ?? 0.0;
      final totalCost = (r['totalCost'] as num?)?.toDouble() ?? (qty * unitCost);
      buf.write(
        '\n- $name: SL ${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2)}, Giá ${fmtMoney.format(unitCost.round())}, Tiền ${fmtMoney.format(totalCost.round())}',
      );
    }

    buf.write('\n');
    buf.write('\nTạm tính: ${fmtMoney.format(subtotal.round())}');
    buf.write('\nChiết khấu: ${fmtMoney.format(discountAmount.round())}');
    buf.write('\nTổng đơn: ${fmtMoney.format(total.round())}');
    buf.write('\nĐã thanh toán (đơn): ${fmtMoney.format(paidAmount.round())}');
    buf.write('\nCòn nợ (theo đơn): ${fmtMoney.format(debtInitialAmount.round())}');
    final description = buf.toString().trim();

    final existing = await getDebtBySource(sourceType: 'purchase', sourceId: purchaseOrderId);
    if (existing == null) {
      if (debtInitialAmount <= 0) return;
      final d = Debt(
        type: DebtType.oweOthers,
        partyId: 'supplier_unknown',
        partyName: (supplierName == null || supplierName.isEmpty) ? 'Nhà cung cấp' : supplierName,
        initialAmount: debtInitialAmount,
        amount: debtInitialAmount,
        description: description,
        sourceType: 'purchase',
        sourceId: purchaseOrderId,
      );
      await insertDebt(d);
      return;
    }

    final alreadyPaidForDebt = await getTotalPaidForDebt(existing.id);
    final newRemain = (debtInitialAmount - alreadyPaidForDebt).clamp(0.0, double.infinity).toDouble();
    final updated = Debt(
      id: existing.id,
      createdAt: existing.createdAt,
      type: DebtType.oweOthers,
      partyId: existing.partyId,
      partyName: (supplierName == null || supplierName.isEmpty) ? existing.partyName : supplierName,
      initialAmount: debtInitialAmount,
      amount: newRemain,
      description: description,
      settled: newRemain <= 0,
      sourceType: 'purchase',
      sourceId: purchaseOrderId,
    );
    await updateDebt(updated);
  }

  Future<void> assignPurchaseHistoryToOrder({
    required String purchaseHistoryId,
    required String purchaseOrderId,
  }) async {
    final now = DateTime.now();
    await db.update(
      'purchase_history',
      {'purchaseOrderId': purchaseOrderId, 'updatedAt': now.toIso8601String()},
      where: 'id = ?',
      whereArgs: [purchaseHistoryId],
    );
  }

  Future<void> unassignPurchaseHistoryFromOrder({
    required String purchaseHistoryId,
  }) async {
    final now = DateTime.now();
    await db.update(
      'purchase_history',
      {'purchaseOrderId': null, 'updatedAt': now.toIso8601String()},
      where: 'id = ?',
      whereArgs: [purchaseHistoryId],
    );
  }

  Future<String?> quickCreateOrderForPurchaseHistoryRow({
    required String purchaseHistoryId,
  }) async {
    final now = DateTime.now();
    return db.transaction((txn) async {
      final phRows = await txn.query(
        'purchase_history',
        where: 'id = ?',
        whereArgs: [purchaseHistoryId],
        limit: 1,
      );
      if (phRows.isEmpty) return null;

      final ph = phRows.first;
      final existing = (ph['purchaseOrderId'] as String?)?.trim();
      if (existing != null && existing.isNotEmpty) return existing;

      final orderId = _uuid.v4();
      final createdAt = (ph['createdAt'] as String?)?.trim();

      await txn.insert(
        'purchase_orders',
        {
          'id': orderId,
          'createdAt': (createdAt == null || createdAt.isEmpty) ? now.toIso8601String() : createdAt,
          'supplierName': ph['supplierName'],
          'supplierPhone': ph['supplierPhone'],
          'discountType': 'AMOUNT',
          'discountValue': 0,
          'paidAmount': (ph['paidAmount'] as num?)?.toDouble() ?? 0.0,
          'note': ph['note'],
          // Legacy: copy row-level doc to order for quick-create flow
          'purchaseDocUploaded': (ph['purchaseDocUploaded'] as int?) ?? 0,
          'purchaseDocFileId': ph['purchaseDocFileId'],
          'purchaseDocUpdatedAt': ph['purchaseDocUpdatedAt'],
          'updatedAt': now.toIso8601String(),
          'deletedAt': null,
          'isSynced': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.update(
        'purchase_history',
        {'purchaseOrderId': orderId, 'updatedAt': now.toIso8601String()},
        where: 'id = ?',
        whereArgs: [purchaseHistoryId],
      );

      await txn.update(
        'debts',
        {'sourceId': orderId, 'updatedAt': now.toIso8601String()},
        where: 'sourceType = ? AND sourceId = ?',
        whereArgs: ['purchase', purchaseHistoryId],
      );

      return orderId;
    });
  }

  Future<List<String>> autoCreateOrdersForUnassignedPurchaseHistory({
    DateTimeRange? range,
    int limit = 500,
  }) async {
    final now = DateTime.now();

    String? where;
    final whereArgs = <Object?>[];
    if (range != null) {
      final start = DateTime(range.start.year, range.start.month, range.start.day);
      final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59, 999);
      where = 'purchaseOrderId IS NULL AND createdAt >= ? AND createdAt <= ?';
      whereArgs.addAll([start.toIso8601String(), end.toIso8601String()]);
    } else {
      where = 'purchaseOrderId IS NULL';
    }

    final rows = await db.query(
      'purchase_history',
      where: where,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'createdAt ASC',
      limit: limit,
    );
    if (rows.isEmpty) return const [];

    final fmtDay = DateFormat('yyyy-MM-dd');
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final createdAt = DateTime.tryParse(r['createdAt'] as String? ?? '') ?? DateTime.now();
      final dayKey = fmtDay.format(createdAt);
      final supplierName = (r['supplierName'] as String?)?.trim() ?? '';
      final supplierPhone = (r['supplierPhone'] as String?)?.trim() ?? '';
      final key = '${supplierName.toLowerCase()}|${supplierPhone.toLowerCase()}|$dayKey';
      (groups[key] ??= <Map<String, dynamic>>[]).add(r);
    }

    final createdOrderIds = <String>[];
    for (final g in groups.values) {
      if (g.isEmpty) continue;

      final first = g.first;
      final orderId = _uuid.v4();

      final createdAtStr = (first['createdAt'] as String?)?.trim();
      final supplierName = (first['supplierName'] as String?)?.trim();
      final supplierPhone = (first['supplierPhone'] as String?)?.trim();
      final note = (first['note'] as String?)?.trim();

      double paidSum = 0.0;
      for (final r in g) {
        paidSum += (r['paidAmount'] as num?)?.toDouble() ?? 0.0;
      }

      await db.transaction((txn) async {
        await txn.insert(
          'purchase_orders',
          {
            'id': orderId,
            'createdAt': (createdAtStr == null || createdAtStr.isEmpty) ? now.toIso8601String() : createdAtStr,
            'supplierName': supplierName,
            'supplierPhone': supplierPhone,
            'discountType': 'AMOUNT',
            'discountValue': 0,
            'paidAmount': paidSum,
            'note': note,
            'purchaseDocUploaded': (first['purchaseDocUploaded'] as int?) ?? 0,
            'purchaseDocFileId': first['purchaseDocFileId'],
            'purchaseDocUpdatedAt': first['purchaseDocUpdatedAt'],
            'updatedAt': now.toIso8601String(),
            'deletedAt': null,
            'isSynced': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        for (final r in g) {
          final id = (r['id'] as String?)?.trim();
          if (id == null || id.isEmpty) continue;
          await txn.update(
            'purchase_history',
            {'purchaseOrderId': orderId, 'updatedAt': now.toIso8601String()},
            where: 'id = ?',
            whereArgs: [id],
          );

          await txn.update(
            'debts',
            {'sourceId': orderId, 'updatedAt': now.toIso8601String()},
            where: 'sourceType = ? AND sourceId = ?',
            whereArgs: ['purchase', id],
          );
        }
      });

      await syncPurchaseOrderDebt(purchaseOrderId: orderId);
      createdOrderIds.add(orderId);
    }

    return createdOrderIds;
  }

  Future<void> deletePurchaseOrder({
    required String purchaseOrderId,
  }) async {
    final now = DateTime.now();
    await db.transaction((txn) async {
      // Delete order-level debt + payments
      final debtRows = await txn.query(
        'debts',
        columns: ['id'],
        where: 'sourceType = ? AND sourceId = ?',
        whereArgs: ['purchase', purchaseOrderId],
      );
      for (final d in debtRows) {
        final debtId = d['id'] as String?;
        if (debtId == null) continue;

        final payments = await txn.query(
          'debt_payments',
          columns: ['id', 'uuid'],
          where: "debtId = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
          whereArgs: [debtId],
        );
        for (final p in payments) {
          final pid = p['id'];
          final uuid = (p['uuid'] as String?)?.trim();
          if (pid == null) continue;
          await _markEntityAsDeletedTxn(txn, 'debt_payments', (uuid == null || uuid.isEmpty) ? pid.toString() : uuid);
          await txn.update(
            'debt_payments',
            {
              'deletedAt': now.toIso8601String(),
              'updatedAt': now.toIso8601String(),
              'isSynced': 0,
            },
            where: 'id = ?',
            whereArgs: [pid],
          );
        }

        await _markEntityAsDeletedTxn(txn, 'debts', debtId);
        await txn.update(
          'debts',
          {
            'deletedAt': now.toIso8601String(),
            'updatedAt': now.toIso8601String(),
            'isSynced': 0,
          },
          where: "id = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
          whereArgs: [debtId],
        );
      }

      // Delete all purchase_history rows belonging to this order and revert stock
      final lines = await txn.query(
        'purchase_history',
        columns: ['id', 'productId', 'quantity'],
        where: 'purchaseOrderId = ?',
        whereArgs: [purchaseOrderId],
      );

      for (final r in lines) {
        final lineId = r['id'] as String?;
        final productId = r['productId'] as String?;
        final qty = (r['quantity'] as num?)?.toDouble() ?? 0;

        if (productId != null && qty != 0) {
          await txn.rawUpdate(
            'UPDATE products SET currentStock = currentStock - ?, updatedAt = ? WHERE id = ?',
            [qty, now.toIso8601String(), productId],
          );
        }
        if (lineId != null) {
          await txn.update(
            'purchase_history',
            {
              'deletedAt': now.toIso8601String(),
              'isSynced': 0,
            },
            where: 'id = ?',
            whereArgs: [lineId],
          );
        }
      }

      await txn.update(
        'purchase_orders',
        {
          'deletedAt': now.toIso8601String(),
          'isSynced': 0,
        },
        where: 'id = ?',
        whereArgs: [purchaseOrderId],
      );
    });
  }

  Future<String> insertExpense({
    required DateTime occurredAt,
    required double amount,
    required String category,
    String? note,
  }) async {
    if (_isOnlineMode) {
      return await OnlineApiService.instance.insertExpense(
        occurredAt: occurredAt,
        amount: amount,
        category: category,
        note: note,
      );
    }
    final now = DateTime.now();
    final id = _uuid.v4();
    await db.insert(
      'expenses',
      {
        'id': id,
        'occurredAt': occurredAt.toIso8601String(),
        'amount': amount,
        'category': category,
        'note': note,
        'expenseDocUploaded': 0,
        'expenseDocFileId': null,
        'expenseDocUpdatedAt': null,
        'updatedAt': now.toIso8601String(),
        'deletedAt': null,
        'isSynced': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return id;
  }

  Future<void> updateExpense({
    required String id,
    required DateTime occurredAt,
    required double amount,
    required String category,
    String? note,
  }) async {
    if (_isOnlineMode) {
      await OnlineApiService.instance.updateExpense(
        id: id,
        occurredAt: occurredAt,
        amount: amount,
        category: category,
        note: note,
      );
      return;
    }
    final now = DateTime.now();
    await db.update(
      'expenses',
      {
        'occurredAt': occurredAt.toIso8601String(),
        'amount': amount,
        'category': category,
        'note': note,
        'updatedAt': now.toIso8601String(),
        'deletedAt': null,
        'isSynced': 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteExpense(String id) async {
    if (_isOnlineMode) {
      await OnlineApiService.instance.deleteExpense(id);
      return;
    }
    final now = DateTime.now();
    await db.update(
      'expenses',
      {
        'deletedAt': now.toIso8601String(),
        'isSynced': 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getExpenses({
    DateTimeRange? range,
    String? category,
    String? query,
  }) async {
    if (_isOnlineMode) {
      return await OnlineApiService.instance.getExpenses(
        range: range,
        category: category,
        query: query,
      );
    }
    String? where;
    final whereArgs = <Object?>[];

    if (range != null) {
      final start = DateTime(range.start.year, range.start.month, range.start.day);
      final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59, 999);
      where = 'occurredAt >= ? AND occurredAt <= ?';
      whereArgs.addAll([start.toIso8601String(), end.toIso8601String()]);
    }

    if (category != null && category.trim().isNotEmpty && category.trim() != 'all') {
      if (where == null) {
        where = 'category = ?';
      } else {
        where = '$where AND category = ?';
      }
      whereArgs.add(category.trim());
    }

    if (query != null && query.trim().isNotEmpty) {
      final q = '%${query.trim()}%';
      if (where == null) {
        where = '(note LIKE ?)';
      } else {
        where = '$where AND (note LIKE ?)';
      }
      whereArgs.add(q);
    }

    if (where == null) {
      where = "(deletedAt IS NULL OR TRIM(deletedAt) = '')";
    } else {
      where = "$where AND (deletedAt IS NULL OR TRIM(deletedAt) = '')";
    }

    return await db.query(
      'expenses',
      where: where,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'occurredAt DESC',
    );
  }

  Future<void> markExpenseDocUploaded({
    required String expenseId,
    required String fileId,
  }) async {
    final now = DateTime.now();
    await db.update(
      'expenses',
      {
        'expenseDocUploaded': 1,
        'expenseDocFileId': fileId,
        'expenseDocUpdatedAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [expenseId],
    );
  }

  Future<void> clearExpenseDoc({required String expenseId}) async {
    final now = DateTime.now();
    await db.update(
      'expenses',
      {
        'expenseDocUploaded': 0,
        'expenseDocFileId': null,
        'expenseDocUpdatedAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [expenseId],
    );
  }

  Future<double> getTotalExpensesInRange(DateTimeRange range) async {
    final start = DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59, 999);
    final rows = await db.rawQuery(
      "SELECT SUM(amount) as total FROM expenses WHERE occurredAt >= ? AND occurredAt <= ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
      [start.toIso8601String(), end.toIso8601String()],
    );
    final total = rows.isNotEmpty ? rows.first['total'] : null;
    return (total as num?)?.toDouble() ?? 0;
  }

  // Reinitialize the database
  Future<void> reinitialize() async {
    await close();
    await init();
  }

  // Thêm bản ghi mới với thông tin đồng bộ
  Future<void> insertWithSync(String table, Map<String, dynamic> data) async {
    final now = DateTime.now();
    final devId = await deviceId;

    final newData = Map<String, dynamic>.from(data)
      ..addAll({
        'deviceId': devId,
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'isSynced': 0, // Chưa đồng bộ
      });

    await db.insert(table, newData);

    // Ghi log
    await _logSyncAction('create', table, newData['id'], devId, now.toIso8601String());
  }

  // Cập nhật bản ghi với thông tin đồng bộ
  Future<int> updateWithSync(String table, Map<String, dynamic> data, String id) async {
    final now = DateTime.now();
    final devId = await deviceId;

    final updatedData = Map<String, dynamic>.from(data)
      ..addAll({
        'updatedAt': now.toIso8601String(),
        'isSynced': 0, // Đánh dấu là chưa đồng bộ
      });

    final count = await db.update(
      table,
      updatedData,
      where: 'id = ?',
      whereArgs: [id],
    );

    // Ghi log
    if (count > 0) {
      await _logSyncAction('update', table, id, devId, now.toIso8601String());
    }

    return count;
  }

  // Xóa bản ghi với thông tin đồng bộ
  Future<int> deleteWithSync(String table, String id) async {
    final now = DateTime.now();
    final devId = await deviceId;

    // Lấy dữ liệu trước khi xóa để lưu vào bảng deleted_entities
    final rows = await db.query(
      table,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (rows.isNotEmpty) {
      // Lưu vào bảng deleted_entities
      await db.insert('deleted_entities', {
        'entityType': table,
        'entityId': id,
        'deletedAt': now.toIso8601String(),
        'deviceId': devId,
        'isSynced': 0, // Chưa đồng bộ
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // Ghi log
      await _logSyncAction('delete', table, id, devId, now.toIso8601String());
    }

    // Soft delete: set deletedAt instead of deleting row
    final updateData = <String, Object?>{
      'deletedAt': now.toIso8601String(),
      'isSynced': 0,
    };
    try {
      // most tables have updatedAt
      updateData['updatedAt'] = now.toIso8601String();
    } catch (_) {
      // ignore
    }

    return await db.update(
      table,
      updateData,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Ghi log hoạt động đồng bộ
  Future<void> _logSyncAction(
    String action,
    String entityType,
    String? entityId,
    String deviceId,
    String timestamp, {
    String? details,
  }) async {
    await db.insert('sync_logs', {
      'action': action,
      'entityType': entityType,
      'entityId': entityId,
      'deviceId': deviceId,
      'timestamp': timestamp,
      'details': details,
    });
  }

  // Helper function to safely add columns
  Future<void> safeAddColumn(Database db, String table, String column, String definition) async {
    try {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    } catch (_) {
      // ignore
    }
  }

  Future<void> _migrateDatabase(Database db, int oldVersion, int newVersion) async {
    print('Đang thực hiện migration từ phiên bản $oldVersion lên $newVersion');
    await EncryptionService.instance.init();

    // Migration cho version 1 lên 2: Thêm cột updatedAt
    if (oldVersion < 2) {
      final now = DateTime.now().toIso8601String();
      await safeAddColumn(db, 'products', 'updatedAt', 'TEXT');
      await db.execute("UPDATE products SET updatedAt = '$now' WHERE updatedAt IS NULL");
      await safeAddColumn(db, 'customers', 'updatedAt', 'TEXT');
      await db.execute("UPDATE customers SET updatedAt = '$now' WHERE updatedAt IS NULL");
      await safeAddColumn(db, 'sales', 'updatedAt', 'TEXT');
      await db.execute("UPDATE sales SET updatedAt = '$now' WHERE updatedAt IS NULL");
    }

    // Migration từ version 4 lên 5: Thêm cột isSynced vào bảng deleted_entities
    if (oldVersion < 5) {
      try {
        print('Đang thêm cột isSynced vào bảng deleted_entities...');

        // Kiểm tra xem bảng deleted_entities có tồn tại không
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='deleted_entities'");
        if (tables.isNotEmpty) {
          // Thêm cột isSynced nếu chưa tồn tại
          await safeAddColumn(db, 'deleted_entities', 'isSynced', 'INTEGER NOT NULL DEFAULT 0');
          await safeAddColumn(db, 'deleted_entities', 'deviceId', 'TEXT NOT NULL DEFAULT "unknown"');
          print('Đã cập nhật bảng deleted_entities thành công');
        } else {
          // Nếu bảng chưa tồn tại, tạo mới
          await db.execute('''
            CREATE TABLE IF NOT EXISTS deleted_entities (
              entityType TEXT NOT NULL,
              entityId TEXT NOT NULL,
              deletedAt TEXT NOT NULL,
              deviceId TEXT NOT NULL,
              isSynced INTEGER NOT NULL DEFAULT 0,
              PRIMARY KEY (entityType, entityId)
            )
          ''');
          print('Đã tạo mới bảng deleted_entities');
        }
      } catch (e) {
        print('Lỗi khi cập nhật bảng deleted_entities: $e');
        // Nếu có lỗi, tạo lại bảng mới nếu chưa tồn tại
        try {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS deleted_entities (
              entityType TEXT NOT NULL,
              entityId TEXT NOT NULL,
              deletedAt TEXT NOT NULL,
              deviceId TEXT NOT NULL,
              isSynced INTEGER NOT NULL DEFAULT 0,
              PRIMARY KEY (entityType, entityId)
            )
          ''');
          print('Đã tạo lại bảng deleted_entities sau khi xảy ra lỗi');
        } catch (e2) {
          print('Lỗi khi tạo lại bảng deleted_entities: $e2');
        }
      }
    }

    // Migration từ version 6 lên 7: Thêm cột isSynced vào bảng sale_items và debt_payments
    if (oldVersion < 7) {
      try {
        print('Đang thêm cột isSynced vào bảng sale_items và debt_payments...');
        await safeAddColumn(db, 'sale_items', 'isSynced', 'INTEGER NOT NULL DEFAULT 0');
        await safeAddColumn(db, 'debt_payments', 'isSynced', 'INTEGER NOT NULL DEFAULT 0');
        print('Đã cập nhật bảng sale_items và debt_payments thành công');
      } catch (e) {
        print('Lỗi khi cập nhật bảng sale_items và debt_payments: $e');
      }
    }

    // Migration từ version 7 lên 8: Thêm cột costPrice vào bảng products
    if (oldVersion < 8) {
      try {
        print('Đang thêm cột costPrice vào bảng products...');
        await safeAddColumn(db, 'products', 'costPrice', 'REAL NOT NULL DEFAULT 0');
        print('Đã cập nhật bảng products thành công');
      } catch (e) {
        print('Lỗi khi cập nhật bảng products: $e');
      }
    }

    // Migration từ version 8 lên 9: Thêm cột totalCost vào bảng sales
    if (oldVersion < 9) {
      try {
        print('Đang thêm cột totalCost vào bảng sales...');
        await safeAddColumn(db, 'sales', 'totalCost', 'REAL NOT NULL DEFAULT 0');
        print('Đã cập nhật bảng sales thành công');
      } catch (e) {
        print('Lỗi khi cập nhật bảng sales: $e');
      }
    }

    // Migration từ version 9 lên 10: Thêm cột currentStock vào bảng products
    if (oldVersion < 10) {
      try {
        print('Đang thêm cột currentStock vào bảng products...');
        await safeAddColumn(db, 'products', 'currentStock', 'REAL NOT NULL DEFAULT 0');
        print('Đã cập nhật bảng products (currentStock) thành công');
      } catch (e) {
        print('Lỗi khi cập nhật bảng products (currentStock): $e');
      }
    }

    // Migration lên version 21: Thêm cột imagePath vào bảng products (lưu đường dẫn ảnh trong thư mục app)
    if (oldVersion < 21) {
      try {
        print('Đang thêm cột imagePath vào bảng products...');
        await safeAddColumn(db, 'products', 'imagePath', 'TEXT');
        print('Đã cập nhật bảng products (imagePath) thành công');
      } catch (e) {
        print('Lỗi khi cập nhật bảng products (imagePath): $e');
      }
    }

    // Migration từ version 10 lên 11: Thêm bảng tồn đầu kỳ theo tháng/năm
    if (oldVersion < 11) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS product_opening_stocks(
            productId TEXT NOT NULL,
            year INTEGER NOT NULL,
            month INTEGER NOT NULL,
            openingStock REAL NOT NULL DEFAULT 0,
            updatedAt TEXT NOT NULL,
            PRIMARY KEY (productId, year, month)
          )
        ''');
      } catch (e) {
        print('Lỗi khi tạo bảng product_opening_stocks: $e');
      }
    }

    // Migration từ version 11 lên 12: Thêm bảng lịch sử nhập hàng
    if (oldVersion < 12) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS purchase_history(
            id TEXT PRIMARY KEY,
            createdAt TEXT NOT NULL,
            productId TEXT NOT NULL,
            productName TEXT NOT NULL,
            quantity REAL NOT NULL,
            unitCost REAL NOT NULL DEFAULT 0,
            totalCost REAL NOT NULL DEFAULT 0,
            paidAmount REAL NOT NULL DEFAULT 0,
            supplierName TEXT,
            supplierPhone TEXT,
            note TEXT,
            purchaseDocUploaded INTEGER NOT NULL DEFAULT 0,
            purchaseDocFileId TEXT,
            purchaseDocUpdatedAt TEXT,
            purchaseOrderId TEXT,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            isSynced INTEGER NOT NULL DEFAULT 0
          )
        ''');
      } catch (e) {
        print('Lỗi khi tạo bảng purchase_history: $e');
      }
    }

    if (oldVersion < 13) {
      try {
        await db.execute('ALTER TABLE purchase_history ADD COLUMN supplierName TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE purchase_history ADD COLUMN supplierPhone TEXT');
      } catch (_) {}
    }

    if (oldVersion < 14) {
      try {
        await safeAddColumn(db, 'purchase_history', 'paidAmount', 'REAL NOT NULL DEFAULT 0');
      } catch (_) {}
    }

    if (oldVersion < 15) {
      try {
        await safeAddColumn(db, 'debts', 'sourceType', 'TEXT');
      } catch (_) {}
      try {
        await safeAddColumn(db, 'debts', 'sourceId', 'TEXT');
      } catch (_) {}
    }

    if (oldVersion < 16) {
      try {
        await safeAddColumn(db, 'purchase_history', 'purchaseDocUploaded', 'INTEGER NOT NULL DEFAULT 0');
      } catch (_) {}
      try {
        await safeAddColumn(db, 'purchase_history', 'purchaseDocFileId', 'TEXT');
      } catch (_) {}
      try {
        await safeAddColumn(db, 'purchase_history', 'purchaseDocUpdatedAt', 'TEXT');
      } catch (_) {}
    }

    if (oldVersion < 17) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS expenses(
            id TEXT PRIMARY KEY,
            occurredAt TEXT NOT NULL,
            amount REAL NOT NULL,
            category TEXT NOT NULL,
            note TEXT,
            expenseDocUploaded INTEGER NOT NULL DEFAULT 0,
            expenseDocFileId TEXT,
            expenseDocUpdatedAt TEXT,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            isSynced INTEGER NOT NULL DEFAULT 0
          )
        ''');
      } catch (e) {
        print('Lỗi khi tạo bảng expenses: $e');
      }
    }

    if (oldVersion < 18) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS store_info(
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            address TEXT NOT NULL,
            phone TEXT NOT NULL,
            taxCode TEXT,
            email TEXT,
            bankName TEXT,
            bankAccount TEXT,
            updatedAt TEXT NOT NULL
          )
        ''');
      } catch (e) {
        print('Lỗi khi tạo bảng store_info: $e');
      }
    }

    if (oldVersion < 20) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS debt_reminder_settings(
            debtId TEXT PRIMARY KEY,
            muted INTEGER NOT NULL DEFAULT 0,
            lastNotifiedAt TEXT
          )
        ''');
      } catch (e) {
        print('Lỗi khi tạo bảng debt_reminder_settings: $e');
      }
    }

    if (oldVersion < 22) {
      try {
        await safeAddColumn(db, 'sales', 'paymentType', 'TEXT');
      } catch (_) {}
      try {
        await safeAddColumn(db, 'debt_payments', 'paymentType', 'TEXT');
      } catch (_) {}
    }

    if (oldVersion < 23) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS purchase_orders(
            id TEXT PRIMARY KEY,
            createdAt TEXT NOT NULL,
            supplierName TEXT,
            supplierPhone TEXT,
            discountType TEXT NOT NULL DEFAULT 'AMOUNT',
            discountValue REAL NOT NULL DEFAULT 0,
            paidAmount REAL NOT NULL DEFAULT 0,
            note TEXT,
            purchaseDocUploaded INTEGER NOT NULL DEFAULT 0,
            purchaseDocFileId TEXT,
            purchaseDocUpdatedAt TEXT,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            isSynced INTEGER NOT NULL DEFAULT 0
          )
        ''');
      } catch (e) {
        print('Lỗi khi tạo bảng purchase_orders: $e');
      }

      try {
        await safeAddColumn(db, 'purchase_history', 'purchaseOrderId', 'TEXT');
      } catch (_) {}

      // Migrate existing purchase debts to reference purchase_orders instead of purchase_history
      // Rule: for legacy data, each purchase_history row becomes its own purchase_order (only when it has a debt)
      try {
        final now = DateTime.now().toIso8601String();
        final debts = await db.query(
          'debts',
          columns: ['id', 'sourceType', 'sourceId'],
          where: 'sourceType = ? AND sourceId IS NOT NULL AND TRIM(sourceId) != ""',
          whereArgs: ['purchase'],
        );

        for (final d in debts) {
          final debtId = (d['id'] as String?)?.trim();
          final legacyPurchaseId = (d['sourceId'] as String?)?.trim();
          if (debtId == null || debtId.isEmpty) continue;
          if (legacyPurchaseId == null || legacyPurchaseId.isEmpty) continue;

          final ph = await db.query(
            'purchase_history',
            where: 'id = ?',
            whereArgs: [legacyPurchaseId],
            limit: 1,
          );
          if (ph.isEmpty) continue;

          final row = ph.first;
          final existingOrderId = (row['purchaseOrderId'] as String?)?.trim();
          final orderId = (existingOrderId != null && existingOrderId.isNotEmpty) ? existingOrderId : _uuid.v4();

          if (existingOrderId == null || existingOrderId.isEmpty) {
            final createdAt = (row['createdAt'] as String?)?.trim();

            final supplierName = row['supplierName'] as String?;
            final supplierPhone = row['supplierPhone'] as String?;
            final note = row['note'] as String?;
            final paidAmount = (row['paidAmount'] as num?)?.toDouble() ?? 0.0;
            final docUploaded = (row['purchaseDocUploaded'] as int?) ?? 0;
            final docFileId = row['purchaseDocFileId'] as String?;
            final docUpdatedAt = row['purchaseDocUpdatedAt'] as String?;

            await db.insert(
              'purchase_orders',
              {
                'id': orderId,
                'createdAt': (createdAt == null || createdAt.isEmpty) ? now : createdAt,
                'supplierName': supplierName,
                'supplierPhone': supplierPhone,
                'discountType': 'AMOUNT',
                'discountValue': 0,
                'paidAmount': paidAmount,
                'note': note,
                'purchaseDocUploaded': docUploaded,
                'purchaseDocFileId': docFileId,
                'purchaseDocUpdatedAt': docUpdatedAt,
                'updatedAt': now,
                'deletedAt': null,
                'isSynced': 0,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );

            await db.update(
              'purchase_history',
              {'purchaseOrderId': orderId, 'updatedAt': now},
              where: 'id = ?',
              whereArgs: [legacyPurchaseId],
            );
          }

          await db.update(
            'debts',
            {'sourceId': orderId, 'updatedAt': now},
            where: 'id = ?',
            whereArgs: [debtId],
          );
        }
      } catch (e) {
        print('Lỗi khi migrate công nợ nhập hàng sang purchase_orders: $e');
      }
    }

    if (oldVersion < 24) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS vietqr_bank_accounts(
            id TEXT PRIMARY KEY,
            bankApiId INTEGER,
            name TEXT,
            code TEXT,
            bin TEXT,
            shortName TEXT,
            short_name TEXT,
            logo TEXT,
            transferSupported INTEGER,
            lookupSupported INTEGER,
            support INTEGER,
            isTransfer INTEGER,
            swift_code TEXT,
            accountNo TEXT NOT NULL,
            accountName TEXT NOT NULL,
            isDefault INTEGER NOT NULL DEFAULT 0,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            isSynced INTEGER NOT NULL DEFAULT 0
          )
        ''');
      } catch (e) {
        print('Lỗi khi tạo bảng vietqr_bank_accounts: $e');
      }
    }

    // Migration lên version 25: Thêm bảng employees + thêm thông tin nhân viên vào sales
    if (oldVersion < 25) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS employees(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            isSynced INTEGER NOT NULL DEFAULT 0
          )
        ''');
      } catch (e) {
        print('Lỗi khi tạo bảng employees: $e');
      }
      try {
        await safeAddColumn(db, 'sales', 'employeeId', 'TEXT');
      } catch (e) {
        print('Lỗi khi thêm cột employeeId vào sales: $e');
      }
      try {
        await safeAddColumn(db, 'sales', 'employeeName', 'TEXT');
      } catch (e) {
        print('Lỗi khi thêm cột employeeName vào sales: $e');
      }
    }

    // Migration lên version 26: Thêm cột initialAmount vào debts
    if (oldVersion < 26) {
      try {
        await safeAddColumn(db, 'debts', 'initialAmount', 'REAL NOT NULL DEFAULT 0');
      } catch (e) {
        print('Lỗi khi thêm cột initialAmount vào debts: $e');
      }
    }

    // Migration lên version 27: Thêm outbox + sync_state + chuẩn hoá debt_payments để sync online
    if (oldVersion < 27) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS outbox(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            eventUuid TEXT NOT NULL,
            entity TEXT NOT NULL,
            entityId TEXT NOT NULL,
            op TEXT NOT NULL,
            payloadJson TEXT,
            clientUpdatedAt TEXT NOT NULL,
            status INTEGER NOT NULL DEFAULT 0,
            createdAt TEXT NOT NULL
          )
        ''');
      } catch (e) {
        print('Lỗi khi tạo bảng outbox: $e');
      }

      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS sync_state(
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
      } catch (e) {
        print('Lỗi khi tạo bảng sync_state: $e');
      }

      try {
        await safeAddColumn(db, 'debt_payments', 'uuid', 'TEXT');
      } catch (e) {
        print('Lỗi khi thêm cột uuid vào debt_payments: $e');
      }
      try {
        await safeAddColumn(db, 'debt_payments', 'updatedAt', 'TEXT');
      } catch (e) {
        print('Lỗi khi thêm cột updatedAt vào debt_payments: $e');
      }

      try {
        // Backfill uuid + updatedAt for existing payments
        final rows = await db.query('debt_payments', columns: ['id', 'createdAt', 'uuid', 'updatedAt']);
        for (final r in rows) {
          final pid = r['id'];
          final existingUuid = (r['uuid'] as String?)?.trim();
          final createdAt = (r['createdAt'] as String?)?.trim();
          final existingUpdatedAt = (r['updatedAt'] as String?)?.trim();
          await db.update(
            'debt_payments',
            {
              'uuid': (existingUuid == null || existingUuid.isEmpty) ? _uuid.v4() : existingUuid,
              'updatedAt': (existingUpdatedAt == null || existingUpdatedAt.isEmpty) ? createdAt : existingUpdatedAt,
            },
            where: 'id = ?',
            whereArgs: [pid],
          );
        }
      } catch (e) {
        print('Lỗi khi backfill uuid/updatedAt cho debt_payments: $e');
      }
    }

    // Migration lên version 28: Lưu event_uuid đã apply để idempotent khi pull
    if (oldVersion < 28) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS applied_sync_events(
            eventUuid TEXT PRIMARY KEY,
            appliedAt TEXT NOT NULL
          )
        ''');
      } catch (e) {
        print('Lỗi khi tạo bảng applied_sync_events: $e');
      }
    }

    // Migration lên version 29: Thêm isSynced vào purchase_orders để sync online
    if (oldVersion < 29) {
      try {
        await safeAddColumn(db, 'purchase_orders', 'isSynced', 'INTEGER NOT NULL DEFAULT 0');
      } catch (e) {
        print('Lỗi khi thêm isSynced vào purchase_orders: $e');
      }
    }

    // Migration lên version 30: Thêm isSynced vào các bảng còn thiếu để sync online
    if (oldVersion < 30) {
      try {
        await safeAddColumn(db, 'purchase_history', 'isSynced', 'INTEGER NOT NULL DEFAULT 0');
      } catch (e) {
        print('Lỗi khi thêm isSynced vào purchase_history: $e');
      }

      try {
        await safeAddColumn(db, 'expenses', 'isSynced', 'INTEGER NOT NULL DEFAULT 0');
      } catch (e) {
        print('Lỗi khi thêm isSynced vào expenses: $e');
      }

      try {
        await safeAddColumn(db, 'vietqr_bank_accounts', 'isSynced', 'INTEGER NOT NULL DEFAULT 0');
      } catch (e) {
        print('Lỗi khi thêm isSynced vào vietqr_bank_accounts: $e');
      }

      try {
        await safeAddColumn(db, 'employees', 'isSynced', 'INTEGER NOT NULL DEFAULT 0');
      } catch (e) {
        print('Lỗi khi thêm isSynced vào employees: $e');
      }
    }

    // Migration lên version 31: Đảm bảo tất cả các bảng có isSynced trong onCreate
    if (oldVersion < 31) {
      try {
        await safeAddColumn(db, 'purchase_history', 'isSynced', 'INTEGER NOT NULL DEFAULT 0');
      } catch (e) {
        print('Lỗi khi thêm isSynced vào purchase_history (v31): $e');
      }

      try {
        await safeAddColumn(db, 'purchase_orders', 'isSynced', 'INTEGER NOT NULL DEFAULT 0');
      } catch (e) {
        print('Lỗi khi thêm isSynced vào purchase_orders (v31): $e');
      }

      try {
        await safeAddColumn(db, 'expenses', 'isSynced', 'INTEGER NOT NULL DEFAULT 0');
      } catch (e) {
        print('Lỗi khi thêm isSynced vào expenses (v31): $e');
      }

      try {
        await safeAddColumn(db, 'vietqr_bank_accounts', 'isSynced', 'INTEGER NOT NULL DEFAULT 0');
      } catch (e) {
        print('Lỗi khi thêm isSynced vào vietqr_bank_accounts (v31): $e');
      }

      try {
        await safeAddColumn(db, 'employees', 'isSynced', 'INTEGER NOT NULL DEFAULT 0');
      } catch (e) {
        print('Lỗi khi thêm isSynced vào employees (v31): $e');
      }
    }

    // Migration lên version 32: Thêm deletedAt cho tất cả entity tables + bổ sung isSynced còn thiếu
    if (oldVersion < 32) {
      // deletedAt for entities
      final tables = <String>[
        'products',
        'customers',
        'sales',
        'sale_items',
        'debts',
        'debt_payments',
        'purchase_orders',
        'purchase_history',
        'expenses',
        'employees',
        'vietqr_bank_accounts',
      ];

      for (final t in tables) {
        try {
          await safeAddColumn(db, t, 'deletedAt', 'TEXT');
        } catch (e) {
          print('Lỗi khi thêm deletedAt vào $t: $e');
        }
      }

      // Ensure isSynced exists for the remaining entity tables
      final needIsSynced = <String>[
        'purchase_orders',
        'purchase_history',
        'expenses',
        'employees',
        'vietqr_bank_accounts',
      ];
      for (final t in needIsSynced) {
        try {
          await safeAddColumn(db, t, 'isSynced', 'INTEGER NOT NULL DEFAULT 0');
        } catch (e) {
          print('Lỗi khi thêm isSynced vào $t (v32): $e');
        }
      }
    }

    // Migration lên version 33: sale_items thiếu updatedAt trong một số DB cũ
    if (oldVersion < 33) {
      try {
        await safeAddColumn(db, 'sale_items', 'updatedAt', 'TEXT');
      } catch (e) {
        print('Lỗi khi thêm updatedAt vào sale_items (v33): $e');
      }

      try {
        final now = DateTime.now().toIso8601String();
        // Backfill for existing rows (avoid NULL updatedAt causing UPDATE failures later)
        await db.execute("UPDATE sale_items SET updatedAt = '$now' WHERE updatedAt IS NULL OR TRIM(updatedAt) = ''");
      } catch (e) {
        print('Lỗi khi backfill updatedAt cho sale_items (v33): $e');
      }
    }

    // Migration lên version 34: Tạo các Indexes tối ưu hiệu năng và tránh giật lag khi dữ liệu lớn
    if (oldVersion < 34) {
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sale_items_saleId ON sale_items(saleId)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_debt_payments_debtId ON debt_payments(debtId)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_createdAt ON sales(createdAt)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_debts_partyId ON debts(partyId)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_purchase_history_orderId ON purchase_history(purchaseOrderId)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_outbox_status ON outbox(status)');
      } catch (e) {
        print('Lỗi khi tạo index tối ưu hiệu năng (v34): $e');
      }
    }
  }

  Future<void> init({bool? isOnline}) async {
    if (isOnline != null) {
      _isOnlineMode = isOnline;
    }
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, currentDbFileName);

    _db = await openDatabase(
      path,
      version: 34, // Tăng version lên 34 để áp dụng indexes & tối ưu
      onCreate: (db, version) async {
        // Tạo các bảng mới nếu chưa tồn tại
        await db.execute('''
          CREATE TABLE IF NOT EXISTS products(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            price REAL NOT NULL,
            costPrice REAL NOT NULL DEFAULT 0,
            currentStock REAL NOT NULL DEFAULT 0,
            unit TEXT NOT NULL,
            barcode TEXT,
            isActive INTEGER NOT NULL DEFAULT 1,
            itemType TEXT NOT NULL DEFAULT 'RAW',
            isStocked INTEGER NOT NULL DEFAULT 1,
            imagePath TEXT,
            updatedAt TEXT NOT NULL,
            deviceId TEXT,
            deletedAt TEXT,
            isSynced INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS customers(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            phone TEXT,
            note TEXT,
            isSupplier INTEGER NOT NULL DEFAULT 0,
            updatedAt TEXT NOT NULL,
            deviceId TEXT,
            deletedAt TEXT,
            isSynced INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS sales(
            id TEXT PRIMARY KEY,
            createdAt TEXT NOT NULL,
            customerId TEXT,
            customerName TEXT,
            employeeId TEXT,
            employeeName TEXT,
            discount REAL NOT NULL DEFAULT 0,
            paidAmount REAL NOT NULL DEFAULT 0,
            paymentType TEXT,
            totalCost REAL NOT NULL DEFAULT 0, -- Thêm cột totalCost
            note TEXT,
            updatedAt TEXT NOT NULL,
            deviceId TEXT,
            deletedAt TEXT,
            isSynced INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS sale_items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            saleId TEXT NOT NULL,
            productId TEXT,
            name TEXT NOT NULL,
            unitPrice REAL NOT NULL,
            unitCost REAL NOT NULL DEFAULT 0,
            quantity REAL NOT NULL,
            unit TEXT NOT NULL,
            itemType TEXT,
            displayName TEXT,
            mixItemsJson TEXT,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            isSynced INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (saleId) REFERENCES sales(id) ON DELETE CASCADE
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS debts(
            id TEXT PRIMARY KEY,
            createdAt TEXT NOT NULL,
            type INTEGER NOT NULL,
            partyId TEXT NOT NULL,
            partyName TEXT NOT NULL,
            initialAmount REAL NOT NULL DEFAULT 0,
            amount REAL NOT NULL,
            description TEXT,
            dueDate TEXT,
            settled INTEGER NOT NULL DEFAULT 0,
            sourceType TEXT,
            sourceId TEXT,
            updatedAt TEXT NOT NULL,
            deviceId TEXT,
            deletedAt TEXT,
            isSynced INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute(''' 
          CREATE TABLE IF NOT EXISTS deleted_entities(
            entityType TEXT NOT NULL,
            entityId TEXT NOT NULL,
            deletedAt TEXT NOT NULL,
            deviceId TEXT NOT NULL,
            isSynced INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (entityType, entityId)
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS debt_payments(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uuid TEXT,
            debtId TEXT NOT NULL,
            amount REAL NOT NULL,
            note TEXT,
            paymentType TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT,
            deletedAt TEXT,
            isSynced INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (debtId) REFERENCES debts(id) ON DELETE CASCADE
          )
        ''');

        await db.execute(''' 
          CREATE TABLE IF NOT EXISTS audit_logs(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entity TEXT NOT NULL,
            entityId TEXT NOT NULL,
            action TEXT NOT NULL,
            at TEXT NOT NULL,
            payload TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS sync_logs(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            action TEXT NOT NULL,
            entityType TEXT NOT NULL,
            entityId TEXT,
            deviceId TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            details TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS product_opening_stocks(
            productId TEXT NOT NULL,
            year INTEGER NOT NULL,
            month INTEGER NOT NULL,
            openingStock REAL NOT NULL DEFAULT 0,
            updatedAt TEXT NOT NULL,
            PRIMARY KEY (productId, year, month)
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS purchase_history(
            id TEXT PRIMARY KEY,
            createdAt TEXT NOT NULL,
            productId TEXT NOT NULL,
            productName TEXT NOT NULL,
            quantity REAL NOT NULL,
            unitCost REAL NOT NULL DEFAULT 0,
            totalCost REAL NOT NULL DEFAULT 0,
            paidAmount REAL NOT NULL DEFAULT 0,
            supplierName TEXT,
            supplierPhone TEXT,
            note TEXT,
            purchaseDocUploaded INTEGER NOT NULL DEFAULT 0,
            purchaseDocFileId TEXT,
            purchaseDocUpdatedAt TEXT,
            purchaseOrderId TEXT,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            isSynced INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS purchase_orders(
            id TEXT PRIMARY KEY,
            createdAt TEXT NOT NULL,
            supplierName TEXT,
            supplierPhone TEXT,
            discountType TEXT NOT NULL DEFAULT 'AMOUNT',
            discountValue REAL NOT NULL DEFAULT 0,
            paidAmount REAL NOT NULL DEFAULT 0,
            note TEXT,
            purchaseDocUploaded INTEGER NOT NULL DEFAULT 0,
            purchaseDocFileId TEXT,
            purchaseDocUpdatedAt TEXT,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            isSynced INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS expenses(
            id TEXT PRIMARY KEY,
            occurredAt TEXT NOT NULL,
            amount REAL NOT NULL,
            category TEXT NOT NULL,
            note TEXT,
            expenseDocUploaded INTEGER NOT NULL DEFAULT 0,
            expenseDocFileId TEXT,
            expenseDocUpdatedAt TEXT,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            isSynced INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS store_info(
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            address TEXT NOT NULL,
            phone TEXT NOT NULL,
            taxCode TEXT,
            email TEXT,
            bankName TEXT,
            bankAccount TEXT,
            updatedAt TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS debt_reminder_settings(
            debtId TEXT PRIMARY KEY,
            muted INTEGER NOT NULL DEFAULT 0,
            lastNotifiedAt TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS vietqr_bank_accounts(
            id TEXT PRIMARY KEY,
            bankApiId INTEGER,
            name TEXT,
            code TEXT,
            bin TEXT,
            shortName TEXT,
            short_name TEXT,
            logo TEXT,
            transferSupported INTEGER,
            lookupSupported INTEGER,
            support INTEGER,
            isTransfer INTEGER,
            swift_code TEXT,
            accountNo TEXT NOT NULL,
            accountName TEXT NOT NULL,
            isDefault INTEGER NOT NULL DEFAULT 0,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            isSynced INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS employees(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            updatedAt TEXT NOT NULL,
            deletedAt TEXT,
            isSynced INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS outbox(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            eventUuid TEXT NOT NULL,
            entity TEXT NOT NULL,
            entityId TEXT NOT NULL,
            op TEXT NOT NULL,
            payloadJson TEXT,
            clientUpdatedAt TEXT NOT NULL,
            status INTEGER NOT NULL DEFAULT 0,
            createdAt TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS sync_state(
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS applied_sync_events(
            eventUuid TEXT PRIMARY KEY,
            appliedAt TEXT NOT NULL
          )
        ''');

        // Indexes tối ưu hiệu năng
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sale_items_saleId ON sale_items(saleId)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_debt_payments_debtId ON debt_payments(debtId)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_createdAt ON sales(createdAt)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_debts_partyId ON debts(partyId)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_purchase_history_orderId ON purchase_history(purchaseOrderId)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_outbox_status ON outbox(status)');
      },
      onUpgrade: _migrateDatabase,
      onDowngrade: (db, oldVersion, newVersion) async {
        // IMPORTANT: Tránh sqflite mặc định xóa DB khi downgrade (gây mất dữ liệu sau restore)
        // Giữ nguyên database hiện tại và không thực hiện gì.
        print('DB downgrade detected (old=$oldVersion, new=$newVersion). Skip downgrade to avoid data loss.');
      },
    );

    print('Đã khởi tạo database ($currentDbFileName) thành công');
    unawaited(cleanOldLogs());

    // Nếu đang ở Online Mode và database online đang trống, tự động nạp từ offline sang
    if (_isOnlineMode) {
      await copyFromOfflineIfOnlineEmpty();
    }
  }

  /// Chuyển đổi giữa Chế độ Online (market_vendor_online.db) và Chế độ Offline (market_vendor.db)
  Future<void> switchDatabaseMode({required bool isOnline}) async {
    if (_isOnlineMode == isOnline && _db != null && _db!.isOpen) return;
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
    _isOnlineMode = isOnline;
    await init(isOnline: isOnline);

    // Nếu chuyển sang Online mode và database online đang trống,
    // tự động sao chép toàn bộ dữ liệu từ offline sang để không bao giờ bị trắng màn hình!
    if (isOnline) {
      await copyFromOfflineIfOnlineEmpty();
    }
  }

  /// Mở kết nối riêng biệt tới file SQLite offline (market_vendor.db)
  Future<Database> openOfflineDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'market_vendor.db');
    return await openDatabase(
      path,
      version: 34,
      onUpgrade: _migrateDatabase,
    );
  }

  /// Tự động sao chép toàn bộ dữ liệu từ Offline (market_vendor.db) sang Online (market_vendor_online.db)
  /// nếu database online đang trống (để tránh màn hình trắng khi người dùng mới bật Online)
  Future<void> copyFromOfflineIfOnlineEmpty() async {
    if (!_isOnlineMode || _db == null || !_db!.isOpen) return;
    try {
      final pCountRows = await _db!.rawQuery('SELECT COUNT(*) as c FROM products');
      final pCount = (pCountRows.first['c'] as num?)?.toInt() ?? 0;
      if (pCount > 0) {
        print('copyFromOfflineIfOnlineEmpty: Online DB đã có $pCount sản phẩm, không cần sao chép.');
        return;
      }

      print('copyFromOfflineIfOnlineEmpty: Online DB đang trống. Đang sao chép từ Offline DB...');
      final offlineDb = await openOfflineDb();
      try {
        final tables = [
          'products',
          'customers',
          'sales',
          'sale_items',
          'debts',
          'debt_payments',
          'purchase_orders',
          'purchase_history',
          'expenses',
          'employees',
          'vietqr_bank_accounts',
          'store_info',
          'product_opening_stocks',
          'debt_reminder_settings',
        ];

        await _db!.transaction((txn) async {
          for (final t in tables) {
            try {
              final rows = await offlineDb.query(t);
              for (final row in rows) {
                await txn.insert(t, row, conflictAlgorithm: ConflictAlgorithm.replace);
              }
            } catch (te) {
              print('Lỗi sao chép bảng $t: $te');
            }
          }
        });
        print('copyFromOfflineIfOnlineEmpty: Đã hoàn tất sao chép dữ liệu ban đầu sang Online DB!');
      } finally {
        await offlineDb.close();
      }
    } catch (e) {
      print('copyFromOfflineIfOnlineEmpty error: $e');
    }
  }

  /// Trích xuất toàn bộ dữ liệu offline phục vụ Tải lên máy chủ (Sync Up 1 chiều)
  Future<Map<String, dynamic>> getAllOfflineDataForSync() async {
    final targetDb = _isOnlineMode ? await openOfflineDb() : db;
    try {
      final tables = [
        'products',
        'customers',
        'sales',
        'debts',
        'debt_payments',
        'purchase_orders',
        'purchase_history',
        'expenses',
        'employees',
        'vietqr_bank_accounts',
        'store_info',
        'product_opening_stocks',
        'debt_reminder_settings',
      ];

      final result = <String, dynamic>{};
      for (final t in tables) {
        try {
          final rows = await targetDb.query(t);
          if (t == 'sales') {
            final salesWithItems = <Map<String, dynamic>>[];
            for (final s in rows) {
              final sId = s['id']?.toString() ?? '';
              final items = await targetDb.query('sale_items', where: 'saleId = ?', whereArgs: [sId]);
              salesWithItems.add({
                ...s,
                'items': items,
              });
            }
            result[t] = salesWithItems;
          } else {
            result[t] = rows;
          }
        } catch (e) {
          result[t] = [];
        }
      }
      return result;
    } finally {
      if (_isOnlineMode) {
        await targetDb.close();
      }
    }
  }

  /// Áp dụng Snapshot từ máy chủ vào database (toOfflineOnly: chỉ ghi vào market_vendor.db)
  Future<void> applySnapshot(Map<String, dynamic> snapshot, {bool toOfflineOnly = false}) async {
    if (toOfflineOnly) {
      final targetDb = await openOfflineDb();
      try {
        await _applySnapshotToDatabase(targetDb, snapshot);
      } finally {
        await targetDb.close();
      }
      return;
    }

    // 1. Áp dụng ngay vào database đang mở (db)
    await _applySnapshotToDatabase(db, snapshot);

    // 2. Nếu đang ở Online Mode, cập nhật luôn cả database offline để đảm bảo bản sao lưu an toàn
    if (_isOnlineMode) {
      try {
        final offlineDb = await openOfflineDb();
        try {
          await _applySnapshotToDatabase(offlineDb, snapshot);
        } finally {
          await offlineDb.close();
        }
      } catch (e) {
        print('Không thể cập nhật bản sao lưu offline khi apply snapshot: $e');
      }
    }
  }

  Future<void> _applySnapshotToDatabase(Database targetDb, Map<String, dynamic> snapshot) async {
    await targetDb.transaction((txn) async {
        // 1. Products
        final products = (snapshot['products'] as List?) ?? [];
        for (final p in products) {
          if (p is! Map) continue;
          final row = {
            'id': p['id']?.toString() ?? '',
            'name': p['name']?.toString() ?? '',
            'price': (p['price'] as num?)?.toDouble() ?? double.tryParse(p['price']?.toString() ?? '0') ?? 0.0,
            'costPrice': (p['costPrice'] as num?)?.toDouble() ?? double.tryParse(p['costPrice']?.toString() ?? '0') ?? 0.0,
            'currentStock': (p['currentStock'] as num?)?.toDouble() ?? double.tryParse(p['currentStock']?.toString() ?? '0') ?? 0.0,
            'unit': p['unit']?.toString() ?? '',
            'barcode': p['barcode']?.toString(),
            'isActive': (p['isActive'] == true || p['isActive'] == 1 || p['isActive'] == '1') ? 1 : 0,
            'itemType': p['itemType']?.toString() ?? 'RAW',
            'isStocked': (p['isStocked'] == true || p['isStocked'] == 1 || p['isStocked'] == '1') ? 1 : 0,
            'imagePath': p['imagePath']?.toString(),
            'updatedAt': p['updatedAt']?.toString() ?? DateTime.now().toIso8601String(),
            'deviceId': p['deviceId']?.toString() ?? 'server',
            'deletedAt': p['deletedAt']?.toString(),
            'isSynced': 1,
          };
          if (row['id'] != '') {
            await txn.insert('products', row, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }

        // 2. Customers
        final customers = (snapshot['customers'] as List?) ?? [];
        for (final c in customers) {
          if (c is! Map) continue;
          final row = {
            'id': c['id']?.toString() ?? '',
            'name': c['name']?.toString() ?? '',
            'phone': c['phone']?.toString(),
            'note': c['note']?.toString(),
            'isSupplier': (c['isSupplier'] == true || c['isSupplier'] == 1 || c['isSupplier'] == '1') ? 1 : 0,
            'updatedAt': c['updatedAt']?.toString() ?? DateTime.now().toIso8601String(),
            'deviceId': c['deviceId']?.toString() ?? 'server',
            'deletedAt': c['deletedAt']?.toString(),
            'isSynced': 1,
          };
          if (row['id'] != '') {
            await txn.insert('customers', row, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }

        // 3. Sales & Sale Items
        final sales = (snapshot['sales'] as List?) ?? [];
        for (final s in sales) {
          if (s is! Map) continue;
          final sId = s['id']?.toString() ?? '';
          if (sId.isEmpty) continue;
          final saleRow = {
            'id': sId,
            'createdAt': s['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
            'customerId': s['customerId']?.toString(),
            'customerName': s['customerName']?.toString(),
            'employeeId': s['employeeId']?.toString(),
            'employeeName': s['employeeName']?.toString(),
            'discount': (s['discount'] as num?)?.toDouble() ?? double.tryParse(s['discount']?.toString() ?? '0') ?? 0.0,
            'paidAmount': (s['paidAmount'] as num?)?.toDouble() ?? double.tryParse(s['paidAmount']?.toString() ?? '0') ?? 0.0,
            'paymentType': s['paymentType']?.toString(),
            'totalCost': (s['totalCost'] as num?)?.toDouble() ?? double.tryParse(s['totalCost']?.toString() ?? '0') ?? 0.0,
            'note': s['note']?.toString(),
            'updatedAt': s['updatedAt']?.toString() ?? DateTime.now().toIso8601String(),
            'deviceId': s['deviceId']?.toString() ?? 'server',
            'deletedAt': s['deletedAt']?.toString(),
            'isSynced': 1,
          };
          await txn.insert('sales', saleRow, conflictAlgorithm: ConflictAlgorithm.replace);

          final items = (s['items'] as List?) ?? [];
          await txn.delete('sale_items', where: 'saleId = ?', whereArgs: [sId]);
          for (final it in items) {
            if (it is! Map) continue;
            await txn.insert('sale_items', {
              'saleId': sId,
              'productId': it['productId']?.toString(),
              'name': it['name']?.toString() ?? '',
              'unitPrice': (it['unitPrice'] as num?)?.toDouble() ?? double.tryParse(it['unitPrice']?.toString() ?? '0') ?? 0.0,
              'unitCost': (it['unitCost'] as num?)?.toDouble() ?? double.tryParse(it['unitCost']?.toString() ?? '0') ?? 0.0,
              'quantity': (it['quantity'] as num?)?.toDouble() ?? double.tryParse(it['quantity']?.toString() ?? '0') ?? 0.0,
              'unit': it['unit']?.toString() ?? '',
              'itemType': it['itemType']?.toString(),
              'displayName': it['displayName']?.toString(),
              'mixItemsJson': it['mixItemsJson']?.toString(),
              'updatedAt': it['updatedAt']?.toString() ?? DateTime.now().toIso8601String(),
              'deletedAt': it['deletedAt']?.toString(),
              'isSynced': 1,
            });
          }
        }

        // 4. Debts
        final debts = (snapshot['debts'] as List?) ?? [];
        for (final d in debts) {
          if (d is! Map) continue;
          final dId = d['id']?.toString() ?? '';
          if (dId.isEmpty) continue;
          await txn.insert('debts', {
            'id': dId,
            'createdAt': d['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
            'type': (d['type'] as num?)?.toInt() ?? int.tryParse(d['type']?.toString() ?? '0') ?? 0,
            'partyId': d['partyId']?.toString() ?? '',
            'partyName': d['partyName']?.toString() ?? '',
            'initialAmount': (d['initialAmount'] as num?)?.toDouble() ?? double.tryParse(d['initialAmount']?.toString() ?? '0') ?? 0.0,
            'amount': (d['amount'] as num?)?.toDouble() ?? double.tryParse(d['amount']?.toString() ?? '0') ?? 0.0,
            'description': d['description']?.toString(),
            'dueDate': d['dueDate']?.toString(),
            'settled': (d['settled'] == true || d['settled'] == 1 || d['settled'] == '1') ? 1 : 0,
            'sourceType': d['sourceType']?.toString(),
            'sourceId': d['sourceId']?.toString(),
            'updatedAt': d['updatedAt']?.toString() ?? DateTime.now().toIso8601String(),
            'deviceId': d['deviceId']?.toString() ?? 'server',
            'deletedAt': d['deletedAt']?.toString(),
            'isSynced': 1,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }

        // 5. Debt Payments
        final debtPayments = (snapshot['debtPayments'] as List?) ?? [];
        for (final dp in debtPayments) {
          if (dp is! Map) continue;
          final uuid = dp['uuid']?.toString() ?? '';
          if (uuid.isEmpty) continue;
          await txn.insert('debt_payments', {
            'uuid': uuid,
            'debtId': dp['debtId']?.toString() ?? '',
            'amount': (dp['amount'] as num?)?.toDouble() ?? double.tryParse(dp['amount']?.toString() ?? '0') ?? 0.0,
            'note': dp['note']?.toString(),
            'paymentType': dp['paymentType']?.toString(),
            'createdAt': dp['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
            'updatedAt': dp['updatedAt']?.toString() ?? DateTime.now().toIso8601String(),
            'deletedAt': dp['deletedAt']?.toString(),
            'isSynced': 1,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }

        // 6. Expenses
        final expenses = (snapshot['expenses'] as List?) ?? [];
        for (final ex in expenses) {
          if (ex is! Map) continue;
          final exId = ex['id']?.toString() ?? '';
          if (exId.isEmpty) continue;
          await txn.insert('expenses', {
            'id': exId,
            'occurredAt': ex['occurredAt']?.toString() ?? DateTime.now().toIso8601String(),
            'amount': (ex['amount'] as num?)?.toDouble() ?? double.tryParse(ex['amount']?.toString() ?? '0') ?? 0.0,
            'category': ex['category']?.toString() ?? '',
            'note': ex['note']?.toString(),
            'expenseDocUploaded': (ex['expenseDocUploaded'] == true || ex['expenseDocUploaded'] == 1 || ex['expenseDocUploaded'] == '1') ? 1 : 0,
            'expenseDocFileId': ex['expenseDocFileId']?.toString(),
            'expenseDocUpdatedAt': ex['expenseDocUpdatedAt']?.toString(),
            'updatedAt': ex['updatedAt']?.toString() ?? DateTime.now().toIso8601String(),
            'deletedAt': ex['deletedAt']?.toString(),
            'isSynced': 1,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }

        // 7. Purchase Orders
        final purchaseOrders = (snapshot['purchaseOrders'] as List?) ?? [];
        for (final po in purchaseOrders) {
          if (po is! Map) continue;
          final poId = po['id']?.toString() ?? '';
          if (poId.isEmpty) continue;
          await txn.insert('purchase_orders', {
            'id': poId,
            'createdAt': po['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
            'supplierName': po['supplierName']?.toString(),
            'supplierPhone': po['supplierPhone']?.toString(),
            'discountType': po['discountType']?.toString() ?? 'AMOUNT',
            'discountValue': (po['discountValue'] as num?)?.toDouble() ?? double.tryParse(po['discountValue']?.toString() ?? '0') ?? 0.0,
            'paidAmount': (po['paidAmount'] as num?)?.toDouble() ?? double.tryParse(po['paidAmount']?.toString() ?? '0') ?? 0.0,
            'note': po['note']?.toString(),
            'purchaseDocUploaded': (po['purchaseDocUploaded'] == true || po['purchaseDocUploaded'] == 1 || po['purchaseDocUploaded'] == '1') ? 1 : 0,
            'purchaseDocFileId': po['purchaseDocFileId']?.toString(),
            'purchaseDocUpdatedAt': po['purchaseDocUpdatedAt']?.toString(),
            'updatedAt': po['updatedAt']?.toString() ?? DateTime.now().toIso8601String(),
            'deletedAt': po['deletedAt']?.toString(),
            'isSynced': 1,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }

        // 8. Purchase History
        final purchaseHistories = (snapshot['purchaseHistories'] as List?) ?? [];
        for (final ph in purchaseHistories) {
          if (ph is! Map) continue;
          final phId = ph['id']?.toString() ?? '';
          if (phId.isEmpty) continue;
          await txn.insert('purchase_history', {
            'id': phId,
            'createdAt': ph['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
            'productId': ph['productId']?.toString() ?? '',
            'productName': ph['productName']?.toString() ?? '',
            'quantity': (ph['quantity'] as num?)?.toDouble() ?? double.tryParse(ph['quantity']?.toString() ?? '0') ?? 0.0,
            'unitCost': (ph['unitCost'] as num?)?.toDouble() ?? double.tryParse(ph['unitCost']?.toString() ?? '0') ?? 0.0,
            'totalCost': (ph['totalCost'] as num?)?.toDouble() ?? double.tryParse(ph['totalCost']?.toString() ?? '0') ?? 0.0,
            'paidAmount': (ph['paidAmount'] as num?)?.toDouble() ?? double.tryParse(ph['paidAmount']?.toString() ?? '0') ?? 0.0,
            'supplierName': ph['supplierName']?.toString(),
            'supplierPhone': ph['supplierPhone']?.toString(),
            'note': ph['note']?.toString(),
            'purchaseDocUploaded': (ph['purchaseDocUploaded'] == true || ph['purchaseDocUploaded'] == 1 || ph['purchaseDocUploaded'] == '1') ? 1 : 0,
            'purchaseDocFileId': ph['purchaseDocFileId']?.toString(),
            'purchaseDocUpdatedAt': ph['purchaseDocUpdatedAt']?.toString(),
            'purchaseOrderId': ph['purchaseOrderId']?.toString(),
            'updatedAt': ph['updatedAt']?.toString() ?? DateTime.now().toIso8601String(),
            'deletedAt': ph['deletedAt']?.toString(),
            'isSynced': 1,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }

        // 9. Employees
        final employees = (snapshot['employees'] as List?) ?? [];
        for (final emp in employees) {
          if (emp is! Map) continue;
          final empId = emp['id']?.toString() ?? '';
          if (empId.isEmpty) continue;
          await txn.insert('employees', {
            'id': empId,
            'name': emp['name']?.toString() ?? '',
            'updatedAt': emp['updatedAt']?.toString() ?? DateTime.now().toIso8601String(),
            'deletedAt': emp['deletedAt']?.toString(),
            'isSynced': 1,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }

        // 10. VietQR Bank Accounts
        final bankAccounts = (snapshot['vietqrBankAccounts'] as List?) ?? [];
        for (final ba in bankAccounts) {
          if (ba is! Map) continue;
          final baId = ba['id']?.toString() ?? '';
          if (baId.isEmpty) continue;
          await txn.insert('vietqr_bank_accounts', {
            'id': baId,
            'bankApiId': (ba['bankApiId'] as num?)?.toInt() ?? int.tryParse(ba['bankApiId']?.toString() ?? '0'),
            'name': ba['name']?.toString(),
            'code': ba['code']?.toString(),
            'bin': ba['bin']?.toString(),
            'shortName': ba['shortName']?.toString() ?? ba['short_name']?.toString(),
            'logo': ba['logo']?.toString(),
            'transferSupported': (ba['transferSupported'] == true || ba['transferSupported'] == 1 || ba['transferSupported'] == '1') ? 1 : 0,
            'lookupSupported': (ba['lookupSupported'] == true || ba['lookupSupported'] == 1 || ba['lookupSupported'] == '1') ? 1 : 0,
            'support': (ba['support'] as num?)?.toInt() ?? int.tryParse(ba['support']?.toString() ?? '0'),
            'isTransfer': (ba['isTransfer'] == true || ba['isTransfer'] == 1 || ba['isTransfer'] == '1') ? 1 : 0,
            'swiftCode': ba['swiftCode']?.toString() ?? ba['swift_code']?.toString(),
            'accountNo': ba['accountNo']?.toString() ?? '',
            'accountName': ba['accountName']?.toString() ?? '',
            'isDefault': (ba['isDefault'] == true || ba['isDefault'] == 1 || ba['isDefault'] == '1') ? 1 : 0,
            'updatedAt': ba['updatedAt']?.toString() ?? DateTime.now().toIso8601String(),
            'deletedAt': ba['deletedAt']?.toString(),
            'isSynced': 1,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }

        // 11. Store Info
        final storeInfoList = (snapshot['storeInfo'] as List?) ?? [];
        if (storeInfoList.isNotEmpty && storeInfoList.first is Map) {
          final si = storeInfoList.first as Map;
          await txn.insert('store_info', {
            'id': (si['id'] as num?)?.toInt() ?? 1,
            'name': si['name']?.toString() ?? '',
            'address': si['address']?.toString() ?? '',
            'phone': si['phone']?.toString() ?? '',
            'taxCode': si['taxCode']?.toString() ?? si['tax_code']?.toString(),
            'email': si['email']?.toString(),
            'bankName': si['bankName']?.toString() ?? si['bank_name']?.toString(),
            'bankAccount': si['bankAccount']?.toString() ?? si['bank_account']?.toString(),
            'updatedAt': si['updatedAt']?.toString() ?? DateTime.now().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }

        // 12. Product Opening Stocks
        final openingStocks = (snapshot['productOpeningStocks'] as List?) ?? [];
        for (final os in openingStocks) {
          if (os is! Map) continue;
          final prodId = os['productId']?.toString() ?? '';
          final yr = (os['year'] as num?)?.toInt() ?? int.tryParse(os['year']?.toString() ?? '0') ?? 0;
          final mo = (os['month'] as num?)?.toInt() ?? int.tryParse(os['month']?.toString() ?? '0') ?? 0;
          if (prodId.isNotEmpty && yr > 0 && mo > 0) {
            await txn.insert('product_opening_stocks', {
              'productId': prodId,
              'year': yr,
              'month': mo,
              'openingStock': (os['openingStock'] as num?)?.toDouble() ?? double.tryParse(os['openingStock']?.toString() ?? '0') ?? 0.0,
              'updatedAt': os['updatedAt']?.toString() ?? DateTime.now().toIso8601String(),
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }

        // 13. Debt Reminder Settings
        final reminders = (snapshot['debtReminderSettings'] as List?) ?? [];
        for (final dr in reminders) {
          if (dr is! Map) continue;
          final dId = dr['debtId']?.toString() ?? '';
          if (dId.isNotEmpty) {
            await txn.insert('debt_reminder_settings', {
              'debtId': dId,
              'muted': (dr['muted'] == true || dr['muted'] == 1 || dr['muted'] == '1') ? 1 : 0,
              'lastNotifiedAt': dr['lastNotifiedAt']?.toString(),
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      });
  }

  /// Dọn dẹp logs và outbox đã gửi
  Future<void> cleanOldLogs() async {
    try {
      if (_db == null || !_db!.isOpen) return;
      await db.execute('DELETE FROM sync_logs WHERE id NOT IN (SELECT id FROM sync_logs ORDER BY id DESC LIMIT 500)');
      await db.execute('DELETE FROM audit_logs WHERE id NOT IN (SELECT id FROM audit_logs ORDER BY id DESC LIMIT 500)');
      await db.execute('DELETE FROM outbox WHERE status = 1');
    } catch (_) {
      // Ignore
    }
  }

  Future<List<Map<String, dynamic>>> getVietQrBankAccounts() async {
    return db.query(
      'vietqr_bank_accounts',
      where: "(deletedAt IS NULL OR TRIM(deletedAt) = '')",
      orderBy: 'isDefault DESC, updatedAt DESC',
    );
  }

  Future<Map<String, dynamic>?> getDefaultVietQrBankAccount() async {
    final rows = await db.query(
      'vietqr_bank_accounts',
      where: "isDefault = 1 AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first;
  }

  Future<void> upsertVietQrBankAccount(Map<String, dynamic> data) async {
    final id = (data['id']?.toString() ?? '').trim();
    if (id.isEmpty) {
      throw Exception('Missing id');
    }
    final now = DateTime.now();

    final row = <String, Object?>{
      'id': id,
      'bankApiId': data['bankApiId'],
      'name': data['name'],
      'code': data['code'],
      'bin': data['bin'],
      'shortName': data['shortName'],
      'short_name': data['short_name'],
      'logo': data['logo'],
      'transferSupported': data['transferSupported'],
      'lookupSupported': data['lookupSupported'],
      'support': data['support'],
      'isTransfer': data['isTransfer'],
      'swift_code': data['swift_code'],
      'accountNo': data['accountNo'],
      'accountName': data['accountName'],
      'isDefault': data['isDefault'] ?? 0,
      'updatedAt': now.toIso8601String(),
    };

    await db.transaction((txn) async {
      final isDefault = (row['isDefault'] as int?) ?? 0;
      if (isDefault == 1) {
        await txn.update('vietqr_bank_accounts', {'isDefault': 0, 'updatedAt': now.toIso8601String()});
      }
      await txn.insert(
        'vietqr_bank_accounts',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> deleteVietQrBankAccount(String id) async {
    await deleteWithSync('vietqr_bank_accounts', id);
  }

  Future<void> setDefaultVietQrBankAccount(String id) async {
    final now = DateTime.now();
    await db.transaction((txn) async {
      await txn.update('vietqr_bank_accounts', {'isDefault': 0, 'updatedAt': now.toIso8601String()});
      await txn.update(
        'vietqr_bank_accounts',
        {'isDefault': 1, 'updatedAt': now.toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  // Employees
  Future<List<Map<String, dynamic>>> getEmployees() async {
    return db.query('employees', where: "(deletedAt IS NULL OR TRIM(deletedAt) = '')", orderBy: 'id ASC');
  }

  Future<String> _nextEmployeeId() async {
    final rows = await db.query('employees', columns: ['id'], where: "(deletedAt IS NULL OR TRIM(deletedAt) = '')");
    var maxNum = 0;

    for (final r in rows) {
      final id = (r['id']?.toString() ?? '').trim();
      final digits = id.replaceAll(RegExp(r'\D'), '');
      final n = int.tryParse(digits);
      if (n != null && n > maxNum) maxNum = n;
    }
    final next = maxNum + 1;
    return 'NV${next.toString().padLeft(4, '0')}';
  }

  Future<Map<String, dynamic>> createEmployee({required String name}) async {
    final id = await _nextEmployeeId();
    final now = DateTime.now();
    final row = <String, dynamic>{
      'id': id,
      'name': name,
      'updatedAt': now.toIso8601String(),
    };
    await db.insert('employees', row, conflictAlgorithm: ConflictAlgorithm.abort);
    return row;
  }

  Future<void> updateEmployee({required String id, required String name}) async {
    final now = DateTime.now();
    await db.update(
      'employees',
      {
        'name': name,
        'updatedAt': now.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<bool> isEmployeeUsed(String employeeId) async {
    final rows = await db.query(
      'sales',
      columns: ['id'],
      where: "employeeId = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
      whereArgs: [employeeId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> deleteEmployee(String id) async {
    await deleteWithSync('employees', id);
  }

  // Products
  Future<List<Product>> getProducts() async {
    if (_isOnlineMode) {
      return await OnlineApiService.instance.getProducts();
    }
    final rows = await db.query(
      'products',
      where: "isActive = 1 AND (itemType IS NULL OR itemType = 'RAW') AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
      orderBy: 'name ASC',
    );
    return rows.map(Product.fromMap).toList();
  }

  Future<List<Product>> getProductsForSale() async {
    if (_isOnlineMode) {
      return await OnlineApiService.instance.getProductsForSale();
    }
    final rows = await db.query(
      'products',
      where: "isActive = 1 AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
      orderBy: 'name ASC',
    );
    return rows.map(Product.fromMap).toList();
  }

  Future<bool> isProductUsed(String productId) async {
    if (_isOnlineMode) return false;
    final saleCount = Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(1) FROM sale_items WHERE productId = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
            [productId],
          ),
        ) ??
        0;
    if (saleCount > 0) return true;

    final purchaseCount = Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(1) FROM purchase_history WHERE productId = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
            [productId],
          ),
        ) ??
        0;
    return purchaseCount > 0;
  }

  Future<bool> isCustomerUsed(String customerId) async {
    if (_isOnlineMode) return false;
    final saleCount = Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(1) FROM sales WHERE customerId = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
            [customerId],
          ),
        ) ??
        0;
    if (saleCount > 0) return true;

    final debtCount = Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(1) FROM debts WHERE partyId = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
            [customerId],
          ),
        ) ??
        0;
    return debtCount > 0;
  }

  Future<void> deleteCustomerHard(String customerId) async {
    if (_isOnlineMode) {
      await OnlineApiService.instance.deleteCustomer(customerId);
      return;
    }
    await deleteWithSync('customers', customerId);
  }

  Future<void> deleteProductHard(String productId) async {
    if (_isOnlineMode) {
      await OnlineApiService.instance.deleteProduct(productId);
      return;
    }
    await deleteWithSync('products', productId);
  }

  Future<void> insertProduct(Product p) async {
    if (_isOnlineMode) {
      await OnlineApiService.instance.insertProduct(p);
      return;
    }
    await db.insert('products', {
      ...p.toMap(),
      'updatedAt': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateProduct(Product p) async {
    if (_isOnlineMode) {
      await OnlineApiService.instance.updateProduct(p);
      return;
    }
    await db.update('products', {
      ...p.toMap(),
      'updatedAt': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [p.id]);
  }

  Future<void> upsertProduct(Product p, {DateTime? updatedAt}) async {
    if (_isOnlineMode) {
      await OnlineApiService.instance.updateProduct(p);
      return;
    }
    await db.insert('products', {
      ...p.toMap(),
      'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateProductUnit({required String productId, required String unit}) async {
    if (_isOnlineMode) {
      await OnlineApiService.instance.updateProductUnit(productId: productId, unit: unit);
      return;
    }
    await db.update(
      'products',
      {
        'unit': unit,
        'updatedAt': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [productId],
    );
  }

  Future<Map<String, double>> getOpeningStocksForMonth(int year, int month) async {
    final rows = await db.query(
      'product_opening_stocks',
      columns: ['productId', 'openingStock'],
      where: 'year = ? AND month = ?',
      whereArgs: [year, month],
    );
    final map = <String, double>{};
    for (final r in rows) {
      final pid = r['productId'] as String;
      map[pid] = (r['openingStock'] as num?)?.toDouble() ?? 0;
    }
    return map;
  }

  Future<double> getPurchasedQtyForMonth({
    required String productId,
    required int year,
    required int month,
  }) async {
    final start = DateTime(year, month, 1);
    final end = (month == 12) ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
    final rows = await db.rawQuery(
      "SELECT SUM(quantity) as q FROM purchase_history WHERE productId = ? AND createdAt >= ? AND createdAt < ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
      [productId, start.toIso8601String(), end.toIso8601String()],
    );
    final q = rows.isNotEmpty ? rows.first['q'] : null;
    return (q as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getSoldQtyForMonthIncludingMix({
    required String productId,
    required int year,
    required int month,
  }) async {
    final start = DateTime(year, month, 1);
    final end = (month == 12) ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);

    final saleIdRows = await db.rawQuery(
      '''
        SELECT id FROM sales WHERE createdAt >= ? AND createdAt < ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')
      ''',
      [start.toIso8601String(), end.toIso8601String()],
    );

    if (saleIdRows.isEmpty) return 0.0;
    final ids = saleIdRows.map((e) => e['id'] as String).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final items = await db.rawQuery(
      '''
        SELECT productId, quantity, itemType, mixItemsJson
        FROM sale_items
        WHERE saleId IN ($placeholders)
          AND (deletedAt IS NULL OR TRIM(deletedAt) = '')
      ''',
      ids,
    );

    double sold = 0.0;
    for (final m in items) {
      final itemType = (m['itemType']?.toString() ?? '').toUpperCase().trim();
      if (itemType == 'MIX') {
        final raw = (m['mixItemsJson']?.toString() ?? '').trim();
        if (raw.isEmpty) continue;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            for (final e in decoded) {
              if (e is Map) {
                final rid = e['rawProductId']?.toString();
                if (rid != productId) continue;
                sold += (e['rawQty'] as num?)?.toDouble() ?? 0.0;
              }
            }
          }
        } catch (_) {
          continue;
        }
      } else {
        final pid = m['productId'];
        if (pid == productId) {
          sold += (m['quantity'] as num?)?.toDouble() ?? 0.0;
        }
      }
    }
    return sold;
  }

  Future<void> setCurrentStockAndRecalcOpeningStockForMonth({
    required String productId,
    required double newCurrentStock,
    required int year,
    required int month,
  }) async {
    final now = DateTime.now();

    await db.update(
      'products',
      {'currentStock': newCurrentStock, 'updatedAt': now.toIso8601String()},
      where: 'id = ?',
      whereArgs: [productId],
    );

    final sold = await getSoldQtyForMonthIncludingMix(productId: productId, year: year, month: month);
    final purchased = await getPurchasedQtyForMonth(productId: productId, year: year, month: month);
    final opening = (newCurrentStock + sold - purchased).toDouble();
    await upsertOpeningStocksForMonth(year: year, month: month, openingByProductId: {productId: opening});
  }

  Future<void> upsertOpeningStocksForMonth({
    required int year,
    required int month,
    required Map<String, double> openingByProductId,
  }) async {
    final now = DateTime.now();
    final batch = db.batch();
    openingByProductId.forEach((productId, openingStock) {
      batch.insert(
        'product_opening_stocks',
        {
          'productId': productId,
          'year': year,
          'month': month,
          'openingStock': openingStock,
          'updatedAt': now.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    await batch.commit(noResult: true);
  }

  // Customers
  Future<List<Customer>> getCustomers() async {
    if (_isOnlineMode) {
      return await OnlineApiService.instance.getCustomers();
    }
    try {
      final rows = await db.query(
        'customers',
        where: "(deletedAt IS NULL OR TRIM(deletedAt) = '')",
        orderBy: 'name ASC',
      );
      final customers = <Customer>[];
      
      // Process each row
      for (final m in rows) {
        try {
          customers.add(Customer(
            id: m['id'] as String,
            name: m['name'] as String,
            phone: m['phone'] as String?,
            note: m['note'] as String?,
            isSupplier: (m['isSupplier'] as int) == 1,
          ));
          
          developer.log('Đã tải khách hàng: ${m['name']}');
        } catch (e) {
          developer.log('Lỗi khi xử lý khách hàng: $e');
          // Bỏ qua lỗi và tiếp tục với khách hàng tiếp theo
          continue;
        }
      }
      
      developer.log('Tổng số khách hàng đã tải: ${customers.length}');
      return customers;
    } catch (e) {
      developer.log('Lỗi khi lấy danh sách khách hàng:', error: e);
      rethrow;
    }
  }

  Future<void> insertCustomer(Customer c) async {
    if (_isOnlineMode) {
      await OnlineApiService.instance.insertCustomer(c);
      return;
    }
    try {
      await db.insert('customers', {
        'id': c.id,
        'name': c.name,
        'phone': c.phone,
        'note': c.note,
        'isSupplier': c.isSupplier ? 1 : 0,
        'updatedAt': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      
      developer.log('Đã thêm khách hàng: ${c.name} (ID: ${c.id})');
    } catch (e) {
      developer.log('Lỗi khi thêm khách hàng:', error: e);
      rethrow;
    }
  }

  Future<void> updateCustomer(Customer c) async {
    if (_isOnlineMode) {
      await OnlineApiService.instance.updateCustomer(c);
      return;
    }
    try {
      await db.update(
        'customers',
        {
          'name': c.name,
          'phone': c.phone,
          'note': c.note,
          'isSupplier': c.isSupplier ? 1 : 0,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [c.id],
      );
      
      developer.log('Đã cập nhật khách hàng: ${c.name} (ID: ${c.id})');
    } catch (e) {
      developer.log('Lỗi khi cập nhật khách hàng:', error: e);
      rethrow;
    }
  }

  Future<void> upsertCustomer(Customer c, {DateTime? updatedAt}) async {
    if (_isOnlineMode) {
      await OnlineApiService.instance.updateCustomer(c);
      return;
    }
    try {
      await db.insert('customers', {
        'id': c.id,
        'name': c.name,
        'phone': c.phone,
        'note': c.note,
        'isSupplier': c.isSupplier ? 1 : 0,
        'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      
      developer.log('Đã cập nhật/thêm khách hàng: ${c.name} (ID: ${c.id})');
    } catch (e) {
      developer.log('Lỗi khi cập nhật/thêm khách hàng:', error: e);
      rethrow;
    }
  }

  Future<void> insertSale(Sale s) async {
    if (_isOnlineMode) {
      await OnlineApiService.instance.insertSale(s);
      return;
    }
    try {
      // Initialize encryption service
      await EncryptionService.instance.init();
      
      // Encrypt note if it exists
      final encryptedNote = s.note != null ? await EncryptionService.instance.encrypt(s.note!) : null;

      // totalCost:
      // - RAW: lấy costPrice hiện tại trong products
      // - MIX: dùng unitCost/quantity đã được tính từ nguyên liệu
      double totalCost = 0.0;
      final rawProductIds = <String>[];
      for (final it in s.items) {
        final t = (it.itemType ?? '').toUpperCase().trim();
        if (t != 'MIX') rawProductIds.add(it.productId);
      }
      final productMap = <String, double>{};
      if (rawProductIds.isNotEmpty) {
        final productRows = await db.query(
          'products',
          where: "id IN (${List.filled(rawProductIds.length, '?').join(',')}) AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
          whereArgs: rawProductIds,
        );
        for (final p in productRows) {
          productMap[p['id'] as String] = (p['costPrice'] as num?)?.toDouble() ?? 0.0;
        }
      }
      for (final it in s.items) {
        final t = (it.itemType ?? '').toUpperCase().trim();
        if (t == 'MIX') {
          totalCost += (it.unitCost * it.quantity);
        } else {
          totalCost += ((productMap[it.productId] ?? it.unitCost) * it.quantity);
        }
      }

      await db.transaction((txn) async {
        await txn.insert('sales', {
          'id': s.id,
          'createdAt': s.createdAt.toIso8601String(),
          'customerId': s.customerId,
          'customerName': s.customerName,
          'employeeId': s.employeeId,
          'employeeName': s.employeeName,
          'discount': s.discount,
          'paidAmount': s.paidAmount,
          'paymentType': s.paymentType,
          'totalCost': totalCost,
          'note': encryptedNote,
          'updatedAt': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        for (final it in s.items) {
          final t = (it.itemType ?? '').toUpperCase().trim();
          final snapUnitCost = (t == 'MIX')
              ? it.unitCost
              : ((it.unitCost > 0) ? it.unitCost : (productMap[it.productId] ?? 0.0));
          await txn.insert('sale_items', {
            'saleId': s.id,
            'productId': it.productId,
            'name': it.name,
            'unitPrice': it.unitPrice,
            'unitCost': snapUnitCost,
            'quantity': it.quantity,
            'unit': it.unit,
            'itemType': it.itemType,
            'displayName': it.displayName,
            'mixItemsJson': it.mixItemsJson,
            'updatedAt': DateTime.now().toIso8601String(),
            'isSynced': 0,
          });
        }

        // Trừ tồn:
        // - RAW: trừ theo số lượng bán
        // - MIX: không trừ tồn MIX, trừ tồn các RAW theo mixItemsJson
        final qtyByProductId = <String, double>{};
        for (final it in s.items) {
          final t = (it.itemType ?? '').toUpperCase().trim();
          if (t == 'MIX') {
            final raw = (it.mixItemsJson ?? '').trim();
            if (raw.isEmpty) continue;
            try {
              final decoded = jsonDecode(raw);
              if (decoded is List) {
                for (final e in decoded) {
                  if (e is Map) {
                    final rid = e['rawProductId']?.toString();
                    if (rid == null || rid.isEmpty) continue;
                    final rq = (e['rawQty'] as num?)?.toDouble() ?? 0.0;
                    qtyByProductId[rid] = (qtyByProductId[rid] ?? 0) + rq;
                  }
                }
              }
            } catch (_) {
              continue;
            }
          } else {
            final pid = it.productId;
            qtyByProductId[pid] = (qtyByProductId[pid] ?? 0) + it.quantity;
          }
        }
        for (final entry in qtyByProductId.entries) {
          await txn.rawUpdate(
            "UPDATE products SET currentStock = currentStock - ?, updatedAt = ? WHERE id = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
            [entry.value, DateTime.now().toIso8601String(), entry.key],
          );
        }

        await _addAuditTxn(txn, 'sale', s.id, 'create', {
          'total': s.total,
          'discount': s.discount,
          'paidAmount': s.paidAmount,
          'totalCost': totalCost,
        });
      });
    } catch (e) {
      developer.log('Error inserting sale:', error: e);
      rethrow;
    }
  }

  Future<void> updateSaleWithStockAdjustment({
    required Sale oldSale,
    required Sale newSale,
  }) async {
    try {
      final oldOut = _saleStockOutByProductId(oldSale);
      final newOut = _saleStockOutByProductId(newSale);
      final allProductIds = <String>{...oldOut.keys, ...newOut.keys};
      final deltaOut = <String, double>{};
      for (final pid in allProductIds) {
        final d = (newOut[pid] ?? 0) - (oldOut[pid] ?? 0);
        if (d != 0) deltaOut[pid] = d;
      }

      await db.transaction((txn) async {
        for (final entry in deltaOut.entries) {
          await txn.rawUpdate(
            "UPDATE products SET currentStock = currentStock - ?, updatedAt = ? WHERE id = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
            [entry.value, DateTime.now().toIso8601String(), entry.key],
          );
        }

        await EncryptionService.instance.init();
        final encryptedNote = newSale.note != null ? await EncryptionService.instance.encrypt(newSale.note!) : null;

        double totalCost = 0.0;
        final rawProductIds = <String>[];
        for (final it in newSale.items) {
          final t = (it.itemType ?? '').toUpperCase().trim();
          if (t != 'MIX') rawProductIds.add(it.productId);
        }
        final productMap = <String, double>{};
        if (rawProductIds.isNotEmpty) {
          final productRows = await txn.query(
            'products',
            where: "id IN (${List.filled(rawProductIds.length, '?').join(',')}) AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
            whereArgs: rawProductIds,
          );
          for (final p in productRows) {
            productMap[p['id'] as String] = (p['costPrice'] as num?)?.toDouble() ?? 0.0;
          }
        }
        for (final it in newSale.items) {
          final t = (it.itemType ?? '').toUpperCase().trim();
          if (t == 'MIX') {
            totalCost += (it.unitCost * it.quantity);
          } else {
            final snap = it.unitCost;
            final effective = (snap > 0) ? snap : (productMap[it.productId] ?? 0.0);
            totalCost += (effective * it.quantity);
          }
        }

        await txn.insert('sales', {
          'id': newSale.id,
          'createdAt': newSale.createdAt.toIso8601String(),
          'customerId': newSale.customerId,
          'customerName': newSale.customerName,
          'employeeId': newSale.employeeId,
          'employeeName': newSale.employeeName,
          'discount': newSale.discount,
          'paidAmount': newSale.paidAmount,
          'paymentType': newSale.paymentType,
          'totalCost': totalCost,
          'note': encryptedNote,
          'updatedAt': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        final now = DateTime.now().toIso8601String();
        await txn.update(
          'sale_items',
          {'deletedAt': now, 'updatedAt': now, 'isSynced': 0},
          where: "saleId = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
          whereArgs: [newSale.id],
        );
        for (final it in newSale.items) {
          final t = (it.itemType ?? '').toUpperCase().trim();
          final snapUnitCost = (t == 'MIX')
              ? it.unitCost
              : (productMap[it.productId] ?? it.unitCost);
          await txn.insert('sale_items', {
            'saleId': newSale.id,
            'productId': it.productId,
            'name': it.name,
            'unitPrice': it.unitPrice,
            'unitCost': snapUnitCost,
            'quantity': it.quantity,
            'unit': it.unit,
            'itemType': it.itemType,
            'displayName': it.displayName,
            'mixItemsJson': it.mixItemsJson,
            'updatedAt': now,
            'isSynced': 0,
          });
        }

        await _addAuditTxn(txn, 'sale', newSale.id, 'update', {
          'total': newSale.total,
          'discount': newSale.discount,
          'paidAmount': newSale.paidAmount,
          'totalCost': totalCost,
        });
      });
    } catch (e) {
      developer.log('Error updating sale with stock adjustment:', error: e);
      rethrow;
    }
  }

  Future<void> upsertSale(Sale s, {DateTime? updatedAt}) async {
    try {
      await EncryptionService.instance.init();
      final encryptedNote = s.note != null ? await EncryptionService.instance.encrypt(s.note!) : null;

      double totalCost = 0.0;
      final rawProductIds = <String>[];
      for (final it in s.items) {
        final t = (it.itemType ?? '').toUpperCase().trim();
        if (t != 'MIX') rawProductIds.add(it.productId);
      }
      final productMap = <String, double>{};
      if (rawProductIds.isNotEmpty) {
        final productRows = await db.query(
          'products',
          where: "id IN (${List.filled(rawProductIds.length, '?').join(',')}) AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
          whereArgs: rawProductIds,
        );
        for (final p in productRows) {
          productMap[p['id'] as String] = (p['costPrice'] as num?)?.toDouble() ?? 0.0;
        }
      }
      for (final it in s.items) {
        final t = (it.itemType ?? '').toUpperCase().trim();
        if (t == 'MIX') {
          totalCost += (it.unitCost * it.quantity);
        } else {
          totalCost += ((productMap[it.productId] ?? it.unitCost) * it.quantity);
        }
      }

      await db.transaction((txn) async {
        await txn.insert('sales', {
          'id': s.id,
          'createdAt': s.createdAt.toIso8601String(),
          'customerId': s.customerId,
          'customerName': s.customerName,
          'employeeId': s.employeeId,
          'employeeName': s.employeeName,
          'discount': s.discount,
          'paidAmount': s.paidAmount,
          'paymentType': s.paymentType,
          'totalCost': totalCost,
          'note': encryptedNote,
          'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        final now = DateTime.now().toIso8601String();
        await txn.update(
          'sale_items',
          {'deletedAt': now, 'updatedAt': now, 'isSynced': 0},
          where: "saleId = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
          whereArgs: [s.id],
        );
        for (final it in s.items) {
          final t = (it.itemType ?? '').toUpperCase().trim();
          final snapUnitCost = (t == 'MIX')
              ? it.unitCost
              : (productMap[it.productId] ?? it.unitCost);
          await txn.insert('sale_items', {
            'saleId': s.id,
            'productId': it.productId,
            'name': it.name,
            'unitPrice': it.unitPrice,
            'unitCost': snapUnitCost,
            'quantity': it.quantity,
            'unit': it.unit,
            'itemType': it.itemType,
            'displayName': it.displayName,
            'mixItemsJson': it.mixItemsJson,
            'updatedAt': now,
            'isSynced': 0,
          });
        }
      });
    } catch (e) {
      developer.log('Error upserting sale:', error: e);
      rethrow;
    }
  }

  Future<void> deleteSale(String saleId) async {
    if (_isOnlineMode) {
      await OnlineApiService.instance.deleteSale(saleId);
      return;
    }
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      // Soft delete sale_items
      final items = await txn.query(
        'sale_items',
        columns: ['id'],
        where: "saleId = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
        whereArgs: [saleId],
      );

      for (final it in items) {
        final iid = it['id'];
        if (iid == null) continue;
        await _markEntityAsDeletedTxn(txn, 'sale_items', iid.toString());
        await txn.update(
          'sale_items',
          {'deletedAt': now, 'updatedAt': now, 'isSynced': 0},
          where: 'id = ?',
          whereArgs: [iid],
        );
        await _addAuditTxn(txn, 'sale_item', iid.toString(), 'delete', {});
      }

      // Soft delete sale
      await _markEntityAsDeletedTxn(txn, 'sales', saleId);
      await txn.update(
        'sales',
        {'deletedAt': now, 'updatedAt': now, 'isSynced': 0},
        where: "id = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
        whereArgs: [saleId],
      );
      await _addAuditTxn(txn, 'sale', saleId, 'delete', {});
    });
  }

  Future<void> deleteAllSales() async {
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final saleRows = await txn.query(
        'sales',
        columns: ['id'],
        where: "(deletedAt IS NULL OR TRIM(deletedAt) = '')",
      );
      for (final s in saleRows) {
        final sid = (s['id']?.toString() ?? '').trim();
        if (sid.isEmpty) continue;

        // soft delete children
        final items = await txn.query(
          'sale_items',
          columns: ['id'],
          where: "saleId = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
          whereArgs: [sid],
        );
        for (final it in items) {
          final iid = it['id'];
          if (iid == null) continue;
          await _markEntityAsDeletedTxn(txn, 'sale_items', iid.toString());
          await txn.update(
            'sale_items',
            {'deletedAt': now, 'updatedAt': now, 'isSynced': 0},
            where: 'id = ?',
            whereArgs: [iid],
          );
          await _addAuditTxn(txn, 'sale_item', iid.toString(), 'delete', {});
        }

        await _markEntityAsDeletedTxn(txn, 'sales', sid);
        await txn.update(
          'sales',
          {'deletedAt': now, 'updatedAt': now, 'isSynced': 0},
          where: "id = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
          whereArgs: [sid],
        );
      }

      await txn.insert('audit_logs', {
        'entity': 'sale',
        'entityId': '*',
        'action': 'delete_all',
        'at': now,
        'payload': '',
      });
    });
  }

  Future<Map<String, dynamic>> getAllForBackup() async {
    final products = await db.query('products', where: "(deletedAt IS NULL OR TRIM(deletedAt) = '')");
    final customers = await getCustomersForSync();
    final sales = await db.query('sales', where: "(deletedAt IS NULL OR TRIM(deletedAt) = '')");
    final debts = await getDebtsForSync();
    final saleItems = await db.query('sale_items', where: "(deletedAt IS NULL OR TRIM(deletedAt) = '')");
    final purchaseHistory = await db.query('purchase_history', where: "(deletedAt IS NULL OR TRIM(deletedAt) = '')");
    final deletedEntities = await db.query('deleted_entities');
    return {
      'products': products,
      'customers': customers,
      'sales': sales,
      'debts': debts,
      'sale_items': saleItems,
      'purchase_history': purchaseHistory,
      'deleted_entities': deletedEntities,
    };
  }

  Future<void> updateSalePaymentType({required String saleId, String? paymentType}) async {
    if (_isOnlineMode) {
      await OnlineApiService.instance.updateSalePaymentType(saleId: saleId, paymentType: paymentType);
      return;
    }
    final now = DateTime.now();
    await db.update(
      'sales',
      {
        'paymentType': (paymentType == null || paymentType.trim().isEmpty) ? null : paymentType.trim(),
        'updatedAt': now.toIso8601String(),
        'isSynced': 0,
      },
      where: "id = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
      whereArgs: [saleId],
    );
  }

  Future<void> updateDebtPaymentType({required int paymentId, String? paymentType}) async {
    final now = DateTime.now();
    await db.update(
      'debt_payments',
      {
        'paymentType': (paymentType == null || paymentType.trim().isEmpty) ? null : paymentType.trim(),
        'updatedAt': now.toIso8601String(),
        'isSynced': 0,
      },
      where: 'id = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = \'\')',
      whereArgs: [paymentId],
    );
  }

  Future<void> updateAllDebtPaymentsPaymentType({required String debtId, String? paymentType}) async {
    final now = DateTime.now();
    await db.update(
      'debt_payments',
      {
        'paymentType': (paymentType == null || paymentType.trim().isEmpty) ? null : paymentType.trim(),
        'updatedAt': now.toIso8601String(),
        'isSynced': 0,
      },
      where: 'debtId = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = \'\')',
      whereArgs: [debtId],
    );
  }

  // Debt payments API
  Future<void> insertDebtPayment({required String debtId, required double amount, String? note, DateTime? createdAt, String? paymentType}) async {
    if (_isOnlineMode) {
      await OnlineApiService.instance.insertDebtPayment(
        debtId: debtId,
        amount: amount,
        note: note,
        createdAt: createdAt,
        paymentType: paymentType,
      );
      return;
    }
    try {
      // Initialize encryption service
      await EncryptionService.instance.init();
      
      // Encrypt note if not null
      final encryptedNote = note != null 
          ? await EncryptionService.instance.encrypt(note)
          : null;
      final now = DateTime.now().toIso8601String();
      final uuid = _uuid.v4();
      await db.insert('debt_payments', {
        'uuid': uuid,
        'debtId': debtId,
        'amount': amount,
        'note': encryptedNote,
        'paymentType': paymentType,
        'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
        'updatedAt': now,
        'isSynced': 0, // Chưa đồng bộ
      });
    } catch (e) {
      developer.log('Error inserting debt payment:', error: e);
      rethrow;
    }
  }

  Future<void> updateDebtPaymentWithAdjustment({
    required int paymentId,
    required String debtId,
    required double newAmount,
    required DateTime newCreatedAt,
    String? newNote,
    String? newPaymentType,
  }) async {
    if (newAmount <= 0) return;
    await db.transaction((txn) async {
      await EncryptionService.instance.init();

      final payRows = await txn.query(
        'debt_payments',
        where: 'id = ? AND debtId = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = \'\')',
        whereArgs: [paymentId, debtId],
        limit: 1,
      );
      if (payRows.isEmpty) {
        throw Exception('Không tìm thấy khoản thanh toán');
      }
      final oldAmount = (payRows.first['amount'] as num?)?.toDouble() ?? 0.0;

      final encryptedNote = newNote != null ? await EncryptionService.instance.encrypt(newNote) : null;

      await txn.update(
        'debt_payments',
        {
          'amount': newAmount,
          'note': encryptedNote,
          'paymentType': newPaymentType,
          'createdAt': newCreatedAt.toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
          'isSynced': 0,
        },
        where: 'id = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = \'\')',
        whereArgs: [paymentId],
      );

      final debtRows = await txn.query(
        'debts',
        columns: ['amount'],
        where: 'id = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = \'\')',
        whereArgs: [debtId],
        limit: 1,
      );
      if (debtRows.isEmpty) {
        throw Exception('Không tìm thấy công nợ');
      }
      final currentRemain = (debtRows.first['amount'] as num?)?.toDouble() ?? 0.0;
      final newRemain = (currentRemain + (oldAmount - newAmount)).clamp(0.0, double.infinity).toDouble();
      final settled = newRemain <= 0;

      await txn.update(
        'debts',
        {
          'amount': newRemain,
          'settled': settled ? 1 : 0,
          'updatedAt': DateTime.now().toIso8601String(),
          'isSynced': 0,
        },
        where: 'id = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = \'\')',
        whereArgs: [debtId],
      );

      await _addAuditTxn(txn, 'debt_payment', paymentId.toString(), 'update', {
        'oldAmount': oldAmount,
        'newAmount': newAmount,
        'newCreatedAt': newCreatedAt.toIso8601String(),
      });
    });
  }

  Future<List<Map<String, dynamic>>> getDebtPayments(String debtId) async {
    if (_isOnlineMode) {
      return await OnlineApiService.instance.getDebtPayments(debtId);
    }
    try {
      final rows = await db.query('debt_payments', 
        where: "debtId = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')", 
        whereArgs: [debtId], 
        orderBy: 'createdAt DESC'
      );
      
      // Process rows asynchronously
      return await Future.wait(rows.map((m) async {
        final note = m['note'] as String?;
        final decryptedNote = note != null 
            ? await EncryptionService.instance.decrypt(note)
            : null;
            
        return {
          ...m,
          'note': decryptedNote,
        };
      }));
    } catch (e) {
      developer.log('Error getting debt payments:', error: e);
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getDebtPaymentsForSync({required String debtId, DateTimeRange? range}) async {
    try {
      await EncryptionService.instance.init();

      String? where;
      List<Object?>? whereArgs;
      if (range != null) {
        final start = DateTime(range.start.year, range.start.month, range.start.day);
        final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59, 999);
        where = 'p.createdAt >= ? AND p.createdAt <= ?';
        whereArgs = [start.toIso8601String(), end.toIso8601String()];
      }

      final rows = await db.rawQuery(
        '''
        SELECT
          p.id as paymentId,
          p.debtId as debtId,
          p.amount as amount,
          p.note as note,
          p.paymentType as paymentType,
          p.createdAt as createdAt,
          p.isSynced as isSynced,
          p.uuid as uuid,
          p.updatedAt as updatedAt,
          d.type as debtType,
          d.partyId as partyId,
          d.partyName as partyName
        FROM debt_payments p
        LEFT JOIN debts d ON d.id = p.debtId
        WHERE p.debtId = ? AND (p.deletedAt IS NULL OR TRIM(p.deletedAt) = '') ${where != null ? 'AND $where' : ''}
        ORDER BY p.createdAt DESC
        ''',
        whereArgs != null ? [debtId, ...whereArgs] : [debtId],
      );

      return await Future.wait(rows.map((m) async {
        final note = m['note'] as String?;
        final decryptedNote = note != null ? await EncryptionService.instance.decrypt(note) : null;
        return {
          ...m,
          'note': decryptedNote,
        };
      }));
    } catch (e) {
      developer.log('Error getting debt payments for sync:', error: e);
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getDebtPaymentById(int id) async {
    try {
      final rows = await db.query('debt_payments', 
        where: "id = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')", 
        whereArgs: [id], 
        limit: 1
      );
      
      if (rows.isEmpty) return null;
      
      final m = rows.first;
      final note = m['note'] as String?;
      final decryptedNote = note != null 
          ? await EncryptionService.instance.decrypt(note)
          : null;
          
      return {
        ...m,
        'note': decryptedNote,
      };
    } catch (e) {
      developer.log('Error getting debt payment by id:', error: e);
      rethrow;
    }
  }

  Future<void> deleteDebtPayment(int id) async {
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'debt_payments',
        columns: ['uuid'],
        where: 'id = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = \'\')',
        whereArgs: [id],
        limit: 1,
      );
      final uuid = (rows.isNotEmpty ? (rows.first['uuid'] as String?)?.trim() : null);
      await _markEntityAsDeletedTxn(txn, 'debt_payments', (uuid == null || uuid.isEmpty) ? id.toString() : uuid);
      await txn.update(
        'debt_payments',
        {'deletedAt': now, 'updatedAt': now, 'isSynced': 0},
        where: 'id = ?',
        whereArgs: [id],
      );
      await _addAuditTxn(txn, 'debt_payment', id.toString(), 'delete', {});
    });
  }

  Future<void> deleteDebt(String debtId) async {
    if (_isOnlineMode) {
      await OnlineApiService.instance.deleteDebt(debtId);
      return;
    }
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final payments = await txn.query(
        'debt_payments',
        columns: ['id', 'uuid'],
        where: "debtId = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = '')",
        whereArgs: [debtId],
      );
      for (final p in payments) {
        final pid = p['id'];
        final uuid = (p['uuid'] as String?)?.trim();
        if (pid == null) continue;
        await _markEntityAsDeletedTxn(txn, 'debt_payments', (uuid == null || uuid.isEmpty) ? pid.toString() : uuid);
        await txn.update(
          'debt_payments',
          {'deletedAt': now, 'updatedAt': now, 'isSynced': 0},
          where: 'id = ?',
          whereArgs: [pid],
        );
        await _addAuditTxn(txn, 'debt_payment', pid.toString(), 'delete', {});
      }

      await _markEntityAsDeletedTxn(txn, 'debts', debtId);
      await txn.update(
        'debts',
        {'deletedAt': now, 'updatedAt': now, 'isSynced': 0},
        where: 'id = ? AND (deletedAt IS NULL OR TRIM(deletedAt) = \'\')',
        whereArgs: [debtId],
      );
      await _addAuditTxn(txn, 'debt', debtId, 'delete', {});
    });
  }

  // Audit helpers
  Future<void> _addAudit(String entity, String entityId, String action, Map<String, dynamic> payload) async {
    await db.insert('audit_logs', {
      'entity': entity,
      'entityId': entityId,
      'action': action,
      'at': DateTime.now().toIso8601String(),
      'payload': payload.toString(),
    });
  }

  Future<void> _addAuditTxn(Transaction txn, String entity, String entityId, String action, Map<String, dynamic> payload) async {
    await txn.insert('audit_logs', {
      'entity': entity,
      'entityId': entityId,
      'action': action,
      'at': DateTime.now().toIso8601String(),
      'payload': payload.toString(),
    });
  }
}