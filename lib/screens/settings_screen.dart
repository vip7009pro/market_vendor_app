import 'package:flutter/material.dart';
import 'package:market_vendor_app/providers/product_provider.dart';
import 'package:provider/provider.dart';
import '../main.dart'; // Import main.dart để lấy navigatorKey
import '../providers/auth_provider.dart';
import '../providers/customer_provider.dart';
import '../providers/debt_provider.dart';
import '../providers/sale_provider.dart';
import '../services/sync_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _syncing = false;

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
          const SizedBox(height: 8),
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
