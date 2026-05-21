import 'package:flutter/services.dart';

import '../models/recoverable_file.dart';

class MediaStoreScanPayload {
  final List<RecoverableFile> files;
  final int scannedCount;

  const MediaStoreScanPayload({
    required this.files,
    required this.scannedCount,
  });
}

class MediaStoreScannerService {
  static const MethodChannel _channel =
      MethodChannel('photo_recover_ai/media_store');

  Future<MediaStoreScanPayload> scanAccessibleMedia({
    required String fileType,
    required bool deletedOnly,
  }) async {
    final dynamic raw = await _channel.invokeMethod(
      'scanAccessibleMedia',
      <String, dynamic>{
        'fileType': fileType,
        'deletedOnly': deletedOnly,
      },
    );

    if (raw is! Map) {
      return const MediaStoreScanPayload(files: <RecoverableFile>[], scannedCount: 0);
    }

    final scannedCount = (raw['scannedCount'] as num?)?.toInt() ?? 0;
    final filesRaw = raw['files'];
    if (filesRaw is! List) {
      return MediaStoreScanPayload(files: const <RecoverableFile>[], scannedCount: scannedCount);
    }

    final files = <RecoverableFile>[];
    for (final item in filesRaw) {
      if (item is! Map) continue;

      final name = (item['name'] ?? '').toString();
      final path = (item['path'] ?? '').toString();
      if (name.isEmpty || path.isEmpty) continue;

      final extension = _extensionFromName(name, fallback: (item['extension'] ?? '').toString());
      final size = (item['size'] as num?)?.toInt() ?? 0;
      final modifiedMs = (item['lastModifiedMs'] as num?)?.toInt() ?? 0;
      final source = (item['source'] ?? 'Accessible Media').toString();
      final id = (item['id'] ?? path).toString();
      final qualityTag = (item['qualityTag'] as String?)?.trim();

      files.add(
        RecoverableFile(
          id: id,
          name: name,
          path: path,
          extension: extension,
          size: size,
          lastModified: modifiedMs > 0
              ? DateTime.fromMillisecondsSinceEpoch(modifiedMs)
              : DateTime.now(),
          fileType: fileType,
          source: source,
          qualityTag: qualityTag?.isNotEmpty == true ? qualityTag : null,
        ),
      );
    }

    return MediaStoreScanPayload(files: files, scannedCount: scannedCount);
  }

  String _extensionFromName(String name, {String fallback = ''}) {
    if (fallback.isNotEmpty) {
      return fallback.startsWith('.') ? fallback : '.$fallback';
    }
    final idx = name.lastIndexOf('.');
    if (idx < 0 || idx == name.length - 1) return '';
    return name.substring(idx).toLowerCase();
  }
}

