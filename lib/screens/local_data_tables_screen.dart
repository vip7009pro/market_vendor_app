import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/customer_provider.dart';
import '../providers/debt_provider.dart';
import '../providers/product_provider.dart';
import '../providers/sale_provider.dart';
import '../services/database_service.dart';

class LocalDataTablesScreen extends StatefulWidget {
  const LocalDataTablesScreen({super.key});

  @override
  State<LocalDataTablesScreen> createState() => _LocalDataTablesScreenState();
}

class _LocalDataTablesScreenState extends State<LocalDataTablesScreen> {
  bool _loading = false;
  bool _deleting = false;
  String? _error;

  List<String> _tables = const [];
  Map<String, int> _rowCountByTable = const {};
  final Map<String, bool> _selected = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final tables = await DatabaseService.instance.getUserTables();
      final counts = await DatabaseService.instance.countRowsByTable(tables);

      if (!mounted) return;
      setState(() {
        _tables = tables;
        _rowCountByTable = counts;
        for (final t in tables) {
          _selected.putIfAbsent(t, () => false);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  void _setAll(bool v) {
    setState(() {
      for (final t in _tables) {
        _selected[t] = v;
      }
    });
  }

  Future<void> _deleteSelected() async {
    final selectedTables = _tables.where((t) => _selected[t] == true).toList();
    if (selectedTables.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xác nhận xóa dữ liệu'),
        content: Text('Xóa dữ liệu của ${selectedTables.length} bảng đã chọn? Thao tác này không thể hoàn tác.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa')),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _deleting = true;
      _error = null;
    });

    try {
      await DatabaseService.instance.clearTables(selectedTables);

      if (!mounted) return;

      await Future.wait([
        Provider.of<ProductProvider>(context, listen: false).load(),
        Provider.of<CustomerProvider>(context, listen: false).load(),
        Provider.of<SaleProvider>(context, listen: false).load(),
        Provider.of<DebtProvider>(context, listen: false).load(),
      ]);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã xóa dữ liệu các bảng đã chọn')));

      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _deleting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _tables.where((t) => _selected[t] == true).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Xóa dữ liệu theo bảng'),
        actions: [
          IconButton(
            tooltip: 'Tải lại',
            onPressed: _loading || _deleting ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: (_loading || _deleting || _tables.isEmpty) ? null : () => _setAll(true),
                    child: const Text('Check all'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: (_loading || _deleting || _tables.isEmpty) ? null : () => _setAll(false),
                    child: const Text('Uncheck all'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: (_loading || _deleting || selectedCount == 0) ? null : _deleteSelected,
                    icon: _deleting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.delete_forever_outlined),
                    label: Text(selectedCount == 0 ? 'Xóa' : 'Xóa ($selectedCount)'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _tables.isEmpty
                      ? const Center(child: Text('Không có bảng nào'))
                      : ListView.separated(
                          itemCount: _tables.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final t = _tables[i];
                            final c = _rowCountByTable[t] ?? 0;
                            final checked = _selected[t] == true;
                            return CheckboxListTile(
                              value: checked,
                              onChanged: _deleting
                                  ? null
                                  : (v) {
                                      setState(() {
                                        _selected[t] = v == true;
                                      });
                                    },
                              title: Text(t),
                              subtitle: Text('Số dòng: $c'),
                              controlAffinity: ListTileControlAffinity.leading,
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
