import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_colors.dart';

// ── Card data model ────────────────────────────────────────────────────────────
class _CardData {
  final IconData icon;
  final Color iconColor;
  final String step;
  final String title;
  final String body;
  final String? badge; // optional highlighted chip shown between title and body

  const _CardData({
    required this.icon,
    required this.iconColor,
    required this.step,
    required this.title,
    required this.body,
    this.badge,
  });
}

// ── Onboarding page ────────────────────────────────────────────────────────────
class OnboardingPage extends StatefulWidget {
  /// [viewOnly] = true when opened from Settings — finish just pops back.
  /// [viewOnly] = false (default) = first-launch flow → writes prefs → /setup.
  final bool viewOnly;
  const OnboardingPage({super.key, this.viewOnly = false});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  static const List<_CardData> _cards = [
    _CardData(
      icon: Icons.power_settings_new,
      iconColor: AppColors.midBlue,
      step: '01',
      title: 'Power On Your BETTANK',
      body: 'Plug in your BETTANK device.\n\n'
          '1.  Locate the BOOT button on your ESP32\n'
          '2.  Hold it for 3 seconds\n'
          '3.  Release — the BETTANK_SETUP\n'
          '     hotspot will appear on your phone',
    ),
    _CardData(
      icon: Icons.wifi,
      iconColor: AppColors.darkNavy,
      step: '02',
      title: 'Connect to the Hotspot',
      body: 'On your phone:\n\n'
          '1.  Open WiFi Settings\n'
          '2.  Connect to the hotspot shown above\n'
          '3.  Open a browser → go to 192.168.4.1\n'
          '4.  Select your home WiFi → tap Save',
      badge: 'BETTANK_SETUP',
    ),
    _CardData(
      icon: Icons.phonelink_setup,
      iconColor: AppColors.midBlue,
      step: '03',
      title: 'Enter Your Device ID',
      body: 'After connecting, find your Device ID on the '
          'device label or Serial Monitor\n(e.g. bettank_DD30).\n\n'
          'Enter it in the app to start monitoring.\n\n'
          'To change WiFi later:\n'
          '•  Hold BOOT button for 3 seconds\n'
          '•  Or go to Settings → Reset WiFi',
    ),
  ];

  Future<void> _finish() async {
    if (widget.viewOnly) {
      // Opened from Settings — just close the page
      if (mounted) Navigator.pop(context);
      return;
    }
    // First-launch flow — mark done then go to device setup
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/setup');
    }
  }

  void _nextPage() {
    if (_currentPage < _cards.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBlue,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_currentPage + 1} of ${_cards.length}',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: AppColors.darkNavy.withValues(alpha: 0.45),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  TextButton(
                    onPressed: _finish,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                    ),
                    child: Text(
                      widget.viewOnly ? 'Close' : 'Skip',
                      style: GoogleFonts.poppins(
                        color: AppColors.darkNavy.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Swipeable cards ──────────────────────────────────────────
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _cards.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (ctx, i) => _CardPage(card: _cards[i]),
              ),
            ),

            // ── Bottom: dot indicators + action button ───────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 4, 28, 36),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Animated pill dots
                  Row(
                    children: List.generate(_cards.length, (i) {
                      final active = i == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 280),
                        margin: const EdgeInsets.only(right: 7),
                        width: active ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.darkNavy
                              : AppColors.darkNavy.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  // Next / Get Started
                  ElevatedButton(
                    onPressed: _nextPage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.darkNavy,
                      foregroundColor: AppColors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 30, vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      _currentPage < _cards.length - 1
                          ? 'Next  →'
                          : (widget.viewOnly ? 'Close' : 'Get Started'),
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Single card page ───────────────────────────────────────────────────────────
class _CardPage extends StatelessWidget {
  final _CardData card;
  const _CardPage({required this.card});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Step label chip
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: card.iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              'STEP ${card.step}',
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: card.iconColor,
                letterSpacing: 1.8,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Icon box
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: card.iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(card.icon, size: 38, color: card.iconColor),
          ),
          const SizedBox(height: 26),

          // Title
          Text(
            card.title,
            style: GoogleFonts.poppins(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: AppColors.darkNavy,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 20),

          // Badge — WiFi network name highlight (card 2 only)
          if (card.badge != null) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.darkNavy,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi, color: AppColors.white, size: 19),
                  const SizedBox(width: 10),
                  Text(
                    card.badge!,
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.white,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],

          // Body
          Text(
            card.body,
            style: GoogleFonts.poppins(
              fontSize: 14.5,
              color: AppColors.darkNavy.withValues(alpha: 0.72),
              height: 1.78,
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
