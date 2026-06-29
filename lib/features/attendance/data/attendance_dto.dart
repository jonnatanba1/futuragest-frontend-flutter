import '../domain/attendance_record.dart';
import '../domain/operario.dart';

// ── Operario ───────────────────────────────────────────────────────────────

/// Maps a raw JSON object from GET /iam/operarios to an [Operario].
Operario operarioFromJson(Map<String, dynamic> json) {
  return Operario(
    id: json['id'] as String,
    fullName: json['fullName'] as String,
    documento: json['documento'] as String,
    active: json['active'] as bool? ?? true,
  );
}

// ── AttendanceRecord ───────────────────────────────────────────────────────

/// Maps the JSON body returned by POST /asistencia/check-in (201/200)
/// or POST /asistencia/:id/check-out (200) to an [AttendanceRecord].
///
/// The backend response shape for check-in:
///   { id, operarioId, date, clientRef, checkInCapturedAt, checkInLat,
///     checkInLng, checkInAccuracy?, checkInPhotoKey?, completedAt?, ... }
AttendanceRecord attendanceRecordFromJson(
  Map<String, dynamic> json, {
  required String clientRef,
}) {
  DateTime? completedAt;
  if (json['completedAt'] != null) {
    completedAt = DateTime.tryParse(json['completedAt'] as String);
  }

  DateTime? checkOutCapturedAt;
  if (json['checkOutCapturedAt'] != null) {
    checkOutCapturedAt =
        DateTime.tryParse(json['checkOutCapturedAt'] as String);
  }

  return AttendanceRecord(
    id: json['id'] as String,
    operarioId: json['operarioId'] as String,
    date: json['date'] as String,
    clientRef: clientRef,
    checkInCapturedAt:
        DateTime.parse(json['checkInCapturedAt'] as String),
    checkInLat: (json['checkInLat'] as num).toDouble(),
    checkInLng: (json['checkInLng'] as num).toDouble(),
    checkInAccuracy: json['checkInAccuracy'] != null
        ? (json['checkInAccuracy'] as num).toDouble()
        : null,
    // photoUploaded is inferred from checkInPhotoKey presence in the response.
    photoUploaded: json['checkInPhotoKey'] != null,
    checkOutCapturedAt: checkOutCapturedAt,
    checkOutLat: json['checkOutLat'] != null
        ? (json['checkOutLat'] as num).toDouble()
        : null,
    checkOutLng: json['checkOutLng'] != null
        ? (json['checkOutLng'] as num).toDouble()
        : null,
    checkOutAccuracy: json['checkOutAccuracy'] != null
        ? (json['checkOutAccuracy'] as num).toDouble()
        : null,
    completedAt: completedAt,
  );
}
