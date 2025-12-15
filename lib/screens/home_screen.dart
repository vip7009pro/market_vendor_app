import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:market_vendor_app/providers/auth_provider.dart';
import 'package:market_vendor_app/screens/sales_history_screen.dart';
import 'package:market_vendor_app/utils/contact_serializer.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/product_provider.dart';
import '../providers/customer_provider.dart';
import '../providers/sale_provider.dart';
import '../providers/debt_provider.dart';
import '../services/database_service.dart';
import '../providers/theme_provider.dart'; // Import theme_provider
import 'debt_screen.dart';
import 'purchase_history_screen.dart';
import 'report_screen.dart';
import 'settings_screen.dart';
import 'sale_screen.dart';

class FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const FeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 28,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

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
    if (!mounted) return;
    setState(() => _index = 0);
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
    // Load saved theme từ SharedPreferences sau build đầu tiên
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      final savedTheme = prefs.getString('selected_theme') ?? 'light';
      final themeProvider = context.read<ThemeProvider>();
      themeProvider.setTheme(savedTheme);
      debugPrint('Loaded saved theme: $savedTheme'); // Debug log để check
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    
    // If user is not signed in, show sign in screen
    if (auth.firebaseUser == null) {
      return Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 5),
                // App Logo
                Hero(
                  tag: 'app-logo',
                  child: Container(
                    width: 120,
                    height: 120,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.storefront_rounded,
                      size: 60,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                
                // App Name
                Text(
                  'Bán Hàng Ghi Nợ',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 5),
                
                // Tagline
                Text(
                  'Quản lý bán hàng và công nợ dễ dàng',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 10),
                
                // Features Grid
                const Text(
                  'Tính năng chính',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                
                const SizedBox(height: 8),
                
                // Features Grid
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.1,
                  children: const [
                    FeatureCard(
                      icon: Icons.point_of_sale,
                      title: 'Bán Hàng',
                      description: 'Nhanh chóng, dễ dàng',
                    ),
                    FeatureCard(
                      icon: Icons.receipt_long,
                      title: 'Ghi Nợ',
                      description: 'Theo dõi công nợ',
                    ),
                    FeatureCard(
                      icon: Icons.people,
                      title: 'Khách Hàng',
                      description: 'Quản lý thông tin',
                    ),
                    FeatureCard(
                      icon: Icons.analytics,
                      title: 'Báo Cáo',
                      description: 'Thống kê doanh thu',
                    ),
                  ],
                ),
                
                const SizedBox(height: 40),
                
                // Sign In Button
                FilledButton.icon(
                  onPressed: () => _handleSignIn(context, auth),
                  icon: const Icon(Icons.login, size: 24),
                  label: const Text('Đăng nhập bằng Google'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Terms and Privacy
                Text(
                  'Bằng việc tiếp tục, bạn đồng ý với Điều khoản dịch vụ và Chính sách bảo mật của chúng tôi',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      );
    }
    
    // User is signed in, show the app
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: NavigationBar(
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
  
  Future<void> _handleSignIn(BuildContext context, AuthProvider auth) async {
    try {
      await auth.signIn();
      final uid = auth.firebaseUser?.uid;
      if (uid != null && uid.isNotEmpty && context.mounted) {
        await _handleAccountAfterLogin(uid);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đăng nhập thất bại: ${e.toString()}')),
      );
    }
  }
}