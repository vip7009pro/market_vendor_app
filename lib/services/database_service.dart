import 'dart:async';
import 'dart:io';
import 'dart:developer' as developer;
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
  }

  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'market_vendor.db');
    
    _db = await openDatabase(
      path,
      version: 7, // Tăng version để áp dụng migration
      onCreate: (db, version) async {
        // Tạo các bảng mới nếu chưa tồn tại
        await db.execute('''
          CREATE TABLE IF NOT EXISTS products(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            price REAL NOT NULL,
            unit TEXT NOT NULL,
            barcode TEXT,
            isActive INTEGER NOT NULL DEFAULT 1,
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
            quantity REAL NOT NULL,
            unit TEXT NOT NULL,
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
      },
      onUpgrade: _migrateDatabase,
    );
    
    print('Đã khởi tạo database thành công');
  }

  // Products
  Future<List<Product>> getProducts() async {
    final rows = await db.query('products', orderBy: 'name ASC');
    return rows.map(Product.fromMap).toList();
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

  // Sales
  Future<void> insertSale(Sale s) async {
    try {
      // Initialize encryption service
      await EncryptionService.instance.init();
      
      // Encrypt note if it exists
      final encryptedNote = s.note != null 
          ? await EncryptionService.instance.encrypt(s.note!)
          : null;
      
      await db.transaction((txn) async {
        await txn.insert('sales', {
          'id': s.id,
          'createdAt': s.createdAt.toIso8601String(),
          'customerId': s.customerId,
          'customerName': s.customerName,
          'discount': s.discount,
          'paidAmount': s.paidAmount,
          'note': encryptedNote,
          'updatedAt': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        for (final it in s.items) {
          await txn.insert('sale_items', {
            'saleId': s.id,
            'productId': it.productId,
            'name': it.name,
            'unitPrice': it.unitPrice,
            'quantity': it.quantity,
            'unit': it.unit,
            'isSynced': 0, // Chưa đồng bộ
          });
        }
        await _addAuditTxn(txn, 'sale', s.id, 'create', {
          'total': s.total,
          'discount': s.discount,
          'paidAmount': s.paidAmount,
        });
      });
    } catch (e) {
      developer.log('Error inserting sale:', error: e);
      rethrow;
    }
  }

  Future<void> upsertSale(Sale s, {DateTime? updatedAt}) async {
    try {
      // Initialize encryption service
      await EncryptionService.instance.init();
      
      // Encrypt note if it exists
      final encryptedNote = s.note != null 
          ? await EncryptionService.instance.encrypt(s.note!)
          : null;
      
      await db.transaction((txn) async {
        await txn.insert('sales', {
          'id': s.id,
          'createdAt': s.createdAt.toIso8601String(),
          'customerId': s.customerId,
          'customerName': s.customerName,
          'discount': s.discount,
          'paidAmount': s.paidAmount,
          'note': encryptedNote,
          'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        // Delete existing items
        await txn.delete('sale_items', where: 'saleId = ?', whereArgs: [s.id]);

        // Insert new items
        for (final it in s.items) {
          await txn.insert('sale_items', {
            'saleId': s.id,
            'productId': it.productId,
            'name': it.name,
            'unitPrice': it.unitPrice,
            'quantity': it.quantity,
            'unit': it.unit,
            'isSynced': 0, // Chưa đồng bộ
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
      // Initialize encryption service
      await EncryptionService.instance.init();
      
      final salesRows = await db.query('sales', orderBy: 'createdAt DESC');
      final List<Sale> sales = [];
      
      // Process each sale asynchronously
      await Future.forEach(salesRows, (row) async {
        try {
          // Get sale items
          final items = await db.query(
            'sale_items', 
            where: 'saleId = ?', 
            whereArgs: [row['id']]
          );
          
          // Process sale items
          final saleItems = items
              .map((m) => SaleItem.fromMap({
                    'productId': m['productId'],
                    'name': m['name'],
                    'unitPrice': m['unitPrice'],
                    'quantity': m['quantity'],
                    'unit': m['unit'],
                  }))
              .toList();
          
          // Decrypt note if it exists
          final note = row['note'] as String?;
          final decryptedNote = note != null 
              ? await EncryptionService.instance.decrypt(note)
              : null;
          
          // Create sale object
          final sale = Sale(
            id: row['id'] as String,
            createdAt: DateTime.parse(row['createdAt'] as String),
            customerId: row['customerId'] as String?,
            customerName: row['customerName'] as String?,
            items: saleItems,
            discount: (row['discount'] as num).toDouble(),
            paidAmount: (row['paidAmount'] as num).toDouble(),
            note: decryptedNote,
          );
          
          sales.add(sale);
        } catch (e) {
          developer.log('Error processing sale ${row['id']}: $e', error: e);
          // Continue with other sales even if one fails
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

  // Sum of payments for a debt
  Future<double> getTotalPaidForDebt(String debtId) async {
    final rows = await db.rawQuery(
      'SELECT SUM(amount) as total FROM debt_payments WHERE debtId = ?',
      [debtId],
    );
    final val = rows.isNotEmpty ? rows.first['total'] as num? : null;
    return (val ?? 0).toDouble();
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
    final deletedEntities = await db.query('deleted_entities');
    return {
      'products': products,
      'customers': customers,
      'sales': sales,
      'sale_items': saleItems,
      'debts': debts,
      'deleted_entities': deletedEntities,
    };
  }

  // Debt payments API
  Future<void> insertDebtPayment({required String debtId, required double amount, String? note, DateTime? createdAt}) async {
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
        'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
        'isSynced': 0, // Chưa đồng bộ
      });
    } catch (e) {
      developer.log('Error inserting debt payment:', error: e);
      rethrow;
    }
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