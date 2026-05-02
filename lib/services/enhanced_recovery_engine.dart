import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/recoverable_file.dart';
import 'database_helper.dart';

/// Recovery progress for batch operations.
class RecoveryProgress {
  final int totalFiles;
  final int completedFiles;
  final int failedFiles;
  final double progress;
  final String currentFile;
  final String status;
  final int bytesRecovered;

  RecoveryProgress({
    required this.totalFiles,
    required this.completedFiles,
    required this.failedFiles,
    required this.progress,
    required this.currentFile,
    required this.status,
    this.bytesRecovered = 0,
  });
}

/// Enhanced recovery engine with batch recovery, progress tracking, and history.
class EnhancedRecoveryEngine {
  static const _baseFolder = 'PhotoRecover';

  final DatabaseHelper _db = DatabaseHelper.instance;
  bool _isCancelled = false;

  void cancel() => _isCancelled = true;
  void reset() => _isCancelled = false;

  /// Get the base recovery directory.
  Future<String> getRecoveryBasePath() async {
    final basePath = '/storage/emulated/0/$_baseFolder';
    final baseDir = Directory(basePath);
    if (!await baseDir.exists()) await baseDir.create(recursive: true);
    // Create sub-folders
    for (final sub in ['Photos', 'Videos', 'Audio', 'Documents', 'Carved']) {
      await Directory('$basePath/$sub').create(recursive: true);
    }
    return basePath;
  }

  /// Recover a single file.
  Stream<RecoveryProgress> recoverSingle(RecoverableFile file) async* {
    reset();
    final basePath = await getRecoveryBasePath();
    final subFolder = _getSubFolder(file.fileType);
    final dirPath = '$basePath/$subFolder';
    await Directory(dirPath).create(recursive: true);

    yield RecoveryProgress(
      totalFiles: 1, completedFiles: 0, failedFiles: 0, progress: 0.0,
      currentFile: file.name, status: 'Preparing recovery...',
    );

    try {
      final sourceFile = File(file.path);
      if (!await sourceFile.exists()) {
        yield RecoveryProgress(totalFiles: 1, completedFiles: 0, failedFiles: 1, progress: 1.0, currentFile: file.name, status: 'Source file not found');
        return;
      }

      yield RecoveryProgress(totalFiles: 1, completedFiles: 0, failedFiles: 0, progress: 0.3, currentFile: file.name, status: 'Copying file...');

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final newPath = '$dirPath/recovered_${timestamp}_${file.name}';
      await sourceFile.copy(newPath);

      // Save to database
      await _db.insertRecoveryRecord(RecoveryRecord(
        id: 'rec_${timestamp}',
        fileName: file.name,
        originalPath: file.path,
        recoveredPath: newPath,
        fileType: file.fileType,
        recoveredAt: DateTime.now(),
        fileSize: file.size,
      ));

      yield RecoveryProgress(totalFiles: 1, completedFiles: 1, failedFiles: 0, progress: 1.0, currentFile: file.name, status: 'Recovered successfully', bytesRecovered: file.size);
    } catch (e) {
      yield RecoveryProgress(totalFiles: 1, completedFiles: 0, failedFiles: 1, progress: 1.0, currentFile: file.name, status: 'Recovery failed: ${e.toString()}');
    }
  }

  /// Batch recover multiple files with progress tracking.
  Stream<RecoveryProgress> recoverBatch(List<RecoverableFile> files) async* {
    reset();
    final basePath = await getRecoveryBasePath();
    int completed = 0;
    int failed = 0;
    int totalBytes = 0;

    yield RecoveryProgress(totalFiles: files.length, completedFiles: 0, failedFiles: 0, progress: 0.0, currentFile: '', status: 'Preparing batch recovery...');

    for (int i = 0; i < files.length; i++) {
      if (_isCancelled) break;

      final file = files[i];
      final subFolder = _getSubFolder(file.fileType);
      final dirPath = '$basePath/$subFolder';
      await Directory(dirPath).create(recursive: true);

      try {
        final sourceFile = File(file.path);
        if (!await sourceFile.exists()) {
          failed++;
          yield RecoveryProgress(totalFiles: files.length, completedFiles: completed, failedFiles: failed, progress: (i + 1) / files.length, currentFile: file.name, status: 'Skipped (not found)', bytesRecovered: totalBytes);
          continue;
        }

        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final newPath = '$dirPath/recovered_${timestamp}_${file.name}';
        await sourceFile.copy(newPath);
        totalBytes += file.size;
        completed++;

        await _db.insertRecoveryRecord(RecoveryRecord(
          id: 'rec_${timestamp}_$i',
          fileName: file.name,
          originalPath: file.path,
          recoveredPath: newPath,
          fileType: file.fileType,
          recoveredAt: DateTime.now(),
          fileSize: file.size,
        ));

        yield RecoveryProgress(totalFiles: files.length, completedFiles: completed, failedFiles: failed, progress: (i + 1) / files.length, currentFile: file.name, status: 'Recovered $completed/${files.length}', bytesRecovered: totalBytes);
      } catch (e) {
        failed++;
        yield RecoveryProgress(totalFiles: files.length, completedFiles: completed, failedFiles: failed, progress: (i + 1) / files.length, currentFile: file.name, status: 'Failed: $completed recovered', bytesRecovered: totalBytes);
      }
    }

    final statusMsg = _isCancelled ? 'Cancelled. Recovered $completed files' : 'Complete! Recovered $completed files';
    yield RecoveryProgress(totalFiles: files.length, completedFiles: completed, failedFiles: failed, progress: 1.0, currentFile: '', status: statusMsg, bytesRecovered: totalBytes);
  }

  /// Get recovery history from database.
  Future<List<RecoveryRecord>> getRecoveryHistory({String? fileType}) async {
    return await _db.getRecoveryRecords(fileType: fileType);
  }

  /// Get recovery stats.
  Future<Map<String, int>> getRecoveryStats() async {
    return await _db.getRecoveryStats();
  }

  /// Get total recovery count.
  Future<int> getTotalRecoveredCount({String? fileType}) async {
    return await _db.getRecoveryCount(fileType: fileType);
  }

  /// Delete a recovered file.
  Future<bool> deleteRecoveredFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Clear all recovered files.
  Future<bool> clearAllRecovered() async {
    try {
      final basePath = await getRecoveryBasePath();
      final dir = Directory(basePath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        await dir.create(recursive: true);
        await _db.clearRecoveryRecords();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Get total size of recovered files.
  Future<int> getRecoveredTotalSize() async {
    final basePath = await getRecoveryBasePath();
    final dir = Directory(basePath);
    if (!await dir.exists()) return 0;
    int totalSize = 0;
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try { totalSize += (await entity.stat()).size; } catch (_) {}
        }
      }
    } catch (_) {}
    return totalSize;
  }

  /// Get count of recovered files on disk.
  Future<int> getRecoveredFileCount() async {
    final basePath = await getRecoveryBasePath();
    final dir = Directory(basePath);
    if (!await dir.exists()) return 0;
    int count = 0;
    try {
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) count++;
      }
    } catch (_) {}
    return count;
  }

  String _getSubFolder(String fileType) {
    switch (fileType) {
      case 'photo': return 'Photos';
      case 'video': return 'Videos';
      case 'audio': return 'Audio';
      case 'document': return 'Documents';
      default: return 'Files';
    }
  }
}
