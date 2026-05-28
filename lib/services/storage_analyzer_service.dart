import 'dart:io';
import 'package:flutter/material.dart';

/// Represents a single storage category (e.g. Photos, Videos, WhatsApp).
class StorageCategory {
  final String name;
  final IconData icon;
  final Color color;
  int sizeInBytes;
  int fileCount;
  final String path;

  StorageCategory({
    required this.name,
    required this.icon,
    required this.color,
    this.sizeInBytes = 0,
    this.fileCount = 0,
    required this.path,
  });

  /// Human‑readable size string.
  String get formattedSize => _formatBytes(sizeInBytes);

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  String toString() =>
      'StorageCategory(name: $name, sizeInBytes: $sizeInBytes, fileCount: $fileCount, path: $path)';
}

/// Analyses device storage by scanning well‑known directories under
/// `/storage/emulated/0/`.
class StorageAnalyzerService {
  static const String _emulatedBase = '/storage/emulated/0';
  static const int _maxScanDepth = 4;

  // ---------------------------------------------------------------------------
  // Category definitions
  // ---------------------------------------------------------------------------

  static const List<Map<String, dynamic>> _categoryDefs = [
    {
      'name': 'Photos',
      'icon': Icons.photo_library,
      'color': Colors.blue,
      'folders': ['DCIM', 'Pictures'],
    },
    {
      'name': 'Videos',
      'icon': Icons.videocam,
      'color': Colors.red,
      'folders': ['Movies', 'Video'],
    },
    {
      'name': 'WhatsApp',
      'icon': Icons.chat,
      'color': Colors.green,
      'folders': ['WhatsApp', 'Android/media/com.whatsapp'],
    },
    {
      'name': 'Telegram',
      'icon': Icons.send,
      'color': Colors.lightBlue,
      'folders': ['Telegram', 'Android/media/org.telegram.messenger'],
    },
    {
      'name': 'Instagram',
      'icon': Icons.camera_alt,
      'color': Colors.purple,
      'folders': [
        'Instagram',
        'Android/media/com.instagram.android',
        'Pictures/Instagram',
      ],
    },
    {
      'name': 'Downloads',
      'icon': Icons.download,
      'color': Colors.teal,
      'folders': ['Download', 'Downloads'],
    },
    {
      'name': 'Music',
      'icon': Icons.music_note,
      'color': Colors.orange,
      'folders': ['Music'],
    },
    {
      'name': 'Documents',
      'icon': Icons.description,
      'color': Colors.indigo,
      'folders': ['Documents'],
    },
    {
      'name': 'Cache',
      'icon': Icons.cached,
      'color': Colors.grey,
      'folders': ['Android/data'],
    },
    {
      'name': 'System',
      'icon': Icons.android,
      'color': Colors.brown,
      'folders': ['Android'],
    },
  ];

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Scans `/storage/emulated/0/` and returns a list of [StorageCategory]
  /// objects with their computed sizes and file counts.
  Future<List<StorageCategory>> analyzeStorage() async {
    final basePath = await _resolveBasePath();
    final baseDir = Directory(basePath);
    if (!await baseDir.exists()) {
      return _buildEmptyCategories();
    }

    final List<StorageCategory> categories = [];
    final Set<String> accountedTopLevelDirs = {};

    for (final def in _categoryDefs) {
      final folders = def['folders'] as List<dynamic>;
      int totalSize = 0;
      int totalFiles = 0;
      final List<String> matchedPaths = [];

      for (final folder in folders) {
        final dir = Directory('$basePath/$folder');
        if (await dir.exists()) {
          // Mark top-level directory as already accounted to avoid double counting in "Other".
          final topLevel = folder.toString().split('/').first;
          if (topLevel.isNotEmpty) {
            accountedTopLevelDirs.add(topLevel);
          }
          matchedPaths.add(dir.path);
          final result = await _scanDirectory(dir, 0);
          totalSize += result.size;
          totalFiles += result.files;
        }
      }

      categories.add(StorageCategory(
        name: def['name'] as String,
        icon: def['icon'] as IconData,
        color: def['color'] as Color,
        sizeInBytes: totalSize,
        fileCount: totalFiles,
        path: matchedPaths.join('; '),
      ));
    }

    // Collect remaining top‑level directories into "Other".
    int otherSize = 0;
    int otherFiles = 0;
    try {
      await for (final entity in baseDir.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final dirName = _dirName(entity.path);
        if (accountedTopLevelDirs.contains(dirName)) continue;
        if (dirName.startsWith('.')) continue;

        final result = await _scanDirectory(entity, 0);
        otherSize += result.size;
        otherFiles += result.files;
      }
    } catch (_) {}

    categories.add(StorageCategory(
      name: 'Other',
      icon: Icons.folder,
      color: Colors.grey.shade600,
      sizeInBytes: otherSize,
      fileCount: otherFiles,
      path: '$basePath/...',
    ));

    return categories;
  }

  /// Returns the total internal storage in bytes.
  Future<int> getTotalStorageBytes() async {
    try {
      final statFs = await _getStatFs();
      if (statFs == null) return 0;
      return statFs['total'] as int;
    } catch (_) {
      return 0;
    }
  }

  /// Returns the number of bytes currently in use.
  Future<int> getUsedStorageBytes() async {
    try {
      final statFs = await _getStatFs();
      if (statFs == null) return 0;
      return statFs['used'] as int;
    } catch (_) {
      return 0;
    }
  }

  /// Returns the number of bytes currently free.
  Future<int> getFreeStorageBytes() async {
    try {
      final statFs = await _getStatFs();
      if (statFs == null) return 0;
      return statFs['free'] as int;
    } catch (_) {
      return 0;
    }
  }

  /// Reads storage stats using `df` command on Android.
  Future<Map<String, int>?> _getStatFs() async {
    try {
      final basePath = await _resolveBasePath();
      final result = await Process.run(
        'df',
        ['-P', basePath],
      );
      final lines = (result.stdout as String).trim().split('\n');
      if (lines.length >= 2) {
        // df -P output format: Filesystem  1K-blocks      Used Available Use% Mounted on
        // or sometimes: /dev/root   12345678  8765432  3590246  72% /
        final parts = lines[1].split(RegExp(r'\s+'));
        // Skip the filesystem name (index 0) and mounted-on (last index)
        if (parts.length >= 5) {
          final blockSize = 1024; // df -P reports in 1K blocks
          // Find where numeric columns start (after filesystem name)
          int startIdx = 1;
          // Skip non-numeric entries at start
          while (startIdx < parts.length && int.tryParse(parts[startIdx]) == null) {
            startIdx++;
          }
          if (startIdx + 2 < parts.length) {
            final totalKb = int.tryParse(parts[startIdx]) ?? 0;
            final usedKb = int.tryParse(parts[startIdx + 1]) ?? 0;
            final availKb = int.tryParse(parts[startIdx + 2]) ?? 0;
            return {
              'total': totalKb * blockSize,
              'used': usedKb * blockSize,
              'free': availKb * blockSize,
            };
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Clears cache files for a given category path.
  Future<int> clearCacheFiles(String path) async {
    int freed = 0;
    try {
      if (path.trim().isEmpty) return 0;
      final dir = Directory(path);
      if (!await dir.exists()) return 0;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            // Only delete common cache file extensions
            final ext = entity.path.split('.').last.toLowerCase();
            final cacheExts = ['cache', 'tmp', 'log', 'bak', 'old'];
            if (cacheExts.contains(ext) || entity.path.contains('/cache/')) {
              await entity.delete();
              freed += stat.size;
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    return freed;
  }

  /// Clears old WhatsApp media files (older than 30 days).
  Future<int> clearOldWhatsAppMedia(String basePath) async {
    int freed = 0;
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    try {
      if (basePath.trim().isEmpty) return 0;
      // Build candidate directories from whichever WhatsApp root exists.
      final candidates = <String>[
        // Legacy root: /storage/emulated/0/WhatsApp
        '$basePath/Media/WhatsApp Images/Sent',
        '$basePath/Media/WhatsApp Images',
        '$basePath/Media/WhatsApp Video/Sent',
        '$basePath/Media/WhatsApp Video',
        // New Android/media root: /storage/emulated/0/Android/media/com.whatsapp
        '$basePath/WhatsApp/Media/WhatsApp Images/Sent',
        '$basePath/WhatsApp/Media/WhatsApp Images',
        '$basePath/WhatsApp/Media/WhatsApp Video/Sent',
        '$basePath/WhatsApp/Media/WhatsApp Video',
      ];

      final dirs = candidates.toSet().toList();
      for (final rel in dirs) {
        final dir = Directory(rel);
        if (!await dir.exists()) continue;
        await for (final entity in dir.list(recursive: false, followLinks: false)) {
          if (entity is File) {
            try {
              final stat = await entity.stat();
              if (stat.modified.isBefore(cutoff)) {
                await entity.delete();
                freed += stat.size;
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    return freed;
  }

  /// Returns the top [limit] storage categories sorted by size (largest first).
  List<StorageCategory> getTopFolders(
    List<StorageCategory> categories, {
    int limit = 5,
  }) {
    final sorted = List<StorageCategory>.from(categories)
      ..sort((a, b) => b.sizeInBytes.compareTo(a.sizeInBytes));
    return sorted.take(limit).toList();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<_DirStats> _scanDirectory(Directory dir, int currentDepth) async {
    if (currentDepth > _maxScanDepth) return _DirStats(0, 0);

    int totalSize = 0;
    int totalFiles = 0;

    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File) {
          try {
            final len = await entity.length();
            totalSize += len;
            totalFiles++;
          } catch (_) {}
        } else if (entity is Directory) {
          final sub = await _scanDirectory(entity, currentDepth + 1);
          totalSize += sub.size;
          totalFiles += sub.files;
        }
      }
    } catch (_) {}

    return _DirStats(totalSize, totalFiles);
  }

  String _dirName(String path) {
    final idx = path.lastIndexOf('/');
    return idx == -1 ? path : path.substring(idx + 1);
  }

  List<StorageCategory> _buildEmptyCategories() {
    return _categoryDefs.map((def) {
      return StorageCategory(
        name: def['name'] as String,
        icon: def['icon'] as IconData,
        color: def['color'] as Color,
        sizeInBytes: 0,
        fileCount: 0,
        path: '',
      );
    }).toList()
      ..add(StorageCategory(
        name: 'Other',
        icon: Icons.folder,
        color: Colors.grey.shade600,
        sizeInBytes: 0,
        fileCount: 0,
        path: '',
      ));
  }

  Future<String> _resolveBasePath() async {
    const candidates = <String>[
      '/storage/emulated/0',
      '/sdcard',
      '/storage/self/primary',
    ];

    for (final candidate in candidates) {
      try {
        if (await Directory(candidate).exists()) {
          return candidate;
        }
      } catch (_) {}
    }

    return _emulatedBase;
  }
}

class _DirStats {
  final int size;
  final int files;
  const _DirStats(this.size, this.files);
}


