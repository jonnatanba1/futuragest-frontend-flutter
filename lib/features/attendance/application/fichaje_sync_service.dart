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

  /// Number of records that still need to reach the backend (any non-terminal
  /// status except [FichajeQueueStatus.completed] and [FichajeQueueStatus.failed]).
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
/// Replay order per item:
///   pendingCheckIn         → POST check-in → markCheckedIn (or recover)
///   checkedInPendingSignature → POST signature → markSignatureUploaded
///   signedPendingCheckOut  → POST check-out  → markCompleted
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

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Initialises the database and triggers an initial sync attempt.
  Future<void> init() async {
    await _queue.init();
    await _refreshStats();
    final online = await _connectivity.isOnline();
    if (online) await _replayAll();
  }

  /// Enqueues a new fichaje (write-first), then attempts sync if online.
  ///
  /// Returns the queued [PendingFichaje] so the controller can track [localId].
  Future<PendingFichaje> enqueue({
    required String operarioId,
    required String operarioName,
    required String date,
    required String clientRef,
    required DateTime checkInCapturedAt,
    required GpsPosition checkInGps,
  }) async {
    final pending = await _queue.enqueue(
      operarioId: operarioId,
      operarioName: operarioName,
      date: date,
      clientRef: clientRef,
      checkInCapturedAt: checkInCapturedAt,
      checkInGps: checkInGps,
    );
    await _refreshStats();

    final online = await _connectivity.isOnline();
    if (online) unawaited(_replayAll());

    return pending;
  }

  /// Saves the captured signature bytes for [localId].
  Future<void> saveSignature({
    required int localId,
    required List<int> pngBytes,
  }) async {
    await _queue.saveSignature(localId: localId, pngBytes: pngBytes);
    await _refreshStats();

    final online = await _connectivity.isOnline();
    if (online) unawaited(_replayAll());
  }

  /// Saves the check-out intent for [localId].
  Future<void> saveCheckOut({
    required int localId,
    required String checkOutClientRef,
    required DateTime checkOutCapturedAt,
    required GpsPosition checkOutGps,
  }) async {
    await _queue.saveCheckOut(
      localId: localId,
      checkOutClientRef: checkOutClientRef,
      checkOutCapturedAt: checkOutCapturedAt,
      checkOutGps: checkOutGps,
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

      // ── Step 2: POST signature ────────────────────────────────────────────
      if (current.status == FichajeQueueStatus.checkedInPendingSignature) {
        current = await _stepUploadSignature(current);
        if (current.status == FichajeQueueStatus.failed) return;
      }

      // ── Step 3: POST check-out ────────────────────────────────────────────
      if (current.status == FichajeQueueStatus.signedPendingCheckOut) {
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
      );

      await _queue.markCheckedIn(
        localId: item.localId,
        serverAttendanceId: record.id,
      );
      return item.copyWith(
        serverAttendanceId: record.id,
        status: FichajeQueueStatus.checkedInPendingSignature,
      );
    } on AttendanceException catch (e) {
      // 409 = duplicate → the check-in already exists server-side.
      // Attempt to recover the server attendance ID via GET.
      if (e.message.contains('ya tiene un registro')) {
        return await _recoverCheckIn(item);
      }
      // Other attendance error — mark failed (non-transient business error).
      await _queue.markFailed(localId: item.localId, reason: e.message);
      return item.copyWith(
        status: FichajeQueueStatus.failed,
        failureReason: e.message,
      );
    } catch (_) {
      // Network error — leave as pendingCheckIn and retry next cycle.
      return item;
    }
  }

  /// Calls GET /asistencia?clientRef= to recover the server attendance ID
  /// after a 409 or a lost response.
  Future<PendingFichaje> _recoverCheckIn(PendingFichaje item) async {
    try {
      final record = await _remote.recoverByClientRef(item.clientRef);
      if (record != null) {
        await _queue.markCheckedIn(
          localId: item.localId,
          serverAttendanceId: record.id,
        );
        return item.copyWith(
          serverAttendanceId: record.id,
          status: FichajeQueueStatus.checkedInPendingSignature,
        );
      }
    } catch (_) {
      // Recovery request itself failed; retry next cycle.
    }
    // Could not recover — leave as pendingCheckIn.
    return item;
  }

  Future<PendingFichaje> _stepUploadSignature(PendingFichaje item) async {
    final serverId = item.serverAttendanceId;
    final sigPath = item.signaturePngPath;

    // If no signature captured yet, the supervisor hasn't drawn it offline —
    // nothing to upload. Leave in checkedInPendingSignature.
    if (sigPath == null || serverId == null) return item;

    try {
      final bytes = await File(sigPath).readAsBytes();
      await _remote.uploadSignature(
        attendanceId: serverId,
        signaturePngBytes: bytes.toList(),
      );
      await _queue.markSignatureUploaded(localId: item.localId);
      return item.copyWith(status: FichajeQueueStatus.signedPendingCheckOut);
    } on AttendanceException catch (e) {
      // Non-transient → mark failed.
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

    // No check-out data yet — supervisor hasn't triggered it offline.
    if (serverId == null || checkOutRef == null || checkOutAt == null ||
        checkOutGps == null) {
      return;
    }

    try {
      await _remote.checkOut(
        attendanceId: serverId,
        capturedAt: checkOutAt,
        position: checkOutGps,
        checkOutClientRef: checkOutRef,
      );
      await _queue.markCompleted(localId: item.localId);
    } on AttendanceException catch (e) {
      if (e.message.contains('firma')) {
        // 422 SignatureRequired — shouldn't happen (we check step ordering)
        // but retry after re-uploading signature next cycle.
        // Reset to checkedInPendingSignature so we retry upload first.
        // We do this by leaving current status as-is and NOT marking failed.
        return;
      }
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
              f.status != FichajeQueueStatus.failed,
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

