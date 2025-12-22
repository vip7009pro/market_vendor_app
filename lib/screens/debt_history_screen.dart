import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import '../providers/debt_provider.dart';
import '../models/debt.dart';
import '../services/database_service.dart';
import '../utils/file_helper.dart';

class DebtHistoryScreen extends StatefulWidget {
  const DebtHistoryScreen({super.key});

  @override
  State<DebtHistoryScreen> createState() => _DebtHistoryScreenState();
}

// Vietnamese diacritics removal (accent-insensitive search)
String _vn(String input) {
  const source = 'àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđÀÁẢÃẠĂẰẮẲẴẶÂẦẤẨẪẬÈÉẺẼẸÊỀẾỂỄỆÌÍỈĨỊÒÓỎÕỌÔỒỐỔỖỘƠỜỚỞỠỢÙÚỦŨỤƯỪỨỬỮỰỲÝỶỸỴĐ';
  const target = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyydAAAAAAAAAAAAAAAAAEEEEEEEEEEEIIIIIooooooooooooooooOUUUUUUUUUUYYYYYD';
  final map = <String, String>{};
  for (var i = 0; i < source.length; i++) {
    map[source[i]] = target[i];
  }
  final sb = StringBuffer();
  for (final ch in input.split('')) {
    sb.write(map[ch] ?? ch);
  }
  return sb.toString();
}

class _DebtHistoryScreenState extends State<DebtHistoryScreen> {
  DebtType? _filterType; // null = all
  bool _onlyUnsettled = true;
  DateTimeRange? _range;
  String _query = '';

  Widget _buildAssignmentChip(Debt d) {
    final isAssigned = (d.sourceId ?? '').trim().isNotEmpty;
    final bg = isAssigned ? Colors.green.withOpacity(0.12) : Colors.orange.withOpacity(0.12);
    final fg = isAssigned ? Colors.green.shade800 : Colors.orange.shade800;
    final icon = isAssigned ? Icons.link : Icons.link_off;
    final label = isAssigned ? 'Đã gán' : 'Chưa gán';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DebtProvider>();
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    var debts = provider.debts;

    if (_filterType != null) {
      debts = debts.where((d) => d.type == _filterType).toList();
    }
    if (_onlyUnsettled) {
      debts = debts.where((d) => !d.settled).toList();
    }
    if (_range != null) {
      final start = DateTime(_range!.start.year, _range!.start.month, _range!.start.day);
      final end = DateTime(_range!.end.year, _range!.end.month, _range!.end.day, 23, 59, 59, 999);
      debts = debts.where((d) => d.createdAt.isAfter(start.subtract(const Duration(milliseconds: 1))) && d.createdAt.isBefore(end.add(const Duration(milliseconds: 1)))).toList();
    }
    if (_query.isNotEmpty) {
      final q = _vn(_query).toLowerCase();
      debts = debts.where((d) => _vn(d.partyName).toLowerCase().contains(q) || _vn(d.description ?? '').toLowerCase().contains(q)).toList();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử công nợ'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (val) {
              setState(() {
                if (val == 'all') _filterType = null;
                if (val == 'othersOweMe') _filterType = DebtType.othersOweMe;
                if (val == 'oweOthers') _filterType = DebtType.oweOthers;
              });
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'all', child: Text('Tất cả')),
              PopupMenuItem(value: 'othersOweMe', child: Text('Tiền nợ tôi')),
              PopupMenuItem(value: 'oweOthers', child: Text('Tiền tôi nợ')),
            ],
          ),
          IconButton(
            tooltip: 'Xuất CSV',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: () => _exportCsv(context, debts),
          ),
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
                    decoration: const InputDecoration(hintText: 'Tìm theo tên/ghi chú', isDense: true, prefixIcon: Icon(Icons.search)),
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.date_range),
                  label: Text(_range == null ? 'Khoảng ngày' : '${DateFormat('dd/MM').format(_range!.start)} - ${DateFormat('dd/MM').format(_range!.end)}'),
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(now.year - 5),
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
                  )
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('Chỉ hiển thị chưa thanh toán'),
            value: _onlyUnsettled,
            onChanged: (v) => setState(() => _onlyUnsettled = v),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: debts.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final d = debts[i];
                final isOwedToMe = d.type == DebtType.othersOweMe;
                final amountColor = isOwedToMe ? Colors.green : Colors.orange;
                final iconColor = isOwedToMe ? Colors.green : Colors.orange;
                final statusColor = d.settled ? Colors.green : Colors.blueGrey;
                final isAssigned = (d.sourceId ?? '').trim().isNotEmpty;
                
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade200, width: 1),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        // Header row with party name and amount
                        Row(
                          children: [
                            // Icon with background
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: iconColor.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isOwedToMe ? Icons.call_received : Icons.call_made,
                                size: 20,
                                color: iconColor,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Party name and date
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    d.partyName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(
                                        DateFormat('dd/MM/yyyy').format(d.createdAt),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _buildAssignmentChip(d),
                                      if (isAssigned && (d.sourceType ?? '').trim().isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Text(
                                          d.sourceType == 'sale' ? 'Bán hàng' : (d.sourceType == 'purchase' ? 'Nhập hàng' : d.sourceType!),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade700,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Amount
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: amountColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                currency.format(d.amount),
                                style: TextStyle(
                                  color: amountColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                        
                        // Description and payment info
                        if ((d.description ?? '').isNotEmpty || !d.settled) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              // Description
                              if ((d.description ?? '').isNotEmpty) ...[
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      d.description!,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade800,
                                        fontStyle: FontStyle.italic,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              
                              // Payment status
                              if (!d.settled)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: FutureBuilder<double>(
                                    future: DatabaseService.instance.getTotalPaidForDebt(d.id),
                                    builder: (context, snap) {
                                      if (snap.connectionState != ConnectionState.done) {
                                        return const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        );
                                      }
                                      final paid = snap.data ?? 0;
                                      final initial = paid + d.amount;
                                      final paidPercentage = (paid / initial * 100).toInt();
                                      
                                      return Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'Đã trả $paidPercentage%',
                                            style: TextStyle(
                                              color: statusColor,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            paidPercentage >= 100 ? Icons.check_circle : Icons.pending_actions,
                                            size: 16,
                                            color: paidPercentage >= 100 ? Colors.green : statusColor,
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ],
                        
                        // Status badge
                        if (d.settled) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle, size: 16, color: Colors.green),
                                const SizedBox(width: 6),
                                Text(
                                  'Đã thanh toán đủ',
                                  style: TextStyle(
                                    color: Colors.green.shade800,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
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

  Future<void> _exportCsv(BuildContext context, List<Debt> debts) async {
    if (!context.mounted) return;
    
    // Tạo nội dung CSV
    final buffer = StringBuffer();
    buffer.writeln('id,type,partyId,partyName,amount,settled,createdAt,description');
    for (final d in debts) {
      final typeStr = d.type == DebtType.othersOweMe ? 'othersOweMe' : 'oweOthers';
      final desc = (d.description ?? '').replaceAll('\n', ' ').replaceAll(',', ' ');
      buffer.writeln('${d.id},$typeStr,${d.partyId},${d.partyName},${d.amount},${d.settled},${d.createdAt.toIso8601String()},$desc');
    }
    
    // Sử dụng helper để xuất file
    await FileHelper.exportCsv(
      context: context,
      csvContent: buffer.toString(),
      fileName: 'debt_export',
      openAfterExport: false,
    );
  }
}
