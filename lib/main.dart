// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';

import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/product_provider.dart';
import 'providers/customer_provider.dart';
import 'providers/sale_provider.dart';
import 'providers/debt_provider.dart';
import 'providers/purchase_provider.dart';

import 'services/database_service.dart';
import 'services/sync_service.dart';
import 'services/debt_reminder_service.dart';

import 'screens/product_list_screen.dart';
import 'screens/customer_list_screen.dart';
import 'screens/sales_history_screen.dart';
import 'screens/debt_history_screen.dart';
import 'screens/login_screen.dart';       // Đại ca tự tạo nếu chưa có
import 'screens/home_screen.dart';         // Màn hình chính sau khi login

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Khởi tạo Firebase
  await Firebase.initializeApp();

  // Khởi tạo local database
  await DatabaseService.instance.init();

  await DebtReminderService.instance.init();

  // Khởi tạo SyncService sớm để dùng navigatorKey
  SyncService(navigatorKey: navigatorKey);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()), // Firebase Auth + Google Sign In
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => CustomerProvider()),
        ChangeNotifierProvider(create: (_) => SaleProvider()),
        ChangeNotifierProvider(create: (_) => DebtProvider()),
        ChangeNotifierProvider(
          create: (_) => PurchaseProvider()..initialize(), // init async ngay khi tạo
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Quản lý bán hàng',
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            theme: themeProvider.currentTheme,
            locale: const Locale('vi'),
            supportedLocales: const [Locale('vi'), Locale('en')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: const AuthGate(), // Widget quyết định màn hình đầu
            routes: {
              '/products': (_) => const ProductListScreen(),
              '/customers': (_) => const CustomerListScreen(),
              '/sales_history': (_) => const SalesHistoryScreen(),
              '/debts_history': (_) => const DebtHistoryScreen(),
            },
          );
        },
      ),
    );
  }
}

// Widget trung gian kiểm tra trạng thái đăng nhập
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, child) {
        // Đang loading (Firebase đang check auth state hoặc silent login)
        if (auth.isLoading) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_cart, size: 100, color: Colors.blue),
                  SizedBox(height: 20),
                  Text('App Bán Hàng Ghi Nợ', style: TextStyle(fontSize: 24)),
                  SizedBox(height: 20),
                  CircularProgressIndicator(),
                ],
              ),
            ),
          );
        }

        // Đã đăng nhập → vào Home
        if (auth.isSignedIn) {
          return const HomeScreen();
        }

        // Chưa đăng nhập → vào Login
        return const LoginScreen();
      },
    );
  }
}