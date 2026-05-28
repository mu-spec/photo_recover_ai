import 'dart:async';
import 'dart:io';
import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/recoverable_file.dart';
import 'exif_extractor.dart';
import 'file_repair_service.dart';
import 'scan_cache_service.dart';
import 'database_helper.dart';

enum ScanMode { allPhotos, deletedPhotos, allVideos, deletedVideos, allFiles, deletedFiles }

class ScanProgress {
  final double progress;
  final String currentFolder;
  final int filesFound;
  final String status;
  final String phase;
  final int totalScanned;
  final int elapsedSeconds;
  final int folderCount;
  final int totalBytesScanned;
  final int signaturesMatched;
  final int storageLocations;

  ScanProgress({
    required this.progress,
    required this.currentFolder,
    required this.filesFound,
    required this.status,
    this.phase = 'scanning',
    this.totalScanned = 0,
    this.elapsedSeconds = 0,
    this.folderCount = 0,
    this.totalBytesScanned = 0,
    this.signaturesMatched = 0,
    this.storageLocations = 1,
  });
}

// ============================================================================
// MAGIC BYTE SIGNATURES - Professional file identification by binary headers
// ============================================================================

class FileSignature {
  final String type;
  final String fileType; // 'photo', 'video', 'file'
  final List<int> headerBytes;
  final int headerOffset;
  final List<String>? extensions;

  const FileSignature({
    required this.type,
    required this.fileType,
    required this.headerBytes,
    this.headerOffset = 0,
    this.extensions,
  });
}

class SignatureDetector {
  static const photoSignatures = [
    // JPEG / JFIF
    FileSignature(type: 'JPEG', fileType: 'photo', headerBytes: [0xFF, 0xD8, 0xFF], extensions: ['.jpg', '.jpeg']),
    // PNG
    FileSignature(type: 'PNG', fileType: 'photo', headerBytes: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], extensions: ['.png']),
    // GIF87a
    FileSignature(type: 'GIF', fileType: 'photo', headerBytes: [0x47, 0x49, 0x46, 0x38, 0x37, 0x61], extensions: ['.gif']),
    // GIF89a
    FileSignature(type: 'GIF', fileType: 'photo', headerBytes: [0x47, 0x49, 0x46, 0x38, 0x39, 0x61], extensions: ['.gif']),
    // BMP
    FileSignature(type: 'BMP', fileType: 'photo', headerBytes: [0x42, 0x4D], extensions: ['.bmp']),
    // WebP
    FileSignature(type: 'WebP', fileType: 'photo', headerBytes: [0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50], extensions: ['.webp']),
    // TIFF (little-endian)
    FileSignature(type: 'TIFF', fileType: 'photo', headerBytes: [0x49, 0x49, 0x2A, 0x00], extensions: ['.tiff', '.tif']),
    // TIFF (big-endian)
    FileSignature(type: 'TIFF', fileType: 'photo', headerBytes: [0x4D, 0x4D, 0x00, 0x2A], extensions: ['.tiff', '.tif']),
    // HEIC / HEIF (ftyp box)
    FileSignature(type: 'HEIC', fileType: 'photo', headerBytes: [0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63], extensions: ['.heic']),
    // HEIF
    FileSignature(type: 'HEIF', fileType: 'photo', headerBytes: [0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x6D, 0x69, 0x66, 0x31], extensions: ['.heif']),
    // AVIF
    FileSignature(type: 'AVIF', fileType: 'photo', headerBytes: [0x00, 0x00, 0x00, 0x00, 0x66, 0x74, 0x79, 0x70, 0x61, 0x76, 0x69, 0x66], extensions: ['.avif']),
    // JPEG XL
    FileSignature(type: 'JXL', fileType: 'photo', headerBytes: [0xFF, 0x0A], extensions: ['.jxl']),
    // Photoshop PSD
    FileSignature(type: 'PSD', fileType: 'photo', headerBytes: [0x38, 0x42, 0x50, 0x53], extensions: ['.psd']),
    // Canon CR2 (TIFF-based)
    FileSignature(type: 'CR2', fileType: 'photo', headerBytes: [0x49, 0x49, 0x2A, 0x00, 0x10, 0x00, 0x00, 0x00, 0x43, 0x52], extensions: ['.cr2']),
    // Adobe Illustrator AI
    FileSignature(type: 'AI', fileType: 'file', headerBytes: [0x25, 0x50, 0x44, 0x46], extensions: ['.ai']),
    // JPEG 2000
    FileSignature(type: 'JP2', fileType: 'photo', headerBytes: [0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50], extensions: ['.jp2', '.j2k']),
  ];

  static const videoSignatures = [
    // MP4 / M4V / MOV (ftyp box)
    FileSignature(type: 'MP4', fileType: 'video', headerBytes: [0x00, 0x00, 0x00, 0x00, 0x66, 0x74, 0x79, 0x70], extensions: ['.mp4', '.m4v', '.mov']),
    // 3GP
    FileSignature(type: '3GP', fileType: 'video', headerBytes: [0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x33, 0x67, 0x70], extensions: ['.3gp']),
    // MKV / WebM (EBML header)
    FileSignature(type: 'MKV', fileType: 'video', headerBytes: [0x1A, 0x45, 0xDF, 0xA3], extensions: ['.mkv', '.webm']),
    // AVI (RIFF + AVI )
    FileSignature(type: 'AVI', fileType: 'video', headerBytes: [0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x41, 0x56, 0x49, 0x20], extensions: ['.avi']),
    // FLV
    FileSignature(type: 'FLV', fileType: 'video', headerBytes: [0x46, 0x4C, 0x56], extensions: ['.flv']),
    // MPEG-TS
    FileSignature(type: 'TS', fileType: 'video', headerBytes: [0x47], extensions: ['.ts', '.mts', '.m2ts']),
    // OGV / OGG
    FileSignature(type: 'OGV', fileType: 'video', headerBytes: [0x4F, 0x67, 0x67, 0x53], extensions: ['.ogv', '.ogg']),
    // WMV / ASF
    FileSignature(type: 'WMV', fileType: 'video', headerBytes: [0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11], extensions: ['.wmv', '.asf']),
    // RMVB
    FileSignature(type: 'RMVB', fileType: 'video', headerBytes: [0x2E, 0x52, 0x4D, 0x46], extensions: ['.rmvb', '.rm']),
  ];

  static const audioSignatures = [
    // MP3 (ID3v2)
    FileSignature(type: 'MP3', fileType: 'file', headerBytes: [0x49, 0x44, 0x33], extensions: ['.mp3']),
    // MP3 (sync word: 0xFF 0xFB or 0xFF 0xF3)
    FileSignature(type: 'MP3', fileType: 'file', headerBytes: [0xFF, 0xFB], extensions: ['.mp3']),
    FileSignature(type: 'MP3', fileType: 'file', headerBytes: [0xFF, 0xF3], extensions: ['.mp3']),
    // WAV (RIFF + WAVE)
    FileSignature(type: 'WAV', fileType: 'file', headerBytes: [0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x41, 0x56, 0x45], extensions: ['.wav']),
    // FLAC (fLaC)
    FileSignature(type: 'FLAC', fileType: 'file', headerBytes: [0x66, 0x4C, 0x61, 0x43], extensions: ['.flac']),
    // OGG Vorbis
    FileSignature(type: 'OGG', fileType: 'file', headerBytes: [0x4F, 0x67, 0x67, 0x53], extensions: ['.ogg', '.opus']),
    // AAC (ADTS)
    FileSignature(type: 'AAC', fileType: 'file', headerBytes: [0xFF, 0xF1], extensions: ['.aac']),
    FileSignature(type: 'AAC', fileType: 'file', headerBytes: [0xFF, 0xF9], extensions: ['.aac']),
    // AMR
    FileSignature(type: 'AMR', fileType: 'file', headerBytes: [0x23, 0x21, 0x41, 0x4D, 0x52], extensions: ['.amr']),
    // MIDI
    FileSignature(type: 'MIDI', fileType: 'file', headerBytes: [0x4D, 0x54, 0x68, 0x64], extensions: ['.mid', '.midi']),
    // WMA
    FileSignature(type: 'WMA', fileType: 'file', headerBytes: [0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11], extensions: ['.wma']),
  ];

  static const documentSignatures = [
    // PDF
    FileSignature(type: 'PDF', fileType: 'file', headerBytes: [0x25, 0x50, 0x44, 0x46, 0x2D], extensions: ['.pdf']),
    // ZIP (also used for DOCX, XLSX, PPTX, APK, etc.)
    FileSignature(type: 'ZIP', fileType: 'file', headerBytes: [0x50, 0x4B, 0x03, 0x04], extensions: ['.zip', '.docx', '.xlsx', '.pptx', '.apk', '.ipa', '.epub', '.odt', '.ods', '.odp']),
    // RAR
    FileSignature(type: 'RAR', fileType: 'file', headerBytes: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00], extensions: ['.rar']),
    // RAR5
    FileSignature(type: 'RAR5', fileType: 'file', headerBytes: [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00], extensions: ['.rar']),
    // 7-Zip
    FileSignature(type: '7Z', fileType: 'file', headerBytes: [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C], extensions: ['.7z']),
    // GZIP
    FileSignature(type: 'GZIP', fileType: 'file', headerBytes: [0x1F, 0x8B], extensions: ['.gz', '.gzip']),
    // DOC (OLE2)
    FileSignature(type: 'DOC', fileType: 'file', headerBytes: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1], extensions: ['.doc', '.xls', '.ppt']),
    // RTF
    FileSignature(type: 'RTF', fileType: 'file', headerBytes: [0x7B, 0x5C, 0x72, 0x74, 0x66], extensions: ['.rtf']),
  ];

  static List<FileSignature> signaturesForType(String scanFileType) {
    switch (scanFileType) {
      case 'photo': return [...photoSignatures, ...videoSignatures]; // photos can find video thumbs
      case 'video': return [...videoSignatures, ...photoSignatures];
      case 'file': return [...documentSignatures, ...audioSignatures];
      default: return [...photoSignatures, ...videoSignatures, ...documentSignatures, ...audioSignatures];
    }
  }

  /// Read first N bytes from a file and identify it by magic bytes
  static FileSignature? identifyFile(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final raf = file.openSync(mode: FileMode.read);
      final bytes = Uint8List(32);
      final bytesRead = raf.readIntoSync(bytes);
      raf.closeSync();
      if (bytesRead < 4) return null;

      // Check all signatures
      for (final sig in [...photoSignatures, ...videoSignatures, ...audioSignatures, ...documentSignatures]) {
        if (bytesRead >= sig.headerOffset + sig.headerBytes.length) {
          bool match = true;
          for (int i = 0; i < sig.headerBytes.length; i++) {
            if (bytes[sig.headerOffset + i] != sig.headerBytes[i]) {
              match = false;
              break;
            }
          }
          if (match) return sig;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Quick check - just first 4 bytes for fast filtering
  static String? quickIdentify(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final raf = file.openSync(mode: FileMode.read);
      final bytes = Uint8List(12);
      final bytesRead = raf.readIntoSync(bytes);
      raf.closeSync();
      if (bytesRead < 3) return null;

      // JPEG
      if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return 'photo';
      // PNG
      if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return 'photo';
      // GIF
      if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return 'photo';
      // BMP
      if (bytes[0] == 0x42 && bytes[1] == 0x4D) return 'photo';
      // WebP
      if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46) return 'photo';
      // TIFF
      if ((bytes[0] == 0x49 && bytes[1] == 0x49 && bytes[2] == 0x2A && bytes[3] == 0x00) ||
          (bytes[0] == 0x4D && bytes[1] == 0x4D && bytes[2] == 0x00 && bytes[3] == 0x2A)) return 'photo';
      // HEIC/HEIF (ftyp heic/mif1)
      if (bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70) {
        if (bytes[8] == 0x68 && bytes[9] == 0x65 && bytes[10] == 0x69 && bytes[11] == 0x63) return 'photo';
        if (bytes[8] == 0x6D && bytes[9] == 0x69 && bytes[10] == 0x66 && bytes[11] == 0x31) return 'photo';
        // MP4
        return 'video';
      }
      // MP4 / MOV (ftyp is at offset 4)
      if (bytesRead >= 12 && bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70) return 'video';
      // MKV
      if (bytes[0] == 0x1A && bytes[1] == 0x45 && bytes[2] == 0xDF && bytes[3] == 0xA3) return 'video';
      // AVI
      if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46) {
        if (bytesRead >= 12 && bytes[8] == 0x41 && bytes[9] == 0x56 && bytes[10] == 0x49) return 'video';
        if (bytesRead >= 12 && bytes[8] == 0x57 && bytes[9] == 0x41 && bytes[10] == 0x56) return 'file'; // WAV
      }
      // FLV
      if (bytes[0] == 0x46 && bytes[1] == 0x4C && bytes[2] == 0x56) return 'video';
      // MPEG-TS
      if (bytes[0] == 0x47) return 'video';
      // PDF
      if (bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46) return 'file';
      // ZIP-based (docx, xlsx, apk, etc.)
      if (bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04) return 'file';
      // RAR
      if (bytes[0] == 0x52 && bytes[1] == 0x61 && bytes[2] == 0x72 && bytes[3] == 0x21) return 'file';
      // 7z
      if (bytes[0] == 0x37 && bytes[1] == 0x7A && bytes[2] == 0xBC && bytes[3] == 0xAF) return 'file';
      // DOC/XLS/PPT OLE2
      if (bytes[0] == 0xD0 && bytes[1] == 0xCF && bytes[2] == 0x11 && bytes[3] == 0xE0) return 'file';
      // MP3 ID3v2
      if (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) return 'file';
      // FLAC
      if (bytes[0] == 0x66 && bytes[1] == 0x4C && bytes[2] == 0x61 && bytes[3] == 0x43) return 'file';
      // OGG
      if (bytes[0] == 0x4F && bytes[1] == 0x67 && bytes[2] == 0x67 && bytes[3] == 0x53) return 'file';
      // RTF
      if (bytes[0] == 0x7B && bytes[1] == 0x5C && bytes[2] == 0x72 && bytes[3] == 0x74) return 'file';

      return null;
    } catch (_) {
      return null;
    }
  }
}

// ============================================================================
// MAIN SCANNER
// ============================================================================

class StorageScanner {
  // ===== EXPANDED EXTENSION LISTS =====
  static const photoExtensions = [
    '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.heic', '.heif',
    '.tiff', '.tif', '.svg', '.raw', '.cr2', '.nef', '.arw', '.srw',
    '.dng', '.orf', '.rw2', '.ico', '.avif', '.jxl', '.jp2', '.j2k',
    '.3fr', '.k25', '.sr2', '.erf', '.mef', '.mos', '.pef', '.raf',
    '.psd', '.ai', '.eps',
  ];

  static const videoExtensions = [
    '.mp4', '.3gp', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm',
    '.m4v', '.ts', '.mts', '.m2ts', '.ogv', '.rmvb', '.rm', '.asf',
    '.f4v', '.divx', '.vp9', '.h264', '.h265', '.mpg', '.mpeg',
  ];

  static const audioExtensions = [
    '.mp3', '.wav', '.aac', '.flac', '.ogg', '.wma', '.m4a', '.amr',
    '.opus', '.mid', '.midi', '.aiff', '.alac', '.wv', '.ape',
    '.ac3', '.dts', '.mka', '.tak', '.tta',
  ];

  static const documentExtensions = [
    '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.txt',
    '.rtf', '.csv', '.zip', '.rar', '.7z', '.tar', '.gz', '.epub',
    '.odt', '.ods', '.odp', '.wps', '.pages', '.numbers', '.key',
    '.xps', '.mht', '.htm', '.html',
    '.vcf', '.vcard',  // Contact backup files
  ];

  // Temp / backup / partial file extensions (used in deep trace scanning)
  static const tempRecoveryExtensions = [
    '.tmp', '.bak', '.part', '.crdownload', '.download', '.pending',
    '.temp', '.cache', '.sav', '.old', '.orig', '.backup',
    '.partial', '.incomplete', '.dl',
  ];

  // VCF contact backup extensions
  static const contactExtensions = ['.vcf', '.vcard'];

  // WhatsApp Status media paths (auto-deleted after 24h)
  static const whatsappStatusPaths = [
    'Android/media/com.whatsapp/WhatsApp/Media/.Statuses',
    'WhatsApp/Media/.Statuses',
    'Android/media/com.whatsapp.w4b/WhatsApp/Media/.Statuses',
  ];

  // ===== PRIORITY FOLDERS =====
  static const normalScanFolders = [
    'DCIM', 'Camera', 'Pictures', 'Picture', 'Download', 'Downloads',
    'WhatsApp', 'Telegram', 'Instagram', 'TikTok', 'Snapchat',
    'Signal', 'Viber', 'Messenger', 'Movies', 'Movie', 'Music',
    'Recordings', 'ScreenRecord', 'ScreenRecording', 'Bluetooth',
    'Shared', 'Screenshots', 'Screenshot', 'Photos', 'Photo',
    'Gallery', 'Images', 'Video', 'Videos', 'Documents', 'Audio',
    'Alarms', 'Notifications', 'Ringtones',
    'KakaoTalk', 'LINE', 'WeChat',
  ];

  // ===== CORE APP MEDIA CACHE PATHS =====
  static const appMediaCorePaths = [
    // Messaging apps
    'Android/data/com.whatsapp',
    'Android/data/com.whatsapp.w4b',
    'Android/media/com.whatsapp',
    'Android/data/org.telegram.messenger',
    'Android/data/com.instagram.android',
    'Android/media/com.instagram.android',
    'Android/data/com.snapchat.android',
    'Android/data/com.facebook.katana',
    'Android/data/com.facebook.orca',
    'Android/data/com.zhiliaoapp.musically',
    'Android/data/com.ss.android.ugc.aweme',
    'Android/data/com.tencent.mm',           // WeChat
    'Android/data/com.viber.voip',
    'Android/data/jp.naver.line.android',    // LINE
    'Android/data/com.discord',
    'Android/data/com.kakao.talk',           // KakaoTalk
    'Android/data/com.linkedin.android',
    'Android/data/com.twitter.android',
    'Android/data/com.pinterest',
    'Android/data/com.signalvpn',            // Signal variant
    'Android/data/org.thoughtcrime.securesms', // Signal proper
    'Android/data/com.samsung.android.messaging',
    'Android/data/com.google.android.apps.messaging',
    'Android/data/com.android.mms',
    'Android/data/com.alibaba.android.rimet', // DingTalk
    // Photo/Video editing
    'Android/data/com.miui.gallery',
    'Android/data/com.huawei.himovie',
    'Android/data/com.utorrent.client',
    'Android/data/com.viva.video',
    'Android/data/com.nexstreaming.app.jellyvideomaker', // CapCut
    'Android/data/com.ss.android.ugc.aweme', // TikTok/CapCut
    'Android/data/com.zideate',              // InShot
    'Android/data/com.cheetah.mobile.videomate',
    'Android/data/com.kmplayer',             // KMPlayer
    'Android/data/com.mxtech.videoplayer.ad', // MX Player
    'Android/data/com.mxtech.videoplayer.pro', // MX Player Pro
    'Android/data/org.videolan.vlc',
    'Android/data/com.google.android.apps.youtube',
    'Android/data/com.spotify.music',
    'Android/data/com.amazon.mShop.android.shopping',
    'Android/data/com.google.android.apps.photos',
    'Android/data/com.google.android.gms',
    'Android/data/com.samsung.android.vocorder',
    // Cloud / File managers
    'Android/data/com.microsoft.skydrive',   // OneDrive
    'Android/data/com.dropbox.android',
    'Android/data/com.google.android.apps.docs', // Google Drive
    'Android/data/com.alibaba.android.rimet',
    'Android/data/com.estrongs.android.pop', // ES File Explorer
    'Android/data/com.google.android.apps.nbu.files', // Files by Google
    // Browsers (cache downloaded images/videos)
    'Android/data/com.android.chrome',
    'Android/data/com.chrome.beta',
    'Android/data/org.mozilla.firefox',
    'Android/data/com.opera.browser',
    'Android/data/com.opera.mini.native',
    'Android/data/com.UCMobile.intl',        // UC Browser
    'Android/data/com.sec.android.app.sbrowser', // Samsung Internet
    'Android/data/com.brave.browser',
    'Android/data/com.microsoft.emmx',       // Edge
    'Android/data/com.google.androidbrowser', // Android Browser
    'Android/data/org.chromium.chrome',
    // Social media
    'Android/data/com.reddit.frontpage',
    'Android/data/com.whatsapp.w4b',
    'Android/data/com.like.android',
    'Android/data/com.zalo.zalo3',
    'Android/media',                         // Scoped storage media
    'Android/data/com.tencent.mobileqq',     // QQ
    'Android/data/com.sina.weibo',           // Weibo
    'Android/data/com.camscanner.app',       // CamScanner
    'Android/data/com.xender',               // Xender
    'Android/data/com.shareit',              // ShareIt
    'Android/data/com.google.android.videos', // Google TV
    'Android/data/com.amazon.avod.thirdpartyclient', // Amazon Prime Video
    'Android/data/com.netflix.mediaclient',   // Netflix
    'Android/data/com.disney.disneyplus',    // Disney+
  ];

  // Additional package universe to generate 500+ realistic scan paths.
  static const _highPriorityPackageIds = [
    'com.whatsapp', 'com.whatsapp.w4b', 'org.telegram.messenger', 'com.instagram.android',
    'com.zhiliaoapp.musically', 'com.ss.android.ugc.aweme', 'com.facebook.katana',
    'com.facebook.orca', 'com.snapchat.android', 'com.tencent.mm', 'jp.naver.line.android',
    'org.thoughtcrime.securesms', 'com.viber.voip', 'com.discord', 'com.reddit.frontpage',
    'com.twitter.android', 'com.pinterest', 'com.linkedin.android', 'com.kakao.talk',
    'com.sina.weibo', 'com.tencent.mobileqq', 'com.zalo.zalo3', 'com.google.android.apps.photos',
    'com.google.android.apps.docs', 'com.dropbox.android', 'com.microsoft.skydrive',
    'com.google.android.apps.nbu.files', 'com.estrongs.android.pop', 'com.xender', 'com.shareit',
    'org.videolan.vlc', 'com.mxtech.videoplayer.ad', 'com.mxtech.videoplayer.pro', 'com.kmplayer',
    'com.google.android.youtube', 'com.google.android.apps.youtube.music', 'com.spotify.music',
    'com.netflix.mediaclient', 'com.disney.disneyplus', 'com.amazon.avod.thirdpartyclient',
    'com.android.chrome', 'org.mozilla.firefox', 'com.opera.browser', 'com.opera.mini.native',
    'com.sec.android.app.sbrowser', 'com.brave.browser', 'com.microsoft.emmx',
    'com.UCMobile.intl', 'org.chromium.chrome', 'com.google.android.gm',
    'com.android.vending', 'com.google.android.apps.maps', 'com.google.android.keep',
    'com.adobe.lrmobile', 'com.canva.editor', 'com.burbn.instagram', 'com.google.android.apps.tachyon',
    'com.skype.raider', 'com.zoom.us', 'com.microsoft.teams', 'com.slack',
    'com.google.android.calendar', 'com.google.android.contacts', 'com.google.android.music',
    'com.google.android.videos', 'com.samsung.android.messaging', 'com.google.android.apps.messaging',
    'com.android.mms', 'com.google.android.apps.translate', 'com.google.android.apps.docs.editors.docs',
    'com.google.android.apps.docs.editors.sheets', 'com.google.android.apps.docs.editors.slides',
    'com.miui.gallery', 'com.huawei.himovie', 'com.viva.video', 'com.nexstreaming.app.jellyvideomaker',
    'com.zideate', 'com.camscanner.app', 'com.amazon.mShop.android.shopping',
    'com.paypal.android.p2pmobile', 'com.binance.dev', 'com.bybit.app', 'com.coinbase.android',
    'com.roblox.client', 'com.supercell.clashofclans', 'com.supercell.clashroyale',
    'com.dts.freefireth', 'com.ea.gp.fifamobile', 'com.mobile.legends', 'com.activision.callofduty.shooter',
    'com.epicgames.fortnite', 'com.nianticlabs.pokemongo', 'com.king.candycrushsaga',
    'com.ubercab', 'com.ubercab.eats', 'com.olacabs.customer', 'com.booking', 'com.airbnb.android',
    'com.tripadvisor.tripadvisor', 'com.agoda.mobile.consumer', 'com.tinder', 'com.bumble.app',
    'com.quora.android', 'com.medium.reader', 'com.flipboard.app', 'com.naver.linewebtoon',
    'com.nono.android', 'com.picsart.studio', 'com.prisma.photoeditor', 'com.snowcorp.stickerly.android',
    'com.capcut.videoeditor', 'video.editor.videomaker.effects.fx', 'com.cyberlink.powerdirector.DRA140225_01',
    'com.adobe.psmobile', 'com.google.android.apps.walletnfcrel',
  ];

  static const _generatedPathSuffixes = [
    '',
    '/cache',
    '/cache/image_manager_disk_cache',
    '/cache/video',
    '/files',
    '/files/Pictures',
    '/files/Movies',
  ];

  static final List<String> appMediaCachePaths = _buildExpandedAppMediaCachePaths();

  // ===== THUMBNAIL / HIDDEN / TRASH PATHS =====
  static const thumbnailPaths = [
    'DCIM/.thumbnails',
    'Pictures/.thumbnails',
    '.thumbnails',
    '.THMBDATA',
    '.face',
    'DCIM/.THMBDATA',
  ];

  static const deletedTracePaths = [
    '.Trash',
    '.trashed',
    'Trash',
    'Recently Deleted',
  ];

  // ===== SKIP LIST (system/process folders) =====
  static const skipFolderNames = {
    'node_modules', '.gradle', 'gradle', 'build', 'obsidian', 'PhotoRecover', 'MediaRescue',
    'MIUI', 'MiUI', 'HwBackup', 'huawei', '__MACOSX',
    'dexopt', 'dalvik-cache', 'app-lib', 'app-libs',
    'app-webview', 'app_chrome', 'cache',
    'Code Cache', 'GPUCache', 'blob_storage', 'Service Worker',
    'Local Storage', 'Session Storage', 'IndexedDB',
    'databases', 'shared_prefs',
  };

  static const skipFolderPrefixes = [
    'com.android.', 'com.google.android.gms', 'com.google.android.gsf',
    'com.google.android.providers', 'com.qualcomm', 'com.samsung.android.app',
    'com.samsung.android.providers', 'com.samsung.android.soagent',
    'com.samsung.android.biometrics', 'com.samsung.android.servermode',
    'com.qti.', 'com.mediatek.', 'com.sec.android',
    'com.sonymobile.', 'com.htc.', 'com.lge.',
    'com.android.providers.', 'com.android.internal',
  ];

  // ===== CONSTANTS =====
  static const int minFileSize = 512;        // Lowered from 1024 to catch tiny files
  static const int thumbnailMaxSize = 60000;
  static const int maxDepthNormal = 6;       // Increased from 5
  static const int maxDepthDeep = 12;        // Increased from 10
  static const int fileStatDelay = 3;        // ms
  static const int folderTransitionDelay = 120; // ms
  static const int batchSize = 30;           // files per batch before yield

  static List<String> _buildExpandedAppMediaCachePaths() {
    final paths = <String>{...appMediaCorePaths};

    for (final pkg in _highPriorityPackageIds) {
      for (final suffix in _generatedPathSuffixes) {
        paths.add('Android/data/$pkg$suffix');
      }

      // Scoped storage media variants.
      paths.add('Android/media/$pkg');
      paths.add('Android/media/$pkg/files');
      paths.add('Android/media/$pkg/Media');
      paths.add('Android/media/$pkg/Media/.Statuses');
    }

    // Generic hot spots frequently containing residual media/caches.
    paths.addAll(const [
      'Android/data',
      'Android/media',
      'Android/obb',
      'DCIM/.thumbnails',
      'Pictures/.thumbnails',
      'Download',
      'Downloads',
      'WhatsApp/Media',
      'Telegram',
    ]);

    return paths.toList(growable: false);
  }

  // ===== STATE =====
  bool _isCancelled = false;
  bool _isPaused = false;
  List<RecoverableFile> _lastScanResults = [];
  int _signaturesMatched = 0;
  int _storageLocationsScanned = 0;

  List<RecoverableFile> get lastScanResults => _lastScanResults;
  bool get isPaused => _isPaused;

  void cancelScan() => _isCancelled = true;
  void resetCancel() => _isCancelled = false;
  void pauseScan() => _isPaused = true;
  void resumeScan() => _isPaused = false;
  void resetState() { _isCancelled = false; _isPaused = false; _signaturesMatched = 0; _storageLocationsScanned = 0; }

  Future<bool> _waitIfPaused() async {
    while (_isPaused) {
      if (_isCancelled) return true;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return _isCancelled;
  }

  // ===== PERMISSIONS =====
  Future<bool> requestPermissions() async {
    return requestPermissionsForType('photo');
  }

  Future<bool> requestPermissionsForType(String fileType) async {
    switch (fileType) {
      case 'photo':
        if (await _checkAndRequestPermission(Permission.photos)) return true;
        return await _checkAndRequestPermission(Permission.storage);
      case 'video':
        if (await _checkAndRequestPermission(Permission.videos)) return true;
        return await _checkAndRequestPermission(Permission.storage);
      case 'file':
      default:
        if (await _checkAndRequestPermission(Permission.photos)) return true;
        if (await _checkAndRequestPermission(Permission.videos)) return true;
        if (await _checkAndRequestPermission(Permission.audio)) return true;
        if (await _checkAndRequestPermission(Permission.storage)) return true;
        return false;
    }
  }

  Future<bool> _checkAndRequestPermission(Permission permission) async {
    final status = await permission.status;
    if (status.isGranted) return true;
    if (status.isDenied) return (await permission.request()).isGranted;
    if (status.isPermanentlyDenied) { await openAppSettings(); return false; }
    return false;
  }

  // ====================================================================
  // STORAGE LOCATION DISCOVERY (Internal + SD Card + USB)
  // ====================================================================

  Future<List<String>> _discoverStorageLocations() async {
    final locations = ['/storage/emulated/0'];

    // Check for secondary storage / SD card / USB OTG
    final storageDir = Directory('/storage');
    try {
      await for (final entity in storageDir.list()) {
        if (_isCancelled) break;
        if (entity is Directory) {
          final name = entity.path.split('/').last;
          // Skip emulated (already added) and self
          if (name == 'emulated' || name == 'self') continue;
          // Skip system mounts
          if (name == 'enc_emulated' || name == 'dfc') continue;
          // Check if it's a real mount point (has content)
          try {
            final sub = await entity.list().toList();
            if (sub.isNotEmpty) {
              locations.add(entity.path);
              // Also check for 0 subfolder (e.g., /storage/ABCD-1234/0)
              for (final s in sub) {
                if (s is Directory) {
                  final subName = s.path.split('/').last;
                  if (subName == '0' || subName == '1') {
                    locations.add(s.path);
                  }
                }
              }
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    return locations;
  }

  // ====================================================================
  // PUBLIC API
  // ====================================================================

  /// Scan ALL photos — runs full 12-phase deep scan, returns EVERYTHING found (existing + deleted + hidden)
  Stream<ScanProgress> scanAllPhotos() async* {
    yield* _scanFiles('photo', photoExtensions, isDeepScan: true, deletedOnly: false);
  }

  /// Scan DELETED photos — runs full 12-phase deep scan, then FILTERS OUT existing/normal files
  /// Only shows recycle-bin, restored-copy, hidden, cached, and signature-matched files.
  Stream<ScanProgress> scanDeletedPhotos() async* {
    yield* _scanFiles('photo', photoExtensions, isDeepScan: true, deletedOnly: true);
  }

  /// Scan ALL videos — runs full 12-phase deep scan, returns EVERYTHING found
  Stream<ScanProgress> scanAllVideos() async* {
    yield* _scanFiles('video', videoExtensions, isDeepScan: true, deletedOnly: false);
  }

  /// Scan DELETED videos — runs full deep scan, then filters out existing files
  Stream<ScanProgress> scanDeletedVideos() async* {
    yield* _scanFiles('video', videoExtensions, isDeepScan: true, deletedOnly: true);
  }

  /// Scan ALL files — runs full 12-phase deep scan, returns EVERYTHING found
  Stream<ScanProgress> scanAllFiles() async* {
    yield* _scanFiles('file', [...documentExtensions, ...audioExtensions], isDeepScan: true, deletedOnly: false);
  }

  /// Scan DELETED files — runs full deep scan, then filters out existing files
  Stream<ScanProgress> scanDeletedFiles() async* {
    yield* _scanFiles('file', [...documentExtensions, ...audioExtensions], isDeepScan: true, deletedOnly: true);
  }

  /// Backward compatibility
  Stream<ScanProgress> scanForPhotos({ScanMode mode = ScanMode.allPhotos}) async* {
    yield* _scanFiles('photo', photoExtensions,
      isDeepScan: true,
      deletedOnly: mode == ScanMode.deletedPhotos,
    );
  }
  Stream<ScanProgress> scanForVideos({ScanMode mode = ScanMode.allVideos}) async* {
    yield* _scanFiles('video', videoExtensions,
      isDeepScan: true,
      deletedOnly: mode == ScanMode.deletedVideos,
    );
  }
  Stream<ScanProgress> scanForFiles({ScanMode mode = ScanMode.allFiles}) async* {
    yield* _scanFiles('file', [...documentExtensions, ...audioExtensions],
      isDeepScan: true,
      deletedOnly: mode == ScanMode.deletedFiles,
    );
  }

  // ====================================================================
  // CORE SCANNING ENGINE - 12 PHASES (Deep) / 6 PHASES (Normal)
  // ====================================================================

  Stream<ScanProgress> _scanFiles(
    String fileType, List<String> extensions, {
    required bool isDeepScan,
    bool deletedOnly = false,
  }
  ) async* {
    resetState();
    _lastScanResults = [];
    final stopwatch = Stopwatch()..start();
    final allFiles = <RecoverableFile>[];
    final scannedPaths = HashSet<String>();
    final typeLabel = fileType == 'photo' ? 'Photos' : fileType == 'video' ? 'Videos' : 'Files';
    int totalDirsScanned = 0;
    int totalBytes = 0;

    // ================================================================
    // PHASE 1: STORAGE DISCOVERY
    // ================================================================
    yield ScanProgress(
      progress: 0.0, currentFolder: 'Initializing...', filesFound: 0,
      status: 'Discovering storage locations...', phase: 'discovery',
      elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
    );
    await Future.delayed(const Duration(milliseconds: 600));
    if (_isCancelled) { yield _buildFinal(allFiles, stopwatch, totalBytes); return; }

    // Discover all storage locations (internal + SD + USB)
    final storageLocations = await _discoverStorageLocations();
    _storageLocationsScanned = storageLocations.length;

    yield ScanProgress(
      progress: 0.02, currentFolder: 'Found ${storageLocations.length} storage(s)',
      filesFound: 0, status: 'Found ${storageLocations.length} storage location(s) to scan',
      phase: 'discovery', storageLocations: storageLocations.length,
      elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
    );
    await Future.delayed(const Duration(milliseconds: 300));

    // Scan EACH storage location
    for (int locIndex = 0; locIndex < storageLocations.length; locIndex++) {
      if (_isCancelled) break;

      final baseStoragePath = storageLocations[locIndex];
      final baseDir = Directory(baseStoragePath);
      if (!await baseDir.exists()) continue;
      _storageLocationsScanned = locIndex + 1;

      final locLabel = locIndex == 0 ? 'Internal Storage' : 'Storage ${locIndex + 1}';

      // ================================================================
      // PHASE 2: DIRECTORY DISCOVERY
      // ================================================================
      yield ScanProgress(
        progress: 0.03 + locIndex * 0.01, currentFolder: locLabel,
        filesFound: allFiles.length,
        status: 'Scanning $locLabel - Discovering directories...',
        phase: 'discovery', storageLocations: locIndex + 1,
        elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
      );
      await Future.delayed(const Duration(milliseconds: 400));

      final allTopLevelDirs = <Directory>[];
      try {
        await for (final entity in baseDir.list(followLinks: false)) {
          if (_isCancelled) break;
          if (entity is Directory) allTopLevelDirs.add(entity);
        }
      } catch (e) { debugPrint('Discovery error: $e'); }

      if (_isCancelled) { yield _buildFinal(allFiles, stopwatch, totalBytes); return; }

      // Sort: priority folders first
      allTopLevelDirs.sort((a, b) {
        final aName = a.path.split('/').last.toLowerCase();
        final bName = b.path.split('/').last.toLowerCase();
        final aP = normalScanFolders.indexWhere((p) => p.toLowerCase() == aName);
        final bP = normalScanFolders.indexWhere((p) => p.toLowerCase() == bName);
        if (aP == -1 && bP == -1) return aName.compareTo(bName);
        if (aP == -1) return 1;
        if (bP == -1) return -1;
        return aP.compareTo(bP);
      });

      yield ScanProgress(
        progress: 0.05 + locIndex * 0.01,
        currentFolder: '$locLabel (${allTopLevelDirs.length} dirs)',
        filesFound: allFiles.length,
        status: 'Found ${allTopLevelDirs.length} directories in $locLabel',
        phase: 'discovery', folderCount: allTopLevelDirs.length,
        storageLocations: locIndex + 1,
        elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
      );
      await Future.delayed(const Duration(milliseconds: 200));

      // ================================================================
      // PHASE 3: MAIN FOLDER SCAN
      // ================================================================
      yield ScanProgress(
        progress: 0.06 + locIndex * 0.01,
        currentFolder: 'Priority Folders', filesFound: allFiles.length,
        status: isDeepScan ? 'Deep scanning priority media folders...' : 'Scanning media folders...',
        phase: isDeepScan ? 'deep_scan' : 'scanning',
        folderCount: allTopLevelDirs.length,
        storageLocations: locIndex + 1,
        elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
      );

      int phase3Dirs = 0;
      for (final dir in allTopLevelDirs) {
        if (_isCancelled) break;
        if (await _waitIfPaused()) break;

        final dirName = dir.path.split('/').last;
        final isPriority = normalScanFolders.any((p) => p.toLowerCase() == dirName.toLowerCase());

        // In normal mode, ONLY scan priority folders
        if (!isDeepScan && !isPriority) continue;

        final displayName = _getFolderDisplayName(dir.path);
        final maxDepth = isDeepScan ? maxDepthDeep : (isPriority ? maxDepthNormal : maxDepthNormal - 2);

        yield ScanProgress(
          progress: 0.06 + (phase3Dirs / (allTopLevelDirs.length + 3)) * 0.28,
          currentFolder: displayName, filesFound: allFiles.length,
          status: 'Scanning $displayName...', phase: isPriority ? 'scanning' : 'deep_scan',
          totalScanned: scannedPaths.length, folderCount: phase3Dirs,
          totalBytesScanned: totalBytes, storageLocations: locIndex + 1,
          signaturesMatched: _signaturesMatched,
          elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
        );

        final bytesBefore = allFiles.fold<int>(0, (sum, f) => sum + f.size);
        await _scanDirectoryRecursive(
          dir.path, extensions, fileType, scannedPaths, allFiles,
          currentDepth: 0, maxDepth: maxDepth,
          isDeepScan: isDeepScan,
        );
        totalBytes += allFiles.fold<int>(0, (sum, f) => sum + f.size) - bytesBefore;

        phase3Dirs++;

        if (isPriority || allFiles.length > 0) {
          yield ScanProgress(
            progress: 0.06 + (phase3Dirs / (allTopLevelDirs.length + 3)) * 0.28,
            currentFolder: displayName, filesFound: allFiles.length,
            status: 'Found ${allFiles.length} $typeLabel so far...',
            phase: 'scanning', totalScanned: scannedPaths.length,
            folderCount: phase3Dirs, totalBytesScanned: totalBytes,
            storageLocations: locIndex + 1, signaturesMatched: _signaturesMatched,
            elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
          );
        }

        await Future.delayed(const Duration(milliseconds: folderTransitionDelay));
      }

      if (_isCancelled) { yield _buildFinal(allFiles, stopwatch, totalBytes); return; }

      // ================================================================
      // PHASE 4: APP MEDIA CACHE SCAN
      // ================================================================
      yield ScanProgress(
        progress: 0.36, currentFolder: 'App Caches', filesFound: allFiles.length,
        status: isDeepScan
            ? 'Deep scanning ${appMediaCachePaths.length}+ app/media cache paths...'
            : 'Scanning app caches...',
        phase: 'cache_scan', totalScanned: scannedPaths.length,
        folderCount: totalDirsScanned, totalBytesScanned: totalBytes,
        storageLocations: locIndex + 1, signaturesMatched: _signaturesMatched,
        elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
      );
      await Future.delayed(const Duration(milliseconds: 350));

      int cachePhaseIndex = 0;
      for (final cachePath in appMediaCachePaths) {
        if (_isCancelled) break;
        if (await _waitIfPaused()) break;

        final fullPath = '$baseStoragePath/$cachePath';
        final dir = Directory(fullPath);
        if (!await dir.exists()) continue;

        cachePhaseIndex++;
        final displayName = _getFolderDisplayName(fullPath);

        if (cachePhaseIndex % 3 == 0) {
          yield ScanProgress(
            progress: 0.36 + (cachePhaseIndex / (appMediaCachePaths.length + 10)) * 0.14,
            currentFolder: displayName, filesFound: allFiles.length,
            status: 'Scanning $displayName...', phase: 'cache_scan',
            totalScanned: scannedPaths.length, totalBytesScanned: totalBytes,
            storageLocations: locIndex + 1, signaturesMatched: _signaturesMatched,
            elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
          );
        }

        final bytesBefore = allFiles.fold<int>(0, (sum, f) => sum + f.size);
        await _scanDirectoryRecursive(
          fullPath, extensions, fileType, scannedPaths, allFiles,
          currentDepth: 0, maxDepth: isDeepScan ? 8 : 4,
          isDeepScan: isDeepScan,
        );
        totalBytes += allFiles.fold<int>(0, (sum, f) => sum + f.size) - bytesBefore;
      }

      if (_isCancelled) { yield _buildFinal(allFiles, stopwatch, totalBytes); return; }

      // ================================================================
      // PHASE 5: THUMBNAIL SCAN
      // ================================================================
      yield ScanProgress(
        progress: 0.52, currentFolder: 'Thumbnails', filesFound: allFiles.length,
        status: isDeepScan ? 'Scanning thumbnail & hidden files...' : 'Scanning thumbnails...',
        phase: 'hidden_scan', totalScanned: scannedPaths.length,
        folderCount: totalDirsScanned, totalBytesScanned: totalBytes,
        storageLocations: locIndex + 1, signaturesMatched: _signaturesMatched,
        elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
      );
      await Future.delayed(const Duration(milliseconds: 350));

      for (final thumbPath in thumbnailPaths) {
        if (_isCancelled) break;
        if (await _waitIfPaused()) break;

        final fullPath = '$baseStoragePath/$thumbPath';
        final dir = Directory(fullPath);
        if (!await dir.exists()) continue;

        final bytesBefore = allFiles.fold<int>(0, (sum, f) => sum + f.size);
        await _scanDirectoryRecursive(
          fullPath, extensions, fileType, scannedPaths, allFiles,
          currentDepth: 0, maxDepth: 3, isDeepScan: true, forceQualityTag: 'thumbnail',
        );
        totalBytes += allFiles.fold<int>(0, (sum, f) => sum + f.size) - bytesBefore;
      }

      // Dynamic thumbnail detection
      try {
        await for (final entity in baseDir.list(recursive: false)) {
          if (_isCancelled) break;
          if (entity is Directory) {
            final name = entity.path.split('/').last.toLowerCase();
            if (name.contains('thumbnail') || name.contains('.thumb') || name.contains('thumbdata')) {
              if (!thumbnailPaths.any((p) => entity.path.endsWith('/$p'))) {
                await _scanDirectoryRecursive(
                  entity.path, extensions, fileType, scannedPaths, allFiles,
                  currentDepth: 0, maxDepth: 3, isDeepScan: true, forceQualityTag: 'thumbnail',
                );
              }
            }
          }
        }
      } catch (_) {}

      if (_isCancelled) { yield _buildFinal(allFiles, stopwatch, totalBytes); return; }

      // ================================================================
      // PHASE 6: MAGIC BYTES SCAN (only for accessible "all" scan mode)
      // ================================================================
      if (!deletedOnly) {
        yield ScanProgress(
          progress: 0.58, currentFolder: 'Signature Scan', filesFound: allFiles.length,
          status: 'Scanning files by binary signatures (magic bytes)...',
          phase: 'carving', totalScanned: scannedPaths.length,
          folderCount: totalDirsScanned, totalBytesScanned: totalBytes,
          storageLocations: locIndex + 1, signaturesMatched: _signaturesMatched,
          elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
        );
        await Future.delayed(const Duration(milliseconds: 300));

        final sigResults = await _scanBySignatures(
          baseStoragePath, extensions, fileType, scannedPaths, isDeepScan,
        );
        allFiles.addAll(sigResults);
        totalBytes += sigResults.fold<int>(0, (sum, f) => sum + f.size);

        yield ScanProgress(
          progress: 0.63, currentFolder: 'Signature Scan', filesFound: allFiles.length,
          status: 'Magic bytes matched ${_signaturesMatched} additional files',
          phase: 'carving', totalScanned: scannedPaths.length,
          folderCount: totalDirsScanned, totalBytesScanned: totalBytes,
          storageLocations: locIndex + 1, signaturesMatched: _signaturesMatched,
          elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
        );
      }

      // ================================================================
      // DEEP SCAN ONLY PHASES (7-11)
      // ================================================================
      if (isDeepScan) {
        // ============================================================
        // PHASE 7: TRASH & RECENTLY DELETED
        // ============================================================
        yield ScanProgress(
          progress: 0.65, currentFolder: 'Trash & Deleted', filesFound: allFiles.length,
          status: 'Scanning trash & recently deleted folders...', phase: 'deep_scan',
          totalScanned: scannedPaths.length, totalBytesScanned: totalBytes,
          storageLocations: locIndex + 1, signaturesMatched: _signaturesMatched,
          elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
        );
        await Future.delayed(const Duration(milliseconds: 400));

        for (final trashPath in deletedTracePaths) {
          if (_isCancelled) break;
          if (await _waitIfPaused()) break;

          final fullPath = '$baseStoragePath/$trashPath';
          final dir = Directory(fullPath);
          if (!await dir.exists()) continue;

          final bytesBefore = allFiles.fold<int>(0, (sum, f) => sum + f.size);
          await _scanDirectoryRecursive(
            fullPath, extensions, fileType, scannedPaths, allFiles,
            currentDepth: 0, maxDepth: 6, isDeepScan: true,
          );
          totalBytes += allFiles.fold<int>(0, (sum, f) => sum + f.size) - bytesBefore;
        }

        // Scan DCIM for recently deleted subfolders
        try {
          final dcimDir = Directory('$baseStoragePath/DCIM');
          if (await dcimDir.exists()) {
            await for (final entity in dcimDir.list()) {
              if (_isCancelled) break;
              if (entity is Directory) {
                final name = entity.path.split('/').last.toLowerCase();
                if (name.contains('recently') || name.contains('deleted') ||
                    name.contains('trash') || name.contains('restore') ||
                    name.contains('.thumbnails') || name.contains('100andro') ||
                    name.contains('100media')) {
                  await _scanDirectoryRecursive(
                    entity.path, extensions, fileType, scannedPaths, allFiles,
                    currentDepth: 0, maxDepth: 6, isDeepScan: true,
                  );
                }
              }
            }
          }
        } catch (_) {}

        if (_isCancelled) { yield _buildFinal(allFiles, stopwatch, totalBytes); return; }

        // ============================================================
        // PHASE 8: TEMP / BACKUP / PARTIAL FILE RECOVERY
        // ============================================================
        yield ScanProgress(
          progress: 0.72, currentFolder: 'Temp & Backup', filesFound: allFiles.length,
          status: 'Scanning temp, backup & partial download files...', phase: 'deep_scan',
          totalScanned: scannedPaths.length, totalBytesScanned: totalBytes,
          storageLocations: locIndex + 1, signaturesMatched: _signaturesMatched,
          elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
        );
        await Future.delayed(const Duration(milliseconds: 300));

        final tempResults = await _scanTempAndBackupFiles(
          baseStoragePath, fileType, scannedPaths,
        );
        allFiles.addAll(tempResults);
        totalBytes += tempResults.fold<int>(0, (sum, f) => sum + f.size);

        yield ScanProgress(
          progress: 0.76, currentFolder: 'Temp & Backup', filesFound: allFiles.length,
          status: 'Found ${tempResults.length} files from temp/backup folders',
          phase: 'deep_scan', totalScanned: scannedPaths.length,
          totalBytesScanned: totalBytes, storageLocations: locIndex + 1,
          signaturesMatched: _signaturesMatched,
          elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
        );

        if (_isCancelled) { yield _buildFinal(allFiles, stopwatch, totalBytes); return; }

        // ============================================================
        // PHASE 8.5: WHATSAPP STATUS & CONTACT BACKUP RECOVERY
        // ============================================================
        yield ScanProgress(
          progress: 0.77, currentFolder: 'WhatsApp Status', filesFound: allFiles.length,
          status: 'Scanning WhatsApp Status & contact backups...',
          phase: 'deep_scan',
          totalScanned: scannedPaths.length, totalBytesScanned: totalBytes,
          storageLocations: locIndex + 1, signaturesMatched: _signaturesMatched,
          elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
        );
        await Future.delayed(const Duration(milliseconds: 250));

        // Scan WhatsApp Status media (disappears after 24h)
        for (final statusPath in whatsappStatusPaths) {
          if (_isCancelled) break;
          if (await _waitIfPaused()) break;
          final fullPath = '$baseStoragePath/$statusPath';
          final dir = Directory(fullPath);
          if (!await dir.exists()) continue;
          final bytesBefore = allFiles.fold<int>(0, (sum, f) => sum + f.size);
          await _scanDirectoryRecursive(
            fullPath, extensions, fileType, scannedPaths, allFiles,
            currentDepth: 0, maxDepth: 4, isDeepScan: true,
          );
          totalBytes += allFiles.fold<int>(0, (sum, f) => sum + f.size) - bytesBefore;
        }

        // Scan for VCF contact backup files
        final contactDirs = [
          '$baseStoragePath/Download',
          '$baseStoragePath/Downloads',
          '$baseStoragePath/Documents',
          '$baseStoragePath/WhatsApp',
          '$baseStoragePath/Bluetooth',
        ];
        for (final contactDir in contactDirs) {
          if (_isCancelled) break;
          final dir = Directory(contactDir);
          if (!await dir.exists()) continue;
          try {
            await for (final entity in dir.list(recursive: true, followLinks: false)) {
              if (_isCancelled) break;
              if (entity is File && scannedPaths.add(entity.path)) {
                final ext = _getExtension(entity.path).toLowerCase();
                if (contactExtensions.contains(ext)) {
                  try {
                    final stat = await entity.stat();
                    if (stat.size >= 50) {
                      allFiles.add(RecoverableFile(
                        id: entity.path,
                        name: entity.path.split('/').last,
                        path: entity.path,
                        extension: ext,
                        size: stat.size,
                        lastModified: stat.modified,
                        fileType: 'file',
                        source: _getSourceName(entity.path),
                        qualityTag: 'medium',
                      ));
                    }
                  } catch (_) {}
                }
              }
            }
          } catch (_) {}
        }

        // ============================================================
        // PHASE 9: ORPHANED THUMBNAIL DETECTION
        // ============================================================
        yield ScanProgress(
          progress: 0.78, currentFolder: 'Orphan Detection', filesFound: allFiles.length,
          status: 'Detecting orphaned thumbnails (deleted originals)...', phase: 'analysis',
          totalScanned: scannedPaths.length, totalBytesScanned: totalBytes,
          storageLocations: locIndex + 1, signaturesMatched: _signaturesMatched,
          elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
        );
        await Future.delayed(const Duration(milliseconds: 400));

        final orphaned = await _findOrphanedThumbnails(baseStoragePath, scannedPaths, extensions, fileType);
        allFiles.addAll(orphaned);
        totalBytes += orphaned.fold<int>(0, (sum, f) => sum + f.size);

        if (_isCancelled) { yield _buildFinal(allFiles, stopwatch, totalBytes); return; }

        // ============================================================
        // PHASE 10: FULL STORAGE SCAN (remaining dirs)
        // ============================================================
        yield ScanProgress(
          progress: 0.82, currentFolder: 'Full Storage', filesFound: allFiles.length,
          status: 'Scanning all remaining storage directories...', phase: 'deep_scan',
          totalScanned: scannedPaths.length, totalBytesScanned: totalBytes,
          storageLocations: locIndex + 1, signaturesMatched: _signaturesMatched,
          elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
        );

        for (final dir in allTopLevelDirs) {
          if (_isCancelled) break;
          if (await _waitIfPaused()) break;

          final dirName = dir.path.split('/').last;
          final isPriority = normalScanFolders.any((p) => p.toLowerCase() == dirName.toLowerCase());
          if (isPriority) continue;
          if (skipFolderNames.contains(dirName)) continue;
          if (dirName == 'Android') continue;

          final displayName = _getFolderDisplayName(dir.path);

          yield ScanProgress(
            progress: 0.82 + Random().nextDouble() * 0.03,
            currentFolder: displayName, filesFound: allFiles.length,
            status: 'Deep scanning $displayName...', phase: 'deep_scan',
            totalScanned: scannedPaths.length, totalBytesScanned: totalBytes,
            storageLocations: locIndex + 1, signaturesMatched: _signaturesMatched,
            elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
          );

          final bytesBefore = allFiles.fold<int>(0, (sum, f) => sum + f.size);
          await _scanDirectoryRecursive(
            dir.path, extensions, fileType, scannedPaths, allFiles,
            currentDepth: 0, maxDepth: 6, isDeepScan: true,
          );
          totalBytes += allFiles.fold<int>(0, (sum, f) => sum + f.size) - bytesBefore;
        }

        // ============================================================
        // PHASE 11: DEEP ANDROID/DATA SCAN
        // ============================================================
        yield ScanProgress(
          progress: 0.86, currentFolder: 'App Data', filesFound: allFiles.length,
          status: 'Deep scanning all app data folders...', phase: 'deep_scan',
          totalScanned: scannedPaths.length, totalBytesScanned: totalBytes,
          storageLocations: locIndex + 1, signaturesMatched: _signaturesMatched,
          elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
        );

        try {
          final androidDataDir = Directory('$baseStoragePath/Android/data');
          if (await androidDataDir.exists()) {
            String? lastApp;
            int appIndex = 0;
            await for (final entity in androidDataDir.list()) {
              if (_isCancelled) break;
              if (await _waitIfPaused()) break;
              if (entity is Directory) {
                final appName = entity.path.split('/').last;

                // Skip apps already scanned
                if (appMediaCachePaths.any((p) => entity.path.contains(p))) continue;

                // Skip system apps by prefix
                bool skipSystem = false;
                for (final prefix in skipFolderPrefixes) {
                  if (appName.startsWith(prefix)) {
                    skipSystem = true;
                    break;
                  }
                }
                if (skipSystem) continue;

                appIndex++;
                if (appName != lastApp) {
                  yield ScanProgress(
                    progress: 0.86 + (appIndex % 25) * 0.002,
                    currentFolder: appName, filesFound: allFiles.length,
                    status: 'Scanning $appName...', phase: 'deep_scan',
                    totalScanned: scannedPaths.length, totalBytesScanned: totalBytes,
                    storageLocations: locIndex + 1, signaturesMatched: _signaturesMatched,
                    elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
                  );
                  lastApp = appName;
                }

                final bytesBefore = allFiles.fold<int>(0, (sum, f) => sum + f.size);
                await _scanDirectoryRecursive(
                  entity.path, extensions, fileType, scannedPaths, allFiles,
                  currentDepth: 0, maxDepth: 5, isDeepScan: true,
                );
                totalBytes += allFiles.fold<int>(0, (sum, f) => sum + f.size) - bytesBefore;
              }
            }
          }
        } catch (_) {}

        // Also scan Android/media
        try {
          final androidMediaDir = Directory('$baseStoragePath/Android/media');
          if (await androidMediaDir.exists()) {
            await _scanDirectoryRecursive(
              androidMediaDir.path, extensions, fileType, scannedPaths, allFiles,
              currentDepth: 0, maxDepth: 6, isDeepScan: true,
            );
          }
        } catch (_) {}

        // Also scan Android/obb (some games/apps store media here)
        try {
          final obbDir = Directory('$baseStoragePath/Android/obb');
          if (await obbDir.exists()) {
            await _scanDirectoryRecursive(
              obbDir.path, extensions, fileType, scannedPaths, allFiles,
              currentDepth: 0, maxDepth: 4, isDeepScan: true,
            );
          }
        } catch (_) {}
      } // end deep scan phases

      totalDirsScanned += allTopLevelDirs.length;
    } // end storage locations loop

    if (_isCancelled) { yield _buildFinal(allFiles, stopwatch, totalBytes); return; }

    // ================================================================
    // PRE-FINAL: Filter for deleted-only mode
    // ================================================================
    if (deletedOnly) {
      yield ScanProgress(
        progress: 0.92, currentFolder: 'Filtering', filesFound: allFiles.length,
        status: 'Filtering accessible results, keeping likely recycle/cache traces...', phase: 'analysis',
        totalScanned: scannedPaths.length, totalBytesScanned: totalBytes,
        storageLocations: _storageLocationsScanned, signaturesMatched: _signaturesMatched,
        elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
      );
      await Future.delayed(const Duration(milliseconds: 400));

      final preFilterCandidates = List<RecoverableFile>.from(allFiles);
      final beforeFilter = allFiles.length;
      allFiles.removeWhere((f) => _isLikelyExistingFile(f, fileType));
      final removed = beforeFilter - allFiles.length;

      // Cross-device fallback:
      // Some OEM ROMs expose recycle/cache traces in unusual locations that can be
      // over-filtered by strict existing-file heuristics.
      if (allFiles.isEmpty && (scannedPaths.length > 5000 || _signaturesMatched > 200)) {
        final fallback = preFilterCandidates.where((f) {
          final p = f.path.toLowerCase();
          final src = f.source.toLowerCase();
          final ext = f.extension.toLowerCase();
          final isValidTypeExt = fileType == 'photo'
              ? photoExtensions.contains(ext)
              : fileType == 'video'
                  ? videoExtensions.contains(ext)
                  : [...documentExtensions, ...audioExtensions].contains(ext);
          if (!isValidTypeExt) return false;
          if (f.size <= minFileSize) return false;

          return p.contains('/android/media/') ||
              p.contains('/android/data/') ||
              p.contains('/cache/') ||
              p.contains('/.thumbnails') ||
              p.contains('/trash') ||
              p.contains('/recently') ||
              src.contains('hidden') ||
              src.contains('cache') ||
              src.contains('other');
        }).take(400).toList();

        if (fallback.isNotEmpty) {
          allFiles
            ..clear()
            ..addAll(fallback);
        }
      }

      yield ScanProgress(
        progress: 0.93, currentFolder: 'Filtered', filesFound: allFiles.length,
        status: 'Removed $removed regular files. Kept ${allFiles.length} likely trace files.', phase: 'analysis',
        totalScanned: scannedPaths.length, totalBytesScanned: totalBytes,
        storageLocations: _storageLocationsScanned, signaturesMatched: _signaturesMatched,
        elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
      );
      await Future.delayed(const Duration(milliseconds: 300));
    }

    // ================================================================
    // FINAL PHASE: Deduplicate, Quality Score, Sort & Complete
    // ================================================================
    yield ScanProgress(
      progress: deletedOnly ? 0.94 : 0.93, currentFolder: 'Deduplication', filesFound: allFiles.length,
      status: 'Removing duplicates & scoring quality...', phase: 'analysis',
      totalScanned: scannedPaths.length, totalBytesScanned: totalBytes,
      storageLocations: _storageLocationsScanned, signaturesMatched: _signaturesMatched,
      elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
    );
    await Future.delayed(const Duration(milliseconds: 500));

    // Deduplicate by path
    final seen = HashSet<String>();
    final deduped = <RecoverableFile>[];
    for (final f in allFiles) {
      if (seen.add(f.path)) {
        deduped.add(f);
      }
    }

    // Smart deduplication by size + extension (catch renamed duplicates)
    final sizeExtSeen = HashSet<String>();
    final smartDeduped = <RecoverableFile>[];
    for (final f in deduped) {
      // Keep files from different sources even if same size
      final key = '${f.size}_${f.extension}_${f.name.toLowerCase().replaceAll(RegExp(r'\d'), '')}';
      if (sizeExtSeen.add(key) || !f.path.contains('/cache/') || !f.path.contains('/.thumbnails')) {
        smartDeduped.add(f);
      }
    }

    // Quality scoring
    for (final f in smartDeduped) {
      f.qualityTag = _computeQualityScore(f);
    }

    yield ScanProgress(
      progress: 0.94, currentFolder: 'EXIF Analysis', filesFound: smartDeduped.length,
      status: 'Extracting EXIF metadata & assessing corruption...',
      phase: 'analysis', totalScanned: scannedPaths.length,
      totalBytesScanned: totalBytes, storageLocations: _storageLocationsScanned,
      signaturesMatched: _signaturesMatched,
      elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
    );
    await Future.delayed(const Duration(milliseconds: 300));

    // ENHANCEMENT: EXIF extraction & corruption assessment for photos/videos
    for (int i = 0; i < smartDeduped.length; i++) {
      final f = smartDeduped[i];
      if (f.fileType == 'photo') {
        try {
          final exif = ExifExtractor.extractFromFile(f.path);
          if (exif.hasExif) {
            f.cameraInfo = exif.cameraInfo;
            f.resolution = exif.resolution;
            f.gpsLocation = exif.gpsLocation;
            f.dateTaken = exif.dateTimeOriginal;
            f.orientation = exif.orientation;
            f.software = exif.software;
            f.iso = exif.iso;
          } else {
            // Get dimensions from header even without EXIF
            final dims = ExifExtractor.getImageDimensions(f.path);
            if (dims.containsKey('width')) {
              f.resolution = '${dims['width']}x${dims['height']}';
            }
          }
          // Assess corruption
          f.corruptionLevel = FileRepairService.assessCorruption(f.path);
          if (f.corruptionLevel != null && f.corruptionLevel! > 0.5) {
            f.qualityTag = 'corrupted';
          }
        } catch (_) {}
      } else if (f.fileType == 'video') {
        try {
          final dims = ExifExtractor.getImageDimensions(f.path);
          if (dims.containsKey('width')) {
            f.resolution = '${dims['width']}x${dims['height']}';
          }
          f.corruptionLevel = FileRepairService.assessCorruption(f.path);
        } catch (_) {}
      }
      // Check if file is new (incremental scan)
      f.isNewFile = !(await ScanCacheService.isNewFile(fileType, f.path));
    }

    // Incremental: save scanned paths to cache
    await ScanCacheService.saveScannedPaths(
      fileType,
      smartDeduped.map((f) => f.path).toSet(),
    );

    // Save scan results to cache
    await ScanCacheService.saveScanResults(
      fileType,
      smartDeduped.map((f) => f.toMap()).toList(),
    );

    yield ScanProgress(
      progress: 0.97, currentFolder: 'Finalizing', filesFound: smartDeduped.length,
      status: 'Sorting ${smartDeduped.length} files by quality & date...',
      phase: 'analysis', totalScanned: scannedPaths.length,
      totalBytesScanned: totalBytes, storageLocations: _storageLocationsScanned,
      signaturesMatched: _signaturesMatched,
      elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
    );
    await Future.delayed(const Duration(milliseconds: 400));

    // Sort: quality desc, then date desc
    smartDeduped.sort((a, b) {
      final qa = _qualityScoreValue(a.qualityTag);
      final qb = _qualityScoreValue(b.qualityTag);
      if (qa != qb) return qb.compareTo(qa);
      return b.lastModified.compareTo(a.lastModified);
    });

    _lastScanResults = smartDeduped;

    yield _buildFinal(smartDeduped, stopwatch, totalBytes);
  }

  // ====================================================================
  // QUALITY SCORING
  // ====================================================================

  String _computeQualityScore(RecoverableFile file) {
    // Already scored from temp/signature recovery
    if (file.qualityTag != null) return file.qualityTag!;

    final path = file.path.toLowerCase();

    // Source-based scoring
    if (path.contains('/dcim/camera')) return 'high';
    if (path.contains('/dcim/') && !path.contains('.thumbnails')) return 'high';
    if (path.contains('/pictures/') && !path.contains('.thumbnails') && !path.contains('/cache')) return 'high';
    if (path.contains('/screenshots')) return 'high';
    if (path.contains('/whatsapp/') && !path.contains('/.thumbnails') && !path.contains('/media/')) return 'high';
    if (path.contains('/instagram/')) return 'high';
    if (path.contains('/telegram/')) return 'high';

    // Medium quality
    if (path.contains('/download')) return 'medium';
    if (path.contains('/bluetooth')) return 'medium';
    if (path.contains('/shared')) return 'medium';
    if (path.contains('/gallery')) return 'medium';
    if (path.contains('/movies') || path.contains('/video')) return 'medium';
    if (path.contains('/android/media')) return 'medium';
    if (path.contains('/android/data/com.whatsapp')) return 'medium';

    // Low quality
    if (path.contains('/cache') || path.contains('/Cache')) return 'low';
    if (path.contains('.thumbnails') || path.contains('.thumbdata')) return 'thumbnail';
    if (path.contains('/.face')) return 'thumbnail';

    // Size-based fallback
    if (file.size > 5000000) return 'high';     // > 5MB
    if (file.size > 500000) return 'medium';      // > 500KB
    if (file.size < 30000) return 'thumbnail';    // < 30KB
    return 'medium';
  }

  int _qualityScoreValue(String? quality) {
    switch (quality) {
      case 'high': return 4;
      case 'medium': return 3;
      case 'low': return 2;
      case 'thumbnail': return 1;
      case 'corrupted': return 0;
      case 'recovered': return 3;
      case 'partial': return 2;
      default: return 2;
    }
  }

  // ====================================================================
  // RECURSIVE DIRECTORY SCANNER
  // ====================================================================

  Future<void> _scanDirectoryRecursive(
    String path, List<String> extensions, String fileType,
    Set<String> scannedPaths, List<RecoverableFile> results, {
    required int currentDepth, required int maxDepth,
    required bool isDeepScan, String? forceQualityTag,
  }) async {
    if (currentDepth > maxDepth || _isCancelled) return;
    final dir = Directory(path);
    if (!await dir.exists()) return;

    try {
      int batchCount = 0;

      await for (final entity in dir.list(followLinks: false)) {
        if (_isCancelled) break;
        if (_isPaused) { await _waitIfPaused(); if (_isCancelled) break; }

        if (entity is File) {
          final ext = _getExtension(entity.path).toLowerCase();
          if (extensions.contains(ext) && scannedPaths.add(entity.path)) {
            try {
              final stat = await entity.stat();
              if (stat.size < minFileSize) continue;

              final source = _getSourceName(entity.path);
              final isFromHidden = _isHiddenPath(entity.path);
              final isCache = _isCachePath(entity.path);

              String? qualityTag = forceQualityTag;
              if (qualityTag == null) {
                qualityTag = stat.size < thumbnailMaxSize && (isFromHidden || isCache)
                    ? 'thumbnail' : null;
              }

              results.add(RecoverableFile(
                id: entity.path,
                name: entity.path.split('/').last,
                path: entity.path,
                extension: ext,
                size: stat.size,
                lastModified: stat.modified,
                fileType: fileType,
                source: isFromHidden ? 'Hidden' : isCache ? 'Cache' : source,
                qualityTag: qualityTag,
              ));

              batchCount++;
              if (batchCount % batchSize == 0) {
                await Future.delayed(const Duration(milliseconds: fileStatDelay));
              }
            } catch (_) {}
          }
        } else if (entity is Directory) {
          final dirName = entity.path.split('/').last;

          // Skip rules
          if (skipFolderNames.contains(dirName)) continue;

          // In normal mode, skip hidden dot-folders
          if (!isDeepScan && dirName.startsWith('.') &&
              !thumbnailPaths.any((p) => entity.path.contains(p))) continue;

          // Skip Android/data in normal mode
          if (!isDeepScan && (dirName == 'Android' || dirName == 'data')) continue;

          // System skip
          if (dirName == 'dexopt' || dirName == 'dalvik-cache' ||
              dirName == 'app-lib' || dirName == 'app-libs') continue;

          await _scanDirectoryRecursive(
            entity.path, extensions, fileType, scannedPaths, results,
            currentDepth: currentDepth + 1, maxDepth: maxDepth,
            isDeepScan: isDeepScan, forceQualityTag: forceQualityTag,
          );
        }
      }
    } catch (_) {}
  }

  // ====================================================================
  // MAGIC BYTES SIGNATURE SCANNER
  // ====================================================================

  /// Scan files that have NO extension or WRONG extension but match by binary header
  Future<List<RecoverableFile>> _scanBySignatures(
    String basePath, List<String> extensions, String fileType,
    Set<String> scannedPaths, bool isDeepScan,
  ) async {
    final results = <RecoverableFile>[];
    final extensionSet = extensions.toSet();

    // Build set of valid extensions for quick lookup
    final allValidExts = {...extensionSet, ...tempRecoveryExtensions.toSet()};

    // Scan key directories for extensionless or misnamed files
    final scanTargets = [
      '$basePath/DCIM',
      '$basePath/Pictures',
      '$basePath/Download',
      '$basePath/Downloads',
      '$basePath/WhatsApp',
      '$basePath/Telegram',
      '$basePath/Movies',
      '$basePath/Video',
      '$basePath/Videos',
      '$basePath/Recordings',
      '$basePath/Bluetooth',
      '$basePath/Music',
      if (isDeepScan) ...[
        '$basePath/.Trash',
        '$basePath/Trash',
        '$basePath/Documents',
        '$basePath/Shared',
        '$basePath/.thumbnails',
        '$basePath/Android/media',
      ],
    ];

    int checkedCount = 0;

    for (final targetPath in scanTargets) {
      if (_isCancelled) break;
      if (await _waitIfPaused()) break;

      final targetDir = Directory(targetPath);
      if (!await targetDir.exists()) continue;

      try {
        await for (final entity in targetDir.list(recursive: true, followLinks: false)) {
          if (_isCancelled) break;
          if (entity is! File) continue;
          if (scannedPaths.contains(entity.path)) continue;

          checkedCount++;

          // Check extension
          final ext = _getExtension(entity.path).toLowerCase();

          // Case 1: File has NO extension at all
          if (ext.isEmpty) {
            final identified = SignatureDetector.quickIdentify(entity.path);
            if (identified != null) {
              try {
                final stat = await entity.stat();
                if (stat.size < minFileSize) continue;

                final properExt = _getProperExtension(identified);
                if (!extensionSet.contains(properExt)) continue;

                _signaturesMatched++;
                results.add(RecoverableFile(
                  id: entity.path,
                  name: entity.path.split('/').last,
                  path: entity.path,
                  extension: properExt,
                  size: stat.size,
                  lastModified: stat.modified,
                  fileType: fileType,
                  source: _getSourceName(entity.path),
                  qualityTag: 'recovered',
                ));
                scannedPaths.add(entity.path);
              } catch (_) {}
            }
          }
          // Case 2: File has an unrecognized extension (might be renamed/misnamed)
          else if (!allValidExts.contains(ext) && !isCommonSystemExtension(ext)) {
            final identified = SignatureDetector.quickIdentify(entity.path);
            if (identified != null && identified == fileType) {
              try {
                final stat = await entity.stat();
                if (stat.size < minFileSize) continue;

                final properExt = _getProperExtension(identified);
                _signaturesMatched++;
                results.add(RecoverableFile(
                  id: entity.path,
                  name: entity.path.split('/').last,
                  path: entity.path,
                  extension: properExt,
                  size: stat.size,
                  lastModified: stat.modified,
                  fileType: fileType,
                  source: _getSourceName(entity.path),
                  qualityTag: 'recovered',
                ));
                scannedPaths.add(entity.path);
              } catch (_) {}
            }
          }

          // Pace the signature scanning
          if (checkedCount % 20 == 0) {
            await Future.delayed(const Duration(milliseconds: 5));
          }
        }
      } catch (_) {}
    }

    return results;
  }

  // ====================================================================
  // TEMP / BACKUP / PARTIAL FILE RECOVERY
  // ====================================================================

  Future<List<RecoverableFile>> _scanTempAndBackupFiles(
    String basePath, String fileType, Set<String> scannedPaths,
  ) async {
    final results = <RecoverableFile>[];

    // Known temp/download directories
    final tempDirs = [
      '$basePath/Download',
      '$basePath/Downloads',
      '$basePath/Android/data/com.android.providers.downloads',
      '$basePath/Android/data/com.opera.browser/cache',
      '$basePath/Android/data/com.android.chrome/cache',
      '$basePath/Android/data/org.mozilla.firefox/cache',
      '$basePath/Android/data/com.UCMobile.intl/cache',
      '$basePath/.Trash',
      '$basePath/Trash',
    ];

    for (final tempPath in tempDirs) {
      if (_isCancelled) break;
      if (await _waitIfPaused()) break;

      final tempDir = Directory(tempPath);
      if (!await tempDir.exists()) continue;

      try {
        await for (final entity in tempDir.list(recursive: true, followLinks: false)) {
          if (_isCancelled) break;
          if (entity is! File) continue;
          if (scannedPaths.contains(entity.path)) continue;

          final ext = _getExtension(entity.path).toLowerCase();
          if (!tempRecoveryExtensions.contains(ext)) continue;

          try {
            final stat = await entity.stat();
            if (stat.size < 1024) continue; // Skip very small temp files

            final identified = SignatureDetector.quickIdentify(entity.path);
            if (identified == fileType || (fileType == 'file' && identified != null)) {
              final properExt = _getProperExtension(identified ?? fileType);
              _signaturesMatched++;
              results.add(RecoverableFile(
                id: entity.path,
                name: entity.path.split('/').last,
                path: entity.path,
                extension: properExt,
                size: stat.size,
                lastModified: stat.modified,
                fileType: fileType,
                source: _getSourceName(entity.path),
                qualityTag: 'partial',
              ));
              scannedPaths.add(entity.path);
            }
          } catch (_) {}
        }
      } catch (_) {}
    }

    return results;
  }

  // ====================================================================
  // ORPHANED THUMBNAIL DETECTION
  // ====================================================================

  Future<List<RecoverableFile>> _findOrphanedThumbnails(
    String basePath, Set<String> existingPaths, List<String> extensions, String fileType,
  ) async {
    final orphaned = <RecoverableFile>[];

    final existingBaseNames = <String>{};
    for (final p in existingPaths) {
      final name = p.split('/').last.split('.').first;
      existingBaseNames.add(name.toLowerCase());
    }

    final thumbDirs = <String>[
      '$basePath/DCIM/.thumbnails',
      '$basePath/Pictures/.thumbnails',
      '$basePath/.thumbnails',
      '$basePath/.THMBDATA',
    ];

    // Dynamic thumbnail dirs
    try {
      final baseDir = Directory(basePath);
      if (await baseDir.exists()) {
        await for (final entity in baseDir.list()) {
          if (_isCancelled) break;
          if (entity is Directory) {
            final name = entity.path.split('/').last.toLowerCase();
            if (name.contains('thumbnail') || name.contains('.thumb')) {
              thumbDirs.add(entity.path);
            }
          }
        }
      }
    } catch (_) {}

    // DCIM subfolder thumbnails
    try {
      final dcimDir = Directory('$basePath/DCIM');
      if (await dcimDir.exists()) {
        await for (final entity in dcimDir.list()) {
          if (_isCancelled) break;
          if (entity is Directory) {
            final thumbSub = Directory('${entity.path}/.thumbnails');
            if (await thumbSub.exists()) thumbDirs.add(thumbSub.path);
          }
        }
      }
    } catch (_) {}

    for (final thumbPath in thumbDirs) {
      if (_isCancelled) break;
      if (await _waitIfPaused()) break;
      final dir = Directory(thumbPath);
      if (!await dir.exists()) continue;

      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (_isCancelled) break;
          if (entity is File) {
            final ext = _getExtension(entity.path).toLowerCase();
            if (extensions.contains(ext) && !existingPaths.contains(entity.path)) {
              try {
                final stat = await entity.stat();
                if (stat.size < 512) continue;

                final baseName = entity.path.split('/').last.split('.').first.toLowerCase();
                final isOrphaned = !existingBaseNames.any((n) => baseName.startsWith(n) || n.startsWith(baseName));

                orphaned.add(RecoverableFile(
                  id: entity.path,
                  name: entity.path.split('/').last,
                  path: entity.path,
                  extension: ext,
                  size: stat.size,
                  lastModified: stat.modified,
                  fileType: fileType,
                  source: isOrphaned ? 'Media Trace' : 'Hidden',
                  qualityTag: isOrphaned ? 'corrupted' : 'thumbnail',
                ));
              } catch (_) {}
            }
          }
        }
      } catch (_) {}
    }

    return orphaned;
  }

  // ====================================================================
  // DELETED-ONLY FILTER
  // ====================================================================

  /// Determines if a file appears to be a normal, existing (non-deleted) file.
  /// If true, the file is EXCLUDED from "Scan Deleted" results.
  ///
  /// A file is considered "existing" if it:
  /// - Has a standard extension for its type
  /// - Is NOT in a hidden/dot folder
  /// - Is NOT in a cache folder
  /// - Is NOT a thumbnail
  /// - Quality tag is NOT 'recovered', 'corrupted', or 'thumbnail'
  /// - Source is NOT from hidden/cache/carving/signature paths
  /// - Is located in a standard visible media folder (DCIM, Pictures, Camera, etc.)
  /// - Does NOT have a temp/partial/download extension
  /// - Size is above thumbnail threshold
  bool _isLikelyExistingFile(RecoverableFile f, String fileType) {
    // Always keep files tagged as recovered, corrupted, or thumbnail
    if (f.qualityTag == 'recovered' || f.qualityTag == 'corrupted' || f.qualityTag == 'thumbnail') {
      return false; // NOT existing -> keep in deleted results
    }

    // Always keep files from hidden/cache/carving sources
    if (f.source == 'Hidden' || f.source == 'Cache' ||
        f.source == 'Carving' || f.source == 'Signature' ||
        f.source == 'Trash' || f.source == 'WhatsApp Status' ||
        f.source == 'Temp Recovery' || f.source == 'Orphaned') {
      return false; // NOT existing -> keep in deleted results
    }

    // Keep files in hidden paths (dot-folders)
    if (_isHiddenPath(f.path)) return false;

    // Keep files in cache paths
    if (_isCachePath(f.path)) return false;

    // On several OEM ROMs, deleted or stale media remnants remain under
    // Android/media with normal-looking paths; don't classify too aggressively.
    if (f.path.contains('/Android/media/') || f.path.contains('/android/media/')) {
      return false;
    }

    // Keep files in trash/recently-deleted paths
    for (final trashPath in deletedTracePaths) {
      if (f.path.contains('/$trashPath/') || f.path.endsWith('/$trashPath')) {
        return false;
      }
    }

    // Keep files with temp/partial/download extensions
    final ext = f.extension.toLowerCase();
    if (tempRecoveryExtensions.contains(ext)) return false;

    // Keep files that have no extension or a wrong extension (found by carving)
    if (ext.isEmpty) return false;

    // Check if file is in a standard visible media folder
    final pathParts = f.path.split('/');
    bool inStandardFolder = false;
    for (final part in pathParts) {
      final lower = part.toLowerCase();
      if (normalScanFolders.contains(lower) ||
          normalScanFolders.any((p) => p.toLowerCase() == lower)) {
        inStandardFolder = true;
        break;
      }
    }

    // If NOT in a standard folder, it's likely deleted/hidden -> keep it
    if (!inStandardFolder) return false;

    // If file has standard extension, is in a visible folder, not hidden/cache,
    // and not tagged as recovered/corrupted/thumbnail -> it's likely existing
    // Check for valid standard extension for the file type
    final validExtensions = fileType == 'photo' ? photoExtensions
        : fileType == 'video' ? videoExtensions
        : [...documentExtensions, ...audioExtensions];

    if (validExtensions.contains(ext) || validExtensions.any((e) => e.toLowerCase() == ext)) {
      // Standard extension + standard folder + no special tags = existing file
      // Exclude if the file is suspiciously small (might be a remnant)
      if (f.size > thumbnailMaxSize) {
        return true; // IS existing -> EXCLUDE from deleted results
      }
    }

    // Default: keep the file in deleted results
    return false;
  }

  // ====================================================================
  // UTILITIES
  // ====================================================================

  ScanProgress _buildFinal(List<RecoverableFile> files, Stopwatch stopwatch, int totalBytes, {bool cancelled = false}) {
    final highCount = files.where((f) => f.qualityTag == 'high').length;
    final medCount = files.where((f) => f.qualityTag == 'medium' || f.qualityTag == 'recovered').length;

    return ScanProgress(
      progress: 1.0, currentFolder: cancelled ? 'Cancelled' : 'Complete',
      filesFound: files.length, phase: 'complete', totalScanned: files.length,
      totalBytesScanned: totalBytes,
      status: cancelled
          ? 'Scan cancelled. Found ${files.length} files.'
          : 'Found ${files.length} files! ($highCount high quality, $medCount medium)',
      elapsedSeconds: stopwatch.elapsedMilliseconds ~/ 1000,
      signaturesMatched: _signaturesMatched,
      storageLocations: _storageLocationsScanned,
    );
  }

  String _getExtension(String path) {
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex == -1) return '';
    return path.substring(dotIndex);
  }

  String _getProperExtension(String fileType) {
    switch (fileType) {
      case 'photo': return '.jpg';
      case 'video': return '.mp4';
      case 'file': return '.bin';
      default: return '.dat';
    }
  }

  bool isCommonSystemExtension(String ext) {
    const systemExts = [
      '.xml', '.json', '.log', '.db', '.sqlite', '.db-journal',
      '.ini', '.cfg', '.conf', '.properties', '.lock',
      '.class', '.dex', '.so', '.odex', '.vdex', '.oat',
      '.apk', '.jar', '.sh', '.bat', '.cmd',
      '.proto', '.gradle', '.kts', '.kt', '.java',
      '.tmp', '.bak', '.swp', '.part', '.crdownload',
    ];
    return systemExts.contains(ext.toLowerCase());
  }

  bool _isHiddenPath(String path) {
    final parts = path.split('/');
    for (final part in parts) {
      if (part.startsWith('.') && part != '.' && part != '..') return true;
    }
    return false;
  }

  bool _isCachePath(String path) {
    return path.contains('/cache/') || path.contains('/Cache/');
  }

  String _getSourceName(String path) {
    if (path.contains('/DCIM/Camera')) return 'Camera';
    if (path.contains('/DCIM')) return 'DCIM';
    if (path.contains('/WhatsApp') || path.contains('/whatsapp')) return 'WhatsApp';
    if (path.contains('/Telegram') || path.contains('/telegram')) return 'Telegram';
    if (path.contains('/Instagram') || path.contains('/instagram')) return 'Instagram';
    if (path.contains('/TikTok') || path.contains('/tiktok') || path.contains('/musically')) return 'TikTok';
    if (path.contains('/Snapchat') || path.contains('/snapchat')) return 'Snapchat';
    if (path.contains('/Viber') || path.contains('/viber')) return 'Viber';
    if (path.contains('/Messenger') || path.contains('/messenger')) return 'Messenger';
    if (path.contains('/Signal') || path.contains('/securesms')) return 'Signal';
    if (path.contains('/LINE') || path.contains('/line.android')) return 'LINE';
    if (path.contains('/Facebook') || path.contains('/facebook')) return 'Facebook';
    if (path.contains('/Twitter') || path.contains('/twitter')) return 'Twitter';
    if (path.contains('/Pinterest') || path.contains('/pinterest')) return 'Pinterest';
    if (path.contains('/LinkedIn') || path.contains('/linkedin')) return 'LinkedIn';
    if (path.contains('/Google Photos') || path.contains('/google.android.apps.photos')) return 'Google Photos';
    if (path.contains('/WeChat') || path.contains('/tencent.mm')) return 'WeChat';
    if (path.contains('/Discord') || path.contains('/discord')) return 'Discord';
    if (path.contains('/KakaoTalk') || path.contains('/kakao.talk')) return 'KakaoTalk';
    if (path.contains('/Reddit') || path.contains('/reddit')) return 'Reddit';
    if (path.contains('/VLC') || path.contains('/videolan')) return 'VLC';
    if (path.contains('/YouTube') || path.contains('/youtube')) return 'YouTube';
    if (path.contains('/Netflix') || path.contains('/netflix')) return 'Netflix';
    if (path.contains('/Spotify') || path.contains('/spotify')) return 'Spotify';
    if (path.contains('/CapCut') || path.contains('/capcut') || path.contains('/nexstreaming')) return 'CapCut';
    if (path.contains('/InShot') || path.contains('/inshot') || path.contains('/zideate')) return 'InShot';
    if (path.contains('/MX Player') || path.contains('/mxtech')) return 'MX Player';
    if (path.contains('/KMPlayer') || path.contains('/kmplayer')) return 'KMPlayer';
    if (path.contains('/OneDrive') || path.contains('/skydrive')) return 'OneDrive';
    if (path.contains('/Dropbox') || path.contains('/dropbox')) return 'Dropbox';
    if (path.contains('/Google Drive') || path.contains('/apps.docs')) return 'Google Drive';
    if (path.contains('/Chrome') || path.contains('/chrome')) return 'Browser';
    if (path.contains('/Firefox') || path.contains('/firefox')) return 'Browser';
    if (path.contains('/Opera') || path.contains('/opera')) return 'Browser';
    if (path.contains('/UCBrowser') || path.contains('/UCMobile')) return 'Browser';
    if (path.contains('/Samsung Internet') || path.contains('/sbrowser')) return 'Browser';
    if (path.contains('/Edge') || path.contains('/emmx')) return 'Browser';
    if (path.contains('/Brave') || path.contains('/brave')) return 'Browser';
    if (path.contains('/CamScanner') || path.contains('/camscanner')) return 'CamScanner';
    if (path.contains('/ShareIt') || path.contains('/shareit')) return 'ShareIt';
    if (path.contains('/Xender') || path.contains('/xender')) return 'Xender';
    if (path.contains('/ES File') || path.contains('/estrongs')) return 'File Manager';
    if (path.contains('/Pictures/Screenshots')) return 'Screenshots';
    if (path.contains('/Pictures')) return 'Pictures';
    if (path.contains('/Photos') || path.contains('/Photo')) return 'Photos';
    if (path.contains('/Camera')) return 'Camera';
    if (path.contains('/Screenshots') || path.contains('/Screenshot')) return 'Screenshots';
    if (path.contains('/Download') || path.contains('/download')) return 'Downloads';
    if (path.contains('/Movies') || path.contains('/Video') || path.contains('/Videos')) return 'Videos';
    if (path.contains('/Music') || path.contains('/Audio')) return 'Music';
    if (path.contains('/Recordings')) return 'Recordings';
    if (path.contains('/Bluetooth')) return 'Bluetooth';
    if (path.contains('/Alarms')) return 'Alarms';
    if (path.contains('/Ringtones')) return 'Ringtones';
    if (path.contains('/Notifications')) return 'Notifications';
    if (path.contains('/Trash') || path.contains('/trash') || path.contains('/.Trash')) return 'Trash';
    if (path.contains('/Recently Deleted') || path.contains('/.trashed')) return 'Trash';
    if (path.contains('/.thumbnails') || path.contains('/.THMBDATA')) return 'Hidden';
    if (path.contains('/cache') || path.contains('/Cache')) return 'Cache';
    if (path.contains('/Shared')) return 'Shared';
    if (path.contains('/Documents')) return 'Documents';
    if (path.contains('/Gallery')) return 'Gallery';
    if (path.contains('/KakaoTalk')) return 'KakaoTalk';
    if (path.contains('/QQ') || path.contains('/mobileqq')) return 'QQ';
    if (path.contains('/Weibo') || path.contains('/weibo')) return 'Weibo';
    return 'Other';
  }

  String _getFolderDisplayName(String path) {
    if (path.contains('/DCIM/Camera')) return 'Camera Roll';
    if (path.contains('/DCIM')) return 'DCIM';
    if (path.contains('/WhatsApp')) return 'WhatsApp';
    if (path.contains('/Telegram')) return 'Telegram';
    if (path.contains('/Instagram')) return 'Instagram';
    if (path.contains('/TikTok') || path.contains('/musically')) return 'TikTok';
    if (path.contains('/Snapchat')) return 'Snapchat';
    if (path.contains('/Viber')) return 'Viber';
    if (path.contains('/Messenger')) return 'Messenger';
    if (path.contains('/Signal')) return 'Signal';
    if (path.contains('/LINE')) return 'LINE';
    if (path.contains('/Discord')) return 'Discord';
    if (path.contains('/KakaoTalk')) return 'KakaoTalk';
    if (path.contains('/Facebook')) return 'Facebook';
    if (path.contains('/Twitter')) return 'Twitter';
    if (path.contains('/Pinterest')) return 'Pinterest';
    if (path.contains('/LinkedIn')) return 'LinkedIn';
    if (path.contains('/Reddit')) return 'Reddit';
    if (path.contains('/Google Photos') || path.contains('/google.android.apps.photos')) return 'Google Photos';
    if (path.contains('/WeChat') || path.contains('/tencent.mm')) return 'WeChat';
    if (path.contains('/VLC') || path.contains('/videolan')) return 'VLC';
    if (path.contains('/YouTube') || path.contains('/youtube')) return 'YouTube';
    if (path.contains('/Netflix')) return 'Netflix';
    if (path.contains('/Spotify')) return 'Spotify';
    if (path.contains('/CapCut') || path.contains('/nexstreaming')) return 'CapCut';
    if (path.contains('/InShot') || path.contains('/zideate')) return 'InShot';
    if (path.contains('/MX Player') || path.contains('/mxtech')) return 'MX Player';
    if (path.contains('/OneDrive') || path.contains('/skydrive')) return 'OneDrive';
    if (path.contains('/Dropbox')) return 'Dropbox';
    if (path.contains('/Google Drive')) return 'Google Drive';
    if (path.contains('/Chrome') || path.contains('/chrome')) return 'Chrome Cache';
    if (path.contains('/Firefox') || path.contains('/firefox')) return 'Firefox Cache';
    if (path.contains('/Opera') || path.contains('/opera')) return 'Opera Cache';
    if (path.contains('/UCBrowser') || path.contains('/UCMobile')) return 'UC Browser';
    if (path.contains('/sbrowser')) return 'Samsung Internet';
    if (path.contains('/Brave')) return 'Brave Cache';
    if (path.contains('/Edge') || path.contains('/emmx')) return 'Edge Cache';
    if (path.contains('/CamScanner')) return 'CamScanner';
    if (path.contains('/ShareIt') || path.contains('/shareit')) return 'ShareIt';
    if (path.contains('/Xender')) return 'Xender';
    if (path.contains('/estrongs')) return 'ES File Explorer';
    if (path.contains('/Pictures/Screenshots')) return 'Screenshots';
    if (path.contains('/Pictures')) return 'Pictures';
    if (path.contains('/Photos') || path.contains('/Photo')) return 'Photos';
    if (path.contains('/Camera')) return 'Camera';
    if (path.contains('/Screenshots') || path.contains('/Screenshot')) return 'Screenshots';
    if (path.contains('/Download') || path.contains('/Downloads')) return 'Downloads';
    if (path.contains('/Movies') || path.contains('/Video') || path.contains('/Videos')) return 'Videos';
    if (path.contains('/Music')) return 'Music';
    if (path.contains('/Audio')) return 'Audio';
    if (path.contains('/Recordings')) return 'Recordings';
    if (path.contains('/Alarms')) return 'Alarms';
    if (path.contains('/Ringtones')) return 'Ringtones';
    if (path.contains('/Notifications')) return 'Notifications';
    if (path.contains('/Bluetooth')) return 'Bluetooth';
    if (path.contains('/Shared')) return 'Shared';
    if (path.contains('/Documents')) return 'Documents';
    if (path.contains('/Gallery')) return 'Gallery';
    if (path.contains('/Trash') || path.contains('/trash') || path.contains('.Trash')) return 'Trash';
    if (path.contains('/Recently Deleted') || path.contains('.trashed')) return 'Recently Deleted';
    if (path.contains('/.thumbnails') || path.contains('.THMBDATA')) return 'Thumbnails';
    if (path.contains('/cache') || path.contains('/Cache')) return 'App Cache';
    if (path.contains('/Android/data')) return 'App Data';
    if (path.contains('/Android/media')) return 'Android Media';
    if (path.contains('/Android/obb')) return 'App OBB';
    if (path.contains('/KakaoTalk')) return 'KakaoTalk';
    if (path.contains('/QQ') || path.contains('/mobileqq')) return 'QQ';
    if (path.contains('/Weibo')) return 'Weibo';
    return path.split('/').last;
  }
}

// ============================================================================
// RecoveryService
// ============================================================================

class RecoveryService {
  static const _recoveryBaseFolder = 'MediaRescue';
  static const _legacyRecoveryBaseFolder = 'PhotoRecover';

  Future<String> getRecoveryBasePath() async {
    final basePath = '/storage/emulated/0/$_recoveryBaseFolder';
    final baseDir = Directory(basePath);
    if (!await baseDir.exists()) await baseDir.create(recursive: true);
    return basePath;
  }

  Future<List<String>> _getRecoveryRoots() async {
    final roots = <String>[];
    final current = '/storage/emulated/0/$_recoveryBaseFolder';
    roots.add(current);

    final legacy = '/storage/emulated/0/$_legacyRecoveryBaseFolder';
    if (legacy != current && await Directory(legacy).exists()) {
      roots.add(legacy);
    }
    return roots;
  }

  Future<String?> recoverFile(RecoverableFile file) async {
    try {
      final sourceFile = File(file.path);
      if (!await sourceFile.exists()) return null;
      final basePath = await getRecoveryBasePath();
      final subFolder = file.fileType == 'photo' ? 'Photos' : file.fileType == 'video' ? 'Videos' : 'Files';
      final path = '$basePath/$subFolder';
      await Directory(path).create(recursive: true);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final newPath = '$path/recovered_${timestamp}_${file.name}';
      await sourceFile.copy(newPath);

      // Also insert a DB recovery record so stats stay consistent
      try {
        final db = DatabaseHelper.instance;
        await db.insertRecoveryRecord(RecoveryRecord(
          id: 'rec_$timestamp',
          fileName: file.name,
          originalPath: file.path,
          recoveredPath: newPath,
          fileType: file.fileType,
          recoveredAt: DateTime.now(),
          fileSize: file.size,
        ));
      } catch (_) {
        // DB insert failure should not break the recovery itself
      }

      return newPath;
    } catch (e) { return null; }
  }

  Future<int> getRecoveryFolderSize() async {
    int totalSize = 0;
    final roots = await _getRecoveryRoots();
    for (final root in roots) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            try {
              totalSize += (await entity.stat()).size;
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
    return totalSize;
  }

  Future<int> getRecoveredFileCount() async {
    // Use DB count for consistency with RecoveredFilesScreen
    try {
      return await DatabaseHelper.instance.getRecoveryCount();
    } catch (_) {
      // Fallback to filesystem count if DB fails
      final basePath = await getRecoveryBasePath();
      final dir = Directory(basePath);
      if (!await dir.exists()) return 0;
      int count = 0;
      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) count++;
        }
      } catch (_) {}
      return count;
    }
  }

  Future<bool> deleteRecoveredFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> clearAllRecoveredFiles() async {
    try {
      final roots = await _getRecoveryRoots();
      bool changed = false;
      for (final root in roots) {
        final dir = Directory(root);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
          changed = true;
        }
      }
      final currentDir = Directory('/storage/emulated/0/$_recoveryBaseFolder');
      if (!await currentDir.exists()) {
        await currentDir.create(recursive: true);
      }
      return changed;
    } catch (_) {
      return false;
    }
  }
}
