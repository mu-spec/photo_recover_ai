import '../models/recoverable_file.dart';

enum MediaCategory {
  existingMedia,
  cacheThumbnail,
  messengerMedia,
  recycleBin,
  cloudBackup,
  otherAccessible,
}

class MediaCategorizer {
  static MediaCategory categorize(RecoverableFile file) {
    final path = file.path.toLowerCase();

    if (path.contains('/dcim/') ||
        path.contains('/pictures/') ||
        path.contains('/download/')) {
      return MediaCategory.existingMedia;
    }

    if (path.contains('/cache/') ||
        path.contains('/.thumbnails') ||
        path.contains('/thumb')) {
      return MediaCategory.cacheThumbnail;
    }

    if (path.contains('whatsapp') ||
        path.contains('telegram') ||
        path.contains('messenger') ||
        path.contains('instagram') ||
        path.contains('snapchat')) {
      return MediaCategory.messengerMedia;
    }

    if (path.contains('/trash') ||
        path.contains('/recycle') ||
        path.contains('recently deleted') ||
        path.contains('/.trashed')) {
      return MediaCategory.recycleBin;
    }

    if (path.contains('googlephotos') ||
        path.contains('onedrive') ||
        path.contains('dropbox') ||
        path.contains('drive')) {
      return MediaCategory.cloudBackup;
    }

    return MediaCategory.otherAccessible;
  }

  static String label(MediaCategory category) {
    switch (category) {
      case MediaCategory.existingMedia:
        return 'Existing Media';
      case MediaCategory.cacheThumbnail:
        return 'Cache & Thumbnails';
      case MediaCategory.messengerMedia:
        return 'Messenger Media';
      case MediaCategory.recycleBin:
        return 'Recently Deleted';
      case MediaCategory.cloudBackup:
        return 'Cloud/Backup';
      case MediaCategory.otherAccessible:
        return 'Other Accessible';
    }
  }
}

