import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:futuragest_mobile/core/config/app_config.dart';
import 'package:futuragest_mobile/core/push/push_messaging_service.dart'
    show pushNavigatorKey;
import 'package:futuragest_mobile/core/storage/token_storage.dart';

/// Builds and returns the singleton [Dio] instance used across the app.
///
/// Interceptors (order matters):
///  1. [_AuthInterceptor]    – attaches `Authorization: Bearer <accessToken>`.
///  2. [_RefreshInterceptor] – on 401, transparently refreshes the access token
///     via POST /auth/refresh and retries the original request. The access
///     token is short-lived (15 min); without this, a supervisor working a full
///     shift (ingreso → salida hours apart) would be rejected on every call
///     after the first 15 minutes.
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
  dio.interceptors.add(_RefreshInterceptor(storage: storage, dio: dio));

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

/// Marker placed on a request that has already been retried after a refresh, so
/// a second 401 does not trigger an infinite refresh loop.
const _retriedFlag = '__refresh_retried__';

/// Catches 401s, refreshes the access token once (single-flight), and retries
/// the failed request with the new token. On refresh failure the session is
/// dead: tokens are cleared and the app is sent back to login.
class _RefreshInterceptor extends Interceptor {
  _RefreshInterceptor({required TokenStorage storage, required Dio dio})
      : _storage = storage, // ignore: prefer_initializing_formals
        _dio = dio; // ignore: prefer_initializing_formals

  final TokenStorage _storage;
  final Dio _dio;

  /// In-flight refresh shared by all requests that 401 concurrently. Resolves
  /// to the new access token, or null when the refresh failed.
  Future<String?>? _refreshing;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final path = options.path;
    final isAuthRoute =
        path.contains('/auth/refresh') || path.contains('/auth/login');
    final alreadyRetried = options.extra[_retriedFlag] == true;

    // Only act on 401s from protected routes that haven't already been retried.
    if (err.response?.statusCode != 401 || isAuthRoute || alreadyRetried) {
      handler.next(err);
      return;
    }

    final newToken = await _refreshSingleFlight();
    if (newToken == null) {
      // Refresh failed → session is dead (clear + redirect already handled).
      handler.next(err);
      return;
    }

    // Retry the original request once with the fresh token.
    try {
      options.extra[_retriedFlag] = true;
      options.headers['Authorization'] = 'Bearer $newToken';
      final response = await _dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (retryErr) {
      handler.next(retryErr);
    }
  }

  /// Ensures only one /auth/refresh is in flight at a time. Concurrent 401s
  /// await the same future.
  Future<String?> _refreshSingleFlight() {
    return _refreshing ??=
        _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<String?> _doRefresh() async {
    final refreshToken = await _storage.readRefreshToken();
    final deviceId = await _storage.readDeviceId();
    final accessToken = await _storage.readAccessToken();

    final userId = accessToken != null ? _decodeSub(accessToken) : null;
    if (refreshToken == null || deviceId == null || userId == null) {
      await _failSession();
      return null;
    }

    try {
      // A bare Dio (no interceptors) so the refresh call can't recurse.
      final refreshDio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          headers: {'Content-Type': 'application/json'},
        ),
      );

      final resp = await refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {
          'userId': userId,
          'deviceId': deviceId,
          'refreshToken': refreshToken,
        },
      );

      final newAccess = resp.data?['accessToken'] as String?;
      if (newAccess == null || newAccess.isEmpty) {
        await _failSession();
        return null;
      }

      await _storage.saveAccessToken(newAccess);
      return newAccess;
    } on DioException {
      // Refresh token revoked/expired (401) or network failure → dead session.
      await _failSession();
      return null;
    }
  }

  /// Clears the session tokens (preserving device_id — Fix 2) and navigates
  /// to /login when the app is in the foreground.
  ///
  /// Background sync can trigger _failSession while the app is not resumed;
  /// in that case the tokens are cleared but navigation is skipped so it
  /// happens naturally when the user next opens the app.
  Future<void> _failSession() async {
    // Preserve device_id — only delete auth tokens + session owner (Fix 2).
    await _storage.clearSession();

    // Only navigate when the app is in the foreground (Fix 9).
    // A null lifecycle state is treated as resumed (conservative).
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final isForeground =
        lifecycle == null || lifecycle == AppLifecycleState.resumed;
    if (isForeground) {
      pushNavigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/login',
        (route) => false,
      );
    }
  }

  /// Decodes the `sub` (userId) claim from a JWT without verifying the
  /// signature. The token may be expired — we only need the subject to refresh.
  String? _decodeSub(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      final payload = json.decode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      return payload['sub'] as String?;
    } catch (_) {
      return null;
    }
  }
}
