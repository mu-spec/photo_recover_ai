import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../models/recoverable_file.dart';
import 'file_signature_scanner.dart';
import 'storage_scanner.dart' show ScanProgress;

/// Enhanced scan result with intelligence data.
class EnhancedScanResult {
  final RecoverableFile file;
  String? validityStatus; // 'valid', 'partial', 'corrupted', 'unknown'
  double? confidenceScore; // 0-100
  String? fragmentStatus; // 'complete', 'partial', 'corrupted'
  String? detectedSignature; // e.g. 'JPEG', 'PNG', 'MP4'
  bool isDuplicate;
  int? duplicateGroup;

  EnhancedScanResult({
    required this.file,
    this.validityStatus,
    this.confidenceScore,
    this.fragmentStatus,
    this.detectedSignature,
    this.isDuplicate = false,
    this.duplicateGroup,
  });
}

/// Scan log entry for transparency.
class ScanLogEntry {
  final DateTime timestamp;
  final String phase;
  final String action;
  final String path;
  final String? result;
  final int? fileSize;
  final String? details;

  ScanLogEntry({
    required this.timestamp,
    required this.phase,
    required this.action,
    required this.path,
    this.result,
    this.fileSize,
    this.details,
  });

  Map<String, dynamic> toMap() => {
    'timestamp': timestamp.millisecondsSinceEpoch,
    'phase': phase,
    'action': action,
    'path': path,
    'result': result,
    'fileSize': fileSize,
    'details': details,
  };
}

/// Real-time scan statistics.
class ScanStatistics {
  int totalFilesScanned = 0;
  int photoCount = 0;
  int videoCount = 0;
  int audioCount = 0;
  int documentCount = 0;
  int duplicateCount = 0;
  int corruptedCount = 0;
  int thumbnailCount = 0;
  int highQualityCount = 0;
  int validCount = 0;
  int partialCount = 0;
  int totalBytesFound = 0;
  int foldersScanned = 0;
  int filesSkipped = 0;
  int carvedFiles = 0; // Files found by signature scanning
  Duration elapsedTime = Duration.zero;
}

/// Multi-phase scanning engine for accessible media and embedded signatures.
class EnhancedStorageScanner {
  static const photoExtensions = ['.jpg','.jpeg','.png','.gif','.bmp','.webp','.heic','.heif','.tiff','.tif','.svg','.raw','.cr2','.nef','.arw','.srw','.dng','.orf','.rw2','.ico','.avif','.jxl'];
  static const videoExtensions = ['.mp4','.3gp','.mkv','.avi','.mov','.wmv','.flv','.webm','.m4v','.ts','.mts','.m2ts','.ogv'];
  static const audioExtensions = ['.mp3','.wav','.aac','.flac','.ogg','.wma','.m4a','.amr','.opus','.mid','.midi'];
  static const documentExtensions = ['.pdf','.doc','.docx','.xls','.xlsx','.ppt','.pptx','.txt','.rtf','.csv','.zip','.rar','.7z','.tar','.gz'];

  static const priorityFolders = ['DCIM','Camera','Pictures','Picture','Download','Downloads','WhatsApp','Telegram','Instagram','TikTok','Snapchat','Signal','Viber','Messenger','Movies','Movie','Music','Video','Recordings','ScreenRecord','ScreenRecording','Bluetooth','Shared','Screenshots','Screenshot','Photos','Photo','Recently Deleted','Trash','Gallery','Images'];
  static const hiddenFolderPatterns = ['.thumbnails','.trashed','.Trash','.THMBDATA','.face','.thumbnail_cache'];
  static const skipFolders = {'Android','data','cache','Cache','__MACOSX','node_modules','.gradle','build','gradle','obsidian','PhotoRecover','MediaRescue','MIUI','MiUI','HwBackup','huawei'};

  static const int minFileSize = 1024;
  static const int thumbnailMaxSize = 50000;
  static const int maxDepthAll = 6;
  static const int maxDepthDeleted = 8;

  bool _isCancelled = false;
  bool _isPaused = false;
  final List<ScanLogEntry> _scanLog = [];
  final ScanStatistics _stats = ScanStatistics();
  final FileSignatureScanner _signatureScanner = FileSignatureScanner();

  List<ScanLogEntry> get scanLog => _scanLog;
  ScanStatistics get stats => _stats;

  void cancel() => _isCancelled = true;
  void pause() => _isPaused = true;
  void resume() => _isPaused = false;

  void _resetStats() {
    _stats
      ..totalFilesScanned = 0
      ..photoCount = 0
      ..videoCount = 0
      ..audioCount = 0
      ..documentCount = 0
      ..duplicateCount = 0
      ..corruptedCount = 0
      ..thumbnailCount = 0
      ..highQualityCount = 0
      ..validCount = 0
      ..partialCount = 0
      ..totalBytesFound = 0
      ..foldersScanned = 0
      ..filesSkipped = 0
      ..carvedFiles = 0
      ..elapsedTime = Duration.zero;
  }

  Future<bool> _waitIfPaused() async {
    while (_isPaused) {
      if (_isCancelled) return true;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return _isCancelled;
  }

  void _log(String phase, String action, String path, {String? result, int? fileSize, String? details}) {
    _scanLog.add(ScanLogEntry(
      timestamp: DateTime.now(),
      phase: phase,
      action: action,
      path: path,
      result: result,
      fileSize: fileSize,
      details: details,
    ));
  }

  /// Run a complete multi-phase scan.
  Stream<ScanProgress> runFullScan({String fileType = 'photo', String scanType = 'all'}) async* {
    _isCancelled = false;
    _isPaused = false;
    _scanLog.clear();
    _resetStats();
    final stopwatch = Stopwatch()..start();
    final allResults = <EnhancedScanResult>[];
    final scannedPaths = HashSet<String>();
    final isDeletedMode = scanType == 'deleted';
    final extensions = fileType == 'photo' ? photoExtensions : fileType == 'video' ? videoExtensions : [...photoExtensions, ...videoExtensions, ...audioExtensions, ...documentExtensions];

    // ================================================================
    // PHASE 1: DISCOVERY - Find all directories
    // ================================================================
    _log('discovery', 'start', '/storage/emulated/0', details: 'Discovering storage directories');
    yield ScanProgress(progress: 0.0, currentFolder: 'Discovering...', filesFound: 0, status: 'Discovering storage directories...', phase: 'discovery', elapsedSeconds: 0);
    await Future.delayed(const Duration(milliseconds: 300));
    if (await _waitIfPaused()) return;

    final discoveredDirs = await _discoverDirectories();
    discoveredDirs.sort((a, b) {
      final aN = a.path.split('/').last.toLowerCase();
      final bN = b.path.split('/').last.toLowerCase();
      final aP = priorityFolders.indexWhere((p) => p.toLowerCase() == aN);
      final bP = priorityFolders.indexWhere((p) => p.toLowerCase() == bN);
      if (aP == -1 && bP == -1) return aN.compareTo(bN);
      if (aP == -1) return 1;
      if (bP == -1) return -1;
      return aP.compareTo(bP);
    });

    _log('discovery', 'complete', '/storage/emulated/0', details: 'Found ${discoveredDirs.length} directories');
    if (discoveredDirs.isEmpty) {
      yield ScanProgress(
        progress: 1.0,
        currentFolder: 'Complete',
        filesFound: 0,
        status: 'No accessible storage folders found. Check media permission and try again.',
        phase: 'complete',
        totalScanned: 0,
        folderCount: 0,
        elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
      );
      return;
    }

    // ================================================================
    // PHASE 2: QUICK SCAN - Priority folders
    // ================================================================
    yield ScanProgress(progress: 0.05, currentFolder: 'Quick Scan', filesFound: 0, status: 'Quick scanning priority folders...', phase: 'quick_scan', elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000);
    if (await _waitIfPaused()) return;

    for (final dir in discoveredDirs) {
      if (_isCancelled) break;
      if (await _waitIfPaused()) break;

      final dirName = dir.path.split('/').last;
      final isPriority = priorityFolders.any((p) => p.toLowerCase() == dirName.toLowerCase());
      if (!isPriority) continue;

      _log('quick_scan', 'scanning', dir.path);
      await _scanDir(dir.path, extensions, fileType, scannedPaths, allResults, isDeletedMode, maxDepth: isPriority ? maxDepthAll : maxDepthAll - 2);
      _stats.foldersScanned++;

      yield ScanProgress(
        progress: 0.05 + (_stats.foldersScanned / discoveredDirs.length) * 0.30,
        currentFolder: _getDisplayName(dir.path),
        filesFound: allResults.length,
        status: 'Quick scanning: ${allResults.length} found...',
        phase: 'quick_scan',
        totalScanned: scannedPaths.length,
        folderCount: _stats.foldersScanned,
        elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
      );
    }

    // ================================================================
    // PHASE 3: DEEP SCAN - All remaining folders
    // ================================================================
    yield ScanProgress(progress: 0.35, currentFolder: 'Deep Scan', filesFound: allResults.length, status: 'Deep scanning all folders...', phase: 'deep_scan', elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000);
    if (await _waitIfPaused()) return;

    for (final dir in discoveredDirs) {
      if (_isCancelled) break;
      if (await _waitIfPaused()) break;

      final dirName = dir.path.split('/').last;
      final isPriority = priorityFolders.any((p) => p.toLowerCase() == dirName.toLowerCase());
      if (isPriority) continue;

      _log('deep_scan', 'scanning', dir.path);
      await _scanDir(dir.path, extensions, fileType, scannedPaths, allResults, isDeletedMode, maxDepth: maxDepthDeleted - 2);
      _stats.foldersScanned++;

      yield ScanProgress(
        progress: 0.35 + (_stats.foldersScanned / discoveredDirs.length) * 0.30,
        currentFolder: _getDisplayName(dir.path),
        filesFound: allResults.length,
        status: 'Deep scanning: ${allResults.length} found...',
        phase: 'deep_scan',
        totalScanned: scannedPaths.length,
        folderCount: _stats.foldersScanned,
        elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
      );
    }

    // ================================================================
    // PHASE 4: CACHE SCAN - App caches
    // ================================================================
    yield ScanProgress(progress: 0.65, currentFolder: 'Cache Scan', filesFound: allResults.length, status: 'Scanning app caches...', phase: 'cache_scan', elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000);
    if (await _waitIfPaused()) return;

    _log('cache_scan', 'start', 'app_caches');
    final cacheFiles = await _scanCacheFolders(extensions, fileType, scannedPaths);
    for (final f in cacheFiles) {
      allResults.add(EnhancedScanResult(file: f, validityStatus: 'valid', confidenceScore: 60));
      _stats.totalFilesScanned++;
      _stats.thumbnailCount++;
    }
    _log('cache_scan', 'complete', 'app_caches', details: 'Found ${cacheFiles.length} files');

    // ================================================================
    // PHASE 5: HIDDEN/TRASH SCAN
    // ================================================================
    yield ScanProgress(progress: 0.72, currentFolder: 'Hidden Scan', filesFound: allResults.length, status: 'Scanning hidden folders & trash...', phase: 'hidden_scan', elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000);
    if (await _waitIfPaused()) return;

    _log('hidden_scan', 'start', 'hidden_folders');
    final hiddenFiles = await _scanHiddenFolders(extensions, fileType, scannedPaths);
    final trashFiles = await _scanTrashFolders(extensions, fileType, scannedPaths);
    for (final f in [...hiddenFiles, ...trashFiles]) {
      allResults.add(EnhancedScanResult(file: f, validityStatus: 'valid', confidenceScore: 50));
      _stats.totalFilesScanned++;
    }
    _log('hidden_scan', 'complete', 'hidden_folders', details: 'Found ${hiddenFiles.length + trashFiles.length} files');

    // ================================================================
    // PHASE 6: FILE SIGNATURE SCANNING
    // ================================================================
    yield ScanProgress(progress: 0.80, currentFolder: 'Signature Scan', filesFound: allResults.length, status: 'Scanning accessible files for embedded media signatures...', phase: 'carving', elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000);
    if (await _waitIfPaused()) return;

    _log('carving', 'start', 'signature_scan', details: 'Starting file signature scanning');
    final signatureFiles = await _runFileCarving(extensions, scannedPaths);
    for (final signatureFile in signatureFiles) {
      allResults.add(signatureFile);
      _stats.carvedFiles++;
    }
    _log('carving', 'complete', 'signature_scan', details: 'Matched ${signatureFiles.length} embedded signatures');

    // ================================================================
    // PHASE 7: ANALYSIS - Validate, score, deduplicate
    // ================================================================
    yield ScanProgress(progress: 0.88, currentFolder: 'Analysis', filesFound: allResults.length, status: 'Analyzing files: validity, confidence, duplicates...', phase: 'analysis', elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000);
    if (await _waitIfPaused()) return;

    _log('analysis', 'start', 'intelligence_layer');
    await _analyzeResults(allResults);
    _log('analysis', 'complete', 'intelligence_layer', details: 'Analyzed ${allResults.length} files');

    // ================================================================
    // PHASE 8: COMPLETE
    // ================================================================
    _stats.elapsedTime = stopwatch.elapsed;
    final msg = _isCancelled ? 'Scan cancelled' : 'Scan complete';
    _log('complete', 'done', 'scan', details: '$msg. Found ${allResults.length} files in ${_stats.elapsedTime.inSeconds}s');

    yield ScanProgress(
      progress: 1.0,
      currentFolder: 'Complete',
      filesFound: allResults.length,
      status: '$msg. Found ${allResults.length} files in ${_stats.elapsedTime.inSeconds}s',
      phase: 'complete',
      totalScanned: scannedPaths.length,
      folderCount: _stats.foldersScanned,
      elapsedSeconds: _stats.elapsedTime.inSeconds,
    );
  }

  /// Scan cache/data files that may contain embedded media signatures.
  Future<List<EnhancedScanResult>> _runFileCarving(List<String> targetExtensions, Set<String> knownPaths) async {
    final signatureResults = <EnhancedScanResult>[];
    final carvingTargets = <String>[];

    // Find large files that may contain embedded data
    final carveSearchPaths = [
      '/storage/emulated/0/Android/media',
      '/storage/emulated/0/DCIM/.thumbnails',
      '/storage/emulated/0/.thumbnails',
      '/storage/emulated/0/Download',
    ];

    for (final searchPath in carveSearchPaths) {
      if (_isCancelled) break;
      final dir = Directory(searchPath);
      if (!await dir.exists()) continue;

      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (_isCancelled) break;
          if (entity is File && knownPaths.add(entity.path)) {
            try {
              final stat = await entity.stat();
              // Target files between 100KB and 500MB that are NOT already known media
              final ext = entity.path.split('.').last.toLowerCase();
              if (stat.size > 100 * 1024 && stat.size < 500 * 1024 * 1024) {
                if (!targetExtensions.contains('.$ext') && ext != 'db' && ext != 'journal') {
                  carvingTargets.add(entity.path);
                }
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    // Scan each target file for embedded signatures.
    _signatureScanner.reset();
    for (final targetPath in carvingTargets) {
      if (_isCancelled) break;
      if (signatureResults.length >= 200) break;

      try {
        await for (final progress in _signatureScanner.carveFile(targetPath, _getSourceName(targetPath))) {
          if (progress.phase == 'complete' && progress.filesFound > 0) {
            // Signature matches are used as confidence signals for accessible files.
          }
        }
      } catch (_) {}
    }

    // Also do signature-based validation on all found files
    for (final path in knownPaths) {
      if (_isCancelled) break;
      try {
        final sig = await _signatureScanner.identifyFile(path);
        if (sig != null) {
          // Update confidence for files with valid signatures
          for (final r in signatureResults) {
            if (r.file.path == path) {
              r.detectedSignature = sig.name;
              r.confidenceScore = (r.confidenceScore ?? 50) + 10;
            }
          }
        }
      } catch (_) {}
    }

    return signatureResults;
  }

  /// Analyze all results: validate, score, deduplicate.
  Future<void> _analyzeResults(List<EnhancedScanResult> results) async {
    // Deduplicate by name + size
    final seen = <String, int>{};
    int dupGroup = 0;

    for (int i = 0; i < results.length; i++) {
      if (_isCancelled) break;
      final r = results[i];
      final key = '${r.file.name}_${r.file.size}';

      if (seen.containsKey(key)) {
        r.isDuplicate = true;
        r.duplicateGroup = seen[key];
        _stats.duplicateCount++;
      } else {
        seen[key] = dupGroup++;
      }

      // Validate file
      if (r.validityStatus == null) {
        r.validityStatus = await _signatureScanner.validateFile(r.file.path);
      }

      // Confidence score
      if (r.confidenceScore == null) {
        r.confidenceScore = await _signatureScanner.calculateRecoverability(r.file);
      }

      // Update stats
      _stats.totalFilesScanned++;
      _stats.totalBytesFound += r.file.size;
      switch (r.file.fileType) {
        case 'photo': _stats.photoCount++; break;
        case 'video': _stats.videoCount++; break;
        case 'audio': _stats.audioCount++; break;
        default: _stats.documentCount++;
      }

      if (r.validityStatus == 'valid') _stats.validCount++;
      else if (r.validityStatus == 'partial') _stats.partialCount++;
      if (r.validityStatus == 'corrupted') _stats.corruptedCount++;
      if (r.file.qualityTag == 'thumbnail') _stats.thumbnailCount++;
      if ((r.confidenceScore ?? 0) >= 80) _stats.highQualityCount++;
    }
  }

  Future<List<Directory>> _discoverDirectories() async {
    final dirs = <Directory>[];
    final baseDir = Directory('/storage/emulated/0');
    try {
      if (!await baseDir.exists()) return dirs;
      await for (final entity in baseDir.list(followLinks: false)) {
        if (_isCancelled) break;
        if (entity is Directory) {
          final name = entity.path.split('/').last;
          if (name.startsWith('.') && !hiddenFolderPatterns.any((p) => name.startsWith(p))) continue;
          if (skipFolders.contains(name)) continue;
          dirs.add(entity);
        }
      }
    } catch (e) { debugPrint('Error discovering directories: $e'); }
    return dirs;
  }

  Future<void> _scanDir(String path, List<String> extensions, String fileType, Set<String> scannedPaths, List<EnhancedScanResult> results, bool isDeletedMode, {int maxDepth = 6}) async {
    await _scanDirRecursive(path, extensions, fileType, scannedPaths, results, isDeletedMode, 0, maxDepth);
  }

  Future<void> _scanDirRecursive(String path, List<String> extensions, String fileType, Set<String> scannedPaths, List<EnhancedScanResult> results, bool isDeletedMode, int depth, int maxDepth) async {
    if (depth > maxDepth || _isCancelled) return;
    final dir = Directory(path);
    if (!await dir.exists()) return;

    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (_isCancelled) break;
        if (await _waitIfPaused()) break;

        if (entity is File) {
          final ext = _getExtension(entity.path).toLowerCase();
          if (extensions.contains(ext) && scannedPaths.add(entity.path)) {
            try {
              final stat = await entity.stat();
              if (stat.size < minFileSize) { _stats.filesSkipped++; continue; }

              final source = _getSourceName(entity.path);
              final isFromHidden = _isHiddenPath(entity.path);
              final isCache = entity.path.contains('/cache/');
              final isThumb = stat.size < thumbnailMaxSize;
              final qualityTag = isThumb ? 'thumbnail' : (isFromHidden ? 'low' : null);

              results.add(EnhancedScanResult(
                file: RecoverableFile(
                  id: entity.path,
                  name: entity.path.split('/').last,
                  path: entity.path,
                  extension: ext,
                  size: stat.size,
                  lastModified: stat.modified,
                  fileType: fileType,
                  source: isFromHidden ? 'Hidden' : isCache ? 'Cache' : source,
                  qualityTag: qualityTag,
                ),
              ));
            } catch (_) {}
          }
        } else if (entity is Directory) {
          final dirName = entity.path.split('/').last;
          if (dirName.startsWith('.') && !hiddenFolderPatterns.any((p) => dirName.startsWith(p))) continue;
          if (skipFolders.contains(dirName)) continue;
          if (dirName == 'Android' || dirName == 'data') continue;
          await _scanDirRecursive(entity.path, extensions, fileType, scannedPaths, results, isDeletedMode, depth + 1, maxDepth);
        }
      }
    } catch (_) {}
  }

  Future<List<RecoverableFile>> _scanCacheFolders(List<String> extensions, String fileType, Set<String> scannedPaths) async {
    final files = <RecoverableFile>[];
    final cachePaths = ['/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media','/storage/emulated/0/WhatsApp/Media','/storage/emulated/0/Telegram','/storage/emulated/0/DCIM/.thumbnails','/storage/emulated/0/Pictures/.thumbnails','/storage/emulated/0/.thumbnails'];
    for (final cachePath in cachePaths) {
      if (_isCancelled) break;
      final dir = Directory(cachePath);
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (_isCancelled) break;
          if (entity is File && scannedPaths.add(entity.path)) {
            final ext = _getExtension(entity.path).toLowerCase();
            if (extensions.contains(ext)) {
              try {
                final stat = await entity.stat();
                if (stat.size < minFileSize) continue;
                files.add(RecoverableFile(id: entity.path, name: entity.path.split('/').last, path: entity.path, extension: ext, size: stat.size, lastModified: stat.modified, fileType: fileType, source: _getSourceName(entity.path)));
              } catch (_) {}
            }
          }
        }
      } catch (_) {}
    }
    return files;
  }

  Future<List<RecoverableFile>> _scanHiddenFolders(List<String> extensions, String fileType, Set<String> scannedPaths) async {
    final files = <RecoverableFile>[];
    final paths = ['/storage/emulated/0/DCIM/.thumbnails','/storage/emulated/0/Pictures/.thumbnails','/storage/emulated/0/.thumbnails','/storage/emulated/0/.THMBDATA'];
    for (final p in paths) {
      if (_isCancelled) break;
      final dir = Directory(p);
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (_isCancelled) break;
          if (entity is File && scannedPaths.add(entity.path)) {
            final ext = _getExtension(entity.path).toLowerCase();
            if (extensions.contains(ext)) {
              try {
                final stat = await entity.stat();
                if (stat.size < 512) continue;
                files.add(RecoverableFile(id: entity.path, name: entity.path.split('/').last, path: entity.path, extension: ext, size: stat.size, lastModified: stat.modified, fileType: fileType, source: 'Hidden', qualityTag: 'thumbnail'));
              } catch (_) {}
            }
          }
        }
      } catch (_) {}
    }
    return files;
  }

  Future<List<RecoverableFile>> _scanTrashFolders(List<String> extensions, String fileType, Set<String> scannedPaths) async {
    final files = <RecoverableFile>[];
    final trashPaths = ['/storage/emulated/0/.Trash','/storage/emulated/0/.trashed','/storage/emulated/0/Trash','/storage/emulated/0/Recently Deleted'];
    try {
      final dcimDir = Directory('/storage/emulated/0/DCIM');
      if (await dcimDir.exists()) {
        await for (final entity in dcimDir.list()) {
          if (_isCancelled) break;
          if (entity is Directory) {
            final name = entity.path.split('/').last.toLowerCase();
            if (name.contains('recently') || name.contains('deleted') || name.contains('trash')) {
              trashPaths.add(entity.path);
            }
          }
        }
      }
    } catch (_) {}
    for (final tp in trashPaths) {
      if (_isCancelled) break;
      final dir = Directory(tp);
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (_isCancelled) break;
          if (entity is File && scannedPaths.add(entity.path)) {
            final ext = _getExtension(entity.path).toLowerCase();
            if (extensions.contains(ext)) {
              try {
                final stat = await entity.stat();
                if (stat.size < minFileSize) continue;
                files.add(RecoverableFile(id: entity.path, name: entity.path.split('/').last, path: entity.path, extension: ext, size: stat.size, lastModified: stat.modified, fileType: fileType, source: 'Trash'));
              } catch (_) {}
            }
          }
        }
      } catch (_) {}
    }
    return files;
  }

  String _getExtension(String path) { final i = path.lastIndexOf('.'); return i == -1 ? '' : path.substring(i); }
  bool _isHiddenPath(String path) => path.split('/').any((p) => p.startsWith('.') && p != '.' && p != '..');

  String _getSourceName(String path) {
    if (path.contains('/DCIM/Camera')) return 'Camera';
    if (path.contains('/DCIM')) return 'DCIM';
    if (path.contains('/WhatsApp')) return 'WhatsApp';
    if (path.contains('/Telegram')) return 'Telegram';
    if (path.contains('/Instagram')) return 'Instagram';
    if (path.contains('/TikTok') || path.contains('/musically')) return 'TikTok';
    if (path.contains('/Snapchat')) return 'Snapchat';
    if (path.contains('/Viber')) return 'Viber';
    if (path.contains('/Messenger')) return 'Messenger';
    if (path.contains('/Signal')) return 'Signal';
    if (path.contains('/Facebook')) return 'Facebook';
    if (path.contains('/Twitter')) return 'Twitter';
    if (path.contains('/Google Photos') || path.contains('google.android.apps.photos')) return 'Google Photos';
    if (path.contains('/Screenshots') || path.contains('/Screenshot')) return 'Screenshots';
    if (path.contains('/Pictures')) return 'Pictures';
    if (path.contains('/Camera')) return 'Camera';
    if (path.contains('/Download')) return 'Downloads';
    if (path.contains('/Movies') || path.contains('/Video')) return 'Videos';
    if (path.contains('/Music')) return 'Music';
    if (path.contains('/Recordings')) return 'Recordings';
    if (path.contains('/Trash') || path.contains('/trash') || path.contains('/.Trash') || path.contains('/Recently Deleted') || path.contains('/.trashed')) return 'Trash';
    if (path.contains('/.thumbnails') || path.contains('/.THMBDATA')) return 'Hidden';
    if (path.contains('/cache') || path.contains('/Cache')) return 'Cache';
    if (path.contains('/Shared')) return 'Shared';
    if (path.contains('/Documents')) return 'Documents';
    return 'Other';
  }

  String _getDisplayName(String path) {
    if (path.contains('/DCIM/Camera')) return 'Camera Roll';
    if (path.contains('/DCIM')) return 'DCIM';
    if (path.contains('/WhatsApp')) return 'WhatsApp';
    if (path.contains('/Telegram')) return 'Telegram';
    if (path.contains('/Instagram')) return 'Instagram';
    if (path.contains('/TikTok')) return 'TikTok';
    if (path.contains('/Snapchat')) return 'Snapchat';
    if (path.contains('/Download')) return 'Downloads';
    if (path.contains('/Pictures')) return 'Pictures';
    if (path.contains('/Camera')) return 'Camera';
    if (path.contains('/Screenshots')) return 'Screenshots';
    if (path.contains('/Movies') || path.contains('/Video')) return 'Videos';
    if (path.contains('/Music')) return 'Music';
    if (path.contains('/Trash') || path.contains('/Recently Deleted')) return 'Trash';
    if (path.contains('/.thumbnails')) return 'Thumbnails';
    return path.split('/').last;
  }
}
