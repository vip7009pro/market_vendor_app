import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/customer_provider.dart';
import '../models/customer.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../utils/contact_serializer.dart'; // Import serializer (nếu có cache)

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

  // FIX: removeDiacritics dùng groups.forEach như _vn, chính xác hơn single string (fix "hùng" -> "hung")
  String removeDiacritics(String s) {
    const groups = <String, String>{
      'a': 'àáạảãâầấậẩẫăằắặẳẵ',
      'A': 'ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴ',
      'e': 'èéẹẻẽêềếệểễ',
      'E': 'ÈÉẸẺẼÊỀẾỆỂỄ',
      'i': 'ìíịỉĩ',
      'I': 'ÌÍỊỈĨ',
      'o': 'òóọỏõôồốộổỗơờớợởỡ',
      'O': 'ÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠ',
      'u': 'ùúụủũưừứựửữ',
      'U': 'ÙÚỤỦŨƯỪỨỰỬỮ',
      'y': 'ỳýỵỷỹ',
      'Y': 'ỲÝỴỶỸ',
      'd': 'đ',
      'D': 'Đ',
    };
    groups.forEach((base, chars) {
      for (final ch in chars.split('')) {
        s = s.replaceAll(ch, base);
      }
    });
    return s;
  }

  // Helper: Lấy chữ cái đầu của các từ
  String getInitials(String str) {
    final normalized = removeDiacritics(str);
    final words = normalized.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return words.map((w) => w[0]).join().toLowerCase();
  }

  Future<void> _showCustomerDialog(BuildContext context, {Customer? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    bool isSupplier = existing?.isSupplier ?? false;

    List<Contact> allContacts = [];

    // FIX Load chậm: Ưu tiên load từ cache (ngay lập tức), fallback load fresh nếu rỗng
    allContacts = await ContactSerializer.loadContactsFromPrefs();
    if (allContacts.isEmpty) {
      try {
        final granted = await FlutterContacts.requestPermission();
        if (granted) {
          allContacts = await FlutterContacts.getContacts(withProperties: true, withPhoto: true);
          await ContactSerializer.saveContactsToPrefs(allContacts); // Cache lại nếu load mới
        }
      } catch (e) {
        debugPrint('Error getting contacts: $e');
      }
    }

    List<Contact> nameMatches = [];
    List<Contact> phoneMatches = [];

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existing == null ? 'Thêm liên hệ' : 'Sửa liên hệ'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Tên'),
                  onChanged: (value) {
                    if (value.isEmpty) {
                      nameMatches = [];
                    } else {
                      final normalizedQuery = removeDiacritics(value.toLowerCase());
                      final initialsQuery = getInitials(value.toLowerCase());
                      nameMatches = allContacts.where((c) {
                        if (c.displayName.isEmpty) return false;
                        final name = removeDiacritics(c.displayName.toLowerCase());
                        final initials = getInitials(c.displayName);
                        return name.contains(normalizedQuery) || initials.contains(initialsQuery);
                      }).take(5).toList();
                    }
                    setState(() {});
                  },
                ),
                if (nameMatches.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const ClampingScrollPhysics(),
                      itemExtent: 72,
                      itemCount: nameMatches.length,
                      itemBuilder: (context, idx) {
                        final contact = nameMatches[idx];
                        return ListTile(
                          leading: contact.photo != null 
                              ? CircleAvatar(backgroundImage: MemoryImage(contact.photo!))
                              : const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(contact.displayName),
                          subtitle: Text(contact.phones.isNotEmpty ? contact.phones.first.number : 'No phone'),
                          onTap: () {
                            nameCtrl.text = contact.displayName;
                            if (contact.phones.isNotEmpty) {
                              phoneCtrl.text = contact.phones.first.number;
                            }
                            nameMatches = [];
                            setState(() {});
                          },
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'SĐT (tuỳ chọn)'),
                  onChanged: (value) {
                    if (value.isEmpty) {
                      phoneMatches = [];
                    } else {
                      phoneMatches = allContacts.where((c) {
                        return c.phones.any((p) => (p.number).contains(value));
                      }).take(5).toList();
                    }
                    setState(() {});
                  },
                ),
                if (phoneMatches.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const ClampingScrollPhysics(),
                      itemExtent: 72,
                      itemCount: phoneMatches.length,
                      itemBuilder: (context, idx) {
                        final contact = phoneMatches[idx];
                        return ListTile(
                          leading: contact.photo != null 
                              ? CircleAvatar(backgroundImage: MemoryImage(contact.photo!))
                              : const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(contact.displayName),
                          subtitle: Text(contact.phones.isNotEmpty ? contact.phones.first.number : 'No phone'),
                          onTap: () {
                            phoneCtrl.text = contact.phones.first.number;
                            nameCtrl.text = contact.displayName;
                            phoneMatches = [];
                            setState(() {});
                          },
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Là nhà cung cấp (tôi nợ)'),
                  value: isSupplier,
                  onChanged: (v) => setState(() => isSupplier = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lưu')),
          ],
        ),
      ),
    );

    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      // ignore: use_build_context_synchronously
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