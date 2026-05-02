import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/recoverable_file.dart';

class DatabaseHelper {
  static const _databaseName = 'photo_recover_ai.db';
  static const _databaseVersion = 3;

  static const tableScanResults = 'scan_results';
  static const tableRecoveryRecords = 'recovery_records';
  static const tableScanStates = 'scan_states';

  static Database? _database;

  DatabaseHelper._privateConstructor();

  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableScanResults (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        path TEXT NOT NULL,
        extension TEXT NOT NULL,
        size INTEGER NOT NULL,
        lastModified INTEGER NOT NULL,
        fileType TEXT NOT NULL,
        source TEXT NOT NULL,
        isRecovered INTEGER DEFAULT 0,
        qualityTag TEXT,
        cameraInfo TEXT,
        resolution TEXT,
        gpsLocation TEXT,
        dateTaken INTEGER,
        orientation INTEGER,
        software TEXT,
        iso INTEGER,
        corruptionLevel REAL,
        isNewFile INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableRecoveryRecords (
        id TEXT PRIMARY KEY,
        fileName TEXT NOT NULL,
        originalPath TEXT NOT NULL,
        recoveredPath TEXT NOT NULL,
        fileType TEXT NOT NULL,
        recoveredAt INTEGER NOT NULL,
        fileSize INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableScanStates (
        id TEXT PRIMARY KEY,
        file_type TEXT NOT NULL,
        processed_dirs INTEGER DEFAULT 0,
        total_dirs INTEGER DEFAULT 0,
        files_found INTEGER DEFAULT 0,
        scanned_paths TEXT DEFAULT '',
        current_index INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add qualityTag column to scan_results
      await db.execute('ALTER TABLE $tableScanResults ADD COLUMN qualityTag TEXT');
      // Create scan_states table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableScanStates (
          id TEXT PRIMARY KEY,
          file_type TEXT NOT NULL,
          processed_dirs INTEGER DEFAULT 0,
          total_dirs INTEGER DEFAULT 0,
          files_found INTEGER DEFAULT 0,
          scanned_paths TEXT DEFAULT '',
          current_index INTEGER DEFAULT 0,
          created_at INTEGER NOT NULL
        )
      ''');
    }

    if (oldVersion < 3) {
      await _addColumnIfNotExists(db, tableScanResults, 'cameraInfo', 'TEXT');
      await _addColumnIfNotExists(db, tableScanResults, 'resolution', 'TEXT');
      await _addColumnIfNotExists(db, tableScanResults, 'gpsLocation', 'TEXT');
      await _addColumnIfNotExists(db, tableScanResults, 'dateTaken', 'INTEGER');
      await _addColumnIfNotExists(db, tableScanResults, 'orientation', 'INTEGER');
      await _addColumnIfNotExists(db, tableScanResults, 'software', 'TEXT');
      await _addColumnIfNotExists(db, tableScanResults, 'iso', 'INTEGER');
      await _addColumnIfNotExists(db, tableScanResults, 'corruptionLevel', 'REAL');
      await _addColumnIfNotExists(
        db,
        tableScanResults,
        'isNewFile',
        'INTEGER DEFAULT 0',
      );
    }
  }

  Future<void> _addColumnIfNotExists(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute(
        'ALTER TABLE $table ADD COLUMN $column $definition',
      );
    }
  }

  // ---- Scan Results Operations ----

  Future<void> insertScanResults(List<RecoverableFile> files) async {
    final db = await database;
    final batch = db.batch();
    for (final file in files) {
      batch.insert(
        tableScanResults,
        file.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<RecoverableFile>> getScanResults({
    required String fileType,
    String? source,
  }) async {
    final db = await database;
    final List<Map<String, dynamic>> maps;

    if (source != null) {
      maps = await db.query(
        tableScanResults,
        where: 'fileType = ? AND source = ?',
        whereArgs: [fileType, source],
        orderBy: 'lastModified DESC',
      );
    } else {
      maps = await db.query(
        tableScanResults,
        where: 'fileType = ?',
        whereArgs: [fileType],
        orderBy: 'lastModified DESC',
      );
    }

    return List.generate(maps.length, (i) => RecoverableFile.fromMap(maps[i]));
  }

  Future<void> clearScanResults(String fileType) async {
    final db = await database;
    await db.delete(tableScanResults, where: 'fileType = ?', whereArgs: [fileType]);
  }

  Future<void> clearAllScanResults() async {
    final db = await database;
    await db.delete(tableScanResults);
  }

  // ---- Recovery Records Operations ----

  Future<void> insertRecoveryRecord(RecoveryRecord record) async {
    final db = await database;
    await db.insert(
      tableRecoveryRecords,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<RecoveryRecord>> getRecoveryRecords({String? fileType}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps;

    if (fileType != null) {
      maps = await db.query(
        tableRecoveryRecords,
        where: 'fileType = ?',
        whereArgs: [fileType],
        orderBy: 'recoveredAt DESC',
      );
    } else {
      maps = await db.query(
        tableRecoveryRecords,
        orderBy: 'recoveredAt DESC',
      );
    }

    return List.generate(maps.length, (i) => RecoveryRecord.fromMap(maps[i]));
  }

  Future<int> getRecoveryCount({String? fileType}) async {
    final db = await database;
    if (fileType != null) {
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $tableRecoveryRecords WHERE fileType = ?',
        [fileType],
      );
      return Sqflite.firstIntValue(result) ?? 0;
    }
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $tableRecoveryRecords',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> deleteRecoveryRecord(String id) async {
    final db = await database;
    await db.delete(tableRecoveryRecords, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearRecoveryRecords() async {
    final db = await database;
    await db.delete(tableRecoveryRecords);
  }

  Future<Map<String, int>> getRecoveryStats() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT fileType, COUNT(*) as count FROM $tableRecoveryRecords GROUP BY fileType',
    );
    final Map<String, int> stats = {};
    for (final row in result) {
      stats[row['fileType'] as String] = row['count'] as int;
    }
    return stats;
  }

  // ---- Scan States Operations ----

  /// Save or update a scan state record
  Future<void> saveScanState({
    required String fileType,
    required int processedDirs,
    required int totalDirs,
    required int filesFound,
    required String scannedPaths,
    required int currentIndex,
  }) async {
    final db = await database;
    final id = 'scan_state_$fileType';
    await db.insert(
      tableScanStates,
      {
        'id': id,
        'file_type': fileType,
        'processed_dirs': processedDirs,
        'total_dirs': totalDirs,
        'files_found': filesFound,
        'scanned_paths': scannedPaths,
        'current_index': currentIndex,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Load a scan state by file type
  Future<Map<String, dynamic>?> loadScanState(String fileType) async {
    final db = await database;
    final id = 'scan_state_$fileType';
    final maps = await db.query(
      tableScanStates,
      where: 'id = ? AND file_type = ?',
      whereArgs: [id, fileType],
    );
    if (maps.isEmpty) return null;
    return maps.first;
  }

  /// Clear a scan state by file type
  Future<void> clearScanState(String fileType) async {
    final db = await database;
    final id = 'scan_state_$fileType';
    await db.delete(tableScanStates, where: 'id = ?', whereArgs: [id]);
  }
}
