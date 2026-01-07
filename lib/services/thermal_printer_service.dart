import 'package:esc_pos_printer_plus/esc_pos_printer_plus.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:intl/intl.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../models/sale.dart';
import '../models/thermal_printer_config.dart';

class ThermalPrinterService {
  static final ThermalPrinterService instance = ThermalPrinterService._();
  ThermalPrinterService._();

  PaperSize _paperSize(ThermalPaperSize s) {
    switch (s) {
      case ThermalPaperSize.mm57:
        return PaperSize.mm58;
      case ThermalPaperSize.mm80:
        return PaperSize.mm80;
    }
  }

  Future<void> printSaleReceipt({
    required ThermalPrinterConfig printerConfig,
    required Sale sale,
    required NumberFormat currency,
    required String storeName,
    required String storeAddress,
    required String storePhone,
  }) async {
    if (printerConfig.type == ThermalPrinterType.bluetooth) {
      await _printBluetooth(
        printerConfig: printerConfig,
        sale: sale,
        currency: currency,
        storeName: storeName,
        storeAddress: storeAddress,
        storePhone: storePhone,
      );
      return;
    }

    final profile = await CapabilityProfile.load();
    final printer = NetworkPrinter(_paperSize(printerConfig.paperSize), profile);

    final res = await printer.connect(printerConfig.ip, port: printerConfig.port);
    if (res != PosPrintResult.success) {
      throw Exception('Không kết nối được máy in (${res.msg})');
    }

    try {
      final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

      printer.text(storeName, styles: const PosStyles(align: PosAlign.center, bold: true));
      if (storeAddress.trim().isNotEmpty) {
        printer.text(storeAddress, styles: const PosStyles(align: PosAlign.center));
      }
      if (storePhone.trim().isNotEmpty) {
        printer.text(storePhone, styles: const PosStyles(align: PosAlign.center));
      }

      printer.hr();
      printer.text('HÓA ĐƠN THANH TOÁN', styles: const PosStyles(align: PosAlign.center, bold: true));
      printer.text('Mã HD: ${sale.id}');
      printer.text('Ngày: ${dateFormat.format(sale.createdAt)}');
      final customerName = sale.customerName?.trim().isNotEmpty == true ? sale.customerName!.trim() : 'Khách lẻ';
      printer.text('Khách: $customerName');
      printer.hr();

      for (final it in sale.items) {
        final name = (it.displayName ?? it.name).trim();
        final qty = it.quantity % 1 == 0 ? it.quantity.toInt().toString() : it.quantity.toString();
        final total = currency.format(it.unitPrice * it.quantity);

        printer.text(name, styles: const PosStyles(bold: true));
        printer.row([
          PosColumn(text: '${currency.format(it.unitPrice)} x $qty ${it.unit}', width: 8),
          PosColumn(text: total, width: 4, styles: const PosStyles(align: PosAlign.right)),
        ]);
      }

      printer.hr();
      printer.row([
        PosColumn(text: 'Tạm tính', width: 8),
        PosColumn(text: currency.format(sale.subtotal), width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]);

      if (sale.discount > 0) {
        printer.row([
          PosColumn(text: 'Giảm giá', width: 8),
          PosColumn(text: '-${currency.format(sale.discount)}', width: 4, styles: const PosStyles(align: PosAlign.right)),
        ]);
      }

      printer.row([
        PosColumn(text: 'TỔNG CỘNG', width: 8, styles: const PosStyles(bold: true)),
        PosColumn(
          text: currency.format(sale.total),
          width: 4,
          styles: const PosStyles(align: PosAlign.right, bold: true),
        ),
      ]);

      printer.row([
        PosColumn(text: 'Thanh toán', width: 8),
        PosColumn(text: currency.format(sale.paidAmount), width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]);

      if (sale.debt > 0) {
        printer.row([
          PosColumn(text: 'Còn nợ', width: 8, styles: const PosStyles(bold: true)),
          PosColumn(
            text: currency.format(sale.debt),
            width: 4,
            styles: const PosStyles(align: PosAlign.right, bold: true),
          ),
        ]);
      }

      printer.hr();
      printer.qrcode(sale.id);
      printer.text(sale.id, styles: const PosStyles(align: PosAlign.center));
      printer.feed(1);
      printer.text('Trân trọng cảm ơn!', styles: const PosStyles(align: PosAlign.center));
      printer.feed(2);
      printer.cut();
    } finally {
      printer.disconnect();
    }
  }

  Future<void> _printBluetooth({
    required ThermalPrinterConfig printerConfig,
    required Sale sale,
    required NumberFormat currency,
    required String storeName,
    required String storeAddress,
    required String storePhone,
  }) async {
    final mac = printerConfig.macAddress.trim();
    if (mac.isEmpty) {
      throw Exception('Thiếu địa chỉ MAC máy in Bluetooth');
    }

    final enabled = await PrintBluetoothThermal.bluetoothEnabled;
    if (!enabled) {
      throw Exception('Bluetooth đang tắt');
    }

    final connected = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
    if (!connected) {
      throw Exception('Không kết nối được máy in Bluetooth');
    }

    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(_paperSize(printerConfig.paperSize), profile);
      final bytes = <int>[];

      final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

      bytes.addAll(generator.text(storeName, styles: const PosStyles(align: PosAlign.center, bold: true)));
      if (storeAddress.trim().isNotEmpty) {
        bytes.addAll(generator.text(storeAddress, styles: const PosStyles(align: PosAlign.center)));
      }
      if (storePhone.trim().isNotEmpty) {
        bytes.addAll(generator.text(storePhone, styles: const PosStyles(align: PosAlign.center)));
      }

      bytes.addAll(generator.hr());
      bytes.addAll(generator.text('HÓA ĐƠN THANH TOÁN', styles: const PosStyles(align: PosAlign.center, bold: true)));
      bytes.addAll(generator.text('Mã HD: ${sale.id}'));
      bytes.addAll(generator.text('Ngày: ${dateFormat.format(sale.createdAt)}'));
      final customerName = sale.customerName?.trim().isNotEmpty == true ? sale.customerName!.trim() : 'Khách lẻ';
      bytes.addAll(generator.text('Khách: $customerName'));
      bytes.addAll(generator.hr());

      for (final it in sale.items) {
        final name = (it.displayName ?? it.name).trim();
        final qty = it.quantity % 1 == 0 ? it.quantity.toInt().toString() : it.quantity.toString();
        final total = currency.format(it.unitPrice * it.quantity);

        bytes.addAll(generator.text(name, styles: const PosStyles(bold: true)));
        bytes.addAll(
          generator.row([
            PosColumn(text: '${currency.format(it.unitPrice)} x $qty ${it.unit}', width: 8),
            PosColumn(text: total, width: 4, styles: const PosStyles(align: PosAlign.right)),
          ]),
        );
      }

      bytes.addAll(generator.hr());
      bytes.addAll(
        generator.row([
          PosColumn(text: 'Tạm tính', width: 8),
          PosColumn(text: currency.format(sale.subtotal), width: 4, styles: const PosStyles(align: PosAlign.right)),
        ]),
      );

      if (sale.discount > 0) {
        bytes.addAll(
          generator.row([
            PosColumn(text: 'Giảm giá', width: 8),
            PosColumn(text: '-${currency.format(sale.discount)}', width: 4, styles: const PosStyles(align: PosAlign.right)),
          ]),
        );
      }

      bytes.addAll(
        generator.row([
          PosColumn(text: 'TỔNG CỘNG', width: 8, styles: const PosStyles(bold: true)),
          PosColumn(
            text: currency.format(sale.total),
            width: 4,
            styles: const PosStyles(align: PosAlign.right, bold: true),
          ),
        ]),
      );

      bytes.addAll(
        generator.row([
          PosColumn(text: 'Thanh toán', width: 8),
          PosColumn(text: currency.format(sale.paidAmount), width: 4, styles: const PosStyles(align: PosAlign.right)),
        ]),
      );

      if (sale.debt > 0) {
        bytes.addAll(
          generator.row([
            PosColumn(text: 'Còn nợ', width: 8, styles: const PosStyles(bold: true)),
            PosColumn(
              text: currency.format(sale.debt),
              width: 4,
              styles: const PosStyles(align: PosAlign.right, bold: true),
            ),
          ]),
        );
      }

      bytes.addAll(generator.hr());
      bytes.addAll(generator.qrcode(sale.id));
      bytes.addAll(generator.text(sale.id, styles: const PosStyles(align: PosAlign.center)));
      bytes.addAll(generator.feed(1));
      bytes.addAll(generator.text('Trân trọng cảm ơn!', styles: const PosStyles(align: PosAlign.center)));
      bytes.addAll(generator.feed(2));
      bytes.addAll(generator.cut());

      final ok = await PrintBluetoothThermal.writeBytes(bytes);
      if (!ok) {
        throw Exception('Gửi lệnh in Bluetooth thất bại');
      }
    } finally {
      await PrintBluetoothThermal.disconnect;
    }
  }
}
