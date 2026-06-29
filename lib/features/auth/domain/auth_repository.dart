import 'auth_session.dart';
import 'user_profile.dart';

/// Port (hexagonal) — defines what the auth feature needs from the outside
/// world. The data layer provides the implementation; the application layer
/// depends only on this interface.
abstract interface class AuthRepository {
  /// Authenticates the user against the backend.
  ///
  /// Throws [AuthException] on 401 or network errors.
  Future<AuthSession> login({
    required String email,
    required String password,
    required String deviceId,
  });

  /// Fetches the authenticated user's profile using the stored access token.
  Future<UserProfile> getMe();

  /// Registers (or updates) the FCM push token for the caller's current device
  /// session. The device is resolved from the JWT — never from the body.
  ///
  /// [pushToken] is the FCM registration token string.
  /// [pushPlatform] is optional ("android" | "ios").
  ///
  /// Calls POST /auth/push-token → 204.
  /// Throws [AuthException] on 401 or 400.
  Future<void> registerPushToken({
    required String pushToken,
    String? pushPlatform,
  });

  /// Clears the FCM push token for the caller's current device session.
  ///
  /// The device is resolved from the JWT — never from the body. Used on logout
  /// so the backend stops targeting this device.
  ///
  /// Calls DELETE /auth/push-token → 204 (no body).
  /// Throws [AuthException] on 401.
  Future<void> unregisterPushToken();

  /// Changes the authenticated user's password.
  ///
  /// [oldPassword] is the current password (field name confirmed from backend DTO).
  /// [newPassword] is the new password (min 8 chars enforced by backend).
  ///
  /// Calls POST /auth/change-password → 200 { message }.
  /// Throws [AuthException] on 401 (wrong current password) or 400 (invalid new).
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  });
}

/// Domain exception for authentication failures.
class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => 'AuthException: $message';
}
