import 'package:dio/dio.dart';
import 'package:futuragest_mobile/core/config/app_config.dart';
import 'package:futuragest_mobile/core/storage/token_storage.dart';

/// Builds and returns the singleton [Dio] instance used across the app.
///
/// Interceptors:
///  1. [_AuthInterceptor] – attaches `Authorization: Bearer <token>` when a
///     stored access token exists.
///
/// TODO: Add a refresh interceptor that:
///  – Catches 401 responses on non-auth endpoints.
///  – POSTs to /auth/refresh with the stored refreshToken.
///  – Retries the original request with the new accessToken.
///  – Calls [TokenStorage.clearAll] and redirects to login on refresh failure.
Dio buildDioClient(TokenStorage storage) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  dio.interceptors.add(_AuthInterceptor(storage));

  return dio;
}

/// Reads the stored access token before each request and injects it as a
/// Bearer token in the Authorization header when present.
class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._storage);

  final TokenStorage _storage;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _storage.readAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}
