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
      throw AttendanceException(
        'No se pudo cargar la lista de operarios: ${e.message}',
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
          if (position.accuracy != null)
            'checkInAccuracy': position.accuracy,
          'clientRef': clientRef,
        },
      );

      return attendanceRecordFromJson(response.data!, clientRef: clientRef);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 409) {
        throw const AttendanceException(
          'Este operario ya tiene un registro de entrada para hoy.',
        );
      }
      throw AttendanceException(
        'Error al registrar la entrada: ${e.message}',
      );
    }
  }

  // ── Signature upload ───────────────────────────────────────────────────────

  @override
  Future<void> uploadSignature({
    required String attendanceId,
    required List<int> signaturePngBytes,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          signaturePngBytes,
          filename: 'signature.png',
          contentType: DioMediaType('image', 'png'),
        ),
      });

      await dio.post<void>(
        '/asistencia/$attendanceId/signature',
        data: formData,
      );
    } on DioException catch (e) {
      throw AttendanceException(
        'No se pudo subir la firma: ${e.message}',
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
  }) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/asistencia/$attendanceId/check-out',
        data: {
          'checkOutCapturedAt': capturedAt.toUtc().toIso8601String(),
          'checkOutLat': position.latitude,
          'checkOutLng': position.longitude,
          if (position.accuracy != null)
            'checkOutAccuracy': position.accuracy,
          'checkOutClientRef': checkOutClientRef,
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
      if (status == 422) {
        throw const AttendanceException(
          'Debe subir la firma del operario antes de registrar la salida.',
        );
      }
      throw AttendanceException(
        'Error al registrar la salida: ${e.message}',
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
      final json = list.first as Map<String, dynamic>;
      return attendanceRecordFromJson(json, clientRef: clientRef);
    } on DioException catch (_) {
      // If the recovery request itself fails, return null so the sync
      // service retries on the next cycle.
      return null;
    }
  }
}
