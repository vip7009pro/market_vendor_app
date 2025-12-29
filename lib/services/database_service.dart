import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/product.dart';
import '../models/customer.dart';
import '../models/sale.dart';
import '../models/debt.dart';
import 'encryption_service.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._();
  DatabaseService._();

  Database? _db;
  Database get db => _db!;
  String? _deviceId;
  final Uuid _uuid = const Uuid();
  
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
        final r = await db.rawQuery('SELECT COUNT(1) as c FROM $t');
        final c = (r.isNotEmpty ? r.first['c'] : 0) as int?;
        if ((c ?? 0) > 0) return true;
      } catch (_) {
        continue;
      }
    }
    return false;
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
  
  // Lấy thời gian đồng bộ cuối cùng
  Future<DateTime?> getLastSyncTime(String table) async {
    final db = await this.db;
    final result = await db.rawQuery(
      'SELECT MAX(updatedAt) as lastSync FROM $table WHERE isSynced = 1'
    );
    
    final lastSync = result.first['lastSync'] as String?;
    return lastSync != null ? DateTime.parse(lastSync) : null;
  }
  
  // Đánh dấu các bản ghi đã đồng bộ
  Future<void> markAsSynced(String table, List<String> ids) async {
    if (ids.isEmpty) return;
    
    final db = await this.db;
    await db.update(
      table,
      {'isSynced': 1},
      where: 'id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  }
  
  // Lấy các bản ghi chưa đồng bộ
  Future<List<Map<String, dynamic>>> getUnsyncedRecords(String table) async {
    final db = await this.db;
    return await db.query(
      table,
      where: 'isSynced = ?',
      whereArgs: [0], // 0 = false
    );
  }
  
  // Lấy danh sách các bản ghi đã bị xóa chưa đồng bộ
  Future<List<Map<String, dynamic>>> getUnsyncedDeletions() async {
    try {
      final db = await this.db;
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
  }) async {
    final now = DateTime.now();
    final created = createdAt ?? now;
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
          'updatedAt': now.toIso8601String(),
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
          'updatedAt': now.toIso8601String(),
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

      await txn.delete('purchase_history', where: 'id = ?', whereArgs: [id]);
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
    final now = DateTime.now().toIso8601String();
    await db.update(
      'purchase_history',
      {
        'purchaseDocUploaded': 1,
        'purchaseDocFileId': fileId,
        'purchaseDocUpdatedAt': now,
        'updatedAt': now,
      },
      where: 'id = ?',
      whereArgs: [purchaseId],
    );
  }

  Future<void> clearPurchaseDoc({required String purchaseId}) async {
    final now = DateTime.now().toIso8601String();
    await db.update(
      'purchase_history',
      {
        'purchaseDocUploaded': 0,
        'purchaseDocFileId': null,
        'purchaseDocUpdatedAt': now,
        'updatedAt': now,
      },
      where: 'id = ?',
      whereArgs: [purchaseId],
    );
  }

  Future<String> insertExpense({
    required DateTime occurredAt,
    required double amount,
    required String category,
    String? note,
  }) async {
    final now = DateTime.now().toIso8601String();
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
        'updatedAt': now,
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
    final now = DateTime.now().toIso8601String();
    await db.update(
      'expenses',
      {
        'occurredAt': occurredAt.toIso8601String(),
        'amount': amount,
        'category': category,
        'note': note,
        'updatedAt': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteExpense(String id) async {
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getExpenses({
    DateTimeRange? range,
    String? category,
    String? query,
  }) async {
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
    final now = DateTime.now().toIso8601String();
    await db.update(
      'expenses',
      {
        'expenseDocUploaded': 1,
        'expenseDocFileId': fileId,
        'expenseDocUpdatedAt': now,
        'updatedAt': now,
      },
      where: 'id = ?',
      whereArgs: [expenseId],
    );
  }

  Future<void> clearExpenseDoc({required String expenseId}) async {
    final now = DateTime.now().toIso8601String();
    await db.update(
      'expenses',
      {
        'expenseDocUploaded': 0,
        'expenseDocFileId': null,
        'expenseDocUpdatedAt': now,
        'updatedAt': now,
      },
      where: 'id = ?',
      whereArgs: [expenseId],
    );
  }

  Future<double> getTotalExpensesInRange(DateTimeRange range) async {
    final start = DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59, 999);
    final rows = await db.rawQuery(
      'SELECT SUM(amount) as total FROM expenses WHERE occurredAt >= ? AND occurredAt <= ?',
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
    final now = DateTime.now().toIso8601String();
    final devId = await deviceId;

    final newData = Map<String, dynamic>.from(data)
      ..addAll({
        'deviceId': devId,
        'createdAt': now,
        'updatedAt': now,
        'isSynced': 0, // Chưa đồng bộ
      });

    await db.insert(table, newData);

    // Ghi log
    await _logSyncAction('create', table, newData['id'], devId, now);
  }

  // Cập nhật bản ghi với thông tin đồng bộ
  Future<int> updateWithSync(String table, Map<String, dynamic> data, String id) async {
    final now = DateTime.now().toIso8601String();
    final devId = await deviceId;

    final updatedData = Map<String, dynamic>.from(data)
      ..addAll({
        'updatedAt': now,
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
      await _logSyncAction('update', table, id, devId, now);
    }

    return count;
  }

  // Xóa bản ghi với thông tin đồng bộ
  Future<int> deleteWithSync(String table, String id) async {
    final now = DateTime.now().toIso8601String();
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
        'deletedAt': now,
        'deviceId': devId,
        'isSynced': 0, // Chưa đồng bộ
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // Ghi log
      await _logSyncAction('delete', table, id, devId, now);
    }

    // Thực hiện xóa
    return await db.delete(
      table,
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
      print('Đã thêm cột $column vào bảng $table');
    } on DatabaseException catch (e) {
      // Bỏ qua lỗi "cột đã tồn tại"
      if (!e.toString().contains('duplicate column')) {
        rethrow;
      }
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
            updatedAt TEXT NOT NULL
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
            updatedAt TEXT NOT NULL
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
  }

  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'market_vendor.db');

    _db = await openDatabase(
      path,
      version: 22, // Tăng version để áp dụng migration
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
            isSynced INTEGER NOT NULL DEFAULT 0
          )
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS sales(
            id TEXT PRIMARY KEY,
            createdAt TEXT NOT NULL,
            customerId TEXT,
            customerName TEXT,
            discount REAL NOT NULL DEFAULT 0,
            paidAmount REAL NOT NULL DEFAULT 0,
            paymentType TEXT,
            totalCost REAL NOT NULL DEFAULT 0, -- Thêm cột totalCost
            note TEXT,
            updatedAt TEXT NOT NULL,
            deviceId TEXT,
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
            amount REAL NOT NULL,
            description TEXT,
            dueDate TEXT,
            settled INTEGER NOT NULL DEFAULT 0,
            sourceType TEXT,
            sourceId TEXT,
            updatedAt TEXT NOT NULL,
            deviceId TEXT,
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
            debtId TEXT NOT NULL,
            amount REAL NOT NULL,
            note TEXT,
            paymentType TEXT,
            createdAt TEXT NOT NULL,
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
            updatedAt TEXT NOT NULL
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
            updatedAt TEXT NOT NULL
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
      },
      onUpgrade: _migrateDatabase,
      onDowngrade: (db, oldVersion, newVersion) async {
        // IMPORTANT: Tránh sqflite mặc định xóa DB khi downgrade (gây mất dữ liệu sau restore)
        // Giữ nguyên database hiện tại và không thực hiện gì.
        print('DB downgrade detected (old=$oldVersion, new=$newVersion). Skip downgrade to avoid data loss.');
      },
    );
    
    print('Đã khởi tạo database thành công');
  }

  // Products
  Future<List<Product>> getProducts() async {
    final rows = await db.query(
      'products',
      where: "isActive = 1 AND (itemType IS NULL OR itemType = 'RAW')",
      orderBy: 'name ASC',
    );
    return rows.map(Product.fromMap).toList();
  }

  Future<List<Product>> getProductsForSale() async {
    final rows = await db.query(
      'products',
      where: 'isActive = 1',
      orderBy: 'name ASC',
    );
    return rows.map(Product.fromMap).toList();
  }

  Future<bool> isProductUsed(String productId) async {
    final saleCount = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(1) FROM sale_items WHERE productId = ?',
            [productId],
          ),
        ) ??
        0;
    if (saleCount > 0) return true;

    final purchaseCount = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(1) FROM purchase_history WHERE productId = ?',
            [productId],
          ),
        ) ??
        0;
    return purchaseCount > 0;
  }

  Future<bool> isCustomerUsed(String customerId) async {
    final saleCount = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(1) FROM sales WHERE customerId = ?',
            [customerId],
          ),
        ) ??
        0;
    if (saleCount > 0) return true;

    final debtCount = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(1) FROM debts WHERE partyId = ?',
            [customerId],
          ),
        ) ??
        0;
    return debtCount > 0;
  }

  Future<void> deleteCustomerHard(String customerId) async {
    await db.delete('customers', where: 'id = ?', whereArgs: [customerId]);
  }

  Future<void> deleteProductHard(String productId) async {
    await db.transaction((txn) async {
      await txn.delete('product_opening_stocks', where: 'productId = ?', whereArgs: [productId]);
      await txn.delete('products', where: 'id = ?', whereArgs: [productId]);
    });
  }

  Future<void> insertProduct(Product p) async {
    await db.insert('products', {
      ...p.toMap(),
      'updatedAt': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateProduct(Product p) async {
    await db.update('products', {
      ...p.toMap(),
      'updatedAt': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [p.id]);
  }

  Future<void> upsertProduct(Product p, {DateTime? updatedAt}) async {
    await db.insert('products', {
      ...p.toMap(),
      'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateProductUnit({required String productId, required String unit}) async {
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
      'SELECT SUM(quantity) as q FROM purchase_history WHERE productId = ? AND createdAt >= ? AND createdAt < ?',
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

    final saleIds = await db.rawQuery(
      'SELECT id FROM sales WHERE createdAt >= ? AND createdAt < ?',
      [start.toIso8601String(), end.toIso8601String()],
    );
    if (saleIds.isEmpty) return 0.0;
    final ids = saleIds.map((e) => e['id'] as String).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final items = await db.rawQuery(
      'SELECT productId, quantity, itemType, mixItemsJson FROM sale_items WHERE saleId IN ($placeholders)',
      ids,
    );

    double sold = 0.0;
    for (final m in items) {
      final itemType = (m['itemType']?.toString() ?? '').toUpperCase().trim();
      if (itemType == 'MIX') {
        final rawJson = (m['mixItemsJson']?.toString() ?? '').trim();
        if (rawJson.isEmpty) continue;
        try {
          final decoded = jsonDecode(rawJson);
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
        final pid = (m['productId']?.toString() ?? '');
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
    final now = DateTime.now().toIso8601String();

    await db.update(
      'products',
      {'currentStock': newCurrentStock, 'updatedAt': now},
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
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    openingByProductId.forEach((productId, openingStock) {
      batch.insert(
        'product_opening_stocks',
        {
          'productId': productId,
          'year': year,
          'month': month,
          'openingStock': openingStock,
          'updatedAt': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    await batch.commit(noResult: true);
  }

  // Customers
  Future<List<Customer>> getCustomers() async {
    try {
      final rows = await db.query('customers', orderBy: 'name ASC');
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

  Future<int> backfillSaleItemsUnitCostFromProducts() async {
    // Backfill legacy data where sale_items.unitCost was missing (0)
    // by using current products.costPrice.
    // Only applies to RAW / non-MIX items.
    try {
      final rows = await db.rawUpdate(
        '''
        UPDATE sale_items
        SET unitCost = (
          SELECT p.costPrice
          FROM products p
          WHERE p.id = sale_items.productId
        )
        WHERE (unitCost IS NULL OR unitCost = 0)
          AND productId IS NOT NULL
          AND TRIM(COALESCE(itemType, '')) != 'MIX'
          AND (
            SELECT COALESCE(p.costPrice, 0)
            FROM products p
            WHERE p.id = sale_items.productId
          ) > 0
        ''',
      );
      return rows;
    } catch (e) {
      developer.log('Error backfilling sale_items.unitCost:', error: e);
      rethrow;
    }
  }

  // Sales
  Future<void> insertSale(Sale s) async {
    try {
      await EncryptionService.instance.init();
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
          where: 'id IN (${List.filled(rawProductIds.length, '?').join(',')})',
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
            'UPDATE products SET currentStock = currentStock - ?, updatedAt = ? WHERE id = ?',
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
            'UPDATE products SET currentStock = currentStock - ?, updatedAt = ? WHERE id = ?',
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
            where: 'id IN (${List.filled(rawProductIds.length, '?').join(',')})',
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
            totalCost += ((productMap[it.productId] ?? it.unitCost) * it.quantity);
          }
        }

        await txn.insert('sales', {
          'id': newSale.id,
          'createdAt': newSale.createdAt.toIso8601String(),
          'customerId': newSale.customerId,
          'customerName': newSale.customerName,
          'discount': newSale.discount,
          'paidAmount': newSale.paidAmount,
          'paymentType': newSale.paymentType,
          'totalCost': totalCost,
          'note': encryptedNote,
          'updatedAt': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        await txn.delete('sale_items', where: 'saleId = ?', whereArgs: [newSale.id]);
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
          where: 'id IN (${List.filled(rawProductIds.length, '?').join(',')})',
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
          'discount': s.discount,
          'paidAmount': s.paidAmount,
          'paymentType': s.paymentType,
          'totalCost': totalCost,
          'note': encryptedNote,
          'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        await txn.delete('sale_items', where: 'saleId = ?', whereArgs: [s.id]);
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
            'isSynced': 0,
          });
        }
      });
    } catch (e) {
      developer.log('Error upserting sale:', error: e);
      rethrow;
    }
  }

  Future<List<Sale>> getSales() async {
    try {
      await EncryptionService.instance.init();
      final salesRows = await db.query('sales', orderBy: 'createdAt DESC');
      final List<Sale> sales = [];
      await Future.forEach(salesRows, (row) async {
        try {
          final items = await db.query(
            'sale_items',
            where: 'saleId = ?',
            whereArgs: [row['id']],
          );

          final saleItems = items
              .map((m) => SaleItem.fromMap({
                    'productId': m['productId'],
                    'name': m['name'],
                    'unitPrice': m['unitPrice'],
                    'unitCost': m['unitCost'],
                    'quantity': m['quantity'],
                    'unit': m['unit'],
                    'itemType': m['itemType'],
                    'displayName': m['displayName'],
                    'mixItemsJson': m['mixItemsJson'],
                  }))
              .toList();

          final note = row['note'] as String?;
          final decryptedNote = note != null ? await EncryptionService.instance.decrypt(note) : null;
          final totalCost = (row['totalCost'] as num?)?.toDouble() ?? 0.0;

          sales.add(
            Sale(
              id: row['id'] as String,
              createdAt: DateTime.parse(row['createdAt'] as String),
              customerId: row['customerId'] as String?,
              customerName: row['customerName'] as String?,
              items: saleItems,
              discount: (row['discount'] as num).toDouble(),
              paidAmount: (row['paidAmount'] as num).toDouble(),
              paymentType: row['paymentType'] as String?,
              note: decryptedNote,
              totalCost: totalCost,
            ),
          );
        } catch (e) {
          developer.log('Error processing sale ${row['id']}: $e', error: e);
        }
      });
      return sales;
    } catch (e) {
      developer.log('Error getting sales:', error: e);
      rethrow;
    }
  }

  // Debts
  Future<void> insertDebt(Debt d) async {
    try {
      // Initialize encryption service
      await EncryptionService.instance.init();
      
      // Encrypt description if it exists
      final encryptedDescription = d.description != null 
          ? await EncryptionService.instance.encrypt(d.description!)
          : null;
      
      await db.insert('debts', {
        'id': d.id,
        'createdAt': d.createdAt.toIso8601String(),
        'type': d.type == DebtType.oweOthers ? 0 : 1,
        'partyId': d.partyId,
        'partyName': d.partyName,
        'amount': d.amount,
        'description': encryptedDescription,
        'dueDate': d.dueDate?.toIso8601String(),
        'settled': d.settled ? 1 : 0,
        'sourceType': d.sourceType,
        'sourceId': d.sourceId,
        'updatedAt': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      
      await _addAudit('debt', d.id, 'create', {
        'amount': d.amount,
        'partyName': d.partyName,
        'settled': d.settled,
      });
    } catch (e) {
      developer.log('Error inserting debt:', error: e);
      rethrow;
    }
  }

  Future<void> updateDebt(Debt d) async {
    try {
      // Initialize encryption service
      await EncryptionService.instance.init();
      
      // Encrypt description if it exists
      final encryptedDescription = d.description != null 
          ? await EncryptionService.instance.encrypt(d.description!)
          : null;
      
      await db.update(
        'debts',
        {
          'type': d.type == DebtType.oweOthers ? 0 : 1,
          'partyId': d.partyId,
          'partyName': d.partyName,
          'amount': d.amount,
          'description': encryptedDescription,
          'dueDate': d.dueDate?.toIso8601String(),
          'settled': d.settled ? 1 : 0,
          'sourceType': d.sourceType,
          'sourceId': d.sourceId,
          'updatedAt': DateTime.now().toIso8601String(),
          'isSynced': 0, // Đánh dấu là chưa đồng bộ để đẩy lên Firestore
        },
        where: 'id = ?',
        whereArgs: [d.id],
      );
      
      await _addAudit('debt', d.id, 'update', {
        'amount': d.amount,
        'settled': d.settled,
      });
    } catch (e) {
      developer.log('Error updating debt:', error: e);
      rethrow;
    }
  }

  Future<void> updateDebtWithCreatedAt(Debt d) async {
    try {
      // Initialize encryption service
      await EncryptionService.instance.init();
      
      // Encrypt description if it exists
      final encryptedDescription = d.description != null 
          ? await EncryptionService.instance.encrypt(d.description!)
          : null;
      
      await db.update(
        'debts',
        {
          'createdAt': d.createdAt.toIso8601String(),
          'type': d.type == DebtType.oweOthers ? 0 : 1,
          'partyId': d.partyId,
          'partyName': d.partyName,
          'amount': d.amount,
          'description': encryptedDescription,
          'dueDate': d.dueDate?.toIso8601String(),
          'settled': d.settled ? 1 : 0,
          'sourceType': d.sourceType,
          'sourceId': d.sourceId,
          'updatedAt': DateTime.now().toIso8601String(),
          'isSynced': 0, // Đánh dấu là chưa đồng bộ để đẩy lên Firestore
        },
        where: 'id = ?',
        whereArgs: [d.id],
      );
    } catch (e) {
      developer.log('Error updating debt with createdAt:', error: e);
      rethrow;
    }
  }

  Future<void> upsertDebt(Debt d, {DateTime? updatedAt}) async {
    try {
      // Initialize encryption service
      await EncryptionService.instance.init();
      
      // Encrypt description if not null
      final encryptedDescription = d.description != null 
          ? await EncryptionService.instance.encrypt(d.description!)
          : null;

      await db.insert('debts', {
        'id': d.id,
        'createdAt': d.createdAt.toIso8601String(),
        'type': d.type.index,
        'partyId': d.partyId,
        'partyName': d.partyName,
        'amount': d.amount,
        'description': encryptedDescription,
        'dueDate': d.dueDate?.toIso8601String(),
        'settled': d.settled ? 1 : 0,
        'sourceType': d.sourceType,
        'sourceId': d.sourceId,
        'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      developer.log('Error upserting debt:', error: e);
      rethrow;
    }
  }

  Future<List<Debt>> getDebts() async {
    try {
      // Initialize encryption service
      await EncryptionService.instance.init();
      
      final rows = await db.query('debts', orderBy: 'createdAt DESC');
      
      // Process rows asynchronously
      return await Future.wait(rows.map((m) async {
        final description = m['description'] as String?;
        final decryptedDescription = description != null 
            ? await EncryptionService.instance.decrypt(description)
            : null;
            
        return Debt(
          id: m['id'] as String,
          createdAt: DateTime.parse(m['createdAt'] as String),
          type: (m['type'] as int) == 0 ? DebtType.oweOthers : DebtType.othersOweMe,
          partyId: m['partyId'] as String,
          partyName: m['partyName'] as String,
          amount: (m['amount'] as num).toDouble(),
          description: decryptedDescription,
          dueDate: m['dueDate'] != null ? DateTime.parse(m['dueDate'] as String) : null,
          settled: (m['settled'] as int) == 1,
          sourceType: m['sourceType'] as String?,
          sourceId: m['sourceId'] as String?,
        );
      }));
    } catch (e) {
      developer.log('Error getting debts:', error: e);
      rethrow;
    }
  }

  // Sync helpers
  Future<Map<String, DateTime>> getUpdatedAtMap(String table) async {
    final rows = await db.query(table, columns: ['id', 'updatedAt']);
    final map = <String, DateTime>{};
    for (final r in rows) {
      final id = r['id'] as String;
      final ua = r['updatedAt'] as String?;
      if (ua != null) map[id] = DateTime.parse(ua);
    }
    return map;
  }

  Future<List<Map<String, dynamic>>> getProductsForSync() async {
    final rows = await db.query('products');
    return rows;
  }

  Future<List<Map<String, dynamic>>> getCustomersForSync() async {
    try {
      // Initialize encryption service
      await EncryptionService.instance.init();
      
      final rows = await db.query('customers');
      
      // Process rows asynchronously
      return await Future.wait(rows.map((m) async {
        final phone = m['phone'] as String?;
        final note = m['note'] as String?;
        
        // Decrypt fields in parallel
        final decrypted = await Future.wait([
          phone != null ? EncryptionService.instance.decrypt(phone) : Future.value(null),
          note != null ? EncryptionService.instance.decrypt(note) : Future.value(null),
        ]);
        
        return {
          ...m,
          'phone': decrypted[0],
          'note': decrypted[1],
        };
      }));
    } catch (e) {
      developer.log('Error getting customers for sync:', error: e);
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getDebtsForSync() async {
    try {
      // Initialize encryption service
      await EncryptionService.instance.init();
      
      final rows = await db.query('debts');
      
      // Process rows asynchronously
      return await Future.wait(rows.map((m) async {
        final description = m['description'] as String?;
        final decryptedDescription = description != null 
            ? await EncryptionService.instance.decrypt(description)
            : null;
            
        return {
          ...m,
          'description': decryptedDescription,
        };
      }));
    } catch (e) {
      developer.log('Error getting debts for sync:', error: e);
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getSalesForSync() async {
    try {
      // Initialize encryption service
      await EncryptionService.instance.init();
      
      final rows = await db.query('sales');
      
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
      developer.log('Error getting sales for sync:', error: e);
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getSaleItems(String saleId) async {
    return await db.query('sale_items', where: 'saleId = ?', whereArgs: [saleId]);
  }

  Future<Map<String, double>?> getSaleTotals(String saleId) async {
    final rows = await db.query(
      'sales',
      columns: ['totalCost', 'discount', 'paidAmount'],
      where: 'id = ?',
      whereArgs: [saleId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final m = rows.first;
    final totalCost = (m['totalCost'] as num?)?.toDouble() ?? 0.0;
    final discount = (m['discount'] as num?)?.toDouble() ?? 0.0;
    final paidAmount = (m['paidAmount'] as num?)?.toDouble() ?? 0.0;
    final total = (totalCost - discount).clamp(0.0, double.infinity).toDouble();
    return {
      'total': total,
      'paidAmount': paidAmount,
    };
  }

  // Sum of payments for a debt
  Future<double> getTotalPaidForDebt(String debtId) async {
    final rows = await db.rawQuery(
      'SELECT SUM(amount) as total FROM debt_payments WHERE debtId = ?',
      [debtId],
    );
    final val = rows.isNotEmpty ? rows.first['total'] as num? : null;
    return (val ?? 0).toDouble();
  }

  Future<Debt?> getDebtBySource({required String sourceType, required String sourceId}) async {
    await EncryptionService.instance.init();
    final rows = await db.query(
      'debts',
      where: 'sourceType = ? AND sourceId = ?',
      whereArgs: [sourceType, sourceId],
      orderBy: 'createdAt DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final m = rows.first;
    final description = m['description'] as String?;
    final decryptedDescription =
        description != null ? await EncryptionService.instance.decrypt(description) : null;

    return Debt(
      id: m['id'] as String,
      createdAt: DateTime.parse(m['createdAt'] as String),
      type: (m['type'] as int) == 0 ? DebtType.oweOthers : DebtType.othersOweMe,
      partyId: m['partyId'] as String,
      partyName: m['partyName'] as String,
      amount: (m['amount'] as num).toDouble(),
      description: decryptedDescription,
      dueDate: m['dueDate'] != null ? DateTime.parse(m['dueDate'] as String) : null,
      settled: (m['settled'] as int) == 1,
      sourceType: m['sourceType'] as String?,
      sourceId: m['sourceId'] as String?,
    );
  }

  Future<Debt?> getDebtById(String debtId) async {
    try {
      await EncryptionService.instance.init();
      final rows = await db.query(
        'debts',
        where: 'id = ?',
        whereArgs: [debtId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final m = rows.first;
      final description = m['description'] as String?;
      final decryptedDescription = description != null ? await EncryptionService.instance.decrypt(description) : null;
      return Debt(
        id: m['id'] as String,
        createdAt: DateTime.parse(m['createdAt'] as String),
        type: (m['type'] as int) == 0 ? DebtType.oweOthers : DebtType.othersOweMe,
        partyId: m['partyId'] as String,
        partyName: m['partyName'] as String,
        amount: (m['amount'] as num).toDouble(),
        description: decryptedDescription,
        dueDate: m['dueDate'] != null ? DateTime.parse(m['dueDate'] as String) : null,
        settled: (m['settled'] as int) == 1,
        sourceType: m['sourceType'] as String?,
        sourceId: m['sourceId'] as String?,
      );
    } catch (e) {
      developer.log('Error getting debt by id:', error: e);
      rethrow;
    }
  }

  Future<void> muteDebtReminder(String debtId) async {
    await db.insert(
      'debt_reminder_settings',
      {
        'debtId': debtId,
        'muted': 1,
        'lastNotifiedAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> markDebtNotifiedToday(String debtId) async {
    await db.insert(
      'debt_reminder_settings',
      {
        'debtId': debtId,
        'muted': 0,
        'lastNotifiedAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Debt>> getDebtsToRemind() async {
    await EncryptionService.instance.init();

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final sevenDaysAgo = now.subtract(const Duration(days: 7));

    final rows = await db.rawQuery(
      '''
      SELECT d.*,
             s.muted as muted,
             s.lastNotifiedAt as lastNotifiedAt
      FROM debts d
      LEFT JOIN debt_reminder_settings s ON s.debtId = d.id
      WHERE d.settled = 0
        AND (
          (d.dueDate IS NOT NULL AND d.dueDate <= ?)
          OR
          (d.dueDate IS NULL AND d.createdAt <= ?)
        )
        AND (s.muted IS NULL OR s.muted = 0)
      ORDER BY d.createdAt DESC
      ''',
      [now.toIso8601String(), sevenDaysAgo.toIso8601String()],
    );

    final result = <Debt>[];
    for (final m in rows) {
      final lastNotified = m['lastNotifiedAt'] as String?;
      if (lastNotified != null) {
        final dt = DateTime.tryParse(lastNotified);
        if (dt != null && !dt.isBefore(todayStart) && dt.isBefore(todayEnd)) {
          continue;
        }
      }

      final description = m['description'] as String?;
      final decryptedDescription =
          description != null ? await EncryptionService.instance.decrypt(description) : null;

      result.add(
        Debt(
          id: m['id'] as String,
          createdAt: DateTime.parse(m['createdAt'] as String),
          type: (m['type'] as int) == 0 ? DebtType.oweOthers : DebtType.othersOweMe,
          partyId: m['partyId'] as String,
          partyName: m['partyName'] as String,
          amount: (m['amount'] as num).toDouble(),
          description: decryptedDescription,
          dueDate: m['dueDate'] != null ? DateTime.parse(m['dueDate'] as String) : null,
          settled: (m['settled'] as int) == 1,
          sourceType: m['sourceType'] as String?,
          sourceId: m['sourceId'] as String?,
        ),
      );
    }

    return result;
  }

  Future<void> _markEntityAsDeletedTxn(Transaction txn, String table, String id) async {
    final devId = await deviceId;
    await txn.insert('deleted_entities', {
      'entityType': table,
      'entityId': id,
      'deletedAt': DateTime.now().toIso8601String(),
      'deviceId': devId,
      'isSynced': 0, // Chưa đồng bộ
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteSale(String saleId) async {
    await db.transaction((txn) async {
      // Ghi nhận xóa cho tất cả sale_items thuộc sale này để đồng bộ xóa trên Firestore
      final items = await txn.query(
        'sale_items',
        columns: ['id'],
        where: 'saleId = ?',
        whereArgs: [saleId],
      );
      for (final it in items) {
        final iid = it['id'];
        if (iid != null) {
          await _markEntityAsDeletedTxn(txn, 'sale_items', iid.toString());
          await _addAuditTxn(txn, 'sale_item', iid.toString(), 'delete', {});
        }
      }

      // Xóa dữ liệu local
      await txn.delete('sale_items', where: 'saleId = ?', whereArgs: [saleId]);
      await txn.delete('sales', where: 'id = ?', whereArgs: [saleId]);

      // Ghi nhận xóa sale để đồng bộ lên Firestore
      await _markEntityAsDeletedTxn(txn, 'sales', saleId);
      await _addAuditTxn(txn, 'sale', saleId, 'delete', {});
    });
  }

  Future<void> deleteAllSales() async {
    await db.transaction((txn) async {
      await txn.delete('sale_items');
      await txn.delete('sales');
      await txn.insert('audit_logs', {
        'entity': 'sale',
        'entityId': '*',
        'action': 'delete_all',
        'at': DateTime.now().toIso8601String(),
        'payload': '',
      });
    });
  }

  Future<Map<String, dynamic>> getAllForBackup() async {
    final products = await db.query('products');
    final customers = await getCustomersForSync();
    final sales = await db.query('sales');
    final debts = await getDebtsForSync();
    final saleItems = await db.query('sale_items');
    final purchaseHistory = await db.query('purchase_history');
    final deletedEntities = await db.query('deleted_entities');
    return {
      'products': products,
      'customers': customers,
      'sales': sales,
      'sale_items': saleItems,
      'debts': debts,
      'purchase_history': purchaseHistory,
      'deleted_entities': deletedEntities,
    };
  }

  Future<void> updateSalePaymentType({required String saleId, String? paymentType}) async {
    final now = DateTime.now().toIso8601String();
    await db.update(
      'sales',
      {
        'paymentType': (paymentType == null || paymentType.trim().isEmpty) ? null : paymentType.trim(),
        'updatedAt': now,
        'isSynced': 0,
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );
  }

  Future<void> updateDebtPaymentType({required int paymentId, String? paymentType}) async {
    await db.update(
      'debt_payments',
      {
        'paymentType': (paymentType == null || paymentType.trim().isEmpty) ? null : paymentType.trim(),
        'isSynced': 0,
      },
      where: 'id = ?',
      whereArgs: [paymentId],
    );
  }

  Future<void> updateAllDebtPaymentsPaymentType({required String debtId, String? paymentType}) async {
    await db.update(
      'debt_payments',
      {
        'paymentType': (paymentType == null || paymentType.trim().isEmpty) ? null : paymentType.trim(),
        'isSynced': 0,
      },
      where: 'debtId = ?',
      whereArgs: [debtId],
    );
  }

  // Debt payments API
  Future<void> insertDebtPayment({required String debtId, required double amount, String? note, DateTime? createdAt, String? paymentType}) async {
    try {
      // Initialize encryption service
      await EncryptionService.instance.init();
      
      // Encrypt note if not null
      final encryptedNote = note != null 
          ? await EncryptionService.instance.encrypt(note)
          : null;
          
      await db.insert('debt_payments', {
        'debtId': debtId,
        'amount': amount,
        'note': encryptedNote,
        'paymentType': paymentType,
        'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
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
        where: 'id = ? AND debtId = ?',
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
          'isSynced': 0,
        },
        where: 'id = ?',
        whereArgs: [paymentId],
      );

      final debtRows = await txn.query(
        'debts',
        columns: ['amount'],
        where: 'id = ?',
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
        where: 'id = ?',
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
    try {
      final rows = await db.query('debt_payments', 
        where: 'debtId = ?', 
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

  Future<List<Map<String, dynamic>>> getDebtPaymentsForSync({DateTimeRange? range}) async {
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
          d.type as debtType,
          d.partyId as partyId,
          d.partyName as partyName
        FROM debt_payments p
        LEFT JOIN debts d ON d.id = p.debtId
        ${where != null ? 'WHERE $where' : ''}
        ORDER BY p.createdAt DESC
        ''',
        whereArgs,
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
        where: 'id = ?', 
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
    // Ghi nhận xóa để đồng bộ với Firestore, sau đó mới xóa local
    await db.transaction((txn) async {
      await _markEntityAsDeletedTxn(txn, 'debt_payments', id.toString());
      await txn.delete('debt_payments', where: 'id = ?', whereArgs: [id]);
      await _addAuditTxn(txn, 'debt_payment', id.toString(), 'delete', {});
    });
  }
  
  Future<void> deleteDebt(String debtId) async {
    await db.transaction((txn) async {
      // Ghi nhận xóa cho tất cả các payment liên quan để đồng bộ xóa trên Firestore
      final payments = await txn.query(
        'debt_payments',
        columns: ['id'],
        where: 'debtId = ?',
        whereArgs: [debtId],
      );
      for (final p in payments) {
        final pid = p['id'];
        if (pid != null) {
          await _markEntityAsDeletedTxn(txn, 'debt_payments', pid.toString());
          await _addAuditTxn(txn, 'debt_payment', pid.toString(), 'delete', {});
        }
      }

      // Xóa dữ liệu local
      await txn.delete('debt_payments', where: 'debtId = ?', whereArgs: [debtId]);
      await txn.delete('debts', where: 'id = ?', whereArgs: [debtId]);

      // Ghi nhận xóa debt để đồng bộ lên Firestore
      await _markEntityAsDeletedTxn(txn, 'debts', debtId);
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