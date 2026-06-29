import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connectivity/connectivity_service.dart';
import '../../../features/auth/application/auth_providers.dart';
import '../data/attendance_repository_impl.dart';
import '../data/sqflite_fichaje_queue_repository.dart';
import '../domain/attendance_repository.dart';
import '../domain/operario.dart';
import '../domain/pending_fichaje.dart';
import '../domain/ports/fichaje_queue_repository.dart';
import 'fichaje_sync_service.dart';

export '../../../core/biometric/biometric_providers.dart'
    show biometricServiceProvider;

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

// ── Recorded-today provider ─────────────────────────────────────────────────

/// Today's Colombia-local date "YYYY-MM-DD" (UTC-5). Matches the date the
/// fichaje flow stamps on a check-in, so the one-per-day rule lines up.
String colombiaToday() {
  final c = DateTime.now().toUtc().add(const Duration(hours: -5));
  return '${c.year.toString().padLeft(4, '0')}'
      '-${c.month.toString().padLeft(2, '0')}'
      '-${c.day.toString().padLeft(2, '0')}';
}

/// Per-operario fichaje status for TODAY: `operarioId -> (attendanceId?, completed)`.
///
/// Drives the operario list:
///  - `completed == true` (ingreso + salida) blocks a new fichaje and unlocks
///    the "Horas extra" action;
///  - a record with `completed == false` is in progress (ingreso only) — the
///    operario stays actionable so the supervisor can register the salida;
///  - `attendanceId` is null when captured offline and not yet synced (overtime
///    can only be attached once the attendance exists server-side).
///
/// Combines two sources so it works offline-first:
///  - the local offline queue (anything captured today that hasn't failed), and
///  - the backend's records for today (authoritative — fills in real ids/state).
/// Either source failing (queue not yet initialised, or device offline)
/// degrades gracefully to the other.
typedef TodayFichaje = ({String? attendanceId, bool completed});

final recordedTodayProvider =
    FutureProvider<Map<String, TodayFichaje>>((ref) async {
  final today = colombiaToday();
  final byOperario = <String, TodayFichaje>{};

  // Local queue — covers fichajes not yet synced (serverAttendanceId may be null).
  try {
    final queue = ref.watch(fichajeQueueRepositoryProvider);
    final all = await queue.listAll();
    for (final f in all) {
      if (f.date == today && f.status != FichajeQueueStatus.failed) {
        byOperario[f.operarioId] = (
          attendanceId: f.serverAttendanceId,
          completed: f.status == FichajeQueueStatus.completed,
        );
      }
    }
  } catch (_) {
    // Queue not initialised yet — rely on the server source below.
  }

  // Server — authoritative: overwrites with the real id + completion state.
  try {
    final repo = ref.watch(attendanceRepositoryProvider);
    final server = await repo.todayAttendanceByOperario(today);
    server.forEach((operarioId, info) {
      byOperario[operarioId] =
          (attendanceId: info.id, completed: info.completed);
    });
  } catch (_) {
    // Offline or transient failure — rely on the local queue above.
  }

  return byOperario;
});
