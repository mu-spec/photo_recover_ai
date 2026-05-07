import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'models/app_settings.dart';
import 'services/ad_service.dart';
import 'utils/app_theme.dart';
import 'screens/splash_screen.dart';

// Global ad service instance
final AdService adService = AdService();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final settings = await AppSettings.create();

  // Set initial dark mode state for AppTheme dynamic colors
  AppTheme.isDarkMode = settings.darkModeEnabled;

  // Initialize Google Mobile Ads
  await adService.initialize();
  adService.loadBannerAd();

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppSettingsProvider(settings),
      child: const PhotoRecoverApp(),
    ),
  );
}

class AppSettingsProvider extends ChangeNotifier {
  final AppSettings _settings;
  bool _isLoading = false;

  AppSettingsProvider(this._settings);

  AppSettings get settings => _settings;
  bool get isLoading => _isLoading;
  bool get isProUser => _settings.isProUser;
  bool get notificationsEnabled => _settings.notificationsEnabled;
  bool get darkModeEnabled => _settings.darkModeEnabled;
  bool get autoScanEnabled => _settings.autoScanEnabled;

  Future<void> setProUser(bool value) async {
    await _settings.setProUser(value);
    notifyListeners();
  }

  Future<void> setNotificationsEnabled(bool value) async {
    await _settings.setNotificationsEnabled(value);
    notifyListeners();
  }

  Future<void> setDarkModeEnabled(bool value) async {
    await _settings.setDarkModeEnabled(value);
    notifyListeners();
  }

  Future<void> setAutoScanEnabled(bool value) async {
    await _settings.setAutoScanEnabled(value);
    notifyListeners();
  }

  Future<void> incrementScanCount() async {
    await _settings.incrementScanCount();
    notifyListeners();
  }

  Future<void> incrementRecoveredCount(int count) async {
    await _settings.incrementRecoveredCount(count);
    notifyListeners();
  }
}

class PhotoRecoverApp extends StatelessWidget {
  const PhotoRecoverApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Listen to dark mode setting and sync with AppTheme
    final isDark = context.select((AppSettingsProvider p) => p.darkModeEnabled);
    AppTheme.isDarkMode = isDark;

    // Update status bar style based on theme
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
    );

    return MaterialApp(
      title: 'Photo Recover',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return Column(
          children: [
            Expanded(child: child ?? const SizedBox.shrink()),
            adService.buildBannerContainer(),
          ],
        );
      },
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      home: const SplashScreen(),
    );
  }

  ThemeData _buildLightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6C63FF),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF8F9FE),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Color(0xFF1A1A2E)),
        titleTextStyle: TextStyle(
          color: Color(0xFF1A1A2E),
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6C63FF),
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6C63FF),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0F172A),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Color(0xFFE2E8F0)),
        titleTextStyle: TextStyle(
          color: Color(0xFFE2E8F0),
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6C63FF),
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
