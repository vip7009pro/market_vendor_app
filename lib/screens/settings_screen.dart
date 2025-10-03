import 'package:flutter/material.dart';
import 'package:market_vendor_app/providers/product_provider.dart';
import 'package:market_vendor_app/screens/store_info_screen.dart';
import 'package:provider/provider.dart';
import '../main.dart'; // Import main.dart để lấy navigatorKey
import '../providers/auth_provider.dart';
import '../providers/customer_provider.dart';
import '../providers/debt_provider.dart';
import '../providers/sale_provider.dart';
import '../providers/theme_provider.dart';
import '../services/sync_service.dart';
import '../services/drive_sync_service.dart';
import '../services/database_service.dart';
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView(
        padding: const EdgeInsets.all(10),
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).pushNamed('/products'),
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Sản phẩm'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).pushNamed('/customers'),
                icon: const Icon(Icons.people_outline),
                label: const Text('Khách hàng'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const StoreInfoScreen()),
                ),
                icon: const Icon(Icons.store),
                label: const Text('Thông tin cửa hàng'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ThemeSelectionScreen()),
                ),
                icon: const Icon(Icons.palette_outlined),
                label: const Text('Giao diện'),
              ),
              
            ],
          ),
          
          const SizedBox(height: 4),
          Card(
            child: ListTile(
              leading: CircleAvatar(
                radius: 24,
                backgroundImage: auth.isSignedIn && (auth.firebaseUser?.photoURL != null && auth.firebaseUser!.photoURL!.isNotEmpty)
                    ? NetworkImage(auth.firebaseUser!.photoURL!)
                    : null,
                child: !(auth.isSignedIn && (auth.firebaseUser?.photoURL != null && auth.firebaseUser!.photoURL!.isNotEmpty))
                    ? const Icon(Icons.person, size: 24)
                    : null,
              ),
              title: Text(auth.isSignedIn ? (auth.user?.displayName ?? auth.user?.email ?? 'Đã đăng nhập') : 'Chưa đăng nhập'),
              subtitle: Text(auth.isSignedIn ? (auth.user?.email ?? '') : 'Đăng nhập để đồng bộ dữ liệu'),
              trailing: SizedBox(
                width: 140,
                child: FilledButton.icon(
                  icon: Icon(auth.isSignedIn ? Icons.logout : Icons.login),
                  label: Text(auth.isSignedIn ? 'Đăng xuất' : 'Đăng nhập'),
                  onPressed: () async {
                    try {
                      if (auth.firebaseUser != null) {
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
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
           Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: const Text('Sao lưu'),
              subtitle: const Text('Lưu lên Drive'),
              trailing: _driveSyncing
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : SizedBox(
                      width: 140,
                      child: FilledButton.icon(
                        onPressed: auth.isSignedIn
                            ? () async {
                                setState(() => _driveSyncing = true);
                                try {
                                  final token = await context.read<AuthProvider>().getAccessToken();
                                  if (token == null || token.isEmpty) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Không lấy được token Google. Vui lòng đăng nhập lại.')),
                                    );
                                  } else {
                                    final msg = await DriveSyncService().uploadLocalDb(accessToken: token);
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
                        icon: const Icon(Icons.cloud_upload),
                        label: const Text('Tải lên'),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          // Google Drive sync card
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: const Text('Khôi phục'),
              subtitle: const Text('Khôi phục từ Drive'),
              trailing: _driveRestoring
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : SizedBox(
                      width: 140,
                      child: FilledButton.icon(
                        onPressed: auth.isSignedIn
                            ? () async {
                                setState(() => _driveRestoring = true);
                                try {
                                  final token = await context.read<AuthProvider>().getAccessToken();
                                  if (token == null || token.isEmpty) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Không lấy được token Google. Vui lòng đăng nhập lại.')),
                                    );
                                    return;
                                  }
                                  final drive = DriveSyncService();
                                  final files = await drive.listBackups(accessToken: token);
                                  if (!mounted) return;
                                  if (files.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Không có bản sao lưu nào trong Google Drive')),
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
                                        // Close current DB connection before replacing the file
                                        await DatabaseService.instance.close();
                                        await drive.restoreToLocal(accessToken: token, fileId: selected['id']!);
                                        // Reinitialize DB and then reload providers
                                        await DatabaseService.instance.reinitialize();
                                        await Future.wait([
                                          Provider.of<ProductProvider>(context, listen: false).load(),
                                          Provider.of<CustomerProvider>(context, listen: false).load(),
                                          Provider.of<SaleProvider>(context, listen: false).load(),
                                          Provider.of<DebtProvider>(context, listen: false).load(),
                                        ]);
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
                            : null,
                        icon: const Icon(Icons.sync),
                        label: const Text('Đồng bộ'),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_download_outlined),
              title: const Text('Tải dữ liệu từ đám mây'),
              subtitle: const Text('Tải dữ liệu mới nhất từ Firestore'),
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
