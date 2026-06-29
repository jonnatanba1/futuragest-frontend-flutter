import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/biometric/biometric_service.dart'
    show BiometricException, BiometricOutcome, BiometricResult, BiometricService, VerificationMethod;
import '../../../core/location/location_service.dart'
    as core_location show LocationException;
import '../../../core/location/location_service.dart' show LocationService;
import '../domain/attendance_record.dart';
import '../domain/attendance_repository.dart';
import '../domain/gps_position.dart';
import '../domain/operario.dart';
import '../domain/ports/fichaje_queue_repository.dart'
    show DuplicateLocalFichajeException;
import 'attendance_providers.dart';
import 'fichaje_state.dart';
import 'fichaje_sync_service.dart';

const _uuid = Uuid();

/// Parameters that identify a fichaje session for the [FichajeController]
/// family provider.
///
/// [mode] determines which flow runs:
///   - [FichajeMode.ingreso]: biometric → GPS → enqueue → entry photo → done.
///   - [FichajeMode.salida]: biometric → GPS → exit photo → saveSalida → done.
///
/// For salida mode, [localQueueId] identifies the queue row created at ingreso.
/// [serverAttendanceId] may be null if the ingreso hasn't synced yet — salida
/// is still captured offline and replay sequences correctly.
class FichajeParams {
  const FichajeParams({
    required this.operario,
    required this.mode,
    this.localQueueId,
    this.serverAttendanceId,
  });

  final Operario operario;
  final FichajeMode mode;
  final int? localQueueId;
  final String? serverAttendanceId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FichajeParams &&
          operario.id == other.operario.id &&
          mode == other.mode &&
          localQueueId == other.localQueueId;

  @override
  int get hashCode => Object.hash(operario.id, mode, localQueueId);
}

/// Drives the per-operario fichaje flow (ingreso or salida).
///
/// INGRESO flow:
///   checkIn() → biometric → GPS → enqueue → FichajeAwaitingPhoto(mode:ingreso)
///   uploadPhoto(photoBytes) → saveCheckInPhoto → FichajeDone(mode:ingreso)
///
/// SALIDA flow:
///   startSalidaFlow() → biometric → GPS → FichajeAwaitingPhoto(mode:salida)
///   uploadPhoto(photoBytes) → saveSalida → FichajeDone(mode:salida)
class FichajeController extends StateNotifier<FichajeState> {
  FichajeController({
    required FichajeParams params,
    required this._syncService,
    required this._biometric,
  })  : _params = params,
        super(FichajeIdle(params.operario));

  final FichajeParams _params;
  final FichajeSyncService _syncService;
  final BiometricService _biometric;

  // Tracks the local queue row ID for this session.
  int? _localId;
  // Data captured during the salida biometric+GPS step.
  // Cleared on reset/abort to prevent stale data leaking into a later attempt.
  GpsPosition? _salidaGps;
  DateTime? _salidaCapturedAt;
  String? _salidaVerification;

  Operario get _operario => _params.operario;

  // ── Biometric gate ─────────────────────────────────────────────────────────

  /// Asks the user to confirm identity and returns the [BiometricOutcome].
  ///
  /// Returns the outcome to callers so they can:
  ///   - check [BiometricOutcome.result] to decide whether to proceed, and
  ///   - read [BiometricOutcome.verification] for the audit label.
  ///
  /// Throws [AttendanceException] on unrecoverable platform errors.
  Future<BiometricOutcome> _confirmBiometric(String reason) async {
    try {
      return await _biometric.confirm(reason);
    } on BiometricException catch (e) {
      throw AttendanceException(e.message);
    }
  }

  // ── Entry point ────────────────────────────────────────────────────────────

  /// Starts the appropriate flow based on [FichajeParams.mode].
  Future<void> start() async {
    if (_params.mode == FichajeMode.ingreso) {
      await checkIn();
    } else {
      await startSalidaFlow();
    }
  }

  // ── INGRESO flow ───────────────────────────────────────────────────────────

  Future<void> checkIn() async {
    final current = state;
    if (current is! FichajeIdle) return;

    state = FichajeCheckingIn(_operario);

    try {
      // 1. Biometric gate.
      final outcome = await _confirmBiometric(
        'Confirmá tu identidad para registrar la entrada de ${_operario.fullName}.',
      );
      if (outcome.result == BiometricResult.cancelled) {
        state = FichajeError(
          message: 'Autenticación biométrica cancelada.',
          previous: FichajeIdle(_operario),
        );
        return;
      }
      // unavailable → degrade gracefully; label = NONE.
      final checkInVerification =
          outcome.result == BiometricResult.unavailable
              ? VerificationMethod.none
              : outcome.verification;

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
        operarioId: _operario.id,
        operarioName: _operario.fullName,
        date: date,
        clientRef: clientRef,
        checkInCapturedAt: capturedAt,
        checkInGps: pos,
        checkInVerification: checkInVerification,
      );
      _localId = queued.localId;

      // 5. Provisional AttendanceRecord so the screen can continue.
      final provisionalRecord = AttendanceRecord(
        id: queued.serverAttendanceId ?? '',
        operarioId: _operario.id,
        date: date,
        clientRef: clientRef,
        checkInCapturedAt: capturedAt,
        checkInLat: pos.latitude,
        checkInLng: pos.longitude,
        checkInAccuracy: pos.accuracy,
      );

      state = FichajeAwaitingPhoto(
        operario: _operario,
        mode: FichajeMode.ingreso,
        record: provisionalRecord,
        localQueueId: queued.localId,
        isOffline: queued.serverAttendanceId == null,
      );
    } on DuplicateLocalFichajeException {
      state = FichajeError(
        message: 'Este operario ya tiene un ingreso registrado para hoy en este dispositivo.',
        previous: FichajeIdle(_operario),
      );
    } on core_location.LocationException catch (e) {
      state = FichajeError(message: e.message, previous: FichajeIdle(_operario));
    } on AttendanceException catch (e) {
      state = FichajeError(message: e.message, previous: FichajeIdle(_operario));
    } catch (e) {
      state = FichajeError(
        message: 'Error inesperado: $e',
        previous: FichajeIdle(_operario),
      );
    }
  }

  // ── SALIDA flow ────────────────────────────────────────────────────────────

  Future<void> startSalidaFlow() async {
    final current = state;
    if (current is! FichajeIdle) return;

    state = FichajeCheckingIn(_operario);

    try {
      // 1. Biometric gate.
      final outcome = await _confirmBiometric(
        'Confirmá tu identidad para registrar la salida de ${_operario.fullName}.',
      );
      if (outcome.result == BiometricResult.cancelled) {
        state = FichajeError(
          message: 'Autenticación biométrica cancelada.',
          previous: FichajeIdle(_operario),
        );
        return;
      }
      // unavailable → degrade gracefully; label = NONE.
      final checkOutVerification =
          outcome.result == BiometricResult.unavailable
              ? VerificationMethod.none
              : outcome.verification;

      // 2. GPS.
      final corePos = await LocationService.getCurrentPosition();
      final pos = GpsPosition(
        latitude: corePos.latitude,
        longitude: corePos.longitude,
        accuracy: corePos.accuracy,
      );
      _salidaGps = pos;
      _salidaCapturedAt = DateTime.now().toUtc();
      _salidaVerification = checkOutVerification;

      // 3. Resolve the local queue row. The caller provides localQueueId if
      //    they looked it up via findOpenByOperarioAndDate.
      _localId = _params.localQueueId;

      state = FichajeAwaitingPhoto(
        operario: _operario,
        mode: FichajeMode.salida,
        localQueueId: _localId,
        // The salida is always "offline-capable" — show badge if no server id.
        isOffline: _params.serverAttendanceId == null,
      );
    } on core_location.LocationException catch (e) {
      state = FichajeError(message: e.message, previous: FichajeIdle(_operario));
    } on AttendanceException catch (e) {
      state = FichajeError(message: e.message, previous: FichajeIdle(_operario));
    } catch (e) {
      state = FichajeError(
        message: 'Error inesperado: $e',
        previous: FichajeIdle(_operario),
      );
    }
  }

  // ── Shared: photo upload ───────────────────────────────────────────────────

  /// Routes to the correct save method depending on the current mode.
  Future<void> uploadPhoto(List<int> photoBytes) async {
    final current = state;
    if (current is! FichajeAwaitingPhoto) return;

    final localId = current.localQueueId ?? _localId;
    state = FichajeUploadingPhoto(operario: _operario);

    try {
      if (current.mode == FichajeMode.ingreso) {
        await _saveIngresoPhoto(localId, photoBytes, current);
      } else {
        await _saveSalidaPhoto(localId, photoBytes, current);
      }
    } on AttendanceException catch (e) {
      state = FichajeError(
        message: e.message,
        previous: current,
      );
    } catch (e) {
      state = FichajeError(
        message: 'Error inesperado al guardar la foto: $e',
        previous: current,
      );
    }
  }

  Future<void> _saveIngresoPhoto(
    int? localId,
    List<int> photoBytes,
    FichajeAwaitingPhoto prev,
  ) async {
    if (localId != null) {
      await _syncService.saveCheckInPhoto(
        localId: localId,
        photoBytes: photoBytes,
      );
    }

    state = FichajeDone(
      operario: _operario,
      mode: FichajeMode.ingreso,
      serverAttendanceId: prev.record?.id.isNotEmpty == true
          ? prev.record!.id
          : null,
    );
  }

  Future<void> _saveSalidaPhoto(
    int? localId,
    List<int> photoBytes,
    FichajeAwaitingPhoto prev,
  ) async {
    final capturedAt = _salidaCapturedAt ?? DateTime.now().toUtc();
    final gps = _salidaGps;

    if (localId != null && gps != null) {
      await _syncService.saveSalida(
        localId: localId,
        checkOutPhotoBytes: photoBytes,
        checkOutClientRef: _uuid.v4(),
        checkOutCapturedAt: capturedAt,
        checkOutGps: gps,
        checkOutVerification: _salidaVerification,
      );
    } else if (localId == null) {
      // No local row AND no server ID — same-device assumption violated.
      // The caller (operario list) should have already shown the SnackBar;
      // this branch is a safety net.
      // TODO(cross-device-salida): support salida from a different device.
      state = FichajeError(
        message: 'No se encontró el ingreso en este dispositivo.',
        previous: prev,
      );
      return;
    }

    state = FichajeDone(
      operario: _operario,
      mode: FichajeMode.salida,
      serverAttendanceId: _params.serverAttendanceId,
    );
  }

  // ── Retry ──────────────────────────────────────────────────────────────────

  /// Resets to the previous state (typically [FichajeIdle]) and restarts the
  /// flow so biometric + GPS are re-prompted on the next attempt.
  ///
  /// This fixes the dead-end where calling [retry()] alone just reset to Idle
  /// without re-triggering [start()], leaving the user stuck on a blank spinner.
  Future<void> retry() async {
    final current = state;
    if (current is! FichajeError) return;
    _clearSalidaFields();
    state = current.previous;
    // Re-start only if we landed back on FichajeIdle; any other previous state
    // (e.g. FichajeAwaitingPhoto from an upload error) doesn't need a restart.
    if (state is FichajeIdle) {
      await start();
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Clears salida-phase ephemeral fields so a subsequent flow attempt cannot
  /// accidentally reuse GPS or verification data from an aborted salida.
  void _clearSalidaFields() {
    _salidaGps = null;
    _salidaCapturedAt = null;
    _salidaVerification = null;
  }
}

/// Family provider — one [FichajeController] per [FichajeParams].
final fichajeControllerProvider = StateNotifierProviderFamily<
    FichajeController, FichajeState, FichajeParams>(
  (ref, params) => FichajeController(
    params: params,
    syncService: ref.watch(fichajeSyncServiceProvider.notifier),
    biometric: ref.watch(biometricServiceProvider),
  ),
);
