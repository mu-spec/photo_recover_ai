import 'dart:math';
import 'package:flutter/material.dart';

class AppColors {
  static final List<Color> gradientPrimary = [
    const Color(0xFF6C63FF),
    const Color(0xFF8B83FF),
  ];

  static final List<Color> gradientAccent = [
    const Color(0xFF00D9A6),
    const Color(0xFF00B4D8),
  ];

  static final List<Color> gradientWarm = [
    const Color(0xFFFF6B6B),
    const Color(0xFFFF8E53),
  ];

  static final List<Color> gradientCool = [
    const Color(0xFF4ECDC4),
    const Color(0xFF44B0FF),
  ];

  static final List<Color> gradientPurple = [
    const Color(0xFFA855F7),
    const Color(0xFF6366F1),
  ];

  static Color randomGradientColor() {
    final colors = [
      gradientPrimary,
      gradientAccent,
      gradientWarm,
      gradientCool,
      gradientPurple,
    ];
    return colors[Random().nextInt(colors.length)][0];
  }
}

class AppConstants {
  static const String appName = 'Photo Recover';
  static const String appVersion = '1.0.0';
  static const String recoveryFolder = 'PhotoRecover';
  static const int maxFreeRecoveryPerScan = 10;
  static const int maxScanFilesFree = 100;
  static const String supportEmail = 'saaddkhan99@gmail.com';
  static const String privacyPolicyUrl = 'https://mu-spec.github.io/photo_recover_ai/privacy-policy.html';
  static const String termsOfServiceUrl = 'https://mu-spec.github.io/photo_recover_ai/terms-of-service.html';

  static const List<String> photoExtensions = [
    'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic', 'heif',
  ];

  static const List<String> videoExtensions = [
    'mp4', '3gp', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm',
  ];

  static const List<String> fileExtensions = [
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt', 'mp3', 'wav', 'aac',
  ];
}
