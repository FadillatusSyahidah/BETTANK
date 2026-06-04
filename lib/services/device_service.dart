import 'package:shared_preferences/shared_preferences.dart';

class DeviceService {
  static const _key = 'device_id';
  static String? _deviceId;

  static String get deviceId => _deviceId ?? 'bettank_DD30';

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString(_key);
  }

  static Future<void> setDeviceId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, id);
    _deviceId = id;
  }

  static Future<void> clearDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    _deviceId = null;
  }

  static bool get isConfigured => _deviceId != null && _deviceId!.isNotEmpty;

  static String basePath() => '/devices/$deviceId';
}
