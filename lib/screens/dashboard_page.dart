import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_database/firebase_database.dart';

import '../utils/app_colors.dart';
import '../utils/water_quality.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/pump_status_row.dart';
import '../widgets/sensor_card.dart';
import '../services/device_service.dart';

// ─── value helpers ────────────────────────────────────────────────────────────

double? _parseDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

String _fmtNum(dynamic v, {int d = 1}) {
  final n = _parseDouble(v);
  return n == null ? '--' : n.toStringAsFixed(d);
}

// Water-quality classification rules live in WaterQuality (lib/utils/water_quality.dart)
// so they can be unit-tested independently of the UI.

// ─── page ─────────────────────────────────────────────────────────────────────

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final Stream<DatabaseEvent> _deviceStream;
  double? _lastValidTds;

  @override
  void initState() {
    super.initState();
    _deviceStream =
        FirebaseDatabase.instance.ref(DeviceService.basePath()).onValue;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7FF),
      appBar: _buildAppBar(),
      body: StreamBuilder<DatabaseEvent>(
        stream: _deviceStream,
        builder: (context, snapshot) {
          final root = snapshot.data?.snapshot;
          final sensors = root?.child('sensors');
          final lastCycleStr =
              root?.child('status').child('lastCycleStr').value?.toString();
          final tsRaw = sensors?.child('ts').value;
          final ts = tsRaw is int
              ? tsRaw
              : int.tryParse(tsRaw?.toString() ?? '');

          return SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildGreetingHeader(ts),
                const SizedBox(height: 20),
                _buildSensorGrid(sensors),
                const SizedBox(height: 20),
                _buildWaterConditionCard(sensors),
                const SizedBox(height: 20),
                _buildPumpActivityCard(sensors, lastCycleStr),
                const SizedBox(height: 20),
                _buildAlertStatusCard(sensors),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: const BetankBottomNav(currentIndex: 0),
    );
  }

  // ── app bar ────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.darkNavy,
      elevation: 0,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          Image.asset('assets/images/BETTANKlogo.png',
              width: 32, height: 32, fit: BoxFit.contain),
          const SizedBox(width: 10),
          Text(
            'BETTANK',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.white,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined,
              color: AppColors.white),
          onPressed: () {},
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  // ── greeting ───────────────────────────────────────────────────────────────

  Widget _buildGreetingHeader(int? ts) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final isLive = ts != null && (now - ts) <= 30;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hello, Betta Keeper 👋',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppColors.darkNavy,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isLive ? Colors.green : AppColors.darkGrey,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              isLive ? 'Live · Updated just now' : 'Not updating · Offline',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppColors.darkGrey,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── sensor grid ────────────────────────────────────────────────────────────

  Widget _buildSensorGrid(DataSnapshot? sensors) {
    final ph = _parseDouble(sensors?.child('ph').value);
    final temp = _parseDouble(sensors?.child('temp').value);
    final rawTds = _parseDouble(sensors?.child('tds').value);
    if (rawTds != null && rawTds > 0) _lastValidTds = rawTds;
    final tds = rawTds ?? _lastValidTds;
    final turb = _parseDouble(sensors?.child('turbNTU').value);

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 14,
      mainAxisSpacing: 14,
      childAspectRatio: 1.15,
      children: [
        SensorCard(
          title: 'pH Level',
          value: _fmtNum(ph),
          unit: 'pH',
          label: WaterQuality.phLabel(ph),
          icon: Icons.science_outlined,
          labelColor: WaterQuality.phColor(ph),
        ),
        SensorCard(
          title: 'Temperature',
          value: _fmtNum(temp),
          unit: '°C',
          label: WaterQuality.tempLabel(temp),
          icon: Icons.thermostat_outlined,
          labelColor: WaterQuality.tempColor(temp),
        ),
        SensorCard(
          title: 'TDS',
          value: _fmtNum(tds, d: 0),
          unit: 'ppm',
          label: WaterQuality.tdsLabel(tds),
          icon: Icons.water_drop_outlined,
          labelColor: WaterQuality.tdsColor(tds),
        ),
        SensorCard(
          title: 'Turbidity',
          value: _fmtNum(turb, d: 0),
          unit: 'NTU',
          label: WaterQuality.turbLabel(turb),
          icon: Icons.blur_on_outlined,
          labelColor: WaterQuality.turbColor(turb),
        ),
      ],
    );
  }

  // ── water condition ────────────────────────────────────────────────────────

  Widget _buildWaterConditionCard(DataSnapshot? sensors) {
    final state = sensors?.child('waterState').value?.toString();

    final Color stateColor;
    final IconData stateIcon;
    final String stateText;

    switch (state) {
      case 'GOOD':
        stateColor = Colors.green;
        stateIcon = Icons.check_circle_outline;
        stateText = 'Overall: Good';
        break;
      case 'WARNING':
        stateColor = const Color(0xFFE67E22);
        stateIcon = Icons.warning_amber_rounded;
        stateText = 'Overall: Warning';
        break;
      case 'BAD':
        stateColor = AppColors.red;
        stateIcon = Icons.error_outline;
        stateText = 'Overall: Bad';
        break;
      default:
        stateColor = AppColors.darkGrey;
        stateIcon = Icons.help_outline;
        stateText = state == null ? 'Overall: Loading…' : 'Overall: Unknown';
    }

    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkNavy.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: stateColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(stateIcon, color: stateColor, size: 26),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Water Condition',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppColors.darkGrey,
                  fontWeight: FontWeight.w400,
                ),
              ),
              Text(
                stateText,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  color: stateColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── pump activity ──────────────────────────────────────────────────────────

Widget _buildPumpActivityCard(DataSnapshot? sensors, String? lastCycleStr) {
    final pumpState =
        sensors?.child('pumpState').value?.toString() ?? 'IDLE';

    final isDraining = pumpState == 'DRAINING';
    final isFilling = pumpState == 'FILLING';
    const idleGrey = Color(0xFFBDBDBD);

    final drainDot = isDraining ? AppColors.red : idleGrey;
    final drainStatus = isDraining ? 'DRAINING' : 'Idle';

    final fillDot = isFilling ? Colors.green : idleGrey;
    final fillStatus = isFilling ? 'FILLING' : 'Idle';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkNavy.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.autorenew,
                  size: 18, color: AppColors.midBlue),
              const SizedBox(width: 8),
              Text(
                'Pump Activity',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkNavy,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.lightBlue,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Auto Replacement',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: AppColors.darkNavy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Divider(color: Color(0xFFEEEEEE)),
          PumpStatusRow(
              label: 'Drain Pump',
              status: drainStatus,
              dotColor: drainDot),
          const Divider(color: Color(0xFFEEEEEE), height: 1),
          PumpStatusRow(
              label: 'Fill Pump',
              status: fillStatus,
              dotColor: fillDot),
        ],
      ),
    );
  }

  // ── alert status ───────────────────────────────────────────────────────────

  Widget _buildAlertStatusCard(DataSnapshot? sensors) {
    final temp = _parseDouble(sensors?.child('temp').value);
    final liveTds = _parseDouble(sensors?.child('tds').value);
    final tds = (liveTds != null && liveTds > 0) ? liveTds : _lastValidTds;
    final turb = _parseDouble(sensors?.child('turbNTU').value);
    final ph = _parseDouble(sensors?.child('ph').value);

    final tiles = <_SensorAlertTile>[];

    if (temp != null) {
      final isWarn = WaterQuality.tempIsAlert(temp);
      tiles.add(_SensorAlertTile(
        isWarning: isWarn,
        sensorName: 'Temperature',
        subtitle: isWarn
            ? (temp > 30 ? 'Above threshold' : 'Below threshold')
            : 'Within safe range',
        rangeText: isWarn
            ? '${_fmtNum(temp)} °C • limit 24–30 °C'
            : '${_fmtNum(temp)} °C • 24–30 °C',
      ));
    }

    if (tds != null) {
      final isWarn = WaterQuality.tdsIsAlert(tds);
      tiles.add(_SensorAlertTile(
        isWarning: isWarn,
        sensorName: 'TDS',
        subtitle: isWarn ? 'Above threshold' : 'Within safe range',
        rangeText: '${_fmtNum(tds, d: 0)} ppm • limit 500 ppm',
      ));
    }

    if (turb != null) {
      final isWarn = WaterQuality.turbIsAlert(turb);
      tiles.add(_SensorAlertTile(
        isWarning: isWarn,
        sensorName: 'Turbidity',
        subtitle: isWarn ? 'Above threshold' : 'Within safe range',
        rangeText: '${_fmtNum(turb, d: 0)} NTU • limit 100 NTU',
      ));
    }

    if (ph != null) {
      final isWarn = WaterQuality.phIsAlert(ph);
      tiles.add(_SensorAlertTile(
        isWarning: isWarn,
        sensorName: 'pH',
        subtitle: isWarn
            ? (ph > 7.5 ? 'Above threshold' : 'Below threshold')
            : 'Within safe range',
        rangeText: '${_fmtNum(ph)} pH • 6.5–7.5',
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Alert Status',
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.darkNavy,
          ),
        ),
        const SizedBox(height: 12),
        if (tiles.isEmpty)
          _AlertTile(
            icon: Icons.check_circle_outline,
            iconColor: Colors.green,
            borderColor: Colors.green,
            bgColor: Colors.green.withValues(alpha: 0.05),
            title: 'No Active Alerts',
            subtitle: 'Water parameters are within normal range',
            badgeText: 'OK',
            badgeColor: Colors.green,
          )
        else
          ...tiles.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: t,
            ),
          ),
      ],
    );
  }
}

// ─── sensor alert tile ────────────────────────────────────────────────────────

class _SensorAlertTile extends StatelessWidget {
  final bool isWarning;
  final String sensorName;
  final String subtitle;
  final String rangeText;

  const _SensorAlertTile({
    required this.isWarning,
    required this.sensorName,
    required this.subtitle,
    required this.rangeText,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        isWarning ? const Color(0xFFE67E22) : Colors.green;
    final icon = isWarning
        ? Icons.notifications_outlined
        : Icons.check_circle_outline;
    final title = isWarning ? '$sensorName Warning' : '$sensorName OK';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkNavy,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: AppColors.darkGrey,
                  ),
                ),
              ],
            ),
          ),
          Text(
            rangeText,
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── alert tile ───────────────────────────────────────────────────────────────

class _AlertTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color borderColor;
  final Color bgColor;
  final String title;
  final String subtitle;
  final String badgeText;
  final Color badgeColor;

  const _AlertTile({
    required this.icon,
    required this.iconColor,
    required this.borderColor,
    required this.bgColor,
    required this.title,
    required this.subtitle,
    required this.badgeText,
    required this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: borderColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkNavy,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: AppColors.darkGrey),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              badgeText,
              style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
