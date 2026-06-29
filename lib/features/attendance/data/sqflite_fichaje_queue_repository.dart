import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/gps_position.dart';
import '../domain/pending_fichaje.dart';
import '../domain/ports/fichaje_queue_repository.dart';

/// SQLite-backed implementation of [FichajeQueueRepository].
///
/// Schema (table: fichaje_queue) v4:
///   localId                  INTEGER PRIMARY KEY AUTOINCREMENT
///   operarioId               TEXT NOT NULL
///   operarioName             TEXT NOT NULL
///   date                     TEXT NOT NULL   (YYYY-MM-DD)
///   clientRef                TEXT NOT NULL UNIQUE
///   checkInCapturedAt        TEXT NOT NULL   (ISO-8601 UTC)
///   checkInLat               REAL NOT NULL
///   checkInLng               REAL NOT NULL
///   checkInAccuracy          REAL
///   checkInPhotoPath         TEXT            (entry/ingreso photo; renamed from signaturePngPath in v4)
///   checkOutPhotoPath        TEXT            (exit/salida photo; renamed from checkoutSignaturePngPath in v4)
///   checkOutClientRef        TEXT
///   checkOutCapturedAt       TEXT
///   checkOutLat              REAL
///   checkOutLng              REAL
///   checkOutAccuracy         REAL
///   serverAttendanceId       TEXT
///   status                   TEXT NOT NULL
///   failureReason            TEXT
///   createdAt                TEXT NOT NULL   (ISO-8601 UTC)
///   checkInVerification      TEXT            (audit label: BIOMETRIC|DEVICE_CREDENTIAL|NONE; added v3)
///   checkOutVerification     TEXT            (audit label: BIOMETRIC|DEVICE_CREDENTIAL|NONE; added v3)
///
/// Migration notes:
///   v1 → v2: ADD COLUMN checkoutSignaturePngPath TEXT
///   v2 → v3: ADD COLUMN checkInVerification TEXT; ADD COLUMN checkOutVerification TEXT
///   v3 → v4: RENAME COLUMN signaturePngPath → checkInPhotoPath
///             RENAME COLUMN checkoutSignaturePngPath → checkOutPhotoPath
///
///   SQLite RENAME COLUMN was introduced in SQLite 3.25.0 (2018-09-15).
///   Android bundles its own SQLite. The floor version that includes 3.25.0
///   is API 30+. Since this project's minSdk is API 21 (firebase_messaging
///   requirement), we use the add-column + copy + drop-old-column approach
///   (which is: create new column, UPDATE to copy values, leave old column
///   as orphan — SQLite has no DROP COLUMN before 3.35.0 / API 33+).
///   We accept the orphaned columns on pre-API-33 devices; they waste a
///   small amount of storage but do not affect correctness.
class SqfliteFichajeQueueRepository implements FichajeQueueRepository {
  Database? _db;

  static const _tableName = 'fichaje_queue';
  static const _dbName = 'futuragest_queue.db';
  static const _dbVersion = 4;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  Future<void> init() async {
    // Idempotent: skip if already initialised.
    if (_db != null) return;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, _dbName),
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            localId                  INTEGER PRIMARY KEY AUTOINCREMENT,
            operarioId               TEXT    NOT NULL,
            operarioName             TEXT    NOT NULL,
            date                     TEXT    NOT NULL,
            clientRef                TEXT    NOT NULL UNIQUE,
            checkInCapturedAt        TEXT    NOT NULL,
            checkInLat               REAL    NOT NULL,
            checkInLng               REAL    NOT NULL,
            checkInAccuracy          REAL,
            checkInPhotoPath         TEXT,
            checkOutPhotoPath        TEXT,
            checkOutClientRef        TEXT,
            checkOutCapturedAt       TEXT,
            checkOutLat              REAL,
            checkOutLng              REAL,
            checkOutAccuracy         REAL,
            serverAttendanceId       TEXT,
            status                   TEXT    NOT NULL,
            failureReason            TEXT,
            createdAt                TEXT    NOT NULL,
            checkInVerification      TEXT,
            checkOutVerification     TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN checkoutSignaturePngPath TEXT',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN checkInVerification TEXT',
          );
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN checkOutVerification TEXT',
          );
        }
        if (oldVersion < 4) {
          // Rename signaturePngPath → checkInPhotoPath.
          // Rename checkoutSignaturePngPath → checkOutPhotoPath.
          //
          // Strategy: add new columns, copy values, leave old columns as orphans.
          // (SQLite DROP COLUMN is only available from 3.35.0 / API 33+, but we
          // must support minSdk 21. Old orphaned columns are harmless.)
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN checkInPhotoPath TEXT',
          );
          await db.execute(
            'UPDATE $_tableName SET checkInPhotoPath = signaturePngPath '
            'WHERE signaturePngPath IS NOT NULL',
          );
          await db.execute(
            'ALTER TABLE $_tableName ADD COLUMN checkOutPhotoPath TEXT',
          );
          await db.execute(
            'UPDATE $_tableName SET checkOutPhotoPath = checkoutSignaturePngPath '
            'WHERE checkoutSignaturePngPath IS NOT NULL',
          );
        }
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
    String? checkInVerification,
  }) async {
    // Fix 7: local duplicate guard — prevent a second open record for the same
    // operario on the same date. The UNIQUE constraint on clientRef prevents
    // exact-duplicate rows but does NOT prevent two distinct clientRefs for the
    // same operario+date pair. Use findOpenByOperarioAndDate as a pre-insert
    // guard to catch this case.
    final existing = await findOpenByOperarioAndDate(operarioId, date);
    if (existing != null) {
      throw DuplicateLocalFichajeException(
        operarioId: operarioId,
        date: date,
        existingLocalId: existing.localId,
      );
    }

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
      'checkInVerification': ?checkInVerification,
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
      checkInVerification: checkInVerification,
    );
  }

  @override
  Future<void> saveCheckInPhoto({
    required int localId,
    required List<int> photoBytes,
  }) async {
    // Write bytes to app documents directory — entry photo file.
    final docsDir = await getApplicationDocumentsDirectory();
    final photoDir = Directory(p.join(docsDir.path, 'photos'));
    if (!photoDir.existsSync()) {
      await photoDir.create(recursive: true);
    }
    final file = File(p.join(photoDir.path, 'photo_$localId.jpg'));
    await file.writeAsBytes(photoBytes, flush: true);

    await _database.update(
      _tableName,
      {'checkInPhotoPath': file.path},
      where: 'localId = ?',
      whereArgs: [localId],
    );
  }

  @override
  Future<void> saveSalida({
    required int localId,
    required List<int> checkOutPhotoBytes,
    required String checkOutClientRef,
    required DateTime checkOutCapturedAt,
    required GpsPosition checkOutGps,
    String? checkOutVerification,
  }) async {
    // Write exit photo to disk.
    final docsDir = await getApplicationDocumentsDirectory();
    final photoDir = Directory(p.join(docsDir.path, 'photos'));
    if (!photoDir.existsSync()) {
      await photoDir.create(recursive: true);
    }
    final file = File(p.join(photoDir.path, 'photo_${localId}_out.jpg'));
    await file.writeAsBytes(checkOutPhotoBytes, flush: true);

    await _database.update(
      _tableName,
      {
        'checkOutPhotoPath': file.path,
        'checkOutClientRef': checkOutClientRef,
        'checkOutCapturedAt': checkOutCapturedAt.toUtc().toIso8601String(),
        'checkOutLat': checkOutGps.latitude,
        'checkOutLng': checkOutGps.longitude,
        'checkOutAccuracy': checkOutGps.accuracy,
        'checkOutVerification': ?checkOutVerification,
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
        'status': FichajeQueueStatus.checkedIn.name,
      },
      where: 'localId = ?',
      whereArgs: [localId],
    );
  }

  @override
  Future<void> markIngresoComplete({required int localId}) async {
    await _database.update(
      _tableName,
      {'status': FichajeQueueStatus.ingresoComplete.name},
      where: 'localId = ?',
      whereArgs: [localId],
    );
  }

  @override
  Future<void> markSalidaSigned({required int localId}) async {
    await _database.update(
      _tableName,
      {'status': FichajeQueueStatus.salidaSigned.name},
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

  // ── Wipe ──────────────────────────────────────────────────────────────────

  @override
  Future<void> wipeAll() async {
    // 1. Collect all photo file paths before deleting rows.
    final rows = await _database.query(
      _tableName,
      columns: ['checkInPhotoPath', 'checkOutPhotoPath'],
    );

    // 2. Delete all queue rows.
    await _database.delete(_tableName);

    // 3. Delete the individual photo files referenced by the rows.
    for (final row in rows) {
      for (final col in ['checkInPhotoPath', 'checkOutPhotoPath']) {
        final path = row[col] as String?;
        if (path != null) {
          final f = File(path);
          if (f.existsSync()) {
            await f.delete();
          }
        }
      }
    }

    // 4. Wipe the photos directory (handles orphans and v4+ files).
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final photoDir = Directory(p.join(docsDir.path, 'photos'));
      if (photoDir.existsSync()) {
        await photoDir.delete(recursive: true);
      }
    } catch (_) {
      // Best-effort: directory may not exist yet.
    }

    // 5. Also wipe the legacy signatures directory for v3 installs upgrading
    //    to v4 — orphaned signature files from the old schema.
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final sigDir = Directory(p.join(docsDir.path, 'signatures'));
      if (sigDir.existsSync()) {
        await sigDir.delete(recursive: true);
      }
    } catch (_) {
      // Best-effort: may not exist on fresh installs.
    }
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

  @override
  Future<PendingFichaje?> findOpenByOperarioAndDate(
    String operarioId,
    String date,
  ) async {
    final rows = await _database.query(
      _tableName,
      where:
          'operarioId = ? AND date = ? AND status != ? AND status != ?',
      whereArgs: [
        operarioId,
        date,
        FichajeQueueStatus.completed.name,
        FichajeQueueStatus.failed.name,
      ],
      orderBy: 'localId DESC',
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
      checkInPhotoPath: row['checkInPhotoPath'] as String?,
      checkOutPhotoPath: row['checkOutPhotoPath'] as String?,
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
      checkInVerification: row['checkInVerification'] as String?,
      checkOutVerification: row['checkOutVerification'] as String?,
    );
  }
}
