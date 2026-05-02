import 'dart:io';
import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

// ============================================================================
// MODELS
// ============================================================================

/// Represents a single WhatsApp status item (photo or video).
class StatusItem {
  final String path;
  final String name;
  final int size;
  final String fileType; // 'photo' or 'video'
  final DateTime lastModified;
  final bool isSaved;

  const StatusItem({
    required this.path,
    required this.name,
    required this.size,
    required this.fileType,
    required this.lastModified,
    this.isSaved = false,
  });

  /// Human-readable file size string.
  String get readableSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Duration since the status was last modified (human-readable).
  String get timeAgo {
    final diff = DateTime.now().difference(lastModified);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StatusItem && runtimeType == other.runtimeType && path == other.path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() =>
      'StatusItem(name: $name, type: $fileType, size: $readableSize, '
      'saved: $isSaved, modified: $lastModified)';
}

/// Result returned after a full scan of WhatsApp status folders.
class StatusSaverResult {
  final int totalFound;
  final int newCount;
  final int savedCount;
  final List<StatusItem> items;

  const StatusSaverResult({
    required this.totalFound,
    required this.newCount,
    required this.savedCount,
    required this.items,
  });

  /// Convenience getters.
  List<StatusItem> get newItems => items.where((i) => !i.isSaved).toList();
  List<StatusItem> get savedItems => items.where((i) => i.isSaved).toList();
  List<StatusItem> get photos => items.where((i) => i.fileType == 'photo').toList();
  List<StatusItem> get videos => items.where((i) => i.fileType == 'video').toList();
  List<StatusItem> get newPhotos => items.where((i) => !i.isSaved && i.fileType == 'photo').toList();
  List<StatusItem> get newVideos => items.where((i) => !i.isSaved && i.fileType == 'video').toList();

  /// Total size of all discovered items in bytes.
  int get totalBytes => items.fold(0, (sum, i) => sum + i.size);

  /// Human-readable total size.
  String get totalReadableSize {
    if (totalBytes < 1024) return '$totalBytes B';
    if (totalBytes < 1024 * 1024) return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    if (totalBytes < 1024 * 1024 * 1024) {
      return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  String toString() =>
      'StatusSaverResult(total: $totalFound, new: $newCount, '
      'saved: $savedCount, size: $totalReadableSize)';
}

// ============================================================================
// WHATSAPP STATUS SAVER SERVICE
// ============================================================================

/// Scans WhatsApp status folders, tracks seen files, and copies media to a
/// user-accessible saved-status directory.
///
/// All public methods are `static` so callers don't need to hold an instance.
/// State that must persist across app launches is kept in
/// [SharedPreferences].
class WhatsAppStatusSaver {
  // ---------------------------------------------------------------------------
  // SharedPreferences keys
  // ---------------------------------------------------------------------------

  static const String _prefsKey = 'wa_status_seen';
  static const String _prefsSavedKey = 'wa_status_saved_paths';

  // ---------------------------------------------------------------------------
  // Folder paths – WhatsApp status sources
  // ---------------------------------------------------------------------------

  /// All directories that may contain current WhatsApp statuses.
  ///
  /// WhatsApp stores statuses as temporary files that are auto-deleted after
  /// 24 hours.  Different Android versions / WhatsApp versions use different
  /// paths.
  static const List<String> statusSourcePaths = [
    // Android 11+ scoped storage
    '/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/.Statuses/',
    // Older Android / WhatsApp versions
    '/storage/emulated/0/WhatsApp/Media/.Statuses/',
    // Cache folder (sometimes used for in-progress statuses)
    '/storage/emulated/0/Android/data/com.whatsapp/cache/',
    // WhatsApp Business
    '/storage/emulated/0/Android/media/com.whatsapp.w4b/WhatsApp/Media/.Statuses/',
  ];

  // ---------------------------------------------------------------------------
  // Folder paths – saved-status destination
  // ---------------------------------------------------------------------------

  static const String _savedBasePath = '/storage/emulated/0/PhotoRecover/SavedStatus';
  static const String _savedPhotosPath = '$_savedBasePath/Photos';
  static const String _savedVideosPath = '$_savedBasePath/Videos';

  // ---------------------------------------------------------------------------
  // Supported file extensions
  // ---------------------------------------------------------------------------

  static const _photoExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'];
  static const _videoExtensions = ['.mp4', '.3gp', '.mkv', '.avi', '.mov', '.webm'];

  // ---------------------------------------------------------------------------
  // Tuning constants
  // ---------------------------------------------------------------------------

  /// Minimum file size to consider (skip 0-byte / corrupt stubs).
  static const int _minFileSizeBytes = 512;

  // ===========================================================================
  // PUBLIC API
  // ===========================================================================

  // ---------------------------------------------------------------------------
  // Scanning
  // ---------------------------------------------------------------------------

  /// Scans all known WhatsApp status folders and returns a stream of
  /// [StatusSaverResult] objects – one per source directory found, plus a
  /// final cumulative result.
  ///
  /// Items that have already been saved or marked as seen will have
  /// [StatusItem.isSaved] set to `true`.
  static Stream<StatusSaverResult> scanStatuses() async* {
    final seenPaths = await _getSeenPaths();
    final savedPaths = await _getSavedPaths();
    final allItems = <StatusItem>[];

    for (final sourceDir in statusSourcePaths) {
      final dir = Directory(sourceDir);
      if (!await dir.exists()) continue;

      final items = <StatusItem>[];

      try {
        await for (final entity in dir.list()) {
          if (entity is! File) continue;

          final ext = p.extension(entity.path).toLowerCase();
          final isPhoto = _photoExtensions.contains(ext);
          final isVideo = _videoExtensions.contains(ext);

          // Skip unsupported file types
          if (!isPhoto && !isVideo) continue;

          final fileSize = await _safeFileSize(entity);
          if (fileSize == null || fileSize < _minFileSizeBytes) continue;

          final lastModified = await _safeLastModified(entity);
          final fileName = p.basename(entity.path);
          final isKnown = seenPaths.contains(entity.path) || savedPaths.contains(entity.path);

          items.add(StatusItem(
            path: entity.path,
            name: fileName,
            size: fileSize,
            fileType: isPhoto ? 'photo' : 'video',
            lastModified: lastModified ?? DateTime.now(),
            isSaved: isKnown,
          ));
        }
      } catch (e) {
        debugPrint('[WhatsAppStatusSaver] Error scanning $sourceDir: $e');
        // Continue to the next source directory
      }

      allItems.addAll(items);

      // Yield an intermediate result for this source
      final newInBatch = items.where((i) => !i.isSaved).length;
      yield StatusSaverResult(
        totalFound: items.length,
        newCount: newInBatch,
        savedCount: items.length - newInBatch,
        items: List.unmodifiable(items),
      );
    }

    // Final cumulative result
    final totalNew = allItems.where((i) => !i.isSaved).length;
    yield StatusSaverResult(
      totalFound: allItems.length,
      newCount: totalNew,
      savedCount: allItems.length - totalNew,
      items: List.unmodifiable(allItems),
    );
  }

  /// Single-shot convenience wrapper around [scanStatuses] that returns only
  /// the final cumulative result.
  static Future<StatusSaverResult> scanStatusesOnce() async {
    StatusSaverResult? finalResult;
    await for (final result in scanStatuses()) {
      finalResult = result;
    }
    return finalResult ?? const StatusSaverResult(
      totalFound: 0,
      newCount: 0,
      savedCount: 0,
      items: [],
    );
  }

  // ---------------------------------------------------------------------------
  // Saving
  // ---------------------------------------------------------------------------

  /// Copies a single [StatusItem] to the appropriate saved-status folder.
  ///
  /// Returns `true` if the file was saved successfully, `false` otherwise.
  /// Duplicate file names are resolved by appending a numeric suffix.
  static Future<bool> saveStatus(StatusItem item) async {
    try {
      final sourceFile = File(item.path);
      if (!await sourceFile.exists()) {
        debugPrint('[WhatsAppStatusSaver] Source not found: ${item.path}');
        return false;
      }

      // Determine destination directory
      final destDir = item.fileType == 'video' ? _savedVideosPath : _savedPhotosPath;
      await _ensureDirectory(destDir);

      // Build unique destination path (avoid overwrites)
      final destPath = await _uniqueFilePath(
        directory: destDir,
        fileName: item.name,
      );

      // Copy the file
      await sourceFile.copy(destPath);

      // Persist tracking state
      await _addSavedPath(item.path, destPath);
      await markAsSeen([item.path]);

      debugPrint('[WhatsAppStatusSaver] Saved: ${item.name} → $destPath');
      return true;
    } catch (e) {
      debugPrint('[WhatsAppStatusSaver] Failed to save ${item.name}: $e');
      return false;
    }
  }

  /// Saves all *new* (unsaved) statuses from [items] and yields the running
  /// count of successfully saved files.
  ///
  /// Returns a stream of integers — the cumulative saved count after each
  /// individual save.
  static Stream<int> saveAllNewStatuses(List<StatusItem> items) async* {
    int saved = 0;
    for (final item in items) {
      if (item.isSaved) continue;
      final ok = await saveStatus(item);
      if (ok) {
        saved++;
        yield saved;
      }
    }
  }

  /// Batch-save convenience wrapper that returns the final count.
  static Future<int> saveAllNewStatusesOnce(List<StatusItem> items) async {
    int count = 0;
    await for (final c in saveAllNewStatuses(items)) {
      count = c;
    }
    return count;
  }

  // ---------------------------------------------------------------------------
  // Seen-state tracking (SharedPreferences)
  // ---------------------------------------------------------------------------

  /// Marks a list of file paths as "seen" so they are flagged as already known
  /// on subsequent scans.
  static Future<void> markAsSeen(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_prefsKey) ?? [];
      final updated = {...existing, ...paths}.toList();
      await prefs.setStringList(_prefsKey, updated);
    } catch (e) {
      debugPrint('[WhatsAppStatusSaver] Failed to mark as seen: $e');
    }
  }

  /// Returns `true` when [path] has been previously marked as seen or saved.
  static Future<bool> isStatusSeen(String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getStringList(_prefsKey) ?? [];
      final saved = prefs.getStringList(_prefsSavedKey) ?? [];
      return seen.contains(path) || saved.contains(path);
    } catch (_) {
      return false;
    }
  }

  /// Clears *all* seen/saved tracking state.
  ///
  /// Useful when the user wants to re-discover all statuses as "new".
  static Future<void> clearSeenHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
      await prefs.remove(_prefsSavedKey);
    } catch (e) {
      debugPrint('[WhatsAppStatusSaver] Failed to clear seen history: $e');
    }
  }

  /// Returns the total number of distinct paths currently tracked as seen.
  static Future<int> getSeenCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_prefsKey) ?? []).length;
    } catch (_) {
      return 0;
    }
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Deletes saved statuses that are older than [daysOld] days.
  ///
  /// Returns the number of files removed.
  static Future<int> cleanOldStatuses({int daysOld = 7}) async {
    final cutoff = DateTime.now().subtract(Duration(days: daysOld));
    int deleted = 0;

    for (final dirPath in [_savedPhotosPath, _savedVideosPath]) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;

      try {
        await for (final entity in dir.list()) {
          if (entity is! File) continue;
          try {
            final stat = await entity.stat();
            if (stat.modified.isBefore(cutoff)) {
              await entity.delete();
              deleted++;
            }
          } catch (_) {
            // Skip files that can't be stat'd or deleted
          }
        }
      } catch (e) {
        debugPrint('[WhatsAppStatusSaver] Error cleaning $dirPath: $e');
      }
    }

    if (deleted > 0) {
      debugPrint('[WhatsAppStatusSaver] Cleaned $deleted old saved statuses');
    }
    return deleted;
  }

  /// Deletes *all* saved statuses (photos + videos).
  ///
  /// Returns the number of files removed.
  static Future<int> clearAllSavedStatuses() async {
    int deleted = 0;

    for (final dirPath in [_savedPhotosPath, _savedVideosPath]) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;

      try {
        await for (final entity in dir.list()) {
          if (entity is! File) continue;
          try {
            await entity.delete();
            deleted++;
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('[WhatsAppStatusSaver] Error clearing $dirPath: $e');
      }
    }

    // Also reset tracking
    await clearSeenHistory();
    return deleted;
  }

  // ---------------------------------------------------------------------------
  // Statistics
  // ---------------------------------------------------------------------------

  /// Returns the total number of files in the saved-status directories.
  static Future<int> getSavedStatusesCount() async {
    int count = 0;
    for (final dirPath in [_savedPhotosPath, _savedVideosPath]) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;
      try {
        count += await dir.list().length;
      } catch (_) {}
    }
    return count;
  }

  /// Returns a breakdown of saved photo and video counts.
  static Future<Map<String, int>> getSavedStatusesBreakdown() async {
    int photos = 0;
    int videos = 0;

    final photosDir = Directory(_savedPhotosPath);
    if (await photosDir.exists()) {
      try { photos = await photosDir.list().length; } catch (_) {}
    }

    final videosDir = Directory(_savedVideosPath);
    if (await videosDir.exists()) {
      try { videos = await videosDir.list().length; } catch (_) {}
    }

    return {'photos': photos, 'videos': videos, 'total': photos + videos};
  }

  /// Returns the combined size (in bytes) of all saved statuses.
  static Future<int> getSavedStatusesSize() async {
    int totalSize = 0;
    for (final dirPath in [_savedPhotosPath, _savedVideosPath]) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list()) {
          if (entity is! File) continue;
          try {
            final stat = await entity.stat();
            totalSize += stat.size;
          } catch (_) {}
        }
      } catch (_) {}
    }
    return totalSize;
  }

  /// Lists all currently saved status files as [StatusItem] objects.
  static Future<List<StatusItem>> listSavedStatuses() async {
    final items = <StatusItem>[];

    for (final dirPath in [_savedPhotosPath, _savedVideosPath]) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;

      final fileType = dirPath == _savedPhotosPath ? 'photo' : 'video';

      try {
        await for (final entity in dir.list()) {
          if (entity is! File) continue;
          try {
            final stat = await entity.stat();
            if (stat.size < _minFileSizeBytes) continue;
            items.add(StatusItem(
              path: entity.path,
              name: p.basename(entity.path),
              size: stat.size,
              fileType: fileType,
              lastModified: stat.modified,
              isSaved: true,
            ));
          } catch (_) {}
        }
      } catch (e) {
        debugPrint('[WhatsAppStatusSaver] Error listing $dirPath: $e');
      }
    }

    // Sort newest first
    items.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return items;
  }

  // ---------------------------------------------------------------------------
  // Utility / Validation
  // ---------------------------------------------------------------------------

  /// Checks whether the WhatsApp status folders are accessible on this device.
  ///
  /// Returns a map of path → `bool` indicating accessibility.
  static Future<Map<String, bool>> checkStatusFoldersAccess() async {
    final result = <String, bool>{};
    for (final path in statusSourcePaths) {
      try {
        result[path] = await Directory(path).exists();
      } catch (_) {
        result[path] = false;
      }
    }
    return result;
  }

  /// Ensures the saved-status output directories exist.
  ///
  /// Returns `true` if both directories are ready.
  static Future<bool> ensureOutputDirectories() async {
    try {
      await _ensureDirectory(_savedPhotosPath);
      await _ensureDirectory(_savedVideosPath);
      return true;
    } catch (e) {
      debugPrint('[WhatsAppStatusSaver] Failed to create output dirs: $e');
      return false;
    }
  }

  /// Deletes a previously saved status file.
  ///
  /// Returns `true` if deletion succeeded.
  static Future<bool> deleteSavedStatus(StatusItem item) async {
    try {
      final file = File(item.path);
      if (await file.exists()) {
        await file.delete();
      }
      // Also remove from saved-paths tracking
      await _removeSavedPath(item.path);
      return true;
    } catch (e) {
      debugPrint('[WhatsAppStatusSaver] Failed to delete ${item.name}: $e');
      return false;
    }
  }

  // ===========================================================================
  // PRIVATE HELPERS
  // ===========================================================================

  /// Ensures [dirPath] and all parent directories exist.
  static Future<void> _ensureDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Returns the set of file paths that have been marked as "seen".
  static Future<Set<String>> _getSeenPaths() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefsKey) ?? [];
      return list.toSet();
    } catch (_) {
      return {};
    }
  }

  /// Returns the set of file paths that have been saved (source path → dest
  /// path mapping stored as `sourcePath|||destPath`).
  static Future<Set<String>> _getSavedPaths() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = prefs.getStringList(_prefsSavedKey) ?? [];
      // Extract just the source paths (before the delimiter)
      return entries.map((e) => e.split('|||').first).toSet();
    } catch (_) {
      return {};
    }
  }

  /// Records a source → destination mapping for a saved status.
  static Future<void> _addSavedPath(String sourcePath, String destPath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_prefsSavedKey) ?? [];
      final entry = '$sourcePath|||$destPath';
      if (!existing.contains(entry)) {
        existing.add(entry);
        await prefs.setStringList(_prefsSavedKey, existing);
      }
    } catch (e) {
      debugPrint('[WhatsAppStatusSaver] Failed to record saved path: $e');
    }
  }

  /// Removes a source path from the saved-paths tracking.
  static Future<void> _removeSavedPath(String sourcePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_prefsSavedKey) ?? [];
      existing.removeWhere((e) => e.startsWith('$sourcePath|||'));
      await prefs.setStringList(_prefsSavedKey, existing);
    } catch (e) {
      debugPrint('[WhatsAppStatusSaver] Failed to remove saved path: $e');
    }
  }

  /// Returns a unique file path inside [directory] by appending `(1)`, `(2)`,
  /// … if [fileName] already exists.
  static Future<String> _uniqueFilePath({
    required String directory,
    required String fileName,
  }) async {
    String candidate = p.join(directory, fileName);
    if (!await File(candidate).exists()) return candidate;

    final baseName = p.basenameWithoutExtension(fileName);
    final ext = p.extension(fileName);
    int counter = 1;

    while (true) {
      candidate = p.join(directory, '$baseName ($counter)$ext');
      if (!await File(candidate).exists()) return candidate;
      counter++;
    }
  }

  /// Safe wrapper around [FileStat.size] that returns `null` on error.
  static Future<int?> _safeFileSize(File file) async {
    try {
      return (await file.stat()).size;
    } catch (_) {
      return null;
    }
  }

  /// Safe wrapper around [FileStat.modified] that returns `null` on error.
  static Future<DateTime?> _safeLastModified(File file) async {
    try {
      return (await file.stat()).modified;
    } catch (_) {
      return null;
    }
  }
}
