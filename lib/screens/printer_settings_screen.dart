import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

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
        return '58mm';
    }
  }

  String _typeLabel(ThermalPrinterType t) {
    switch (t) {
      case ThermalPrinterType.lan:
        return 'LAN';
      case ThermalPrinterType.bluetooth:
        return 'Bluetooth';
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

    var type = existing?.type ?? ThermalPrinterType.lan;
    var btMac = existing?.macAddress ?? '';

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
                  DropdownButtonFormField<ThermalPrinterType>(
                    value: type,
                    decoration: const InputDecoration(labelText: 'Loại máy in'),
                    items: const [
                      DropdownMenuItem(value: ThermalPrinterType.lan, child: Text('LAN/WiFi')),
                      DropdownMenuItem(value: ThermalPrinterType.bluetooth, child: Text('Bluetooth')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => type = v);
                    },
                  ),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Tên máy in'),
                  ),
                  const SizedBox(height: 8),
                  if (type == ThermalPrinterType.lan) ...[
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
                  ] else ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Thiết bị Bluetooth'),
                      subtitle: Text(btMac.isEmpty ? 'Chưa chọn' : btMac),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final enabled = await PrintBluetoothThermal.bluetoothEnabled;
                        if (!enabled) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Vui lòng bật Bluetooth để tìm máy in')),
                          );
                          return;
                        }

                        final paired = await PrintBluetoothThermal.pairedBluetooths;
                        if (!mounted) return;
                        final chosen = await showModalBottomSheet<BluetoothInfo>(
                          context: context,
                          showDragHandle: true,
                          builder: (ctx2) {
                            return SafeArea(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text('Chọn máy in Bluetooth', style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                  Flexible(
                                    child: paired.isEmpty
                                        ? const Center(child: Text('Chưa có thiết bị Bluetooth đã ghép đôi'))
                                        : ListView.separated(
                                            shrinkWrap: true,
                                            itemCount: paired.length,
                                            separatorBuilder: (_, __) => const Divider(height: 1),
                                            itemBuilder: (_, i) {
                                              final d = paired[i];
                                              return ListTile(
                                                leading: const Icon(Icons.bluetooth),
                                                title: Text(d.name),
                                                subtitle: Text(d.macAdress),
                                                onTap: () => Navigator.pop(ctx2, d),
                                              );
                                            },
                                          ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );

                        if (chosen != null) {
                          setState(() {
                            btMac = chosen.macAdress;
                            if (nameCtrl.text.trim().isEmpty) {
                              nameCtrl.text = chosen.name;
                            }
                          });
                        }
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ThermalPaperSize>(
                    value: paper,
                    decoration: const InputDecoration(labelText: 'Khổ giấy'),
                    items: const [
                      DropdownMenuItem(value: ThermalPaperSize.mm80, child: Text('80mm')),
                      DropdownMenuItem(value: ThermalPaperSize.mm57, child: Text('58mm')),
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

    if (name.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập tên máy in')));
      return;
    }

    if (type == ThermalPrinterType.lan) {
      if (ip.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập IP máy in')));
        return;
      }
    } else {
      if (btMac.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng chọn thiết bị Bluetooth')));
        return;
      }
    }

    final p = ThermalPrinterConfig(
      id: existing?.id,
      type: type,
      name: name,
      ip: type == ThermalPrinterType.lan ? ip : '',
      port: type == ThermalPrinterType.lan ? port : 9100,
      macAddress: type == ThermalPrinterType.bluetooth ? btMac.trim() : '',
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
                              final subtitle = p.type == ThermalPrinterType.bluetooth
                                  ? '${p.macAddress} • ${_paperLabel(p.paperSize)}'
                                  : '${p.ip}:${p.port} • ${_paperLabel(p.paperSize)}';
                              return ListTile(
                                leading: Icon(isDefault ? Icons.print : Icons.print_outlined),
                                title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text('${_typeLabel(p.type)} • $subtitle'),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: _loading ? null : () => _upsertPrinter(),
                          icon: const Icon(Icons.add),
                          label: const Text('Thêm máy in'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _loading
                              ? null
                              : () async {
                                  final paired = await PrintBluetoothThermal.pairedBluetooths;
                                  if (!mounted) return;
                                  if (paired.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Chưa có thiết bị Bluetooth đã ghép đôi')),
                                    );
                                  }
                                },
                          icon: const Icon(Icons.bluetooth_searching),
                          label: const Text('Tìm thiết bị Bluetooth (đã ghép đôi)'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
