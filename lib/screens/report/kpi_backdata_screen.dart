part of '../report_screen.dart';

enum _KpiBackdataKind {
  triple,
  cash,
  bank,
  cashPaidInPeriod,
  bankPaidInPeriod,
  outstanding,
}

class _KpiBackdataScreen extends StatefulWidget {
  final _KpiBackdataKind kind;
  final DateTimeRange dateRange;
  final String? employeeId;
  const _KpiBackdataScreen({
    required this.kind,
    required this.dateRange,
    required this.employeeId,
  });

  @override
  State<_KpiBackdataScreen> createState() => _KpiBackdataScreenState();
}

class _KpiBackdataScreenState extends State<_KpiBackdataScreen> {
  bool _exporting = false;
  final ScrollController _hScroll = ScrollController();

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  String _title() {
    switch (widget.kind) {
      case _KpiBackdataKind.triple:
        return 'Backdata Doanh thu / Vốn / Lợi nhuận';
      case _KpiBackdataKind.cash:
        return 'Backdata Thu tiền mặt';
      case _KpiBackdataKind.bank:
        return 'Backdata Thu chuyển khoản';
      case _KpiBackdataKind.cashPaidInPeriod:
        return 'Backdata Thu tiền mặt trong kỳ';
      case _KpiBackdataKind.bankPaidInPeriod:
        return 'Backdata Thu chuyển khoản trong kỳ';
      case _KpiBackdataKind.outstanding:
        return 'Backdata Nợ bán hàng';
    }
  }

  String _rangeLabel() {
    final fmt = DateFormat('dd/MM/yyyy');
    return '${fmt.format(widget.dateRange.start)} - ${fmt.format(widget.dateRange.end)}';
  }

  ex.CellValue? _cv(Object? v) {
    if (v == null) return null;
    if (v is ex.CellValue) return v;
    if (v is bool) return ex.BoolCellValue(v);
    if (v is int) return ex.IntCellValue(v);
    if (v is double) return ex.DoubleCellValue(v);
    if (v is num) return ex.DoubleCellValue(v.toDouble());
    return ex.TextCellValue(v.toString());
  }

  String _formatQty(num v) {
    final d = v.toDouble();
    if (d % 1 == 0) return d.toInt().toString();
    return d.toStringAsFixed(2);
  }

  Future<Map<String, List<Map<String, dynamic>>>> _loadSaleItemsBySaleIds(List<String> saleIds) async {
    if (saleIds.isEmpty) return const <String, List<Map<String, dynamic>>>{};
    final db = DatabaseService.instance.db;
    final uniq = saleIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    if (uniq.isEmpty) return const <String, List<Map<String, dynamic>>>{};
    final placeholders = List.filled(uniq.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT
        saleId as saleId,
        name as name,
        unitPrice as unitPrice,
        quantity as quantity
      FROM sale_items
      WHERE saleId IN ($placeholders)
      ORDER BY saleId
      ''',
      uniq,
    );

    final bySaleId = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      final sid = (r['saleId']?.toString() ?? '').trim();
      if (sid.isEmpty) continue;
      (bySaleId[sid] ??= <Map<String, dynamic>>[]).add(Map<String, dynamic>.from(r));
    }
    return bySaleId;
  }

  Future<List<Map<String, dynamic>>> _loadRows() async {
    final start = DateTime(widget.dateRange.start.year, widget.dateRange.start.month, widget.dateRange.start.day);
    final end = DateTime(widget.dateRange.end.year, widget.dateRange.end.month, widget.dateRange.end.day, 23, 59, 59, 999);
    final employeeId = (widget.employeeId ?? '').trim();
    final db = DatabaseService.instance.db;

    if (widget.kind == _KpiBackdataKind.triple) {
      final rows = await db.rawQuery(
        '''
        SELECT
          s.id as saleId,
          s.createdAt as saleCreatedAt,
          s.customerName as customerName,
          s.employeeId as employeeId,
          s.employeeName as employeeName,
          si.productId as productId,
          si.name as productName,
          si.unitPrice as unitPrice,
          si.quantity as quantity,
          si.unit as unit,
          si.unitCost as unitCost
        FROM sale_items si
        JOIN sales s ON s.id = si.saleId
        WHERE s.createdAt >= ? AND s.createdAt <= ?
        ${employeeId.isEmpty ? '' : 'AND s.employeeId = ?'}
        ORDER BY s.createdAt DESC
        ''',
        employeeId.isEmpty
            ? [start.toIso8601String(), end.toIso8601String()]
            : [start.toIso8601String(), end.toIso8601String(), employeeId],
      );

      return rows.map((e) => Map<String, dynamic>.from(e)).toList();
    }

    if (widget.kind == _KpiBackdataKind.cash || widget.kind == _KpiBackdataKind.bank) {
      final isCash = widget.kind == _KpiBackdataKind.cash;

      final salePaid = await db.rawQuery(
        '''
        SELECT
          s.id as saleId,
          s.createdAt as createdAt,
          s.customerName as customerName,
          s.employeeId as employeeId,
          s.employeeName as employeeName,
          s.paidAmount as amount,
          s.paymentType as paymentType,
          'sale' as source
        FROM sales s
        WHERE s.createdAt >= ? AND s.createdAt <= ?
          AND COALESCE(s.paidAmount, 0) > 0
          AND (
            (? = 1 AND LOWER(COALESCE(s.paymentType, '')) = 'cash')
            OR
            (? = 0 AND LOWER(COALESCE(s.paymentType, '')) != 'cash')
          )
          ${employeeId.isEmpty ? '' : 'AND s.employeeId = ?'}
        ORDER BY s.createdAt DESC
        ''',
        employeeId.isEmpty
            ? [start.toIso8601String(), end.toIso8601String(), isCash ? 1 : 0, isCash ? 1 : 0]
            : [start.toIso8601String(), end.toIso8601String(), isCash ? 1 : 0, isCash ? 1 : 0, employeeId],
      );

      final debtPaid = await db.rawQuery(
        '''
        SELECT
          d.sourceId as saleId,
          p.createdAt as createdAt,
          d.partyName as customerName,
          s.employeeId as employeeId,
          s.employeeName as employeeName,
          p.amount as amount,
          p.paymentType as paymentType,
          'debt' as source
        FROM debt_payments p
        JOIN debts d ON d.id = p.debtId
        JOIN sales s ON s.id = d.sourceId
        WHERE d.sourceType = 'sale'
          AND s.createdAt >= ? AND s.createdAt <= ?
          AND (
            (? = 1 AND LOWER(COALESCE(p.paymentType, '')) = 'cash')
            OR
            (? = 0 AND LOWER(COALESCE(p.paymentType, '')) != 'cash')
          )
          ${employeeId.isEmpty ? '' : 'AND s.employeeId = ?'}
        ORDER BY p.createdAt DESC
        ''',
        employeeId.isEmpty
            ? [start.toIso8601String(), end.toIso8601String(), isCash ? 1 : 0, isCash ? 1 : 0]
            : [start.toIso8601String(), end.toIso8601String(), isCash ? 1 : 0, isCash ? 1 : 0, employeeId],
      );

      final merged = <Map<String, dynamic>>[];
      merged.addAll(salePaid.map((e) => Map<String, dynamic>.from(e)));
      merged.addAll(debtPaid.map((e) => Map<String, dynamic>.from(e)));
      merged.sort((a, b) {
        final at = DateTime.tryParse((a['createdAt'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = DateTime.tryParse((b['createdAt'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      return merged;
    }

    if (widget.kind == _KpiBackdataKind.cashPaidInPeriod || widget.kind == _KpiBackdataKind.bankPaidInPeriod) {
      final isCash = widget.kind == _KpiBackdataKind.cashPaidInPeriod;
      final salePaid = await db.rawQuery(
        '''
        SELECT
          s.id as saleId,
          s.createdAt as createdAt,
          s.customerName as customerName,
          s.employeeId as employeeId,
          s.employeeName as employeeName,
          s.paidAmount as amount,
          s.paymentType as paymentType,
          'sale' as source
        FROM sales s
        WHERE s.createdAt >= ? AND s.createdAt <= ?
          AND COALESCE(s.paidAmount, 0) > 0
          AND (
            (? = 1 AND LOWER(COALESCE(s.paymentType, '')) = 'cash')
            OR
            (? = 0 AND LOWER(COALESCE(s.paymentType, '')) != 'cash')
          )
          ${employeeId.isEmpty ? '' : 'AND s.employeeId = ?'}
        ORDER BY s.createdAt DESC
        ''',
        employeeId.isEmpty
            ? [start.toIso8601String(), end.toIso8601String(), isCash ? 1 : 0, isCash ? 1 : 0]
            : [start.toIso8601String(), end.toIso8601String(), isCash ? 1 : 0, isCash ? 1 : 0, employeeId],
      );

      final debtPaid = await db.rawQuery(
        '''
        SELECT
          d.sourceId as saleId,
          p.createdAt as createdAt,
          d.partyName as customerName,
          s.employeeId as employeeId,
          s.employeeName as employeeName,
          p.amount as amount,
          p.paymentType as paymentType,
          'debt' as source
        FROM debt_payments p
        JOIN debts d ON d.id = p.debtId
        JOIN sales s ON s.id = d.sourceId
        WHERE d.sourceType = 'sale'
          AND p.createdAt >= ? AND p.createdAt <= ?
          AND (
            (? = 1 AND LOWER(COALESCE(p.paymentType, '')) = 'cash')
            OR
            (? = 0 AND LOWER(COALESCE(p.paymentType, '')) != 'cash')
          )
          ${employeeId.isEmpty ? '' : 'AND s.employeeId = ?'}
        ORDER BY p.createdAt DESC
        ''',
        employeeId.isEmpty
            ? [start.toIso8601String(), end.toIso8601String(), isCash ? 1 : 0, isCash ? 1 : 0]
            : [start.toIso8601String(), end.toIso8601String(), isCash ? 1 : 0, isCash ? 1 : 0, employeeId],
      );

      final merged = <Map<String, dynamic>>[];
      merged.addAll(salePaid.map((e) => Map<String, dynamic>.from(e)));
      merged.addAll(debtPaid.map((e) => Map<String, dynamic>.from(e)));
      merged.sort((a, b) {
        final at = DateTime.tryParse((a['createdAt'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = DateTime.tryParse((b['createdAt'] ?? '').toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      return merged;
    }

    final rows = await db.rawQuery(
      '''
      SELECT
        s.id as saleId,
        s.createdAt as saleCreatedAt,
        s.customerName as customerName,
        s.employeeId as employeeId,
        s.employeeName as employeeName,
        d.id as debtId,
        d.amount as debtAmount,
        COALESCE(SUM(p.amount), 0) as paidAmount
      FROM sales s
      JOIN debts d ON d.sourceType = 'sale' AND d.sourceId = s.id
      LEFT JOIN debt_payments p ON p.debtId = d.id
      WHERE s.createdAt >= ? AND s.createdAt <= ?
        ${employeeId.isEmpty ? '' : 'AND s.employeeId = ?'}
      GROUP BY s.id, s.createdAt, s.customerName, s.employeeId, s.employeeName, d.id, d.amount
      HAVING (d.amount - COALESCE(SUM(p.amount), 0)) > 0
      ORDER BY s.createdAt DESC
      ''',
      employeeId.isEmpty
          ? [start.toIso8601String(), end.toIso8601String()]
          : [start.toIso8601String(), end.toIso8601String(), employeeId],
    );
    return rows.map((e) {
      final m = Map<String, dynamic>.from(e);
      final debtAmount = (m['debtAmount'] as num?)?.toDouble() ?? 0.0;
      final paidAmount = (m['paidAmount'] as num?)?.toDouble() ?? 0.0;
      m['remain'] = (debtAmount - paidAmount);
      return m;
    }).toList();
  }

  Future<Map<String, double>> _computeTotals(List<Map<String, dynamic>> rows) async {
    if (widget.kind == _KpiBackdataKind.triple) {
      double sell = 0;
      double cost = 0;
      for (final r in rows) {
        final unitPrice = (r['unitPrice'] as num?)?.toDouble() ?? 0.0;
        final qty = (r['quantity'] as num?)?.toDouble() ?? 0.0;
        final unitCost = (r['unitCost'] as num?)?.toDouble() ?? 0.0;
        sell += unitPrice * qty;
        cost += unitCost * qty;
      }
      return {
        'sell': sell,
        'cost': cost,
        'profit': sell - cost,
      };
    }

    if (widget.kind == _KpiBackdataKind.outstanding) {
      final remain = rows.fold<double>(0.0, (p, e) => p + ((e['remain'] as num?)?.toDouble() ?? 0.0));
      return {
        'total': remain,
      };
    }

    final total = rows.fold<double>(0.0, (p, e) => p + ((e['amount'] as num?)?.toDouble() ?? 0.0));
    return {
      'total': total,
    };
  }

  Future<void> _exportExcel(List<Map<String, dynamic>> rows) async {
    setState(() => _exporting = true);
    try {
      final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
      final excel = ex.Excel.createExcel();
      excel.delete('Sheet1');
      final sheet = excel['backdata'];

      final saleIds = rows
          .map((e) => (e['saleId']?.toString() ?? '').trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      final itemsBySaleId = await _loadSaleItemsBySaleIds(saleIds);

      if (widget.kind == _KpiBackdataKind.triple) {
        sheet.appendRow([
          _cv('Ngày'),
          _cv('Khách'),
          _cv('Sản phẩm'),
          _cv('Số lượng'),
          _cv('Đơn giá'),
          _cv('Thành tiền'),
          _cv('Giá vốn'),
          _cv('Tiền vốn'),
          _cv('Lợi nhuận'),
        ]);
        for (final r in rows) {
          final createdAt = (r['saleCreatedAt'] ?? '').toString();
          final dt = DateTime.tryParse(createdAt);
          final dateLabel = dt == null ? createdAt : DateFormat('dd/MM/yyyy').format(dt);
          final customer = (r['customerName'] ?? '').toString();
          final name = (r['productName'] ?? '').toString();
          final unitPrice = (r['unitPrice'] as num?)?.toDouble() ?? 0.0;
          final qty = (r['quantity'] as num?)?.toDouble() ?? 0.0;
          final unitCost = (r['unitCost'] as num?)?.toDouble() ?? 0.0;
          final lineTotal = unitPrice * qty;
          final lineCost = unitCost * qty;
          final profit = lineTotal - lineCost;
          sheet.appendRow([
            _cv(dateLabel),
            _cv(customer),
            _cv(name),
            _cv(qty),
            _cv(unitPrice),
            _cv(lineTotal),
            _cv(unitCost),
            _cv(lineCost),
            _cv(profit),
          ]);
        }
      } else if (widget.kind == _KpiBackdataKind.outstanding) {
        sheet.appendRow([
          _cv('Ngày'),
          _cv('Khách'),
          _cv('SaleId'),
          _cv('DebtId'),
          _cv('Chi tiết'),
          _cv('Còn nợ'),
        ]);
        for (final r in rows) {
          final createdAt = (r['saleCreatedAt'] ?? '').toString();
          final dt = DateTime.tryParse(createdAt);
          final dateLabel = dt == null ? createdAt : DateFormat('dd/MM/yyyy').format(dt);
          final sid = (r['saleId']?.toString() ?? '').trim();
          final items = itemsBySaleId[sid] ?? const <Map<String, dynamic>>[];
          final detail = items
              .map((it) {
                final name = (it['name'] ?? '').toString();
                final unitPrice = (it['unitPrice'] as num?)?.toDouble() ?? 0.0;
                final qty = (it['quantity'] as num?)?.toDouble() ?? 0.0;
                final total = unitPrice * qty;
                return '$name, ${currency.format(unitPrice)}, ${_formatQty(qty)}, ${currency.format(total)}';
              })
              .where((e) => e.trim().isNotEmpty)
              .join('; ');
          sheet.appendRow([
            _cv(dateLabel),
            _cv(r['customerName']),
            _cv(r['saleId']),
            _cv(r['debtId']),
            _cv(detail),
            _cv(r['remain']),
          ]);
        }
      } else {
        sheet.appendRow([
          _cv('Ngày'),
          _cv('Khách'),
          _cv('SaleId'),
          _cv('Nguồn'),
          _cv('Hình thức'),
          _cv('Chi tiết'),
          _cv('Số tiền'),
        ]);
        for (final r in rows) {
          final createdAt = (r['createdAt'] ?? '').toString();
          final dt = DateTime.tryParse(createdAt);
          final dateLabel = dt == null ? createdAt : DateFormat('dd/MM/yyyy').format(dt);
          final sid = (r['saleId']?.toString() ?? '').trim();
          final items = itemsBySaleId[sid] ?? const <Map<String, dynamic>>[];
          final detail = items
              .map((it) {
                final name = (it['name'] ?? '').toString();
                final unitPrice = (it['unitPrice'] as num?)?.toDouble() ?? 0.0;
                final qty = (it['quantity'] as num?)?.toDouble() ?? 0.0;
                final total = unitPrice * qty;
                return '$name, ${currency.format(unitPrice)}, ${_formatQty(qty)}, ${currency.format(total)}';
              })
              .where((e) => e.trim().isNotEmpty)
              .join('; ');
          sheet.appendRow([
            _cv(dateLabel),
            _cv(r['customerName']),
            _cv(r['saleId']),
            _cv(r['source']),
            _cv(r['paymentType']),
            _cv(detail),
            _cv(r['amount']),
          ]);
        }
      }

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Không thể tạo file Excel');
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'backdata_$ts.xlsx';
      final filePath = await FileHelper.saveBytesToDownloads(bytes: bytes, fileName: fileName);
      if (filePath == null || filePath.trim().isEmpty) {
        throw Exception('Không thể lưu file Excel');
      }

      if (!mounted) return;
      await Share.shareXFiles([
        XFile(filePath),
      ], text: '${_title()} (${_rangeLabel()})');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã xuất: $fileName'),
          action: SnackBarAction(
            label: 'Mở',
            onPressed: () {
              OpenFilex.open(filePath);
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  List<String> _columns() {
    if (widget.kind == _KpiBackdataKind.triple) {
      return const ['Ngày', 'Khách', 'Sản phẩm', 'Số lượng', 'Đơn giá', 'Thành tiền', 'Giá vốn', 'Tiền vốn', 'Lợi nhuận'];
    }
    if (widget.kind == _KpiBackdataKind.outstanding) {
      return const ['Ngày', 'Khách', 'SaleId', 'DebtId', 'Chi tiết', 'Còn nợ'];
    }
    return const ['Ngày', 'Khách', 'SaleId', 'Nguồn', 'Hình thức', 'Chi tiết', 'Số tiền'];
  }

  String _buildDetailForSaleId(
    String saleId,
    NumberFormat currency,
    Map<String, List<Map<String, dynamic>>> itemsBySaleId,
  ) {
    final items = itemsBySaleId[saleId] ?? const <Map<String, dynamic>>[];
    return items
        .map((it) {
          final name = (it['name'] ?? '').toString();
          final unitPrice = (it['unitPrice'] as num?)?.toDouble() ?? 0.0;
          final qty = (it['quantity'] as num?)?.toDouble() ?? 0.0;
          final total = unitPrice * qty;
          return '$name, ${currency.format(unitPrice)}, ${_formatQty(qty)}, ${currency.format(total)}';
        })
        .where((e) => e.trim().isNotEmpty)
        .join('; ');
  }

  List<List<String>> _rowsAsStrings(
    List<Map<String, dynamic>> rows,
    NumberFormat currency,
    Map<String, List<Map<String, dynamic>>> itemsBySaleId,
  ) {
    if (widget.kind == _KpiBackdataKind.triple) {
      return rows.map((r) {
        final createdAt = (r['saleCreatedAt'] ?? '').toString();
        final dt = DateTime.tryParse(createdAt);
        final dateLabel = dt == null ? createdAt : DateFormat('dd/MM/yyyy').format(dt);
        final unitPrice = (r['unitPrice'] as num?)?.toDouble() ?? 0.0;
        final qty = (r['quantity'] as num?)?.toDouble() ?? 0.0;
        final unitCost = (r['unitCost'] as num?)?.toDouble() ?? 0.0;
        final lineTotal = unitPrice * qty;
        final lineCost = unitCost * qty;
        final profit = lineTotal - lineCost;
        return [
          dateLabel,
          (r['customerName'] ?? '').toString(),
          (r['productName'] ?? '').toString(),
          _formatQty(qty),
          currency.format(unitPrice),
          currency.format(lineTotal),
          currency.format(unitCost),
          currency.format(lineCost),
          currency.format(profit),
        ];
      }).toList();
    }

    if (widget.kind == _KpiBackdataKind.outstanding) {
      return rows.map((r) {
        final createdAt = (r['saleCreatedAt'] ?? '').toString();
        final dt = DateTime.tryParse(createdAt);
        final dateLabel = dt == null ? createdAt : DateFormat('dd/MM/yyyy').format(dt);
        final remain = (r['remain'] as num?)?.toDouble() ?? 0.0;
        final sid = (r['saleId'] ?? '').toString().trim();
        final detail = sid.isEmpty ? '' : _buildDetailForSaleId(sid, currency, itemsBySaleId);
        return [
          dateLabel,
          (r['customerName'] ?? '').toString(),
          (r['saleId'] ?? '').toString(),
          (r['debtId'] ?? '').toString(),
          detail,
          currency.format(remain),
        ];
      }).toList();
    }

    return rows.map((r) {
      final createdAt = (r['createdAt'] ?? '').toString();
      final dt = DateTime.tryParse(createdAt);
      final dateLabel = dt == null ? createdAt : DateFormat('dd/MM/yyyy').format(dt);
      final amount = (r['amount'] as num?)?.toDouble() ?? 0.0;
      final sid = (r['saleId'] ?? '').toString().trim();
      final detail = sid.isEmpty ? '' : _buildDetailForSaleId(sid, currency, itemsBySaleId);
      return [
        dateLabel,
        (r['customerName'] ?? '').toString(),
        (r['saleId'] ?? '').toString(),
        (r['source'] ?? '').toString(),
        (r['paymentType'] ?? '').toString(),
        detail,
        currency.format(amount),
      ];
    }).toList();
  }

  List<double> _calcWidths({required List<String> headers, required List<List<String>> rows}) {
    final maxChars = List<int>.filled(headers.length, 0);
    for (var i = 0; i < headers.length; i++) {
      maxChars[i] = headers[i].trim().length;
    }
    final sampleCount = rows.length > 80 ? 80 : rows.length;
    for (var r = 0; r < sampleCount; r++) {
      final row = rows[r];
      for (var i = 0; i < headers.length && i < row.length; i++) {
        final len = row[i].trim().length;
        if (len > maxChars[i]) maxChars[i] = len;
      }
    }

    double wFor(int chars, {double min = 70, double max = 320}) {
      final w = (chars * 7.4) + 28;
      if (w < min) return min;
      if (w > max) return max;
      return w;
    }

    return List<double>.generate(headers.length, (i) {
      final h = headers[i].toLowerCase();
      if (h.contains('saleid') || h.contains('debtid')) return wFor(maxChars[i], min: 80, max: 100);
      if (h.contains('ngày')) return 100;
      if (h.contains('khách')) return wFor(maxChars[i], min: 80, max: 150);
      if (h.contains('sản phẩm')) return wFor(maxChars[i], min: 180, max: 360);
      if (h.contains('hình thức') || h.contains('nguồn')) return wFor(maxChars[i], min: 50, max: 100);
      if (h.contains('tiền') || h.contains('giá') || h.contains('thành') || h.contains('lợi') || h.contains('còn')) {
        return wFor(maxChars[i], min: 110, max: 160);
      }
      return wFor(maxChars[i]);
    });
  }

  bool _isNumericColumn(String header) {
    final h = header.toLowerCase();
    return h.contains('tiền') || h.contains('giá') || h.contains('thành') || h.contains('lợi') || h.contains('còn') || h.contains('số');
  }

  Widget _buildCell({required String text, required double width, required bool isHeader, required TextAlign align, required TextStyle style}) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: align,
          style: style,
        ),
      ),
    );
  }

  Widget _buildPrettyTable({required List<String> headers, required List<List<String>> bodyRows, required List<double> widths}) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: theme.colorScheme.onPrimary,
        ) ??
        TextStyle(fontWeight: FontWeight.w800, color: theme.colorScheme.onPrimary);
    final cellStyle = theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        ) ??
        TextStyle(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface);

    final header = Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Row(
        children: List.generate(headers.length, (i) {
          final align = _isNumericColumn(headers[i]) ? TextAlign.right : TextAlign.left;
          return _buildCell(
            text: headers[i],
            width: widths[i],
            isHeader: true,
            align: align,
            style: headerStyle,
          );
        }),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor.withAlpha(120)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            header,
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: bodyRows.length,
                itemBuilder: (context, index) {
                  final r = bodyRows[index];
                  final zebra = index.isEven;
                  final bg = zebra ? theme.colorScheme.surface : theme.colorScheme.surfaceContainerHighest;
                  return Container(
                    color: bg,
                    child: Row(
                      children: List.generate(headers.length, (i) {
                        final v = (i < r.length) ? r[i] : '';
                        final align = _isNumericColumn(headers[i]) ? TextAlign.right : TextAlign.left;
                        return _buildCell(
                          text: v,
                          width: widths[i],
                          isHeader: false,
                          align: align,
                          style: cellStyle,
                        );
                      }),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);
    return Scaffold(
      appBar: AppBar(
        title: Text(_title()),
        actions: [
          IconButton(
            tooltip: 'Xuất / Share Excel',
            onPressed: _exporting
                ? null
                : () async {
                    final rows = await _loadRows();
                    if (!mounted) return;
                    await _exportExcel(rows);
                  },
            icon: _exporting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share),
          ),
        ],
      ),
      body: FutureBuilder<List<Object>>(
        future: () async {
          final rows = await _loadRows();
          final saleIds = rows
              .map((e) => (e['saleId']?.toString() ?? '').trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList();
          final itemsBySaleId = await _loadSaleItemsBySaleIds(saleIds);
          return [rows, itemsBySaleId];
        }(),
        builder: (context, snap) {
          final data = snap.data;
          final rows = (data != null && data.isNotEmpty)
              ? (data[0] as List<Map<String, dynamic>>)
              : const <Map<String, dynamic>>[];
          final itemsBySaleId = (data != null && data.length > 1)
              ? (data[1] as Map<String, List<Map<String, dynamic>>>)
              : const <String, List<Map<String, dynamic>>>{};
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return FutureBuilder<Map<String, double>>(
            future: _computeTotals(rows),
            builder: (context, totalSnap) {
              final totals = totalSnap.data ?? const <String, double>{};
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Khoảng: ${_rangeLabel()}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        if (widget.kind == _KpiBackdataKind.triple) ...[
                          Text('Doanh thu: ${currency.format(totals['sell'] ?? 0)}'),
                          Text('Vốn: ${currency.format(totals['cost'] ?? 0)}'),
                          Text('Lợi nhuận: ${currency.format(totals['profit'] ?? 0)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        ] else ...[
                          Text('Tổng: ${currency.format(totals['total'] ?? 0)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: rows.isEmpty
                        ? const Center(child: Text('Chưa có dữ liệu'))
                        : Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final tableHeight = constraints.maxHeight;
                                final headers = _columns();
                                final body = _rowsAsStrings(rows, currency, itemsBySaleId);
                                final widths = _calcWidths(headers: headers, rows: body);
                                final minTableWidth = MediaQuery.of(context).size.width - 24;
                                final sumWidth = widths.fold<double>(0.0, (p, e) => p + e);
                                final tableWidth = (sumWidth < minTableWidth) ? minTableWidth : sumWidth;

                                return Scrollbar(
                                  controller: _hScroll,
                                  child: SingleChildScrollView(
                                    controller: _hScroll,
                                    scrollDirection: Axis.horizontal,
                                    child: SizedBox(
                                      height: tableHeight,
                                      width: tableWidth,
                                      child: _buildPrettyTable(headers: headers, bodyRows: body, widths: widths),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
