import 'dart:io';

class RecoverableFile {
  final String id;
  final String name;
  final String path;
  final String extension;
  final int size;
  final DateTime lastModified;
  final String fileType; // 'photo', 'video', 'file'
  final String source; // 'DCIM', 'WhatsApp', 'Downloads', 'Cache', 'Hidden', 'Recently Deleted'
  final bool isRecovered;
  String? qualityTag; // 'high', 'thumbnail', 'corrupted', 'low', 'recovered', 'partial', or null

  // Enhanced fields
  String? cameraInfo;      // Camera make/model from EXIF
  String? resolution;      // Image dimensions (e.g., "1920x1080")
  String? gpsLocation;     // GPS coordinates from EXIF
  DateTime? dateTaken;     // Original capture date from EXIF
  int? orientation;         // EXIF orientation
  String? software;         // Software used
  int? iso;                 // ISO value
  double? corruptionLevel;  // 0.0 = perfect, 1.0 = corrupted
  bool isNewFile;           // Not seen in previous scan (incremental)

  RecoverableFile({
    required this.id,
    required this.name,
    required this.path,
    required this.extension,
    required this.size,
    required this.lastModified,
    required this.fileType,
    required this.source,
    this.isRecovered = false,
    this.qualityTag,
    this.cameraInfo,
    this.resolution,
    this.gpsLocation,
    this.dateTaken,
    this.orientation,
    this.software,
    this.iso,
    this.corruptionLevel,
    this.isNewFile = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'extension': extension,
      'size': size,
      'lastModified': lastModified.millisecondsSinceEpoch,
      'fileType': fileType,
      'source': source,
      'isRecovered': isRecovered ? 1 : 0,
      'qualityTag': qualityTag,
      'cameraInfo': cameraInfo,
      'resolution': resolution,
      'gpsLocation': gpsLocation,
      'dateTaken': dateTaken?.millisecondsSinceEpoch,
      'orientation': orientation,
      'software': software,
      'iso': iso,
      'corruptionLevel': corruptionLevel,
      'isNewFile': isNewFile ? 1 : 0,
    };
  }

  factory RecoverableFile.fromMap(Map<String, dynamic> map) {
    return RecoverableFile(
      id: map['id'],
      name: map['name'],
      path: map['path'],
      extension: map['extension'],
      size: map['size'],
      lastModified: DateTime.fromMillisecondsSinceEpoch(map['lastModified']),
      fileType: map['fileType'],
      source: map['source'],
      isRecovered: map['isRecovered'] == 1,
      qualityTag: map['qualityTag'],
      cameraInfo: map['cameraInfo'],
      resolution: map['resolution'],
      gpsLocation: map['gpsLocation'],
      dateTaken: map['dateTaken'] != null ? DateTime.fromMillisecondsSinceEpoch(map['dateTaken']) : null,
      orientation: map['orientation'],
      software: map['software'],
      iso: map['iso'],
      corruptionLevel: map['corruptionLevel'] != null ? (map['corruptionLevel'] as num).toDouble() : null,
      isNewFile: map['isNewFile'] == 1,
    );
  }

  bool get exists => File(path).existsSync();
  String get formattedSize => formatFileSize(size);
  String get formattedDate =>
      '${lastModified.day}/${lastModified.month}/${lastModified.year} ${lastModified.hour}:${lastModified.minute.toString().padLeft(2, '0')}';

  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1073741824) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1073741824).toStringAsFixed(1)} GB';
  }
}

class RecoveryRecord {
  final String id;
  final String fileName;
  final String originalPath;
  final String recoveredPath;
  final String fileType;
  final DateTime recoveredAt;
  final int fileSize;

  RecoveryRecord({
    required this.id,
    required this.fileName,
    required this.originalPath,
    required this.recoveredPath,
    required this.fileType,
    required this.recoveredAt,
    required this.fileSize,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fileName': fileName,
      'originalPath': originalPath,
      'recoveredPath': recoveredPath,
      'fileType': fileType,
      'recoveredAt': recoveredAt.millisecondsSinceEpoch,
      'fileSize': fileSize,
    };
  }

  factory RecoveryRecord.fromMap(Map<String, dynamic> map) {
    return RecoveryRecord(
      id: map['id'],
      fileName: map['fileName'],
      originalPath: map['originalPath'],
      recoveredPath: map['recoveredPath'],
      fileType: map['fileType'],
      recoveredAt: DateTime.fromMillisecondsSinceEpoch(map['recoveredAt']),
      fileSize: map['fileSize'],
    );
  }

  String get formattedDate =>
      '${recoveredAt.day}/${recoveredAt.month}/${recoveredAt.year}';
  String get formattedSize => RecoverableFile.formatFileSize(fileSize);
}
