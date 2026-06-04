import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'screens/login_page.dart';
import 'screens/device_setup_page.dart';
import 'services/device_service.dart';
import 'services/notification_service.dart';
import 'services/background_notification_service.dart';
import 'screens/dashboard_page.dart';
import 'screens/history_page.dart';
import 'screens/settings_page.dart';
import 'screens/onboarding_page.dart';
import 'utils/app_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await DeviceService.init();
  await NotificationService.init();
  if (DeviceService.isConfigured) {
    NotificationService.startListening();
    await BackgroundNotificationService.init();
  }
  runApp(const BetankApp());
}

class BetankApp extends StatelessWidget {
  const BetankApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BETTANK',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.darkNavy,
          primary: AppColors.darkNavy,
          background: AppColors.lightBlue,
        ),
        textTheme: GoogleFonts.poppinsTextTheme(),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/onboarding': (context) => const OnboardingPage(),
        '/login': (context) => const LoginPage(),
        '/setup': (context) => const DeviceSetupPage(),
        '/dashboard': (context) => const DashboardPage(),
        '/history': (context) => const HistoryPage(),
        '/settings': (context) => const SettingsPage(),
      },
    );
  }
}
