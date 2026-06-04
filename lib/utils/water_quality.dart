import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Centralised water-quality evaluation rules for *Betta splendens*.
///
/// Optimal / safe ranges:
///   • pH          : 6.5 – 7.5
///   • Temperature : 24 – 28 °C optimal  (alert if < 24 or > 30 °C)
///   • TDS         : < 500 ppm
///   • Turbidity   : < 100 NTU
///
/// These pure functions encapsulate the domain logic so the dashboard widgets
/// stay presentation-only and the rules can be unit-tested in isolation.
class WaterQuality {
  // ── pH ──────────────────────────────────────────────────────────────────
  static String phLabel(double? v) {
    if (v == null) return '--';
    if (v >= 6.5 && v <= 7.5) return 'stable';
    return v < 6.5 ? 'low pH' : 'high pH';
  }

  static Color phColor(double? v) {
    if (v == null) return AppColors.darkGrey;
    if (v >= 6.5 && v <= 7.5) return Colors.green;
    return AppColors.red;
  }

  /// True when pH is outside the safe range (drives the alert card).
  static bool phIsAlert(double v) => v < 6.5 || v > 7.5;

  // ── Temperature ─────────────────────────────────────────────────────────
  static String tempLabel(double? v) {
    if (v == null) return '--';
    if (v >= 24 && v <= 28) return 'optimal';
    return v < 24 ? 'too cold' : 'too warm';
  }

  static Color tempColor(double? v) {
    if (v == null) return AppColors.darkGrey;
    if (v >= 24 && v <= 28) return AppColors.midBlue;
    return AppColors.red;
  }

  /// Temperature alert band is wider than the "optimal" label band:
  /// a reading of 29–30 °C is shown as "too warm" but is not yet an alert.
  static bool tempIsAlert(double v) => v < 24 || v > 30;

  // ── TDS (ppm) ───────────────────────────────────────────────────────────
  static String tdsLabel(double? v) {
    if (v == null) return '--';
    if (v < 300) return 'good';
    if (v < 500) return 'slightly high';
    return 'high';
  }

  static Color tdsColor(double? v) {
    if (v == null) return AppColors.darkGrey;
    if (v < 300) return Colors.green;
    if (v < 500) return const Color(0xFFE67E22);
    return AppColors.red;
  }

  static bool tdsIsAlert(double v) => v > 500;

  // ── Turbidity (NTU) ───────────────────────────────────────────────────────
  static String turbLabel(double? v) {
    if (v == null) return '--';
    if (v < 50) return 'clear';
    if (v < 100) return 'moderate';
    return 'turbid';
  }

  static Color turbColor(double? v) {
    if (v == null) return AppColors.darkGrey;
    if (v < 50) return Colors.green;
    if (v < 100) return AppColors.midBlue;
    return const Color(0xFFE67E22);
  }

  static bool turbIsAlert(double v) => v > 100;
}
