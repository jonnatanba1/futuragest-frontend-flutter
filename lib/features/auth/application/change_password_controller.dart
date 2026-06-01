import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/auth_repository.dart';
import 'auth_providers.dart';
import 'change_password_state.dart';

/// Drives the change-password screen.
///
/// State machine: [ChangePasswordIdle] → [ChangePasswordLoading]
///   → [ChangePasswordSuccess] | [ChangePasswordError]
class ChangePasswordController extends StateNotifier<ChangePasswordState> {
  ChangePasswordController(this._repository) : super(const ChangePasswordIdle());

  final AuthRepository _repository;

  /// Submits the password change.
  ///
  /// [oldPassword] is the user's current password.
  /// [newPassword] is the desired new password (already validated by the form).
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    state = const ChangePasswordLoading();
    try {
      await _repository.changePassword(
        oldPassword: oldPassword,
        newPassword: newPassword,
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
  return ChangePasswordController(ref.watch(authRepositoryProvider));
});
