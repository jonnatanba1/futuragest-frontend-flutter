import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/biometric/biometric_service.dart';
import '../../../core/location/location_service.dart'
    as core_location show LocationException;
import '../../../core/location/location_service.dart' show LocationService;
import '../domain/attendance_record.dart';
import '../domain/attendance_repository.dart';
import '../domain/gps_position.dart';
import '../domain/operario.dart';
import 'attendance_providers.dart';
import 'fichaje_state.dart';
import 'fichaje_sync_service.dart';

const _uuid = Uuid();

/// Drives the per-operario fichaje flow.
///
/// STEP 2 changes vs STEP 1:
///  - Each commit action (checkIn, checkOut) is now gated behind a biometric
///    confirmation via [BiometricService].
///  - The intent is written to the offline queue FIRST via [FichajeSyncService]
///    before any network call. Sync service handles the actual POSTs.
///  - UI state advances optimistically after the queue write succeeds. When
///    offline the supervisor can still complete the full flow (GPS + signature
///    + check-out captured locally); the sync service replays when online.
///  - The state machine transitions are identical to STEP 1 — screen code
///    needed minimal changes (pending-offline badge only).
class FichajeController extends StateNotifier<FichajeState> {
  FichajeController({
    required Operario operario,
    required FichajeSyncService syncService,
    required BiometricService biometric,
  })  : _syncService = syncService, // ignore: prefer_initializing_formals
        _biometric = biometric, // ignore: prefer_initializing_formals
        super(FichajeIdle(operario));

  final FichajeSyncService _syncService;
  final BiometricService _biometric;

  // Tracks the local queue row ID for this fichaje session.
  int? _localId;

  // ── Biometric gate ─────────────────────────────────────────────────────────

  /// Returns [true] to proceed, [false] if cancelled.
  /// Throws [AttendanceException] on lockout.
  Future<bool> _confirmBiometric(String reason) async {
    try {
      final result = await _biometric.confirm(reason);
      return switch (result) {
        BiometricResult.authenticated => true,
        BiometricResult.cancelled => false,
        // Device has no biometric — service has set requireBiometric=false.
        BiometricResult.unavailable => true,
      };
    } on BiometricException catch (e) {
      throw AttendanceException(e.message);
    }
  }

  // ── Check-in ───────────────────────────────────────────────────────────────

  Future<void> checkIn() async {
    final current = state;
    if (current is! FichajeIdle) return;
    final operario = current.operario;

    state = FichajeCheckingIn(operario);

    try {
      // 1. Biometric gate (before any write).
      final ok = await _confirmBiometric(
        'Confirmá tu identidad para registrar la entrada de ${operario.fullName}.',
      );
      if (!ok) {
        state = FichajeError(
          message: 'Autenticación biométrica cancelada.',
          previous: FichajeIdle(operario),
        );
        return;
      }

      // 2. GPS.
      final corePos = await LocationService.getCurrentPosition();
      final pos = GpsPosition(
        latitude: corePos.latitude,
        longitude: corePos.longitude,
        accuracy: corePos.accuracy,
      );

      // 3. Idempotency token + Colombia date (UTC-5).
      final clientRef = _uuid.v4();
      final now = DateTime.now();
      final colombiaTime = now.toUtc().add(const Duration(hours: -5));
      final date =
          '${colombiaTime.year.toString().padLeft(4, '0')}'
          '-${colombiaTime.month.toString().padLeft(2, '0')}'
          '-${colombiaTime.day.toString().padLeft(2, '0')}';
      final capturedAt = now.toUtc();

      // 4. Write to offline queue FIRST; sync handles the POST.
      final queued = await _syncService.enqueue(
        operarioId: operario.id,
        operarioName: operario.fullName,
        date: date,
        clientRef: clientRef,
        checkInCapturedAt: capturedAt,
        checkInGps: pos,
      );
      _localId = queued.localId;

      // 5. Provisional AttendanceRecord so the screen can continue.
      //    The server ID will be empty until sync succeeds; the queue localId
      //    is used as the routing key for subsequent steps.
      final provisionalRecord = AttendanceRecord(
        id: queued.serverAttendanceId ?? '',
        operarioId: operario.id,
        date: date,
        clientRef: clientRef,
        checkInCapturedAt: capturedAt,
        checkInLat: pos.latitude,
        checkInLng: pos.longitude,
        checkInAccuracy: pos.accuracy,
      );

      state = FichajeAwaitingSignature(
        operario: operario,
        record: provisionalRecord,
        localQueueId: queued.localId,
        isOffline: queued.serverAttendanceId == null,
      );
    } on core_location.LocationException catch (e) {
      state = FichajeError(message: e.message, previous: FichajeIdle(operario));
    } on AttendanceException catch (e) {
      state = FichajeError(message: e.message, previous: FichajeIdle(operario));
    } catch (e) {
      state = FichajeError(
        message: 'Error inesperado: $e',
        previous: FichajeIdle(operario),
      );
    }
  }

  // ── Signature upload ───────────────────────────────────────────────────────

  Future<void> uploadSignature(List<int> pngBytes) async {
    final current = state;
    if (current is! FichajeAwaitingSignature) return;

    final operario = current.operario;
    final record = current.record;
    final localId = current.localQueueId ?? _localId;
    state = FichajeUploadingSignature(operario: operario, record: record);

    try {
      if (localId != null) {
        // Persist PNG to disk via queue; sync will upload to backend.
        await _syncService.saveSignature(
          localId: localId,
          pngBytes: pngBytes,
        );
      }

      final updatedRecord = record.copyWith(signatureUploaded: true);
      state = FichajeSignatureDone(
        operario: operario,
        record: updatedRecord,
        localQueueId: localId,
      );
    } on AttendanceException catch (e) {
      state = FichajeError(
        message: e.message,
        previous: FichajeAwaitingSignature(
          operario: operario,
          record: record,
          localQueueId: localId,
        ),
      );
    } catch (e) {
      state = FichajeError(
        message: 'Error inesperado al guardar la firma: $e',
        previous: FichajeAwaitingSignature(
          operario: operario,
          record: record,
          localQueueId: localId,
        ),
      );
    }
  }

  // ── Check-out ──────────────────────────────────────────────────────────────

  Future<void> checkOut() async {
    final current = state;
    if (current is! FichajeSignatureDone) return;

    final operario = current.operario;
    final record = current.record;
    final localId = current.localQueueId ?? _localId;
    state = FichajeCheckingOut(operario: operario, record: record);

    try {
      // 1. Biometric gate.
      final ok = await _confirmBiometric(
        'Confirmá tu identidad para registrar la salida de ${operario.fullName}.',
      );
      if (!ok) {
        state = FichajeError(
          message: 'Autenticación biométrica cancelada.',
          previous: FichajeSignatureDone(
            operario: operario,
            record: record,
            localQueueId: localId,
          ),
        );
        return;
      }

      // 2. GPS.
      final corePos = await LocationService.getCurrentPosition();
      final pos = GpsPosition(
        latitude: corePos.latitude,
        longitude: corePos.longitude,
        accuracy: corePos.accuracy,
      );

      final capturedAt = DateTime.now().toUtc();
      final checkOutClientRef = _uuid.v4();

      // 3. Save check-out intent to queue; sync handles the POST.
      if (localId != null) {
        await _syncService.saveCheckOut(
          localId: localId,
          checkOutClientRef: checkOutClientRef,
          checkOutCapturedAt: capturedAt,
          checkOutGps: pos,
        );
      }

      // 4. Advance UI optimistically.
      final completedRecord = record.copyWith(
        checkOutCapturedAt: capturedAt,
        checkOutLat: pos.latitude,
        checkOutLng: pos.longitude,
        checkOutAccuracy: pos.accuracy,
      );

      state = FichajeDone(operario: operario, record: completedRecord);
    } on core_location.LocationException catch (e) {
      state = FichajeError(
        message: e.message,
        previous: FichajeSignatureDone(
          operario: operario,
          record: record,
          localQueueId: localId,
        ),
      );
    } on AttendanceException catch (e) {
      state = FichajeError(
        message: e.message,
        previous: FichajeSignatureDone(
          operario: operario,
          record: record,
          localQueueId: localId,
        ),
      );
    } catch (e) {
      state = FichajeError(
        message: 'Error inesperado: $e',
        previous: FichajeSignatureDone(
          operario: operario,
          record: record,
          localQueueId: localId,
        ),
      );
    }
  }

  // ── Retry ──────────────────────────────────────────────────────────────────

  void retry() {
    final current = state;
    if (current is FichajeError) {
      state = current.previous;
    }
  }
}

/// Family provider — one [FichajeController] per operario.
final fichajeControllerProvider = StateNotifierProviderFamily<
    FichajeController, FichajeState, Operario>(
  (ref, operario) => FichajeController(
    operario: operario,
    syncService: ref.watch(fichajeSyncServiceProvider.notifier),
    biometric: ref.watch(biometricServiceProvider),
  ),
);
