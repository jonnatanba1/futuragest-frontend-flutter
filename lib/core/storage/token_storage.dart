import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keys for values persisted in the secure keychain / keystore.
abstract class _Keys {
  static const accessToken = 'access_token';
  static const refreshToken = 'refresh_token';
  static const deviceId = 'device_id';
}

/// Wraps [FlutterSecureStorage] to provide typed read/write/clear helpers
/// for JWT tokens and the stable device identifier.
class TokenStorage {
  TokenStorage() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  // ── Access token ───────────────────────────────────────────────────────────

  Future<void> saveAccessToken(String token) =>
      _storage.write(key: _Keys.accessToken, value: token);

  Future<String?> readAccessToken() =>
      _storage.read(key: _Keys.accessToken);

  // ── Refresh token ──────────────────────────────────────────────────────────

  Future<void> saveRefreshToken(String token) =>
      _storage.write(key: _Keys.refreshToken, value: token);

  Future<String?> readRefreshToken() =>
      _storage.read(key: _Keys.refreshToken);

  // ── Device ID ──────────────────────────────────────────────────────────────

  Future<void> saveDeviceId(String id) =>
      _storage.write(key: _Keys.deviceId, value: id);

  Future<String?> readDeviceId() => _storage.read(key: _Keys.deviceId);

  // ── Clear all ──────────────────────────────────────────────────────────────

  Future<void> clearAll() => _storage.deleteAll();
}
