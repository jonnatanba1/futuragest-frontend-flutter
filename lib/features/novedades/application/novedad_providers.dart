import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/application/auth_providers.dart';
import '../data/novedad_repository_impl.dart';
import '../domain/novedad.dart';
import '../domain/novedad_repository.dart';
import 'create_novedad_controller.dart';
import 'create_novedad_state.dart';

// ── Repository provider ────────────────────────────────────────────────────

/// Provides the [NovedadRepository] implementation (Dio-backed).
final novedadRepositoryProvider = Provider<NovedadRepository>((ref) {
  return NovedadRepositoryImpl(dio: ref.watch(dioProvider));
});

// ── List provider ──────────────────────────────────────────────────────────

/// Fetches the full list of novedades scoped to the logged-in supervisor.
///
/// Returns [AsyncValue<List<Novedad>>]. Invalidate to refresh:
///   ref.invalidate(novedadesListProvider)
///
/// TODO(delta-sync): add ?since=ISO query param once the backend delta endpoint
///                   is wired and a local cache layer is added.
final novedadesListProvider = FutureProvider<List<Novedad>>((ref) async {
  final repo = ref.watch(novedadRepositoryProvider);
  return repo.listNovedades();
});

// ── Create controller provider ─────────────────────────────────────────────

/// Family provider — one [CreateNovedadController] per attendanceId.
///
/// Keyed by attendanceId so a supervisor opening two different forms
/// (if navigation allows it) gets independent states.
final createNovedadControllerProvider = StateNotifierProvider.family<
    CreateNovedadController, CreateNovedadState, String>(
  (ref, attendanceId) => CreateNovedadController(
    repository: ref.watch(novedadRepositoryProvider),
    ref: ref,
  ),
);
