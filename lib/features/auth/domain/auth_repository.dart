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
}

/// Domain exception for authentication failures.
class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => 'AuthException: $message';
}
