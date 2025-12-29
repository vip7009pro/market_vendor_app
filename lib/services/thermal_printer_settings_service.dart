import 'package:shared_preferences/shared_preferences.dart';

import '../models/thermal_printer_config.dart';

class ThermalPrinterSettingsService {
  static final ThermalPrinterSettingsService instance = ThermalPrinterSettingsService._();
  ThermalPrinterSettingsService._();

  static const _prefPrinters = 'thermal_printers';
  static const _prefDefaultPrinterId = 'thermal_printers_default_id';

  Future<List<ThermalPrinterConfig>> loadPrinters() async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_prefPrinters) ?? const <String>[];
    return list
        .map((e) {
          try {
            return ThermalPrinterConfig.fromJson(e);
          } catch (_) {
            return null;
          }
        })
        .whereType<ThermalPrinterConfig>()
        .toList();
  }

  Future<void> savePrinters(List<ThermalPrinterConfig> printers) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_prefPrinters, printers.map((e) => e.toJson()).toList());
  }

  Future<String?> getDefaultPrinterId() async {
    final sp = await SharedPreferences.getInstance();
    final id = sp.getString(_prefDefaultPrinterId);
    if (id == null || id.trim().isEmpty) return null;
    return id;
  }

  Future<void> setDefaultPrinterId(String? id) async {
    final sp = await SharedPreferences.getInstance();
    if (id == null || id.trim().isEmpty) {
      await sp.remove(_prefDefaultPrinterId);
      return;
    }
    await sp.setString(_prefDefaultPrinterId, id);
  }

  Future<ThermalPrinterConfig?> getDefaultPrinter() async {
    final printers = await loadPrinters();
    if (printers.isEmpty) return null;

    final id = await getDefaultPrinterId();
    if (id == null) return printers.first;

    try {
      return printers.firstWhere((p) => p.id == id);
    } catch (_) {
      return printers.first;
    }
  }
}
