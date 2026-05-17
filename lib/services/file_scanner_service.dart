import '../models/recoverable_file.dart';
import 'media_categorizer.dart';
import 'storage_scanner.dart';

class FileScannerService {
  final StorageScanner _scanner = StorageScanner();

  List<RecoverableFile> get lastScanResults => _scanner.lastScanResults;

  void cancelScan() => _scanner.cancelScan();
  void resetCancel() => _scanner.resetCancel();
  void pauseScan() => _scanner.pauseScan();
  void resumeScan() => _scanner.resumeScan();

  Stream<ScanProgress> scan({
    required String fileType,
    required bool scanDeleted,
  }) async* {
    final base = _baseStream(fileType, scanDeleted);

    await for (final progress in base) {
      final mapped = _mapPhaseStatus(progress);
      yield mapped;
    }
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

