import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'providers/product_provider.dart';
import 'providers/customer_provider.dart';
import 'providers/sale_provider.dart';
import 'providers/debt_provider.dart';
import 'services/database_service.dart';
import 'app_init.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/purchase_provider.dart';
import 'screens/product_list_screen.dart';
import 'screens/customer_list_screen.dart';
import 'screens/sales_history_screen.dart';
import 'screens/debt_history_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/sync_service.dart';

// Tạo GlobalKey cho Navigator
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await DatabaseService.instance.init();
  
  // Initialize auth state
  final auth = AuthProvider();
  await auth.initialize();
  
  // Initialize purchase provider
  final purchaseProvider = PurchaseProvider();
  await purchaseProvider.initialize();
  
  // Initialize SyncService with navigatorKey
  SyncService(navigatorKey: navigatorKey);
  
  runApp(MyApp(auth: auth, purchaseProvider: purchaseProvider));
}

class MyApp extends StatelessWidget {
  final AuthProvider auth;
  final PurchaseProvider purchaseProvider;
  
  const MyApp({super.key, required this.auth, required this.purchaseProvider});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => CustomerProvider()),
        ChangeNotifierProvider(create: (_) => SaleProvider()),
        ChangeNotifierProvider(create: (_) => DebtProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: purchaseProvider),
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
            builder: (context, child) {
              final auth = Provider.of<AuthProvider>(context, listen: false);
              print('Auth state - FirebaseUser: ${auth.firebaseUser}');
              
              if (auth.firebaseUser == null) {
                print('No user found, showing sign in screen');
                return const HomeScreen();
              }
              
              print('User found, showing app content');
              return AppInit(child: child!);
            },
            home: const HomeScreen(),
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
 
