import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/customer_provider.dart';
import '../models/customer.dart';
import 'customer_form_screen.dart'; // Import form screen mới

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
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (ctx) => CustomerFormScreen(existing: c),
                ),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (ctx) => const CustomerFormScreen(),
          ),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}