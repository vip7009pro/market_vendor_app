import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/customer_provider.dart';
import '../models/customer.dart';

class CustomerListScreen extends StatelessWidget {
  const CustomerListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CustomerProvider>();
    final customers = provider.customers;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Khách hàng / Nhà cung cấp'),
      ),
      body: ListView.separated(
        itemCount: customers.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final c = customers[i];
          return ListTile(
            leading: Icon(c.isSupplier ? Icons.local_shipping_outlined : Icons.person_outline),
            title: Text(c.name),
            subtitle: Text(c.phone ?? ''),
            trailing: IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _showCustomerDialog(context, existing: c),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCustomerDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _showCustomerDialog(BuildContext context, {Customer? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    bool isSupplier = existing?.isSupplier ?? false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existing == null ? 'Thêm liên hệ' : 'Sửa liên hệ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Tên')),
              const SizedBox(height: 8),
              TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'SĐT (tuỳ chọn)')),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Là nhà cung cấp (tôi nợ)') ,
                value: isSupplier,
                onChanged: (v) => setState(() => isSupplier = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lưu')),
          ],
        ),
      ),
    );

    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      final provider = context.read<CustomerProvider>();
      if (existing == null) {
        await provider.add(Customer(
          name: nameCtrl.text.trim(),
          phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
          isSupplier: isSupplier,
        ));
      } else {
        await provider.update(Customer(
          id: existing.id,
          name: nameCtrl.text.trim(),
          phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
          isSupplier: isSupplier,
          note: existing.note,
        ));
      }
    }
  }
}
