import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/debt.dart';
import '../providers/debt_provider.dart';
import '../providers/customer_provider.dart';
import '../models/customer.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../utils/contact_serializer.dart';
import '../utils/text_normalizer.dart';

class DebtFormScreen extends StatefulWidget {
  final Debt? existing;
  final DebtType? initialType;
  const DebtFormScreen({super.key, this.existing, this.initialType});

  @override
  State<DebtFormScreen> createState() => _DebtFormScreenState();
}

class _DebtFormScreenState extends State<DebtFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late DebtType _type;
  String? _partyId;
  String _partyName = '';
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _partyCtrl = TextEditingController();
  DateTime? _dueDate;
  bool _settled = false;

  String removeDiacritics(String str) {
    return str.replaceAllMapped(
      RegExp(r'[àáảãạăắằẵặẳâầấậẫẩđèéẻẽẹêềếệễểìíỉĩịòóỏõọôồốộỗổơờớợỡởùúủũụưừứựữửỳýỷỹỵ]'),
      (match) {
        const map = {
          'à': 'a', 'á': 'a', 'ả': 'a', 'ã': 'a', 'ạ': 'a',
          'ă': 'a', 'ắ': 'a', 'ằ': 'a', 'ẵ': 'a', 'ặ': 'a', 'ẳ': 'a',
          'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ậ': 'a', 'ẫ': 'a', 'ẩ': 'a',
          'đ': 'd',
          'è': 'e', 'é': 'e', 'ẻ': 'e', 'ẽ': 'e', 'ẹ': 'e',
          'ê': 'e', 'ề': 'e', 'ế': 'e', 'ệ': 'e', 'ễ': 'e', 'ể': 'e',
          'ì': 'i', 'í': 'i', 'ỉ': 'i', 'ĩ': 'i', 'ị': 'i',
          'ò': 'o', 'ó': 'o', 'ỏ': 'o', 'õ': 'o', 'ọ': 'o',
          'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ộ': 'o', 'ỗ': 'o', 'ổ': 'o',
          'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ợ': 'o', 'ỡ': 'o', 'ở': 'o',
          'ù': 'u', 'ú': 'u', 'ủ': 'u', 'ũ': 'u', 'ụ': 'u',
          'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ự': 'u', 'ữ': 'u', 'ử': 'u',
          'ỳ': 'y', 'ý': 'y', 'ỷ': 'y', 'ỹ': 'y', 'ỵ': 'y',
        };
        return map[match.group(0)] ?? match.group(0)!;
      },
    ).toLowerCase();
  }

  String getInitials(String name) {
    return name.split(' ').map((e) => e.isNotEmpty ? e[0] : '').join('').toUpperCase();
  }

  Future<Customer?> _showCustomerPicker() async {
    final customers = Provider.of<CustomerProvider>(context, listen: false).customers;
    
    return await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final TextEditingController searchController = TextEditingController();
        List<Customer> filteredCustomers = List.from(customers);

        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              padding: const EdgeInsets.all(16),
              height: MediaQuery.of(context).size.height * 0.8,
              child: Column(
                children: [
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      labelText: _type == DebtType.othersOweMe ? 'Tìm kiếm khách hàng' : 'Tìm kiếm nhà cung cấp',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          searchController.clear();
                          setState(() {
                            filteredCustomers = List.from(customers);
                          });
                        },
                      ),
                    ),
                    onChanged: (value) {
                      if (value.isEmpty) {
                        setState(() {
                          filteredCustomers = List.from(customers);
                        });
                      } else {
                        final query = removeDiacritics(value).toLowerCase();
                        setState(() {
                          filteredCustomers = customers.where((customer) {
                            final nameMatch = removeDiacritics(customer.name).toLowerCase().contains(query);
                            final phoneMatch = customer.phone?.toLowerCase().contains(query) ?? false;
                            return nameMatch || phoneMatch;
                          }).toList();
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: filteredCustomers.isEmpty
                        ? const Center(
                            child: Text('Không tìm thấy kết quả'),
                          )
                        : ListView.builder(
                            itemCount: filteredCustomers.length,
                            itemBuilder: (context, index) {
                              final customer = filteredCustomers[index];
                              return ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.person),
                                ),
                                title: Text(customer.name),
                                subtitle: Text(customer.phone ?? 'Không có SĐT'),
                                onTap: () {
                                  Navigator.of(context).pop(customer);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _addQuickCustomer() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Thêm ${_type == DebtType.othersOweMe ? 'khách hàng' : 'nhà cung cấp'} mới'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Tên',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Số điện thoại (tuỳ chọn)',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.contacts),
                  onPressed: () async {
                    final contact = await _showContactPicker();
                    if (contact != null) {
                      nameCtrl.text = contact.displayName;
                      if (contact.phones.isNotEmpty) {
                        phoneCtrl.text = contact.phones.first.number;
                      }
                    }
                  },
                  tooltip: 'Chọn từ danh bạ',
                ),
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
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );

    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      final name = nameCtrl.text.trim();
      final phone = phoneCtrl.text.trim();
      
      final provider = Provider.of<CustomerProvider>(context, listen: false);
      final newName = TextNormalizer.normalize(name);
      final duplicated = provider.customers.any((c) => TextNormalizer.normalize(c.name) == newName);
      
      if (duplicated) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã tồn tại người dùng cùng tên')),
        );
        return;
      }

      final customer = Customer(
        name: name,
        phone: phone.isEmpty ? null : phone,
      );
      
      await provider.add(customer);
      if (!mounted) return;
      setState(() {
        _partyId = customer.id;
        _partyName = customer.name;
        _partyCtrl.text = customer.name;
      });
    }
  }

  Future<Contact?> _showContactPicker() async {
    List<Contact> allContacts = await ContactSerializer.loadContactsFromPrefs();
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

    return await showModalBottomSheet<Contact>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final TextEditingController searchController = TextEditingController();
        List<Contact> filteredContacts = List.from(allContacts);

        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              padding: const EdgeInsets.all(16),
              height: MediaQuery.of(context).size.height * 0.8,
              child: Column(
                children: [
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      labelText: 'Tìm kiếm liên hệ',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          searchController.clear();
                          setState(() {
                            filteredContacts = List.from(allContacts);
                          });
                        },
                      ),
                    ),
                    onChanged: (value) {
                      if (value.isEmpty) {
                        setState(() {
                          filteredContacts = List.from(allContacts);
                        });
                      } else {
                        final query = removeDiacritics(value).toLowerCase();
                        setState(() {
                          filteredContacts = allContacts.where((contact) {
                            final nameMatch = removeDiacritics(contact.displayName).toLowerCase().contains(query);
                            final phoneMatch = contact.phones.any(
                              (phone) => phone.number.contains(query),
                            );
                            return nameMatch || phoneMatch;
                          }).toList();
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: filteredContacts.isEmpty
                        ? const Center(
                            child: Text('Không tìm thấy liên hệ nào'),
                          )
                        : ListView.builder(
                            itemCount: filteredContacts.length,
                            itemBuilder: (context, index) {
                              final contact = filteredContacts[index];
                              return ListTile(
                                leading: contact.photo != null
                                    ? CircleAvatar(
                                        backgroundImage: MemoryImage(contact.photo!),
                                        radius: 20,
                                      )
                                    : const CircleAvatar(
                                        child: Icon(Icons.person),
                                        radius: 20,
                                      ),
                                title: Text(contact.displayName),
                                subtitle: Text(
                                  contact.phones.isNotEmpty
                                      ? contact.phones.first.number
                                      : 'Không có SĐT',
                                ),
                                onTap: () {
                                  Navigator.of(context).pop(contact);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _type = e.type;
      _partyId = e.partyId;
      _partyName = e.partyName;
      _partyCtrl.text = e.partyName;
      _amountCtrl.text = e.amount.toStringAsFixed(0);
      _descCtrl.text = e.description ?? '';
      _dueDate = e.dueDate;
      _settled = e.settled;
    } else {
      _type = widget.initialType ?? DebtType.othersOweMe;
      _partyCtrl.text = '';
    }
  }

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 5),
      initialDate: _dueDate ?? now,
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Customers are now loaded in _showCustomerPicker

    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Thêm công nợ' : 'Sửa công nợ')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<DebtType>(
              segments: const [
                ButtonSegment(value: DebtType.othersOweMe, label: Text('Tiền nợ tôi'), icon: Icon(Icons.call_received)),
                ButtonSegment(value: DebtType.oweOthers, label: Text('Tiền tôi nợ'), icon: Icon(Icons.call_made)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _partyCtrl,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: _type == DebtType.othersOweMe ? 'Khách hàng' : 'Nhà cung cấp',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Chọn người liên quan' : null,
                    onTap: () async {
                      final customer = await _showCustomerPicker();
                      if (customer != null) {
                        setState(() {
                          _partyId = customer.id;
                          _partyName = customer.name;
                          _partyCtrl.text = customer.name;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 56,
                  width: 48,
                  child: IconButton(
                    icon: const Icon(Icons.person_add_alt),
                    onPressed: _addQuickCustomer,
                    tooltip: 'Thêm mới',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Số tiền (₫)'),
              validator: (v) {
                final val = double.tryParse((v ?? '').replaceAll(',', '.')) ?? -1;
                if (val <= 0) return 'Số tiền phải > 0';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Ghi chú (tuỳ chọn)'),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDueDate,
                    icon: const Icon(Icons.event),
                    label: Text(_dueDate == null ? 'Hạn thanh toán' : _dueDate!.toString().split(' ').first),
                  ),
                ),
                const SizedBox(width: 12),
                Row(children: [
                  const Text('Đã thanh toán'),
                  Switch(value: _settled, onChanged: (v) => setState(() => _settled = v)),
                ]),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () async {
                if (!_formKey.currentState!.validate()) return;
                final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '.')) ?? 0;
                final provider = Provider.of<DebtProvider>(context, listen: false);
                if (widget.existing == null) {
                  final d = Debt(
                    type: _type,
                    partyId: _partyId ?? 'unknown',
                    partyName: _partyName,
                    amount: amount,
                    description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
                    dueDate: _dueDate,
                    settled: _settled,
                  );
                  await provider.add(d);
                } else {
                  final e = widget.existing!;
                  final updated = Debt(
                    id: e.id,
                    createdAt: e.createdAt,
                    type: _type,
                    partyId: _partyId ?? e.partyId,
                    partyName: _partyName,
                    amount: amount,
                    description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
                    dueDate: _dueDate,
                    settled: _settled,
                  );
                  await provider.update(updated);
                }
                if (!mounted) return;
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.save),
              label: Text(widget.existing == null ? 'Lưu' : 'Cập nhật'),
            ),
          ],
        ),
      ),
    );
  }
}
