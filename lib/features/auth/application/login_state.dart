import '../domain/user_profile.dart';

/// Sealed state for the login flow.
sealed class LoginState {
  const LoginState();
}

/// No login attempt has been made.
final class LoginIdle extends LoginState {
  const LoginIdle();
}

/// A login request is in flight.
final class LoginLoading extends LoginState {
  const LoginLoading();
}

/// Login succeeded and /auth/me returned a valid profile.
final class LoginSuccess extends LoginState {
  const LoginSuccess(this.profile);

  final UserProfile profile;
}

/// Login (or profile fetch) failed.
final class LoginError extends LoginState {
  const LoginError(this.message);

  final String message;
}
