import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../providers/auth_provider.dart';
import 'database_service.dart';

class OnlineSyncService {
  OnlineSyncService._();

  static const _prefsKeyJwt = 'backend_jwt';
  static const _prefsKeyBaseUrl = 'backend_base_url';
  static const _prefsKeyLastSyncAt = 'online_sync_last_at';
  static const _prefsKeyLastSyncError = 'online_sync_last_error';

  static const _syncCursorKey = 'online_sync_cursor';

  static StreamSubscription<ConnectivityResult>? _connSub;
  static bool _syncInFlight = false;
  static int _consecutiveFailures = 0;
  static DateTime? _nextAllowedAttemptAt;

  static void _log(String message) {
    debugPrint('[OnlineSync] $message');
  }

  static Future<void> _logDb({required String action, String? details}) async {
    try {
      final db = DatabaseService.instance.db;
      final deviceId = await DatabaseService.instance.deviceId;
      await db.insert('sync_logs', {
        'action': action,
        'entityType': 'online_sync',
        'entityId': null,
        'deviceId': deviceId,
        'timestamp': DateTime.now().toIso8601String(),
        'details': details,
      });
    } catch (_) {
      // ignore
    }
  }

  static Duration _computeBackoff(int failures) {
    if (failures <= 0) return Duration.zero;
    final seconds = 2 << (failures.clamp(1, 6) - 1);
    return Duration(seconds: seconds);
  }

  static Future<bool> _hasNetwork() async {
    final r = await Connectivity().checkConnectivity();
    return r != ConnectivityResult.none;
  }

  static Future<void> startAutoSync({required AuthProvider auth}) async {
    await stopAutoSync();

    _connSub = Connectivity().onConnectivityChanged.listen((r) async {
      if (r == ConnectivityResult.none) return;
      _log('connectivity changed => $r');
      await syncNow(auth: auth, allowBackoff: true);
    });

    if (await _hasNetwork()) {
      _log('startAutoSync: already has network => trigger sync');
      await syncNow(auth: auth, allowBackoff: true);
    }
  }

  static Future<void> stopAutoSync() async {
    final sub = _connSub;
    _connSub = null;
    await sub?.cancel();
    _log('stopAutoSync');
  }

  static Future<String> _baseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = (prefs.getString(_prefsKeyBaseUrl) ?? '').trim();
    if (raw.isNotEmpty) return raw;
    return 'http://localhost:3006';
  }

  static Future<String> getBaseUrl() async {
    return _baseUrl();
  }

  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyBaseUrl, url.trim());
  }

  static Future<String?> getLastSyncAt() async {
    final prefs = await SharedPreferences.getInstance();
    final v = (prefs.getString(_prefsKeyLastSyncAt) ?? '').trim();
    return v.isEmpty ? null : v;
  }

  static Future<String?> getLastSyncError() async {
    final prefs = await SharedPreferences.getInstance();
    final v = (prefs.getString(_prefsKeyLastSyncError) ?? '').trim();
    return v.isEmpty ? null : v;
  }

  static Future<void> _setLastSyncOk() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyLastSyncAt, DateTime.now().toIso8601String());
    await prefs.remove(_prefsKeyLastSyncError);
  }

  static Future<void> _setLastSyncError(String message) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyLastSyncAt, DateTime.now().toIso8601String());
    await prefs.setString(_prefsKeyLastSyncError, message.trim());
  }

  static Future<String?> _getJwt() async {
    final prefs = await SharedPreferences.getInstance();
    final v = (prefs.getString(_prefsKeyJwt) ?? '').trim();
    return v.isEmpty ? null : v;
  }

  static Future<void> _setJwt(String jwt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyJwt, jwt);
  }

  static Future<int> _getCursor() async {
    final v = await DatabaseService.instance.getSyncState(_syncCursorKey);
    return int.tryParse((v ?? '').trim()) ?? 0;
  }

  static Future<void> _setCursor(int cursor) async {
    await DatabaseService.instance.setSyncState(_syncCursorKey, cursor.toString());
  }

  static Future<void> ensureBackendSession({
    required AuthProvider auth,
  }) async {
    final idToken = await auth.getIdToken();
    if (idToken == null || idToken.trim().isEmpty) {
      _log('ensureBackendSession: missing idToken');
      return;
    }

    final deviceId = await DatabaseService.instance.deviceId;
    final url = Uri.parse('${await _baseUrl()}/auth/google');
    _log('auth: POST $url');
    final resp = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'idToken': idToken, 'deviceId': deviceId}),
    );
    _log('auth: status=${resp.statusCode}');
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Auth backend failed (${resp.statusCode}): ${resp.body}');
    }

    final decoded = (jsonDecode(resp.body) as Map).cast<String, dynamic>();
    final token = (decoded['token']?.toString() ?? '').trim();
    if (token.isNotEmpty) {
      await _setJwt(token);
      _log('auth: jwt stored');
    }
  }

  static Future<void> syncNow({
    required AuthProvider auth,
    bool allowBackoff = false,
  }) async {
    if (_syncInFlight) return;
    if (allowBackoff) {
      final nextAt = _nextAllowedAttemptAt;
      if (nextAt != null && DateTime.now().isBefore(nextAt)) {
        return;
      }
      if (!await _hasNetwork()) return;
    }

    _syncInFlight = true;
    final startedAt = DateTime.now();
    try {
      _log('syncNow: start allowBackoff=$allowBackoff baseUrl=${await _baseUrl()}');
      await _logDb(action: 'sync_start');
      await ensureBackendSession(auth: auth);
      final jwt = await _getJwt();
      if (jwt == null) {
        _log('syncNow: no jwt, abort');
        return;
      }

      final deviceId = await DatabaseService.instance.deviceId;
      final cursorBefore = await _getCursor();
      _log('syncNow: deviceId=$deviceId cursor=$cursorBefore');

      await _enqueueOutboxFromUnsynced(deviceId: deviceId);
      await _pushOutbox(jwt: jwt, deviceId: deviceId);
      await _pullAndApply(jwt: jwt);

      _consecutiveFailures = 0;
      _nextAllowedAttemptAt = null;
      await _setLastSyncOk();
      final ms = DateTime.now().difference(startedAt).inMilliseconds;
      _log('syncNow: OK in ${ms}ms');
      await _logDb(action: 'sync_ok', details: 'ms=$ms');
    } catch (e) {
      _consecutiveFailures += 1;
      if (allowBackoff) {
        final delay = _computeBackoff(_consecutiveFailures);
        _nextAllowedAttemptAt = DateTime.now().add(delay);
      }

      try {
        await _setLastSyncError(e.toString());
      } catch (_) {
        // ignore
      }

      _log('syncNow: ERROR $e');
      await _logDb(action: 'sync_error', details: e.toString());
      rethrow;
    } finally {
      _syncInFlight = false;
    }
  }

  static Future<void> _enqueueOutboxFromUnsynced({required String deviceId}) async {
    final db = DatabaseService.instance.db;
    final uuid = const Uuid();
    final now = DateTime.now().toIso8601String();

    int enq = 0;

    Future<void> enqueueRow({required String entity, required String entityId, required Map<String, dynamic> payload, required String updatedAt}) async {
      // prevent duplicates for the same entity/entityId/updatedAt
      final exist = await db.query(
        'outbox',
        columns: ['id'],
        where: 'entity = ? AND entityId = ? AND op = ? AND clientUpdatedAt = ? AND status = 0',
        whereArgs: [entity, entityId, 'upsert', updatedAt],
        limit: 1,
      );
      if (exist.isNotEmpty) return;

      await db.insert('outbox', {
        'eventUuid': uuid.v4(),
        'entity': entity,
        'entityId': entityId,
        'op': 'upsert',
        'payloadJson': jsonEncode(payload),
        'clientUpdatedAt': updatedAt,
        'status': 0,
        'createdAt': now,
      });

      enq += 1;
    }

    Future<void> enqueueDelete({required String entity, required String entityId, required String deletedAt}) async {
      final exist = await db.query(
        'outbox',
        columns: ['id'],
        where: 'entity = ? AND entityId = ? AND op = ? AND clientUpdatedAt = ? AND status = 0',
        whereArgs: [entity, entityId, 'delete', deletedAt],
        limit: 1,
      );
      if (exist.isNotEmpty) return;

      await db.insert('outbox', {
        'eventUuid': uuid.v4(),
        'entity': entity,
        'entityId': entityId,
        'op': 'delete',
        'payloadJson': null,
        'clientUpdatedAt': deletedAt,
        'status': 0,
        'createdAt': now,
      });
    }

    // Entities with string IDs
    final tables = <String>[
      'products',
      'customers',
      'sales',
      'debts',
      'purchase_orders',
      'purchase_history',
      'expenses',
      'employees',
      'vietqr_bank_accounts',
    ];

    for (final t in tables) {
      final rows = await DatabaseService.instance.getUnsyncedRecords(t);
      for (final r in rows) {
        final id = (r['id']?.toString() ?? '').trim();
        if (id.isEmpty) continue;
        final updatedAt = (r['updatedAt']?.toString() ?? '').trim();
        if (updatedAt.isEmpty) continue;

        if (t == 'sales') {
          final items = await db.query('sale_items', where: 'saleId = ?', whereArgs: [id]);
          final payload = {
            ...r,
            'items': items,
          };
          await enqueueRow(entity: 'sales', entityId: id, payload: payload, updatedAt: updatedAt);
        } else {
          await enqueueRow(entity: t, entityId: id, payload: r, updatedAt: updatedAt);
        }
      }
    }

    // debt_payments use uuid as entityId
    final paymentRows = await DatabaseService.instance.getUnsyncedRecords('debt_payments');
    for (final r in paymentRows) {
      final pid = (r['uuid']?.toString() ?? '').trim();
      if (pid.isEmpty) continue;
      final updatedAt = (r['updatedAt']?.toString() ?? '').trim();
      if (updatedAt.isEmpty) continue;
      await enqueueRow(entity: 'debt_payments', entityId: pid, payload: r, updatedAt: updatedAt);
    }

    // deletions
    final deletions = await DatabaseService.instance.getUnsyncedDeletions();
    for (final d in deletions) {
      final entity = (d['entityType']?.toString() ?? '').trim();
      final entityId = (d['entityId']?.toString() ?? '').trim();
      final deletedAt = (d['deletedAt']?.toString() ?? '').trim();
      if (entity.isEmpty || entityId.isEmpty || deletedAt.isEmpty) continue;

      // sale_items are embedded in sales
      if (entity == 'sale_items') continue;

      await enqueueDelete(entity: entity, entityId: entityId, deletedAt: deletedAt);
    }

    _log('enqueue: added=$enq');
  }

  static Future<void> _pushOutbox({required String jwt, required String deviceId}) async {
    final db = DatabaseService.instance.db;
    final rows = await db.query('outbox', where: 'status = 0', orderBy: 'id ASC', limit: 500);
    if (rows.isEmpty) {
      _log('push: outbox empty');
      return;
    }

    final events = rows.map((r) {
      final payloadJson = r['payloadJson'] as String?;
      return {
        'eventUuid': r['eventUuid'],
        'entity': r['entity'],
        'entityId': r['entityId'],
        'op': r['op'],
        'payload': payloadJson == null ? null : jsonDecode(payloadJson),
        'clientUpdatedAt': r['clientUpdatedAt'],
      };
    }).toList();

    final url = Uri.parse('${await _baseUrl()}/sync/push');
    _log('push: POST $url events=${events.length}');
    final resp = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwt',
      },
      body: jsonEncode({'deviceId': deviceId, 'events': events}),
    );

    _log('push: status=${resp.statusCode}');

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Sync push failed (${resp.statusCode}): ${resp.body}');
    }

    // Mark sent + mark entities as synced
    final ids = rows.map((e) => e['id'] as int).toList();
    final batch = db.batch();
    final now = DateTime.now().toIso8601String();
    for (final id in ids) {
      batch.update('outbox', {'status': 1}, where: 'id = ?', whereArgs: [id]);
    }

    // mark tables isSynced=1 based on pushed outbox content
    final byEntity = <String, List<String>>{};
    final deletions = <Map<String, String>>[];
    for (final r in rows) {
      final entity = (r['entity'] as String).trim();
      final entityId = (r['entityId'] as String).trim();
      final op = (r['op'] as String).trim();
      if (op == 'upsert') {
        (byEntity[entity] ??= <String>[]).add(entityId);
      } else if (op == 'delete') {
        deletions.add({'entityType': entity, 'entityId': entityId});
      }
    }

    for (final e in byEntity.entries) {
      if (e.key == 'debt_payments') {
        batch.update('debt_payments', {'isSynced': 1}, where: 'uuid IN (${List.filled(e.value.length, '?').join(',')})', whereArgs: e.value);
      } else {
        batch.update(e.key, {'isSynced': 1}, where: 'id IN (${List.filled(e.value.length, '?').join(',')})', whereArgs: e.value);
      }
    }

    for (final d in deletions) {
      batch.update('deleted_entities', {'isSynced': 1}, where: 'entityType = ? AND entityId = ?', whereArgs: [d['entityType'], d['entityId']]);
    }

    // write a local sync log row if table exists
    try {
      batch.insert('sync_logs', {
        'action': 'push',
        'entityType': 'outbox',
        'entityId': null,
        'deviceId': deviceId,
        'timestamp': now,
        'details': 'pushed=${rows.length}',
      });
    } catch (_) {
      // ignore
    }

    await batch.commit(noResult: true);
    _log('push: committed outbox ids=${ids.length}');
  }

  static Future<void> _pullAndApply({required String jwt}) async {
    final cursor = await _getCursor();
    final url = Uri.parse('${await _baseUrl()}/sync/pull?cursor=$cursor&limit=2000');
    _log('pull: GET $url');
    final resp = await http.get(url, headers: {'Authorization': 'Bearer $jwt'});
    _log('pull: status=${resp.statusCode}');
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Sync pull failed (${resp.statusCode}): ${resp.body}');
    }

    final decoded = (jsonDecode(resp.body) as Map).cast<String, dynamic>();
    final newCursor = (decoded['cursor'] as num?)?.toInt() ?? cursor;
    final events = (decoded['events'] as List?)?.cast<dynamic>() ?? const [];

    _log('pull: cursor $cursor -> $newCursor events=${events.length}');

    final db = DatabaseService.instance.db;
    final localDeviceId = await DatabaseService.instance.deviceId;

    int skippedApplied = 0;
    int skippedEcho = 0;
    int applied = 0;
    int applyErrors = 0;

    Future<bool> alreadyAppliedEvent(String eventUuid) async {
      final id = eventUuid.trim();
      if (id.isEmpty) return false;
      try {
        final rows = await db.query(
          'applied_sync_events',
          columns: ['eventUuid'],
          where: 'eventUuid = ?',
          whereArgs: [id],
          limit: 1,
        );
        return rows.isNotEmpty;
      } catch (_) {
        return false;
      }
    }

    Future<void> markAppliedEvent(String eventUuid) async {
      final id = eventUuid.trim();
      if (id.isEmpty) return;
      try {
        await db.insert(
          'applied_sync_events',
          {'eventUuid': id, 'appliedAt': DateTime.now().toIso8601String()},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      } catch (_) {
        // ignore
      }
    }

    for (final evRaw in events) {
      if (evRaw is! Map) continue;
      final ev = evRaw.cast<String, dynamic>();
      final eventUuid = (ev['event_uuid']?.toString() ?? ev['eventUuid']?.toString() ?? '').trim();
      final deviceId = (ev['device_id']?.toString() ?? '').trim();
      final entity = (ev['entity']?.toString() ?? '').trim();
      final entityId = (ev['entity_id']?.toString() ?? '').trim();
      final op = (ev['op']?.toString() ?? '').trim();
      final clientUpdatedAt = (ev['client_updated_at']?.toString() ?? '').trim();
      final payload = ev['payload'];

      if (eventUuid.isNotEmpty && await alreadyAppliedEvent(eventUuid)) {
        skippedApplied += 1;
        continue;
      }

      // ignore own echo
      if (deviceId.isNotEmpty && deviceId == localDeviceId) {
        skippedEcho += 1;
        continue;
      }

      if (entity.isEmpty || entityId.isEmpty || op.isEmpty) continue;

      if (op == 'delete') {
        // mirror deletion locally
        try {
          if (entity == 'debt_payments') {
            await db.delete('debt_payments', where: 'uuid = ?', whereArgs: [entityId]);
          } else if (entity == 'sale_items') {
            // ignore (embedded)
          } else {
            await db.delete(entity, where: 'id = ?', whereArgs: [entityId]);
          }
        } catch (_) {
          // ignore
        }

        try {
          await db.insert(
            'deleted_entities',
            {
              'entityType': entity,
              'entityId': entityId,
              'deletedAt': clientUpdatedAt.isEmpty ? DateTime.now().toIso8601String() : clientUpdatedAt,
              'deviceId': deviceId.isEmpty ? 'remote' : deviceId,
              'isSynced': 1,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } catch (_) {}

        if (eventUuid.isNotEmpty) {
          await markAppliedEvent(eventUuid);
        }

        applied += 1;

        continue;
      }

      if (op != 'upsert') continue;
      if (payload is! Map) continue;
      final p = payload.cast<String, dynamic>();

      // LWW compare updatedAt
      Future<bool> shouldApply({required String table, required String idColumn, required String idValue, required String remoteUpdatedAt}) async {
        try {
          final rows = await db.query(table, columns: ['updatedAt'], where: '$idColumn = ?', whereArgs: [idValue], limit: 1);
          if (rows.isEmpty) return true;
          final local = (rows.first['updatedAt']?.toString() ?? '').trim();
          if (local.isEmpty) return true;
          return remoteUpdatedAt.compareTo(local) > 0;
        } catch (_) {
          return true;
        }
      }

      if (entity == 'sales') {
        try {
          final remoteUpdatedAt = (p['updatedAt']?.toString() ?? '').trim();
          if (remoteUpdatedAt.isEmpty) continue;
          final ok = await shouldApply(table: 'sales', idColumn: 'id', idValue: entityId, remoteUpdatedAt: remoteUpdatedAt);
          if (!ok) {
            _log('apply sales: skip LWW id=$entityId remoteUpdatedAt=$remoteUpdatedAt');
            continue;
          }

          // apply sale
          await db.insert(
            'sales',
            {
              ...p,
              'id': entityId,
              'isSynced': 1,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          // apply items
          final items = (p['items'] is List) ? (p['items'] as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : <Map<String, dynamic>>[];
          await db.transaction((txn) async {
            await txn.delete('sale_items', where: 'saleId = ?', whereArgs: [entityId]);
            for (final it in items) {
              final toInsert = Map<String, dynamic>.from(it);
              toInsert.remove('id');
              toInsert['saleId'] = entityId;
              toInsert['isSynced'] = 1;
              await txn.insert('sale_items', toInsert);
            }
          });

          if (eventUuid.isNotEmpty) {
            await markAppliedEvent(eventUuid);
          }
          applied += 1;
        } catch (e) {
          applyErrors += 1;
          _log('apply sales: ERROR eventUuid=$eventUuid id=$entityId err=$e');
        }
        continue;
      }

      if (entity == 'debt_payments') {
        try {
          final remoteUpdatedAt = (p['updatedAt']?.toString() ?? '').trim();
          if (remoteUpdatedAt.isEmpty) continue;
          final ok = await shouldApply(table: 'debt_payments', idColumn: 'uuid', idValue: entityId, remoteUpdatedAt: remoteUpdatedAt);
          if (!ok) {
            _log('apply debt_payments: skip LWW uuid=$entityId remoteUpdatedAt=$remoteUpdatedAt');
            continue;
          }

          final toInsert = Map<String, dynamic>.from(p);
          toInsert['uuid'] = entityId;
          toInsert['isSynced'] = 1;
          await db.insert('debt_payments', toInsert, conflictAlgorithm: ConflictAlgorithm.replace);

          if (eventUuid.isNotEmpty) {
            await markAppliedEvent(eventUuid);
          }
          applied += 1;
        } catch (e) {
          applyErrors += 1;
          _log('apply debt_payments: ERROR eventUuid=$eventUuid uuid=$entityId err=$e');
        }
        continue;
      }

      try {
        final remoteUpdatedAt = (p['updatedAt']?.toString() ?? '').trim();
        if (remoteUpdatedAt.isEmpty) continue;
        final ok = await shouldApply(table: entity, idColumn: 'id', idValue: entityId, remoteUpdatedAt: remoteUpdatedAt);
        if (!ok) {
          _log('apply $entity: skip LWW id=$entityId remoteUpdatedAt=$remoteUpdatedAt');
          continue;
        }

        final toInsert = Map<String, dynamic>.from(p);
        toInsert['id'] = entityId;
        toInsert['isSynced'] = 1;
        await db.insert(entity, toInsert, conflictAlgorithm: ConflictAlgorithm.replace);

        if (eventUuid.isNotEmpty) {
          await markAppliedEvent(eventUuid);
        }
        applied += 1;
      } catch (e) {
        applyErrors += 1;
        _log('apply $entity: ERROR eventUuid=$eventUuid id=$entityId err=$e');
      }
    }

    await _setCursor(newCursor);
    _log('pull/apply: applied=$applied skipped_applied=$skippedApplied skipped_echo=$skippedEcho errors=$applyErrors');
  }
}
