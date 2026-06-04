import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_colors.dart';
import '../services/device_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );

    _fadeController.forward();

    Future.delayed(const Duration(seconds: 3), () async {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return; // widget may have been disposed during await
      final onboardingDone = prefs.getBool('onboarding_done') ?? false;
      if (!onboardingDone) {
        Navigator.pushReplacementNamed(context, '/onboarding');
      } else {
        final route = DeviceService.isConfigured ? '/dashboard' : '/setup';
        Navigator.pushReplacementNamed(context, route);
      }
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightBlue,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo image
              Image.asset(
                'assets/images/BETTANKlogo.png',
                width: 160,
                height: 160,
                fit: BoxFit.contain,
              ),

              const SizedBox(height: 28),

              // App name
              Text(
                'BETTANK',
                style: GoogleFonts.poppins(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  color: AppColors.darkNavy,
                  letterSpacing: 6,
                ),
              ),

              const SizedBox(height: 8),

              // Tagline
              Text(
                'Smart Aquarium Monitor',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppColors.darkNavy.withValues(alpha: 0.6),
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(height: 60),

              // Loading indicator
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColors.darkNavy.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
