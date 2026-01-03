import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart' as package_info;
import 'package:market_vendor_app/screens/store_info_screen.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../providers/customer_provider.dart';
import '../providers/sale_provider.dart';
import '../providers/debt_provider.dart';
import '../providers/purchase_provider.dart';
import '../services/database_service.dart';
import '../services/drive_sync_service.dart';
import 'drive_backup_manager_screen.dart';
import 'sheets_sync_screen.dart';
import 'theme_selection_screen.dart';
import 'tax_declaration_form_screen.dart';
import 'vietqr_bank_accounts_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _syncing = false;
  bool _driveSyncing = false;
  bool _driveRestoring = false;
  String _appVersion = '';

  Future<void> _clearLocalDatabase() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xóa dữ liệu trên máy'),
        content: const Text('Bạn có chắc muốn xóa toàn bộ dữ liệu trên máy? Thao tác này không thể hoàn tác.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await DatabaseService.instance.close();
      await DatabaseService.instance.resetLocalDatabase();
      await DatabaseService.instance.reinitialize();

      if (!mounted) return;
      await Future.wait([
        Provider.of<ProductProvider>(context, listen: false).load(),
        Provider.of<CustomerProvider>(context, listen: false).load(),
        Provider.of<SaleProvider>(context, listen: false).load(),
        Provider.of<DebtProvider>(context, listen: false).load(),
      ]);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa dữ liệu trên máy')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi xóa dữ liệu: $e')));
    }
  }

  // Build a menu button with icon and label
  Widget _buildMenuButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.1)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const Spacer(),
              const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  void initState() {
    super.initState();
    _getAppVersion();
  }

  /// Show purchase dialog for premium features
  Future<void> _showPurchaseDialog(BuildContext context) async {
    final purchaseProvider = context.read<PurchaseProvider>();

    if (!purchaseProvider.isStoreAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cửa hàng không khả dụng trên thiết bị này')),
      );
      return;
    }

    final product = purchaseProvider.backupRestoreProduct;
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy sản phẩm. Vui lòng thử lại sau.')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nâng cấp Premium'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              product.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(product.description),
            const SizedBox(height: 16),
            const Text(
              'Tính năng Premium bao gồm:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('• Sao lưu dữ liệu lên Google Drive'),
            const Text('• Khôi phục dữ liệu từ Google Drive'),
            const Text('• Đồng bộ tự động'),
            const Text('• Hỗ trợ ưu tiên'),
            const SizedBox(height: 16),
            Text(
              'Giá: ${product.price}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.green,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Mua ngay'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final success = await purchaseProvider.purchaseProduct(product);
      if (!success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(purchaseProvider.lastError ?? 'Không thể bắt đầu giao dịch'),
          ),
        );
      } else if (success && mounted && purchaseProvider.lastSuccessMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(purchaseProvider.lastSuccessMessage!)),
        );
      }
    }
  }

  /// Check if user has premium access, show purchase dialog if not
  Future<bool> _checkPremiumAccess(BuildContext context) async {
    final purchaseProvider = context.read<PurchaseProvider>();

    // Try to restore previous purchases first (for cases when user installs on new device)
    await purchaseProvider.restorePurchases();

    // Also re-check premium status from local storage
    final hasPremium = await purchaseProvider.checkPremiumStatus();

    if (purchaseProvider.isPremiumUser || hasPremium) {
      return true;
    }

    // Show dialog to inform user about premium feature
    final shouldPurchase = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tính năng Premium'),
        content: const Text(
          'Sao lưu và khôi phục dữ liệu lên Google Drive là tính năng Premium. '
          'Bạn có muốn nâng cấp để sử dụng tính năng này không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Để sau'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Nâng cấp'),
          ),
        ],
      ),
    );

    if (shouldPurchase == true && mounted) {
      await _showPurchaseDialog(context);
      // Check again after purchase attempt
      return purchaseProvider.isPremiumUser;
    }

    return false;
  }

  Future<void> _getAppVersion() async {
    try {
      final info = await package_info.PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = 'Phiên bản ${info.version} (${info.buildNumber})';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _appVersion = 'Phiên bản chưa xác định';
        });
      }
      debugPrint('Failed to get app version: $e');
    }
    return null; // Add explicit return
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final purchaseProvider = context.watch<PurchaseProvider>();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
  elevation: 2,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
                        radius: 30,
                        // Chỉ hiện ảnh khi có URL
                        backgroundImage:
                            auth.isSignedIn &&
                                    auth.firebaseUser?.photoURL != null &&
                                    auth.firebaseUser!.photoURL!.isNotEmpty
                                ? NetworkImage(auth.firebaseUser!.photoURL!)
                                : null,
                        // Logic cho phần nội dung hiển thị đè lên hoặc thay thế
                        child:
                            auth.isSignedIn
                                ? (auth.firebaseUser?.photoURL == null ||
                                        auth.firebaseUser!.photoURL!.isEmpty
                                    ? Text(
                                      auth.firebaseUser?.displayName?[0]
                                              .toUpperCase() ??
                                          'U',
                                      style: const TextStyle(fontSize: 24),
                                    )
                                    : null) // Nếu đã có ảnh nền thì child phải là null để không đè icon lên ảnh
                                : const Icon(
                                  Icons.person,
                                  size: 30,
                                ), // Nếu chưa đăng nhập thì hiện icon
                      ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    auth.isSignedIn
                        ? (auth.firebaseUser?.displayName ?? 'Người dùng')
                        : 'Khách',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (auth.isSignedIn && auth.firebaseUser?.email != null)
                    Text(
                      auth.firebaseUser!.email!,
                      style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                    ),
                  if (!auth.isSignedIn)
                    Text(
                      'Đăng nhập để đồng bộ dữ liệu',
                      style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: auth.isLoading ? null : () async {
              if (auth.isSignedIn) {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Xác nhận đăng xuất'),
                    content: const Text('Bạn có chắc muốn đăng xuất?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Đăng xuất')),
                    ],
                  ),
                );
                if (confirm == true) await auth.signOut();
              } else {
                await auth.signInWithGoogle();
              }
            },
            icon: Icon(auth.isSignedIn ? Icons.logout : Icons.login),
            label: Text(auth.isSignedIn ? 'Đăng xuất' : 'Đăng nhập với Google'),
          ),
        ),
      ],
    ),
  ),
),
                   const SizedBox(height: 16),
          
          // Quick Actions Section
          Text(
            'Tính năng nhanh',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.5,
            children: [
              _buildMenuButton(
                context,
                icon: Icons.inventory_2_outlined,
                label: 'Sản phẩm',
                onTap: () => Navigator.of(context).pushNamed('/products'),
              ),
              _buildMenuButton(
                context,
                icon: Icons.people_outline,
                label: 'Khách hàng',
                onTap: () => Navigator.of(context).pushNamed('/customers'),
              ),
              _buildMenuButton(
                context,
                icon: Icons.store,
                label: 'Cửa hàng',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const StoreInfoScreen()),
                ),
              ),
              _buildMenuButton(
                context,
                icon: Icons.palette_outlined,
                label: 'Giao diện',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ThemeSelectionScreen()),
                ),
              ),
              _buildMenuButton(
                context,
                icon: Icons.description_outlined,
                label: 'Khai thuế',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const TaxDeclarationFormScreen()),
                ),
              ),
              _buildMenuButton(
                context,
                icon: Icons.qr_code_2_outlined,
                label: 'Ngân hàng',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const VietQrBankAccountsScreen()),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Backup & Restore Section
          Text(
            'Sao lưu & Khôi phục',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.cloud_outlined, color: theme.colorScheme.primary),
                  title: const Text('Quản lý backup Google Drive'),
                  subtitle: const Text('Xem danh sách / xóa / backup ngay'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: auth.isSignedIn
                      ? () async {
                          final hasPremium = await _checkPremiumAccess(context);
                          if (!hasPremium) return;
                          if (!mounted) return;
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const DriveBackupManagerScreen(),
                            ),
                          );
                        }
                      : null,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.table_view_outlined, color: theme.colorScheme.primary),
                  title: const Text('Đồng bộ Google Sheets'),
                  subtitle: const Text('Tạo sheet / đồng bộ dữ liệu'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: auth.isSignedIn
                      ? () async {
                          final hasPremium = await _checkPremiumAccess(context);
                          if (!hasPremium) return;
                          if (!mounted) return;
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SheetsSyncScreen(),
                            ),
                          );
                        }
                      : null,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.backup, color: theme.colorScheme.primary),
                  title: const Text('Sao lưu dữ liệu'),
                  subtitle: const Text('Lưu dữ liệu lên Google Drive'),
                  trailing: _driveSyncing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : FilledButton.icon(
                          onPressed: auth.isSignedIn
                              ? () async {
                                  // Check premium access first
                                  final hasPremium = await _checkPremiumAccess(context);
                                  if (!hasPremium) return;

                                  setState(() => _driveSyncing = true);
                                  try {
                                    final token = await context.read<AuthProvider>().getAccessToken();
                                    if (token == null || token.isEmpty) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text('Không lấy được token Google. Vui lòng đăng nhập lại.')),
                                      );
                                    } else {
                                      final msg = await DriveSyncService().uploadLocalDb(accessToken: token);
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text(msg)),
                                      );
                                    }
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Lỗi khi đồng bộ Google Drive: $e')),
                                    );
                                  } finally {
                                    if (mounted) setState(() => _driveSyncing = false);
                                  }
                                }
                              : null,
                          icon: const Icon(Icons.cloud_upload, size: 16),
                          label: const Text('Sao lưu'),
                        ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.restore, color: theme.colorScheme.primary),
                  title: const Text('Khôi phục dữ liệu'),
                  subtitle: const Text('Khôi phục dữ liệu từ Google Drive'),
                  trailing: _driveRestoring
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : FilledButton.icon(
                          onPressed: auth.isSignedIn
                              ? () async {
                                  // Check premium access first
                                  final hasPremium = await _checkPremiumAccess(context);
                                  if (!hasPremium) return;
                                  
                                  setState(() => _driveRestoring = true);
                                  try {
                                    final token = await context.read<AuthProvider>().getAccessToken();
                                    if (token == null || token.isEmpty) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text('Không lấy được token Google. Vui lòng đăng nhập lại.')),
                                      );
                                      return;
                                    }
                                    final drive = DriveSyncService();
                                    final files = await drive.listBackups(accessToken: token);
                                    if (!mounted) return;
                                    if (files.isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text('Không có bản sao lưu nào trong Google Drive')),
                                      );
                                    } else {
                                    final selected = await showModalBottomSheet<Map<String, String>>(
                                      context: context,
                                      showDragHandle: true,
                                      builder: (sheetCtx) {
                                        return SafeArea(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Padding(
                                                padding: EdgeInsets.all(16),
                                                child: Text('Chọn bản sao lưu', style: TextStyle(fontWeight: FontWeight.bold)),
                                              ),
                                              Flexible(
                                                child: ListView.separated(
                                                  shrinkWrap: true,
                                                  itemCount: files.length,
                                                  separatorBuilder: (_, __) => const Divider(height: 1),
                                                  itemBuilder: (_, i) {
                                                    final f = files[i];
                                                    final name = f['name'] ?? '';
                                                    final time = f['modifiedTime'] ?? '';
                                                    final lower = name.toLowerCase();
                                                    final isZip = lower.endsWith('.zip');
                                                    final isDb = lower.endsWith('.db');
                                                    return ListTile(
                                                      leading: Icon(isZip ? Icons.archive_outlined : Icons.backup_outlined),
                                                      title: Text(name),
                                                      subtitle: Text(time),
                                                      trailing: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          borderRadius: BorderRadius.circular(999),
                                                          color: (isZip ? Colors.green : (isDb ? Colors.blueGrey : Colors.black45))
                                                              .withValues(alpha: 0.12),
                                                          border: Border.all(
                                                            color: (isZip ? Colors.green : (isDb ? Colors.blueGrey : Colors.black45))
                                                                .withValues(alpha: 0.30),
                                                          ),
                                                        ),
                                                        child: Text(
                                                          isZip ? 'ZIP: DB + Ảnh' : (isDb ? 'DB-only' : 'File'),
                                                          style: TextStyle(
                                                            color: isZip ? Colors.green : (isDb ? Colors.blueGrey : Colors.black45),
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                      onTap: () => Navigator.pop(sheetCtx, f),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    );
                                    if (selected != null) {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (_) => AlertDialog(
                                          title: const Text('Xác nhận khôi phục'),
                                          content: Text('Khôi phục từ "${selected['name'] ?? ''}"? Dữ liệu hiện tại sẽ bị ghi đè.'),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
                                            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Khôi phục')),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        try {
                                          // Close current DB connection before replacing the file
                                          await DatabaseService.instance.close();
                                          await drive.restoreToLocal(accessToken: token, fileId: selected['id']!);
                                          // Reinitialize DB and then reload providers
                                          await DatabaseService.instance.reinitialize();
                                          
                                          // Get providers before using them
                                          if (!mounted) return;
                                          final productProvider = Provider.of<ProductProvider>(context, listen: false);
                                          final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
                                          final saleProvider = Provider.of<SaleProvider>(context, listen: false);
                                          final debtProvider = Provider.of<DebtProvider>(context, listen: false);
                                          
                                          // Load data
                                          await Future.wait([
                                            productProvider.load(),
                                            customerProvider.load(),
                                            saleProvider.load(),
                                            debtProvider.load(),
                                          ]);
                                        } catch (e) {
                                          debugPrint('Error during restore: $e');
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Lỗi khi khôi phục dữ liệu: $e')),
                                            );
                                          }
                                          rethrow;
                                        }
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Đã khôi phục từ ${selected['name'] ?? ''}')),
                                        );
                                      }
                                    }
                                  }
                                } catch (e) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Lỗi khôi phục: $e')),
                                  );
                                } finally {
                                  if (mounted) setState(() => _driveRestoring = false);
                                }
                              }
                            : null,
                        icon: const Icon(Icons.download),
                        label: const Text('Khôi phục'),
                      ),
                    ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_forever_outlined, color: Colors.redAccent),
                  title: const Text('Xóa dữ liệu trên máy', style: TextStyle(color: Colors.redAccent)),
                  subtitle: const Text('Xóa toàn bộ dữ liệu local (không thể hoàn tác)'),
                  onTap: _clearLocalDatabase,
                ),
        ]),
          ),
          
          // Premium Status Card
          if (purchaseProvider.isStoreAvailable)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Card(
                color: purchaseProvider.isPremiumUser 
                    ? theme.colorScheme.primaryContainer 
                    : null,
                child: ListTile(
                  leading: Icon(
                    purchaseProvider.isPremiumUser 
                        ? Icons.workspace_premium 
                        : Icons.lock_outline,
                    color: purchaseProvider.isPremiumUser 
                        ? theme.colorScheme.primary 
                        : null,
                  ),
                  title: Text(
                    purchaseProvider.isPremiumUser 
                        ? 'Tài khoản Premium' 
                        : 'Nâng cấp Premium',
                  ),
                  subtitle: Text(
                    purchaseProvider.isPremiumUser 
                        ? 'Bạn đang sử dụng tất cả tính năng premium' 
                        : 'Mở khóa sao lưu Google Drive và nhiều tính năng khác',
                  ),
                  trailing: purchaseProvider.isPremiumUser 
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : TextButton(
                          onPressed: () => _showPurchaseDialog(context),
                          child: const Text('Xem thêm'),
                        ),
                ),
              ),
            ),
          
          const SizedBox(height: 4),
         
          
         /*  Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_sync_outlined),
              title: const Text('Đồng bộ dữ liệu'),
              subtitle: const Text('Đồng bộ dữ liệu với đám mây'),
              trailing: _syncing
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : SizedBox(
                      width: 140,
                      child: FilledButton.icon(
                        onPressed: auth.isSignedIn && auth.uid != null
                            ? () async {
                                setState(() => _syncing = true);
                                try {
                                  final syncService = SyncService(navigatorKey: navigatorKey);
                                  final userId = auth.uid!;
                                  await syncService.syncNow(userId: userId);
                                  // Refresh providers
                                  await Future.wait([
                                    Provider.of<ProductProvider>(context, listen: false).load(),
                                    Provider.of<CustomerProvider>(context, listen: false).load(),
                                    Provider.of<SaleProvider>(context, listen: false).load(),
                                    Provider.of<DebtProvider>(context, listen: false).load(),
                                  ]);
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Đồng bộ và cập nhật dữ liệu thành công')),
                                  );
                                } catch (e, st) {
                                  debugPrint('Sync error: $e\n$st');
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Lỗi khi đồng bộ: $e')),
                                  );
                                } finally {
                                  if (mounted) setState(() => _syncing = false);
                                }
                              }
                        icon: const Icon(Icons.sync),
                        label: const Text('Đồng bộ'),
                      ),
                    ),
          // Add About section at the bottom
          const SizedBox(height: 24),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
                      width: 140,
                      child: FilledButton.icon(
                        onPressed: auth.isSignedIn && auth.uid != null
                            ? () async {
                                setState(() => _syncing = true);
                                try {
                                  final syncService = SyncService(navigatorKey: navigatorKey);
                                  final userId = auth.uid!;
                                  await syncService.pullFromFirestore(userId: userId);
                                  await Future.wait([
                                    Provider.of<CustomerProvider>(context, listen: false).load(),
                                    Provider.of<DebtProvider>(context, listen: false).load(),
                                    Provider.of<SaleProvider>(context, listen: false).load(),
                                    Provider.of<ProductProvider>(context, listen: false).load(),
                                  ]);
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Đã tải dữ liệu từ đám mây')),
                                  );
                                } catch (e) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Lỗi tải dữ liệu: $e')),
                                  );
                                } finally {
                                  if (mounted) setState(() => _syncing = false);
                                }
                              }
                            : null,
                        icon: const Icon(Icons.cloud_download),
                        label: const Text('Tải về'),
                      ),
                    ),
            ),
          ),
           */
          const SizedBox(height: 8),
          const _AboutCard(),
        ],
      ),
    );
  }
}

class _AboutCard extends StatefulWidget {
  const _AboutCard();

  @override
  _AboutCardState createState() => _AboutCardState();
}

class _AboutCardState extends State<_AboutCard> {
  String _appVersion = 'Đang tải...';

  @override
  void initState() {
    super.initState();
    _getAppVersion();
  }

  Future<void> _getAppVersion() async {
    try {
      final info = await package_info.PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = 'Phiên bản: ${info.version} (${info.buildNumber})';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _appVersion = 'Không thể tải phiên bản';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ứng dụng quản lý bán hàng cho tiểu thương', 
              style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('• Ghi bán nhanh, quản lý công nợ, báo cáo đơn giản\n• Hoạt động offline, đồng bộ khi có mạng'),
            const SizedBox(height: 8),
            Text(
              _appVersion,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
