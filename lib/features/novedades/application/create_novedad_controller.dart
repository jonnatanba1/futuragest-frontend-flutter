import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../domain/novedad_repository.dart';
import 'create_novedad_state.dart';
import 'novedad_providers.dart';

const _uuid = Uuid();

/// Drives the create-novedad form.
///
/// Responsibilities:
///  - Local validation (horasExtra > 0 and ≤ 24, numeric).
///  - Generates a uuid v4 clientRef per submit for idempotency.
///  - Posts to the backend via [NovedadRepository].
///  - Emits [CreateNovedadState] transitions for the UI.
///
/// TODO(offline): wire clientRef into an offline queue so novedades can be
/// submitted without connectivity and replayed when back online.
class CreateNovedadController extends StateNotifier<CreateNovedadState> {
  CreateNovedadController({
    required NovedadRepository repository,
    required this.ref,
  })  : _repository = repository, // ignore: prefer_initializing_formals
        super(const CreateNovedadIdle());

  final NovedadRepository _repository;
  final Ref ref;

  /// Validates and submits the novedad.
  ///
  /// [horasExtraInput] is the raw string from the text field.
  /// Returns the created [Novedad] on success (same as the success state).
  Future<void> submit({
    required String attendanceId,
    required String horasExtraInput,
    String? motivo,
  }) async {
    // ── Local validation ─────────────────────────────────────────────────────

    final trimmed = horasExtraInput.trim();
    if (trimmed.isEmpty) {
      state = const CreateNovedadError(
        'Ingresá las horas extra (por ejemplo: 2.5).',
      );
      return;
    }

    final parsed = double.tryParse(trimmed);
    if (parsed == null) {
      state = const CreateNovedadError(
        'Horas extra inválidas. Ingresá un número (por ejemplo: 2.5).',
      );
      return;
    }
    if (parsed <= 0) {
      state = const CreateNovedadError(
        'Las horas extra deben ser mayores a 0.',
      );
      return;
    }
    if (parsed > 24) {
      state = const CreateNovedadError(
        'Las horas extra no pueden superar 24 horas.',
      );
      return;
    }

    // Format as a decimal string with two places, e.g. "2.50".
    // The backend validates any positive numeric string — this is just a
    // clean canonical format. horasExtra stays a string end-to-end.
    final horasExtraStr = parsed.toStringAsFixed(2);

    // ── Idempotency token ────────────────────────────────────────────────────
    // Generate a fresh uuid v4 per submit so re-sends are safe.
    // TODO(offline): persist clientRef + payload to local queue before the POST,
    //               then mark the queue item complete on 201/200 reply.
    final clientRef = _uuid.v4();

    // ── POST ─────────────────────────────────────────────────────────────────
    state = const CreateNovedadSubmitting();

    try {
      final novedad = await _repository.createNovedad(
        attendanceId: attendanceId,
        horasExtra: horasExtraStr,
        clientRef: clientRef,
        motivo: motivo?.trim().isEmpty == true ? null : motivo?.trim(),
      );

      // Invalidate the list so it refreshes the next time it's watched.
      ref.invalidate(novedadesListProvider);

      state = CreateNovedadSuccess(novedad);
    } on NovedadException catch (e) {
      state = CreateNovedadError(e.message);
    } catch (e) {
      state = CreateNovedadError('Error inesperado: $e');
    }
  }

  /// Resets the form back to idle so the user can retry after an error.
  void reset() => state = const CreateNovedadIdle();
}
