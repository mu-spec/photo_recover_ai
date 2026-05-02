import 'package:shared_preferences/shared_preferences.dart';

/// Scan result caching and incremental scan support
class ScanCacheService {
  static const String _cachePrefix = 'scan_cache_';
  static const String _incrementalKey = 'scan_incremental_index_';

  /// Save scan results to cache
  static Future<void> saveScanResults(String fileType, List<Map<String, dynamic>> results) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_cachePrefix$fileType';
      final cachedData = results.take(500).map((r) => r['path'] as String).toList();
      await prefs.setStringList(cacheKey, cachedData);
      await prefs.setInt('${cacheKey}_count', results.length);
      await prefs.setInt('${cacheKey}_timestamp', DateTime.now().millisecondsSinceEpoch);
      final incrementalKey = '$_incrementalKey$fileType';
      await prefs.setStringList(incrementalKey, cachedData);
    } catch (_) {}
  }

  /// Load cached scan results count
  static Future<int> getCachedResultCount(String fileType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_cachePrefix$fileType';
      return prefs.getInt('${cacheKey}_count') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Get timestamp of last scan for a file type
  static Future<DateTime?> getLastScanTime(String fileType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_cachePrefix$fileType';
      final ts = prefs.getInt('${cacheKey}_timestamp');
      return ts != null ? DateTime.fromMillisecondsSinceEpoch(ts) : null;
    } catch (_) {
      return null;
    }
  }

  /// Get set of previously scanned file paths (for incremental scanning)
  static Future<Set<String>> getPreviouslyScannedPaths(String fileType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final incrementalKey = '$_incrementalKey$fileType';
      final paths = prefs.getStringList(incrementalKey) ?? [];
      return paths.toSet();
    } catch (_) {
      return {};
    }
  }

  /// Save scanned paths for incremental scanning
  static Future<void> saveScannedPaths(String fileType, Set<String> paths) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final incrementalKey = '$_incrementalKey$fileType';
      final pathList = paths.take(5000).toList();
      await prefs.setStringList(incrementalKey, pathList);
    } catch (_) {}
  }

  /// Clear cache for a specific file type
  static Future<void> clearCache(String fileType) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_cachePrefix$fileType';
      final incrementalKey = '$_incrementalKey$fileType';
      await prefs.remove(cacheKey);
      await prefs.remove('${cacheKey}_count');
      await prefs.remove('${cacheKey}_timestamp');
      await prefs.remove(incrementalKey);
    } catch (_) {}
  }

  /// Clear all scan caches
  static Future<void> clearAllCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith(_cachePrefix) || key.startsWith(_incrementalKey)) {
          await prefs.remove(key);
        }
      }
    } catch (_) {}
  }

  /// Check if a scan result is new (not in previous scan)
  static Future<bool> isNewFile(String fileType, String filePath) async {
    final scannedPaths = await getPreviouslyScannedPaths(fileType);
    return !scannedPaths.contains(filePath);
  }

  /// Compare current results with cached to find new files
  static Future<List<String>> findNewFiles(String fileType, List<String> currentPaths) async {
    final previousPaths = await getPreviouslyScannedPaths(fileType);
    return currentPaths.where((p) => !previousPaths.contains(p)).toList();
  }
}
