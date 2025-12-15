import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import '../models/customer.dart';
import '../services/database_service.dart';
import '../services/encryption_service.dart';

class CustomerProvider with ChangeNotifier {
  final List<Customer> _customers = [];
  bool _isLoading = false;

  List<Customer> get customers => List.unmodifiable(_customers);
  bool get isLoading => _isLoading;

  // Helper method to safely notify listeners
  void _notifyListenersSafely() {
    // Always schedule the notification for the next frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) {
        notifyListeners();
      }
    });
  }

  Future<void> load() async {
    try {
      print('🔄 Đang tải danh sách khách hàng...');
      _isLoading = true;
      _notifyListenersSafely();
      
      final data = await DatabaseService.instance.getCustomers();
      print('✅ Đã tải thành công ${data.length} khách hàng');
      
      _customers.clear();
      _customers.addAll(data);
      
      // Log một vài khách hàng đầu tiên để kiểm tra
      final count = data.length > 5 ? 5 : data.length;
      print('📋 Danh sách $count khách hàng đầu tiên:');
      for (var i = 0; i < count; i++) {
        print('${i + 1}. ${data[i].name} (ID: ${data[i].id})');
      }
      
    } catch (e) {
      print('❌ Lỗi khi tải danh sách khách hàng: $e');
      rethrow;
    } finally {
      _isLoading = false;
      _notifyListenersSafely();
      print('🏁 Hoàn thành tải danh sách khách hàng');
    }
  }

  Future<void> add(Customer c) async {
    try {
      _isLoading = true;
      _notifyListenersSafely();
      
      // Ensure encryption service is initialized
      await EncryptionService.instance.init();
      
      // Add to local state
      _customers.add(c);
      
      // Save to database
      await DatabaseService.instance.insertCustomer(c);
      
      _notifyListenersSafely();
    } catch (e) {
      // Revert local changes on error
      _customers.remove(c);
      debugPrint('Error adding customer: $e');
      rethrow;
    } finally {
      _isLoading = false;
      _notifyListenersSafely();
    }
  }

  Future<void> update(Customer c) async {
    try {
      _isLoading = true;
      _notifyListenersSafely();
      
      final idx = _customers.indexWhere((e) => e.id == c.id);
      if (idx == -1) {
        throw Exception('Customer not found');
      }
      
      // Ensure encryption service is initialized
      await EncryptionService.instance.init();
      
      // Update local state
      _customers[idx] = c;
      
      // Update in database
      await DatabaseService.instance.updateCustomer(c);
      
      _notifyListenersSafely();
    } catch (e) {
      debugPrint('Error updating customer: $e');
      rethrow;
    } finally {
      _isLoading = false;
      _notifyListenersSafely();
    }
  }

  Future<void> delete(String customerId) async {
    try {
      _isLoading = true;
      _notifyListenersSafely();

      final idx = _customers.indexWhere((e) => e.id == customerId);
      if (idx == -1) return;
      _customers.removeAt(idx);

      await DatabaseService.instance.deleteCustomerHard(customerId);

      _notifyListenersSafely();
    } catch (e) {
      debugPrint('Error deleting customer: $e');
      rethrow;
    } finally {
      _isLoading = false;
      _notifyListenersSafely();
    }
  }
}
