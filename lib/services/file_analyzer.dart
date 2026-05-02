import 'package:flutter/material.dart';
import '../models/recoverable_file.dart';

/// Quality classification for recoverable files.
enum FileQualityTag {
  highQuality,
  thumbnail,
  corrupted,
  lowQuality,
}

/// Provides static analysis utilities for recoverable files including
/// quality assessment, duplicate detection, and smart recovery suggestions.
class FileAnalyzer {
  // ---------------------------------------------------------------------------
  // Size thresholds (in bytes)
  // ---------------------------------------------------------------------------
  static const int _photoThumbnailThreshold = 50 * 1024; // 50 KB
  static const int _photoCorruptedThreshold = 10 * 1024; // 10 KB
  static const int _videoCorruptedThreshold = 100 * 1024; // 100 KB
  static const int _junkThumbnailThreshold = 20 * 1024; // 20 KB

  // Extensions considered high‑quality raw formats.
  static const List<String> _highQualityExtensions = [
    '.heic',
    '.raw',
    '.dng',
    '.cr2',
    '.nef',
    '.arw',
    '.orf',
    '.rw2',
  ];

  /// Determines the quality of a single [RecoverableFile].
  ///
  /// Decision logic:
  /// - Photos < 10 KB → corrupted
  /// - Photos < 50 KB → thumbnail
  /// - Videos < 100 KB → corrupted
  /// - `.heic` / `.raw` and similar raw extensions → highQuality
  /// - Source containing "thumbnail" → thumbnail
  /// - Otherwise the file is considered lowQuality.
  static FileQualityTag analyzeFileQuality(RecoverableFile file) {
    final bool isVideo = _isVideoFile(file);
    final String ext = _getExtension(file.name).toLowerCase();
    final String source = file.source.toLowerCase();

    // Check for raw / high‑quality extensions first (highest priority).
    if (_highQualityExtensions.contains(ext)) {
      return FileQualityTag.highQuality;
    }

    // Check size‑based rules.
    if (isVideo) {
      if (file.size < _videoCorruptedThreshold) {
        return FileQualityTag.corrupted;
      }
      // Videos that pass the threshold are high quality.
      return FileQualityTag.highQuality;
    }

    // Photo logic.
    if (file.size < _photoCorruptedThreshold) {
      return FileQualityTag.corrupted;
    }
    if (file.size < _photoThumbnailThreshold) {
      return FileQualityTag.thumbnail;
    }

    // Source‑based checks.
    if (source.contains('thumbnail')) {
      return FileQualityTag.thumbnail;
    }

    return FileQualityTag.lowQuality;
  }

  /// Groups potentially duplicate files together.
  ///
  /// Two files are considered duplicates when they share a **similar name**
  /// (same base name with a different extension, or names differing only by
  /// a numeric suffix such as `(1)`, `(2)`, …) **and** their sizes are within
  /// 5 % of one another.
  ///
  /// Returns a list of groups; each group contains two or more files.
  static List<List<RecoverableFile>> findDuplicates(
    List<RecoverableFile> files,
  ) {
    // Map: normalised name → list of files sharing that name.
    final Map<String, List<RecoverableFile>> nameGroups = {};

    for (final file in files) {
      final normalised = _normaliseName(file.name);
      nameGroups.putIfAbsent(normalised, () => []).add(file);
    }

    final List<List<RecoverableFile>> duplicates = [];

    for (final entry in nameGroups.entries) {
      final group = entry.value;
      if (group.length < 2) continue;

      // Sub‑group by size proximity (within 5 %).
      final List<List<RecoverableFile>> sizeGroups = _groupBySize(group);
      for (final sizeGroup in sizeGroups) {
        if (sizeGroup.length >= 2) {
          duplicates.add(sizeGroup);
        }
      }
    }

    return duplicates;
  }

  /// Returns files worth recovering, sorted by a recovery‑priority score.
  ///
  /// Priority scoring favours:
  /// 1. Camera / DCIM source
  /// 2. High quality
  /// 3. Larger file size
  /// 4. More recent files
  static List<RecoverableFile> getSmartRecoverySuggestions(
    List<RecoverableFile> files,
  ) {
    final scored = files.map((file) {
      int score = 0;

      // Source bonus.
      final src = file.source.toLowerCase();
      if (src.contains('camera') || src.contains('dcim')) {
        score += 40;
      } else if (src.contains('whatsapp') || src.contains('telegram')) {
        score += 20;
      } else if (src.contains('download')) {
        score += 10;
      }

      // Quality bonus.
      final quality = analyzeFileQuality(file);
      switch (quality) {
        case FileQualityTag.highQuality:
          score += 30;
          break;
        case FileQualityTag.lowQuality:
          score += 10;
          break;
        case FileQualityTag.thumbnail:
          score += 5;
          break;
        case FileQualityTag.corrupted:
          score += 0;
          break;
      }

      // Size bonus – larger files are likely more valuable (capped at +20).
      final sizeScore = (file.size / (1024 * 1024)).clamp(0, 20).toInt();
      score += sizeScore;

      // Recency bonus – newer files are worth more (capped at +10).
      final daysSinceModified =
          DateTime.now().difference(file.lastModified).inDays;
      final recencyScore = (10 - daysSinceModified).clamp(0, 10);
      score += recencyScore;

      return MapEntry(file, score);
    }).toList();

    scored.sort((a, b) => b.value.compareTo(a.value));

    return scored.map((e) => e.key).toList();
  }

  /// Identifies files that are likely junk and not worth recovering.
  ///
  /// Junk criteria:
  /// - Tiny thumbnails (< 20 KB)
  /// - Files from cache directories
  /// - Corrupted files
  static List<RecoverableFile> getJunkFiles(List<RecoverableFile> files) {
    return files.where((file) {
      final quality = analyzeFileQuality(file);
      final source = file.source.toLowerCase();

      // Tiny thumbnails.
      if (file.size < _junkThumbnailThreshold && !_isVideoFile(file)) {
        return true;
      }

      // Cache source.
      if (source.contains('cache') ||
          source.contains('.cache') ||
          source.contains('temp')) {
        return true;
      }

      // Corrupted.
      if (quality == FileQualityTag.corrupted) {
        return true;
      }

      return false;
    }).toList();
  }

  /// Returns a human‑readable label for the given quality [tag].
  static String getQualityLabel(FileQualityTag tag) {
    switch (tag) {
      case FileQualityTag.highQuality:
        return 'High Quality';
      case FileQualityTag.thumbnail:
        return 'Thumbnail';
      case FileQualityTag.corrupted:
        return 'Corrupted';
      case FileQualityTag.lowQuality:
        return 'Low Quality';
    }
  }

  /// Returns a colour suitable for a quality badge / chip.
  static Color getQualityColor(FileQualityTag tag) {
    switch (tag) {
      case FileQualityTag.highQuality:
        return Colors.green;
      case FileQualityTag.thumbnail:
        return Colors.orange;
      case FileQualityTag.corrupted:
        return Colors.red;
      case FileQualityTag.lowQuality:
        return Colors.amber.shade700;
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static bool _isVideoFile(RecoverableFile file) {
    final ext = _getExtension(file.name).toLowerCase();
    return const ['.mp4', '.mov', '.avi', '.mkv', '.3gp', '.wmv', '.flv']
        .contains(ext);
  }

  /// Returns the file extension **including** the leading dot, e.g. `.jpg`.
  static String _getExtension(String filename) {
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex == -1) return '';
    return filename.substring(dotIndex);
  }

  /// Strips extension and numeric suffixes such as `(1)`, ` (2)` etc.
  /// so that `IMG_1234.jpg` and `IMG_1234 (1).png` normalise to the same key.
  static String _normaliseName(String filename) {
    final ext = _getExtension(filename);
    var base = filename.substring(0, filename.length - ext.length).trim();

    // Remove trailing numeric suffixes like " (1)", "(2)", " - Copy", etc.
    final suffixPattern = RegExp(r'[\s]*[\(\[]?\d+[\)\]]?$');
    base = base.replaceAll(suffixPattern, '').trim();

    return base.toLowerCase();
  }

  /// Sub‑groups files that have sizes within 5 % of each other.
  static List<List<RecoverableFile>> _groupBySize(
    List<RecoverableFile> group,
  ) {
    if (group.isEmpty) return [];

    // Sort by size so we can greedily cluster.
    final sorted = List<RecoverableFile>.from(group)
      ..sort((a, b) => a.size.compareTo(b.size));

    final List<List<RecoverableFile>> result = [];
    List<RecoverableFile> currentCluster = [sorted.first];

    for (int i = 1; i < sorted.length; i++) {
      final referenceSize = currentCluster.first.size;
      final candidateSize = sorted[i].size;

      if (referenceSize == 0) {
        // Avoid division‑by‑zero – only group truly zero‑size files together.
        if (candidateSize == 0) {
          currentCluster.add(sorted[i]);
        } else {
          result.add(currentCluster);
          currentCluster = [sorted[i]];
        }
      } else {
        final ratio = (candidateSize - referenceSize).abs() / referenceSize;
        if (ratio <= 0.05) {
          currentCluster.add(sorted[i]);
        } else {
          result.add(currentCluster);
          currentCluster = [sorted[i]];
        }
      }
    }

    if (currentCluster.isNotEmpty) {
      result.add(currentCluster);
    }

    return result;
  }
}
