import '../domain/novedad.dart';

/// Maps a raw JSON object from the backend NovedadDto to a [Novedad] entity.
///
/// Backend shape:
///   { id, attendanceId, supervisorId, zoneId, horasExtra (string),
///     motivo (string|null), status ("PENDING"|"APPROVED"|"REJECTED"),
///     approvedByUserId (string|null), decidedAt (ISO|null),
///     clientRef (string|null), createdAt (ISO), updatedAt (ISO) }
Novedad novedadFromJson(Map<String, dynamic> json) {
  return Novedad(
    id: json['id'] as String,
    attendanceId: json['attendanceId'] as String,
    supervisorId: json['supervisorId'] as String,
    zoneId: json['zoneId'] as String?,
    // horasExtra arrives as a decimal string from Prisma — keep it as string.
    horasExtra: json['horasExtra'] as String,
    motivo: json['motivo'] as String?,
    status: _statusFromString(json['status'] as String),
    approvedByUserId: json['approvedByUserId'] as String?,
    decidedAt: json['decidedAt'] != null
        ? DateTime.tryParse(json['decidedAt'] as String)
        : null,
    clientRef: json['clientRef'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

NovedadStatus _statusFromString(String raw) {
  switch (raw.toUpperCase()) {
    case 'APPROVED':
      return NovedadStatus.approved;
    case 'REJECTED':
      return NovedadStatus.rejected;
    case 'PENDING':
    default:
      return NovedadStatus.pending;
  }
}
