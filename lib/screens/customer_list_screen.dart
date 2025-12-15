import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/customer_provider.dart';
import '../models/customer.dart';
import 'customer_form_screen.dart'; // Import form screen mới
import '../utils/text_normalizer.dart';
import '../services/database_service.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CustomerProvider>();
    final customers = provider.customers;

    final qn = TextNormalizer.normalize(_query);
    final filtered = qn.isEmpty
        ? customers
        : customers.where((c) {
            final name = TextNormalizer.normalize(c.name);
            final phone = (c.phone ?? '').trim();
            return name.contains(qn) || (phone.isNotEmpty && phone.contains(_query.trim()));
          }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Khách hàng / Nhà cung cấp'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Thêm khách hàng',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (ctx) => const CustomerFormScreen(),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Tìm theo tên / SĐT',
                isDense: true,
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final c = filtered[i];
                return ListTile(
                  leading: Icon(c.isSupplier ? Icons.local_shipping_outlined : Icons.person_outline),
                  title: Text(c.name),
                  subtitle: Text(c.phone ?? ''),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (ctx) => CustomerFormScreen(existing: c),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        tooltip: 'Xóa',
                        onPressed: () async {
                          final used = await DatabaseService.instance.isCustomerUsed(c.id);
                          if (!context.mounted) return;
                          if (used) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Khách hàng đã được sử dụng nên không thể xóa')),
                            );
                            return;
                          }

                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Xóa khách hàng'),
                              content: Text('Bạn có chắc muốn xóa "${c.name}" không?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
                                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa')),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await context.read<CustomerProvider>().delete(c.id);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa khách hàng')));
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}