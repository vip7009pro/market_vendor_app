import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/product.dart';
import '../models/customer.dart';
import '../models/sale.dart';
import '../models/debt.dart';
import 'online_sync_service.dart';

class OnlineApiService {
  OnlineApiService._();
  static final OnlineApiService instance = OnlineApiService._();

  final http.Client _client = http.Client();

  Future<String> _getBaseUrl() async {
    return await OnlineSyncService.getBaseUrl();
  }

  Future<Map<String, String>> _getHeaders({bool isJson = true}) async {
    final jwt = await OnlineSyncService.ensureValidJwt();
    final headers = <String, String>{
      'Accept': 'application/json',
    };
    if (isJson) {
      headers['Content-Type'] = 'application/json';
    }
    if (jwt.isNotEmpty) {
      headers['Authorization'] = 'Bearer $jwt';
    }
    return headers;
  }

  Future<http.Response> _requestWithRetry(
    Future<http.Response> Function(Map<String, String> headers) requestFn,
  ) async {
    var headers = await _getHeaders();
    var response = await requestFn(headers);

    if (response.statusCode == 401) {
      developer.log('OnlineApiService: 401 received, refreshing token and retrying...');
      await OnlineSyncService.ensureValidJwt(forceRefresh: true);
      headers = await _getHeaders();
      response = await requestFn(headers);
    }

    return response;
  }

  // ══════════════════════════════════════════════════════════════
  // PRODUCTS
  // ══════════════════════════════════════════════════════════════

  Future<List<Product>> getProducts({String? search, String? type, bool? active}) async {
    try {
      final base = await _getBaseUrl();
      final queryParams = <String, String>{};
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      if (type != null && type.isNotEmpty) queryParams['type'] = type;
      if (active != null) queryParams['active'] = active.toString();

      final uri = Uri.parse('$base/api/products').replace(queryParameters: queryParams.isEmpty ? null : queryParams);
      final res = await _requestWithRetry((h) => _client.get(uri, headers: h));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final data = decoded['data'] as List?;
        if (data == null) return [];
        return data
            .whereType<Map>()
            .map((m) => Product.fromMap(Map<String, dynamic>.from(m)))
            .toList();
      }
      developer.log('OnlineApiService.getProducts failed: ${res.statusCode} ${res.body}');
      return [];
    } catch (e, st) {
      developer.log('OnlineApiService.getProducts error: $e', stackTrace: st);
      return [];
    }
  }

  Future<List<Product>> getProductsForSale() async {
    final all = await getProducts();
    return all.where((p) => p.isActive).toList();
  }

  Future<void> insertProduct(Product p) async {
    try {
      final base = await _getBaseUrl();
      final uri = Uri.parse('$base/api/products');
      final body = jsonEncode(p.toMap());
      final res = await _requestWithRetry((h) => _client.post(uri, headers: h, body: body));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Server error (${res.statusCode}): ${res.body}');
      }
    } catch (e, st) {
      developer.log('OnlineApiService.insertProduct error: $e', stackTrace: st);
      rethrow;
    }
  }

  Future<void> updateProduct(Product p) async {
    try {
      final base = await _getBaseUrl();
      final uri = Uri.parse('$base/api/products/${p.id}');
      final body = jsonEncode(p.toMap());
      final res = await _requestWithRetry((h) => _client.put(uri, headers: h, body: body));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Server error (${res.statusCode}): ${res.body}');
      }
    } catch (e, st) {
      developer.log('OnlineApiService.updateProduct error: $e', stackTrace: st);
      rethrow;
    }
  }

  Future<void> updateProductUnit({required String productId, required String unit}) async {
    try {
      final base = await _getBaseUrl();
      final uri = Uri.parse('$base/api/products/$productId');
      final body = jsonEncode({'unit': unit});
      final res = await _requestWithRetry((h) => _client.put(uri, headers: h, body: body));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Server error (${res.statusCode}): ${res.body}');
      }
    } catch (e, st) {
      developer.log('OnlineApiService.updateProductUnit error: $e', stackTrace: st);
      rethrow;
    }
  }

  Future<void> deleteProduct(String productId) async {
    try {
      final base = await _getBaseUrl();
      final uri = Uri.parse('$base/api/products/$productId');
      final res = await _requestWithRetry((h) => _client.delete(uri, headers: h));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Server error (${res.statusCode}): ${res.body}');
      }
    } catch (e, st) {
      developer.log('OnlineApiService.deleteProduct error: $e', stackTrace: st);
      rethrow;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // CUSTOMERS
  // ══════════════════════════════════════════════════════════════

  Future<List<Customer>> getCustomers({String? search, bool? supplier}) async {
    try {
      final base = await _getBaseUrl();
      final queryParams = <String, String>{};
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      if (supplier != null) queryParams['supplier'] = supplier.toString();

      final uri = Uri.parse('$base/api/customers').replace(queryParameters: queryParams.isEmpty ? null : queryParams);
      final res = await _requestWithRetry((h) => _client.get(uri, headers: h));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final data = decoded['data'] as List?;
        if (data == null) return [];
        return data
            .whereType<Map>()
            .map((m) => Customer.fromMap(Map<String, dynamic>.from(m)))
            .toList();
      }
      developer.log('OnlineApiService.getCustomers failed: ${res.statusCode} ${res.body}');
      return [];
    } catch (e, st) {
      developer.log('OnlineApiService.getCustomers error: $e', stackTrace: st);
      return [];
    }
  }

  Future<void> insertCustomer(Customer c) async {
    try {
      final base = await _getBaseUrl();
      final uri = Uri.parse('$base/api/customers');
      final body = jsonEncode({
        'id': c.id,
        'name': c.name,
        'phone': c.phone,
        'note': c.note,
        'isSupplier': c.isSupplier,
      });
      final res = await _requestWithRetry((h) => _client.post(uri, headers: h, body: body));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Server error (${res.statusCode}): ${res.body}');
      }
    } catch (e, st) {
      developer.log('OnlineApiService.insertCustomer error: $e', stackTrace: st);
      rethrow;
    }
  }

  Future<void> updateCustomer(Customer c) async {
    try {
      final base = await _getBaseUrl();
      final uri = Uri.parse('$base/api/customers/${c.id}');
      final body = jsonEncode({
        'name': c.name,
        'phone': c.phone,
        'note': c.note,
        'isSupplier': c.isSupplier,
      });
      final res = await _requestWithRetry((h) => _client.put(uri, headers: h, body: body));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Server error (${res.statusCode}): ${res.body}');
      }
    } catch (e, st) {
      developer.log('OnlineApiService.updateCustomer error: $e', stackTrace: st);
      rethrow;
    }
  }

  Future<void> deleteCustomer(String customerId) async {
    try {
      final base = await _getBaseUrl();
      final uri = Uri.parse('$base/api/customers/$customerId');
      final res = await _requestWithRetry((h) => _client.delete(uri, headers: h));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Server error (${res.statusCode}): ${res.body}');
      }
    } catch (e, st) {
      developer.log('OnlineApiService.deleteCustomer error: $e', stackTrace: st);
      rethrow;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // SALES
  // ══════════════════════════════════════════════════════════════

  Future<List<Sale>> getSales({
    DateTime? startDate,
    DateTime? endDate,
    String? search,
    int? limit,
    bool fetchAll = false,
  }) async {
    try {
      final base = await _getBaseUrl();
      final queryParams = <String, String>{};

      if (fetchAll) {
        queryParams['limit'] = 'all';
      } else if (limit != null) {
        queryParams['limit'] = limit.toString();
      } else if (startDate == null && endDate == null) {
        // Mặc định giới hạn an toàn 500 nếu không chỉ định ngày, tránh làm đơ ứng dụng
        queryParams['limit'] = '500';
      }

      if (startDate != null) queryParams['startDate'] = startDate.toIso8601String();
      if (endDate != null) queryParams['endDate'] = endDate.toIso8601String();
      if (search != null && search.isNotEmpty) queryParams['search'] = search;

      final uri = Uri.parse('$base/api/sales').replace(queryParameters: queryParams.isEmpty ? null : queryParams);
      final res = await _requestWithRetry((h) => _client.get(uri, headers: h));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final data = decoded['data'] as List?;
        if (data == null) return [];
        return data
            .whereType<Map>()
            .map((m) => Sale.fromMap(Map<String, dynamic>.from(m)))
            .toList();
      }
      developer.log('OnlineApiService.getSales failed: ${res.statusCode} ${res.body}');
      return [];
    } catch (e, st) {
      developer.log('OnlineApiService.getSales error: $e', stackTrace: st);
      return [];
    }
  }

  Future<Sale?> getSaleById(String saleId) async {
    try {
      final base = await _getBaseUrl();
      final uri = Uri.parse('$base/api/sales/$saleId');
      final res = await _requestWithRetry((h) => _client.get(uri, headers: h));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final data = decoded['data'] as Map?;
        if (data == null) return null;
        return Sale.fromMap(Map<String, dynamic>.from(data));
      }
      return null;
    } catch (e, st) {
      developer.log('OnlineApiService.getSaleById error: $e', stackTrace: st);
      return null;
    }
  }

  Future<void> insertSale(Sale s) async {
    try {
      final base = await _getBaseUrl();
      final uri = Uri.parse('$base/api/sales');
      final body = jsonEncode({
        'id': s.id,
        'createdAt': s.createdAt.toIso8601String(),
        'customerId': s.customerId,
        'customerName': s.customerName,
        'employeeId': s.employeeId,
        'employeeName': s.employeeName,
        'items': s.items.map((it) => it.toMap()).toList(),
        'discount': s.discount,
        'paidAmount': s.paidAmount,
        'paymentType': s.paymentType,
        'note': s.note,
      });
      final res = await _requestWithRetry((h) => _client.post(uri, headers: h, body: body));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Server error (${res.statusCode}): ${res.body}');
      }
    } catch (e, st) {
      developer.log('OnlineApiService.insertSale error: $e', stackTrace: st);
      rethrow;
    }
  }

  Future<void> updateSale(Sale s) async {
    try {
      final base = await _getBaseUrl();
      final uri = Uri.parse('$base/api/sales/${s.id}');
      final body = jsonEncode({
        'customerId': s.customerId,
        'customerName': s.customerName,
        'employeeId': s.employeeId,
        'employeeName': s.employeeName,
        'items': s.items.map((it) => it.toMap()).toList(),
        'discount': s.discount,
        'paidAmount': s.paidAmount,
        'paymentType': s.paymentType,
        'note': s.note,
        'createdAt': s.createdAt.toIso8601String(),
      });
      final res = await _requestWithRetry((h) => _client.put(uri, headers: h, body: body));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Server error (${res.statusCode}): ${res.body}');
      }
    } catch (e, st) {
      developer.log('OnlineApiService.updateSale error: $e', stackTrace: st);
      rethrow;
    }
  }

  Future<void> updateSalePaymentType({required String saleId, String? paymentType}) async {
    try {
      final base = await _getBaseUrl();
      final uri = Uri.parse('$base/api/sales/$saleId');
      final body = jsonEncode({'paymentType': paymentType});
      final res = await _requestWithRetry((h) => _client.put(uri, headers: h, body: body));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Server error (${res.statusCode}): ${res.body}');
      }
    } catch (e, st) {
      developer.log('OnlineApiService.updateSalePaymentType error: $e', stackTrace: st);
      rethrow;
    }
  }

  Future<void> deleteSale(String saleId) async {
    try {
      final base = await _getBaseUrl();
      final uri = Uri.parse('$base/api/sales/$saleId');
      final res = await _requestWithRetry((h) => _client.delete(uri, headers: h));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Server error (${res.statusCode}): ${res.body}');
      }
    } catch (e, st) {
      developer.log('OnlineApiService.deleteSale error: $e', stackTrace: st);
      rethrow;
    }
  }

  // ══════════════════════════════════════════════════════════════
  // DEBTS & DEBT PAYMENTS
  // ══════════════════════════════════════════════════════════════

  Future<List<Debt>> getDebts({
    int? type,
    bool? settled,
    String? search,
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    try {
      final base = await _getBaseUrl();
      final queryParams = <String, String>{};
      if (type != null) queryParams['type'] = type.toString();
      if (settled != null) queryParams['settled'] = settled.toString();
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      if (startDate != null) queryParams['startDate'] = startDate.toIso8601String();
      if (endDate != null) queryParams['endDate'] = endDate.toIso8601String();
      if (limit != null) queryParams['limit'] = limit.toString();

      final uri = Uri.parse('$base/api/debts').replace(queryParameters: queryParams.isEmpty ? null : queryParams);
      final res = await _requestWithRetry((h) => _client.get(uri, headers: h));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final data = decoded['data'] as List?;
        if (data == null) return [];
        return data
            .whereType<Map>()
            .map((m) => Debt.fromMap(Map<String, dynamic>.from(m)))
            .toList();
      }
      developer.log('OnlineApiService.getDebts failed: ${res.statusCode} ${res.body}');
      return [];
    } catch (e, st) {
      developer.log('OnlineApiService.getDebts error: $e', stackTrace: st);
      return [];
    }
  }

  Future<Map<String, int>> getEntityCounts() async {
    try {
      final base = await _getBaseUrl();
      final uri = Uri.parse('$base/api/sync/counts');
      final res = await _requestWithRetry((h) => _client.get(uri, headers: h));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final data = decoded['data'] as Map?;
        if (data == null) return {};
        return {
          'products': (data['products'] as num?)?.toInt() ?? 0,
          'customers': (data['customers'] as num?)?.toInt() ?? 0,
          'sales': (data['sales'] as num?)?.toInt() ?? 0,
          'debts': (data['debts'] as num?)?.toInt() ?? 0,
          'expenses': (data['expenses'] as num?)?.toInt() ?? 0,
        };
      }
      return {};
    } catch (e, st) {
      developer.log('OnlineApiService.getEntityCounts error: $e', stackTrace: st);
      return {};
    }
  }

  Future<Debt?> getDebtById(String debtId) async {
    try {
      final base = await _getBaseUrl();
      final uri = Uri.parse('$base/api/debts/$debtId');
      final res = await _requestWithRetry((h) => _client.get(uri, headers: h));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final data = decoded['data'] as Map?;
        if (data == null) return null;
        return Debt.fromMap(Map<String, dynamic>.from(data));
      }
      return null;
    } catch (e, st) {
      developer.log('OnlineApiService.getDebtById error: $e', stackTrace: st);
      return null;
    }
  }

  Future<Debt?> getDebtBySource({required String sourceType, required String sourceId}) async {
    try {
      final base = await _getBaseUrl();
      final uri = Uri.parse('$base/api/debts').replace(queryParameters: {
        'sourceType': sourceType,
        'sourceId': sourceId,
      });
      final res = await _requestWithRetry((h) => _client.get(uri, headers: h));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final data = decoded['data'] as List?;
        if (data == null || data.isEmpty) return null;
        return Debt.fromMap(Map<String, dynamic>.from(data.first));
      }
      return null;
    } catch (e, st) {
      developer.log('OnlineApiService.getDebtBySource error: $e', stackTrace: st);
      return null;
    }
  }

  Future<void> insertDebt(Debt d) async {
    try {
      final base = await _getBaseUrl();
      final uri = Uri.parse('$base/api/debts');
      final body = jsonEncode(d.toMap());
      final res = await _requestWithRetry((h) => _client.post(uri, headers: h, body: body));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Server error (${res.statusCode}): ${res.body}');
      }
    } catch (e, st) {
      developer.log('OnlineApiService.insertDebt error: $e', stackTrace: st);
      rethrow;
    }
  }

  Future<void> updateDebt(Debt d) async {
    try {
      final base = await _getBaseUrl();
      final uri = Uri.parse('$base/api/debts/${d.id}');
      final body = jsonEncode(d.toMap());
      final res = await _requestWithRetry((h) => _client.put(uri, headers: h, body: body));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Server error (${res.statusCode}): ${res.body}');
      }
    } catch (e, st) {
      developer.log('OnlineApiService.updateDebt error: $e', stackTrace: st);
      rethrow;
    }
  }

  Future<void> deleteDebt(String debtId) async {
    try {
      final base = await _getBaseUrl();
      final uri = Uri.parse('$base/api/debts/$debtId');
      final res = await _requestWithRetry((h) => _client.delete(uri, headers: h));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Server error (${res.statusCode}): ${res.body}');
      }
    } catch (e, st) {
      developer.log('OnlineApiService.deleteDebt error: $e', stackTrace: st);
      rethrow;
    }
  }

  Future<void> insertDebtPayment({
    required String debtId,
    required double amount,
    String? note,
    DateTime? createdAt,
    String? paymentType,
  }) async {
    try {
      final base = await _getBaseUrl();
      final uri = Uri.parse('$base/api/debts/$debtId/payments');
      final body = jsonEncode({
        'amount': amount,
        'note': note,
        'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
        'paymentType': paymentType,
      });
      final res = await _requestWithRetry((h) => _client.post(uri, headers: h, body: body));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Server error (${res.statusCode}): ${res.body}');
      }
    } catch (e, st) {
      developer.log('OnlineApiService.insertDebtPayment error: $e', stackTrace: st);
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getDebtPayments(String debtId) async {
    try {
      final base = await _getBaseUrl();
      final uri = Uri.parse('$base/api/debts/$debtId');
      final res = await _requestWithRetry((h) => _client.get(uri, headers: h));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final debt = decoded['data'] as Map?;
        if (debt == null) return [];
        final payments = debt['payments'] as List?;
        if (payments == null) return [];
        return payments.whereType<Map>().map((p) {
          final m = Map<String, dynamic>.from(p);
          final rawAmount = m['amount'];
          final double amountVal = (rawAmount is num)
              ? rawAmount.toDouble()
              : double.tryParse(rawAmount?.toString() ?? '0') ?? 0.0;
          return {
            'id': m['id'] ?? 0,
            'uuid': m['uuid']?.toString() ?? '',
            'debtId': m['debtId']?.toString() ?? debtId,
            'amount': amountVal,
            'note': m['note']?.toString(),
            'paymentType': m['paymentType']?.toString(),
            'createdAt': m['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
            'updatedAt': m['updatedAt']?.toString() ?? DateTime.now().toIso8601String(),
          };
        }).toList();
      }
      return [];
    } catch (e, st) {
      developer.log('OnlineApiService.getDebtPayments error: $e', stackTrace: st);
      return [];
    }
  }

  // ══════════════════════════════════════════════════════════════
  // EXPENSES
  // ══════════════════════════════════════════════════════════════

  Future<List<Map<String, dynamic>>> getExpenses({
    DateTimeRange? range,
    String? category,
    String? query,
  }) async {
    try {
      final base = await _getBaseUrl();
      final queryParams = <String, String>{};
      if (range != null) {
        queryParams['startDate'] = range.start.toIso8601String();
        queryParams['endDate'] = range.end.toIso8601String();
      }
      if (category != null && category.isNotEmpty && category != 'all') {
        queryParams['category'] = category;
      }
      if (query != null && query.isNotEmpty) {
        queryParams['search'] = query;
      }

      final uri = Uri.parse('$base/api/expenses').replace(queryParameters: queryParams.isEmpty ? null : queryParams);
      final res = await _requestWithRetry((h) => _client.get(uri, headers: h));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final data = decoded['data'] as List?;
        if (data == null) return [];
        return data.whereType<Map>().map((e) {
          final m = Map<String, dynamic>.from(e);
          final rawAmount = m['amount'];
          final double amountVal = (rawAmount is num)
              ? rawAmount.toDouble()
              : double.tryParse(rawAmount?.toString() ?? '0') ?? 0.0;
          return {
            'id': m['id']?.toString() ?? '',
            'occurredAt': m['occurredAt']?.toString() ?? DateTime.now().toIso8601String(),
            'amount': amountVal,
            'category': m['category']?.toString() ?? '',
            'note': m['note']?.toString(),
            'expenseDocUploaded': m['expenseDocUploaded'] == true ? 1 : 0,
            'expenseDocFileId': m['expenseDocFileId']?.toString(),
            'expenseDocUpdatedAt': m['expenseDocUpdatedAt']?.toString(),
          };
        }).toList();
      }
      return [];
    } catch (e, st) {
      developer.log('OnlineApiService.getExpenses error: $e', stackTrace: st);
      return [];
    }
  }

  Future<String> insertExpense({
    required DateTime occurredAt,
    required double amount,
    required String category,
    String? note,
  }) async {
    try {
      final base = await _getBaseUrl();
      final uri = Uri.parse('$base/api/expenses');
      final body = jsonEncode({
        'occurredAt': occurredAt.toIso8601String(),
        'amount': amount,
        'category': category,
        'note': note,
      });
      final res = await _requestWithRetry((h) => _client.post(uri, headers: h, body: body));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        return decoded['data']?['id']?.toString() ?? '';
      }
      throw Exception('Server error (${res.statusCode}): ${res.body}');
    } catch (e, st) {
      developer.log('OnlineApiService.insertExpense error: $e', stackTrace: st);
      rethrow;
    }
  }

  Future<void> updateExpense({
    required String id,
    required DateTime occurredAt,
    required double amount,
    required String category,
    String? note,
  }) async {
    try {
      final base = await _getBaseUrl();
      final uri = Uri.parse('$base/api/expenses/$id');
      final body = jsonEncode({
        'occurredAt': occurredAt.toIso8601String(),
        'amount': amount,
        'category': category,
        'note': note,
      });
      final res = await _requestWithRetry((h) => _client.put(uri, headers: h, body: body));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Server error (${res.statusCode}): ${res.body}');
      }
    } catch (e, st) {
      developer.log('OnlineApiService.updateExpense error: $e', stackTrace: st);
      rethrow;
    }
  }

  Future<void> deleteExpense(String id) async {
    try {
      final base = await _getBaseUrl();
      final uri = Uri.parse('$base/api/expenses/$id');
      final res = await _requestWithRetry((h) => _client.delete(uri, headers: h));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception('Server error (${res.statusCode}): ${res.body}');
      }
    } catch (e, st) {
      developer.log('OnlineApiService.deleteExpense error: $e', stackTrace: st);
      rethrow;
    }
  }
}
