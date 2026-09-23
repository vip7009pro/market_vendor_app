import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
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
import '../services/drive_backup_scheduler.dart';
import '../services/debt_reminder_service.dart';
import '../services/online_sync_service.dart';
import 'debt_screen.dart';
import 'product_list_screen.dart';
import 'report_screen.dart';
import 'settings_screen.dart';
import 'sale_screen.dart';
import 'sales_history_screen.dart';
import 'expense_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  late final List<Widget> _pages;
  bool _checkedAccount = false;

  bool _isRefreshingData = false;

  Future<void> _refreshAllProviders() async {
    if (_isRefreshingData) return;
    if (mounted) setState(() => _isRefreshingData = true);
    final productProvider = Provider.of<ProductProvider>(context, listen: false);
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
    final saleProvider = Provider.of<SaleProvider>(context, listen: false);
    final debtProvider = Provider.of<DebtProvider>(context, listen: false);
    try {
      await Future.wait([
        productProvider.load(),
        customerProvider.load(),
        saleProvider.load(),
        debtProvider.load(),
      ]);
    } finally {
      if (mounted) setState(() => _isRefreshingData = false);
    }
  }

  Future<void> _handleAccountAfterLogin(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final lastUid = prefs.getString('last_uid');

    if (!_checkedAccount) {
      _checkedAccount = true;
      if (lastUid != null && lastUid.isNotEmpty && lastUid != uid) {
        final hasData = await DatabaseService.instance.hasAnyData();
        if (hasData && mounted) {
          final shouldClear = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Dữ liệu cũ trên máy'),
              content: const Text(
                'Phát hiện dữ liệu đã có sẵn trong máy từ tài khoản trước. Bạn có muốn xóa dữ liệu hiện tại để dùng dữ liệu trống không?',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Giữ lại')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa dữ liệu')),
              ],
            ),
          );

          if (shouldClear == true) {
            await DatabaseService.instance.close();
            await DatabaseService.instance.resetLocalDatabase();
            await DatabaseService.instance.reinitialize();
          }
        }
      }
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
      const ProductListScreen(),
      const ExpenseScreen(),
      const ReportScreen(),
      const SettingsScreen(),
    ];
    _loadAndCacheContacts();

    // Load theme
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final prefs = await SharedPreferences.getInstance();
      final savedTheme = prefs.getString('app_theme') ?? 'light';
      if (!mounted) return;
      final themeProvider = context.read<ThemeProvider>();
      await themeProvider.setTheme(savedTheme);
    });

    // Khi vào HomeScreen nghĩa là đã login → check đổi tài khoản và refresh data
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final uid = auth.firebaseUser?.uid;
    if (uid != null) {
      _handleAccountAfterLogin(uid);
    }

    // Auto backup Google Drive (trưa/tối/đêm) + cleanup > 30 ngày
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      DriveBackupScheduler().start(context);
    });

    // Nhắc nợ: quá hạn hoặc quá 7 ngày nếu chưa set dueDate (mỗi ngày 1 lần)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DebtReminderService.instance.checkAndNotify();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isProdLoading = context.watch<ProductProvider>().isLoading;
    final isCustLoading = context.watch<CustomerProvider>().isLoading;
    final isSaleLoading = context.watch<SaleProvider>().isLoading;
    final isDebtLoading = context.watch<DebtProvider>().isLoading;

    return ValueListenableBuilder<bool>(
      valueListenable: OnlineSyncService.isSyncingNotifier,
      builder: (context, isSyncing, _) {
        final isBusy = _isRefreshingData ||
            isProdLoading ||
            isCustLoading ||
            isSaleLoading ||
            isDebtLoading ||
            isSyncing;

        return Scaffold(
          body: Stack(
            children: [
              _pages[_index],
              if (isBusy)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: IgnorePointer(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LinearProgressIndicator(
                            minHeight: 3.5,
                            backgroundColor: Colors.transparent,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ValueListenableBuilder<String?>(
                            valueListenable: OnlineSyncService.syncStatusNotifier,
                            builder: (context, syncText, _) {
                              final text = syncText ??
                                  (_isRefreshingData
                                      ? 'Đang nạp dữ liệu vào máy...'
                                      : 'Đang tải dữ liệu...');
                              return Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surface
                                        .withValues(alpha: 0.94),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.12),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                    border: Border.all(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary
                                          .withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 13,
                                        height: 13,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                            Theme.of(context).colorScheme.primary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        text,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'Bán hàng'),
              NavigationDestination(icon: Icon(Icons.history), label: 'Lịch sử'),
              NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Ghi nợ'),
              NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Kho'),
              NavigationDestination(icon: Icon(Icons.payments_outlined), label: 'Chi phí'),
              NavigationDestination(icon: Icon(Icons.insights), label: 'Báo cáo'),
              NavigationDestination(icon: Icon(Icons.settings), label: 'Cài đặt'),
            ],
          ),
        );
      },
    );
  }
}