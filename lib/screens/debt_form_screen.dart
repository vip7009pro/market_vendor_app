import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/debt.dart';
import '../providers/debt_provider.dart';
import '../providers/customer_provider.dart';
import '../models/customer.dart';

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
  DateTime? _dueDate;
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _type = e.type;
      _partyId = e.partyId;
      _partyName = e.partyName;
      _amountCtrl.text = e.amount.toStringAsFixed(0);
      _descCtrl.text = e.description ?? '';
      _dueDate = e.dueDate;
      _settled = e.settled;
    } else {
      _type = widget.initialType ?? DebtType.othersOweMe;
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
    final customers = context.watch<CustomerProvider>().customers;

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
            Autocomplete<Customer>(
              optionsBuilder: (text) {
                final q = text.text.toLowerCase();
                if (q.isEmpty) return customers;
                return customers.where((c) => c.name.toLowerCase().contains(q));
              },
              displayStringForOption: (c) => c.name,
              fieldViewBuilder: (context, ctrl, focus, onSubmit) {
                if (_partyName.isNotEmpty) ctrl.text = _partyName;
                return TextFormField(
                  controller: ctrl,
                  focusNode: focus,
                  decoration: const InputDecoration(labelText: 'Khách hàng/Nhà cung cấp'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập tên người liên quan' : null,
                  onChanged: (v) {
                    setState(() {
                      _partyId = null;
                      _partyName = v.trim();
                    });
                  },
                );
              },
              onSelected: (c) {
                setState(() {
                  _partyId = c.id;
                  _partyName = c.name;
                });
              },
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
                final provider = context.read<DebtProvider>();
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
