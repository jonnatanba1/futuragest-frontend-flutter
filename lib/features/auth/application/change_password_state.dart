/// Sealed state for the change-password flow.
sealed class ChangePasswordState {
  const ChangePasswordState();
}

/// Waiting for user input.
final class ChangePasswordIdle extends ChangePasswordState {
  const ChangePasswordIdle();
}

/// Request is in flight.
final class ChangePasswordLoading extends ChangePasswordState {
  const ChangePasswordLoading();
}

/// Password changed successfully.
final class ChangePasswordSuccess extends ChangePasswordState {
  const ChangePasswordSuccess();
}

/// The request failed. [message] is a Spanish string suitable for display.
final class ChangePasswordError extends ChangePasswordState {
  const ChangePasswordError(this.message);

  final String message;
}
