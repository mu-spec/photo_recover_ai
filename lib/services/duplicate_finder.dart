import 'dart:io';
import 'dart:typed_data';

/// Find duplicate and similar photos/videos by content hash and file properties
class DuplicateFinder {

  /// Find duplicate groups among files. Returns a list of groups where each
  /// group contains paths to files that are likely duplicates.
  /// Uses multi-level detection: exact size, partial hash, then byte comparison.
  static Future<List<List<Map<String, dynamic>>>> findDuplicates(
    List<Map<String, dynamic>> files,
  ) async {
    // Group by file size first (most efficient first pass)
    final sizeGroups = <int, List<Map<String, dynamic>>>{};
    for (final file in files) {
      final size = file['size'] as int;
      sizeGroups.putIfAbsent(size, () => []).add(file);
    }

    // Only consider groups with 2+ files of same size
    final candidateGroups = sizeGroups.values.where((g) => g.length >= 2).toList();

    final duplicateGroups = <List<Map<String, dynamic>>>[];

    for (final group in candidateGroups) {
      // For each group, compare by partial content hash
      final hashGroups = <String, List<Map<String, dynamic>>>{};

      for (final file in group) {
        final path = file['path'] as String;
        final hash = await _computeQuickHash(path);
        if (hash != null) {
          hashGroups.putIfAbsent(hash, () => []).add(file);
        }
      }

      for (final hashGroup in hashGroups.values) {
        if (hashGroup.length >= 2) {
          // Verify with byte comparison for exact duplicates
          final exactDuplicates = <Map<String, dynamic>>[];
          final checked = <String>{};

          for (int i = 0; i < hashGroup.length; i++) {
            final pathA = hashGroup[i]['path'] as String;
            if (checked.contains(pathA)) continue;

            final exactMatches = <Map<String, dynamic>>[hashGroup[i]];

            for (int j = i + 1; j < hashGroup.length; j++) {
              final pathB = hashGroup[j]['path'] as String;
              if (checked.contains(pathB)) continue;

              if (await _areFilesIdentical(pathA, pathB)) {
                exactMatches.add(hashGroup[j]);
                checked.add(pathB);
              }
            }

            if (exactMatches.length >= 2) {
              exactDuplicates.addAll(exactMatches);
              checked.add(pathA);
            }
          }

          if (exactDuplicates.length >= 2) {
            duplicateGroups.add(exactDuplicates);
          }
        }
      }
    }

    return duplicateGroups;
  }

  /// Find similar files (same extension, similar size within 1KB tolerance)
  static Future<List<List<Map<String, dynamic>>>> findSimilar(
    List<Map<String, dynamic>> files,
  ) async {
    final extGroups = <String, List<Map<String, dynamic>>>{};

    for (final file in files) {
      final path = file['path'] as String;
      final ext = path.substring(path.lastIndexOf('.')).toLowerCase();
      extGroups.putIfAbsent(ext, () => []).add(file);
    }

    final similarGroups = <List<Map<String, dynamic>>>[];

    for (final group in extGroups.values) {
      if (group.length < 2) continue;

      // Sort by size
      group.sort((a, b) => (a['size'] as int).compareTo(b['size'] as int));

      for (int i = 0; i < group.length; i++) {
        final sizeA = group[i]['size'] as int;
        final similar = [group[i]];

        for (int j = i + 1; j < group.length; j++) {
          final sizeB = group[j]['size'] as int;
          // Within 1KB tolerance
          if ((sizeB - sizeA).abs() <= 1024) {
            similar.add(group[j]);
          } else {
            break; // Since sorted, no need to check further
          }
        }

        if (similar.length >= 2) {
          similarGroups.add(similar);
        }
      }
    }

    return similarGroups;
  }

  /// Find large files above a threshold
  static List<Map<String, dynamic>> findLargeFiles(
    List<Map<String, dynamic>> files, {
    int thresholdBytes = 10 * 1024 * 1024, // Default 10MB
  }) {
    return files.where((f) => (f['size'] as int) >= thresholdBytes).toList()
      ..sort((a, b) => (b['size'] as int).compareTo(a['size'] as int));
  }

  /// Group files by size categories
  static Map<String, List<Map<String, dynamic>>> groupBySize(List<Map<String, dynamic>> files) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final file in files) {
      final size = file['size'] as int;
      final category = _getSizeCategory(size);
      groups.putIfAbsent(category, () => []).add(file);
    }
    return groups;
  }

  /// Filter files by date range
  static List<Map<String, dynamic>> filterByDateRange(
    List<Map<String, dynamic>> files, {
    required DateTime startDate,
    required DateTime endDate,
  }) {
    return files.where((f) {
      final modified = DateTime.fromMillisecondsSinceEpoch(f['lastModified'] as int);
      return (modified.isAfter(startDate) || modified.isAtSameMomentAs(startDate)) &&
          (modified.isBefore(endDate) || modified.isAtSameMomentAs(endDate));
    }).toList();
  }

  /// Group files by source (app/folder)
  static Map<String, List<Map<String, dynamic>>> groupBySource(List<Map<String, dynamic>> files) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final file in files) {
      final source = file['source'] as String? ?? 'Other';
      groups.putIfAbsent(source, () => []).add(file);
    }
    // Sort groups by count descending
    final sorted = Map.fromEntries(
      groups.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length)),
    );
    return sorted;
  }

  /// Count duplicates in a file list
  static Future<int> countDuplicatePairs(List<Map<String, dynamic>> files) async {
    final groups = await findDuplicates(files);
    int count = 0;
    for (final group in groups) {
      // Number of pairs = n*(n-1)/2
      count += group.length * (group.length - 1) ~/ 2;
    }
    return count;
  }

  /// Get total size of duplicate files (potential savings)
  static Future<int> getDuplicateSize(List<Map<String, dynamic>> files) async {
    final groups = await findDuplicates(files);
    int wastedSpace = 0;
    for (final group in groups) {
      // The smallest file in each group represents the space to keep
      final sizes = group.map((f) => f['size'] as int).toList()..sort();
      for (int i = 1; i < sizes.length; i++) {
        wastedSpace += sizes[i];
      }
    }
    return wastedSpace;
  }

  /// Compute a quick hash from first 4KB + last 4KB + file size
  static Future<String?> _computeQuickHash(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final size = file.lengthSync();

      if (size < 8192) {
        // Small file - hash everything
        final bytes = await file.readAsBytes();
        return _hashBytes(bytes, size);
      }

      final raf = await file.open(mode: FileMode.read);
      try {
        final head = await raf.read(4096);
        await raf.setPosition(size - 4096);
        final tail = await raf.read(4096);
        final combined = Uint8List(head.length + tail.length + 8);
        for (int i = 0; i < head.length; i++) combined[i] = head[i];
        for (int i = 0; i < tail.length; i++) combined[head.length + i] = tail[i];
        // Embed file size
        combined[head.length + tail.length] = (size >> 56) & 0xFF;
        combined[head.length + tail.length + 1] = (size >> 48) & 0xFF;
        combined[head.length + tail.length + 2] = (size >> 40) & 0xFF;
        combined[head.length + tail.length + 3] = (size >> 32) & 0xFF;
        combined[head.length + tail.length + 4] = (size >> 24) & 0xFF;
        combined[head.length + tail.length + 5] = (size >> 16) & 0xFF;
        combined[head.length + tail.length + 6] = (size >> 8) & 0xFF;
        combined[head.length + tail.length + 7] = size & 0xFF;
        return _hashBytes(combined, size);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }

  static String _hashBytes(Uint8List bytes, int size) {
    // Simple DJB2 hash
    int hash = 5381;
    for (final byte in bytes) {
      hash = ((hash << 5) + hash + byte) & 0xFFFFFFFF;
    }
    return '${size.toString()}_$hash';
  }

  static Future<bool> _areFilesIdentical(String pathA, String pathB) async {
    try {
      final fileA = File(pathA);
      final fileB = File(pathB);
      if (!fileA.existsSync() || !fileB.existsSync()) return false;
      final sizeA = await fileA.length();
      final sizeB = await fileB.length();
      if (sizeA != sizeB) return false;

      if (sizeA > 5 * 1024 * 1024) {
        // For files > 5MB, compare head + tail + middle
        final rafA = await fileA.open();
        final rafB = await fileB.open();
        try {
          final headA = await rafA.read(4096);
          final headB = await rafB.read(4096);
          if (!_bytesEqual(headA, headB)) return false;

          await rafA.setPosition(sizeA ~/ 2);
          await rafB.setPosition(sizeB ~/ 2);
          final midA = await rafA.read(4096);
          final midB = await rafB.read(4096);
          if (!_bytesEqual(midA, midB)) return false;

          await rafA.setPosition(sizeA - 4096);
          await rafB.setPosition(sizeB - 4096);
          final tailA = await rafA.read(4096);
          final tailB = await rafB.read(4096);
          return _bytesEqual(tailA, tailB);
        } finally {
          await rafA.close();
          await rafB.close();
        }
      } else {
        // Small files - full comparison
        final bytesA = await fileA.readAsBytes();
        final bytesB = await fileB.readAsBytes();
        return _bytesEqual(bytesA, bytesB);
      }
    } catch (_) {
      return false;
    }
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String _getSizeCategory(int bytes) {
    if (bytes < 100 * 1024) return 'Tiny (< 100 KB)';
    if (bytes < 512 * 1024) return 'Small (100-512 KB)';
    if (bytes < 1024 * 1024) return 'Medium (512 KB-1 MB)';
    if (bytes < 5 * 1024 * 1024) return 'Large (1-5 MB)';
    if (bytes < 50 * 1024 * 1024) return 'Very Large (5-50 MB)';
    return 'Huge (50+ MB)';
  }
}
