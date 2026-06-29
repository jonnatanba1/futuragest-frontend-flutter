import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keys for values persisted in the secure keychain / keystore.
abstract class _Keys {
  static const accessToken = 'access_token';
  static const refreshToken = 'refresh_token';
  static const deviceId = 'device_id';
  /// Stores the subject (userId) of the last authenticated user.
  /// Used at login to detect a user switch and wipe the offline queue.
  static const sessionOwner = 'session_owner';
}

/// Wraps [FlutterSecureStorage] to provide typed read/write/clear helpers
/// for JWT tokens and the stable device identifier.
class TokenStorage {
  TokenStorage() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      // If reading fails (usually BAD_DECRYPT), wipe storage.
      // We must catch errors here too because deleteAll() can also throw.
      try {
        await _storage.deleteAll();
      } catch (_) {}
      return null;
    }
  }

  Future<void> _safeWrite(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {
      try {
        await _storage.deleteAll();
      } catch (_) {}
      
      try {
        await _storage.write(key: key, value: value);
      } catch (_) {}
    }
  }

  // ── Access token ───────────────────────────────────────────────────────────

  Future<void> saveAccessToken(String token) =>
      _safeWrite(_Keys.accessToken, token);

  Future<String?> readAccessToken() => _safeRead(_Keys.accessToken);

  // ── Refresh token ──────────────────────────────────────────────────────────

  Future<void> saveRefreshToken(String token) =>
      _safeWrite(_Keys.refreshToken, token);

  Future<String?> readRefreshToken() => _safeRead(_Keys.refreshToken);

  // ── Device ID ──────────────────────────────────────────────────────────────

  Future<void> saveDeviceId(String id) =>
      _safeWrite(_Keys.deviceId, id);

  Future<String?> readDeviceId() => _safeRead(_Keys.deviceId);

  // ── Session owner ──────────────────────────────────────────────────────────

  Future<void> saveSessionOwner(String userId) =>
      _safeWrite(_Keys.sessionOwner, userId);

  Future<String?> readSessionOwner() => _safeRead(_Keys.sessionOwner);

  // ── Clear session ──────────────────────────────────────────────────────────

  /// Deletes auth-related keys (tokens + session owner) while PRESERVING
  /// [_Keys.deviceId] so the stable device identifier survives logout and
  /// session expiry. Use this everywhere instead of a blanket deleteAll().
  Future<void> clearSession() async {
    try {
      await _storage.delete(key: _Keys.accessToken);
      await _storage.delete(key: _Keys.refreshToken);
      await _storage.delete(key: _Keys.sessionOwner);
    } catch (_) {
      try {
        await _storage.deleteAll();
      } catch (_) {}
    }
  }
}
