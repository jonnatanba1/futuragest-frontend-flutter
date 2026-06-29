import '../gps_position.dart';
import '../pending_fichaje.dart';

/// Thrown by [FichajeQueueRepository.enqueue] when an open record already
/// exists for the same [operarioId] and [date] pair.
///
/// The UI layer should surface this with a friendly Spanish message rather than
/// allowing a silent second row to accumulate in the queue.
class DuplicateLocalFichajeException implements Exception {
  const DuplicateLocalFichajeException({
    required this.operarioId,
    required this.date,
    required this.existingLocalId,
  });

  final String operarioId;
  final String date;
  final int existingLocalId;

  @override
  String toString() =>
      'DuplicateLocalFichajeException: operario $operarioId already has an open '
      'fichaje for $date (localId=$existingLocalId).';
}

/// Port (hexagonal) — offline queue persistence boundary.
///
/// The data layer provides the implementation (sqflite-backed).
/// The application layer (FichajeSyncService) depends only on this interface.
abstract interface class FichajeQueueRepository {
  /// Enqueues a new fichaje ingreso intent.
  ///
  /// [checkInVerification] is an optional audit label ('BIOMETRIC' |
  /// 'DEVICE_CREDENTIAL' | 'NONE') — persisted for sync and backend recording.
  /// AUDIT LABEL ONLY — no authorization logic may depend on this field.
  ///
  /// Returns the created [PendingFichaje] with its assigned [localId].
  Future<PendingFichaje> enqueue({
    required String operarioId,
    required String operarioName,
    required String date,
    required String clientRef,
    required DateTime checkInCapturedAt,
    required GpsPosition checkInGps,
    String? checkInVerification,
  });

  /// Persists the captured entry (ingreso) photo bytes for an existing
  /// queued fichaje.
  ///
  /// Writes the bytes to a file in the app documents directory and stores the
  /// path in the [checkInPhotoPath] DB column. Does NOT change status — the
  /// sync service advances it after uploading.
  Future<void> saveCheckInPhoto({
    required int localId,
    required List<int> photoBytes,
  });

  /// Persists the captured salida data: exit photo bytes + check-out GPS/time.
  ///
  /// Writes the exit photo bytes to disk and stores path in [checkOutPhotoPath],
  /// and stores checkOutClientRef / capturedAt / GPS.
  /// [checkOutVerification] is an optional audit label — see [enqueue].
  /// Does NOT change status — the sync service advances it after uploading.
  Future<void> saveSalida({
    required int localId,
    required List<int> checkOutPhotoBytes,
    required String checkOutClientRef,
    required DateTime checkOutCapturedAt,
    required GpsPosition checkOutGps,
    String? checkOutVerification,
  });

  /// Advances status after check-in POST succeeds.
  Future<void> markCheckedIn({
    required int localId,
    required String serverAttendanceId,
  });

  /// Advances status to [FichajeQueueStatus.ingresoComplete] after entry
  /// photo upload succeeds.
  Future<void> markIngresoComplete({required int localId});

  /// Advances status to [FichajeQueueStatus.salidaSigned] after exit
  /// photo upload succeeds.
  Future<void> markSalidaSigned({required int localId});

  /// Marks the fichaje as fully completed.
  Future<void> markCompleted({required int localId});

  /// Marks the fichaje as failed with a reason (non-transient error).
  Future<void> markFailed({required int localId, required String reason});

  /// Returns all non-completed, non-failed fichajes in FIFO order (by localId).
  Future<List<PendingFichaje>> listPending();

  /// Returns all fichajes — for display / debugging.
  Future<List<PendingFichaje>> listAll();

  /// Returns the fichaje with the given [clientRef], or null if not found.
  Future<PendingFichaje?> findByClientRef(String clientRef);

  /// Returns the open fichaje (status != completed && != failed) for the
  /// given [operarioId] on [date] ("YYYY-MM-DD"), or null if none exists.
  ///
  /// Used to resume the salida phase when tapping an operario with an open
  /// ingreso record.
  Future<PendingFichaje?> findOpenByOperarioAndDate(
    String operarioId,
    String date,
  );

  /// Initialises the database. Must be called once before other methods.
  Future<void> init();

  /// Deletes ALL queue rows and the associated photo files from disk.
  ///
  /// Called on explicit logout (or when a different user logs in) to prevent
  /// cross-user data leakage. Must NOT be called on transient session expiry
  /// (_failSession) — the owner guard at login covers user switching.
  Future<void> wipeAll();
}
