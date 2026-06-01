/// The server-side attendance record returned after a successful check-in.
///
/// The [id] is the server-assigned primary key required for subsequent
/// signature upload and check-out requests.
class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.operarioId,
    required this.date,
    required this.clientRef,
    required this.checkInCapturedAt,
    required this.checkInLat,
    required this.checkInLng,
    this.checkInAccuracy,
    this.signatureUploaded = false,
    this.checkOutCapturedAt,
    this.checkOutLat,
    this.checkOutLng,
    this.checkOutAccuracy,
    this.completedAt,
  });

  /// Server-assigned attendance ID (used for /signature and /check-out).
  final String id;

  final String operarioId;

  /// Colombia-local date "YYYY-MM-DD".
  final String date;

  /// Client-generated uuid v4 for idempotency (reused by STEP 2 offline queue).
  final String clientRef;

  final DateTime checkInCapturedAt;
  final double checkInLat;
  final double checkInLng;
  final double? checkInAccuracy;

  /// Whether the signature has been uploaded to the server.
  final bool signatureUploaded;

  final DateTime? checkOutCapturedAt;
  final double? checkOutLat;
  final double? checkOutLng;
  final double? checkOutAccuracy;

  /// Non-null once the server confirms check-out is complete.
  final DateTime? completedAt;

  bool get isComplete => completedAt != null;

  AttendanceRecord copyWith({
    bool? signatureUploaded,
    DateTime? checkOutCapturedAt,
    double? checkOutLat,
    double? checkOutLng,
    double? checkOutAccuracy,
    DateTime? completedAt,
  }) {
    return AttendanceRecord(
      id: id,
      operarioId: operarioId,
      date: date,
      clientRef: clientRef,
      checkInCapturedAt: checkInCapturedAt,
      checkInLat: checkInLat,
      checkInLng: checkInLng,
      checkInAccuracy: checkInAccuracy,
      signatureUploaded: signatureUploaded ?? this.signatureUploaded,
      checkOutCapturedAt: checkOutCapturedAt ?? this.checkOutCapturedAt,
      checkOutLat: checkOutLat ?? this.checkOutLat,
      checkOutLng: checkOutLng ?? this.checkOutLng,
      checkOutAccuracy: checkOutAccuracy ?? this.checkOutAccuracy,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}
