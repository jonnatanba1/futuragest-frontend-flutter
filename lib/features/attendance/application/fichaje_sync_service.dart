import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connectivity/connectivity_service.dart';
import '../domain/attendance_repository.dart';
import '../domain/gps_position.dart';
import '../domain/pending_fichaje.dart';
import '../domain/ports/fichaje_queue_repository.dart';

/// Counts of queued fichajes by state — used by the UI sync-status indicator.
class SyncStats {
  const SyncStats({
    this.pending = 0,
    this.syncing = false,
    this.failed = 0,
  });

  /// Number of records that still need to reach the backend.
  /// [FichajeQueueStatus.ingresoComplete] is excluded — it is a resting state
  /// (ingreso fully synced, awaiting salida capture) with no pending network work.
  final int pending;

  /// [true] while a background sync pass is running.
  final bool syncing;

  /// Number of records in [FichajeQueueStatus.failed] state.
  final int failed;

  SyncStats copyWith({int? pending, bool? syncing, int? failed}) {
    return SyncStats(
      pending: pending ?? this.pending,
      syncing: syncing ?? this.syncing,
      failed: failed ?? this.failed,
    );
  }

  bool get isUpToDate => pending == 0 && !syncing && failed == 0;
}

/// Offline-first orchestrator for fichaje sync.
///
/// Responsibilities:
///  1. Write to queue FIRST (offline-first), then attempt immediate sync.
///  2. On connectivity-regained, replay all pending items in FIFO order.
///  3. On app start, trigger a replay.
///  4. Idempotent replay: backend dedupes on clientRef / checkOutClientRef.
///     Lost responses are recovered via GET /asistencia?clientRef=.
///  5. Exposes [SyncStats] for the UI indicator.
///
/// State machine per queue row (_replayOne):
///   pendingCheckIn     → POST check-in → markCheckedIn; status=checkedIn
///   checkedIn          → requires checkInPhotoPath
///                        → POST photo?phase=checkin → markIngresoComplete; status=ingresoComplete
///   ingresoComplete    → if checkOutPhotoPath present
///                        → POST photo?phase=checkout → markSalidaSigned; status=salidaSigned
///                        else NOTHING (resting — awaiting salida capture)
///   salidaSigned       → requires checkOutClientRef
///                        → POST check-out → markCompleted; status=completed
///
/// Key property: a row can accumulate BOTH ingreso AND salida data offline
/// (while still at pendingCheckIn). Replay then walks all four steps in
/// sequence once online — the step guards make this work regardless of status.
class FichajeSyncService extends StateNotifier<SyncStats> {
  FichajeSyncService({
    required FichajeQueueRepository queue,
    required AttendanceRepository remote,
    required ConnectivityService connectivity,
  })  : _queue = queue, // ignore: prefer_initializing_formals
        _remote = remote, // ignore: prefer_initializing_formals
        _connectivity = connectivity,
        super(const SyncStats()) {
    // Listen to connectivity changes; replay on reconnect.
    _connectivitySubTyped = connectivity.isOnlineStream.listen((online) {
      if (online) _replayAll();
    });
  }

  final FichajeQueueRepository _queue;
  final AttendanceRepository _remote;
  final ConnectivityService _connectivity;

  StreamSubscription<bool>? _connectivitySubTyped;
  bool _syncing = false;
  // True once _queue.init() has completed. The constructor subscribes to the
  // connectivity stream, which can emit "online" before init() finishes — this
  // flag prevents _replayAll from touching the DB before it is initialised.
  bool _initialised = false;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Initialises the database and triggers an initial sync attempt.
  Future<void> init() async {
    await _queue.init();
    _initialised = true;
    await _refreshStats();
    final online = await _connectivity.isOnline();
    if (online) await _replayAll();
  }

  /// Enqueues a new fichaje ingreso (write-first), then attempts sync if online.
  ///
  /// [checkInVerification] is the audit label from the biometric gate.
  /// Returns the queued [PendingFichaje] so the controller can track [localId].
  Future<PendingFichaje> enqueue({
    required String operarioId,
    required String operarioName,
    required String date,
    required String clientRef,
    required DateTime checkInCapturedAt,
    required GpsPosition checkInGps,
    String? checkInVerification,
  }) async {
    final pending = await _queue.enqueue(
      operarioId: operarioId,
      operarioName: operarioName,
      date: date,
      clientRef: clientRef,
      checkInCapturedAt: checkInCapturedAt,
      checkInGps: checkInGps,
      checkInVerification: checkInVerification,
    );
    await _refreshStats();

    final online = await _connectivity.isOnline();
    if (online) unawaited(_replayAll());

    return pending;
  }

  /// Saves the captured ingreso (entry) photo bytes for [localId].
  Future<void> saveCheckInPhoto({
    required int localId,
    required List<int> photoBytes,
  }) async {
    await _queue.saveCheckInPhoto(localId: localId, photoBytes: photoBytes);
    await _refreshStats();

    final online = await _connectivity.isOnline();
    if (online) unawaited(_replayAll());
  }

  /// Saves the salida (exit) data: exit photo + GPS/time for [localId].
  ///
  /// [checkOutVerification] is the audit label from the biometric gate.
  /// Does NOT change the status — replay advances it through the steps.
  Future<void> saveSalida({
    required int localId,
    required List<int> checkOutPhotoBytes,
    required String checkOutClientRef,
    required DateTime checkOutCapturedAt,
    required GpsPosition checkOutGps,
    String? checkOutVerification,
  }) async {
    await _queue.saveSalida(
      localId: localId,
      checkOutPhotoBytes: checkOutPhotoBytes,
      checkOutClientRef: checkOutClientRef,
      checkOutCapturedAt: checkOutCapturedAt,
      checkOutGps: checkOutGps,
      checkOutVerification: checkOutVerification,
    );
    await _refreshStats();

    final online = await _connectivity.isOnline();
    if (online) unawaited(_replayAll());
  }

  /// Force-triggers a sync pass (e.g. on app resume).
  Future<void> triggerSync() async {
    final online = await _connectivity.isOnline();
    if (online) await _replayAll();
  }

  // ── Replay ─────────────────────────────────────────────────────────────────

  Future<void> _replayAll() async {
    // Guard against the connectivity stream firing before init() completes.
    if (!_initialised) return;
    if (_syncing) return;
    _syncing = true;
    state = state.copyWith(syncing: true);

    try {
      final pending = await _queue.listPending();
      for (final item in pending) {
        await _replayOne(item);
      }
    } finally {
      _syncing = false;
      await _refreshStats();
    }
  }

  Future<void> _replayOne(PendingFichaje item) async {
    try {
      var current = item;

      // ── Step 1: POST check-in ─────────────────────────────────────────────
      if (current.status == FichajeQueueStatus.pendingCheckIn) {
        current = await _stepCheckIn(current);
        if (current.status == FichajeQueueStatus.failed) return;
      }

      // ── Step 2: POST entry (ingreso) photo ────────────────────────────────
      if (current.status == FichajeQueueStatus.checkedIn) {
        current = await _stepUploadCheckinPhoto(current);
        if (current.status == FichajeQueueStatus.failed) return;
      }

      // ── Step 3: POST exit (salida) photo ──────────────────────────────────
      // Only advance when checkOutPhotoPath is present.
      if (current.status == FichajeQueueStatus.ingresoComplete) {
        if (current.checkOutPhotoPath != null) {
          current = await _stepUploadCheckoutPhoto(current);
          if (current.status == FichajeQueueStatus.failed) return;
        }
        // else: resting — salida not yet captured, do nothing.
      }

      // ── Step 4: POST check-out ────────────────────────────────────────────
      if (current.status == FichajeQueueStatus.salidaSigned) {
        await _stepCheckOut(current);
      }
    } catch (_) {
      // Unexpected error; leave in current status and retry next cycle.
    }
  }

  Future<PendingFichaje> _stepCheckIn(PendingFichaje item) async {
    try {
      final record = await _remote.checkIn(
        operarioId: item.operarioId,
        date: item.date,
        capturedAt: item.checkInCapturedAt,
        position: item.checkInGps,
        clientRef: item.clientRef,
        verification: item.checkInVerification,
      );

      await _queue.markCheckedIn(
        localId: item.localId,
        serverAttendanceId: record.id,
      );
      return item.copyWith(
        serverAttendanceId: record.id,
        status: FichajeQueueStatus.checkedIn,
      );
    } on AttendanceException catch (e) {
      // Classify by HTTP status code (Fix 3/4/12 — not by message substring).
      final status = e.statusCode;

      if (status == 409) {
        // Duplicate → the check-in already exists server-side.
        // Attempt to recover the server attendance ID via GET.
        return await _recoverCheckIn(item);
      }

      if (status == null || status >= 500) {
        // Network error or server fault → TRANSIENT: leave pending for retry.
        return item;
      }

      // 4xx (422 AttendanceDateMismatchError, 400, etc.) → terminal failure.
      // Fix 6/11: date-mismatch is treated as terminal with the REAL backend
      // message. Full clock-skew detection (NTP) is out of scope.
      await _queue.markFailed(localId: item.localId, reason: e.message);
      return item.copyWith(
        status: FichajeQueueStatus.failed,
        failureReason: e.message,
      );
    } catch (_) {
      // Unexpected non-AttendanceException → leave pending for retry.
      return item;
    }
  }

  /// Calls GET /asistencia?clientRef= to recover the server attendance ID
  /// after a 409 or a lost response.
  Future<PendingFichaje> _recoverCheckIn(PendingFichaje item) async {
    try {
      final record = await _remote.recoverByClientRef(item.clientRef);
      if (record != null) {
        // Our own check-in actually succeeded (the response was lost) — link
        // the server id and continue the flow.
        await _queue.markCheckedIn(
          localId: item.localId,
          serverAttendanceId: record.id,
        );
        return item.copyWith(
          serverAttendanceId: record.id,
          status: FichajeQueueStatus.checkedIn,
        );
      }

      // The GET returned an empty result (null) — the record was NOT found with
      // our clientRef. This could mean:
      //  a) A genuine duplicate: a DIFFERENT check-in owns today's slot.
      //  b) A GET lag: the server committed the row but the read replica hasn't
      //     caught up yet.
      //
      // Fix 5: leave the item PENDING instead of marking it failed immediately.
      // The next sync cycle will retry. A true duplicate will eventually be
      // confirmed once the server read is consistent. This prevents destroying
      // real check-ins due to transient read-after-write lag.
      return item;
    } on AttendanceException catch (e) {
      // recoverByClientRef rethrows non-404 errors as AttendanceException with
      // statusCode (Fix 10). Treat as TRANSIENT — leave pending for retry.
      final status = e.statusCode;
      if (status == null || status >= 500) {
        return item;
      }
      // 401 or other 4xx → also leave pending; session recovery handles 401.
      return item;
    } catch (_) {
      // Network error — leave as pendingCheckIn and retry next cycle.
      return item;
    }
  }

  Future<PendingFichaje> _stepUploadCheckinPhoto(
    PendingFichaje item,
  ) async {
    final serverId = item.serverAttendanceId;
    final photoPath = item.checkInPhotoPath;

    // No entry photo yet — supervisor hasn't captured it offline.
    if (photoPath == null || serverId == null) return item;

    try {
      final bytes = await File(photoPath).readAsBytes();
      await _remote.uploadPhoto(
        attendanceId: serverId,
        photoBytes: bytes.toList(),
        phase: 'checkin',
      );
      await _queue.markIngresoComplete(localId: item.localId);
      return item.copyWith(status: FichajeQueueStatus.ingresoComplete);
    } on AttendanceException catch (e) {
      await _queue.markFailed(localId: item.localId, reason: e.message);
      return item.copyWith(
        status: FichajeQueueStatus.failed,
        failureReason: e.message,
      );
    } catch (_) {
      // Network error — retry next cycle.
      return item;
    }
  }

  Future<PendingFichaje> _stepUploadCheckoutPhoto(
    PendingFichaje item,
  ) async {
    final serverId = item.serverAttendanceId;
    final photoPath = item.checkOutPhotoPath;

    if (photoPath == null || serverId == null) return item;

    try {
      final bytes = await File(photoPath).readAsBytes();
      await _remote.uploadPhoto(
        attendanceId: serverId,
        photoBytes: bytes.toList(),
        phase: 'checkout',
      );
      await _queue.markSalidaSigned(localId: item.localId);
      return item.copyWith(status: FichajeQueueStatus.salidaSigned);
    } on AttendanceException catch (e) {
      await _queue.markFailed(localId: item.localId, reason: e.message);
      return item.copyWith(
        status: FichajeQueueStatus.failed,
        failureReason: e.message,
      );
    } catch (_) {
      // Network error — retry next cycle.
      return item;
    }
  }

  Future<void> _stepCheckOut(PendingFichaje item) async {
    final serverId = item.serverAttendanceId;
    final checkOutRef = item.checkOutClientRef;
    final checkOutAt = item.checkOutCapturedAt;
    final checkOutGps = item.checkOutGps;

    // No check-out data yet — this shouldn't happen when status==salidaSigned
    // but guard defensively.
    if (serverId == null ||
        checkOutRef == null ||
        checkOutAt == null ||
        checkOutGps == null) {
      return;
    }

    try {
      await _remote.checkOut(
        attendanceId: serverId,
        capturedAt: checkOutAt,
        position: checkOutGps,
        checkOutClientRef: checkOutRef,
        verification: item.checkOutVerification,
      );
      await _queue.markCompleted(localId: item.localId);
    } on AttendanceException catch (e) {
      // Classify by HTTP status code (Fix 3/4 — mirrors _stepCheckIn logic).
      final status = e.statusCode;

      if (status == null || status >= 500) {
        // TRANSIENT — leave item in salidaSigned and retry next cycle.
        return;
      }

      // 4xx → terminal failure with the REAL backend message.
      // This correctly surfaces PhotoRequiredError, InvalidShiftDurationError,
      // or any other 422 with its actual Spanish description.
      await _queue.markFailed(localId: item.localId, reason: e.message);
    } catch (_) {
      // Network error — retry next cycle.
    }
  }

  // ── Stats ──────────────────────────────────────────────────────────────────

  Future<void> _refreshStats() async {
    final all = await _queue.listAll();
    final pending = all
        .where(
          (f) =>
              f.status != FichajeQueueStatus.completed &&
              f.status != FichajeQueueStatus.failed &&
              f.status != FichajeQueueStatus.ingresoComplete,
        )
        .length;
    final failed =
        all.where((f) => f.status == FichajeQueueStatus.failed).length;
    state = state.copyWith(pending: pending, syncing: _syncing, failed: failed);
  }

  @override
  void dispose() {
    _connectivitySubTyped?.cancel();
    super.dispose();
  }
}
