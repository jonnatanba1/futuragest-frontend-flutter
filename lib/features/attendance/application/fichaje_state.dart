import '../domain/attendance_record.dart';
import '../domain/operario.dart';

/// Sealed state for the per-operario fichaje (check-in/out) flow.
///
/// State machine:
///   FichajeIdle
///     → FichajeCheckingIn  (biometric + GPS + queue-write in progress)
///     → FichajeAwaitingSignature(record, localQueueId, isOffline)
///     → FichajeUploadingSignature(record)  (PNG write to queue in progress)
///     → FichajeSignatureDone(record, localQueueId)
///     → FichajeCheckingOut(record)         (biometric + GPS + queue-write)
///     → FichajeDone(record)               (check-out confirmed locally)
///     → FichajeError(message, previous)   (recoverable error, retry possible)
///
/// STEP 2 additions:
///   - [FichajeAwaitingSignature] carries [localQueueId] (queue row ID) and
///     [isOffline] flag so the screen can show a "Pendiente de sincronizar"
///     badge when the check-in hasn't reached the backend yet.
///   - [FichajeSignatureDone] carries [localQueueId] for the check-out write.
///   - Both carry the same [AttendanceRecord] shape as STEP 1 for backward
///     compatibility. When offline, [AttendanceRecord.id] may be empty ('') —
///     the controller routes subsequent steps by [localQueueId] instead.
sealed class FichajeState {
  const FichajeState();
}

/// No action in progress for this operario.
final class FichajeIdle extends FichajeState {
  const FichajeIdle(this.operario);

  final Operario operario;
}

/// Biometric prompt + GPS + queue write in progress.
final class FichajeCheckingIn extends FichajeState {
  const FichajeCheckingIn(this.operario);

  final Operario operario;
}

/// Check-in queued (and possibly synced). Waiting for the supervisor to
/// capture the operario's signature.
final class FichajeAwaitingSignature extends FichajeState {
  const FichajeAwaitingSignature({
    required this.operario,
    required this.record,
    this.localQueueId,
    this.isOffline = false,
  });

  final Operario operario;
  final AttendanceRecord record;

  /// Local queue row ID. Used to attach signature / check-out to this record.
  final int? localQueueId;

  /// [true] when the check-in POST has not yet been confirmed by the server.
  /// The UI shows a "Pendiente de sincronizar" badge in this case.
  final bool isOffline;
}

/// PNG write to queue / disk in progress.
final class FichajeUploadingSignature extends FichajeState {
  const FichajeUploadingSignature({
    required this.operario,
    required this.record,
  });

  final Operario operario;
  final AttendanceRecord record;
}

/// Signature saved locally. Ready to check out.
final class FichajeSignatureDone extends FichajeState {
  const FichajeSignatureDone({
    required this.operario,
    required this.record,
    this.localQueueId,
  });

  final Operario operario;
  final AttendanceRecord record;

  /// Local queue row ID. Forwarded to check-out write.
  final int? localQueueId;
}

/// Biometric prompt + GPS + queue write in progress for check-out.
final class FichajeCheckingOut extends FichajeState {
  const FichajeCheckingOut({
    required this.operario,
    required this.record,
  });

  final Operario operario;
  final AttendanceRecord record;
}

/// Check-out queued locally. Flow complete from the supervisor's perspective.
/// The sync service will replay to the backend when online.
final class FichajeDone extends FichajeState {
  const FichajeDone({
    required this.operario,
    required this.record,
  });

  final Operario operario;
  final AttendanceRecord record;
}

/// A recoverable error. [previous] holds the state before the error so the UI
/// can offer a retry.
final class FichajeError extends FichajeState {
  const FichajeError({required this.message, required this.previous});

  final String message;
  final FichajeState previous;
}
