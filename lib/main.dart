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
import 'screens/product_list_screen.dart';
import 'screens/customer_list_screen.dart';
import 'screens/sales_history_screen.dart';
import 'screens/debt_history_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'services/sync_service.dart';
import 'theme/momo_theme.dart';

// Tạo GlobalKey cho Navigator
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await DatabaseService.instance.init();
  
  // Initialize auth state
  final auth = AuthProvider();
  await auth.initialize();
  
  // Initialize SyncService with navigatorKey
  SyncService(navigatorKey: navigatorKey);
  
  runApp(MyApp(auth: auth));
}

class MyApp extends StatelessWidget {
  final AuthProvider auth;
  
  const MyApp({super.key, required this.auth});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => CustomerProvider()),
        ChangeNotifierProvider(create: (_) => SaleProvider()),
        ChangeNotifierProvider(create: (_) => DebtProvider()),
        ChangeNotifierProvider.value(value: auth),
      ],
      child: MaterialApp(
        title: 'Quản lý bán hàng',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        builder: (context, child) {
          final auth = Provider.of<AuthProvider>(context);
          print('Auth state - FirebaseUser: ${auth.firebaseUser}');
          
          // Show loading screen only during initial auth check
          if (auth.firebaseUser == null) {
            print('No user found, showing sign in screen');
            // Return the HomeScreen which should show the sign-in button
            return const HomeScreen();
          }
          
          print('User found, showing app content');
          return AppInit(child: child!);
        },
        theme: MomoTheme.light(),
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: const HomeScreen(),
        routes: {
          '/products': (_) => const ProductListScreen(),
          '/customers': (_) => const CustomerListScreen(),
          '/sales_history': (_) => const SalesHistoryScreen(),
          '/debts_history': (_) => const DebtHistoryScreen(),
        },
      ),
    );
  }
}
 
