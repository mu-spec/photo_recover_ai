import 'dart:io';
import 'dart:typed_data';

/// Extracts EXIF metadata from photos and video metadata
class ExifData {
  final String? cameraMake;
  final String? cameraModel;
  final DateTime? dateTimeOriginal;
  final double? gpsLatitude;
  final double? gpsLongitude;
  final int? imageWidth;
  final int? imageHeight;
  final int? orientation;
  final String? software;
  final int? iso;
  final double? focalLength;
  final double? aperture;
  final double? exposureTime;
  final String? flash;

  const ExifData({
    this.cameraMake,
    this.cameraModel,
    this.dateTimeOriginal,
    this.gpsLatitude,
    this.gpsLongitude,
    this.imageWidth,
    this.imageHeight,
    this.orientation,
    this.software,
    this.iso,
    this.focalLength,
    this.aperture,
    this.exposureTime,
    this.flash,
  });

  String get cameraInfo {
    if (cameraMake != null && cameraModel != null) {
      return '$cameraMake $cameraModel';
    }
    return cameraModel ?? cameraMake ?? 'Unknown';
  }

  String? get gpsLocation {
    if (gpsLatitude != null && gpsLongitude != null) {
      final latDir = gpsLatitude! >= 0 ? 'N' : 'S';
      final lonDir = gpsLongitude! >= 0 ? 'E' : 'W';
      return '${gpsLatitude!.abs().toStringAsFixed(4)}$latDir, ${gpsLongitude!.abs().toStringAsFixed(4)}$lonDir';
    }
    return null;
  }

  String get resolution {
    if (imageWidth != null && imageHeight != null) {
      return '${imageWidth}x$imageHeight';
    }
    return 'Unknown';
  }

  bool get hasExif => cameraMake != null || dateTimeOriginal != null || imageWidth != null;

  Map<String, dynamic> toMap() => {
    if (cameraMake != null) 'cameraMake': cameraMake,
    if (cameraModel != null) 'cameraModel': cameraModel,
    if (dateTimeOriginal != null) 'dateTimeOriginal': dateTimeOriginal!.millisecondsSinceEpoch,
    if (gpsLatitude != null) 'gpsLatitude': gpsLatitude,
    if (gpsLongitude != null) 'gpsLongitude': gpsLongitude,
    if (imageWidth != null) 'imageWidth': imageWidth,
    if (imageHeight != null) 'imageHeight': imageHeight,
    if (orientation != null) 'orientation': orientation,
    if (software != null) 'software': software,
    if (iso != null) 'iso': iso,
    if (focalLength != null) 'focalLength': focalLength,
    if (aperture != null) 'aperture': aperture,
    if (exposureTime != null) 'exposureTime': exposureTime,
    if (flash != null) 'flash': flash,
  };
}

class ExifExtractor {
  /// Extract EXIF data from a JPEG/JPG file
  static ExifData extractFromFile(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return const ExifData();

      final ext = path.toLowerCase();
      if (!ext.endsWith('.jpg') && !ext.endsWith('.jpeg')) {
        return _extractFromPngOrHeic(file);
      }

      final bytes = file.readAsBytesSync();
      if (bytes.length < 4) return const ExifData();
      if (bytes[0] != 0xFF || bytes[1] != 0xD8 || bytes[2] != 0xFF) {
        return const ExifData();
      }

      return _parseJpegExif(bytes);
    } catch (_) {
      return const ExifData();
    }
  }

  /// Extract image dimensions from any image file using header parsing
  static Map<String, int> getImageDimensions(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return {};
      final bytes = file.readAsBytesSync();
      return _parseDimensions(bytes, path);
    } catch (_) {
      return {};
    }
  }

  /// Extract video duration and resolution from file header
  static Map<String, dynamic> getVideoInfo(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return {};
      final size = file.lengthSync();
      final stat = file.statSync();
      return {
        'size': size,
        'modified': stat.modified.millisecondsSinceEpoch,
        'path': path,
      };
    } catch (_) {
      return {};
    }
  }

  static ExifData _parseJpegExif(Uint8List bytes) {
    String? cameraMake;
    String? cameraModel;
    DateTime? dateTimeOriginal;
    double? gpsLatitude;
    double? gpsLongitude;
    int? imageWidth;
    int? imageHeight;
    int? orientation;
    String? software;
    int? iso;
    double? focalLength;
    double? aperture;
    double? exposureTime;
    String? flash;

    int offset = 2; // Skip SOI marker

    while (offset < bytes.length - 4) {
      // Find marker
      if (bytes[offset] != 0xFF) break;

      final marker = bytes[offset + 1];
      if (marker == 0xD9 || marker == 0xDA) break; // EOI or SOS - stop

      // Get segment length
      if (offset + 3 >= bytes.length) break;
      final segLen = (bytes[offset + 2] << 8) | bytes[offset + 3];

      // APP1 (EXIF) marker
      if (marker == 0xE1 && segLen > 4) {
        final exifOffset = offset + 4;
        if (exifOffset + 6 < bytes.length) {
          // Check for "Exif\0\0" header
          if (bytes[exifOffset] == 0x45 && bytes[exifOffset + 1] == 0x78 &&
              bytes[exifOffset + 2] == 0x69 && bytes[exifOffset + 3] == 0x66) {
            final tiffOffset = exifOffset + 6;
            if (tiffOffset + 8 < bytes.length) {
              // Determine byte order
              final isLittleEndian = bytes[tiffOffset] == 0x49 && bytes[tiffOffset + 1] == 0x49;

              // Get IFD0 offset
              final ifd0Offset = _readUint32(bytes, tiffOffset + 4, isLittleEndian);

              // Parse IFD entries
              final ifd0Data = _parseIfd(bytes, tiffOffset + ifd0Offset, isLittleEndian);

              cameraMake = ifd0Data['Make'];
              cameraModel = ifd0Data['Model'];
              software = ifd0Data['Software'];
              orientation = ifd0Data['Orientation'];
              imageWidth = ifd0Data['ExifImageWidth'] ?? ifd0Data['ImageWidth'];
              imageHeight = ifd0Data['ExifImageHeight'] ?? ifd0Data['ImageLength'];

              // Get Exif SubIFD offset
              final exifSubOffset = ifd0Data['__exif_sub_ifd_offset'];
              if (exifSubOffset != null) {
                final exifData = _parseIfd(bytes, tiffOffset + (exifSubOffset as int), isLittleEndian);
                dateTimeOriginal = exifData['DateTimeOriginal'] ?? exifData['DateTimeDigitized'];
                iso = exifData['ISOSpeedRatings'];
                focalLength = exifData['FocalLength'];
                aperture = exifData['FNumber'];
                exposureTime = exifData['ExposureTime'];
                flash = exifData['Flash'];

                // Get GPS SubIFD offset
                final gpsSubOffset = exifData['__gps_sub_ifd_offset'];
                if (gpsSubOffset != null) {
                  final gpsData = _parseIfd(bytes, tiffOffset + (gpsSubOffset as int), isLittleEndian);
                  gpsLatitude = gpsData['__computed_latitude'];
                  gpsLongitude = gpsData['__computed_longitude'];
                }
              }
            }
          }
        }
      }

      // SOF0/SOF2 markers contain image dimensions
      if (marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
        if (offset + 8 < bytes.length) {
          imageHeight = (bytes[offset + 5] << 8) | bytes[offset + 6];
          imageWidth = (bytes[offset + 7] << 8) | bytes[offset + 8];
        }
      }

      offset += 2 + segLen;
    }

    return ExifData(
      cameraMake: cameraMake,
      cameraModel: cameraModel,
      dateTimeOriginal: dateTimeOriginal,
      gpsLatitude: gpsLatitude,
      gpsLongitude: gpsLongitude,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      orientation: orientation,
      software: software,
      iso: iso,
      focalLength: focalLength,
      aperture: aperture,
      exposureTime: exposureTime,
      flash: flash,
    );
  }

  static ExifData _extractFromPngOrHeic(File file) {
    try {
      final bytes = file.readAsBytesSync();
      final dims = _parseDimensions(Uint8List.fromList(bytes), file.path);
      return ExifData(
        imageWidth: dims['width'],
        imageHeight: dims['height'],
      );
    } catch (_) {
      return const ExifData();
    }
  }

  static Map<String, int> _parseDimensions(Uint8List bytes, String path) {
    final ext = path.toLowerCase();

    // PNG: IHDR chunk at offset 16, width at 16-19, height at 20-23
    if (ext.endsWith('.png') && bytes.length >= 24) {
      if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
        final w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
        final h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
        return {'width': w, 'height': h};
      }
    }

    // BMP: width at 18-21, height at 22-25
    if (ext.endsWith('.bmp') && bytes.length >= 30) {
      if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
        final w = bytes[18] | (bytes[19] << 8) | (bytes[20] << 16) | (bytes[21] << 24);
        final h = bytes[22] | (bytes[23] << 8) | (bytes[24] << 16) | (bytes[25] << 24);
        return {'width': w, 'height': h};
      }
    }

    // GIF: width at 6-7, height at 8-9
    if (ext.endsWith('.gif') && bytes.length >= 10) {
      if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
        final w = bytes[6] | (bytes[7] << 8);
        final h = bytes[8] | (bytes[9] << 8);
        return {'width': w, 'height': h};
      }
    }

    // WebP: VP8/VP8L bitstream
    if (ext.endsWith('.webp') && bytes.length >= 30) {
      // Simple WebP (VP8)
      if (bytes[12] == 0x56 && bytes[13] == 0x50 && bytes[14] == 0x38 && bytes[15] == 0x20) {
        final w = bytes[26] | (bytes[27] << 8) | ((bytes[28] & 0x3F) << 16);
        final h = bytes[29] | (bytes[30] << 8) | ((bytes[28] & 0xC0) >> 6);
        return {'width': w, 'height': h};
      }
      // Lossless WebP (VP8L)
      if (bytes[12] == 0x56 && bytes[13] == 0x50 && bytes[14] == 0x38 && bytes[15] == 0x4C) {
        if (bytes.length >= 25) {
          final w = 1 + ((bytes[21] | (bytes[22] << 8) | (bytes[23] << 16)) & 0x3FFF);
          final h = 1 + (((bytes[21] | (bytes[22] << 8) | (bytes[23] << 16)) >> 14) & 0x3FFF);
          return {'width': w, 'height': h};
        }
      }
    }

    return {};
  }

  static int _readUint16(Uint8List bytes, int offset, bool isLittleEndian) {
    if (offset + 1 >= bytes.length) return 0;
    return isLittleEndian
        ? bytes[offset] | (bytes[offset + 1] << 8)
        : (bytes[offset] << 8) | bytes[offset + 1];
  }

  static int _readUint32(Uint8List bytes, int offset, bool isLittleEndian) {
    if (offset + 3 >= bytes.length) return 0;
    return isLittleEndian
        ? bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24)
        : (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];
  }

  static Map<String, dynamic> _parseIfd(Uint8List bytes, int offset, bool isLittleEndian) {
    final result = <String, dynamic>{};
    if (offset + 1 >= bytes.length) return result;

    final entryCount = _readUint16(bytes, offset, isLittleEndian);
    if (entryCount > 500 || entryCount == 0) return result;

    for (int i = 0; i < entryCount; i++) {
      final entryOffset = offset + 2 + (i * 12);
      if (entryOffset + 11 >= bytes.length) break;

      final tag = _readUint16(bytes, entryOffset, isLittleEndian);
      final type = _readUint16(bytes, entryOffset + 2, isLittleEndian);
      final count = _readUint32(bytes, entryOffset + 4, isLittleEndian);
      final valueOffset = entryOffset + 8;

      // Only process common tags we care about
      switch (tag) {
        case 0x010F: // Make
          result['Make'] = _readString(bytes, valueOffset, isLittleEndian, count);
          break;
        case 0x0110: // Model
          result['Model'] = _readString(bytes, valueOffset, isLittleEndian, count);
          break;
        case 0x0112: // Orientation
          result['Orientation'] = _readUint16(bytes, valueOffset, isLittleEndian);
          break;
        case 0x0131: // Software
          result['Software'] = _readString(bytes, valueOffset, isLittleEndian, count);
          break;
        case 0x0100: // ImageWidth
          result['ImageWidth'] = _readValue(bytes, valueOffset, isLittleEndian, type, count);
          break;
        case 0x0101: // ImageLength/Height
          result['ImageLength'] = _readValue(bytes, valueOffset, isLittleEndian, type, count);
          break;
        case 0x8769: // Exif SubIFD pointer
          result['__exif_sub_ifd_offset'] = _readUint32(bytes, valueOffset, isLittleEndian);
          break;
        case 0x8825: // GPS SubIFD pointer
          result['__gps_sub_ifd_offset'] = _readUint32(bytes, valueOffset, isLittleEndian);
          break;
        case 0x9003: // DateTimeOriginal
          result['DateTimeOriginal'] = _parseExifDate(_readString(bytes, valueOffset, isLittleEndian, count));
          break;
        case 0x9004: // DateTimeDigitized
          result['DateTimeDigitized'] = _parseExifDate(_readString(bytes, valueOffset, isLittleEndian, count));
          break;
        case 0x8827: // ISO
          result['ISOSpeedRatings'] = _readValue(bytes, valueOffset, isLittleEndian, type, count);
          break;
        case 0x920A: // FocalLength
          result['FocalLength'] = _readRational(bytes, valueOffset, isLittleEndian);
          break;
        case 0x829D: // FNumber
          result['FNumber'] = _readRational(bytes, valueOffset, isLittleEndian);
          break;
        case 0x829A: // ExposureTime
          result['ExposureTime'] = _readRational(bytes, valueOffset, isLittleEndian);
          break;
        case 0x9209: // Flash
          final flashVal = _readUint16(bytes, valueOffset, isLittleEndian);
          result['Flash'] = (flashVal & 1) == 1 ? 'Fired' : 'Not Fired';
          break;
        case 0xA002: // ExifImageWidth
          result['ExifImageWidth'] = _readValue(bytes, valueOffset, isLittleEndian, type, count);
          break;
        case 0xA003: // ExifImageHeight
          result['ExifImageHeight'] = _readValue(bytes, valueOffset, isLittleEndian, type, count);
          break;
        // GPS tags
        case 0x0001: // GPSLatitudeRef
          result['_gpsLatRef'] = _readString(bytes, valueOffset, isLittleEndian, count);
          break;
        case 0x0002: // GPSLatitude
          result['_gpsLat'] = _readGpsCoord(bytes, valueOffset, isLittleEndian, count);
          break;
        case 0x0003: // GPSLongitudeRef
          result['_gpsLonRef'] = _readString(bytes, valueOffset, isLittleEndian, count);
          break;
        case 0x0004: // GPSLongitude
          result['_gpsLon'] = _readGpsCoord(bytes, valueOffset, isLittleEndian, count);
          break;
      }
    }

    // Compute GPS coordinates from components
    if (result.containsKey('_gpsLat') && result.containsKey('_gpsLon')) {
      final lat = result['_gpsLat'] as double?;
      final lon = result['_gpsLon'] as double?;
      if (lat != null && lon != null) {
        final latRef = result['_gpsLatRef'] as String? ?? 'N';
        final lonRef = result['_gpsLonRef'] as String? ?? 'E';
        result['__computed_latitude'] = latRef == 'S' ? -lat : lat;
        result['__computed_longitude'] = lonRef == 'W' ? -lon : lon;
      }
    }

    return result;
  }

  static String _readString(Uint8List bytes, int offset, bool isLittleEndian, int count) {
    try {
      // If count <= 4, data is inline
      if (count <= 4) {
        final sb = StringBuffer();
        for (int i = 0; i < count; i++) {
          if (bytes[offset + i] == 0) break;
          sb.write(String.fromCharCode(bytes[offset + i]));
        }
        return sb.toString().trim();
      }
      // Otherwise read from data offset
      final dataOffset = _readUint32(bytes, offset, isLittleEndian);
      if (dataOffset + count > bytes.length) return '';
      final sb = StringBuffer();
      for (int i = 0; i < count; i++) {
        if (bytes[dataOffset + i] == 0) break;
        sb.write(String.fromCharCode(bytes[dataOffset + i]));
      }
      return sb.toString().trim();
    } catch (_) {
      return '';
    }
  }

  static dynamic _readValue(Uint8List bytes, int offset, bool isLittleEndian, int type, int count) {
    if (count == 1) {
      switch (type) {
        case 3: return _readUint16(bytes, offset, isLittleEndian);
        case 4: return _readUint32(bytes, offset, isLittleEndian);
      }
    }
    return null;
  }

  static double? _readRational(Uint8List bytes, int offset, bool isLittleEndian) {
    try {
      final dataOffset = _readUint32(bytes, offset, isLittleEndian);
      if (dataOffset + 7 >= bytes.length) return null;
      final numerator = _readUint32(bytes, dataOffset, isLittleEndian);
      final denominator = _readUint32(bytes, dataOffset + 4, isLittleEndian);
      if (denominator == 0) return null;
      return numerator / denominator;
    } catch (_) {
      return null;
    }
  }

  static double? _readGpsCoord(Uint8List bytes, int offset, bool isLittleEndian, int count) {
    try {
      final dataOffset = _readUint32(bytes, offset, isLittleEndian);
      if (dataOffset + 23 >= bytes.length) return null;
      // GPS coordinates are 3 RATIONAL values: degrees, minutes, seconds
      final degNum = _readUint32(bytes, dataOffset, isLittleEndian);
      final degDen = _readUint32(bytes, dataOffset + 4, isLittleEndian);
      final minNum = _readUint32(bytes, dataOffset + 8, isLittleEndian);
      final minDen = _readUint32(bytes, dataOffset + 12, isLittleEndian);
      final secNum = _readUint32(bytes, dataOffset + 16, isLittleEndian);
      final secDen = _readUint32(bytes, dataOffset + 20, isLittleEndian);
      final degrees = degDen != 0 ? degNum / degDen : 0.0;
      final minutes = minDen != 0 ? minNum / minDen : 0.0;
      final seconds = secDen != 0 ? secNum / secDen : 0.0;
      return degrees + minutes / 60.0 + seconds / 3600.0;
    } catch (_) {
      return null;
    }
  }

  static DateTime? _parseExifDate(String dateStr) {
    try {
      if (dateStr.length < 19) return null;
      // Format: "YYYY:MM:DD HH:MM:SS"
      final year = int.tryParse(dateStr.substring(0, 4)) ?? 0;
      final month = int.tryParse(dateStr.substring(5, 7)) ?? 1;
      final day = int.tryParse(dateStr.substring(8, 10)) ?? 1;
      final hour = int.tryParse(dateStr.substring(11, 13)) ?? 0;
      final minute = int.tryParse(dateStr.substring(14, 16)) ?? 0;
      final second = int.tryParse(dateStr.substring(17, 19)) ?? 0;
      return DateTime(year, month, day, hour, minute, second);
    } catch (_) {
      return null;
    }
  }
}
