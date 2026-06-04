import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_service.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static StreamSubscription<DatabaseEvent>? _sub;
  static const _lastTsKey = 'last_notif_ts';
  static int _lastTs = 0;

  static Future<void> init() async {
    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    final prefs = await SharedPreferences.getInstance();
    _lastTs = prefs.getInt(_lastTsKey) ?? 0;
  }

  static Future<void> startListening() async {
    _sub?.cancel();
    final ref = FirebaseDatabase.instance
        .ref('${DeviceService.basePath()}/notifications');

    // Fresh install — skip all historical notifications
    if (_lastTs == 0) {
      _lastTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastTsKey, _lastTs);
      debugPrint('[NotifService] Fresh install — skipping backlog, lastTs set to $_lastTs');
    }

    debugPrint('[NotifService] startListening → ${DeviceService.basePath()}/notifications | _lastTs=$_lastTs');

    _sub = ref.orderByChild('ts').limitToLast(1).onValue.listen(
      (event) async {
        final raw = event.snapshot.value;
        if (raw is! Map) return;

        final entry = raw.values.first;
        if (entry is! Map) return;

        final ts = (entry['ts'] is int)
            ? entry['ts'] as int
            : int.tryParse('${entry['ts']}') ?? 0;

        debugPrint('[NotifService] onValue latest ts=$ts _lastTs=$_lastTs');

        if (ts <= _lastTs) return;

        _lastTs = ts;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_lastTsKey, ts);

        final level = '${entry['level'] ?? 'info'}';
        final msg = '${entry['msg'] ?? ''}';

        debugPrint('[NotifService] showing notif → level=$level msg=$msg');
        await _show(level, msg, ts);
      },
      onError: (e) => debugPrint('[NotifService] error: $e'),
    );
  }

  static void stopListening() {
    _sub?.cancel();
    _sub = null;
  }

  static Future<void> _show(String level, String msg, int ts) async {
    final isCritical = level == 'critical';
    final title = switch (level) {
      'critical' => 'BETTANK – Critical Alert',
      'warning' => 'BETTANK – Warning',
      _ => 'BETTANK',
    };

    final androidDetails = AndroidNotificationDetails(
      'bettank_alerts',
      'BETTANK Alerts',
      channelDescription: 'Water quality and pump alerts',
      importance: isCritical ? Importance.max : Importance.high,
      priority: isCritical ? Priority.max : Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final notifId = ts % 100000; // safe positive int for Android
    debugPrint('[NotifService] _show id=$notifId title=$title');
    await _plugin.show(
      notifId,
      title,
      msg,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }
}
