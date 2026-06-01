import 'gps_position.dart';

/// Status of a queued fichaje intent.
///
/// Transitions (happy path):
///   pendingCheckIn
///     → checkedInPendingSignature   (check-in POST succeeded, server id recovered)
///     → signedPendingCheckOut       (signature POST succeeded)
///     → completed                   (check-out POST succeeded)
///
/// Any step can transition to [failed].
enum FichajeQueueStatus {
  /// Check-in has not been POSTed yet (or the POST failed and needs retry).
  pendingCheckIn,

  /// Check-in succeeded; server ID stored. Waiting for signature upload.
  checkedInPendingSignature,

  /// Signature uploaded. Ready for check-out POST.
  signedPendingCheckOut,

  /// All three steps completed successfully on the backend.
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
    this.signaturePngPath,
    this.checkOutClientRef,
    this.checkOutCapturedAt,
    this.checkOutGps,
    this.serverAttendanceId,
    this.failureReason,
    this.createdAt,
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

  // ── Signature ──────────────────────────────────────────────────────────────

  /// Absolute path to the signature PNG file in app documents directory.
  /// Null until the supervisor captures the signature.
  final String? signaturePngPath;

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

  PendingFichaje copyWith({
    String? signaturePngPath,
    String? checkOutClientRef,
    DateTime? checkOutCapturedAt,
    GpsPosition? checkOutGps,
    String? serverAttendanceId,
    FichajeQueueStatus? status,
    String? failureReason,
  }) {
    return PendingFichaje(
      localId: localId,
      operarioId: operarioId,
      operarioName: operarioName,
      date: date,
      clientRef: clientRef,
      checkInCapturedAt: checkInCapturedAt,
      checkInGps: checkInGps,
      signaturePngPath: signaturePngPath ?? this.signaturePngPath,
      checkOutClientRef: checkOutClientRef ?? this.checkOutClientRef,
      checkOutCapturedAt: checkOutCapturedAt ?? this.checkOutCapturedAt,
      checkOutGps: checkOutGps ?? this.checkOutGps,
      serverAttendanceId: serverAttendanceId ?? this.serverAttendanceId,
      status: status ?? this.status,
      failureReason: failureReason ?? this.failureReason,
      createdAt: createdAt,
    );
  }
}
