import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'database_service.dart';

class SheetsSyncService {
  static const defaultSpreadsheetTitle = 'GhiNoSheetDB';

  Map<String, String> _authHeaders(String accessToken) => {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json; charset=UTF-8',
      };

  Future<Map<String, dynamic>> _getJson({
    required String accessToken,
    required Uri url,
  }) async {
    final resp = await http.get(url, headers: _authHeaders(accessToken));
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return (jsonDecode(resp.body) as Map).cast<String, dynamic>();
    }
    throw Exception('Sheets GET failed (${resp.statusCode}): ${resp.body}');
  }

  Future<Map<String, dynamic>> _postJson({
    required String accessToken,
    required Uri url,
    required Map<String, dynamic> body,
  }) async {
    final resp = await http.post(
      url,
      headers: _authHeaders(accessToken),
      body: jsonEncode(body),
    );
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return (jsonDecode(resp.body) as Map).cast<String, dynamic>();
    }
    throw Exception('Sheets POST failed (${resp.statusCode}): ${resp.body}');
  }

  Future<Map<String, dynamic>> _putJson({
    required String accessToken,
    required Uri url,
    required Map<String, dynamic> body,
  }) async {
    final resp = await http.put(
      url,
      headers: _authHeaders(accessToken),
      body: jsonEncode(body),
    );
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return (jsonDecode(resp.body) as Map).cast<String, dynamic>();
    }
    throw Exception('Sheets PUT failed (${resp.statusCode}): ${resp.body}');
  }

  Future<String> createSpreadsheet({required String accessToken, String? title}) async {
    final resp = await _postJson(
      accessToken: accessToken,
      url: Uri.parse('https://sheets.googleapis.com/v4/spreadsheets'),
      body: {
        'properties': {
          'title': (title == null || title.trim().isEmpty) ? defaultSpreadsheetTitle : title.trim(),
        },
      },
    );

    final id = (resp['spreadsheetId'] ?? '').toString().trim();
    if (id.isEmpty) throw Exception('Không tạo được Spreadsheet');
    return id;
  }

  Future<void> ensureSheets({required String accessToken, required String spreadsheetId}) async {
    final ss = await _getJson(
      accessToken: accessToken,
      url: Uri.parse(
        'https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId?fields=sheets.properties.title',
      ),
    );

    final sheetsList = (ss['sheets'] as List?) ?? const [];
    final existingTitles = <String>{};
    for (final s in sheetsList) {
      if (s is Map) {
        final props = s['properties'];
        if (props is Map) {
          final title = (props['title'] ?? '').toString().trim();
          if (title.isNotEmpty) existingTitles.add(title);
        }
      }
    }

    final requests = <Map<String, dynamic>>[];
    for (final t in _sheetTitles) {
      if (existingTitles.contains(t)) continue;
      requests.add({
        'addSheet': {
          'properties': {'title': t}
        }
      });
    }

    if (requests.isEmpty) return;

    await _postJson(
      accessToken: accessToken,
      url: Uri.parse('https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId:batchUpdate'),
      body: {'requests': requests},
    );
  }

  Future<void> syncAll({
    required String accessToken,
    required String spreadsheetId,
    DateTimeRange? range,
  }) async {
    await ensureSheets(accessToken: accessToken, spreadsheetId: spreadsheetId);

    final db = DatabaseService.instance.db;

    final customers = await DatabaseService.instance.getCustomersForSync();
    final productsRows = await db.query(
      'products',
      where: 'isActive = 1',
      orderBy: 'name ASC',
    );
    final productsById = <String, Map<String, dynamic>>{
      for (final p in productsRows) (p['id'] as String): p,
    };

    final debts = await DatabaseService.instance.getDebtsForSync();
    final debtPayments = await DatabaseService.instance.getDebtPaymentsForSync(range: range);

    final expenses = await _getExpenses(range: range);

    final purchases = await db.query(
      'purchase_history',
      orderBy: 'createdAt DESC',
    );

    final sales = await DatabaseService.instance.getSalesForSync();
    final saleItems = await db.query('sale_items');
    final saleById = <String, Map<String, dynamic>>{
      for (final s in sales) (s['id'] as String): s,
    };

    final saleItemsForExportHistory = await _getSaleItemsInRange(range: range);

    final openingRows = await db.query('product_opening_stocks');

    final monthYear = _monthYearForEnding(range);
    final endingRows = await _buildEndingInventory(monthYear: monthYear);

    await _upsertSheet(
      accessToken: accessToken,
      spreadsheetId: spreadsheetId,
      sheetTitle: 'list khách hàng',
      headers: const ['id', 'name', 'phone', 'note', 'isSupplier', 'updatedAt', 'deviceId', 'isSynced'],
      rows: customers.map((c) => [
            c['id'],
            c['name'],
            c['phone'],
            c['note'],
            c['isSupplier'],
            c['updatedAt'],
            c['deviceId'],
            c['isSynced'],
          ]),
    );

    await _upsertSheet(
      accessToken: accessToken,
      spreadsheetId: spreadsheetId,
      sheetTitle: 'list sản phẩm',
      headers: const [
        'id',
        'name',
        'unit',
        'barcode',
        'price',
        'costPrice',
        'currentStock',
        'isActive',
        'updatedAt',
        'deviceId',
        'isSynced'
      ],
      rows: productsRows.map((p) => [
            p['id'],
            p['name'],
            p['unit'],
            p['barcode'],
            p['price'],
            p['costPrice'],
            p['currentStock'],
            p['isActive'],
            p['updatedAt'],
            p['deviceId'],
            p['isSynced'],
          ]),
    );

    await _upsertSheet(
      accessToken: accessToken,
      spreadsheetId: spreadsheetId,
      sheetTitle: 'list công nợ',
      headers: const [
        'id',
        'customerId',
        'customerName',
        'amount',
        'createdAt',
        'dueDate',
        'note',
        'isPaid',
        'paidAt',
        'updatedAt',
        'sourceType',
        'sourceId'
      ],
      rows: debts.map((d) => [
            d['id'],
            d['customerId'],
            d['customerName'],
            d['amount'],
            d['createdAt'],
            d['dueDate'],
            d['note'],
            d['isPaid'],
            d['paidAt'],
            d['updatedAt'],
            d['sourceType'],
            d['sourceId'],
          ]),
    );

    await _upsertSheet(
      accessToken: accessToken,
      spreadsheetId: spreadsheetId,
      sheetTitle: 'lịch sử trả nợ',
      headers: const [
        'paymentId',
        'debtId',
        'debtType',
        'partyId',
        'partyName',
        'amount',
        'note',
        'createdAt',
        'isSynced'
      ],
      rows: debtPayments.map((p) => [
            p['paymentId'],
            p['debtId'],
            p['debtType'],
            p['partyId'],
            p['partyName'],
            p['amount'],
            p['note'],
            p['createdAt'],
            p['isSynced'],
          ]),
    );

    await _upsertSheet(
      accessToken: accessToken,
      spreadsheetId: spreadsheetId,
      sheetTitle: 'list chi phí',
      headers: const [
        'id',
        'occurredAt',
        'amount',
        'category',
        'note',
        'expenseDocUploaded',
        'expenseDocFileId',
        'expenseDocUpdatedAt',
        'updatedAt'
      ],
      rows: expenses.map((e) => [
            e['id'],
            e['occurredAt'],
            e['amount'],
            e['category'],
            e['note'],
            e['expenseDocUploaded'],
            e['expenseDocFileId'],
            e['expenseDocUpdatedAt'],
            e['updatedAt'],
          ]),
    );

    await _upsertSheet(
      accessToken: accessToken,
      spreadsheetId: spreadsheetId,
      sheetTitle: 'list nhập hàng',
      headers: const [
        'id',
        'createdAt',
        'productId',
        'productName',
        'productUnit',
        'quantity',
        'unitCost',
        'totalCost',
        'supplierName',
        'supplierPhone',
        'note',
        'updatedAt'
      ],
      rows: purchases.map((ph) {
        final pid = ph['productId'] as String;
        final prod = productsById[pid];
        return [
          ph['id'],
          ph['createdAt'],
          pid,
          ph['productName'],
          prod?['unit'],
          ph['quantity'],
          ph['unitCost'],
          ph['totalCost'],
          ph['supplierName'],
          ph['supplierPhone'],
          ph['note'],
          ph['updatedAt'],
        ];
      }),
    );

    await _upsertSheet(
      accessToken: accessToken,
      spreadsheetId: spreadsheetId,
      sheetTitle: 'list xuất hàng',
      headers: const [
        'saleId',
        'saleCreatedAt',
        'customerId',
        'customerName',
        'saleDiscount',
        'salePaidAmount',
        'saleTotalCost',
        'saleNote',
        'productId',
        'productName',
        'productUnit',
        'unitPrice',
        'quantity',
        'lineTotal',
        'productCostPrice',
        'lineCostTotal'
      ],
      rows: saleItems.map((it) {
        final saleId = it['saleId'] as String?;
        if (saleId == null) return const <Object?>[];
        final sale = saleById[saleId];
        if (sale == null) return const <Object?>[];
        final pid = it['productId'] as String?;
        final prod = pid == null ? null : productsById[pid];
        final unitPrice = (it['unitPrice'] as num?)?.toDouble() ?? 0;
        final qty = (it['quantity'] as num?)?.toDouble() ?? 0;
        final lineTotal = unitPrice * qty;
        final costPrice = (prod?['costPrice'] as num?)?.toDouble() ?? 0;
        final lineCostTotal = costPrice * qty;
        return [
          saleId,
          sale['createdAt'],
          sale['customerId'],
          sale['customerName'],
          sale['discount'],
          sale['paidAmount'],
          sale['totalCost'],
          sale['note'],
          pid,
          it['name'],
          prod?['unit'] ?? it['unit'],
          unitPrice,
          qty,
          lineTotal,
          costPrice,
          lineCostTotal,
        ];
      }).where((r) => r.isNotEmpty),
    );

    await _upsertSheet(
      accessToken: accessToken,
      spreadsheetId: spreadsheetId,
      sheetTitle: 'lịch sử xuất kho',
      headers: const [
        'saleId',
        'saleCreatedAt',
        'customerName',
        'productId',
        'productName',
        'unit',
        'quantity',
        'source'
      ],
      rows: _expandExportHistoryRows(saleItemsForExportHistory),
    );

    await _upsertSheet(
      accessToken: accessToken,
      spreadsheetId: spreadsheetId,
      sheetTitle: 'list tồn đầu kỳ',
      headers: const ['year', 'month', 'productId', 'productName', 'productUnit', 'openingStock', 'updatedAt'],
      rows: openingRows.map((r) {
        final pid = r['productId'] as String;
        final prod = productsById[pid];
        return [
          r['year'],
          r['month'],
          pid,
          prod?['name'],
          prod?['unit'],
          r['openingStock'],
          r['updatedAt'],
        ];
      }),
    );

    await _upsertSheet(
      accessToken: accessToken,
      spreadsheetId: spreadsheetId,
      sheetTitle: 'list tồn cuối kỳ',
      headers: const [
        'year',
        'month',
        'productId',
        'productName',
        'productUnit',
        'openingStock',
        'importQty',
        'exportQty',
        'endingQty',
        'costPrice',
        'endingAmountCost',
        'price',
        'endingAmountSell'
      ],
      rows: endingRows,
    );
  }

  Future<List<Map<String, dynamic>>> _getExpenses({DateTimeRange? range}) async {
    final db = DatabaseService.instance.db;
    if (range == null) {
      return db.query('expenses', orderBy: 'occurredAt DESC');
    }
    final start = DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59, 999);
    return db.query(
      'expenses',
      where: 'occurredAt >= ? AND occurredAt <= ?',
      whereArgs: [start.toIso8601String(), end.toIso8601String()],
      orderBy: 'occurredAt DESC',
    );
  }

  Future<List<Map<String, dynamic>>> _getSaleItemsInRange({DateTimeRange? range}) async {
    final db = DatabaseService.instance.db;

    if (range == null) {
      return db.rawQuery(
        '''
        SELECT
          s.id as saleId,
          s.createdAt as saleCreatedAt,
          s.customerName as customerName,
          si.productId as productId,
          si.name as name,
          si.unit as unit,
          si.quantity as quantity,
          si.itemType as itemType,
          si.mixItemsJson as mixItemsJson
        FROM sale_items si
        JOIN sales s ON s.id = si.saleId
        ORDER BY s.createdAt DESC
        ''',
      );
    }

    final start = DateTime(range.start.year, range.start.month, range.start.day);
    final end = DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59, 999);

    return db.rawQuery(
      '''
      SELECT
        s.id as saleId,
        s.createdAt as saleCreatedAt,
        s.customerName as customerName,
        si.productId as productId,
        si.name as name,
        si.unit as unit,
        si.quantity as quantity,
        si.itemType as itemType,
        si.mixItemsJson as mixItemsJson
      FROM sale_items si
      JOIN sales s ON s.id = si.saleId
      WHERE s.createdAt >= ? AND s.createdAt <= ?
      ORDER BY s.createdAt DESC
      ''',
      [start.toIso8601String(), end.toIso8601String()],
    );
  }

  Iterable<List<Object?>> _expandExportHistoryRows(List<Map<String, dynamic>> saleItemsInRange) sync* {
    for (final r in saleItemsInRange) {
      final itemType = (r['itemType']?.toString() ?? '').toUpperCase().trim();
      if (itemType == 'MIX') {
        final raw = (r['mixItemsJson']?.toString() ?? '').trim();
        if (raw.isEmpty) continue;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            for (final e in decoded) {
              if (e is Map) {
                final rid = (e['rawProductId']?.toString() ?? '').trim();
                if (rid.isEmpty) continue;
                yield [
                  r['saleId'],
                  r['saleCreatedAt'],
                  r['customerName'],
                  rid,
                  e['rawName'],
                  e['rawUnit'],
                  (e['rawQty'] as num?)?.toDouble() ?? 0.0,
                  'MIX',
                ];
              }
            }
          }
        } catch (_) {
          continue;
        }
      } else {
        final pid = (r['productId']?.toString() ?? '').trim();
        if (pid.isEmpty) continue;
        yield [
          r['saleId'],
          r['saleCreatedAt'],
          r['customerName'],
          pid,
          r['name'],
          r['unit'],
          (r['quantity'] as num?)?.toDouble() ?? 0.0,
          'RAW',
        ];
      }
    }
  }

  ({int year, int month}) _monthYearForEnding(DateTimeRange? range) {
    final now = DateTime.now();
    final d = range?.start ?? now;
    return (year: d.year, month: d.month);
  }

  Future<List<List<Object?>>> _buildEndingInventory({required ({int year, int month}) monthYear}) async {
    final db = DatabaseService.instance.db;

    final monthStart = DateTime(monthYear.year, monthYear.month, 1);
    final monthEnd = DateTime(monthYear.year, monthYear.month + 1, 0, 23, 59, 59, 999);

    final productsRows = await db.query(
      'products',
      where: 'isActive = 1',
      orderBy: 'name ASC',
    );
    final productsById = <String, Map<String, dynamic>>{
      for (final p in productsRows) (p['id'] as String): p,
    };

    final openingRows = await db.query(
      'product_opening_stocks',
      where: 'year = ? AND month = ?',
      whereArgs: [monthYear.year, monthYear.month],
    );
    final openingByProductId = <String, double>{
      for (final r in openingRows)
        (r['productId'] as String): (r['openingStock'] as num?)?.toDouble() ?? 0,
    };

    final purchases = await db.query('purchase_history', orderBy: 'createdAt DESC');
    final sales = await DatabaseService.instance.getSalesForSync();
    final saleItems = await db.query('sale_items');
    final saleById = <String, Map<String, dynamic>>{
      for (final s in sales) (s['id'] as String): s,
    };

    final importQtyByProductId = <String, double>{};
    final exportQtyByProductId = <String, double>{};

    for (final pr in purchases) {
      final createdAt = DateTime.tryParse(pr['createdAt'] as String? ?? '');
      if (createdAt == null) continue;
      if (createdAt.isBefore(monthStart) || createdAt.isAfter(monthEnd)) continue;
      final pid = pr['productId'] as String;
      final qty = (pr['quantity'] as num?)?.toDouble() ?? 0;
      importQtyByProductId[pid] = (importQtyByProductId[pid] ?? 0) + qty;
    }

    for (final it in saleItems) {
      final saleId = it['saleId'] as String?;
      if (saleId == null) continue;
      final sale = saleById[saleId];
      if (sale == null) continue;
      final createdAt = DateTime.tryParse(sale['createdAt'] as String? ?? '');
      if (createdAt == null) continue;
      if (createdAt.isBefore(monthStart) || createdAt.isAfter(monthEnd)) continue;
      final pid = it['productId'] as String?;
      if (pid == null) continue;
      final qty = (it['quantity'] as num?)?.toDouble() ?? 0;
      exportQtyByProductId[pid] = (exportQtyByProductId[pid] ?? 0) + qty;
    }

    final productIds = <String>{
      ...productsById.keys,
      ...openingByProductId.keys,
      ...importQtyByProductId.keys,
      ...exportQtyByProductId.keys,
    }.toList();

    productIds.sort((a, b) {
      final an = (productsById[a]?['name'] as String?) ?? '';
      final bn = (productsById[b]?['name'] as String?) ?? '';
      return an.compareTo(bn);
    });

    final rows = <List<Object?>>[];
    for (final pid in productIds) {
      final prod = productsById[pid];
      final opening = openingByProductId[pid] ?? 0;
      final importQty = importQtyByProductId[pid] ?? 0;
      final exportQty = exportQtyByProductId[pid] ?? 0;
      final endingQty = opening + importQty - exportQty;
      final costPrice = (prod?['costPrice'] as num?)?.toDouble() ?? 0;
      final price = (prod?['price'] as num?)?.toDouble() ?? 0;
      rows.add([
        monthYear.year,
        monthYear.month,
        pid,
        prod?['name'],
        prod?['unit'],
        opening,
        importQty,
        exportQty,
        endingQty,
        costPrice,
        endingQty * costPrice,
        price,
        endingQty * price,
      ]);
    }

    return rows;
  }

  Future<void> _upsertSheet({
    required String accessToken,
    required String spreadsheetId,
    required String sheetTitle,
    required List<String> headers,
    required Iterable<List<Object?>> rows,
  }) async {
    final rangeAll = Uri.encodeComponent("'$sheetTitle'!A:Z");
    final existing = await _getJson(
      accessToken: accessToken,
      url: Uri.parse('https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId/values/$rangeAll'),
    );

    final values = (existing['values'] as List?) ?? const [];

    // If empty, write full (headers + all rows)
    if (values.isEmpty) {
      final all = <List<Object?>>[headers, ...rows];
      final rangeA1 = Uri.encodeComponent("'$sheetTitle'!A1");
      await _putJson(
        accessToken: accessToken,
        url: Uri.parse(
          'https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId/values/$rangeA1?valueInputOption=RAW',
        ),
        body: {
          'range': "'$sheetTitle'!A1",
          'majorDimension': 'ROWS',
          'values': all,
        },
      );
      return;
    }

    // Ensure headers match (overwrite row1)
    final batchData = <Map<String, dynamic>>[
      {
        'range': "'$sheetTitle'!A1",
        'majorDimension': 'ROWS',
        'values': [headers],
      },
    ];

    final idToRowIndex = <String, int>{};
    for (var i = 1; i < values.length; i++) {
      final row = values[i];
      if (row is! List) continue;
      if (row.isEmpty) continue;
      final id = row.first.toString();
      if (id.trim().isEmpty) continue;
      idToRowIndex[id] = i + 1; // 1-indexed row number
    }

    final toAppend = <List<Object?>>[];

    for (final r in rows) {
      if (r.isEmpty) continue;
      final id = r.first.toString();
      if (id.trim().isEmpty) {
        toAppend.add(r);
        continue;
      }

      final existingRow = idToRowIndex[id];
      if (existingRow == null) {
        toAppend.add(r);
      } else {
        batchData.add({
          'range': "'$sheetTitle'!A$existingRow",
          'majorDimension': 'ROWS',
          'values': [r],
        });
      }
    }

    // Batch update headers + all updated rows in one request
    if (batchData.isNotEmpty) {
      await _postJson(
        accessToken: accessToken,
        url: Uri.parse(
          'https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId/values:batchUpdate',
        ),
        body: {
          'valueInputOption': 'RAW',
          'data': batchData,
        },
      );
    }

    if (toAppend.isNotEmpty) {
      final appendRange = Uri.encodeComponent("'$sheetTitle'!A1");
      await _postJson(
        accessToken: accessToken,
        url: Uri.parse(
          'https://sheets.googleapis.com/v4/spreadsheets/$spreadsheetId/values/$appendRange:append?valueInputOption=RAW&insertDataOption=INSERT_ROWS',
        ),
        body: {
          'range': "'$sheetTitle'!A1",
          'majorDimension': 'ROWS',
          'values': toAppend,
        },
      );
    }
  }

  static const List<String> _sheetTitles = [
    'list khách hàng',
    'list sản phẩm',
    'list công nợ',
    'lịch sử trả nợ',
    'list chi phí',
    'list nhập hàng',
    'list xuất hàng',
    'lịch sử xuất kho',
    'list tồn đầu kỳ',
    'list tồn cuối kỳ',
  ];
}
