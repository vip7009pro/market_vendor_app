// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:market_vendor_app/main.dart';
import 'package:market_vendor_app/providers/auth_provider.dart';
import 'package:market_vendor_app/providers/purchase_provider.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    final auth = AuthProvider();
    final purchaseProvider = PurchaseProvider();
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => auth,
        child: MyApp(auth: auth, purchaseProvider: purchaseProvider),
      ),
    );

    // Verify that the app starts
    expect(find.byType(Scaffold), findsOneWidget);
  });
}
