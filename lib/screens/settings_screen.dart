import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart' as package_info;
import 'package:market_vendor_app/screens/store_info_screen.dart';
import '../main.dart';
import '../providers/auth_provider.dart';
import '../providers/product_provider.dart';
import '../providers/customer_provider.dart';
import '../providers/sale_provider.dart';
import '../providers/debt_provider.dart';
import '../services/database_service.dart';
import '../services/drive_sync_service.dart';
import 'theme_selection_screen.dart';

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
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài đặt'),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // User Profile Card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundImage: auth.isSignedIn && 
                                      auth.firebaseUser?.photoURL != null && 
                                      auth.firebaseUser!.photoURL!.isNotEmpty
                            ? NetworkImage(auth.firebaseUser!.photoURL!)
                            : null,
                        child: !(auth.isSignedIn && 
                                auth.firebaseUser?.photoURL != null && 
                                auth.firebaseUser!.photoURL!.isNotEmpty)
                            ? const Icon(Icons.person, size: 30)
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              auth.isSignedIn 
                                  ? (auth.user?.displayName ?? auth.user?.email ?? 'Người dùng')
                                  : 'Khách',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (auth.isSignedIn && auth.user?.email != null)
                              Text(
                                auth.user!.email!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.textTheme.bodySmall?.color,
                                ),
                              ),
                            if (!auth.isSignedIn)
                              Text(
                                'Đăng nhập để đồng bộ dữ liệu',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.textTheme.bodySmall?.color,
                                ),
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
                      onPressed: () async {
                        try {
                          if (auth.firebaseUser != null) {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('Xác nhận đăng xuất'),
                                content: const Text('Bạn có chắc muốn đăng xuất?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Hủy'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('Đăng xuất'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await auth.signOut();
                              if (mounted) {
                                Navigator.of(context).popUntil((route) => route.isFirst);
                              }
                            }
                          } else {
                            await auth.signIn();
                            if (mounted) {
                              Navigator.of(context).popUntil((route) => route.isFirst);
                            }
                          }
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Lỗi xác thực: ${e.toString()}')),
                          );
                        }
                      },
                      icon: Icon(auth.isSignedIn ? Icons.logout : Icons.login),
                      label: Text(auth.isSignedIn ? 'Đăng xuất' : 'Đăng nhập'),
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
                                                    return ListTile(
                                                      title: Text(name),
                                                      subtitle: Text(time),
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
                        label: const Text('Tải xuống'),
                      ),
                    ),
        ]),
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
           */const SizedBox(height: 8),
          const _AboutCard(),
        ],
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('Ứng dụng quản lý bán hàng cho tiểu thương', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('• Ghi bán nhanh, quản lý công nợ, báo cáo đơn giản\n• Hoạt động offline, đồng bộ khi có mạng'),
          ],
        ),
      ),
    );
  }
}
