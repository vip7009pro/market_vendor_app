import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_provider.dart';
import 'drive_sync_service.dart';

class DriveBackupScheduler {
  static DriveBackupScheduler? _instance;
  DriveBackupScheduler._();

  factory DriveBackupScheduler() {
    _instance ??= DriveBackupScheduler._();
    return _instance!;
  }

  static const _slotNoon = 'noon';
  static const _slotEvening = 'evening';
  static const _slotNight = 'night';

  static const _prefLastRunPrefix = 'drive_backup_last_run_';

  Timer? _timer;
  bool _started = false;

  void start(BuildContext context) {
    if (_started) return;
    _started = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      scheduleMicrotask(() async {
        await runIfDue(context);
        _scheduleNext(context);
      });
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  Future<void> runIfDue(BuildContext context) async {
    if (!context.mounted) return;

    final auth = context.read<AuthProvider>();
    if (!auth.isSignedIn) return;

    final token = await auth.getAccessToken();
    if (token == null || token.isEmpty) return;

    final now = DateTime.now();

    final slots = <_BackupSlot>[
      _BackupSlot(key: _slotNoon, hour: 12, minute: 0),
      _BackupSlot(key: _slotEvening, hour: 19, minute: 0),
      _BackupSlot(key: _slotNight, hour: 2, minute: 0),
    ];

    final prefs = await SharedPreferences.getInstance();

    final dueSlots = <_BackupSlot>[];
    for (final slot in slots) {
      final slotTime = slot.timeFor(now);
      if (now.isBefore(slotTime)) continue;

      final lastRunMs = prefs.getInt('$_prefLastRunPrefix${slot.key}');
      final lastRun = lastRunMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastRunMs);

      if (lastRun == null || lastRun.isBefore(slotTime)) {
        dueSlots.add(slot);
      }
    }

    dueSlots.sort((a, b) => a.timeFor(now).compareTo(b.timeFor(now)));

    for (final slot in dueSlots) {
      try {
        await DriveSyncService().uploadLocalDb(accessToken: token);
        await prefs.setInt(
          '$_prefLastRunPrefix${slot.key}',
          DateTime.now().millisecondsSinceEpoch,
        );
      } catch (e) {
        debugPrint('Auto backup failed (${slot.key}): $e');
      }
    }

    await _cleanupOldBackups(accessToken: token, keepDays: 30);
  }

  void _scheduleNext(BuildContext context) {
    _timer?.cancel();

    final now = DateTime.now();
    final next = _nextRunTime(now);
    final delay = next.difference(now);

    _timer = Timer(delay, () async {
      try {
        if (!context.mounted) return;
        await runIfDue(context);
      } catch (e) {
        debugPrint('Auto backup timer error: $e');
      } finally {
        if (context.mounted) {
          _scheduleNext(context);
        }
      }
    });
  }

  DateTime _nextRunTime(DateTime now) {
    final candidates = <DateTime>[
      DateTime(now.year, now.month, now.day, 12, 0),
      DateTime(now.year, now.month, now.day, 19, 0),
      DateTime(now.year, now.month, now.day, 2, 0),
    ];

    candidates.sort();

    for (final t in candidates) {
      if (t.isAfter(now)) return t;
    }

    // next day first slot
    final tomorrow = now.add(const Duration(days: 1));
    final nextCandidates = <DateTime>[
      DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 2, 0),
      DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 12, 0),
      DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 19, 0),
    ]..sort();

    return nextCandidates.first;
  }

  Future<void> _cleanupOldBackups({required String accessToken, required int keepDays}) async {
    try {
      final files = await DriveSyncService().listBackups(accessToken: accessToken);
      if (files.isEmpty) return;

      final cutoff = DateTime.now().subtract(Duration(days: keepDays));

      for (final f in files) {
        final id = (f['id'] ?? '').trim();
        if (id.isEmpty) continue;

        final modifiedTimeRaw = (f['modifiedTime'] ?? '').trim();
        DateTime? modified;
        if (modifiedTimeRaw.isNotEmpty) {
          try {
            modified = DateTime.parse(modifiedTimeRaw).toLocal();
          } catch (_) {
            modified = null;
          }
        }

        if (modified != null && modified.isBefore(cutoff)) {
          try {
            await DriveSyncService().deleteFile(accessToken: accessToken, fileId: id);
          } catch (e) {
            debugPrint('Delete old backup failed ($id): $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Cleanup old backups failed: $e');
    }
  }
}

class _BackupSlot {
  final String key;
  final int hour;
  final int minute;

  const _BackupSlot({required this.key, required this.hour, required this.minute});

  DateTime timeFor(DateTime ref) {
    return DateTime(ref.year, ref.month, ref.day, hour, minute);
  }
}
