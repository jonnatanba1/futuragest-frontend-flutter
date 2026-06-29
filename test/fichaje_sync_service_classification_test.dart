// Tests for sync service error classification — Fixes 3/4/5/10/11/12.
//
// Uses fake implementations of FichajeQueueRepository and AttendanceRepository
// to exercise the sync service state machine without any real I/O.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:futuragest_mobile/features/attendance/application/fichaje_sync_service.dart';
import 'package:futuragest_mobile/features/attendance/domain/attendance_record.dart';
import 'package:futuragest_mobile/features/attendance/domain/attendance_repository.dart';
import 'package:futuragest_mobile/features/attendance/domain/gps_position.dart';
import 'package:futuragest_mobile/features/attendance/domain/operario.dart';
import 'package:futuragest_mobile/features/attendance/domain/pending_fichaje.dart';
import 'package:futuragest_mobile/features/attendance/domain/ports/fichaje_queue_repository.dart';
import 'package:futuragest_mobile/core/connectivity/connectivity_service.dart';

// ── Fakes ──────────────────────────────────────────────────────────────────

/// Fake connectivity that avoids platform channel initialization.
/// ConnectivityService is a concrete class; we subclass and override the
/// two methods used by FichajeSyncService.
class _FakeConnectivity extends ConnectivityService {
  // Call the real constructor — connectivity_plus initializes lazily, so
  // calling Connectivity() in tests is safe as long as we override all
  // methods that would actually invoke the platform channel.

  @override
  Stream<bool> get isOnlineStream => const Stream.empty();

  @override
  Future<bool> isOnline() async => true; // always online in tests
}

class _FakeQueue implements FichajeQueueRepository {
  final List<PendingFichaje> _items;
  final Map<int, String?> _failures = {};
  final Map<int, FichajeQueueStatus> _statuses = {};

  _FakeQueue(this._items);

  @override
  Future<void> init() async {}

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
    throw UnimplementedError();
  }

  @override
  Future<void> saveCheckInPhoto({
    required int localId,
    required List<int> photoBytes,
  }) async {}

  @override
  Future<void> saveSalida({
    required int localId,
    required List<int> checkOutPhotoBytes,
    required String checkOutClientRef,
    required DateTime checkOutCapturedAt,
    required GpsPosition checkOutGps,
    String? checkOutVerification,
  }) async {}

  @override
  Future<void> markCheckedIn({
    required int localId,
    required String serverAttendanceId,
  }) async {
    _statuses[localId] = FichajeQueueStatus.checkedIn;
  }

  @override
  Future<void> markIngresoComplete({required int localId}) async {
    _statuses[localId] = FichajeQueueStatus.ingresoComplete;
  }

  @override
  Future<void> markSalidaSigned({required int localId}) async {
    _statuses[localId] = FichajeQueueStatus.salidaSigned;
  }

  @override
  Future<void> markCompleted({required int localId}) async {
    _statuses[localId] = FichajeQueueStatus.completed;
  }

  @override
  Future<void> markFailed({
    required int localId,
    required String reason,
  }) async {
    _statuses[localId] = FichajeQueueStatus.failed;
    _failures[localId] = reason;
  }

  @override
  Future<List<PendingFichaje>> listPending() async {
    return _items.where((f) {
      final s = _statuses[f.localId] ?? f.status;
      return s != FichajeQueueStatus.completed &&
          s != FichajeQueueStatus.failed;
    }).toList();
  }

  @override
  Future<List<PendingFichaje>> listAll() async => _items;

  @override
  Future<PendingFichaje?> findByClientRef(String clientRef) async => null;

  @override
  Future<PendingFichaje?> findOpenByOperarioAndDate(
    String operarioId,
    String date,
  ) async =>
      null;

  @override
  Future<void> wipeAll() async {
    _items.clear();
    _failures.clear();
    _statuses.clear();
  }

  FichajeQueueStatus? statusOf(int localId) => _statuses[localId];
  String? failureOf(int localId) => _failures[localId];
}

class _FakeAttendanceRepo implements AttendanceRepository {
  final Future<AttendanceRecord> Function()? onCheckIn;
  final Future<AttendanceRecord?> Function()? onRecover;
  final Future<AttendanceRecord> Function()? onCheckOut;

  _FakeAttendanceRepo({this.onCheckIn, this.onRecover, this.onCheckOut});

  @override
  Future<AttendanceRecord> checkIn({
    required String operarioId,
    required String date,
    required DateTime capturedAt,
    required GpsPosition position,
    required String clientRef,
    String? verification,
  }) async {
    if (onCheckIn != null) return onCheckIn!();
    throw UnimplementedError();
  }

  @override
  Future<void> uploadPhoto({
    required String attendanceId,
    required List<int> photoBytes,
    required String phase,
  }) async {}

  @override
  Future<AttendanceRecord> checkOut({
    required String attendanceId,
    required DateTime capturedAt,
    required GpsPosition position,
    required String checkOutClientRef,
    String? verification,
  }) async {
    if (onCheckOut != null) return onCheckOut!();
    throw UnimplementedError();
  }

  @override
  Future<AttendanceRecord?> recoverByClientRef(String clientRef) async {
    if (onRecover != null) return onRecover!();
    return null;
  }

  @override
  Future<List<Operario>> getOperarios() async => [];

  @override
  Future<Map<String, ({String id, bool completed})>>
      todayAttendanceByOperario(String date) async => {};
}

// ── Helpers ────────────────────────────────────────────────────────────────

PendingFichaje _pendingCheckIn({int localId = 1}) {
  return PendingFichaje(
    localId: localId,
    operarioId: 'op-1',
    operarioName: 'Juan Pérez',
    date: '2026-06-10',
    clientRef: 'ref-abc',
    checkInCapturedAt: DateTime.utc(2026, 6, 10, 8),
    checkInGps: const GpsPosition(latitude: 4.6, longitude: -74.1, accuracy: 10),
    status: FichajeQueueStatus.pendingCheckIn,
    createdAt: DateTime.utc(2026, 6, 10, 8),
  );
}

PendingFichaje _salidaSigned({int localId = 2}) {
  return PendingFichaje(
    localId: localId,
    operarioId: 'op-2',
    operarioName: 'Ana García',
    date: '2026-06-10',
    clientRef: 'ref-xyz',
    checkInCapturedAt: DateTime.utc(2026, 6, 10, 8),
    checkInGps: const GpsPosition(latitude: 4.6, longitude: -74.1, accuracy: 10),
    status: FichajeQueueStatus.salidaSigned,
    serverAttendanceId: 'srv-99',
    checkOutClientRef: 'co-ref',
    checkOutCapturedAt: DateTime.utc(2026, 6, 10, 17),
    checkOutGps: const GpsPosition(latitude: 4.6, longitude: -74.1, accuracy: 10),
    createdAt: DateTime.utc(2026, 6, 10, 8),
  );
}

AttendanceRecord _record({String id = 'srv-1'}) {
  return AttendanceRecord(
    id: id,
    operarioId: 'op-1',
    date: '2026-06-10',
    clientRef: 'ref-abc',
    checkInCapturedAt: DateTime.utc(2026, 6, 10, 8),
    checkInLat: 4.6,
    checkInLng: -74.1,
  );
}

FichajeSyncService _service({
  required _FakeQueue queue,
  required _FakeAttendanceRepo remote,
}) {
  return FichajeSyncService(
    queue: queue,
    remote: remote,
    connectivity: _FakeConnectivity(),
  );
}

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('FichajeSyncService — checkIn error classification (Fix 3/4/12)', () {
    test('409 → triggers recovery (not markFailed)', () async {
      final item = _pendingCheckIn();
      final queue = _FakeQueue([item]);
      final remote = _FakeAttendanceRepo(
        // checkIn throws 409
        onCheckIn: () async => throw const AttendanceException(
          'Duplicate',
          statusCode: 409,
        ),
        // Recovery returns the existing record
        onRecover: () async => _record(),
      );
      final svc = _service(queue: queue, remote: remote);
      await svc.init();
      await svc.triggerSync();

      // Item should be checkedIn (recovered), NOT failed
      expect(queue.statusOf(item.localId), FichajeQueueStatus.checkedIn);
      expect(queue.failureOf(item.localId), isNull);
    });

    test('5xx → TRANSIENT — item stays pending', () async {
      final item = _pendingCheckIn();
      final queue = _FakeQueue([item]);
      final remote = _FakeAttendanceRepo(
        onCheckIn: () async => throw const AttendanceException(
          'Internal server error',
          statusCode: 503,
        ),
      );
      final svc = _service(queue: queue, remote: remote);
      await svc.init();
      await svc.triggerSync();

      // Should NOT be marked failed — stays pending for retry
      expect(queue.statusOf(item.localId), isNull); // no status written
    });

    test('null statusCode (network error) → TRANSIENT — item stays pending',
        () async {
      final item = _pendingCheckIn();
      final queue = _FakeQueue([item]);
      final remote = _FakeAttendanceRepo(
        onCheckIn: () async =>
            throw const AttendanceException('Connection refused'),
      );
      final svc = _service(queue: queue, remote: remote);
      await svc.init();
      await svc.triggerSync();

      expect(queue.statusOf(item.localId), isNull);
    });

    test('422 → terminal markFailed with real backend message', () async {
      final item = _pendingCheckIn();
      final queue = _FakeQueue([item]);
      const realMsg =
          'La fecha proporcionada "2026-06-10" no coincide con la fecha '
          'derivada del servidor para Bogotá "2026-06-11".';
      final remote = _FakeAttendanceRepo(
        onCheckIn: () async =>
            throw const AttendanceException(realMsg, statusCode: 422),
      );
      final svc = _service(queue: queue, remote: remote);
      await svc.init();
      await svc.triggerSync();

      expect(queue.statusOf(item.localId), FichajeQueueStatus.failed);
      expect(queue.failureOf(item.localId), realMsg);
    });

    test('400 → terminal markFailed', () async {
      final item = _pendingCheckIn();
      final queue = _FakeQueue([item]);
      final remote = _FakeAttendanceRepo(
        onCheckIn: () async => throw const AttendanceException(
          'GPS inválido',
          statusCode: 400,
        ),
      );
      final svc = _service(queue: queue, remote: remote);
      await svc.init();
      await svc.triggerSync();

      expect(queue.statusOf(item.localId), FichajeQueueStatus.failed);
    });
  });

  group('FichajeSyncService — checkOut error classification (Fix 3/4)', () {
    test('5xx checkOut → TRANSIENT — item stays salidaSigned', () async {
      final item = _salidaSigned();
      final queue = _FakeQueue([item]);
      final remote = _FakeAttendanceRepo(
        onCheckOut: () async => throw const AttendanceException(
          'Gateway timeout',
          statusCode: 504,
        ),
      );
      final svc = _service(queue: queue, remote: remote);
      await svc.init();
      await svc.triggerSync();

      // Should NOT be marked failed
      expect(queue.statusOf(item.localId), isNull);
    });

    test('null statusCode checkOut → TRANSIENT', () async {
      final item = _salidaSigned();
      final queue = _FakeQueue([item]);
      final remote = _FakeAttendanceRepo(
        onCheckOut: () async =>
            throw const AttendanceException('Network error'),
      );
      final svc = _service(queue: queue, remote: remote);
      await svc.init();
      await svc.triggerSync();

      expect(queue.statusOf(item.localId), isNull);
    });

    test('422 checkOut → markFailed with REAL message (not hardcoded)', () async {
      final item = _salidaSigned();
      final queue = _FakeQueue([item]);
      const realMsg =
          'El registro de asistencia "srv-99" no puede ser cerrado: '
          'se debe subir la foto antes del check-out.';
      final remote = _FakeAttendanceRepo(
        onCheckOut: () async =>
            throw const AttendanceException(realMsg, statusCode: 422),
      );
      final svc = _service(queue: queue, remote: remote);
      await svc.init();
      await svc.triggerSync();

      expect(queue.statusOf(item.localId), FichajeQueueStatus.failed);
      expect(queue.failureOf(item.localId), realMsg);
    });

    test('422 InvalidShiftDurationError → markFailed with duration message',
        () async {
      final item = _salidaSigned();
      final queue = _FakeQueue([item]);
      const realMsg =
          'Duración del turno inválida: la salida es anterior a la entrada.';
      final remote = _FakeAttendanceRepo(
        onCheckOut: () async =>
            throw const AttendanceException(realMsg, statusCode: 422),
      );
      final svc = _service(queue: queue, remote: remote);
      await svc.init();
      await svc.triggerSync();

      expect(queue.statusOf(item.localId), FichajeQueueStatus.failed);
      expect(queue.failureOf(item.localId), realMsg);
    });
  });

  group('FichajeSyncService — _recoverCheckIn (Fix 5)', () {
    test('409 + null recovery → item stays PENDING (not failed)', () async {
      final item = _pendingCheckIn();
      final queue = _FakeQueue([item]);
      final remote = _FakeAttendanceRepo(
        onCheckIn: () async =>
            throw const AttendanceException('Duplicate', statusCode: 409),
        // Recovery returns null — record not found
        onRecover: () async => null,
      );
      final svc = _service(queue: queue, remote: remote);
      await svc.init();
      await svc.triggerSync();

      // Fix 5: must NOT be marked failed when recovery returns null
      expect(queue.statusOf(item.localId), isNull);
    });

    test('409 + AttendanceException from recovery → item stays PENDING', () async {
      final item = _pendingCheckIn();
      final queue = _FakeQueue([item]);
      final remote = _FakeAttendanceRepo(
        onCheckIn: () async =>
            throw const AttendanceException('Duplicate', statusCode: 409),
        // Recovery throws 5xx (Fix 10)
        onRecover: () async =>
            throw const AttendanceException('Server error', statusCode: 502),
      );
      final svc = _service(queue: queue, remote: remote);
      await svc.init();
      await svc.triggerSync();

      expect(queue.statusOf(item.localId), isNull);
    });

    test('409 + successful recovery → item moves to checkedIn', () async {
      final item = _pendingCheckIn();
      final queue = _FakeQueue([item]);
      final remote = _FakeAttendanceRepo(
        onCheckIn: () async =>
            throw const AttendanceException('Duplicate', statusCode: 409),
        onRecover: () async => _record(id: 'recovered-srv-id'),
      );
      final svc = _service(queue: queue, remote: remote);
      await svc.init();
      await svc.triggerSync();

      expect(queue.statusOf(item.localId), FichajeQueueStatus.checkedIn);
    });
  });

  group('FichajeSyncService — queue wipeAll (Fix 1)', () {
    test('wipeAll clears all items from the fake queue', () async {
      final item = _pendingCheckIn();
      final queue = _FakeQueue([item]);
      await queue.wipeAll();
      final all = await queue.listAll();
      expect(all, isEmpty);
    });
  });
}
