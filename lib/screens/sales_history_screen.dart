import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/sale_provider.dart';
import '../models/sale.dart';
import '../utils/file_helper.dart';

// Vietnamese diacritics removal (accent-insensitive search)
String _vn(String s) {
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

// --- MÀN HÌNH CHÍNH: SalesHistoryScreen ---

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  DateTimeRange? _range;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final sales = context.watch<SaleProvider>().sales;
    final fmtDate = DateFormat('dd/MM/yyyy HH:mm');
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);

    var filtered = sales;
    if (_range != null) {
      final start = DateTime(_range!.start.year, _range!.start.month, _range!.start.day);
      final end = DateTime(_range!.end.year, _range!.end.month, _range!.end.day, 23, 59, 59, 999);
      filtered = filtered
          .where((s) => s.createdAt.isAfter(start.subtract(const Duration(milliseconds: 1))) && s.createdAt.isBefore(end.add(const Duration(milliseconds: 1))))
          .toList();
    }
    if (_query.isNotEmpty) {
      final q = _vn(_query).toLowerCase();
      filtered = filtered.where((s) {
        final customer = _vn(s.customerName ?? '').toLowerCase();
        final items = _vn(s.items.map((e) => e.name).join(', ')).toLowerCase();
        return customer.contains(q) || items.contains(q);
      }).toList();
    }

    // Tạo bản sao và sắp xếp theo createdAt giảm dần (mới nhất lên đầu)
    final List<Sale> sortedFiltered = List.from(filtered)..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử bán hàng'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(now.year - 2),
                lastDate: DateTime(now.year + 1),
                initialDateRange: _range,
              );
              if (picked != null) setState(() => _range = picked);
            },
          ),
          PopupMenuButton<String>(
            onSelected: (val) async {
              if (val == 'delete_all') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Xóa tất cả lịch sử'),
                    content: const Text('Bạn có chắc muốn xóa tất cả lịch sử bán hàng?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa')),
                    ],
                  ),
                );
                if (ok == true) {
                  final messenger = ScaffoldMessenger.of(context);
                  await context.read<SaleProvider>().deleteAll();
                  messenger.showSnackBar(
                    SnackBar(
                      content: const Text('Đã xóa tất cả lịch sử'),
                      action: SnackBarAction(
                        label: 'Hoàn tác',
                        onPressed: () async {
                          final ok = await context.read<SaleProvider>().undoDeleteAll();
                          if (ok) messenger.showSnackBar(const SnackBar(content: Text('Đã khôi phục')));
                        },
                      ),
                    ),
                  );
                }
              } else if (val == 'export_csv') {
                await _exportCsv(context, sortedFiltered); // Sử dụng sortedFiltered
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'delete_all', child: Text('Xóa tất cả')),
              PopupMenuItem(value: 'export_csv', child: Text('Xuất CSV')),
            ],
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Tìm theo khách hàng / mặt hàng',
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    _range == null
                        ? 'Khoảng ngày'
                        : '${DateFormat('dd/MM').format(_range!.start)} - ${DateFormat('dd/MM').format(_range!.end)}',
                  ),
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(now.year - 2),
                      lastDate: DateTime(now.year + 1),
                      initialDateRange: _range,
                    );
                    if (picked != null) setState(() => _range = picked);
                  },
                ),
                if (_range != null)
                  IconButton(
                    tooltip: 'Xoá lọc ngày',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _range = null),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: sortedFiltered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final s = sortedFiltered[i];
                final customer = s.customerName?.trim().isEmpty == false ? s.customerName!.trim() : 'Khách lẻ';
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  elevation: 1,
                  child: InkWell(
                    onTap: () {
                      // Handle tap if needed
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header row with customer and total
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  customer,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: s.debt > 0 ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  currency.format(s.total),
                                  style: TextStyle(
                                    color: s.debt > 0 ? Colors.red : Colors.green,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          
                          // Date and time
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              fmtDate.format(s.createdAt),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ),
                          
                          // Items list
                          const SizedBox(height: 8),
                          ...s.items.map((item) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: const BoxDecoration(
                                    color: Colors.blue,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    '${item.name} x ${item.quantity} ${item.unit}',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                                Text(
                                  '${currency.format(item.unitPrice)} x ${item.quantity} = ${currency.format(item.unitPrice * item.quantity)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          )).toList(),
                          
                          // Payment status and actions
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (s.debt > 0) 
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Còn nợ: ${currency.format(s.debt)}',
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Đã thanh toán',
                                    style: TextStyle(
                                      color: Colors.green,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              
                              // New Print Button & Delete Button
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.print_outlined, color: Colors.blueAccent, size: 20),
                                    tooltip: 'In hóa đơn',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () => _showPrintPreview(context, s, currency), // Gọi hàm hiển thị preview
                                  ),
                                  const SizedBox(width: 8), 
                                  // Delete button
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                    tooltip: 'Xóa hóa đơn',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () async {
                                      final ok = await showDialog<bool>(
                                        context: context,
                                        builder: (_) => AlertDialog(
                                          title: const Text('Xóa hóa đơn'),
                                          content: const Text('Bạn có chắc muốn xóa hóa đơn này?'),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context, false), 
                                              child: const Text('Hủy')
                                            ),
                                            FilledButton(
                                              onPressed: () => Navigator.pop(context, true), 
                                              child: const Text('Xóa')
                                            ),
                                          ],
                                        ),
                                      );
                                      if (ok == true) {
                                        await context.read<SaleProvider>().delete(s.id);
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Đã xóa hóa đơn')),
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Hàm hiển thị màn hình preview và in
  Future<void> _showPrintPreview(BuildContext context, Sale sale, NumberFormat currency) async {
    await showDialog(
      context: context,
      builder: (_) => _ReceiptPreviewDialog(sale: sale, currency: currency),
    );
  }

  Future<void> _exportCsv(BuildContext context, List<Sale> sales) async {
    if (!context.mounted) return;
    
    // Tạo nội dung CSV
    final buffer = StringBuffer();
    buffer.writeln('id,createdAt,customerId,customerName,subtotal,discount,paid,total,debt,items');
    for (final s in sales) {
      final items = s.items.map((e) => '${e.name} x ${e.quantity} @ ${e.unitPrice}').join('; ');
      buffer.writeln('${s.id},${s.createdAt.toIso8601String()},${s.customerId ?? ''},${s.customerName ?? ''},${s.subtotal},${s.discount},${s.paidAmount},${s.total},${s.debt},"${items.replaceAll('"', '""')}"');
    }
    
    // Sử dụng helper để xuất file
    await FileHelper.exportCsv(
      context: context,
      csvContent: buffer.toString(),
      fileName: 'sales_export',
      openAfterExport: false,
    );
  }
}

// -----------------------------------------------------------------------------------
// --- WIDGET XEM TRƯỚC HÓA ĐƠN ĐÃ SỬA LỖI RangeError ---
// -----------------------------------------------------------------------------------

class _ReceiptPreviewDialog extends StatefulWidget {
  final Sale sale;
  final NumberFormat currency;

  const _ReceiptPreviewDialog({required this.sale, required this.currency});

  @override
  State<_ReceiptPreviewDialog> createState() => _ReceiptPreviewDialogState();
}

class _ReceiptPreviewDialogState extends State<_ReceiptPreviewDialog> {
  // Key: Độ rộng giấy (mm), Value: Số lượng ký tự tối đa
  final Map<String, int> _paperSizes = {'80mm': 40, '57mm': 32};
  
  // Mặc định chọn 80mm
  String _selectedSize = '80mm';

  // Hàm tạo nội dung hóa đơn kiểu POS (dạng text đơn giản)
  String _buildReceiptContent(Sale sale, NumberFormat currency, int columnWidth) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');
    final List<String> lines = [];
    
    // Helper function để căn giữa
    String center(String text) => text.padLeft((columnWidth - text.length) ~/ 2 + text.length);

    // Helper function để căn 2 bên (Trái + Phải = columnWidth)
    String justify(String left, String right) {
      final totalLen = left.length + right.length;
      
      // Nếu tổng độ dài vượt quá, chúng ta phải cắt chuỗi bên trái.
      if (totalLen > columnWidth) {
        // Độ dài còn lại cho phần bên trái (bao gồm 3 chấm '...')
        final maxLeftLength = columnWidth - right.length; 
        
        if (maxLeftLength < 4) { // 4 ký tự cần thiết cho "..." + ít nhất 1 ký tự nội dung
          // Trường hợp quá chật, chỉ còn cách hiển thị chuỗi trái và xuống dòng cho chuỗi phải
          // (Mặc dù lý tưởng không phải là POS, nhưng tránh RangeError)
          return '$left\n${''.padLeft(columnWidth - right.length) + right}';
        }

        // Độ dài cần cắt (đã trừ đi 3 chấm)
        final trimLength = maxLeftLength - 3; 

        // SỬA LỖI RangeError: Đảm bảo trimLength không âm
        if (trimLength <= 0 || left.length <= trimLength) {
             // Chỉ lấy tối đa 1 ký tự, hoặc nếu left quá ngắn, hiển thị left và right
             return left.padRight(columnWidth - right.length) + right;
        }

        // Cắt chuỗi và thêm dấu '...'
        final trimmedLeft = left.substring(0, trimLength) + '...';
        return trimmedLeft.padRight(columnWidth - right.length) + right;
      }
      // Trường hợp bình thường, căn chỉnh
      return left.padRight(columnWidth - right.length) + right;
    }

    // Header
    lines.add('=' * columnWidth);
    lines.add(center('CỬA HÀNG ABC'));
    lines.add(center('Địa chỉ: 123 Đường XYZ'));
    lines.add(center('Hotline: 090xxxxxxx'));
    lines.add('=' * columnWidth);
    lines.add(center('HÓA ĐƠN BÁN HÀNG'));
    lines.add(justify('Mã HD:', sale.id)); 
    lines.add(justify('Ngày:', dateFormat.format(sale.createdAt)));
    lines.add('Khách hàng: ${sale.customerName?.trim().isNotEmpty == true ? sale.customerName!.trim() : 'Khách lẻ'}');
    lines.add('-' * columnWidth);

    // Items Header
    final headerLeft = 'Mặt hàng';
    final headerRight = 'SL'.padLeft(4) + 'TT'.padLeft(6); // 4 + 6 = 10 ký tự
    lines.add(justify(headerLeft, headerRight));
    lines.add('-' * columnWidth);
    
    // Items
    for (final item in sale.items) {
      // Dòng 1: Tên sản phẩm
      lines.add(item.name); 

      // Dòng 2: Đơn giá x Số lượng = Thành tiền
      final itemTotal = currency.format(item.unitPrice * item.quantity);
      final itemQuantity = item.quantity % 1 == 0 ? item.quantity.toInt().toString() : item.quantity.toString();
      
      final leftPart = currency.format(item.unitPrice); // Giá đơn vị
      final rightPart = 'x $itemQuantity ${item.unit} = $itemTotal'; // Số lượng + Thành tiền

      // Căn chỉnh: Đơn giá (leftPart) nằm ở đầu, (Số lượng + Thành tiền) (rightPart) nằm ở cuối
      lines.add(justify(leftPart, rightPart));
    }

    // Totals
    lines.add('-' * columnWidth);
    
    // Tổng số lượng
    final totalQuantity = sale.items.fold<double>(0.0, (sum, item) => sum + item.quantity);
    lines.add('Tổng SL: ${totalQuantity % 1 == 0 ? totalQuantity.toInt() : totalQuantity}');

    // Các dòng tổng tiền
    lines.add(justify('Tạm tính:', currency.format(sale.subtotal)));
    if (sale.discount > 0) { 
      lines.add(justify('Giảm giá:', '-${currency.format(sale.discount)}'));
    }
    lines.add(justify('TỔNG CỘNG:', currency.format(sale.total)));
    lines.add(justify('Đã thanh toán:', currency.format(sale.paidAmount)));
    if (sale.debt > 0) {
      lines.add(justify('CÒN NỢ:', currency.format(sale.debt)));
    }
    
    lines.add('=' * columnWidth);
    lines.add(center('Cảm ơn quý khách và hẹn gặp lại!'));
    lines.add('=' * columnWidth);
    lines.add('');
    lines.add('');
    lines.add('');

    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final columnWidth = _paperSizes[_selectedSize]!;
    final receiptContent = _buildReceiptContent(widget.sale, widget.currency, columnWidth);
    
    // Giả lập chiều rộng màn hình dựa trên số ký tự cho hiển thị preview
    double maxWidth;
    if (_selectedSize == '80mm') {
      maxWidth = 300;
    } else {
      maxWidth = 240; // Giả lập hẹp hơn cho 57mm
    }

    return AlertDialog(
      // SỬA LỖI OVERFLOW: Dùng Column để buộc Dropdown xuống dòng
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Xem trước Hóa đơn POS'),
          const SizedBox(height: 8),
          DropdownButton<String>(
            value: _selectedSize,
            isDense: true, // Giúp gọn gàng hơn
            underline: const SizedBox.shrink(), // Bỏ gạch chân mặc định
            items: _paperSizes.keys.map((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text('Khổ giấy: $value'),
              );
            }).toList(),
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() {
                  _selectedSize = newValue;
                });
              }
            },
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Container(
          // Chiều rộng tối đa cho màn hình preview
          constraints: BoxConstraints(maxWidth: maxWidth), 
          padding: const EdgeInsets.all(8.0),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black),
            color: Colors.white,
          ),
          child: Text(
            receiptContent,
            style: const TextStyle(
              fontFamily: 'monospace', // Bắt buộc dùng font cố định để căn lề
              fontSize: 12,
              height: 1.2,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context), 
          child: const Text('Đóng')
        ),
        FilledButton.icon(
          icon: const Icon(Icons.print),
          label: Text('In (${_selectedSize})'),
          onPressed: () {
            // TODO: Thay thế bằng logic gọi API/Bluetooth/USB để in thực tế trên máy in POS
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Đang giả lập in hóa đơn ${_selectedSize} (Cần tích hợp thư viện in POS)')),
            );
          },
        ),
      ],
    );
  }
}