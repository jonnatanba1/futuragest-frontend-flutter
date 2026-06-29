import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/biometric/biometric_providers.dart';
import '../../../core/biometric/biometric_service.dart'
    show BiometricException, BiometricOutcome, BiometricResult, BiometricService, VerificationMethod;
import '../domain/novedad_repository.dart';
import 'lider_novedad_action_state.dart';
import 'novedad_providers.dart';

/// Drives the approve/reject action for a single novedad card on the
/// LIDER_OPERATIVO screen.
///
/// Keyed by novedad ID so each card has independent loading state.
///
/// Both [approve] and [reject] gate on biometric confirmation first; the
/// [BiometricOutcome.verification] label is forwarded to the backend as an
/// audit field only. Unavailable device → proceeds with 'NONE'.
/// User cancel → aborts silently (state stays idle / previous).
class LiderNovedadActionController
    extends StateNotifier<LiderNovedadActionState> {
  LiderNovedadActionController({
    required NovedadRepository repository,
    required BiometricService biometric,
    required this.ref,
  })  : _repository = repository, // ignore: prefer_initializing_formals
        _biometric = biometric, // ignore: prefer_initializing_formals
        super(const LiderNovedadActionIdle());

  final NovedadRepository _repository;
  final BiometricService _biometric;
  final Ref ref;

  // ── Biometric gate ─────────────────────────────────────────────────────────

  /// Confirms identity and returns the [BiometricOutcome].
  ///
  /// Returns null when the user cancels (caller must abort silently).
  /// Throws [NovedadException] on unrecoverable platform errors.
  Future<BiometricOutcome?> _confirmBiometric(String reason) async {
    try {
      final outcome = await _biometric.confirm(reason);
      if (outcome.result == BiometricResult.cancelled) return null;
      return outcome;
    } on BiometricException catch (e) {
      throw NovedadException(e.message);
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  /// Approves [novedadId] after biometric confirmation.
  Future<void> approve(String novedadId) async {
    await _decideWithBiometric(
      novedadId: novedadId,
      biometricReason:
          'Confirmá tu identidad para aprobar la novedad.',
      action: (verification) =>
          _repository.approveNovedad(novedadId, verification: verification),
      successMessage: 'Novedad aprobada correctamente.',
    );
  }

  /// Rejects [novedadId] after biometric confirmation.
  Future<void> reject(String novedadId) async {
    await _decideWithBiometric(
      novedadId: novedadId,
      biometricReason:
          'Confirmá tu identidad para rechazar la novedad.',
      action: (verification) =>
          _repository.rejectNovedad(novedadId, verification: verification),
      successMessage: 'Novedad rechazada.',
    );
  }

  Future<void> _decideWithBiometric({
    required String novedadId,
    required String biometricReason,
    required Future<void> Function(String? verification) action,
    required String successMessage,
  }) async {
    state = const LiderNovedadActionActing();
    try {
      // Biometric gate — user cancel aborts silently.
      final outcome = await _confirmBiometric(biometricReason);
      if (outcome == null) {
        // Cancelled: show brief message then reset.
        state = const LiderNovedadActionError(
          message: 'Autenticación cancelada.',
        );
        return;
      }

      // Map unavailable → NONE (graceful degrade).
      final verification =
          outcome.result == BiometricResult.unavailable
              ? VerificationMethod.none
              : outcome.verification;

      await action(verification);

      // Refresh the list so the decided novedad moves to the history section.
      ref.invalidate(novedadesListProvider);
      state = LiderNovedadActionDone(successMessage);
    } on NovedadAlreadyDecidedException catch (e) {
      ref.invalidate(novedadesListProvider);
      state = LiderNovedadActionError(
        message: e.message,
        isAlreadyDecided: true,
      );
    } on NovedadException catch (e) {
      state = LiderNovedadActionError(message: e.message);
    } catch (e) {
      state = LiderNovedadActionError(message: 'Error inesperado: $e');
    }
  }

  /// Resets to idle so the card can be retried.
  void reset() => state = const LiderNovedadActionIdle();
}

/// Family provider — one controller per novedad ID.
final liderNovedadActionControllerProvider = StateNotifierProvider.family<
    LiderNovedadActionController, LiderNovedadActionState, String>(
  (ref, novedadId) => LiderNovedadActionController(
    repository: ref.watch(novedadRepositoryProvider),
    biometric: ref.watch(biometricServiceProvider),
    ref: ref,
  ),
);
