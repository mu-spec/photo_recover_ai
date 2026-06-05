import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/app_constants.dart';

class SmartPhotoEnhanceResult {
  final bool success;
  final String message;
  final String? outputPath;
  final int? originalWidth;
  final int? originalHeight;
  final int? enhancedWidth;
  final int? enhancedHeight;

  const SmartPhotoEnhanceResult({
    required this.success,
    required this.message,
    this.outputPath,
    this.originalWidth,
    this.originalHeight,
    this.enhancedWidth,
    this.enhancedHeight,
  });
}

/// Local photo enhancement for restored/accessed images.
///
/// This does not recover raw deleted storage blocks. It improves a photo copy
/// the app can access by tuning color, contrast, sharpness, and safe upscaling.
class SmartPhotoEnhancerService {
  static const _maxInputEdge = 2600;
  static const _maxUpscaledEdge = 3600;
  static const _enhancedFolderName = 'Enhanced';

  static const _supportedExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.bmp',
    '.gif',
    '.tga',
    '.tif',
    '.tiff',
  };

  bool canEnhance(String path) {
    return _supportedExtensions.contains(p.extension(path).toLowerCase());
  }

  Future<SmartPhotoEnhanceResult> enhancePhoto(
    String sourcePath, {
    bool upscale = true,
  }) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        return const SmartPhotoEnhanceResult(
          success: false,
          message: 'Photo file not found. It may have been deleted.',
        );
      }

      if (!canEnhance(sourcePath)) {
        return const SmartPhotoEnhanceResult(
          success: false,
          message: 'This photo format is not supported for enhancement yet.',
        );
      }

      final inputBytes = await sourceFile.readAsBytes();
      final decoded = img.decodeImage(inputBytes);
      if (decoded == null) {
        return const SmartPhotoEnhanceResult(
          success: false,
          message: 'Could not read this image. It may be damaged or unsupported.',
        );
      }

      final originalWidth = decoded.width;
      final originalHeight = decoded.height;
      var working = img.bakeOrientation(decoded);

      working = _downscaleIfNeeded(working);

      working = img.adjustColor(
        working,
        contrast: 1.10,
        saturation: 1.08,
        brightness: 1.03,
        gamma: 0.96,
      );

      working = img.convolution(
        working,
        filter: const [0, -1, 0, -1, 5, -1, 0, -1, 0],
        amount: 0.42,
      );

      if (upscale) {
        working = _upscaleSafely(working);
      }

      final outputPath = await _buildOutputPath(sourcePath);
      final encoded = img.encodeJpg(working, quality: 92);
      await File(outputPath).writeAsBytes(encoded, flush: true);

      return SmartPhotoEnhanceResult(
        success: true,
        message: 'Enhanced photo saved successfully.',
        outputPath: outputPath,
        originalWidth: originalWidth,
        originalHeight: originalHeight,
        enhancedWidth: working.width,
        enhancedHeight: working.height,
      );
    } catch (_) {
      return const SmartPhotoEnhanceResult(
        success: false,
        message: 'Enhancement failed. Try a smaller or different photo.',
      );
    }
  }

  img.Image _downscaleIfNeeded(img.Image image) {
    final longestEdge = math.max(image.width, image.height);
    if (longestEdge <= _maxInputEdge) return image;

    final scale = _maxInputEdge / longestEdge;
    return img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.cubic,
    );
  }

  img.Image _upscaleSafely(img.Image image) {
    final longestEdge = math.max(image.width, image.height);
    if (longestEdge >= _maxUpscaledEdge) return image;

    final scale = math.min(2.0, _maxUpscaledEdge / longestEdge);
    if (scale <= 1.05) return image;

    return img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.cubic,
    );
  }

  Future<String> _buildOutputPath(String sourcePath) async {
    final baseDir = await _createEnhancedDirectory();

    final baseName = p.basenameWithoutExtension(sourcePath);
    final cleanedName = baseName
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
    final safeName = cleanedName.isEmpty ? 'photo' : cleanedName;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return p.join(baseDir.path, '${safeName}_enhanced_$stamp.jpg');
  }

  Future<Directory> _createEnhancedDirectory() async {
    final publicDir = Directory(
      '/storage/emulated/0/${AppConstants.recoveryFolder}/$_enhancedFolderName',
    );

    try {
      return await publicDir.create(recursive: true);
    } catch (_) {
      final appDir = await getExternalStorageDirectory();
      if (appDir == null) rethrow;
      final fallbackDir = Directory(
        p.join(appDir.path, AppConstants.recoveryFolder, _enhancedFolderName),
      );
      return fallbackDir.create(recursive: true);
    }
  }
}
