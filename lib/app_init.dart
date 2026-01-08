import 'package:flutter/material.dart';
import 'package:market_vendor_app/providers/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/product_provider.dart';
import 'providers/customer_provider.dart';
import 'providers/sale_provider.dart';
import 'providers/debt_provider.dart';
import 'providers/auth_provider.dart';
import 'services/online_sync_service.dart';

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

  @override
  void dispose() {
    OnlineSyncService.stopAutoSync();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTheme = prefs.getString('selected_theme') ?? 'light';
      await Future.wait([
        context.read<ProductProvider>().load(),
        context.read<CustomerProvider>().load(),
        context.read<SaleProvider>().load(),
        context.read<DebtProvider>().load(),
        context.read<ThemeProvider>().setTheme(savedTheme),
      ]);

      final auth = context.read<AuthProvider>();
      if (auth.isSignedIn) {
        try {
          await OnlineSyncService.syncNow(auth: auth);
        } catch (_) {
          // ignore
        }

        try {
          await OnlineSyncService.startAutoSync(auth: auth);
        } catch (_) {
          // ignore
        }
      }
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
