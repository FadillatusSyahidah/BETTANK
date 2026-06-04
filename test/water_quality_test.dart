// Unit tests for the water-quality evaluation rules (WaterQuality).
//
// These tests verify that BETTANK correctly classifies each sensor reading
// for Betta splendens against its safe range, and correctly decides when a
// reading should raise an alert. This is the core decision logic that drives
// the dashboard status labels and the automatic alert card.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bettank/utils/water_quality.dart';
import 'package:bettank/utils/app_colors.dart';

void main() {
  group('pH classification (safe range 6.5 – 7.5)', () {
    test('value inside range is "stable" and green', () {
      expect(WaterQuality.phLabel(7.0), 'stable');
      expect(WaterQuality.phColor(7.0), Colors.green);
      expect(WaterQuality.phIsAlert(7.0), isFalse);
    });
    test('lower boundary 6.5 is still stable', () {
      expect(WaterQuality.phLabel(6.5), 'stable');
      expect(WaterQuality.phIsAlert(6.5), isFalse);
    });
    test('upper boundary 7.5 is still stable', () {
      expect(WaterQuality.phLabel(7.5), 'stable');
      expect(WaterQuality.phIsAlert(7.5), isFalse);
    });
    test('below range is "low pH", red, and an alert', () {
      expect(WaterQuality.phLabel(6.0), 'low pH');
      expect(WaterQuality.phColor(6.0), AppColors.red);
      expect(WaterQuality.phIsAlert(6.0), isTrue);
    });
    test('above range is "high pH", red, and an alert', () {
      expect(WaterQuality.phLabel(8.2), 'high pH');
      expect(WaterQuality.phColor(8.2), AppColors.red);
      expect(WaterQuality.phIsAlert(8.2), isTrue);
    });
    test('null reading shows placeholder', () {
      expect(WaterQuality.phLabel(null), '--');
      expect(WaterQuality.phColor(null), AppColors.darkGrey);
    });
  });

  group('Temperature classification (optimal 24 – 28 °C, alert <24 or >30)', () {
    test('value inside optimal band is "optimal"', () {
      expect(WaterQuality.tempLabel(26.0), 'optimal');
      expect(WaterQuality.tempColor(26.0), AppColors.midBlue);
      expect(WaterQuality.tempIsAlert(26.0), isFalse);
    });
    test('below optimal is "too cold"', () {
      expect(WaterQuality.tempLabel(22.0), 'too cold');
      expect(WaterQuality.tempColor(22.0), AppColors.red);
    });
    test('above optimal is "too warm"', () {
      expect(WaterQuality.tempLabel(29.0), 'too warm');
    });
    test('29–30 °C is "too warm" but NOT yet an alert', () {
      // alert band is wider than the optimal-label band
      expect(WaterQuality.tempLabel(29.5), 'too warm');
      expect(WaterQuality.tempIsAlert(29.5), isFalse);
    });
    test('above 30 °C is an alert', () {
      expect(WaterQuality.tempIsAlert(31.0), isTrue);
    });
    test('below 24 °C is an alert', () {
      expect(WaterQuality.tempIsAlert(23.0), isTrue);
    });
  });

  group('TDS classification (safe < 500 ppm)', () {
    test('< 300 ppm is "good"', () {
      expect(WaterQuality.tdsLabel(250), 'good');
      expect(WaterQuality.tdsColor(250), Colors.green);
    });
    test('300–499 ppm is "slightly high"', () {
      expect(WaterQuality.tdsLabel(400), 'slightly high');
    });
    test('>= 500 ppm is "high"', () {
      expect(WaterQuality.tdsLabel(600), 'high');
      expect(WaterQuality.tdsColor(600), AppColors.red);
    });
    test('only > 500 ppm raises an alert', () {
      expect(WaterQuality.tdsIsAlert(500), isFalse);
      expect(WaterQuality.tdsIsAlert(501), isTrue);
    });
  });

  group('Turbidity classification (safe < 100 NTU)', () {
    test('< 50 NTU is "clear"', () {
      expect(WaterQuality.turbLabel(20), 'clear');
      expect(WaterQuality.turbColor(20), Colors.green);
    });
    test('50–99 NTU is "moderate"', () {
      expect(WaterQuality.turbLabel(75), 'moderate');
    });
    test('>= 100 NTU is "turbid"', () {
      expect(WaterQuality.turbLabel(120), 'turbid');
    });
    test('only > 100 NTU raises an alert (triggers water change)', () {
      expect(WaterQuality.turbIsAlert(100), isFalse);
      expect(WaterQuality.turbIsAlert(101), isTrue);
    });
  });
}
