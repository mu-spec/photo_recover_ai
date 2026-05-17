import 'package:permission_handler/permission_handler.dart';

class PermissionManager {
  Future<bool> requestForScanType(String fileType) async {
    // Prefer scoped permissions first for Play Store safety.
    if (fileType == 'photo') {
      if (await _ensure(Permission.photos)) return true;
      if (await _ensure(Permission.storage)) return true;
      return false;
    }

    if (fileType == 'video') {
      if (await _ensure(Permission.videos)) return true;
      if (await _ensure(Permission.storage)) return true;
      return false;
    }

    // "file" scans usually need broader access for non-media docs.
    if (await _ensure(Permission.storage)) return true;
    if (await _ensure(Permission.manageExternalStorage)) return true;
    return false;
  }

  Future<bool> _ensure(Permission permission) async {
    final status = await permission.status;
    if (status.isGranted) return true;
    if (status.isDenied || status.isRestricted || status.isLimited) {
      return (await permission.request()).isGranted;
    }
    if (status.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }
    return false;
  }
}

