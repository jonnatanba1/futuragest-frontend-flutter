import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/token_storage.dart';
import '../../../features/attendance/application/attendance_providers.dart';
import '../../../features/attendance/domain/ports/fichaje_queue_repository.dart';
import '../domain/auth_repository.dart';
import 'auth_providers.dart';
import 'login_state.dart';

/// Drives the login UI state machine.
///
/// States: [LoginIdle] → [LoginLoading] → [LoginSuccess] | [LoginError]
class LoginController extends StateNotifier<LoginState> {
  LoginController(
    this._repository,
    this._deviceIdFuture,
    this._storage,
    this._queue,
  ) : super(const LoginIdle());

  final AuthRepository _repository;
  final Future<String> _deviceIdFuture;
  final TokenStorage _storage;
  final FichajeQueueRepository _queue;

  Future<void> login({
    required String email,
    required String password,
  }) async {
    state = const LoginLoading();
    try {
      final deviceId = await _deviceIdFuture;

      // 1. Snapshot the previously stored session owner BEFORE login so we can
      //    detect a user switch after the new tokens arrive.
      final previousOwner = await _storage.readSessionOwner();

      // 2. Authenticate — tokens are persisted inside the repository.
      await _repository.login(
        email: email,
        password: password,
        deviceId: deviceId,
      );

      // 3. Decode the sub (userId) from the freshly-stored access token.
      //    repository.login() already wrote the token to storage.
      final accessToken = await _storage.readAccessToken();
      final newOwner = accessToken != null ? _decodeSub(accessToken) : null;

      // 4. Owner guard — if a DIFFERENT user logged in, wipe the offline queue
      //    before the new session touches any shared state.
      if (previousOwner != null &&
          newOwner != null &&
          previousOwner != newOwner) {
        try {
          await _queue.init();
          await _queue.wipeAll();
        } catch (_) {
          // Best-effort: a wipe failure must not block login.
        }
      }

      // 5. Persist the new session owner for the next login's guard.
      if (newOwner != null) {
        await _storage.saveSessionOwner(newOwner);
      }

      // 6. Fetch profile to prove the token works end-to-end.
      final profile = await _repository.getMe();

      state = LoginSuccess(profile);
    } on AuthException catch (e) {
      state = LoginError(e.message);
    } catch (e) {
      state = LoginError('Error inesperado: $e');
    }
  }

  /// Decodes the `sub` claim from a JWT without verifying the signature.
  String? _decodeSub(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      final payload = json.decode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      return payload['sub'] as String?;
    } catch (_) {
      return null;
    }
  }

  void reset() => state = const LoginIdle();
}

/// Provider wiring: the controller depends on the repository + deviceId +
/// storage + queue (for the login-time owner guard).
final loginControllerProvider =
    StateNotifierProvider<LoginController, LoginState>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  final storage = ref.watch(tokenStorageProvider);
  final queue = ref.watch(fichajeQueueRepositoryProvider);
  // Unwrap the FutureProvider into a plain Future for the controller.
  final deviceIdFuture = ref.watch(deviceIdProvider.future);
  return LoginController(repo, deviceIdFuture, storage, queue);
});
