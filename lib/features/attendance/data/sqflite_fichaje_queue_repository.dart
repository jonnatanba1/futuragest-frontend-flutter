import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/gps_position.dart';
import '../domain/pending_fichaje.dart';
import '../domain/ports/fichaje_queue_repository.dart';

/// SQLite-backed implementation of [FichajeQueueRepository].
///
/// Schema (table: fichaje_queue):
///   localId              INTEGER PRIMARY KEY AUTOINCREMENT
///   operarioId           TEXT NOT NULL
///   operarioName         TEXT NOT NULL
///   date                 TEXT NOT NULL   (YYYY-MM-DD)
///   clientRef            TEXT NOT NULL UNIQUE
///   checkInCapturedAt    TEXT NOT NULL   (ISO-8601 UTC)
///   checkInLat           REAL NOT NULL
///   checkInLng           REAL NOT NULL
///   checkInAccuracy      REAL
///   signaturePngPath     TEXT
///   checkOutClientRef    TEXT
///   checkOutCapturedAt   TEXT
///   checkOutLat          REAL
///   checkOutLng          REAL
///   checkOutAccuracy     REAL
///   serverAttendanceId   TEXT
///   status               TEXT NOT NULL
///   failureReason        TEXT
///   createdAt            TEXT NOT NULL   (ISO-8601 UTC)
class SqfliteFichajeQueueRepository implements FichajeQueueRepository {
  Database? _db;

  static const _tableName = 'fichaje_queue';
  static const _dbName = 'futuragest_queue.db';
  static const _dbVersion = 1;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, _dbName),
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            localId            INTEGER PRIMARY KEY AUTOINCREMENT,
            operarioId         TEXT    NOT NULL,
            operarioName       TEXT    NOT NULL,
            date               TEXT    NOT NULL,
            clientRef          TEXT    NOT NULL UNIQUE,
            checkInCapturedAt  TEXT    NOT NULL,
            checkInLat         REAL    NOT NULL,
            checkInLng         REAL    NOT NULL,
            checkInAccuracy    REAL,
            signaturePngPath   TEXT,
            checkOutClientRef  TEXT,
            checkOutCapturedAt TEXT,
            checkOutLat        REAL,
            checkOutLng        REAL,
            checkOutAccuracy   REAL,
            serverAttendanceId TEXT,
            status             TEXT    NOT NULL,
            failureReason      TEXT,
            createdAt          TEXT    NOT NULL
          )
        ''');
      },
    );
  }

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError(
        'FichajeQueueRepository not initialised. Call init() first.',
      );
    }
    return db;
  }

  // ── Write ops ──────────────────────────────────────────────────────────────

  @override
  Future<PendingFichaje> enqueue({
    required String operarioId,
    required String operarioName,
    required String date,
    required String clientRef,
    required DateTime checkInCapturedAt,
    required GpsPosition checkInGps,
  }) async {
    final now = DateTime.now().toUtc();
    final row = {
      'operarioId': operarioId,
      'operarioName': operarioName,
      'date': date,
      'clientRef': clientRef,
      'checkInCapturedAt': checkInCapturedAt.toUtc().toIso8601String(),
      'checkInLat': checkInGps.latitude,
      'checkInLng': checkInGps.longitude,
      'checkInAccuracy': checkInGps.accuracy,
      'status': FichajeQueueStatus.pendingCheckIn.name,
      'createdAt': now.toIso8601String(),
    };

    final id = await _database.insert(_tableName, row);

    return PendingFichaje(
      localId: id,
      operarioId: operarioId,
      operarioName: operarioName,
      date: date,
      clientRef: clientRef,
      checkInCapturedAt: checkInCapturedAt,
      checkInGps: checkInGps,
      status: FichajeQueueStatus.pendingCheckIn,
      createdAt: now,
    );
  }

  @override
  Future<void> saveSignature({
    required int localId,
    required List<int> pngBytes,
  }) async {
    // Write bytes to app documents directory.
    final docsDir = await getApplicationDocumentsDirectory();
    final sigDir = Directory(p.join(docsDir.path, 'signatures'));
    if (!sigDir.existsSync()) {
      await sigDir.create(recursive: true);
    }
    final file = File(p.join(sigDir.path, 'sig_$localId.png'));
    await file.writeAsBytes(pngBytes, flush: true);

    await _database.update(
      _tableName,
      {'signaturePngPath': file.path},
      where: 'localId = ?',
      whereArgs: [localId],
    );
  }

  @override
  Future<void> saveCheckOut({
    required int localId,
    required String checkOutClientRef,
    required DateTime checkOutCapturedAt,
    required GpsPosition checkOutGps,
  }) async {
    await _database.update(
      _tableName,
      {
        'checkOutClientRef': checkOutClientRef,
        'checkOutCapturedAt': checkOutCapturedAt.toUtc().toIso8601String(),
        'checkOutLat': checkOutGps.latitude,
        'checkOutLng': checkOutGps.longitude,
        'checkOutAccuracy': checkOutGps.accuracy,
      },
      where: 'localId = ?',
      whereArgs: [localId],
    );
  }

  @override
  Future<void> markCheckedIn({
    required int localId,
    required String serverAttendanceId,
  }) async {
    await _database.update(
      _tableName,
      {
        'serverAttendanceId': serverAttendanceId,
        'status': FichajeQueueStatus.checkedInPendingSignature.name,
      },
      where: 'localId = ?',
      whereArgs: [localId],
    );
  }

  @override
  Future<void> markSignatureUploaded({required int localId}) async {
    await _database.update(
      _tableName,
      {'status': FichajeQueueStatus.signedPendingCheckOut.name},
      where: 'localId = ?',
      whereArgs: [localId],
    );
  }

  @override
  Future<void> markCompleted({required int localId}) async {
    await _database.update(
      _tableName,
      {'status': FichajeQueueStatus.completed.name},
      where: 'localId = ?',
      whereArgs: [localId],
    );
  }

  @override
  Future<void> markFailed({
    required int localId,
    required String reason,
  }) async {
    await _database.update(
      _tableName,
      {
        'status': FichajeQueueStatus.failed.name,
        'failureReason': reason,
      },
      where: 'localId = ?',
      whereArgs: [localId],
    );
  }

  // ── Read ops ───────────────────────────────────────────────────────────────

  @override
  Future<List<PendingFichaje>> listPending() async {
    final rows = await _database.query(
      _tableName,
      where: 'status != ? AND status != ?',
      whereArgs: [
        FichajeQueueStatus.completed.name,
        FichajeQueueStatus.failed.name,
      ],
      orderBy: 'localId ASC',
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<List<PendingFichaje>> listAll() async {
    final rows = await _database.query(_tableName, orderBy: 'localId ASC');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<PendingFichaje?> findByClientRef(String clientRef) async {
    final rows = await _database.query(
      _tableName,
      where: 'clientRef = ?',
      whereArgs: [clientRef],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  // ── Mapping ────────────────────────────────────────────────────────────────

  PendingFichaje _fromRow(Map<String, dynamic> row) {
    GpsPosition? checkOutGps;
    if (row['checkOutLat'] != null && row['checkOutLng'] != null) {
      checkOutGps = GpsPosition(
        latitude: row['checkOutLat'] as double,
        longitude: row['checkOutLng'] as double,
        accuracy: (row['checkOutAccuracy'] as double?) ?? 0,
      );
    }

    final statusName = row['status'] as String;
    final status = FichajeQueueStatus.values.firstWhere(
      (s) => s.name == statusName,
      orElse: () => FichajeQueueStatus.pendingCheckIn,
    );

    return PendingFichaje(
      localId: row['localId'] as int,
      operarioId: row['operarioId'] as String,
      operarioName: row['operarioName'] as String,
      date: row['date'] as String,
      clientRef: row['clientRef'] as String,
      checkInCapturedAt:
          DateTime.parse(row['checkInCapturedAt'] as String).toUtc(),
      checkInGps: GpsPosition(
        latitude: row['checkInLat'] as double,
        longitude: row['checkInLng'] as double,
        accuracy: (row['checkInAccuracy'] as double?) ?? 0,
      ),
      signaturePngPath: row['signaturePngPath'] as String?,
      checkOutClientRef: row['checkOutClientRef'] as String?,
      checkOutCapturedAt: row['checkOutCapturedAt'] != null
          ? DateTime.parse(row['checkOutCapturedAt'] as String).toUtc()
          : null,
      checkOutGps: checkOutGps,
      serverAttendanceId: row['serverAttendanceId'] as String?,
      status: status,
      failureReason: row['failureReason'] as String?,
      createdAt: row['createdAt'] != null
          ? DateTime.parse(row['createdAt'] as String).toUtc()
          : null,
    );
  }
}
