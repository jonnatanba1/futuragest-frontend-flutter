/// Returned by [AuthRepository.login] after a successful authentication.
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.passwordChangeRequired,
  });

  final String accessToken;
  final String refreshToken;

  /// When true the app should redirect to the change-password screen
  /// before allowing normal navigation.
  final bool passwordChangeRequired;
}
