import 'package:flutter_test/flutter_test.dart';
import 'package:market_vendor_app/models/sale.dart';

void main() {
  test('Sale totals, discount and debt calculations', () {
    final items = [
      SaleItem(productId: 'p1', name: 'Táo', unitPrice: 10000, unitCost: 8000, quantity: 2, unit: 'kg'), // 20k
      SaleItem(productId: 'p2', name: 'Chuối', unitPrice: 5000, unitCost: 3000, quantity: 3, unit: 'nải'), // 15k
    ];
    final sale = Sale(items: items, discount: 3000, paidAmount: 10000);

    expect(sale.subtotal, 35000);
    expect(sale.total, 32000);
    expect(sale.debt, 22000);
  });
}
