import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/customer_provider.dart';
import '../models/customer.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../utils/contact_serializer.dart'; // Import serializer (nếu có cache)
import '../utils/text_normalizer.dart';

class CustomerFormScreen extends StatefulWidget {
  final Customer? existing;
  const CustomerFormScreen({super.key, this.existing});

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  bool isSupplier = false;

  late List<Contact> allContacts;
  List<Contact> nameMatches = [];
  List<Contact> phoneMatches = [];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      nameCtrl.text = widget.existing!.name;
      phoneCtrl.text = widget.existing!.phone ?? '';
      isSupplier = widget.existing!.isSupplier;
    }
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    allContacts = await ContactSerializer.loadContactsFromPrefs();
    if (allContacts.isEmpty) {
      try {
        final granted = await FlutterContacts.requestPermission();
        if (granted) {
          allContacts = await FlutterContacts.getContacts(withProperties: true, withPhoto: true);
          await ContactSerializer.saveContactsToPrefs(allContacts);
        }
      } catch (e) {
        debugPrint('Error getting contacts: $e');
      }
    }
    setState(() {});
  }

  // Helper: Chuyển đổi tiếng Việt có dấu thành không dấu
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Thêm liên hệ' : 'Sửa liên hệ'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: nameCtrl.text.trim().isEmpty
                ? null
                : () async {
                    final provider = context.read<CustomerProvider>();
                    final newName = TextNormalizer.normalize(nameCtrl.text);
                    final duplicated = provider.customers.any((c) {
                      if (widget.existing != null && c.id == widget.existing!.id) return false;
                      return TextNormalizer.normalize(c.name) == newName;
                    });
                    if (duplicated) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã tồn tại khách hàng cùng tên')));
                      return;
                    }
                    if (widget.existing == null) {
                      await provider.add(Customer(
                        name: nameCtrl.text.trim(),
                        phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                        isSupplier: isSupplier,
                      ));
                    } else {
                      await provider.update(Customer(
                        id: widget.existing!.id,
                        name: nameCtrl.text.trim(),
                        phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                        isSupplier: isSupplier,
                        note: widget.existing!.note,
                      ));
                    }
                    if (mounted) Navigator.pop(context);
                  },
            child: const Text('Lưu'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Tên'),
              onChanged: (value) {
                if (value.isEmpty) {
                  nameMatches = [];
                } else {
                  // FIX: Chỉ match full tên (case-insensitive + dấu/không dấu), bỏ initials
                  final valueLower = value.toLowerCase();
                  final normalizedQuery = removeDiacritics(valueLower);
                  nameMatches = allContacts.where((c) {
                    if (c.displayName.isEmpty) return false;
                    final displayNameLower = c.displayName.toLowerCase();
                    final normalizedName = removeDiacritics(displayNameLower);
                    // Match full tên: case-insensitive OR normalized (dấu/không dấu)
                    return displayNameLower.contains(valueLower) || normalizedName.contains(normalizedQuery);
                  }).toList(); // Hiển thị tất cả match, không giới hạn
                }
                setState(() {});
              },
            ),
            if (nameMatches.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 216), // ~3 items, cho phép cuộn
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
                      subtitle: Text(contact.phones.isNotEmpty ? contact.phones.first.number ?? '' : 'No phone'),
                      onTap: () {
                        nameCtrl.text = contact.displayName;
                        if (contact.phones.isNotEmpty) {
                          phoneCtrl.text = contact.phones.first.number ?? '';
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
                  // FIX: Filter phone hỗ trợ partial theo thứ tự (contains), bất kỳ vị trí nào (substring)
                  phoneMatches = allContacts.where((c) {
                    return c.phones.any((p) => (p.number ?? '').contains(value)); // Giữ contains để match giữa (ví dụ "123" match "0123456")
                  }).toList(); // Hiển thị tất cả match, không giới hạn
                }
                setState(() {});
              },
            ),
            if (phoneMatches.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 216), // ~3 items, cho phép cuộn
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
                      subtitle: Text(contact.phones.isNotEmpty ? contact.phones.first.number ?? '' : 'No phone'),
                      onTap: () {
                        phoneCtrl.text = contact.phones.first.number ?? '';
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
    );
  }
}