import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/biometric/biometric_service.dart';
import '../../../core/connectivity/connectivity_service.dart';
import '../../../features/auth/application/auth_providers.dart';
import '../data/attendance_repository_impl.dart';
import '../data/sqflite_fichaje_queue_repository.dart';
import '../domain/attendance_repository.dart';
import '../domain/operario.dart';
import '../domain/ports/fichaje_queue_repository.dart';
import 'fichaje_sync_service.dart';

// ── Repository providers ───────────────────────────────────────────────────

/// Provides the [AttendanceRepository] implementation (Dio-backed).
final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return AttendanceRepositoryImpl(dio: ref.watch(dioProvider));
});

/// Provides the [FichajeQueueRepository] implementation (sqflite-backed).
///
/// NOTE: [SqfliteFichajeQueueRepository.init] is called by [fichajeSyncServiceProvider]
/// during its own initialisation — callers do not need to call it separately.
final fichajeQueueRepositoryProvider = Provider<FichajeQueueRepository>((ref) {
  return SqfliteFichajeQueueRepository();
});

// ── Biometric ──────────────────────────────────────────────────────────────

/// Provides the [BiometricService] singleton.
final biometricServiceProvider = Provider<BiometricService>(
  (ref) => BiometricService(),
);

// ── Sync service ───────────────────────────────────────────────────────────

/// Provides the [FichajeSyncService] StateNotifier.
///
/// The notifier is kept-alive for the app lifetime so its connectivity
/// subscription persists and sync stats are always current.
final fichajeSyncServiceProvider =
    StateNotifierProvider<FichajeSyncService, SyncStats>((ref) {
  final service = FichajeSyncService(
    queue: ref.watch(fichajeQueueRepositoryProvider),
    remote: ref.watch(attendanceRepositoryProvider),
    connectivity: ref.watch(connectivityServiceProvider),
  );
  // init() is async; fire-and-forget — the UI reads stats reactively.
  service.init();
  return service;
});

/// Convenience provider that exposes only [SyncStats] for the UI indicator.
final syncStatsProvider = Provider<SyncStats>((ref) {
  return ref.watch(fichajeSyncServiceProvider);
});

// ── Operario list provider ─────────────────────────────────────────────────

/// Fetches the full list of operarios scoped to the logged-in supervisor.
///
/// Returns an [AsyncValue<List<Operario>>]. Invalidate to refresh:
///   ref.invalidate(operarioListProvider)
///
/// TODO(STEP 2 — optional): add delta-sync support with ?since=ISO query param
///               and local cache to avoid full refetch every time.
final operarioListProvider = FutureProvider<List<Operario>>((ref) async {
  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.getOperarios();
});
