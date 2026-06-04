// Unit tests for DeviceService — the component that stores the paired Device
// ID and builds the Firebase path used by every screen. SharedPreferences is
// mocked so the tests run without a real device or backend.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bettank/services/device_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceService', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DeviceService.init();
    });

    test('saving a Device ID persists it and marks the app configured', () async {
      await DeviceService.setDeviceId('bettank_DD30');
      expect(DeviceService.deviceId, 'bettank_DD30');
      expect(DeviceService.isConfigured, isTrue);
    });

    test('basePath() builds the correct Firebase node for the device', () async {
      await DeviceService.setDeviceId('bettank_DD30');
      expect(DeviceService.basePath(), '/devices/bettank_DD30');
    });

    test('clearing the Device ID logs the device out', () async {
      await DeviceService.setDeviceId('bettank_DD30');
      await DeviceService.clearDeviceId();
      expect(DeviceService.isConfigured, isFalse);
    });

    test('a saved Device ID survives an app restart', () async {
      await DeviceService.setDeviceId('bettank_AA11');
      // simulate a fresh launch: re-read persisted prefs
      await DeviceService.init();
      expect(DeviceService.deviceId, 'bettank_AA11');
      expect(DeviceService.isConfigured, isTrue);
    });
  });
}
