import 'package:dio/dio.dart';

import '../domain/attendance_record.dart';
import '../domain/attendance_repository.dart';
import '../domain/gps_position.dart';
import '../domain/operario.dart';
import 'attendance_dto.dart';

/// Adapter (hexagonal) — implements [AttendanceRepository] using [Dio].
///
/// The Dio instance already carries the Authorization: Bearer header via the
/// auth interceptor wired in [buildDioClient].
class AttendanceRepositoryImpl implements AttendanceRepository {
  AttendanceRepositoryImpl({required this.dio});

  final Dio dio;

  // ── Operarios ──────────────────────────────────────────────────────────────

  @override
  Future<List<Operario>> getOperarios() async {
    try {
      final response = await dio.get<List<dynamic>>('/iam/operarios');
      final list = response.data ?? [];
      return list
          .cast<Map<String, dynamic>>()
          .map(operarioFromJson)
          .toList();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final backendMessage = _extractMessage(e.response?.data);
      throw AttendanceException(
        backendMessage ?? 'No se pudo cargar la lista de operarios: ${e.message}',
        statusCode: status,
      );
    }
  }

  // ── Check-in ───────────────────────────────────────────────────────────────

  @override
  Future<AttendanceRecord> checkIn({
    required String operarioId,
    required String date,
    required DateTime capturedAt,
    required GpsPosition position,
    required String clientRef,
    String? verification,
  }) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/asistencia/check-in',
        data: {
          'operarioId': operarioId,
          'date': date,
          'checkInCapturedAt': capturedAt.toUtc().toIso8601String(),
          'checkInLat': position.latitude,
          'checkInLng': position.longitude,
          if (position.accuracy != null) 'checkInAccuracy': position.accuracy,
          'clientRef': clientRef,
          // AUDIT LABEL ONLY — no authorization logic may depend on this field.
          'verification': ?verification,
        },
      );

      return attendanceRecordFromJson(response.data!, clientRef: clientRef);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // Extract the backend's own message from the response body when present.
      final backendMessage = _extractMessage(e.response?.data);
      throw AttendanceException(
        backendMessage ?? 'Error al registrar la entrada: ${e.message}',
        statusCode: status,
      );
    }
  }

  // ── Photo upload ───────────────────────────────────────────────────────────

  @override
  Future<void> uploadPhoto({
    required String attendanceId,
    required List<int> photoBytes,
    required String phase,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          photoBytes,
          filename: 'photo.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
      });

      await dio.post<void>(
        '/asistencia/$attendanceId/photo',
        queryParameters: {'phase': phase},
        data: formData,
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final backendMessage = _extractMessage(e.response?.data);
      throw AttendanceException(
        backendMessage ?? 'No se pudo subir la foto: ${e.message}',
        statusCode: status,
      );
    }
  }

  // ── Check-out ──────────────────────────────────────────────────────────────

  @override
  Future<AttendanceRecord> checkOut({
    required String attendanceId,
    required DateTime capturedAt,
    required GpsPosition position,
    required String checkOutClientRef,
    String? verification,
  }) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/asistencia/$attendanceId/check-out',
        data: {
          'checkOutCapturedAt': capturedAt.toUtc().toIso8601String(),
          'checkOutLat': position.latitude,
          'checkOutLng': position.longitude,
          if (position.accuracy != null) 'checkOutAccuracy': position.accuracy,
          'checkOutClientRef': checkOutClientRef,
          // AUDIT LABEL ONLY — no authorization logic may depend on this field.
          'verification': ?verification,
        },
      );

      // The check-out response includes the full record; reuse the existing
      // clientRef stored in the record (passed through by the controller).
      // The DTO mapper reads it from the response; clientRef comes from
      // the check-in so we fall back to an empty string (never used for routing).
      final data = response.data!;
      // clientRef is set on check-in; the check-out response may not echo it.
      // The controller already holds the record — this returned value is used
      // to confirm completion (isComplete == true).
      final clientRefFromServer =
          data['clientRef'] as String? ?? checkOutClientRef;
      return attendanceRecordFromJson(data, clientRef: clientRefFromServer);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // Forward the backend's own error message. Do NOT hardcode 422 as
      // "photo missing" — the backend may send InvalidShiftDurationError,
      // AttendanceDateMismatchError, or PhotoRequiredError; each has a
      // distinct Spanish message that must be surfaced verbatim (Fixes 3+4+12).
      final backendMessage = _extractMessage(e.response?.data);
      throw AttendanceException(
        backendMessage ?? 'Error al registrar la salida: ${e.message}',
        statusCode: status,
      );
    }
  }

  // ── Recovery ───────────────────────────────────────────────────────────────

  @override
  Future<AttendanceRecord?> recoverByClientRef(String clientRef) async {
    try {
      final response = await dio.get<List<dynamic>>(
        '/asistencia',
        queryParameters: {'clientRef': clientRef},
      );
      final list = response.data ?? [];
      if (list.isEmpty) return null;
      final jsonData = list.first as Map<String, dynamic>;
      return attendanceRecordFromJson(jsonData, clientRef: clientRef);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // 404 (or empty list above) → record genuinely not found → return null
      // so the caller can decide it's a true duplicate.
      // Any other error (401, 5xx, network) → rethrow as AttendanceException
      // with statusCode so the sync service treats it as TRANSIENT (Fix 10).
      if (status == 404) return null;
      final backendMessage = _extractMessage(e.response?.data);
      throw AttendanceException(
        backendMessage ?? 'Error al recuperar el registro: ${e.message}',
        statusCode: status,
      );
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Extracts the human-readable `message` from a backend error response body.
  ///
  /// NestJS exception bodies use `{ "message": "...", "statusCode": N }` for
  /// plain exceptions, or `{ "message": ["...", "..."] }` for validation
  /// errors. Returns the first non-empty string found, or null.
  static String? _extractMessage(dynamic body) {
    if (body == null) return null;
    if (body is Map<String, dynamic>) {
      final msg = body['message'];
      if (msg is String && msg.isNotEmpty) return msg;
      if (msg is List && msg.isNotEmpty) {
        final first = msg.first;
        if (first is String && first.isNotEmpty) return first;
      }
    }
    return null;
  }

  @override
  Future<Map<String, ({String id, bool completed})>> todayAttendanceByOperario(
    String date,
  ) async {
    try {
      // Bound the query to today via ?since= (Colombia midnight as an instant),
      // then filter by the authoritative `date` field client-side.
      final response = await dio.get<List<dynamic>>(
        '/asistencia',
        queryParameters: {'since': '${date}T00:00:00-05:00'},
      );
      final list = response.data ?? [];
      final byOperario = <String, ({String id, bool completed})>{};
      for (final item in list) {
        final json = item as Map<String, dynamic>;
        if (json['date'] == date) {
          byOperario[json['operarioId'] as String] = (
            id: json['id'] as String,
            // completed once the salida (check-out) was registered.
            completed: json['completedAt'] != null,
          );
        }
      }
      return byOperario;
    } on DioException catch (e) {
      throw AttendanceException(
        'No se pudieron cargar los registros de hoy: ${e.message}',
      );
    }
  }
}
