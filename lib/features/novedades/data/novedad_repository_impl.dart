import 'package:dio/dio.dart';

import '../domain/novedad.dart';
import '../domain/novedad_repository.dart' show NovedadRepository, NovedadException, NovedadAlreadyDecidedException;
import 'novedad_dto.dart';

/// Adapter (hexagonal) — implements [NovedadRepository] using [Dio].
///
/// The Dio instance already carries the Authorization: Bearer header via the
/// auth interceptor wired in [buildDioClient].
class NovedadRepositoryImpl implements NovedadRepository {
  NovedadRepositoryImpl({required this.dio});

  final Dio dio;

  // ── Create novedad ─────────────────────────────────────────────────────────

  @override
  Future<Novedad> createNovedad({
    required String attendanceId,
    required String horasExtra,
    required String clientRef,
    String? motivo,
  }) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/asistencia/$attendanceId/novedades',
        data: {
          'horasExtra': horasExtra,
          'clientRef': clientRef,
          if (motivo != null && motivo.isNotEmpty) 'motivo': motivo,
        },
      );
      return novedadFromJson(response.data!);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      // Try to extract a backend message first, then fall back to generic text.
      final backendMsg = _extractBackendMessage(body);

      if (status == 409) {
        throw NovedadException(
          backendMsg ??
              'Ya existe una novedad activa (pendiente o aprobada) para esta asistencia.',
        );
      }
      if (status == 400) {
        throw NovedadException(
          backendMsg ??
              'Horas extra inválidas. Ingresá un valor entre 0.01 y 24.',
        );
      }
      if (status == 404) {
        throw NovedadException(
          backendMsg ?? 'Registro de asistencia no encontrado.',
        );
      }
      throw NovedadException(
        'Error al registrar la novedad: ${e.message}',
      );
    }
  }

  // ── List novedades ─────────────────────────────────────────────────────────

  @override
  Future<List<Novedad>> listNovedades() async {
    try {
      final response = await dio.get<List<dynamic>>('/novedades');
      final list = response.data ?? [];
      return list.cast<Map<String, dynamic>>().map(novedadFromJson).toList();
    } on DioException catch (e) {
      throw NovedadException(
        'No se pudieron cargar las novedades: ${e.message}',
      );
    }
  }

  // ── Get single novedad ─────────────────────────────────────────────────────

  @override
  Future<Novedad> getNovedad(String id) async {
    try {
      final response = await dio.get<Map<String, dynamic>>('/novedades/$id');
      return novedadFromJson(response.data!);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 404) {
        throw const NovedadException('Novedad no encontrada.');
      }
      throw NovedadException('Error al obtener la novedad: ${e.message}');
    }
  }

  // ── Approve novedad ────────────────────────────────────────────────────────

  @override
  Future<void> approveNovedad(String id) async {
    await _decideNovedad(id, 'approve');
  }

  // ── Reject novedad ─────────────────────────────────────────────────────────

  @override
  Future<void> rejectNovedad(String id) async {
    await _decideNovedad(id, 'reject');
  }

  Future<void> _decideNovedad(String id, String action) async {
    try {
      await dio.patch<void>('/novedades/$id/$action');
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      final backendMsg = _extractBackendMessage(body);

      if (status == 409) {
        throw NovedadAlreadyDecidedException(
          backendMsg ??
              'Esta novedad ya fue decidida (aprobada o rechazada) anteriormente.',
        );
      }
      if (status == 404) {
        throw NovedadException(backendMsg ?? 'Novedad no encontrada.');
      }
      if (status == 403) {
        throw NovedadException(
          backendMsg ?? 'No tenés permiso para realizar esta acción.',
        );
      }
      throw NovedadException(
        'Error al ${action == 'approve' ? 'aprobar' : 'rechazar'} la novedad: ${e.message}',
      );
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String? _extractBackendMessage(dynamic body) {
    if (body is Map<String, dynamic>) {
      final msg = body['message'];
      if (msg is String && msg.isNotEmpty) return msg;
      if (msg is List && msg.isNotEmpty) return msg.first as String?;
    }
    return null;
  }
}
