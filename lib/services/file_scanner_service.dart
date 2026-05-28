import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/recoverable_file.dart';
import 'media_categorizer.dart';
import 'media_store_scanner.dart';
import 'storage_scanner.dart';

class FileScannerService {
  final StorageScanner _scanner = StorageScanner();
  final MediaStoreScannerService _mediaStoreScanner = MediaStoreScannerService();

  List<RecoverableFile> _lastScanResults = [];
  List<RecoverableFile> get lastScanResults => _lastScanResults;

  void cancelScan() => _scanner.cancelScan();
  void resetCancel() => _scanner.resetCancel();
  void pauseScan() => _scanner.pauseScan();
  void resumeScan() => _scanner.resumeScan();

  Stream<ScanProgress> scan({
    required String fileType,
    required bool scanDeleted,
  }) async* {
    if (_shouldUseMediaStore(fileType)) {
      bool usedFallback = false;
      try {
        final payload = await _mediaStoreScanner.scanAccessibleMedia(
          fileType: fileType,
          deletedOnly: scanDeleted,
        );

        final files = scanDeleted
            ? payload.files.where(isLikelyDeletedTrace).toList()
            : payload.files;

        // If strict deleted scan returns empty from MediaStore, fallback to
        // legacy trace scan so recycle/cache paths are still checked.
        if (scanDeleted && files.isEmpty) {
          usedFallback = true;
          yield* _scanWithLegacy(fileType, scanDeleted);
          return;
        }

        _lastScanResults = files;

        yield ScanProgress(
          progress: 0.15,
          currentFolder: 'MediaStore',
          filesFound: 0,
          status: 'Scanning storage...',
          phase: 'scanning',
          totalScanned: payload.scannedCount,
        );
        yield ScanProgress(
          progress: 0.55,
          currentFolder: 'MediaStore',
          filesFound: files.length,
          status: 'Indexing files...',
          phase: 'analysis',
          totalScanned: payload.scannedCount,
        );
        yield ScanProgress(
          progress: 0.85,
          currentFolder: 'MediaStore',
          filesFound: files.length,
          status: 'Categorizing media...',
          phase: 'analysis',
          totalScanned: payload.scannedCount,
        );
        yield ScanProgress(
          progress: 1.0,
          currentFolder: 'Complete',
          filesFound: files.length,
          status: files.isEmpty
              ? (scanDeleted
                  ? 'No recycle/cache traces found on this device. Only accessible and cached media can be restored.'
                  : 'No matching accessible media found.')
              : (scanDeleted
                  ? 'Found ${files.length} possible recoverable traces.'
                  : 'Found ${files.length} accessible files.'),
          phase: 'complete',
          totalScanned: payload.scannedCount,
        );
        return;
      } catch (e) {
        debugPrint('MediaStore scan fallback due to error: $e');
        if (!usedFallback) {
          yield* _scanWithLegacy(fileType, scanDeleted);
          return;
        }
      }
    }

    yield* _scanWithLegacy(fileType, scanDeleted);
  }

  Stream<ScanProgress> _scanWithLegacy(String fileType, bool scanDeleted) async* {
    final base = _baseStream(fileType, scanDeleted);
    await for (final progress in base) {
      final mapped = _mapPhaseStatus(progress);
      if (mapped.phase == 'complete') {
        _lastScanResults = List<RecoverableFile>.from(_scanner.lastScanResults);
      }
      yield mapped;
    }
  }

  bool _shouldUseMediaStore(String fileType) {
    if (!Platform.isAndroid) return false;
    return fileType == 'photo' || fileType == 'video' || fileType == 'file';
  }

  Stream<ScanProgress> _baseStream(String fileType, bool scanDeleted) {
    if (scanDeleted) {
      switch (fileType) {
        case 'photo':
          return _scanner.scanDeletedPhotos();
        case 'video':
          return _scanner.scanDeletedVideos();
        default:
          return _scanner.scanDeletedFiles();
      }
    }

    switch (fileType) {
      case 'photo':
        return _scanner.scanAllPhotos();
      case 'video':
        return _scanner.scanAllVideos();
      default:
        return _scanner.scanAllFiles();
    }
  }

  ScanProgress _mapPhaseStatus(ScanProgress progress) {
    String status = progress.status;
    String phase = progress.phase;

    if (phase == 'discovery' || phase == 'quick_scan' || phase == 'deep_scan') {
      status = 'Scanning storage...';
    } else if (phase == 'carving' || phase == 'cache_scan') {
      status = 'Indexing files...';
    } else if (phase == 'analysis') {
      status = 'Categorizing media...';
    }

    return ScanProgress(
      progress: progress.progress,
      currentFolder: progress.currentFolder,
      filesFound: progress.filesFound,
      status: status,
      phase: phase,
      totalScanned: progress.totalScanned,
      elapsedSeconds: progress.elapsedSeconds,
      folderCount: progress.folderCount,
      totalBytesScanned: progress.totalBytesScanned,
      signaturesMatched: progress.signaturesMatched,
      storageLocations: progress.storageLocations,
    );
  }

  bool isLikelyDeletedTrace(RecoverableFile file) {
    final category = MediaCategorizer.categorize(file);
    return category == MediaCategory.recycleBin ||
        category == MediaCategory.cacheThumbnail ||
        category == MediaCategory.messengerMedia;
  }
}
