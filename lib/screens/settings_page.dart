import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_database/firebase_database.dart';

import '../utils/app_colors.dart';
import '../widgets/bottom_nav_bar.dart';
import '../services/device_service.dart';
import '../services/notification_service.dart';
import 'onboarding_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Optimistic local state — Firebase stream keeps it in sync
  String _selectedMode = 'auto';
  bool _wifiResetDisabled = false;
  double _turbThreshold = 100.0;

  late final DatabaseReference _autoModeRef;
  late final DatabaseReference _wifiResetRef;
  late final DatabaseReference _turbThresholdRef;
  StreamSubscription<DatabaseEvent>? _modeSub;
  StreamSubscription<DatabaseEvent>? _turbSub;
  Timer? _wifiResetTimer;

  @override
  void initState() {
    super.initState();
    _autoModeRef = FirebaseDatabase.instance
        .ref('${DeviceService.basePath()}/config/autoMode');
    _wifiResetRef = FirebaseDatabase.instance
        .ref('${DeviceService.basePath()}/config/resetWiFi');
    _turbThresholdRef = FirebaseDatabase.instance
        .ref('${DeviceService.basePath()}/config/turbThreshold');

    _modeSub = _autoModeRef.onValue.listen((event) {
      final value = event.snapshot.value;
      if (value is bool && mounted) {
        setState(() => _selectedMode = value ? 'auto' : 'manual');
      }
    });

    _turbSub = _turbThresholdRef.onValue.listen((event) {
      final value = event.snapshot.value;
      if (value != null && mounted) {
        setState(() => _turbThreshold = (value as num).toDouble().clamp(10.0, 300.0));
      }
    });
  }

  @override
  void dispose() {
    _modeSub?.cancel();
    _turbSub?.cancel();
    _wifiResetTimer?.cancel();
    super.dispose();
  }

  void _setMode(String mode) {
    setState(() => _selectedMode = mode);
    _autoModeRef.set(mode == 'auto');
  }

  Future<void> _sendWifiReset() async {
    final confirmed = await _showWifiResetDialog();
    if (!confirmed || !mounted) return;

    await _wifiResetRef.set(true);

    setState(() => _wifiResetDisabled = true);
    // Keep button disabled for 3 min — ESP32 polls resetWiFi every 30 s,
    // then takes ~10 s to restart. Total worst-case ≈ 40 s; 3 min is safe.
    _wifiResetTimer = Timer(const Duration(minutes: 3), () {
      if (mounted) setState(() => _wifiResetDisabled = false);
    });

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.wifi_tethering_outlined, color: Colors.orange),
            const SizedBox(width: 10),
            Text(
              'BETTANK Rebooting',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppColors.darkNavy,
              ),
            ),
          ],
        ),
        content: Text(
          'Command sent! The device will restart within ~30 seconds.\n\n'
          '1. Wait for BETTANK_SETUP hotspot to appear\n'
          '2. Go to your phone WiFi settings\n'
          '3. Connect to  BETTANK_SETUP\n'
          '4. Open browser → 192.168.4.1\n'
          '5. Enter new WiFi credentials',
          style: GoogleFonts.poppins(fontSize: 13, color: AppColors.darkGrey),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.midBlue,
              foregroundColor: AppColors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: Text('Got it', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<bool> _showWifiResetDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Text(
              'Reset WiFi Configuration',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                color: AppColors.darkNavy,
              ),
            ),
            content: Text(
              'The device will restart and create a hotspot called BETTANK_SETUP. Connect your phone to that hotspot and open 192.168.4.1 to enter new WiFi credentials.',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppColors.darkGrey,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.poppins(
                    color: AppColors.darkNavy,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.midBlue,
                  foregroundColor: AppColors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Confirm',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7FF),
      appBar: AppBar(
        backgroundColor: AppColors.darkNavy,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Settings',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppColors.white,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 28),
              _buildModeCard(),
              const SizedBox(height: 16),
              _buildThresholdCard(),
              const SizedBox(height: 16),
              _buildWifiResetButton(),
              const SizedBox(height: 16),
              _buildTutorialButton(),
              const SizedBox(height: 16),
              _buildLogoutButton(context),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const BetankBottomNav(currentIndex: 2),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pump Control',
          style: GoogleFonts.poppins(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.darkNavy,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Manual / Automatic switching',
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: AppColors.darkGrey,
          ),
        ),
      ],
    );
  }

  Widget _buildModeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkNavy.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Operation Mode',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.darkGrey,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose how the pump replacement cycle is triggered.',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: AppColors.darkGrey.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 24),
          _ModeButton(
            label: 'Auto Mode',
            description:
                'Pump activates automatically based on sensor readings',
            icon: Icons.smart_toy_outlined,
            isSelected: _selectedMode == 'auto',
            isFilled: true,
            onTap: () => _setMode('auto'),
          ),
          const SizedBox(height: 14),
          _ModeButton(
            label: 'Manual Mode',
            description: 'Pumps are disabled, display sensor readings only',
            icon: Icons.tune_outlined,
            isSelected: _selectedMode == 'manual',
            isFilled: false,
            onTap: () => _setMode('manual'),
          ),
          const SizedBox(height: 20),
          _buildActiveBadge(),
        ],
      ),
    );
  }

  Widget _buildThresholdCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.darkNavy.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section 1: Turbidity slider ──────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Turbidity Threshold',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkNavy,
                ),
              ),
              Text(
                '${_turbThreshold.toStringAsFixed(0)} NTU',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.midBlue,
                ),
              ),
            ],
          ),
          Slider(
            min: 10,
            max: 300,
            divisions: 29,
            value: _turbThreshold,
            activeColor: AppColors.darkNavy,
            inactiveColor: AppColors.lightBlue,
            onChanged: (v) => setState(() => _turbThreshold = v),
            onChangeEnd: (v) => _turbThresholdRef.set(v),
          ),
          Text(
            'Adjust based on your tank setup',
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: AppColors.darkGrey,
            ),
          ),
          const SizedBox(height: 20),
          // ── Section 2: Fixed ranges ──────────────────────────────────
          Text(
            'Fixed Safe Ranges',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.darkGrey,
            ),
          ),
          const SizedBox(height: 10),
          _buildFixedRangeRow('pH', '6.5 – 7.5'),
          const SizedBox(height: 6),
          _buildFixedRangeRow('Temperature', '24 – 30 °C'),
          const SizedBox(height: 6),
          _buildFixedRangeRow('TDS', '< 500 ppm'),
          const SizedBox(height: 8),
          Text(
            'Locked to Betta splendens optimal ranges',
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: AppColors.darkGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFixedRangeRow(String parameter, String range) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.lightBlue.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline,
              size: 14, color: AppColors.darkGrey),
          const SizedBox(width: 8),
          Text(
            '$parameter · $range',
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: AppColors.darkGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveBadge() {
    final isAuto = _selectedMode == 'auto';
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Colors.green,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Active: ${isAuto ? 'Auto Mode' : 'Manual Mode'}',
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.darkNavy,
          ),
        ),
      ],
    );
  }

  Widget _buildWifiResetButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _wifiResetDisabled ? null : _sendWifiReset,
        icon: const Icon(Icons.wifi_tethering_outlined, size: 18),
        label: Text(
          _wifiResetDisabled ? 'Sent — device restarting...' : 'Reset WiFi Config',
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.midBlue,
          foregroundColor: AppColors.white,
          disabledBackgroundColor: AppColors.lightBlue,
          disabledForegroundColor: AppColors.darkNavy,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _buildTutorialButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const OnboardingPage(viewOnly: true),
          ),
        ),
        icon: const Icon(Icons.help_outline_rounded, size: 18),
        label: Text(
          'View Setup Tutorial',
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.softBlue,
          foregroundColor: AppColors.darkNavy,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: () => _showLogoutDialog(context),
        icon: const Icon(Icons.logout_rounded, size: 18),
        label: Text(
          'Logout',
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.red,
          foregroundColor: AppColors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Logout',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            color: AppColors.darkNavy,
          ),
        ),
        content: Text(
          'Are you sure you want to logout?',
          style: GoogleFonts.poppins(
            fontSize: 13,
            color: AppColors.darkGrey,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(
                color: AppColors.darkNavy,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              NotificationService.stopListening();
              await DeviceService.clearDeviceId();
              if (context.mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil(
                  '/setup',
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: AppColors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: Text(
              'Logout',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── mode button ──────────────────────────────────────────────────────────────

class _ModeButton extends StatelessWidget {
  final String label;
  final String description;
  final IconData icon;
  final bool isSelected;
  final bool isFilled;
  final VoidCallback onTap;

  const _ModeButton({
    required this.label,
    required this.description,
    required this.icon,
    required this.isSelected,
    required this.isFilled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool active = isSelected;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: isFilled
              ? (active ? AppColors.darkNavy : AppColors.lightBlue)
              : AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? AppColors.darkNavy : AppColors.lightBlue,
            width: active ? 2 : 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22,
              color: isFilled
                  ? (active ? AppColors.lightBlue : AppColors.darkNavy)
                  : (active ? AppColors.darkNavy : AppColors.midBlue),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isFilled
                          ? (active ? AppColors.white : AppColors.darkNavy)
                          : AppColors.darkNavy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: isFilled
                          ? (active
                              ? AppColors.white.withValues(alpha: 0.75)
                              : AppColors.darkGrey)
                          : AppColors.darkGrey,
                    ),
                  ),
                ],
              ),
            ),
            if (active)
              Icon(
                Icons.check_circle_rounded,
                size: 20,
                color: isFilled ? AppColors.lightBlue : AppColors.darkNavy,
              ),
          ],
        ),
      ),
    );
  }
}
