import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Snapshot of recovery activity for a single day.
class RecoveryInsight {
  final DateTime date;
  int filesRecovered;
  int totalSizeRecovered;
  int scanCount;
  int photosFound;
  int videosFound;
  int filesFound;

  RecoveryInsight({
    required this.date,
    this.filesRecovered = 0,
    this.totalSizeRecovered = 0,
    this.scanCount = 0,
    this.photosFound = 0,
    this.videosFound = 0,
    this.filesFound = 0,
  });

  /// Deserialises from a JSON map.
  factory RecoveryInsight.fromJson(Map<String, dynamic> json) {
    return RecoveryInsight(
      date: DateTime.parse(json['date'] as String),
      filesRecovered: json['filesRecovered'] as int? ?? 0,
      totalSizeRecovered: json['totalSizeRecovered'] as int? ?? 0,
      scanCount: json['scanCount'] as int? ?? 0,
      photosFound: json['photosFound'] as int? ?? 0,
      videosFound: json['videosFound'] as int? ?? 0,
      filesFound: json['filesFound'] as int? ?? 0,
    );
  }

  /// Serialises to a JSON‑compatible map.
  Map<String, dynamic> toJson() {
    return {
      'date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'filesRecovered': filesRecovered,
      'totalSizeRecovered': totalSizeRecovered,
      'scanCount': scanCount,
      'photosFound': photosFound,
      'videosFound': videosFound,
      'filesFound': filesFound,
    };
  }

  @override
  String toString() =>
      'RecoveryInsight(date: ${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}, filesRecovered: $filesRecovered, '
      'totalSizeRecovered: $totalSizeRecovered, scanCount: $scanCount, '
      'photosFound: $photosFound, videosFound: $videosFound, filesFound: $filesFound)';
}

/// Tracks daily recovery statistics and provides aggregated insights.
///
/// All data is persisted as a single JSON string in [SharedPreferences]
/// keyed by [SharedPreferencesKey].
class RecoveryInsightsService {
  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------

  static final RecoveryInsightsService _instance =
      RecoveryInsightsService._internal();

  factory RecoveryInsightsService() => _instance;

  RecoveryInsightsService._internal();

  // ---------------------------------------------------------------------------
  // Keys
  // ---------------------------------------------------------------------------

  static const String _prefsKey = 'recovery_insights_data';

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Records a scan event for today.
  ///
  /// [fileType] should be `"photo"`, `"video"`, or `"file"`.
  /// [filesFound] is the number of matching files discovered by the scan.
  Future<void> recordScan(String fileType, int filesFound) async {
    final insight = await _getOrCreateToday();
    insight.scanCount++;

    switch (fileType.toLowerCase()) {
      case 'photo':
        insight.photosFound += filesFound;
        break;
      case 'video':
        insight.videosFound += filesFound;
        break;
      default:
        insight.filesFound += filesFound;
        break;
    }

    await _saveToday(insight);
  }

  /// Records a recovery event for today.
  ///
  /// [fileType] should be `"photo"`, `"video"`, or `"file"`.
  /// [count] is the number of files recovered and [totalSize] is their
  /// combined size in bytes.
  Future<void> recordRecovery(
    String fileType,
    int count,
    int totalSize,
  ) async {
    final insight = await _getOrCreateToday();
    insight.filesRecovered += count;
    insight.totalSizeRecovered += totalSize;

    // Also update the "found" counters so the totals remain consistent.
    switch (fileType.toLowerCase()) {
      case 'photo':
        insight.photosFound += count;
        break;
      case 'video':
        insight.videosFound += count;
        break;
      default:
        insight.filesFound += count;
        break;
    }

    await _saveToday(insight);
  }

  /// Returns insights for the last 7 days (including today).
  ///
  /// The map is keyed by the [DateTime] (date only, time set to midnight).
  Future<Map<DateTime, RecoveryInsight>> getWeeklyInsights() async {
    final all = await _loadAll();
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 6));

    final Map<DateTime, RecoveryInsight> weekly = {};
    for (final entry in all.entries) {
      final entryDate = entry.key;
      final normalisedEntry =
          DateTime(entryDate.year, entryDate.month, entryDate.day);
      final normalisedWeekAgo =
          DateTime(weekAgo.year, weekAgo.month, weekAgo.day);

      if (!normalisedEntry.isBefore(normalisedWeekAgo)) {
        weekly[entry.key] = entry.value;
      }
    }

    return weekly;
  }

  /// Returns the [RecoveryInsight] for today, creating an empty one if
  /// nothing has been recorded yet.
  Future<RecoveryInsight> getTodayInsights() async {
    return _getOrCreateToday();
  }

  /// Sums [RecoveryInsight.filesRecovered] across all stored days.
  Future<int> getTotalRecoveredAllTime() async {
    final all = await _loadAll();
    int total = 0;
    for (final insight in all.values) {
      total += insight.filesRecovered;
    }
    return total;
  }

  /// Sums [RecoveryInsight.totalSizeRecovered] across all stored days.
  Future<int> getTotalSizeRecoveredAllTime() async {
    final all = await _loadAll();
    int total = 0;
    for (final insight in all.values) {
      total += insight.totalSizeRecovered;
    }
    return total;
  }

  /// Returns a breakdown of recovered files by type:
  /// `{ "photo": <count>, "video": <count>, "file": <count> }`.
  Future<Map<String, int>> getRecoveryByType() async {
    final all = await _loadAll();
    int photos = 0;
    int videos = 0;
    int files = 0;

    for (final insight in all.values) {
      photos += insight.photosFound;
      videos += insight.videosFound;
      files += insight.filesFound;
    }

    return {
      'photo': photos,
      'video': videos,
      'file': files,
    };
  }

  // ---------------------------------------------------------------------------
  // Persistence helpers
  // ---------------------------------------------------------------------------

  /// Loads the full `Map<String, Map<String, dynamic>>` from SharedPreferences.
  Future<Map<DateTime, RecoveryInsight>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final Map<DateTime, RecoveryInsight> result = {};

      for (final entry in decoded.entries) {
        final date = DateTime.parse(entry.key);
        final inner = entry.value as Map<String, dynamic>;
        result[date] = RecoveryInsight.fromJson(inner);
      }

      return result;
    } catch (_) {
      return {};
    }
  }

  /// Persists the entire insights map back to SharedPreferences.
  Future<void> _saveAll(Map<DateTime, RecoveryInsight> data) async {
    final prefs = await SharedPreferences.getInstance();

    final Map<String, Map<String, dynamic>> serialisable = {};
    for (final entry in data.entries) {
      serialisable[_dateKey(entry.key)] = entry.value.toJson();
    }

    await prefs.setString(_prefsKey, jsonEncode(serialisable));
  }

  /// Returns today's insight, creating one if it doesn't exist yet.
  Future<RecoveryInsight> _getOrCreateToday() async {
    final all = await _loadAll();
    final todayKey = _dateKey(DateTime.now());

    if (all.containsKey(DateTime.now())) {
      return all[DateTime.now()]!;
    }

    // Normalise lookup by date‑only key.
    for (final entry in all.entries) {
      if (_dateKey(entry.key) == todayKey) {
        return entry.value;
      }
    }

    // Create a fresh record.
    final today = RecoveryInsight(date: DateTime.now());
    all[today.date] = today;
    await _saveAll(all);
    return today;
  }

  /// Writes back today's insight (convenience wrapper).
  Future<void> _saveToday(RecoveryInsight insight) async {
    final all = await _loadAll();

    // Find and replace existing entry for today, or insert a new one.
    final todayKey = _dateKey(insight.date);
    DateTime? existingKey;
    for (final key in all.keys) {
      if (_dateKey(key) == todayKey) {
        existingKey = key;
        break;
      }
    }

    if (existingKey != null) {
      all[existingKey] = insight;
    } else {
      all[insight.date] = insight;
    }

    await _saveAll(all);
  }

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  /// Formats a [DateTime] as `yyyy-MM-dd` – used as the map key.
  static String _dateKey(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
