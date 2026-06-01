import 'package:dio/dio.dart';

import '../../../core/storage/token_storage.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_session.dart';
import '../domain/user_profile.dart';
import 'auth_dto.dart';

/// Adapter (hexagonal) — implements [AuthRepository] using [Dio] for HTTP
/// and [TokenStorage] for persisting JWT tokens.
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({required this.dio, required this.storage});

  final Dio dio;
  final TokenStorage storage;

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
    required String deviceId,
  }) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {
          'email': email,
          'password': password,
          'deviceId': deviceId,
        },
      );

      final data = response.data!;
      final session = AuthSession(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
        passwordChangeRequired:
            data['passwordChangeRequired'] as bool? ?? false,
      );

      // Persist tokens immediately so the interceptor picks them up for /me.
      await storage.saveAccessToken(session.accessToken);
      await storage.saveRefreshToken(session.refreshToken);

      return session;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const AuthException('Credenciales inválidas');
      }
      throw AuthException('Error de red: ${e.message}');
    }
  }

  @override
  Future<UserProfile> getMe() async {
    try {
      final response = await dio.get<Map<String, dynamic>>('/auth/me');
      return userProfileFromJson(response.data!);
    } on DioException catch (e) {
      throw AuthException('No se pudo obtener el perfil: ${e.message}');
    }
  }

  @override
  Future<void> registerPushToken({
    required String pushToken,
    String? pushPlatform,
  }) async {
    // TODO(push): next slice — obtain the real FCM token via firebase_messaging
    //             (add firebase_messaging dep + google-services.json / GoogleService-Info.plist)
    //             and call this method from a post-login service hook.
    try {
      await dio.post<void>(
        '/auth/push-token',
        data: {
          'pushToken': pushToken,
          'pushPlatform': pushPlatform,
        },
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 400) {
        throw const AuthException('Token de notificaciones inválido.');
      }
      if (status == 401) {
        throw const AuthException(
          'No autenticado. Iniciá sesión nuevamente.',
        );
      }
      throw AuthException(
        'Error al registrar el token de notificaciones: ${e.message}',
      );
    }
  }

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      await dio.post<void>(
        '/auth/change-password',
        data: {
          'oldPassword': oldPassword,
          'newPassword': newPassword,
        },
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      final body = e.response?.data;
      final backendMsg = _extractBackendMessage(body);

      if (status == 400) {
        throw AuthException(
          backendMsg ?? 'La contraseña nueva no cumple los requisitos mínimos.',
        );
      }
      if (status == 401) {
        throw AuthException(
          backendMsg ?? 'La contraseña actual es incorrecta.',
        );
      }
      throw AuthException('Error al cambiar la contraseña: ${e.message}');
    }
  }

  String? _extractBackendMessage(dynamic body) {
    if (body is Map<String, dynamic>) {
      final msg = body['message'];
      if (msg is String && msg.isNotEmpty) return msg;
      if (msg is List && msg.isNotEmpty) return msg.first as String?;
    }
    return null;
  }
}
