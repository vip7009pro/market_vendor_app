import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'sale_screen.dart';
import 'debt_screen.dart';
import 'report_screen.dart';
import 'settings_screen.dart';
import '../providers/auth_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  final _pages = const [
    SaleScreen(),
    DebtScreen(),
    ReportScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    
    // If user is not signed in, show sign in button
    if (auth.firebaseUser == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Vui lòng đăng nhập để tiếp tục',
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.login),
                label: const Text('Đăng nhập bằng Google'),
                onPressed: () => _handleSignIn(context, auth),
              ),
            ],
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
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Ghi nợ'),
          NavigationDestination(icon: Icon(Icons.insights), label: 'Báo cáo'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Cài đặt'),
        ],
      ),
    );
  }
  
  Future<void> _handleSignIn(BuildContext context, AuthProvider auth) async {
    try {
      await auth.signIn();
      // After successful sign in, the UI will update automatically
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đăng nhập thất bại: ${e.toString()}')),
      );
    }
  }
}
