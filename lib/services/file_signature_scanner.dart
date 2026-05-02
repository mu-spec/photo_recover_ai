import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/recoverable_file.dart';

/// Real file signature definitions for file carving.
/// Each signature has: magic bytes (header), optional footer, and max file size for recovery.
class FileSignature {
  final String name;
  final String extension;
  final List<int> headerBytes;
  final List<int>? footerBytes;
  final int headerOffset;
  final String fileType;

  const FileSignature({
    required this.name,
    required this.extension,
    required this.headerBytes,
    this.footerBytes,
    this.headerOffset = 0,
    required this.fileType,
  });
}

/// All supported file signatures for carving.
class FileSignatures {
  static const signatures = <FileSignature>[
    FileSignature(name: 'JPEG', extension: '.jpg', headerBytes: [0xFF, 0xD8, 0xFF], footerBytes: [0xFF, 0xD9], fileType: 'photo'),
    FileSignature(name: 'PNG', extension: '.png', headerBytes: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], footerBytes: [0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82], fileType: 'photo'),
    FileSignature(name: 'GIF', extension: '.gif', headerBytes: [0x47, 0x49, 0x46, 0x38], footerBytes: [0x00, 0x3B], fileType: 'photo'),
    FileSignature(name: 'BMP', extension: '.bmp', headerBytes: [0x42, 0x4D], fileType: 'photo'),
    FileSignature(name: 'WebP', extension: '.webp', headerBytes: [0x52, 0x49, 0x46, 0x46], footerBytes: [0x57, 0x45, 0x42, 0x50], fileType: 'photo'),
    FileSignature(name: 'HEIC', extension: '.heic', headerBytes: [0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70], fileType: 'photo'),
    FileSignature(name: 'TIFF_LE', extension: '.tiff', headerBytes: [0x49, 0x49, 0x2A, 0x00], fileType: 'photo'),
    FileSignature(name: 'TIFF_BE', extension: '.tiff', headerBytes: [0x4D, 0x4D, 0x00, 0x2A], fileType: 'photo'),
    FileSignature(name: 'MP4', extension: '.mp4', headerBytes: [0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70], fileType: 'video'),
    FileSignature(name: 'MP4_alt', extension: '.mp4', headerBytes: [0x00, 0x00, 0x00, 0x1C, 0x66, 0x74, 0x79, 0x70], fileType: 'video'),
    FileSignature(name: 'MP4_alt2', extension: '.mp4', headerBytes: [0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70], fileType: 'video'),
    FileSignature(name: '3GP', extension: '.3gp', headerBytes: [0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x33, 0x67, 0x70], fileType: 'video'),
    FileSignature(name: 'AVI', extension: '.avi', headerBytes: [0x52, 0x49, 0x46, 0x46], fileType: 'video'),
    FileSignature(name: 'MKV', extension: '.mkv', headerBytes: [0x1A, 0x45, 0xDF, 0xA3], fileType: 'video'),
    FileSignature(name: 'FLV', extension: '.flv', headerBytes: [0x46, 0x4C, 0x56], fileType: 'video'),
    FileSignature(name: 'MOV', extension: '.mov', headerBytes: [0x00, 0x00, 0x00, 0x14, 0x66, 0x74, 0x79, 0x70], fileType: 'video'),
    FileSignature(name: 'MP3_ID3', extension: '.mp3', headerBytes: [0x49, 0x44, 0x33], fileType: 'audio'),
    FileSignature(name: 'MP3_sync', extension: '.mp3', headerBytes: [0xFF, 0xFB], fileType: 'audio'),
    FileSignature(name: 'WAV', extension: '.wav', headerBytes: [0x52, 0x49, 0x46, 0x46], fileType: 'audio'),
    FileSignature(name: 'FLAC', extension: '.flac', headerBytes: [0x66, 0x4C, 0x61, 0x43], fileType: 'audio'),
    FileSignature(name: 'OGG', extension: '.ogg', headerBytes: [0x4F, 0x67, 0x67, 0x53], fileType: 'audio'),
    FileSignature(name: 'PDF', extension: '.pdf', headerBytes: [0x25, 0x50, 0x44, 0x46], footerBytes: [0x25, 0x25, 0x45, 0x4F, 0x46], fileType: 'document'),
    FileSignature(name: 'ZIP', extension: '.zip', headerBytes: [0x50, 0x4B, 0x03, 0x04], fileType: 'document'),
    FileSignature(name: 'RAR', extension: '.rar', headerBytes: [0x52, 0x61, 0x72, 0x21], fileType: 'document'),
  ];
}

/// Fragment status for carved files.
enum FragmentStatus {
  complete,
  partial,
  corrupted,
  oversized,
}

/// Result of a file carving operation.
class CarvedFileResult {
  final String name;
  final String extension;
  final int startOffset;
  final int size;
  final String fileType;
  final String signatureName;
  final FragmentStatus fragmentStatus;
  final double confidenceScore;

  CarvedFileResult({
    required this.name,
    required this.extension,
    required this.startOffset,
    required this.size,
    required this.fileType,
    required this.signatureName,
    required this.fragmentStatus,
    required this.confidenceScore,
  });
}

/// Progress callback for deep scan.
class DeepScanProgress {
  final double progress;
  final String status;
  final int bytesScanned;
  final int filesFound;
  final int currentChunk;
  final int totalChunks;
  final String phase;

  DeepScanProgress({
    required this.progress,
    required this.status,
    this.bytesScanned = 0,
    this.filesFound = 0,
    this.currentChunk = 0,
    this.totalChunks = 0,
    required this.phase,
  });
}

/// The core file carving engine.
/// Scans raw bytes of storage to find file signatures and extract embedded files.
class FileSignatureScanner {
  static const int maxCarveSize = 50 * 1024 * 1024;
  static const int minCarveSize = 512;
  static const int scanChunkSize = 64 * 1024;
  static const int maxHeaderLength = 32;

  bool _isCancelled = false;

  void cancel() => _isCancelled = true;
  void reset() => _isCancelled = false;

  /// Scan a single file for embedded file signatures (file carving).
  Stream<DeepScanProgress> carveFile(String filePath, String source) async* {
    reset();
    final file = File(filePath);
    if (!await file.exists()) return;

    final fileSize = await file.length();
    if (fileSize < minCarveSize || fileSize > 2 * 1024 * 1024 * 1024) return;

    final totalChunks = (fileSize / scanChunkSize).ceil();
    int filesFound = 0;

    yield DeepScanProgress(progress: 0.0, status: 'Opening $source...', bytesScanned: 0, filesFound: 0, currentChunk: 0, totalChunks: totalChunks, phase: 'reading');

    try {
      final raf = await file.open(mode: FileMode.read);
      final overlapBuffer = <int>[];
      final allResults = <CarvedFileResult>[];

      for (int chunk = 0; chunk < totalChunks; chunk++) {
        if (_isCancelled) break;

        final offset = chunk * scanChunkSize;
        final bytesToRead = (offset + scanChunkSize > fileSize) ? fileSize - offset : scanChunkSize;
        final chunkData = await raf.read(bytesToRead);
        final scanData = [...overlapBuffer, ...chunkData];

        overlapBuffer.clear();
        if (chunk < totalChunks - 1 && scanData.length > maxHeaderLength) {
          overlapBuffer.addAll(scanData.sublist(scanData.length - maxHeaderLength + 1));
        }

        final results = _findSignaturesInBuffer(scanData, offset - (scanData.length - bytesToRead), source);
        allResults.addAll(results);
        filesFound = allResults.length;

        yield DeepScanProgress(
          progress: ((chunk + 1) / totalChunks).clamp(0.0, 1.0),
          status: 'Scanning chunk ${chunk + 1}/$totalChunks...',
          bytesScanned: offset + bytesToRead,
          filesFound: filesFound,
          currentChunk: chunk + 1,
          totalChunks: totalChunks,
          phase: 'matching',
        );
      }

      await raf.close();
    } catch (e) {
      debugPrint('File carving error for $filePath: $e');
    }

    yield DeepScanProgress(progress: 1.0, status: 'Complete - found $filesFound embedded files', bytesScanned: fileSize, filesFound: filesFound, totalChunks: totalChunks, phase: 'complete');
  }

  List<CarvedFileResult> _findSignaturesInBuffer(List<int> buffer, int globalOffset, String source) {
    final results = <CarvedFileResult>[];
    final scannedPositions = <int>{};

    for (final sig in FileSignatures.signatures) {
      final header = sig.headerBytes;
      if (header.isEmpty) continue;

      for (int i = sig.headerOffset; i <= buffer.length - header.length; i++) {
        if (scannedPositions.contains(i)) continue;

        bool match = true;
        for (int j = 0; j < header.length; j++) {
          if (buffer[i + j] != header[j]) { match = false; break; }
        }
        if (!match) continue;
        scannedPositions.add(i);

        final foundStart = i;
        int foundEnd = buffer.length;

        if (sig.footerBytes != null) {
          final footer = sig.footerBytes!;
          for (int k = foundStart + header.length + 1; k <= buffer.length - footer.length; k++) {
            bool footerMatch = true;
            for (int f = 0; f < footer.length; f++) {
              if (buffer[k + f] != footer[f]) { footerMatch = false; break; }
            }
            if (footerMatch) { foundEnd = k + footer.length; break; }
          }
        } else {
          foundEnd = (foundStart + maxCarveSize).clamp(0, buffer.length);
          if (header.length >= 3 && header[0] == 0xFF && header[1] == 0xD8) {
            for (int k = foundStart + 4; k < buffer.length - 1; k++) {
              if (buffer[k] == 0xFF && buffer[k + 1] == 0xD8) { foundEnd = k; break; }
              if (buffer[k] == 0xFF && buffer[k + 1] == 0xD9) { foundEnd = k + 2; break; }
            }
          }
        }

        final size = foundEnd - foundStart;
        if (size < minCarveSize) continue;

        FragmentStatus status;
        double confidence;

        if (size > maxCarveSize) {
          status = FragmentStatus.oversized; confidence = 0.3;
        } else if (sig.footerBytes != null && foundEnd < buffer.length) {
          status = FragmentStatus.complete; confidence = 0.95;
        } else if (sig.footerBytes != null) {
          status = FragmentStatus.partial; confidence = 0.6;
        } else {
          status = FragmentStatus.complete; confidence = 0.7;
        }

        results.add(CarvedFileResult(
          name: 'carved_${globalOffset + foundStart}',
          extension: sig.extension,
          startOffset: globalOffset + foundStart,
          size: size,
          fileType: sig.fileType,
          signatureName: sig.name,
          fragmentStatus: status,
          confidenceScore: confidence,
        ));
      }
    }

    return results;
  }

  /// Extract a carved file from a source file.
  Future<bool> extractCarvedFile({
    required String sourceFile,
    required int offset,
    required int size,
    required String outputPath,
  }) async {
    try {
      final input = File(sourceFile);
      if (!await input.exists()) return false;
      final raf = await input.open(mode: FileMode.read);
      await raf.setPosition(offset);
      final bytes = await raf.read(size);
      await raf.close();
      if (bytes.isEmpty) return false;
      final output = File(outputPath);
      await output.create(recursive: true);
      await output.writeAsBytes(bytes);
      return true;
    } catch (e) {
      debugPrint('Extract carved file error: $e');
      return false;
    }
  }

  /// Quick header check - validates if a file has the expected signature.
  Future<FileSignature?> identifyFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final raf = await file.open(mode: FileMode.read);
      final headerBytes = await raf.read(maxHeaderLength);
      await raf.close();

      for (final sig in FileSignatures.signatures) {
        if (headerBytes.length < sig.headerBytes.length + sig.headerOffset) continue;
        bool match = true;
        for (int i = 0; i < sig.headerBytes.length; i++) {
          if (headerBytes[sig.headerOffset + i] != sig.headerBytes[i]) { match = false; break; }
        }
        if (match) return sig;
      }
    } catch (_) {}
    return null;
  }

  /// Validate a file by checking header and footer signatures.
  Future<String> validateFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return 'unknown';
      final fileSize = await file.length();
      if (fileSize < 4) return 'unknown';

      final raf = await file.open(mode: FileMode.read);
      final headerBytes = await raf.read(maxHeaderLength);

      if (fileSize > 16) {
        await raf.setPosition(fileSize - 16);
      }
      final footerBytes = await raf.read(16);
      await raf.close();

      FileSignature? matchedSig;
      for (final sig in FileSignatures.signatures) {
        if (headerBytes.length < sig.headerBytes.length + sig.headerOffset) continue;
        bool match = true;
        for (int i = 0; i < sig.headerBytes.length; i++) {
          if (headerBytes[sig.headerOffset + i] != sig.headerBytes[i]) { match = false; break; }
        }
        if (match) { matchedSig = sig; break; }
      }

      if (matchedSig == null) return 'corrupted';

      if (matchedSig.footerBytes != null) {
        final footer = matchedSig.footerBytes!;
        for (int i = footerBytes.length - footer.length; i >= 0; i--) {
          bool match = true;
          for (int f = 0; f < footer.length; f++) {
            if (footerBytes[i + f] != footer[f]) { match = false; break; }
          }
          if (match) return 'valid';
        }
        return 'partial';
      }
      return 'valid';
    } catch (_) {
      return 'unknown';
    }
  }

  /// Calculate a confidence score for how recoverable a file is.
  Future<double> calculateRecoverability(RecoverableFile file) async {
    double score = 50.0;
    if (file.size < 1024) score -= 20;
    else if (file.size > 100000) score += 15;
    else if (file.size > 1000000) score += 20;

    final src = file.source.toLowerCase();
    if (src.contains('camera') || src.contains('dcim')) score += 15;
    else if (src.contains('whatsapp') || src.contains('telegram')) score += 10;
    else if (src.contains('trash') || src.contains('deleted')) score -= 10;

    if (file.qualityTag == 'thumbnail') score -= 20;
    else if (file.qualityTag == 'corrupted') score -= 30;

    final daysOld = DateTime.now().difference(file.lastModified).inDays;
    if (daysOld < 7) score += 10;
    else if (daysOld > 365) score -= 10;

    final sig = await identifyFile(file.path);
    if (sig != null) score += 10;

    return score.clamp(0.0, 100.0);
  }
}
