import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';

import '../main.dart';
import '../models/debt.dart';
import '../screens/debt_detail_screen.dart';
import 'database_service.dart';

class DebtReminderService {
  static final DebtReminderService instance = DebtReminderService._();
  DebtReminderService._();

  final FlutterLocalNotificationsPlugin _noti = FlutterLocalNotificationsPlugin();

  static const String _channelId = 'debt_reminder_channel';
  static const String _channelName = 'Nhắc nợ';

  static const String _actionLater = 'DEBT_LATER';
  static const String _actionMute = 'DEBT_MUTE';

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);

    await _noti.initialize(
      settings,
      onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: _onDidReceiveNotificationResponse,
    );

    // Android 13+ requires runtime notification permission
    await _noti
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    const androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Nhắc nợ đến hạn hoặc quá 7 ngày',
      importance: Importance.max,
    );

    await _noti
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  Future<void> checkAndNotify() async {
    final debts = await DatabaseService.instance.getDebtsToRemind();
    if (debts.isEmpty) return;

    for (final d in debts) {
      await _showDebtNotification(d);
      await DatabaseService.instance.markDebtNotifiedToday(d.id);
    }
  }

  int _notificationIdForDebt(String debtId) {
    // stable int id
    return debtId.hashCode & 0x7fffffff;
  }

  Future<void> _showDebtNotification(Debt debt) async {
    final title = 'Nhắc nợ: ${debt.partyName}';

    final moneyFmt = NumberFormat.currency(locale: 'vi_VN', symbol: '₫', decimalDigits: 0);

    final dueStr = debt.dueDate != null
        ? 'Đến hạn: ${debt.dueDate!.day.toString().padLeft(2, '0')}/${debt.dueDate!.month.toString().padLeft(2, '0')}/${debt.dueDate!.year}'
        : 'Quá 7 ngày';

    final body = '$dueStr • Còn nợ: ${moneyFmt.format(debt.amount)}';

    final payload = jsonEncode({'debtId': debt.id});

    final android = AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher_monochrome',
      category: AndroidNotificationCategory.reminder,
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction(_actionLater, 'Để sau'),
        AndroidNotificationAction(_actionMute, 'Tắt nhắc', showsUserInterface: false, cancelNotification: true),
      ],
    );

    await _noti.show(
      _notificationIdForDebt(debt.id),
      title,
      body,
      NotificationDetails(android: android),
      payload: payload,
    );
  }

  @pragma('vm:entry-point')
  static Future<void> _onDidReceiveNotificationResponse(NotificationResponse response) async {
    final payloadRaw = response.payload;
    String? debtId;
    if (payloadRaw != null && payloadRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(payloadRaw);
        if (decoded is Map) {
          debtId = decoded['debtId']?.toString();
        }
      } catch (_) {}
    }

    if (debtId == null || debtId.trim().isEmpty) return;

    // Handle actions
    final actionId = response.actionId;
    if (actionId == _actionMute) {
      await DatabaseService.instance.muteDebtReminder(debtId);
      return;
    }

    if (actionId == _actionLater) {
      await DatabaseService.instance.markDebtNotifiedToday(debtId);
      return;
    }

    // Default tap -> open detail
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;

    final debt = await DatabaseService.instance.getDebtById(debtId);
    if (debt == null) return;

    Navigator.of(ctx).push(
      MaterialPageRoute(builder: (_) => DebtDetailScreen(debt: debt)),
    );
  }
}
