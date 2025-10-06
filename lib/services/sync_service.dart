import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'database_service.dart';
import '../providers/sale_provider.dart';

class SyncService {
  static SyncService? _instance;
  final GlobalKey<NavigatorState> navigatorKey;
  
  factory SyncService({required GlobalKey<NavigatorState> navigatorKey}) {
    _instance ??= SyncService._internal(navigatorKey);
    return _instance!;
  }
  
  SyncService._internal(this.navigatorKey);

  final DatabaseService _db = DatabaseService.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isInitialized = false;
  bool _isSyncing = false;
  
  // Các hằng số
  static const String _lastSyncKey = 'last_sync_timestamp';
  final List<String> _syncEntities = [
    'products',
    'customers',
    'sales',
    'sale_items',
    'debts',
    'debt_payments',
  ];

  // Hàm xử lý lỗi và ghi log
  void _handleError(dynamic error, StackTrace? stackTrace, {String? context}) {
    final errorMsg = '${context != null ? '$context: ' : ''}$error';
    print('❌ $errorMsg');
    if (stackTrace != null) {
      print('Stack trace: $stackTrace');
    }
    
    // Thông báo lỗi cho người dùng nếu cần
    if (navigatorKey.currentContext != null) {
      final context = navigatorKey.currentContext!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: $error')),
      );
    }
  }

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    
    // Thiết lập cấu hình Firestore
    _firestore.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    
    // Lắng nghe thay đổi trạng thái xác thực
    _auth.authStateChanges().listen((user) {
      if (user != null) {
        // Bắt đầu đồng bộ khi người dùng đăng nhập
        scheduleMicrotask(() => syncNow(userId: user.uid));
      }
    });
  }
  
  // Đồng bộ dữ liệu
  Future<void> syncNow({String? userId}) async {
    if (userId == null) {
      final user = _auth.currentUser;
      if (user == null) return;
      userId = user.uid;
    }
    
    // Tránh đồng bộ đồng thời nhiều lần
    if (_isSyncing) {
      _handleError('Đồng bộ đang được thực hiện, bỏ qua...', null, context: 'syncNow');
      return;
    }
    
    _isSyncing = true;
    
    try {
      print('Bắt đầu quá trình đồng bộ...');
      
      // 1. Đồng bộ các bản ghi đã xóa
      await _syncDeletedEntities(userId);
      
      // 2. Đẩy dữ liệu từ local lên Firestore
      await _pushData(userId);
      
      // 3. Kéo dữ liệu từ Firestore về local
      //await _pullData(userId);
      
      // 4. Cập nhật thời gian đồng bộ cuối cùng
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastSyncKey, DateTime.now().millisecondsSinceEpoch);
      
      print('Đồng bộ hoàn tất!');
      
      // 5. Thông báo cho các provider cập nhật dữ liệu
      await _notifyDataChanged();
    } catch (e) {
      print('Lỗi khi đồng bộ dữ liệu: $e');
      rethrow;
    } finally {
      _isSyncing = false;
    }
  }
  
  // Kéo toàn bộ dữ liệu từ Firestore về local (bỏ qua thời gian đồng bộ)
  Future<void> pullFromFirestore({required String userId}) async {
    if (_isSyncing) {
      print('Đồng bộ đang được thực hiện, vui lòng đợi...');
      return;
    }
    
    _isSyncing = true;
    
    try {
      print('🔄 Bắt đầu tải dữ liệu từ Firestore...');
      print('🔑 User ID: $userId');
      
      for (final entity in _syncEntities) {
        try {
          print('\n📥 Đang tải dữ liệu bảng: $entity');
          
          // Lấy tất cả dữ liệu từ Firestore
          final collectionRef = _firestore
              .collection('users')
              .doc(userId)
              .collection(entity);
              
          print('🔍 Đường dẫn collection: users/$userId/$entity');
          
          // Thêm log để kiểm tra kết nối Firestore
          print('🔄 Đang kết nối đến Firestore...');
          final snapshot = await collectionRef.get();
          print('✅ Kết nối Firestore thành công');
          
          print('📊 Tìm thấy ${snapshot.docs.length} tài liệu trong bảng $entity');
          
          if (snapshot.docs.isEmpty) {
            print('ℹ️ Không có dữ liệu cho bảng: $entity');
            continue;
          }
          
          int successCount = 0;
          int errorCount = 0;
          
          // Xử lý từng tài liệu
          for (final doc in snapshot.docs) {
            try {
              final data = doc.data();
              final id = doc.id;
              
              print('\n📝 Xử lý tài liệu [$entity]: $id');
              print('📂 Dữ liệu gốc: $data');
              
              // Kiểm tra xem bản ghi đã bị xóa chưa
              final isDeleted = await _db.db.query(
                'deleted_entities',
                where: 'entityType = ? AND entityId = ?',
                whereArgs: [entity, id],
              );
              
              if (isDeleted.isEmpty) {
                print('✅ Thêm/cập nhật bản ghi vào local database');
                
                try {
                  // Chuyển đổi dữ liệu Firestore Timestamp thành String
                  final processedData = Map<String, dynamic>.from(data);
                  
                  // Xử lý các trường Timestamp
                  processedData.forEach((key, value) {
                    if (value is Timestamp) {
                      processedData[key] = value.toDate().toIso8601String();
                    }
                  });
                  
                  // Nếu là sale_items hoặc debt_payments, đảm bảo id là int
                  if (entity == 'sale_items' || entity == 'debt_payments') {
                    processedData['id'] = int.parse(id);
                  }
                  
                  // Thêm dữ liệu vào database local
                  await _db.db.insert(
                    entity,
                    {...processedData, 'id': processedData['id'], 'isSynced': 1},
                    conflictAlgorithm: ConflictAlgorithm.replace,
                  );
                  successCount++;
                  print('✅ Đã lưu thành công bản ghi $id vào bảng $entity');
                } catch (e) {
                  errorCount++;
                  print('❌ Lỗi khi lưu bản ghi $id vào bảng $entity: $e');
                  print('📌 Dữ liệu gây lỗi: ${data.toString()}');
                }
              } else {
                print('⏩ Bỏ qua bản ghi đã bị xóa');
              }
            } catch (e) {
              print('❌ Lỗi khi xử lý tài liệu: $e');
              rethrow;
            }
          }
          
          print('✅ Đã tải xong $successCount/${snapshot.docs.length} bản ghi cho bảng: $entity');
          if (errorCount > 0) {
            print('⚠️  Có $errorCount lỗi khi xử lý dữ liệu cho bảng: $entity');
          }
          
        } catch (e) {
          print('❌ Lỗi khi tải dữ liệu bảng $entity: $e');
          rethrow;
        }
      }
      
      // Cập nhật thời gian đồng bộ cuối cùng
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastSyncKey, DateTime.now().millisecondsSinceEpoch);
      
      print('Tải dữ liệu từ Firestore hoàn tất!');
      
    } catch (e) {
      print('Lỗi khi tải dữ liệu từ Firestore: $e');
      rethrow;
    } finally {
      _isSyncing = false;
    }
  }
  
  // Kéo dữ liệu từ Firestore về local (chỉ các bản ghi mới)
  Future<void> _pullData(String userId) async {
    print('Đang kéo dữ liệu từ Firestore về local...');
    
    final lastSync = await _getLastSyncTime();
    
    for (final entity in _syncEntities) {
      try {
        print('Đang đồng bộ bảng: $entity');
        
        // Lấy dữ liệu từ Firestore
        QuerySnapshot snapshot;
        if (lastSync != null) {
          snapshot = await _firestore
              .collection('users')
              .doc(userId)
              .collection(entity)
              .where('updatedAt', isGreaterThan: lastSync.toIso8601String())
              .get();
        } else {
          // Lần đầu đồng bộ, lấy tất cả
          snapshot = await _firestore
              .collection('users')
              .doc(userId)
              .collection(entity)
              .get();
        }
        
        // Xử lý từng tài liệu
        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final id = doc.id;
          
          // Kiểm tra xem bản ghi đã bị xóa chưa
          final isDeleted = await _db.db.query(
            'deleted_entities',
            where: 'entityType = ? AND entityId = ?',
            whereArgs: [entity, id],
          );
          
          if (isDeleted.isEmpty) {
            // Nếu chưa bị xóa, cập nhật hoặc thêm mới
            final processedData = Map<String, dynamic>.from(data);
            
            // Xử lý các trường Timestamp
            processedData.forEach((key, value) {
              if (value is Timestamp) {
                processedData[key] = value.toDate().toIso8601String();
              }
            });
            
            // Nếu là sale_items hoặc debt_payments, đảm bảo id là int
            if (entity == 'sale_items' || entity == 'debt_payments') {
              processedData['id'] = int.parse(id);
            }
            
            await _db.db.insert(
              entity,
              {...processedData, 'id': processedData['id'], 'isSynced': 1},
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
        
      } catch (e) {
        print('Lỗi khi đồng bộ bảng $entity: $e');
        continue;
      }
    }
  }
  
  // Đẩy dữ liệu từ local lên Firestore
  Future<void> _pushData(String userId) async {
    print('Đang đẩy dữ liệu từ local lên Firestore...');
    
    final batchSize = 500; // Kích thước mỗi lô
    
    // 1. Đồng bộ các bản ghi thông thường
    for (final entity in _syncEntities) {
      try {
        print('Đang đẩy dữ liệu bảng: $entity');
        
        // Lấy các bản ghi chưa đồng bộ
        final unsynced = await _db.getUnsyncedRecords(entity);
        
        // Chia thành các lô nhỏ để tránh quá tải
        for (var i = 0; i < unsynced.length; i += batchSize) {
          final batch = _firestore.batch();
          final end = (i + batchSize < unsynced.length) ? i + batchSize : unsynced.length;
          final batchData = unsynced.sublist(i, end);
          
          for (final record in batchData) {
            // Chuyển id sang String cho Firestore
            final recordId = (entity == 'sale_items' || entity == 'debt_payments')
                ? (record['id'] as int).toString()
                : record['id'] as String;
                
            final docRef = _firestore
                .collection('users')
                .doc(userId)
                .collection(entity)
                .doc(recordId);
            
            // Sử dụng merge để tránh ghi đè dữ liệu mới hơn
            batch.set(docRef, record, SetOptions(merge: true));
          }
          
          await batch.commit();
          
          // Đánh dấu là đã đồng bộ
          final syncedIds = batchData
              .map((r) => (entity == 'sale_items' || entity == 'debt_payments')
                  ? (r['id'] as int).toString()
                  : r['id'] as String)
              .toList();
          await _db.markAsSynced(entity, syncedIds);
        }
        
      } catch (e) {
        print('Lỗi khi đẩy dữ liệu bảng $entity: $e');
        continue;
      }
    }
  }
  
  // Đồng bộ các bản ghi đã xóa
  Future<void> _syncDeletedEntities(String userId) async {
    print('Đang đồng bộ các bản ghi đã xóa...');
    
    try {
      // Lấy danh sách các bản ghi đã xóa chưa đồng bộ
      final deletions = await _db.getUnsyncedDeletions();
      
      if (deletions.isEmpty) {
        print('Không có bản ghi đã xóa nào cần đồng bộ');
        return;
      }
      
      print('Đang xử lý ${deletions.length} bản ghi đã xóa...');
      
      // Nhóm các bản ghi đã xóa theo loại thực thể
      final deletionsByType = <String, List<Map<String, dynamic>>>{};
      for (final del in deletions) {
        final type = del['entityType'] as String;
        deletionsByType.putIfAbsent(type, () => []).add(del);
      }
      
      // Xử lý từng loại thực thể
      for (final entry in deletionsByType.entries) {
        final entityType = entry.key;
        final entityDeletions = entry.value;
        
        // Chia thành các lô nhỏ
        for (var i = 0; i < entityDeletions.length; i += 500) {
          final batch = _firestore.batch();
          final end = (i + 500 < entityDeletions.length) ? i + 500 : entityDeletions.length;
          final batchDeletions = entityDeletions.sublist(i, end);
          
          for (final del in batchDeletions) {
            final docRef = _firestore
                .collection('users')
                .doc(userId)
                .collection(entityType)
                .doc(del['entityId'] as String);
            
            batch.delete(docRef);
          }
          
          await batch.commit();
          
          // Đánh dấu là đã đồng bộ
          await _db.markDeletionsAsSynced(batchDeletions);
        }
      }
      
      print('Đã đồng bộ ${deletions.length} bản ghi đã xóa');
      
    } catch (e) {
      print('Lỗi khi đồng bộ các bản ghi đã xóa: $e');
      rethrow;
    }
  }
  
  // Thông báo cho các provider cập nhật dữ liệu
  Future<void> _notifyDataChanged() async {
    try {
      print('🔄 Đang cập nhật dữ liệu mới cho các provider...');
      
      // Kiểm tra xem có context không
      final context = navigatorKey.currentContext;
      if (context == null) {
        print('⚠️ Không thể cập nhật dữ liệu: Không tìm thấy context');
        return;
      }
      
      // Lấy tất cả provider cần refresh
      final saleProvider = Provider.of<SaleProvider>(
        context,
        listen: false,
      );
      
      // Cập nhật dữ liệu mới
      await Future.wait([
        saleProvider.load(),
      ]);
      
      print('✅ Đã cập nhật dữ liệu mới cho các provider');
    } catch (e) {
      print('❌ Lỗi khi cập nhật dữ liệu cho các provider: $e');
      // Không rethrow ở đây để tránh ảnh hưởng đến quá trình đồng bộ chính
    }
  }
  
  // Khởi tạo và bắt đầu đồng bộ
  Future<void> startSync({required String userId}) async {
    if (_isSyncing) {
      print('🔄 Đồng bộ đang được thực hiện, bỏ qua...');
      return;
    }
    
    _isSyncing = true;
    
    try {
      print('🔄 Bắt đầu quá trình đồng bộ cho người dùng: $userId');
      await syncNow(userId: userId);
      print('✅ Đồng bộ hoàn tất cho người dùng: $userId');
    } catch (e) {
      print('❌ Lỗi khi đồng bộ dữ liệu: $e');
      rethrow;
    } finally {
      _isSyncing = false;
    }
  }
  
  // Lấy thời gian đồng bộ cuối cùng
  Future<DateTime?> _getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSyncMillis = prefs.getInt(_lastSyncKey);
    return lastSyncMillis != null 
        ? DateTime.fromMillisecondsSinceEpoch(lastSyncMillis) 
        : null;
  }
  
  // Kiểm tra trạng thái khởi tạo
  bool get isInitialized => _isInitialized;
}