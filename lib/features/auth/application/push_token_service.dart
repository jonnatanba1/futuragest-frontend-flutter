import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/auth_repository.dart';
import 'auth_providers.dart';

/// Service that registers a FCM push token with the backend.
///
/// Usage today (stub): call [register] with a known token string for testing.
///
/// TODO(push): next slice —
///   1. Add `firebase_messaging` to pubspec.yaml.
///   2. Add google-services.json (Android) and GoogleService-Info.plist (iOS).
///   3. Request notification permission via FirebaseMessaging.instance.requestPermission().
///   4. Get the FCM token: final token = await FirebaseMessaging.instance.getToken();
///   5. Detect platform: Platform.isAndroid ? 'android' : 'ios'.
///   6. Call pushTokenServiceProvider.register(token, platform: platform)
///      from the post-login hook (e.g., in LoginController after LoginSuccess).
///   7. Also listen to FirebaseMessaging.instance.onTokenRefresh to re-register
///      when FCM rotates the token.
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
      // TODO(push): add structured logging / crash reporter here.
      // ignore: avoid_print
      print('[PushTokenService] registerPushToken failed (non-fatal): $e');
    }
  }
}

/// Provider for [PushTokenService].
final pushTokenServiceProvider = Provider<PushTokenService>((ref) {
  return PushTokenService(ref.watch(authRepositoryProvider));
});
