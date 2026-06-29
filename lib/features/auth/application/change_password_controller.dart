import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/auth_repository.dart';
import 'auth_providers.dart';
import 'change_password_state.dart';

/// Drives the change-password screen.
///
/// State machine: [ChangePasswordIdle] → [ChangePasswordLoading]
///   → [ChangePasswordSuccess] | [ChangePasswordError]
class ChangePasswordController extends StateNotifier<ChangePasswordState> {
  ChangePasswordController(this._repository, this._deviceIdFuture)
      : super(const ChangePasswordIdle());

  final AuthRepository _repository;
  final Future<String> _deviceIdFuture;

  /// Submits the password change.
  ///
  /// [email] is the user's email — needed to re-authenticate afterwards.
  /// [oldPassword] is the user's current password.
  /// [newPassword] is the desired new password (already validated by the form).
  Future<void> changePassword({
    required String email,
    required String oldPassword,
    required String newPassword,
  }) async {
    state = const ChangePasswordLoading();
    try {
      await _repository.changePassword(
        oldPassword: oldPassword,
        newPassword: newPassword,
      );

      // The current access token still carries mustChangePassword:true in its
      // JWT claims — the backend MustChangePasswordGuard reads that claim on
      // every protected request, so it would keep returning 403
      // PASSWORD_CHANGE_REQUIRED. Re-authenticate with the new password to mint
      // a fresh token (mustChangePassword:false); login persists it to storage.
      final deviceId = await _deviceIdFuture;
      await _repository.login(
        email: email,
        password: newPassword,
        deviceId: deviceId,
      );

      state = const ChangePasswordSuccess();
    } on AuthException catch (e) {
      state = ChangePasswordError(e.message);
    } catch (e) {
      state = ChangePasswordError('Error inesperado: $e');
    }
  }

  void reset() => state = const ChangePasswordIdle();
}

/// Provider for [ChangePasswordController].
final changePasswordControllerProvider =
    StateNotifierProvider<ChangePasswordController, ChangePasswordState>((ref) {
  return ChangePasswordController(
    ref.watch(authRepositoryProvider),
    ref.watch(deviceIdProvider.future),
  );
});
