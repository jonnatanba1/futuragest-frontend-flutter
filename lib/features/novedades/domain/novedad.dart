/// Status of an overtime novedad as returned by the backend.
enum NovedadStatus {
  pending,
  approved,
  rejected,
}

/// Domain entity representing a supervisor overtime record (novedad de horas extra).
///
/// [horasExtra] is kept as a string because the backend serialises Prisma
/// Decimal as a string (e.g. "2.5"). Parse to double only for display/validation.
class Novedad {
  const Novedad({
    required this.id,
    required this.attendanceId,
    required this.supervisorId,
    required this.horasExtra,
    required this.status,
    required this.createdAt,
    this.motivo,
    this.zoneId,
    this.approvedByUserId,
    this.decidedAt,
    this.clientRef,
  });

  /// Server-assigned primary key.
  final String id;

  /// The attendance record this novedad is attached to.
  final String attendanceId;

  final String supervisorId;

  /// Decimal overtime hours as a string (Prisma Decimal → JSON string).
  /// Examples: "2.5", "1.0", "0.5".
  final String horasExtra;

  final NovedadStatus status;
  final DateTime createdAt;

  /// Optional reason provided by the supervisor.
  final String? motivo;

  final String? zoneId;

  /// The user (LIDER_OPERATIVO) who approved/rejected this novedad.
  final String? approvedByUserId;

  /// When the approval/rejection decision was made.
  final DateTime? decidedAt;

  /// Client-generated uuid v4 for idempotency (same pattern as fichaje).
  final String? clientRef;

  /// Parses [horasExtra] string to a double for display.
  /// Returns null if the string is not a valid number.
  double? get horasExtraDouble => double.tryParse(horasExtra);
}
