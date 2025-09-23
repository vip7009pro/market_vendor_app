import 'package:flutter/foundation.dart';
import '../models/sale.dart';
import '../services/database_service.dart';

class SaleProvider with ChangeNotifier {
  final List<Sale> _sales = [];
  // Undo caches
  Sale? _lastDeletedSale;
  List<Sale> _lastDeletedAllSales = const [];

  List<Sale> get sales => List.unmodifiable(_sales);

  Future<void> load() async {
    final data = await DatabaseService.instance.getSales();
    _sales
      ..clear()
      ..addAll(data);
    notifyListeners();
  }

  Future<void> add(Sale s) async {
    _sales.add(s);
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
