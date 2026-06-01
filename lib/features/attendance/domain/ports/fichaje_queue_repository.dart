import '../gps_position.dart';
import '../pending_fichaje.dart';

/// Port (hexagonal) — offline queue persistence boundary.
///
/// The data layer provides the implementation (sqflite-backed).
/// The application layer (FichajeSyncService) depends only on this interface.
abstract interface class FichajeQueueRepository {
  /// Enqueues a new fichaje intent.
  ///
  /// Returns the created [PendingFichaje] with its assigned [localId].
  Future<PendingFichaje> enqueue({
    required String operarioId,
    required String operarioName,
    required String date,
    required String clientRef,
    required DateTime checkInCapturedAt,
    required GpsPosition checkInGps,
  });

  /// Persists the captured signature PNG for an existing queued fichaje.
  ///
  /// Writes the bytes to a file in the app documents directory and stores the
  /// path. Advances status to [FichajeQueueStatus.checkedInPendingSignature]
  /// if the serverAttendanceId is already known, else keeps
  /// [FichajeQueueStatus.pendingCheckIn] (signature will be uploaded after
  /// check-in succeeds).
  Future<void> saveSignature({
    required int localId,
    required List<int> pngBytes,
  });

  /// Stores the check-out intent for an existing queued fichaje.
  ///
  /// Does NOT change the status — the sync service advances it after a
  /// successful POST.
  Future<void> saveCheckOut({
    required int localId,
    required String checkOutClientRef,
    required DateTime checkOutCapturedAt,
    required GpsPosition checkOutGps,
  });

  /// Advances status after check-in POST succeeds.
  Future<void> markCheckedIn({
    required int localId,
    required String serverAttendanceId,
  });

  /// Advances status after signature upload succeeds.
  Future<void> markSignatureUploaded({required int localId});

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

  /// Initialises the database. Must be called once before other methods.
  Future<void> init();
}
