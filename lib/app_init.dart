import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/product_provider.dart';
import 'providers/customer_provider.dart';
import 'providers/sale_provider.dart';
import 'providers/debt_provider.dart';

class AppInit extends StatefulWidget {
  final Widget child;
  const AppInit({super.key, required this.child});

  @override
  State<AppInit> createState() => _AppInitState();
}

class _AppInitState extends State<AppInit> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await Future.wait([
        context.read<ProductProvider>().load(),
        context.read<CustomerProvider>().load(),
        context.read<SaleProvider>().load(),
        context.read<DebtProvider>().load(),
      ]);
    } catch (_) {
      // Optionally log error
    } finally {
      if (mounted) setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return widget.child;
  }
}
