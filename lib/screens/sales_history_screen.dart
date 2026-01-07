import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/debt_provider.dart';
import '../providers/sale_provider.dart';
import '../models/sale.dart';
import '../models/debt.dart';
import '../services/database_service.dart';
import '../utils/file_helper.dart';
// Import file mới
import 'receipt_preview_screen.dart'; // Thêm dòng này
import 'sales_item_history_screen.dart';
import 'sale_edit_screen.dart';
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
enum _DebtIssueKind { ok, missing, mismatch }
class _DebtIssueInfo {
  final String saleId;
  final _DebtIssueKind kind;
  final Debt? debt;
  final double paid;
  final double remain;
  final double initial;
  const _DebtIssueInfo._({
    required this.saleId,
    required this.kind,
    this.debt,
    this.paid = 0,
    this.remain = 0,
    this.initial = 0,
  });
  factory _DebtIssueInfo.ok({
    required String saleId,
    required double paid,
    required double remain,
    required double initial,
  }) {
    return _DebtIssueInfo._(
      saleId: saleId,
      kind: _DebtIssueKind.ok,
      paid: paid,
      remain: remain,
      initial: initial,
    );
  }
  factory _DebtIssueInfo.missing({required String saleId}) {
    return _DebtIssueInfo._(
      saleId: saleId,
      kind: _DebtIssueKind.missing,
    );
  }
  factory _DebtIssueInfo.mismatch({
    required String saleId,
    required Debt debt,
    required double paid,
    required double remain,
    required double initial,
  }) {
    return _DebtIssueInfo._(
      saleId: saleId,
      kind: _DebtIssueKind.mismatch,
      debt: debt,
      paid: paid,
      remain: remain,
      initial: initial,
    );
  }
}
class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  DateTimeRange? _range;
  String _query = '';
  bool _onlyDebtIssues = false;
  bool _isTableView = false;

  bool _didBackfillUnitCost = false;
  final Map<String, _DebtIssueInfo> _debtIssueBySaleId = {};
  String _lastIssueKey = '';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_didBackfillUnitCost) return;
      _didBackfillUnitCost = true;
      try {
        await DatabaseService.instance.backfillSaleItemsUnitCostFromProducts();
      } catch (_) {
        // ignore
      }
    });
  }
  Future<void> _refreshDebtIssuesFor(List<Sale> sales) async {
    // Only compute for sales that currently have debt
    final withDebt = sales.where((s) => s.debt > 0).toList();
    if (withDebt.isEmpty) {
      if (!mounted) return;
      setState(() {
        _debtIssueBySaleId
          ..clear();
        _lastIssueKey = '';
      });
      return;
    }
    // Deduplicate by id
    final saleIds = withDebt.map((e) => e.id).toSet().toList();
    saleIds.sort();
    final key = saleIds.join(',');
    if (key == _lastIssueKey) return;
    final db = DatabaseService.instance.db;
    final placeholders = List.filled(saleIds.length, '?').join(',');
    final debtRows = await db.query(
      'debts',
      columns: ['id', 'sourceId', 'amount', 'settled', 'type', 'partyId', 'partyName', 'description', 'createdAt', 'dueDate', 'sourceType'],
      where: "sourceType = 'sale' AND sourceId IN ($placeholders)",
      whereArgs: saleIds,
    );
    final debtBySaleId = <String, Map<String, dynamic>>{};
    final debtIds = <String>[];
    for (final r in debtRows) {
      final sid = (r['sourceId']?.toString() ?? '').trim();
      final did = (r['id']?.toString() ?? '').trim();
      if (sid.isEmpty || did.isEmpty) continue;
      debtBySaleId[sid] = r;
      debtIds.add(did);
    }
    final paidByDebtId = <String, double>{};
    if (debtIds.isNotEmpty) {
      final dph = List.filled(debtIds.length, '?').join(',');
      final payAgg = await db.rawQuery(
        '''
        SELECT debtId as debtId, SUM(amount) as total
        FROM debt_payments
        WHERE debtId IN ($dph)
        GROUP BY debtId
        ''',
        debtIds,
      );
      for (final r in payAgg) {
        final did = (r['debtId']?.toString() ?? '').trim();
        if (did.isEmpty) continue;
        paidByDebtId[did] = (r['total'] as num?)?.toDouble() ?? 0.0;
      }
    }
    final next = <String, _DebtIssueInfo>{};
    for (final s in withDebt) {
      final debtRow = debtBySaleId[s.id];
      if (debtRow == null) {
        next[s.id] = _DebtIssueInfo.missing(saleId: s.id);
        continue;
      }
      final did = (debtRow['id']?.toString() ?? '').trim();
      final remain = (debtRow['amount'] as num?)?.toDouble() ?? 0.0;
      final paid = paidByDebtId[did] ?? 0.0;
      final initial = (remain + paid).clamp(0.0, double.infinity).toDouble();
      final mismatch = (initial - s.debt).abs() > 0.5;
      if (mismatch) {
        // Rebuild Debt object for actions
        final createdAtRaw = debtRow['createdAt']?.toString();
        final dueDateRaw = debtRow['dueDate']?.toString();
        final typeInt = (debtRow['type'] as int?) ?? 1;
        final settled = ((debtRow['settled'] as int?) ?? 0) == 1;
        final debt = Debt(
          id: did,
          createdAt: createdAtRaw != null ? DateTime.parse(createdAtRaw) : DateTime.now(),
          type: typeInt == 0 ? DebtType.oweOthers : DebtType.othersOweMe,
          partyId: (debtRow['partyId']?.toString() ?? '').trim(),
          partyName: (debtRow['partyName']?.toString() ?? '').trim(),
          amount: remain,
          description: debtRow['description']?.toString(),
          dueDate: (dueDateRaw != null && dueDateRaw.trim().isNotEmpty) ? DateTime.tryParse(dueDateRaw) : null,
          settled: settled,
          sourceType: debtRow['sourceType']?.toString(),
          sourceId: debtRow['sourceId']?.toString(),
        );
        next[s.id] = _DebtIssueInfo.mismatch(
          saleId: s.id,
          debt: debt,
          paid: paid,
          remain: remain,
          initial: initial,
        );
      } else {
        next[s.id] = _DebtIssueInfo.ok(
          saleId: s.id,
          paid: paid,
          remain: remain,
          initial: initial,
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _debtIssueBySaleId
        ..clear()
        ..addAll(next);
      _lastIssueKey = key;
    });
  }
  _DebtIssueInfo? _getIssue(String saleId) => _debtIssueBySaleId[saleId];
  Future<void> _createDebtForSale(Sale s) async {
    final partyName = (s.customerName?.trim().isNotEmpty == true) ? s.customerName!.trim() : 'Khách lẻ';
    final newDebt = Debt(
      createdAt: s.createdAt,
      type: DebtType.othersOweMe,
      partyId: (s.customerId?.trim().isNotEmpty == true) ? s.customerId!.trim() : 'customer_unknown',
      partyName: partyName,
      amount: s.debt,
      description: 'Bán hàng: $partyName, Tổng ${s.total.toStringAsFixed(0)}, Đã trả ${s.paidAmount.toStringAsFixed(0)}',
      sourceType: 'sale',
      sourceId: s.id,
    );
    await context.read<DebtProvider>().add(newDebt);
    await context.read<DebtProvider>().load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã tạo ghi nợ cho hóa đơn')));
  }
  Future<void> _syncInitialDebtForSale({required Sale s, required Debt debt, required double alreadyPaid}) async {
    final newRemain = (s.debt - alreadyPaid).clamp(0.0, double.infinity).toDouble();
    final updated = Debt(
      id: debt.id,
      createdAt: debt.createdAt,
      type: debt.type,
      partyId: debt.partyId,
      partyName: debt.partyName,
      amount: newRemain,
      description: debt.description,
      dueDate: debt.dueDate,
      settled: newRemain <= 0,
      sourceType: debt.sourceType,
      sourceId: debt.sourceId,
    );
    await DatabaseService.instance.updateDebt(updated);
    await context.read<DebtProvider>().load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã đồng bộ nợ ban đầu theo hóa đơn')));
  }
  IconData _paymentTypeIcon(String? t) {
    final v = (t ?? '').trim().toLowerCase();
    if (v == 'cash') return Icons.payments_outlined;
    if (v == 'bank') return Icons.account_balance_outlined;
    return Icons.help_outline;
  }
  Color? _paymentTypeColor(BuildContext context, String? t) {
    final v = (t ?? '').trim().toLowerCase();
    if (v == 'cash') return Colors.green;
    if (v == 'bank') return Colors.blue;
    return Theme.of(context).colorScheme.onSurface.withOpacity(0.55);
  }
  String _paymentTypeLabel(String? t) {
    final v = (t ?? '').trim().toLowerCase();
    if (v == 'cash') return 'Tiền mặt';
    if (v == 'bank') return 'Chuyển khoản';
    return 'Chưa phân loại';
  }
  String _vietQrUrl({
    required String bankId,
    required String accountNo,
    required String accountName,
    required int amount,
    required String description,
    String template = 'compact2',
  }) {
    final addInfo = Uri.encodeComponent(description);
    final accName = Uri.encodeComponent(accountName);
    return 'https://img.vietqr.io/image/$bankId-$accountNo-$template.png?amount=$amount&addInfo=$addInfo&accountName=$accName';
  }
  String _sanitizeVietQrAddInfo(String s) {
    var out = _vn(s);
    out = out.replaceAll(RegExp(r'[^a-zA-Z0-9\s=xX\-]'), ' ');
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    return out;
  }
  String _last5DigitsOfId(String id) {
    final digits = id.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 5) return digits.substring(digits.length - 5);
    final raw = id.trim();
    if (raw.length >= 5) return raw.substring(raw.length - 5);
    return raw;
  }
  String _buildVietQrAddInfoFromSale({required String saleId, required Sale sale}) {
    final parts = <String>[];
    for (final it in sale.items) {
      final name = (it.name).trim();
      if (name.isEmpty) continue;
      final qty = it.quantity;
      final total = it.total;
      parts.add('${name} x${qty.toStringAsFixed(qty % 1 == 0 ? 0 : 2)}=${total.toInt()}');
    }
    final tail = _last5DigitsOfId(saleId);
    final raw = '${tail.isEmpty ? '' : '$tail '}Noi dung: ${parts.join('; ')}';
    final safe = _sanitizeVietQrAddInfo(raw);
    if (safe.length <= 50) return safe;
    return '${safe.substring(0, 47)}...';
  }
  Future<void> _showVietQrDebtDialog(Sale s) async {
    if (s.debt <= 0) return;
    final db = DatabaseService.instance.db;
    final debtRows = await db.query(
      'debts',
      columns: ['id', 'amount'],
      where: "sourceType = 'sale' AND sourceId = ?",
      whereArgs: [s.id],
      orderBy: 'createdAt DESC',
      limit: 1,
    );
    if (!mounted) return;
    if (debtRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không tìm thấy ghi nợ của hóa đơn')));
      return;
    }
    final remain = (debtRows.first['amount'] as num?)?.toDouble() ?? 0.0;
    if (remain <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Khoản nợ đã tất toán')));
      return;
    }
    final bank = await DatabaseService.instance.getDefaultVietQrBankAccount();
    if (!mounted) return;
    if (bank == null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Chưa cấu hình ngân hàng'),
          content: const Text(
            'Bạn chưa cấu hình ngân hàng VietQR mặc định.\n\nVào Cài đặt > Ngân hàng VietQR để thêm và chọn mặc định.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
          ],
        ),
      );
      return;
    }
    final bin = (bank['bin']?.toString() ?? '').trim();
    final code = (bank['code']?.toString() ?? '').trim();
    final bankId = bin.isNotEmpty ? bin : code;
    final accountNo = (bank['accountNo']?.toString() ?? '').trim();
    final accountName = (bank['accountName']?.toString() ?? '').trim();
    final logo = (bank['logo']?.toString() ?? '').trim();
    if (bankId.isEmpty || accountNo.isEmpty || accountName.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Thiếu thông tin ngân hàng'),
          content: const Text('Thông tin ngân hàng VietQR mặc định chưa đầy đủ. Vui lòng kiểm tra lại.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
          ],
        ),
      );
      return;
    }
    final amount = remain.round();
    final desc = _buildVietQrAddInfoFromSale(saleId: s.id, sale: s);
    final url = _vietQrUrl(
      bankId: bankId,
      accountNo: accountNo,
      accountName: accountName,
      amount: amount,
      description: desc,
    );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Center(child: Text('QR thanh toán nợ')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (logo.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Image.network(
                  logo,
                  width: 46,
                  height: 46,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            Text('Số tiền: ${NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0).format(amount)}'),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                url,
                width: 320,
                height: 320,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(6),
                  child: Text('Không tải được QR. Vui lòng kiểm tra mạng.'),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(desc, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
        ],
      ),
    );
  }
  Future<void> _setSalePaymentType({required Sale sale}) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text('Tiền mặt'),
                onTap: () => Navigator.pop(ctx, 'cash'),
              ),
              ListTile(
                leading: const Icon(Icons.account_balance_outlined),
                title: const Text('Chuyển khoản'),
                onTap: () => Navigator.pop(ctx, 'bank'),
              ),
              ListTile(
                leading: const Icon(Icons.clear),
                title: const Text('Bỏ phân loại'),
                onTap: () => Navigator.pop(ctx, ''),
              ),
            ],
          ),
        );
      },
    );
    if (picked == null) return;
    await DatabaseService.instance.updateSalePaymentType(
      saleId: sale.id,
      paymentType: picked.trim().isEmpty ? null : picked.trim(),
    );
    if (!mounted) return;
    await context.read<SaleProvider>().load();
    if (!mounted) return;
    setState(() {});
  }
  Future<Map<String, String>?> _pickEmployee({bool allowClear = false}) async {
    final rows = await DatabaseService.instance.getEmployees();
    if (!mounted) return null;
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa có nhân viên nào')),
      );
      return null;
    }

    final picked = await showModalBottomSheet<Map<String, String>>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (allowClear)
                ListTile(
                  leading: const Icon(Icons.clear),
                  title: const Text('Bỏ gán nhân viên'),
                  onTap: () => Navigator.pop(ctx, <String, String>{}),
                ),
              ...rows.map((r) {
                final id = (r['id']?.toString() ?? '').trim();
                final name = (r['name']?.toString() ?? '').trim();
                final label = name.isNotEmpty ? name : id;
                return ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: Text(label),
                  subtitle: Text(id),
                  onTap: () => Navigator.pop(ctx, <String, String>{'id': id, 'name': name}),
                );
              }),
            ],
          ),
        );
      },
    );
    if (picked == null) return null;
    return picked;
  }

  Future<void> _assignEmployeeForSale(Sale s) async {
    final picked = await _pickEmployee(allowClear: true);
    if (picked == null) return;

    final employeeId = (picked['id'] ?? '').trim();
    final employeeName = (picked['name'] ?? '').trim();

    final db = DatabaseService.instance.db;
    await db.rawUpdate(
      'UPDATE sales SET employeeId = ?, employeeName = ? WHERE id = ?',
      [employeeId.isEmpty ? null : employeeId, employeeName.isEmpty ? null : employeeName, s.id],
    );
    if (!mounted) return;
    await context.read<SaleProvider>().load();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã cập nhật nhân viên cho hóa đơn')),
    );
  }

  Future<void> _bulkAssignEmployeeForMissingSales() async {
    final picked = await _pickEmployee(allowClear: false);
    if (picked == null) return;
    final employeeId = (picked['id'] ?? '').trim();
    final employeeName = (picked['name'] ?? '').trim();
    if (employeeId.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Gán nhân viên hàng loạt'),
        content: const Text('Gán nhân viên cho các giao dịch chưa có nhân viên?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Gán'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final db = DatabaseService.instance.db;
    await db.rawUpdate(
      "UPDATE sales SET employeeId = ?, employeeName = ? WHERE employeeId IS NULL OR TRIM(employeeId) = ''",
      [employeeId, employeeName.isEmpty ? null : employeeName],
    );
    if (!mounted) return;
    await context.read<SaleProvider>().load();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã gán nhân viên cho các giao dịch chưa có nhân viên')),
    );
  }

  Future<void> _showSaleActionSheet(Sale s) async {
    final issue = _getIssue(s.id);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (issue != null && issue.kind == _DebtIssueKind.missing)
                ListTile(
                  leading: const Icon(Icons.add_card_outlined),
                  title: const Text('Tạo nợ'),
                  subtitle: const Text('Tạo ghi nợ cho hóa đơn này'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _createDebtForSale(s);
                    if (!mounted) return;
                    await context.read<SaleProvider>().load();
                    if (!mounted) return;
                    setState(() {
                      _lastIssueKey = '';
                    });
                  },
                ),
              if (issue != null && issue.kind == _DebtIssueKind.mismatch)
                ListTile(
                  leading: const Icon(Icons.sync_outlined),
                  title: const Text('Đồng bộ tiền nợ ban đầu'),
                  subtitle: const Text('Sửa số nợ để khớp theo hóa đơn'),
                  onTap: () async {
                    final debt = issue.debt;
                    if (debt == null) return;
                    Navigator.pop(ctx);
                    await _syncInitialDebtForSale(
                      s: s,
                      debt: debt,
                      alreadyPaid: issue.paid,
                    );
                    if (!mounted) return;
                    await context.read<SaleProvider>().load();
                    if (!mounted) return;
                    setState(() {
                      _lastIssueKey = '';
                    });
                  },
                ),
              ListTile(
                leading: const Icon(Icons.tune),
                title: const Text('Set kiểu thanh toán'),
                subtitle: Text(
                  s.paidAmount > 0 ? _paymentTypeLabel(s.paymentType) : 'Chỉ áp dụng khi có số tiền đã trả > 0',
                ),
                onTap: s.paidAmount > 0
                    ? () async {
                        Navigator.pop(ctx);
                        await _setSalePaymentType(sale: s);
                      }
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Gán nhân viên'),
                subtitle: Text(
                  ((s.employeeName ?? '').trim().isNotEmpty || (s.employeeId ?? '').trim().isNotEmpty)
                      ? 'Hiện tại: ${((s.employeeName ?? '').trim().isNotEmpty) ? (s.employeeName ?? '').trim() : (s.employeeId ?? '').trim()}'
                      : 'Chưa gán nhân viên',
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _assignEmployeeForSale(s);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _tableHeaderCell(String text, {double? width, TextAlign align = TextAlign.left}) {
    return Container(
      alignment: align == TextAlign.right
          ? Alignment.centerRight
          : align == TextAlign.center
              ? Alignment.center
              : Alignment.centerLeft,
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
  Widget _tableCell(Widget child, {double? width, Alignment alignment = Alignment.centerLeft}) {
    return Container(
      alignment: alignment,
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: child,
    );
  }
  Widget _buildSalesTable({
    required List<Sale> rows,
    required DateFormat fmtDate,
    required NumberFormat currency,
  }) {
    if (rows.isEmpty) {
      return const Center(child: Text('Chưa có dữ liệu'));
    }
    const wDate = 150.0;
    const wCustomer = 200.0;
    const wEmployee = 160.0;
    const wTotal = 120.0;
    const wDiscount = 100.0;
    const wPaid = 120.0;
    const wDebt = 120.0;
    const wPayType = 130.0;
    const wIssue = 140.0;
    const wItems = 420.0;
    const wActions = 170.0;
    const tableWidth = wDate + wCustomer + wEmployee + wTotal + wDiscount + wPaid + wDebt + wPayType + wIssue + wItems + wActions;

    String issueText(Sale s) {
      if (s.debt <= 0) return 'Đã thanh toán';
      final issue = _getIssue(s.id);
      if (issue == null) return 'Còn nợ';
      if (issue.kind == _DebtIssueKind.missing) return 'Thiếu ghi nợ';
      if (issue.kind == _DebtIssueKind.mismatch) return 'Lệch nợ';
      return 'Còn nợ';
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            height: constraints.maxHeight,
            child: Column(
              children: [
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  elevation: 1,
                  child: Row(
                    children: [
                      _tableHeaderCell('Ngày', width: wDate),
                      _tableHeaderCell('Khách', width: wCustomer),
                      _tableHeaderCell('Nhân viên', width: wEmployee),
                      _tableHeaderCell('Tổng', width: wTotal, align: TextAlign.right),
                      _tableHeaderCell('Giảm', width: wDiscount, align: TextAlign.right),
                      _tableHeaderCell('Đã trả', width: wPaid, align: TextAlign.right),
                      _tableHeaderCell('Còn nợ', width: wDebt, align: TextAlign.right),
                      _tableHeaderCell('Thanh toán', width: wPayType),

                      _tableHeaderCell('Trạng thái', width: wIssue),
                      _tableHeaderCell('Mặt hàng', width: wItems),
                      _tableHeaderCell('Thao tác', width: wActions, align: TextAlign.center),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final s = rows[i];
                      final customerName = (s.customerName ?? '').trim();
                      final customer = customerName.isEmpty ? 'Khách lẻ' : customerName;
                      final employeeName = (s.employeeName ?? '').trim();
                      final employeeId = (s.employeeId ?? '').trim();
                      final employeeLabel = employeeName.isNotEmpty ? employeeName : (employeeId.isNotEmpty ? employeeId : '');
                      final items = s.items
                          .map((item) =>
                              '${(((item.itemType ?? '').toUpperCase().trim()) == 'MIX' && (item.displayName?.trim().isNotEmpty == true)) ? item.displayName!.trim() : item.name} x ${item.quantity} ${item.unit}')
                          .join(', ');

                      return InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => _SaleDetailScreen(sale: s),
                            ),
                          );
                        },
                        onLongPress: () async {
                          await _showSaleActionSheet(s);
                        },
                        child: Row(
                          children: [
                            _tableCell(Text(fmtDate.format(s.createdAt)), width: wDate),
                            _tableCell(
                              Text(customer, maxLines: 2, overflow: TextOverflow.ellipsis),
                              width: wCustomer,
                            ),
                            _tableCell(
                              Text(employeeLabel, maxLines: 2, overflow: TextOverflow.ellipsis),
                              width: wEmployee,
                            ),
                            _tableCell(
                              Text(currency.format(s.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                              width: wTotal,
                              alignment: Alignment.centerRight,
                            ),

                            _tableCell(
                              Text(currency.format(s.discount)),
                              width: wDiscount,
                              alignment: Alignment.centerRight,
                            ),
                            _tableCell(
                              Text(currency.format(s.paidAmount)),
                              width: wPaid,
                              alignment: Alignment.centerRight,
                            ),
                            _tableCell(
                              Text(currency.format(s.debt)),
                              width: wDebt,
                              alignment: Alignment.centerRight,
                            ),
                            _tableCell(
                              Text(s.paidAmount > 0 ? _paymentTypeLabel(s.paymentType) : ''),
                              width: wPayType,
                            ),

                            _tableCell(Text(issueText(s)), width: wIssue),
                            _tableCell(
                              Text(items, maxLines: 2, overflow: TextOverflow.ellipsis),
                              width: wItems,
                            ),
                            _tableCell(
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (s.debt > 0)
                                    IconButton(
                                      tooltip: 'QR nợ',
                                      icon: const Icon(Icons.qr_code_2_outlined),
                                      onPressed: () async {
                                        await _showVietQrDebtDialog(s);
                                      },
                                    ),
                                  IconButton(
                                    tooltip: 'In hóa đơn',
                                    icon: const Icon(Icons.print_outlined),
                                    onPressed: () => _showPrintPreview(context, s, currency),
                                  ),
                                  IconButton(
                                    tooltip: 'Sửa hóa đơn',
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () async {
                                      final ok = await Navigator.push<bool>(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => SaleEditScreen(sale: s),
                                        ),
                                      );
                                      if (ok == true) {
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Đã cập nhật bán hàng')),
                                        );
                                      }
                                    },
                                  ),
                                  IconButton(
                                    tooltip: 'Xóa hóa đơn',
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                    onPressed: () async {
                                      final ok = await showDialog<bool>(
                                        context: context,
                                        builder: (_) => AlertDialog(
                                          title: const Text('Xóa hóa đơn'),
                                          content: const Text('Bạn có chắc muốn xóa hóa đơn này?'),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(context, false),
                                              child: const Text('Hủy'),
                                            ),
                                            FilledButton(
                                              onPressed: () => Navigator.pop(context, true),
                                              child: const Text('Xóa'),
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
                              width: wActions,
                              alignment: Alignment.center,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  @override
  Widget build(BuildContext context) {
    final sales = context.watch<SaleProvider>().sales;
    final fmtDate = DateFormat('dd/MM/yyyy HH:mm');
    final currency =
        NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    var filtered = sales;
    if (_range != null) {
      final start =
          DateTime(_range!.start.year, _range!.start.month, _range!.start.day);
      final end = DateTime(
          _range!.end.year, _range!.end.month, _range!.end.day, 23, 59, 59, 999);
      filtered = filtered
          .where((s) =>
              s.createdAt.isAfter(start.subtract(const Duration(milliseconds: 1))) &&
              s.createdAt.isBefore(end.add(const Duration(milliseconds: 1))))
          .toList();
    }
    if (_query.isNotEmpty) {
      final q = _vn(_query).toLowerCase();
      filtered = filtered.where((s) {
        final rawCustomer = s.customerName?.trim();
        final customer = _vn((rawCustomer != null && rawCustomer.isNotEmpty) ? rawCustomer : 'Khách lẻ').toLowerCase();
        final items = _vn(s.items.map((e) => e.name).join(', ')).toLowerCase();
        return customer.contains(q) || items.contains(q);
      }).toList();
    }
    // Tạo bản sao và sắp xếp theo createdAt giảm dần (mới nhất lên đầu)
    final List<Sale> sortedFiltered = List.from(filtered)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshDebtIssuesFor(sortedFiltered);
    });
    final List<Sale> finalList;
    if (_onlyDebtIssues) {
      finalList = sortedFiltered.where((s) {
        if (s.debt <= 0) return false;
        final issue = _getIssue(s.id);
        return issue != null && issue.kind != _DebtIssueKind.ok;
      }).toList();
    } else {
      finalList = sortedFiltered;
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử bán hàng'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu),
            onSelected: (val) async {
              if (val == 'bulk_assign_employee') {
                await _bulkAssignEmployeeForMissingSales();
              } else if (val == 'toggle_view') {
                setState(() => _isTableView = !_isTableView);
              } else if (val == 'sales_items_history') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SalesItemHistoryScreen(),
                  ),
                );
              } else if (val == 'delete_all') {
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
                          if (ok) {
                            messenger.showSnackBar(const SnackBar(content: Text('Đã khôi phục')));
                          }
                        },
                      ),
                    ),
                  );
                }
              } else if (val == 'export_csv') {
                await _exportCsv(context, sortedFiltered);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'bulk_assign_employee',
                child: const Text('Gán nhân viên (thiếu)'),
              ),
              PopupMenuItem(
                value: 'toggle_view',
                child: Text(_isTableView ? 'Xem dạng thẻ' : 'Xem dạng bảng'),
              ),
              const PopupMenuItem(
                value: 'sales_items_history',
                child: Text('Bán hàng chi tiết'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'export_csv', child: Text('Xuất CSV')),
              const PopupMenuItem(value: 'delete_all', child: Text('Xóa tất cả')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Tìm theo khách hàng / mặt hàng',
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                    ),
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text(
                    _range == null
                        ? 'Khoảng ngày'
                        : '${DateFormat('dd/MM').format(_range!.start)} - ${DateFormat('dd/MM').format(_range!.end)}',
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
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
                if (_range != null) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Xoá lọc ngày',
                    icon: const Icon(Icons.clear, size: 18),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    onPressed: () => setState(() => _range = null),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Nợ lỗi'),
                  selected: _onlyDebtIssues,
                  labelStyle: const TextStyle(fontSize: 12),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (v) => setState(() => _onlyDebtIssues = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Divider(height: 1),
          Expanded(
            child: _isTableView
                ? _buildSalesTable(rows: finalList, fmtDate: fmtDate, currency: currency)
                : ListView.separated(
                    itemCount: finalList.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 1),
                    itemBuilder: (context, i) {
                      final s = finalList[i];
                      final customerName = (s.customerName ?? '').trim();
                      final customer = customerName.isEmpty ? 'Khách lẻ' : customerName;
                      final employeeName = (s.employeeName ?? '').trim();
                      final employeeId = (s.employeeId ?? '').trim();
                      final employeeLabel = employeeName.isNotEmpty ? employeeName : (employeeId.isNotEmpty ? employeeId : '');
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                        elevation: 1,
                        child: InkWell(
                          onLongPress: () async {
                            await _showSaleActionSheet(s);
                          },
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => _SaleDetailScreen(sale: s),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header row with customer and total
                                Row(
                                  children: [
                                    if (s.paidAmount > 0) ...[
                                      Padding(
                                        padding: const EdgeInsets.only(right: 8),
                                        child: Icon(
                                          _paymentTypeIcon(s.paymentType),
                                          size: 18,
                                          color: _paymentTypeColor(context, s.paymentType),
                                        ),
                                      ),
                                    ],
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            customer,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (employeeLabel.isNotEmpty)
                                            Text(
                                              'NV: $employeeLabel',
                                              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: s.debt > 0
                                            ? Colors.red.withOpacity(0.1)
                                            : Colors.green.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        currency.format(s.total),
                                        style: TextStyle(
                                          color:
                                              s.debt > 0 ? Colors.red : Colors.green,
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
                                ...s.items
                                    .map((item) => Padding(
                                          padding: const EdgeInsets.only(bottom: 4),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 6,
                                                height: 6,
                                                margin:
                                                    const EdgeInsets.only(right: 8),
                                                decoration: const BoxDecoration(
                                                  color: Colors.blue,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              if (((item.itemType ?? '').toUpperCase().trim()) == 'MIX')
                                                Padding(
                                                  padding: const EdgeInsets.only(right: 6),
                                                  child: Icon(
                                                    Icons.blender,
                                                    size: 16,
                                                    color: Colors.deepPurple[400],
                                                  ),
                                                )
                                              else
                                                Padding(
                                                  padding: const EdgeInsets.only(right: 6),
                                                  child: Icon(
                                                    Icons.inventory_2_outlined,
                                                    size: 16,
                                                    color: Colors.blueGrey[400],
                                                  ),
                                                ),
                                              Expanded(
                                                child: Text(
                                                  '${(((item.itemType ?? '').toUpperCase().trim()) == 'MIX' && (item.displayName?.trim().isNotEmpty == true)) ? item.displayName!.trim() : item.name} x ${item.quantity} ${item.unit}',
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
                                        ))
                                    .toList(),
                                // Payment status and actions
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    if (s.discount > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'Giảm: ${currency.format(s.discount)}',
                                          style: const TextStyle(
                                            color: Colors.deepOrange,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      )
                                    else
                                      if (s.debt > 0)
                                        FutureBuilder<Debt?>(
                                          future: DatabaseService.instance.getDebtBySource(
                                            sourceType: 'sale',
                                            sourceId: s.id,
                                          ),
                                          builder: (context, snap) {
                                            if (snap.connectionState != ConnectionState.done) {
                                              return Container(
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
                                              );
                                            }
                                            final d = snap.data;
                                            if (d == null) {
                                              return Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.deepOrange.withOpacity(0.12),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  'Còn nợ: ${currency.format(s.debt)} • Thiếu ghi nợ',
                                                  style: const TextStyle(
                                                    color: Colors.deepOrange,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              );
                                            }
                                            return FutureBuilder<double>(
                                              future: DatabaseService.instance.getTotalPaidForDebt(d.id),
                                              builder: (context, paidSnap) {
                                                if (paidSnap.connectionState != ConnectionState.done) {
                                                  return Container(
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
                                                  );
                                                }
                                                final paid = paidSnap.data ?? 0;
                                                final remain = d.amount;
                                                final initialDebt = (remain + paid).clamp(0.0, double.infinity).toDouble();
                                                final mismatch = (initialDebt - s.debt).abs() > 0.5;
                                                if (mismatch) {
                                                  return Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: Colors.orange.withOpacity(0.16),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                      'Lệch nợ • Sale: ${currency.format(s.debt)} | Debt gốc: ${currency.format(initialDebt)} | Còn: ${currency.format(remain)}',
                                                      style: const TextStyle(
                                                        color: Colors.deepOrange,
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w700,
                                                      ),
                                                    ),
                                                  );
                                                }
                                                final settled = d.settled || remain <= 0;
                                                final bg = settled ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1);
                                                final fg = settled ? Colors.green : Colors.red;
                                                final text = settled
                                                    ? 'Đã tất toán'
                                                    : 'Đã trả: ${currency.format(paid)} | Còn: ${currency.format(remain)}';
                                                return Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: bg,
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    text,
                                                    style: TextStyle(
                                                      color: fg,
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                );
                                              },
                                            );
                                          },
                                        )
                                      else
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
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
                                    // New Print Button & Delete Button & Edit Button
                                    Row(
                                      children: [
                                        if (s.debt > 0) ...[
                                          IconButton(
                                            icon: const Icon(Icons.qr_code_2_outlined, color: Colors.blueAccent, size: 20),
                                            tooltip: 'QR nợ',
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: () async {
                                              await _showVietQrDebtDialog(s);
                                            },
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        IconButton(
                                          icon: const Icon(Icons.print_outlined,
                                              color: Colors.blueAccent, size: 20),
                                          tooltip: 'In hóa đơn',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _showPrintPreview(
                                              context, s, currency),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline,
                                              color: Colors.redAccent, size: 20),
                                          tooltip: 'Xóa hóa đơn',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () async {
                                            final ok = await showDialog<bool>(
                                              context: context,
                                              builder: (_) => AlertDialog(
                                                title: const Text('Xóa hóa đơn'),
                                                content: const Text(
                                                    'Bạn có chắc muốn xóa hóa đơn này?'),
                                                actions: [
                                                  TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              context, false),
                                                      child: const Text('Hủy')),
                                                  FilledButton(
                                                      onPressed: () =>
                                                          Navigator.pop(context, true),
                                                      child: const Text('Xóa')),
                                                ],
                                              ),
                                            );
                                            if (ok == true) {
                                              await context
                                                  .read<SaleProvider>()
                                                  .delete(s.id);
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                    content: Text('Đã xóa hóa đơn')),
                                              );
                                            }
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined,
                                              color: Colors.blueAccent, size: 20),
                                          tooltip: 'Sửa hóa đơn',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () async {
                                            final ok = await Navigator.push<bool>(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => SaleEditScreen(
                                                  sale: s,
                                                ),
                                              ),
                                            );
                                            if (ok == true) {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                    content: Text('Đã cập nhật bán hàng')),
                                              );
                                            }
                                          },
                                        ),
                                      ],
                                    ), // <-- Đã thêm đóng ngoặc Row này
                                  ],
                                ), // <-- Đã thêm đóng ngoặc Row lớn này
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
  Future<void> _showPrintPreview(
      BuildContext context, Sale sale, NumberFormat currency) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReceiptPreviewScreen(sale: sale, currency: currency),
      ),
    );
  }
  Future<void> _exportCsv(BuildContext context, List<Sale> sales) async {
    if (!context.mounted) return;
    // Tạo nội dung CSV
    final buffer = StringBuffer();
    buffer.writeln(
        'id,createdAt,customerId,customerName,subtotal,discount,paid,total,debt,items');
    for (final s in sales) {
      final items = s.items
          .map((e) => '${e.name} x ${e.quantity} @ ${e.unitPrice}')
          .join('; ');
      buffer.writeln(
          '${s.id},${s.createdAt.toIso8601String()},${s.customerId ?? ''},${s.customerName ?? ''},${s.subtotal},${s.discount},${s.paidAmount},${s.total},${s.debt},"${items.replaceAll('"', '""')}"');
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
class _SaleDetailScreen extends StatefulWidget {
  const _SaleDetailScreen({required this.sale});
  final Sale sale;
  @override
  State<_SaleDetailScreen> createState() => _SaleDetailScreenState();
}
class _SaleDetailScreenState extends State<_SaleDetailScreen> {
  late Sale _sale;
  List<Map<String, dynamic>> _decodeMixItems(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(s);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }
  @override
  void initState() {
    super.initState();
    _sale = widget.sale;
  }
  Future<void> _editSale() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SaleEditScreen(sale: widget.sale),
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      await context.read<SaleProvider>().load();
      if (!mounted) return;
      Sale? updated;
      try {
        updated = context.read<SaleProvider>().sales.firstWhere(
              (s) => s.id == widget.sale.id,
            );
      } catch (_) {
        updated = null;
      }
      setState(() {
        _sale = updated ?? _sale;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Đã cập nhật bán hàng')));
    }
  }
  @override
  Widget build(BuildContext context) {
    final sale = _sale;
    final fmtDate = DateFormat('dd/MM/yyyy HH:mm');
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    final customer = sale.customerName?.trim().isNotEmpty == true ? sale.customerName!.trim() : 'Khách lẻ';
    final paidAll = sale.debt <= 0;
    final statusBg = paidAll ? Colors.green.withOpacity(0.12) : Colors.red.withOpacity(0.12);
    final statusFg = paidAll ? Colors.green : Colors.red;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết bán hàng'),
        actions: [
          IconButton(
            tooltip: 'Sửa',
            icon: const Icon(Icons.edit_outlined),
            onPressed: _editSale,
          ),
          IconButton(
            tooltip: 'In hóa đơn',
            icon: const Icon(Icons.print_outlined),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReceiptPreviewScreen(
                    sale: sale,
                    currency: currency,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          customer,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: statusBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          paidAll ? 'Đã thanh toán' : 'Còn nợ',
                          style: TextStyle(color: statusFg, fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    fmtDate.format(sale.createdAt),
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                  const Divider(height: 16),
                  Row(
                    children: [
                      Expanded(child: Text('Tạm tính', style: TextStyle(color: Colors.grey[700]))),
                      Text(currency.format(sale.subtotal), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: Text('Giảm', style: TextStyle(color: Colors.grey[700]))),
                      Text(currency.format(sale.discount), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: Text('Khách trả', style: TextStyle(color: Colors.grey[700]))),
                      Text(currency.format(sale.paidAmount), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: Text('Còn nợ', style: TextStyle(color: Colors.grey[700]))),
                      Text(currency.format(sale.debt), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const Divider(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Tổng cộng', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                      Text(currency.format(sale.total), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              'Danh sách hàng (${sale.items.length})',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ...sale.items.map((it) {
            final t = (it.itemType ?? '').toUpperCase().trim();
            final isMix = t == 'MIX';
            final title = (isMix && it.displayName?.trim().isNotEmpty == true)
                ? it.displayName!.trim()
                : it.name;
            final mixItems = isMix ? _decodeMixItems(it.mixItemsJson) : const <Map<String, dynamic>>[];
            final leading = isMix
                ? Icon(Icons.blender, color: Colors.deepPurple[400])
                : Icon(Icons.inventory_2_outlined, color: Colors.blueGrey[400]);
            if (!isMix) {
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: leading,
                  title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${it.quantity} ${it.unit} × ${currency.format(it.unitPrice)}'),
                  trailing: Text(currency.format(it.total), style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              );
            }
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ExpansionTile(
                leading: leading,
                title: Row(
                  children: [
                    Expanded(
                      child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    Text(currency.format(it.total), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                subtitle: Text('${it.quantity} ${it.unit} × ${currency.format(it.unitPrice)}'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  if (mixItems.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Không có nguyên liệu'),
                    )
                  else
                    Column(
                      children: mixItems.map((m) {
                        final rawName = (m['rawName']?.toString() ?? '').trim();
                        final rawUnit = (m['rawUnit']?.toString() ?? '').trim();
                        final rawQty = (m['rawQty'] as num?)?.toDouble() ?? 0.0;
                        final rawUnitCost = (m['rawUnitCost'] as num?)?.toDouble() ?? 0.0;
                        final lineTotal = rawQty * rawUnitCost;
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  rawName.isEmpty ? 'Nguyên liệu' : rawName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${rawQty.toStringAsFixed(rawQty % 1 == 0 ? 0 : 2)} ${rawUnit.isEmpty ? '' : rawUnit}',
                                style: TextStyle(color: Colors.grey[700]),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                currency.format(rawUnitCost),
                                style: TextStyle(color: Colors.grey[700]),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                currency.format(lineTotal),
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}