import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:market_vendor_app/utils/contact_serializer.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/product_provider.dart';
import '../providers/customer_provider.dart';
import '../providers/sale_provider.dart';
import '../providers/debt_provider.dart';
import '../services/database_service.dart';
import '../providers/theme_provider.dart';
import '../providers/auth_provider.dart'; // Để lấy uid khi cần
import 'debt_screen.dart';
import 'purchase_history_screen.dart';
import 'report_screen.dart';
import 'settings_screen.dart';
import 'sale_screen.dart';
import 'sales_history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  late final List<Widget> _pages;

  Future<void> _refreshAllProviders() async {
    final productProvider = Provider.of<ProductProvider>(context, listen: false);
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
    final saleProvider = Provider.of<SaleProvider>(context, listen: false);
    final debtProvider = Provider.of<DebtProvider>(context, listen: false);
    await Future.wait([
      productProvider.load(),
      customerProvider.load(),
      saleProvider.load(),
      debtProvider.load(),
    ]);
  }

  Future<void> _handleAccountAfterLogin(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final lastUid = prefs.getString('last_uid');
    if (lastUid != null && lastUid.isNotEmpty && lastUid != uid) {
      await DatabaseService.instance.close();
      await DatabaseService.instance.resetLocalDatabase();
      await DatabaseService.instance.reinitialize();
    }
    await prefs.setString('last_uid', uid);
    if (!mounted) return;
    await _refreshAllProviders();
  }

  Future<void> _loadAndCacheContacts() async {
    try {
      final granted = await FlutterContacts.requestPermission();
      if (granted) {
        final contacts = await FlutterContacts.getContacts(withProperties: true, withPhoto: true);
        await ContactSerializer.saveContactsToPrefs(contacts);
        debugPrint('Cached ${contacts.length} contacts');
      }
    } catch (e) {
      debugPrint('Error caching contacts: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _pages = [
      const SaleScreen(),
      const SalesHistoryScreen(),
      const DebtScreen(),
      const PurchaseHistoryScreen(),
      const ReportScreen(),
      const SettingsScreen(),
    ];
    _loadAndCacheContacts();

    // Load theme
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      final savedTheme = prefs.getString('selected_theme') ?? 'light';
      final themeProvider = context.read<ThemeProvider>();
      themeProvider.setTheme(savedTheme);
    });

    // Khi vào HomeScreen nghĩa là đã login → check đổi tài khoản và refresh data
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final uid = auth.firebaseUser?.uid;
    if (uid != null) {
      _handleAccountAfterLogin(uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'Bán hàng'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Lịch sử'),
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Ghi nợ'),
          NavigationDestination(icon: Icon(Icons.inventory), label: 'Nhập hàng'),
          NavigationDestination(icon: Icon(Icons.insights), label: 'Báo cáo'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Cài đặt'),
        ],
      ),
    );
  }
}