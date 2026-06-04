// Smoke test: the water-quality rules (the system's core decision logic) are
// covered in detail in water_quality_test.dart. This file is intentionally
// kept minimal because the app's root widget initialises Firebase, which is
// not available in the unit-test environment.

import 'package:flutter_test/flutter_test.dart';
import 'package:bettank/utils/water_quality.dart';

void main() {
  test('WaterQuality is reachable from the app package', () {
    expect(WaterQuality.phLabel(7.0), 'stable');
  });
}
