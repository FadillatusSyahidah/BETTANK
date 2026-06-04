import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';

const _lastTsKey = 'last_notif_ts';
const _deviceIdKey = 'device_id';

@pragma('vm:entry-point')
void onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  debugPrint('[BGService] Starting...');

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  final prefs = await SharedPreferences.getInstance();
  int lastTs = prefs.getInt(_lastTsKey) ?? 0;
  final deviceId = prefs.getString(_deviceIdKey) ?? 'tank_001';

  // Fresh install — skip all historical notifications
  if (lastTs == 0) {
    lastTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await prefs.setInt(_lastTsKey, lastTs);
    debugPrint('[BGService] Fresh install — skipping backlog, lastTs set to $lastTs');
  }

  debugPrint('[BGService] deviceId=$deviceId lastTs=$lastTs');

  final plugin = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await plugin.initialize(const InitializationSettings(android: androidInit));

  final ref = FirebaseDatabase.instance
      .ref('/devices/$deviceId/notifications');

  ref.onChildAdded.listen(
    (event) async {
      final data = event.snapshot.value;
      if (data is! Map) return;

      final ts = (data['ts'] is int)
          ? data['ts'] as int
          : int.tryParse('${data['ts']}') ?? 0;

      if (ts <= lastTs) {
        debugPrint('[BGService] Skipping old ts=$ts');
        return;
      }
      lastTs = ts;
      await prefs.setInt(_lastTsKey, ts);

      final level = '${data['level'] ?? 'info'}';
      final msg = '${data['msg'] ?? ''}';

      debugPrint('[BGService] New notif → level=$level msg=$msg');

      final isCritical = level == 'critical';
      final title = switch (level) {
        'critical' => 'BETTANK – Critical Alert',
        'warning'  => 'BETTANK – Warning',
        _          => 'BETTANK',
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

      await plugin.show(
        ts % 100000,
        title,
        msg,
        NotificationDetails(android: androidDetails),
      );
    },
    onError: (e) => debugPrint('[BGService] listener error: $e'),
  );

  service.on('stop').listen((_) {
    service.stopSelf();
  });
}

class BackgroundNotificationService {
  static Future<void> init() async {
    // Create notification channel FIRST before starting service
    final plugin = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await plugin.initialize(const InitializationSettings(android: androidInit));

    const channel = AndroidNotificationChannel(
      'bettank_bg',
      'BETTANK Background Service',
      description: 'Keeps BETTANK monitoring running',
      importance: Importance.low,
    );
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    const alertChannel = AndroidNotificationChannel(
      'bettank_alerts',
      'BETTANK Alerts',
      description: 'Water quality and pump alerts',
      importance: Importance.high,
    );
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(alertChannel);

    final service = FlutterBackgroundService();

    // Stop any stale service instance from a previous run before reconfiguring
    if (await service.isRunning()) {
      service.invoke('stop');
      await Future.delayed(const Duration(milliseconds: 500));
    }

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onServiceStart,
        autoStart: true,
        isForegroundMode: false,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: onServiceStart,
      ),
    );

    await service.startService();
    debugPrint('[BGService] Service started');
  }
}
