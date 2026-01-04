import 'package:flutter/material.dart';

import '../services/database_service.dart';

class EmployeeManagementScreen extends StatefulWidget {
  const EmployeeManagementScreen({super.key});

  @override
  State<EmployeeManagementScreen> createState() => _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState extends State<EmployeeManagementScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _employees = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await DatabaseService.instance.getEmployees();
      if (!mounted) return;
      setState(() {
        _employees = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _upsertDialog({Map<String, dynamic>? employee}) async {
    final isEdit = employee != null;
    final ctrl = TextEditingController(text: (employee?['name']?.toString() ?? '').trim());

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Sửa nhân viên' : 'Thêm nhân viên'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Tên nhân viên',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lưu')),
        ],
      ),
    );

    if (ok != true) return;

    final name = ctrl.text.trim();
    if (name.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tên nhân viên không được để trống')));
      return;
    }

    try {
      if (isEdit) {
        final id = (employee['id']?.toString() ?? '').trim();
        if (id.isEmpty) return;
        await DatabaseService.instance.updateEmployee(id: id, name: name);
      } else {
        await DatabaseService.instance.createEmployee(name: name);
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  Future<void> _deleteEmployee(Map<String, dynamic> employee) async {
    final id = (employee['id']?.toString() ?? '').trim();
    final name = (employee['name']?.toString() ?? '').trim();
    if (id.isEmpty) return;

    final used = await DatabaseService.instance.isEmployeeUsed(id);
    if (!mounted) return;
    if (used) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể xóa: nhân viên đã được dùng trong giao dịch')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa nhân viên'),
        content: Text('Bạn có chắc muốn xóa "${name.isEmpty ? id : name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Xóa')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await DatabaseService.instance.deleteEmployee(id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhân viên'),
        actions: [
          IconButton(
            tooltip: 'Thêm nhân viên',
            icon: const Icon(Icons.add),
            onPressed: () => _upsertDialog(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _employees.isEmpty
              ? const Center(child: Text('Chưa có nhân viên'))
              : ListView.separated(
                  itemCount: _employees.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final e = _employees[i];
                    final id = (e['id']?.toString() ?? '').trim();
                    final name = (e['name']?.toString() ?? '').trim();
                    return ListTile(
                      leading: CircleAvatar(child: Text(id.isEmpty ? '?' : id.replaceAll(RegExp(r'[^0-9]'), '').padLeft(2, '0').substring(0, 2))),
                      title: Text(name.isEmpty ? id : name),
                      subtitle: Text(id),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'edit') {
                            await _upsertDialog(employee: e);
                          } else if (v == 'delete') {
                            await _deleteEmployee(e);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Sửa')),
                          PopupMenuItem(value: 'delete', child: Text('Xóa')),
                        ],
                      ),
                      onTap: () => _upsertDialog(employee: e),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _upsertDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
