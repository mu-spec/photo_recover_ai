import '../models/recoverable_file.dart';
import 'database_helper.dart';

class RecoveryRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<void> clearScanResults(String fileType) {
    return _db.clearScanResults(fileType);
  }

  Future<void> saveScanResults(List<RecoverableFile> files) {
    return _db.insertScanResults(files);
  }
}

