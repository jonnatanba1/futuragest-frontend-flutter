import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/auth_repository.dart';
import 'auth_providers.dart';

/// Service that registers / unregisters the FCM push token with the backend.
///
/// [register] is driven by [PushMessagingService] after login and on token
/// refresh; [unregister] is driven by the logout flow so the backend stops
/// targeting the device. Both methods are failure-safe: errors are swallowed
/// and logged so a push-token failure never blocks the auth flow.
class PushTokenService {
  PushTokenService(this._repository);

  final AuthRepository _repository;

  /// Registers [pushToken] with the backend.
  ///
  /// This is a no-op-safe call: errors are swallowed and logged so that a
  /// push-token failure never blocks the login flow.
  ///
  /// [pushPlatform] should be "android" or "ios" when known.
  Future<void> register(String pushToken, {String? pushPlatform}) async {
    try {
      await _repository.registerPushToken(
        pushToken: pushToken,
        pushPlatform: pushPlatform,
      );
    } on AuthException catch (e) {
      // Non-fatal: push token registration failure must never interrupt auth.
      // Log and swallow — the caller (PushMessagingService) also wraps in try/catch.
      dev.log(
        '[PushTokenService] registerPushToken failed (non-fatal): $e',
        name: 'push',
      );
    }
  }

  /// Clears the backend push token for the caller's current device session.
  ///
  /// Failure-safe: errors are swallowed and logged so a failure never blocks
  /// the logout flow.
  Future<void> unregister() async {
    try {
      await _repository.unregisterPushToken();
    } on AuthException catch (e) {
      dev.log(
        '[PushTokenService] unregisterPushToken failed (non-fatal): $e',
        name: 'push',
      );
    }
  }
}

/// Provider for [PushTokenService].
final pushTokenServiceProvider = Provider<PushTokenService>((ref) {
  return PushTokenService(ref.watch(authRepositoryProvider));
});
