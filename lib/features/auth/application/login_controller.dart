import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/auth_repository.dart';
import 'auth_providers.dart';
import 'login_state.dart';

/// Drives the login UI state machine.
///
/// States: [LoginIdle] → [LoginLoading] → [LoginSuccess] | [LoginError]
class LoginController extends StateNotifier<LoginState> {
  LoginController(this._repository, this._deviceIdFuture)
      : super(const LoginIdle());

  final AuthRepository _repository;
  final Future<String> _deviceIdFuture;

  Future<void> login({
    required String email,
    required String password,
  }) async {
    state = const LoginLoading();
    try {
      final deviceId = await _deviceIdFuture;

      // 1. Authenticate — tokens are persisted inside the repository.
      await _repository.login(
        email: email,
        password: password,
        deviceId: deviceId,
      );

      // 2. Fetch profile to prove the token works end-to-end.
      final profile = await _repository.getMe();

      state = LoginSuccess(profile);
    } on AuthException catch (e) {
      state = LoginError(e.message);
    } catch (e) {
      state = LoginError('Error inesperado: $e');
    }
  }

  void reset() => state = const LoginIdle();
}

/// Provider wiring: the controller depends on the repository + deviceId.
final loginControllerProvider =
    StateNotifierProvider<LoginController, LoginState>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  // Unwrap the FutureProvider into a plain Future for the controller.
  final deviceIdFuture = ref
      .watch(deviceIdProvider.future);
  return LoginController(repo, deviceIdFuture);
});
