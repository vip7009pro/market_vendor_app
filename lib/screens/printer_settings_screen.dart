import 'package:flutter/material.dart';

import '../models/thermal_printer_config.dart';
import '../services/thermal_printer_settings_service.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  bool _loading = false;
  String? _error;
  List<ThermalPrinterConfig> _printers = const [];
  String? _defaultId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final printers = await ThermalPrinterSettingsService.instance.loadPrinters();
      final defaultId = await ThermalPrinterSettingsService.instance.getDefaultPrinterId();
      if (!mounted) return;
      setState(() {
        _printers = printers;
        _defaultId = defaultId;
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

  String _paperLabel(ThermalPaperSize s) {
    switch (s) {
      case ThermalPaperSize.mm80:
        return '80mm';
      case ThermalPaperSize.mm57:
        return '57mm';
    }
  }

  Future<void> _setDefault(String id) async {
    await ThermalPrinterSettingsService.instance.setDefaultPrinterId(id);
    await _load();
  }

  Future<void> _deletePrinter(ThermalPrinterConfig p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xóa máy in'),
        content: Text('Xóa "${p.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa')),
        ],
      ),
    );
    if (ok != true) return;

    final next = _printers.where((e) => e.id != p.id).toList();
    await ThermalPrinterSettingsService.instance.savePrinters(next);
    if (_defaultId == p.id) {
      await ThermalPrinterSettingsService.instance.setDefaultPrinterId(next.isEmpty ? null : next.first.id);
    }
    await _load();
  }

  Future<void> _upsertPrinter({ThermalPrinterConfig? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final ipCtrl = TextEditingController(text: existing?.ip ?? '');
    final portCtrl = TextEditingController(text: (existing?.port ?? 9100).toString());

    var paper = existing?.paperSize ?? ThermalPaperSize.mm80;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(existing == null ? 'Thêm máy in' : 'Sửa máy in'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Tên máy in'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: ipCtrl,
                    decoration: const InputDecoration(labelText: 'IP (LAN/WiFi)'),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: portCtrl,
                    decoration: const InputDecoration(labelText: 'Port'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ThermalPaperSize>(
                    value: paper,
                    decoration: const InputDecoration(labelText: 'Khổ giấy'),
                    items: const [
                      DropdownMenuItem(value: ThermalPaperSize.mm80, child: Text('80mm')),
                      DropdownMenuItem(value: ThermalPaperSize.mm57, child: Text('57mm')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => paper = v);
                    },
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lưu')),
          ],
        );
      },
    );

    if (ok != true) return;

    final name = nameCtrl.text.trim();
    final ip = ipCtrl.text.trim();
    final port = int.tryParse(portCtrl.text.trim()) ?? 9100;

    if (name.isEmpty || ip.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập tên và IP máy in')));
      return;
    }

    final p = ThermalPrinterConfig(
      id: existing?.id,
      type: ThermalPrinterType.lan,
      name: name,
      ip: ip,
      port: port,
      paperSize: paper,
    );

    final next = [..._printers];
    final idx = next.indexWhere((e) => e.id == p.id);
    if (idx >= 0) {
      next[idx] = p;
    } else {
      next.add(p);
    }

    await ThermalPrinterSettingsService.instance.savePrinters(next);

    final defaultId = await ThermalPrinterSettingsService.instance.getDefaultPrinterId();
    if (defaultId == null && next.isNotEmpty) {
      await ThermalPrinterSettingsService.instance.setDefaultPrinterId(next.first.id);
    }

    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Máy in nhiệt'),
        actions: [
          IconButton(
            tooltip: 'Thêm máy in',
            onPressed: _loading ? null : () => _upsertPrinter(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                    ),
                  Expanded(
                    child: _printers.isEmpty
                        ? const Center(child: Text('Chưa có máy in nào'))
                        : ListView.separated(
                            itemCount: _printers.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final p = _printers[i];
                              final isDefault = (_defaultId == null && i == 0) || _defaultId == p.id;
                              return ListTile(
                                leading: Icon(isDefault ? Icons.print : Icons.print_outlined),
                                title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text('${p.ip}:${p.port} • ${_paperLabel(p.paperSize)}'),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (v) async {
                                    if (v == 'default') await _setDefault(p.id);
                                    if (v == 'edit') await _upsertPrinter(existing: p);
                                    if (v == 'delete') await _deletePrinter(p);
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'default',
                                      child: Row(
                                        children: [
                                          Icon(isDefault ? Icons.check_circle : Icons.radio_button_unchecked),
                                          const SizedBox(width: 8),
                                          const Text('Đặt mặc định'),
                                        ],
                                      ),
                                    ),
                                    const PopupMenuItem(value: 'edit', child: Text('Sửa')),
                                    const PopupMenuItem(value: 'delete', child: Text('Xóa')),
                                  ],
                                ),
                                onTap: () => _setDefault(p.id),
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: FilledButton.icon(
                      onPressed: _loading ? null : () => _upsertPrinter(),
                      icon: const Icon(Icons.add),
                      label: const Text('Thêm máy in LAN'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
