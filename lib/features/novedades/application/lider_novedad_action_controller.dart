import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/novedad_repository.dart';
import 'lider_novedad_action_state.dart';
import 'novedad_providers.dart';

/// Drives the approve/reject action for a single novedad card on the
/// LIDER_OPERATIVO screen.
///
/// Keyed by novedad ID so each card has independent loading state.
class LiderNovedadActionController
    extends StateNotifier<LiderNovedadActionState> {
  LiderNovedadActionController({
    required NovedadRepository repository,
    required this.ref,
  })  : _repository = repository, // ignore: prefer_initializing_formals
        super(const LiderNovedadActionIdle());

  final NovedadRepository _repository;
  final Ref ref;

  /// Approves [novedadId]. On success, invalidates the list to refresh it.
  Future<void> approve(String novedadId) async {
    await _decide(
      novedadId: novedadId,
      action: () => _repository.approveNovedad(novedadId),
      successMessage: 'Novedad aprobada correctamente.',
    );
  }

  /// Rejects [novedadId]. On success, invalidates the list to refresh it.
  Future<void> reject(String novedadId) async {
    await _decide(
      novedadId: novedadId,
      action: () => _repository.rejectNovedad(novedadId),
      successMessage: 'Novedad rechazada.',
    );
  }

  Future<void> _decide({
    required String novedadId,
    required Future<void> Function() action,
    required String successMessage,
  }) async {
    state = const LiderNovedadActionActing();
    try {
      await action();
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
    ref: ref,
  ),
);
