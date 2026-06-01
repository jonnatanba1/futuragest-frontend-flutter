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
}
