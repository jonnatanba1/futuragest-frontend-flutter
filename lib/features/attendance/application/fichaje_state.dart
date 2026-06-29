import '../domain/attendance_record.dart';
import '../domain/operario.dart';

/// Which phase of the fichaje day this screen session handles.
enum FichajeMode {
  /// Morning: biometric → GPS → enqueue check-in → entry photo → Done.
  ingreso,

  /// Evening: biometric → GPS → exit photo → saveSalida → Done.
  salida,
}

/// Sealed state for the per-operario fichaje (check-in/out) flow.
///
/// INGRESO state machine:
///   FichajeIdle
///     → FichajeCheckingIn            (biometric + GPS + queue-write in progress)
///     → FichajeAwaitingPhoto          (entry photo needed)
///     → FichajeUploadingPhoto         (photo write to queue in progress)
///     → FichajeDone                   (ingreso complete — shows "Ingreso registrado")
///     → FichajeError(message, previous)
///
/// SALIDA state machine:
///   FichajeIdle
///     → FichajeCheckingIn            (biometric + GPS in progress)
///     → FichajeAwaitingPhoto          (exit photo needed; isOffline may be true)
///     → FichajeUploadingPhoto         (photo write + saveSalida in progress)
///     → FichajeDone                   (salida complete — shows "Salida registrada")
///     → FichajeError(message, previous)
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
/// capture the operario's photo.
///
/// Used for BOTH the ingreso (entry) and salida (exit) photo steps.
final class FichajeAwaitingPhoto extends FichajeState {
  const FichajeAwaitingPhoto({
    required this.operario,
    required this.mode,
    this.record,
    this.localQueueId,
    this.isOffline = false,
  });

  final Operario operario;

  /// Which phase this photo belongs to.
  final FichajeMode mode;

  /// Provisional attendance record (may have empty id when offline).
  /// Null for the salida flow when there is no local record yet.
  final AttendanceRecord? record;

  /// Local queue row ID. Used to attach photo to this record.
  final int? localQueueId;

  /// [true] when the underlying ingreso record hasn't reached the server yet.
  final bool isOffline;
}

/// Photo write to queue / disk in progress.
final class FichajeUploadingPhoto extends FichajeState {
  const FichajeUploadingPhoto({
    required this.operario,
  });

  final Operario operario;
}

/// Flow complete from the supervisor's perspective.
/// The sync service will replay to the backend when online.
final class FichajeDone extends FichajeState {
  const FichajeDone({
    required this.operario,
    required this.mode,
    this.serverAttendanceId,
  });

  final Operario operario;

  /// Which phase completed.
  final FichajeMode mode;

  /// Server-side attendance ID if known — used to unlock the overtime button
  /// in the salida-done view.
  final String? serverAttendanceId;
}

/// A recoverable error. [previous] holds the state before the error so the UI
/// can offer a retry.
final class FichajeError extends FichajeState {
  const FichajeError({required this.message, required this.previous});

  final String message;
  final FichajeState previous;
}
