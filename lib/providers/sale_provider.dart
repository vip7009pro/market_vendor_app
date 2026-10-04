import 'package:flutter/material.dart';
import '../models/sale.dart';
import '../services/database_service.dart';

class SaleProvider with ChangeNotifier {
  final List<Sale> _sales = [];
  bool _isLoading = false;
  DateTimeRange? _dateRange = defaultRange();

  // Undo caches
  Sale? _lastDeletedSale;
  List<Sale> _lastDeletedAllSales = const [];

  List<Sale> get sales => List.unmodifiable(_sales);
  bool get isLoading => _isLoading;
  DateTimeRange? get dateRange => _dateRange;
  bool get isAllTime => _dateRange == null;

  /// Khoảng thời gian mặc định: 30 ngày gần nhất
  static DateTimeRange defaultRange() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30));
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    return DateTimeRange(start: start, end: end);
  }

  /// Tải dữ liệu theo khoảng thời gian đã chọn (mặc định 30 ngày gần nhất)
  Future<void> load({DateTimeRange? range, bool forceAll = false}) async {
    _isLoading = true;
    notifyListeners();
    try {
      if (forceAll) {
        _dateRange = null;
      } else if (range != null) {
        _dateRange = range;
      } else if (_dateRange == null) {
        _dateRange = defaultRange();
      }

      final data = await DatabaseService.instance.getSales(
        startDate: _dateRange?.start,
        endDate: _dateRange?.end,
        fetchAll: _dateRange == null,
      );
      _sales
        ..clear()
        ..addAll(data);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Đổi khoảng ngày truy vấn và tự động tải lại
  Future<void> setDateRange(DateTimeRange? newRange) async {
    await load(range: newRange, forceAll: newRange == null);
  }

  Future<void> add(Sale s) async {
    // Chỉ thêm vào danh sách đang hiển thị nếu đơn này nằm trong khoảng ngày lọc
    if (_dateRange == null ||
        (!s.createdAt.isBefore(_dateRange!.start) && !s.createdAt.isAfter(_dateRange!.end))) {
      _sales.insert(0, s);
    }
    notifyListeners();
    await DatabaseService.instance.insertSale(s);
  }

  Future<void> delete(String saleId) async {
    final idx = _sales.indexWhere((s) => s.id == saleId);
    if (idx != -1) {
      _lastDeletedSale = _sales[idx];
      _sales.removeAt(idx);
    }
    notifyListeners();
    await DatabaseService.instance.deleteSale(saleId);
  }

  Future<void> deleteAll() async {
    _lastDeletedAllSales = List<Sale>.from(_sales);
    _sales.clear();
    notifyListeners();
    await DatabaseService.instance.deleteAllSales();
  }

  Future<bool> undoLastDelete() async {
    final s = _lastDeletedSale;
    if (s == null) return false;
    await DatabaseService.instance.insertSale(s);
    _sales.add(s);
    _lastDeletedSale = null;
    notifyListeners();
    return true;
  }

  Future<bool> undoDeleteAll() async {
    if (_lastDeletedAllSales.isEmpty) return false;
    for (final s in _lastDeletedAllSales) {
      await DatabaseService.instance.insertSale(s);
    }
    _sales.addAll(_lastDeletedAllSales);
    _lastDeletedAllSales = const [];
    notifyListeners();
    return true;
  }
}
