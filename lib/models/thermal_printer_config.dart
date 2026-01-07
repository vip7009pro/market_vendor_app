import 'dart:convert';

import 'package:uuid/uuid.dart';

enum ThermalPrinterType { lan, bluetooth }

enum ThermalPaperSize { mm80, mm57 }

class ThermalPrinterConfig {
  final String id;
  final ThermalPrinterType type;
  final String name;
  final String ip;
  final int port;
  final String macAddress;
  final ThermalPaperSize paperSize;

  ThermalPrinterConfig({
    String? id,
    required this.type,
    required this.name,
    required this.ip,
    this.port = 9100,
    this.macAddress = '',
    this.paperSize = ThermalPaperSize.mm80,
  }) : id = id ?? const Uuid().v4();

  static ThermalPrinterType _parseType(dynamic v) {
    final s = (v?.toString() ?? '').toLowerCase().trim();
    switch (s) {
      case 'lan':
        return ThermalPrinterType.lan;
      case 'bluetooth':
        return ThermalPrinterType.bluetooth;
      default:
        return ThermalPrinterType.lan;
    }
  }

  static ThermalPaperSize _parsePaper(dynamic v) {
    final s = (v?.toString() ?? '').toLowerCase().trim();
    switch (s) {
      case 'mm57':
        return ThermalPaperSize.mm57;
      case 'mm80':
      default:
        return ThermalPaperSize.mm80;
    }
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'name': name,
        'ip': ip,
        'port': port,
        'macAddress': macAddress,
        'paperSize': paperSize.name,
      };

  factory ThermalPrinterConfig.fromMap(Map<String, dynamic> map) {
    return ThermalPrinterConfig(
      id: map['id']?.toString(),
      type: _parseType(map['type']),
      name: (map['name']?.toString() ?? '').trim(),
      ip: (map['ip']?.toString() ?? '').trim(),
      port: int.tryParse(map['port']?.toString() ?? '') ?? 9100,
      macAddress: (map['macAddress']?.toString() ?? '').trim(),
      paperSize: _parsePaper(map['paperSize']),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory ThermalPrinterConfig.fromJson(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return ThermalPrinterConfig.fromMap(m);
  }
}
