import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  static const String keyIsPro = 'is_pro_user';
  static const String keyAdCount = 'ad_count';
  static const String keyScanCount = 'scan_count';
  static const String keyRecoveredCount = 'recovered_count';
  static const String keyFirstLaunch = 'first_launch';
  static const String keyThemeMode = 'theme_mode';
  static const String keyDarkMode = 'dark_mode';
  static const String keyNotifications = 'notifications_enabled';
  static const String keyAutoScan = 'auto_scan_enabled';
  static const String keyScanMode = 'scan_mode';
  static const String keyLastScanState = 'last_scan_state';

  final SharedPreferences _prefs;

  AppSettings(this._prefs);

  bool get isProUser => _prefs.getBool(keyIsPro) ?? false;
  int get adCount => _prefs.getInt(keyAdCount) ?? 0;
  int get scanCount => _prefs.getInt(keyScanCount) ?? 0;
  int get recoveredCount => _prefs.getInt(keyRecoveredCount) ?? 0;
  bool get isFirstLaunch => _prefs.getBool(keyFirstLaunch) ?? true;
  String get themeMode => _prefs.getString(keyThemeMode) ?? 'system';
  bool get darkModeEnabled => _prefs.getBool(keyDarkMode) ?? false;
  bool get notificationsEnabled => _prefs.getBool(keyNotifications) ?? true;
  bool get autoScanEnabled => _prefs.getBool(keyAutoScan) ?? false;
  String get scanMode => _prefs.getString(keyScanMode) ?? 'quick';
  String? get lastScanState => _prefs.getString(keyLastScanState);

  Future<void> setProUser(bool value) async {
    await _prefs.setBool(keyIsPro, value);
  }

  Future<void> incrementAdCount() async {
    await _prefs.setInt(keyAdCount, adCount + 1);
  }

  Future<void> incrementScanCount() async {
    await _prefs.setInt(keyScanCount, scanCount + 1);
  }

  Future<void> incrementRecoveredCount(int count) async {
    await _prefs.setInt(keyRecoveredCount, recoveredCount + count);
  }

  Future<void> setFirstLaunchDone() async {
    await _prefs.setBool(keyFirstLaunch, false);
  }

  Future<void> setThemeMode(String mode) async {
    await _prefs.setString(keyThemeMode, mode);
  }

  Future<void> setDarkModeEnabled(bool value) async {
    await _prefs.setBool(keyDarkMode, value);
  }

  Future<void> setNotificationsEnabled(bool value) async {
    await _prefs.setBool(keyNotifications, value);
  }

  Future<void> setAutoScanEnabled(bool value) async {
    await _prefs.setBool(keyAutoScan, value);
  }

  Future<void> setScanMode(String mode) async {
    await _prefs.setString(keyScanMode, mode);
  }

  Future<void> setLastScanState(String stateJson) async {
    await _prefs.setString(keyLastScanState, stateJson);
  }

  bool get shouldShowAd => !isProUser && adCount % 3 == 2;

  static Future<AppSettings> create() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(prefs);
  }
}
