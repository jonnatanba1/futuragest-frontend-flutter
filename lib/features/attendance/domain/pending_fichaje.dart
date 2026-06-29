import 'gps_position.dart';

/// Status of a queued fichaje intent.
///
/// Transitions (happy path):
///   pendingCheckIn
///     → checkedIn          (check-in POST succeeded, server id recovered)
///     → ingresoComplete    (entry photo uploaded)
///     → salidaSigned       (exit photo uploaded)
///     → completed          (check-out POST succeeded)
///
/// ingresoComplete is a RESTING state: the row stays here until the salida
/// phase is captured (hours later in the day).
///
/// Any step can transition to [failed] on a non-transient error.
///
/// NOTE: The Dart symbol [salidaSigned] is intentionally preserved because
/// the string value 'salidaSigned' is persisted in SQLite rows. Renaming the
/// persisted value would break existing queue rows on upgrade.
enum FichajeQueueStatus {
  /// Check-in has not been POSTed yet (or the POST failed and needs retry).
  pendingCheckIn,

  /// Check-in succeeded; server ID stored. Waiting for entry photo upload.
  checkedIn,

  /// Entry (ingreso) photo uploaded. Resting until salida is captured.
  ingresoComplete,

  /// Exit (salida) photo uploaded. Ready for check-out POST.
  /// The persisted string value 'salidaSigned' is kept stable for backward
  /// compatibility with existing SQLite rows from schema v3.
  salidaSigned,

  /// All steps completed successfully on the backend.
  completed,

  /// A non-recoverable error occurred.
  failed,
}

/// A full fichaje intent stored in the local offline queue.
///
/// Created offline-first; replayed to the backend when connectivity returns.
/// The backend is idempotent on [clientRef] (check-in) and [checkOutClientRef]
/// (check-out), so replay is safe.
class PendingFichaje {
  const PendingFichaje({
    required this.localId,
    required this.operarioId,
    required this.operarioName,
    required this.date,
    required this.clientRef,
    required this.checkInCapturedAt,
    required this.checkInGps,
    required this.status,
    this.checkInPhotoPath,
    this.checkOutPhotoPath,
    this.checkOutClientRef,
    this.checkOutCapturedAt,
    this.checkOutGps,
    this.serverAttendanceId,
    this.failureReason,
    this.createdAt,
    this.checkInVerification,
    this.checkOutVerification,
  });

  /// Auto-incremented local primary key (SQLite row ID).
  final int localId;

  final String operarioId;

  /// Stored for display purposes (operario name at time of capture).
  final String operarioName;

  /// Colombia-local date "YYYY-MM-DD".
  final String date;

  // ── Check-in ───────────────────────────────────────────────────────────────

  /// Client-generated uuid v4; backend dedupes check-in on this.
  final String clientRef;

  final DateTime checkInCapturedAt;
  final GpsPosition checkInGps;

  // ── Ingreso (entry) photo ──────────────────────────────────────────────────

  /// Absolute path to the entry photo file in app documents directory.
  /// Null until the supervisor captures the photo at ingreso.
  final String? checkInPhotoPath;

  // ── Salida (exit) photo ────────────────────────────────────────────────────

  /// Absolute path to the exit photo file in app documents directory.
  /// Null until the supervisor captures the photo at salida.
  final String? checkOutPhotoPath;

  // ── Check-out ──────────────────────────────────────────────────────────────

  /// Client-generated uuid v4 for the check-out; backend dedupes on this.
  final String? checkOutClientRef;

  final DateTime? checkOutCapturedAt;
  final GpsPosition? checkOutGps;

  // ── Sync state ─────────────────────────────────────────────────────────────

  /// Server-assigned attendance ID. Populated after a successful check-in POST
  /// (or recovered via GET /asistencia?clientRef=).
  final String? serverAttendanceId;

  final FichajeQueueStatus status;

  /// Non-null when [status] == [FichajeQueueStatus.failed].
  final String? failureReason;

  /// UTC timestamp when this record was first enqueued.
  final DateTime? createdAt;

  // ── Audit: verification method (AUDIT LABEL ONLY) ──────────────────────────
  // No authorization logic may depend on these fields.

  /// Audit label for the check-in biometric confirmation method.
  /// 'BIOMETRIC' | 'DEVICE_CREDENTIAL' | 'NONE' | null (legacy rows).
  final String? checkInVerification;

  /// Audit label for the check-out biometric confirmation method.
  /// 'BIOMETRIC' | 'DEVICE_CREDENTIAL' | 'NONE' | null (legacy rows).
  final String? checkOutVerification;

  PendingFichaje copyWith({
    String? checkInPhotoPath,
    String? checkOutPhotoPath,
    String? checkOutClientRef,
    DateTime? checkOutCapturedAt,
    GpsPosition? checkOutGps,
    String? serverAttendanceId,
    FichajeQueueStatus? status,
    String? failureReason,
    String? checkInVerification,
    String? checkOutVerification,
  }) {
    return PendingFichaje(
      localId: localId,
      operarioId: operarioId,
      operarioName: operarioName,
      date: date,
      clientRef: clientRef,
      checkInCapturedAt: checkInCapturedAt,
      checkInGps: checkInGps,
      checkInPhotoPath: checkInPhotoPath ?? this.checkInPhotoPath,
      checkOutPhotoPath: checkOutPhotoPath ?? this.checkOutPhotoPath,
      checkOutClientRef: checkOutClientRef ?? this.checkOutClientRef,
      checkOutCapturedAt: checkOutCapturedAt ?? this.checkOutCapturedAt,
      checkOutGps: checkOutGps ?? this.checkOutGps,
      serverAttendanceId: serverAttendanceId ?? this.serverAttendanceId,
      status: status ?? this.status,
      failureReason: failureReason ?? this.failureReason,
      createdAt: createdAt,
      checkInVerification: checkInVerification ?? this.checkInVerification,
      checkOutVerification: checkOutVerification ?? this.checkOutVerification,
    );
  }
}
