import 'dart:io';
import 'dart:typed_data';

/// Repair corrupted files and attempt JPEG recovery from damaged data
class FileRepairService {

  /// Attempt to repair a JPEG file with corrupted/missing header
  /// Returns the path to the repaired file, or null if repair failed
  static Future<String?> repairJpeg(String originalPath) async {
    try {
      final file = File(originalPath);
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.length < 100) return null;

      // Check if JPEG header is corrupted
      final needsSoiRepair = bytes[0] != 0xFF || bytes[1] != 0xD8;

      if (!needsSoiRepair) {
        // Check if EOI marker is missing
        if (bytes.length >= 2 && bytes[bytes.length - 2] != 0xFF && bytes[bytes.length - 1] != 0xD9) {
          // Append EOI marker
          final repaired = Uint8List(bytes.length + 2);
          for (int i = 0; i < bytes.length; i++) {
            repaired[i] = bytes[i];
          }
          repaired[bytes.length] = 0xFF;
          repaired[bytes.length + 1] = 0xD9;
          return _writeRepairedFile(originalPath, repaired);
        }
        return null; // File doesn't need repair
      }

      // Find JPEG data start (look for JFIF or EXIF markers after SOI)
      int dataStart = -1;
      for (int i = 0; i < bytes.length - 4; i++) {
        // Look for JFIF marker
        if (bytes[i] == 0xFF && bytes[i + 1] == 0xE0 &&
            bytes[i + 2] == 0x00 && bytes[i + 3] == 0x10) {
          dataStart = i;
          break;
        }
        // Look for EXIF marker
        if (bytes[i] == 0xFF && bytes[i + 1] == 0xE1) {
          dataStart = i;
          break;
        }
        // Look for SOF marker (start of frame)
        if (bytes[i] == 0xFF && bytes[i + 1] >= 0xC0 && bytes[i + 1] <= 0xCF) {
          dataStart = i;
          break;
        }
        // Look for SOS marker (start of scan)
        if (bytes[i] == 0xFF && bytes[i + 1] == 0xDA) {
          dataStart = i;
          break;
        }
      }

      if (dataStart == -1) {
        // Try to find raw JPEG scan data (FFD9 end marker)
        for (int i = bytes.length - 1; i >= 2; i--) {
          if (bytes[i] == 0xD9 && bytes[i - 1] == 0xFF) {
            dataStart = 0;
            break;
          }
        }
        if (dataStart == -1) return null;
      }

      // Build repaired JPEG: SOI + original data + EOI
      final hasEoi = bytes.length >= 2 &&
          bytes[bytes.length - 2] == 0xFF && bytes[bytes.length - 1] == 0xD9;

      final headerSize = 2; // SOI
      final eoiSize = hasEoi ? 0 : 2;
      final repaired = Uint8List(headerSize + bytes.length + eoiSize);

      // Write SOI
      repaired[0] = 0xFF;
      repaired[1] = 0xD8;

      // Copy original data
      for (int i = 0; i < bytes.length; i++) {
        repaired[headerSize + i] = bytes[i];
      }

      // Write EOI if needed
      if (!hasEoi) {
        repaired[headerSize + bytes.length] = 0xFF;
        repaired[headerSize + bytes.length + 1] = 0xD9;
      }

      return _writeRepairedFile(originalPath, repaired);
    } catch (_) {
      return null;
    }
  }

  /// Repair PNG file with corrupted header
  static Future<String?> repairPng(String originalPath) async {
    try {
      final file = File(originalPath);
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.length < 24) return null;

      final pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      bool needsRepair = false;
      for (int i = 0; i < 8; i++) {
        if (bytes[i] != pngSignature[i]) {
          needsRepair = true;
          break;
        }
      }

      if (!needsRepair) return null;

      // Replace first 8 bytes with correct PNG signature
      final repaired = Uint8List.fromList(bytes);
      for (int i = 0; i < 8; i++) {
        repaired[i] = pngSignature[i];
      }

      return _writeRepairedFile(originalPath, repaired);
    } catch (_) {
      return null;
    }
  }

  /// Attempt to repair MP4/MOV file with corrupted ftyp box
  static Future<String?> repairMp4(String originalPath) async {
    try {
      final file = File(originalPath);
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.length < 20) return null;

      // Check if ftyp is present but at wrong offset
      bool hasFtyp = false;
      int ftypOffset = -1;
      for (int i = 0; i < bytes.length - 8; i++) {
        if (bytes[i] == 0x66 && bytes[i + 1] == 0x74 &&
            bytes[i + 2] == 0x79 && bytes[i + 3] == 0x70) {
          hasFtyp = true;
          ftypOffset = i;
          break;
        }
      }

      if (!hasFtyp || ftypOffset <= 0) return null;

      // File probably has garbage before ftyp, trim it
      final repaired = Uint8List.fromList(bytes.sublist(ftypOffset - 4));
      // Fix the box size to match remaining data
      final boxSize = repaired.length;
      repaired[0] = (boxSize >> 24) & 0xFF;
      repaired[1] = (boxSize >> 16) & 0xFF;
      repaired[2] = (boxSize >> 8) & 0xFF;
      repaired[3] = boxSize & 0xFF;

      return _writeRepairedFile(originalPath, repaired);
    } catch (_) {
      return null;
    }
  }

  /// Generic repair attempt based on file extension
  static Future<String?> attemptRepair(String path) async {
    final ext = path.toLowerCase();
    if (ext.endsWith('.jpg') || ext.endsWith('.jpeg')) {
      return repairJpeg(path);
    } else if (ext.endsWith('.png')) {
      return repairPng(path);
    } else if (ext.endsWith('.mp4') || ext.endsWith('.mov') || ext.endsWith('.m4v')) {
      return repairMp4(path);
    }
    return null;
  }

  /// Assess corruption level of a file (0.0 = perfect, 1.0 = completely corrupted)
  static double assessCorruption(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return 1.0;

      final ext = path.toLowerCase();
      final bytes = file.readAsBytesSync();
      if (bytes.length < 10) return 1.0;

      if (ext.endsWith('.jpg') || ext.endsWith('.jpeg')) {
        return _assessJpegCorruption(bytes);
      } else if (ext.endsWith('.png')) {
        return _assessPngCorruption(bytes);
      } else if (ext.endsWith('.mp4') || ext.endsWith('.mov')) {
        return _assessMp4Corruption(bytes);
      }
      return 0.0; // Unknown format, assume OK
    } catch (_) {
      return 1.0;
    }
  }

  static double _assessJpegCorruption(Uint8List bytes) {
    double corruption = 0.0;
    // Missing SOI
    if (bytes[0] != 0xFF || bytes[1] != 0xD8) corruption += 0.3;
    // Missing EOI
    if (bytes.length >= 2 &&
        !(bytes[bytes.length - 2] == 0xFF && bytes[bytes.length - 1] == 0xD9)) {
      corruption += 0.2;
    }
    // Check for valid markers throughout the file
    int validMarkers = 0;
    int totalChecks = 0;
    for (int i = 0; i < bytes.length - 1 && i < 10000; i += 100) {
      totalChecks++;
      if (bytes[i] == 0xFF && bytes[i + 1] != 0x00 && bytes[i + 1] != 0xFF) {
        validMarkers++;
      }
    }
    if (totalChecks > 0 && validMarkers / totalChecks < 0.1) {
      corruption += 0.3;
    }
    return corruption.clamp(0.0, 1.0);
  }

  static double _assessPngCorruption(Uint8List bytes) {
    if (bytes.length < 8) return 1.0;
    final pngSig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    for (int i = 0; i < 8; i++) {
      if (bytes[i] != pngSig[i]) return 0.5;
    }
    // Check for IEND chunk near end
    if (bytes.length >= 8) {
      final iend = [0x49, 0x45, 0x4E, 0x44]; // IEND
      bool found = false;
      for (int i = bytes.length - 12; i < bytes.length - 4; i++) {
        if (bytes[i] == iend[0] && bytes[i + 1] == iend[1] &&
            bytes[i + 2] == iend[2] && bytes[i + 3] == iend[3]) {
          found = true;
          break;
        }
      }
      if (!found) return 0.2;
    }
    return 0.0;
  }

  static double _assessMp4Corruption(Uint8List bytes) {
    if (bytes.length < 8) return 1.0;
    // Check for ftyp
    bool hasFtyp = false;
    for (int i = 0; i < bytes.length - 8 && i < 100; i++) {
      if (bytes[i] == 0x66 && bytes[i + 1] == 0x74 &&
          bytes[i + 2] == 0x79 && bytes[i + 3] == 0x70) {
        hasFtyp = true;
        break;
      }
    }
    return hasFtyp ? 0.0 : 0.5;
  }

  static Future<String?> _writeRepairedFile(String originalPath, Uint8List repairedBytes) async {
    try {
      final file = File(originalPath);
      final dir = file.parent;
      final name = file.path.split('/').last;
      final nameWithoutExt = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
      final ext = name.contains('.') ? name.substring(name.lastIndexOf('.')) : '';
      final repairedPath = '${dir.path}/$nameWithoutExt\_repaired$ext';
      final repairedFile = File(repairedPath);
      await repairedFile.writeAsBytes(repairedBytes);
      return repairedPath;
    } catch (_) {
      return null;
    }
  }

  /// Extract recoverable JPEG data from a larger file (file carving)
  static List<String> carveJpegFromData(String sourcePath) {
    final results = <String>[];
    try {
      final file = File(sourcePath);
      if (!file.existsSync()) return results;
      final bytes = file.readAsBytesSync();
      if (bytes.length < 100) return results;

      // Find all SOI markers
      final soiPositions = <int>[];
      for (int i = 0; i < bytes.length - 1; i++) {
        if (bytes[i] == 0xFF && bytes[i + 1] == 0xD8) {
          // Verify it looks like a real JPEG start
          if (i + 4 < bytes.length && bytes[i + 2] == 0xFF) {
            soiPositions.add(i);
          }
        }
      }

      for (final soiPos in soiPositions) {
        // Find corresponding EOI
        int eoiPos = -1;
        for (int i = soiPos + 2; i < bytes.length - 1; i++) {
          if (bytes[i] == 0xFF && bytes[i + 1] == 0xD9) {
            eoiPos = i + 2;
            break;
          }
        }

        if (eoiPos > soiPos && (eoiPos - soiPos) > 1000) {
          // Extract the JPEG
          final jpegData = Uint8List.fromList(bytes.sublist(soiPos, eoiPos));
          final dir = file.parent;
          final carvedName = '${sourcePath.split('/').last}_carved_${soiPos}.jpg';
          final carvedPath = '${dir.path}/$carvedName';
          File(carvedPath).writeAsBytesSync(jpegData);
          results.add(carvedPath);
        }
      }
    } catch (_) {}
    return results;
  }

  /// Extract recoverable MP4 data from a larger file
  static List<String> carveMp4FromData(String sourcePath) {
    final results = <String>[];
    try {
      final file = File(sourcePath);
      if (!file.existsSync()) return results;
      final bytes = file.readAsBytesSync();
      if (bytes.length < 100) return results;

      // Find ftyp boxes
      for (int i = 0; i < bytes.length - 12; i++) {
        if (bytes[i + 4] == 0x66 && bytes[i + 5] == 0x74 &&
            bytes[i + 6] == 0x79 && bytes[i + 7] == 0x70) {
          // Read box size
          final boxSize = (bytes[i] << 24) | (bytes[i + 1] << 16) |
              (bytes[i + 2] << 8) | bytes[i + 3];
          if (boxSize > 8 && boxSize < bytes.length - i) {
            final mp4Data = bytes.sublist(i, i + boxSize);
            if (mp4Data.length > 1000) {
              final dir = file.parent;
              final carvedName = '${sourcePath.split('/').last}_carved_${i}.mp4';
              final carvedPath = '${dir.path}/$carvedName';
              File(carvedPath).writeAsBytesSync(mp4Data);
              results.add(carvedPath);
            }
          }
        }
      }
    } catch (_) {}
    return results;
  }
}
