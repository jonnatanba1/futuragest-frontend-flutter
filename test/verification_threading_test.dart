// Tests for verification method threading through controller → queue → sync.
//
// Covers:
//   - FichajeController: cancelled biometric → FichajeError.
//   - FichajeController: unavailable biometric → proceeds (not cancelled error).
//   - FichajeController: retry() re-invokes start() after reset.
//   - PendingFichaje.copyWith: propagates verification fields.
//   - FichajeSyncService: checkIn payload includes verification from queue item.
//   - FichajeSyncService: checkOut payload includes verification from queue item.
//   - LiderNovedadActionController: cancel → aborts (repo not called).
//   - LiderNovedadActionController: approve/reject send correct verification.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:futuragest_mobile/core/biometric/biometric_service.dart';
import 'package:futuragest_mobile/core/connectivity/connectivity_service.dart';
import 'package:futuragest_mobile/features/attendance/application/fichaje_controller.dart';
import 'package:futuragest_mobile/features/attendance/application/fichaje_state.dart';
import 'package:futuragest_mobile/features/attendance/application/fichaje_sync_service.dart';
import 'package:futuragest_mobile/features/attendance/domain/attendance_record.dart';
import 'package:futuragest_mobile/features/attendance/domain/attendance_repository.dart';
import 'package:futuragest_mobile/features/attendance/domain/gps_position.dart';
import 'package:futuragest_mobile/features/attendance/domain/operario.dart';
import 'package:futuragest_mobile/features/attendance/domain/pending_fichaje.dart';
import 'package:futuragest_mobile/features/attendance/domain/ports/fichaje_queue_repository.dart';
import 'package:futuragest_mobile/features/novedades/application/lider_novedad_action_controller.dart';
import 'package:futuragest_mobile/features/novedades/application/lider_novedad_action_state.dart';
import 'package:futuragest_mobile/features/novedades/application/novedad_providers.dart'
    show novedadesListProvider;
import 'package:futuragest_mobile/features/novedades/domain/novedad.dart';
import 'package:futuragest_mobile/features/novedades/domain/novedad_repository.dart';

// ── Fake BiometricService ──────────────────────────────────────────────────

class FakeBiometric extends BiometricService {
  FakeBiometric(this._outcome);

  final BiometricOutcome _outcome;

  @override
  Future<BiometricOutcome> confirm(String reason) async => _outcome;
}

class CountingBiometric extends BiometricService {
  CountingBiometric({
    required this.outcome,
    required this.onConfirm,
    this.cancelAfterCalls,
  });

  final BiometricOutcome outcome;
  final void Function() onConfirm;
  final int? cancelAfterCalls;
  int calls = 0;

  @override
  Future<BiometricOutcome> confirm(String reason) async {
    calls++;
    onConfirm();
    if (cancelAfterCalls != null && calls > cancelAfterCalls!) {
      return const BiometricOutcome(result: BiometricResult.cancelled);
    }
    return outcome;
  }
}

// ── Fake FichajeSyncService ────────────────────────────────────────────────

class FakeSyncService extends FichajeSyncService {
  FakeSyncService()
      : super(
          queue: FakeQueue(),
          remote: FakeAttendanceRepo(),
          connectivity: FakeConnectivity(),
        );

  String? lastCheckInVerification;
  String? lastCheckOutVerification;

  @override
  Future<void> init() async {}

  @override
  Future<PendingFichaje> enqueue({
    required String operarioId,
    required String operarioName,
    required String date,
    required String clientRef,
    required DateTime checkInCapturedAt,
    required GpsPosition checkInGps,
    String? checkInVerification,
  }) async {
    lastCheckInVerification = checkInVerification;
    return PendingFichaje(
      localId: 1,
      operarioId: operarioId,
      operarioName: operarioName,
      date: date,
      clientRef: clientRef,
      checkInCapturedAt: checkInCapturedAt,
      checkInGps: checkInGps,
      status: FichajeQueueStatus.pendingCheckIn,
      checkInVerification: checkInVerification,
    );
  }

  @override
  Future<void> saveSalida({
    required int localId,
    required List<int> checkOutPhotoBytes,
    required String checkOutClientRef,
    required DateTime checkOutCapturedAt,
    required GpsPosition checkOutGps,
    String? checkOutVerification,
  }) async {
    lastCheckOutVerification = checkOutVerification;
  }

  @override
  Future<void> saveCheckInPhoto({
    required int localId,
    required List<int> photoBytes,
  }) async {}
}

// ── Fake FichajeQueueRepository ────────────────────────────────────────────

class FakeQueue implements FichajeQueueRepository {
  List<PendingFichaje> pendingItems = [];

  @override
  Future<void> init() async {}

  @override
  Future<PendingFichaje> enqueue({
    required String operarioId,
    required String operarioName,
    required String date,
    required String clientRef,
    required DateTime checkInCapturedAt,
    required GpsPosition checkInGps,
    String? checkInVerification,
  }) async {
    final item = PendingFichaje(
      localId: 1,
      operarioId: operarioId,
      operarioName: operarioName,
      date: date,
      clientRef: clientRef,
      checkInCapturedAt: checkInCapturedAt,
      checkInGps: checkInGps,
      status: FichajeQueueStatus.pendingCheckIn,
      checkInVerification: checkInVerification,
    );
    pendingItems.add(item);
    return item;
  }

  @override
  Future<void> saveSalida({
    required int localId,
    required List<int> checkOutPhotoBytes,
    required String checkOutClientRef,
    required DateTime checkOutCapturedAt,
    required GpsPosition checkOutGps,
    String? checkOutVerification,
  }) async {}

  @override
  Future<void> saveCheckInPhoto({
    required int localId,
    required List<int> photoBytes,
  }) async {}

  @override
  Future<void> markCheckedIn({
    required int localId,
    required String serverAttendanceId,
  }) async {}

  @override
  Future<void> markIngresoComplete({required int localId}) async {}

  @override
  Future<void> markSalidaSigned({required int localId}) async {}

  @override
  Future<void> markCompleted({required int localId}) async {}

  @override
  Future<void> markFailed({required int localId, required String reason}) async {}

  @override
  Future<List<PendingFichaje>> listPending() async => pendingItems;

  @override
  Future<List<PendingFichaje>> listAll() async => pendingItems;

  @override
  Future<PendingFichaje?> findByClientRef(String clientRef) async => null;

  @override
  Future<PendingFichaje?> findOpenByOperarioAndDate(
    String operarioId,
    String date,
  ) async =>
      null;

  @override
  Future<void> wipeAll() async => pendingItems.clear();
}

// ── Fake AttendanceRepository (spy) ───────────────────────────────────────

class FakeAttendanceRepo implements AttendanceRepository {
  String? lastCheckInVerification;
  String? lastCheckOutVerification;

  @override
  Future<AttendanceRecord> checkIn({
    required String operarioId,
    required String date,
    required DateTime capturedAt,
    required GpsPosition position,
    required String clientRef,
    String? verification,
  }) async {
    lastCheckInVerification = verification;
    return AttendanceRecord(
      id: 'srv-1',
      operarioId: operarioId,
      date: date,
      clientRef: clientRef,
      checkInCapturedAt: capturedAt,
      checkInLat: position.latitude,
      checkInLng: position.longitude,
    );
  }

  @override
  Future<AttendanceRecord> checkOut({
    required String attendanceId,
    required DateTime capturedAt,
    required GpsPosition position,
    required String checkOutClientRef,
    String? verification,
  }) async {
    lastCheckOutVerification = verification;
    return AttendanceRecord(
      id: attendanceId,
      operarioId: 'op-1',
      date: '2026-06-10',
      clientRef: checkOutClientRef,
      checkInCapturedAt: capturedAt,
      checkInLat: position.latitude,
      checkInLng: position.longitude,
    );
  }

  @override
  Future<void> uploadPhoto({
    required String attendanceId,
    required List<int> photoBytes,
    required String phase,
  }) async {}

  @override
  Future<AttendanceRecord?> recoverByClientRef(String clientRef) async => null;

  @override
  Future<List<Operario>> getOperarios() async => [];

  @override
  Future<Map<String, ({String id, bool completed})>>
      todayAttendanceByOperario(String date) async => {};
}

// ── Fake ConnectivityService ───────────────────────────────────────────────

class FakeConnectivity extends ConnectivityService {
  @override
  Stream<bool> get isOnlineStream => const Stream.empty();

  @override
  Future<bool> isOnline() async => false;
}

/// Always reports online — used by sync-service replay tests so triggerSync
/// actually runs _replayAll rather than returning early.
class FakeOnlineConnectivity extends ConnectivityService {
  @override
  Stream<bool> get isOnlineStream => const Stream.empty();

  @override
  Future<bool> isOnline() async => true;
}

// ── Fake NovedadRepository ─────────────────────────────────────────────────

class SpyNovedadRepo implements NovedadRepository {
  String? lastApproveVerification;
  String? lastRejectVerification;

  @override
  Future<void> approveNovedad(String id, {String? verification}) async {
    lastApproveVerification = verification;
  }

  @override
  Future<void> rejectNovedad(String id, {String? verification}) async {
    lastRejectVerification = verification;
  }

  @override
  Future<Novedad> createNovedad({
    required String attendanceId,
    required String horasExtra,
    required String clientRef,
    String? motivo,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<Novedad>> listNovedades() async => [];

  @override
  Future<Novedad> getNovedad(String id) =>
      throw UnimplementedError();
}

// ── Helpers ────────────────────────────────────────────────────────────────

const testOperario = Operario(
  id: 'op-1',
  fullName: 'Juan Pérez',
  documento: '12345678',
  active: true,
);

FichajeController makeIngresoController({
  required BiometricService biometric,
  FakeSyncService? syncService,
}) {
  final svc = syncService ?? FakeSyncService();
  return FichajeController(
    params: const FichajeParams(
      operario: testOperario,
      mode: FichajeMode.ingreso,
    ),
    syncService: svc,
    biometric: biometric,
  );
}

PendingFichaje makePendingItem({
  String? checkInVerification,
  String? checkOutVerification,
  FichajeQueueStatus status = FichajeQueueStatus.pendingCheckIn,
}) {
  return PendingFichaje(
    localId: 1,
    operarioId: 'op-1',
    operarioName: 'Juan Pérez',
    date: '2026-06-10',
    clientRef: 'ref-abc',
    checkInCapturedAt: DateTime.utc(2026, 6, 10, 8),
    checkInGps: const GpsPosition(latitude: 4.6, longitude: -74.1, accuracy: 10),
    status: status,
    checkInVerification: checkInVerification,
    checkOutVerification: checkOutVerification,
    serverAttendanceId: status == FichajeQueueStatus.salidaSigned ? 'srv-99' : null,
    checkOutClientRef: status == FichajeQueueStatus.salidaSigned ? 'co-ref' : null,
    checkOutCapturedAt: status == FichajeQueueStatus.salidaSigned
        ? DateTime.utc(2026, 6, 10, 17)
        : null,
    checkOutGps: status == FichajeQueueStatus.salidaSigned
        ? const GpsPosition(latitude: 4.6, longitude: -74.1, accuracy: 10)
        : null,
  );
}

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  // ── PendingFichaje verification fields ───────────────────────────────────

  group('PendingFichaje — verification fields', () {
    test('copyWith propagates checkInVerification', () {
      final item = makePendingItem();
      expect(item.checkInVerification, isNull);

      final updated = item.copyWith(
        checkInVerification: VerificationMethod.biometric,
      );
      expect(updated.checkInVerification, VerificationMethod.biometric);
      expect(updated.checkOutVerification, isNull);
    });

    test('copyWith propagates checkOutVerification', () {
      final item = makePendingItem();
      final updated = item.copyWith(
        checkOutVerification: VerificationMethod.deviceCredential,
      );
      expect(updated.checkOutVerification, VerificationMethod.deviceCredential);
      expect(updated.checkInVerification, isNull);
    });

    test('copyWith preserves both verification fields when set', () {
      final item = makePendingItem(
        checkInVerification: VerificationMethod.biometric,
        checkOutVerification: VerificationMethod.none,
      );
      final updated = item.copyWith(); // no-op copyWith
      expect(updated.checkInVerification, VerificationMethod.biometric);
      expect(updated.checkOutVerification, VerificationMethod.none);
    });
  });

  // ── FichajeController — biometric gate ───────────────────────────────────

  group('FichajeController — biometric gate', () {
    test('cancelled biometric → FichajeError with "cancelada" message', () async {
      final controller = makeIngresoController(
        biometric: FakeBiometric(
          const BiometricOutcome(result: BiometricResult.cancelled),
        ),
      );

      await controller.checkIn();

      expect(controller.state, isA<FichajeError>());
      final err = controller.state as FichajeError;
      expect(err.message, contains('cancelada'));
    });

    test('unavailable biometric does NOT produce cancelled error', () async {
      // unavailable → proceeds; GPS then throws → FichajeError but NOT "cancelada"
      final controller = makeIngresoController(
        biometric: FakeBiometric(
          const BiometricOutcome(
            result: BiometricResult.unavailable,
            verification: VerificationMethod.none,
          ),
        ),
      );

      await controller.checkIn();

      // State is an error (GPS failed) but NOT the biometric-cancelled message.
      if (controller.state is FichajeError) {
        final err = controller.state as FichajeError;
        expect(err.message, isNot(equals('Autenticación biométrica cancelada.')));
      }
    });
  });

  // ── FichajeController — retry restart ────────────────────────────────────

  group('FichajeController — retry restart', () {
    test('retry() after error re-invokes biometric (start() called again)',
        () async {
      int biometricCalls = 0;
      final biometric = CountingBiometric(
        outcome: const BiometricOutcome(result: BiometricResult.cancelled),
        onConfirm: () => biometricCalls++,
      );
      final controller = makeIngresoController(biometric: biometric);

      // First attempt — biometric cancelled.
      await controller.checkIn();
      expect(controller.state, isA<FichajeError>());
      expect(biometricCalls, 1);

      // Retry — should call biometric again (start() re-invoked).
      await controller.retry();

      expect(biometricCalls, 2);
    });

    test('retry() from non-error state does nothing', () async {
      int biometricCalls = 0;
      final biometric = CountingBiometric(
        outcome: const BiometricOutcome(result: BiometricResult.cancelled),
        onConfirm: () => biometricCalls++,
      );
      final controller = makeIngresoController(biometric: biometric);

      // Still in FichajeIdle — retry should be a no-op.
      await controller.retry();

      expect(biometricCalls, 0);
    });
  });

  // ── FichajeSyncService — verification forwarded to remote ─────────────────

  group('FichajeSyncService — verification forwarded to remote', () {
    FichajeSyncService makeSvc(FakeAttendanceRepo remote, FakeQueue queue) {
      return FichajeSyncService(
        queue: queue,
        remote: remote,
        // Must report online so triggerSync → _replayAll actually runs.
        connectivity: FakeOnlineConnectivity(),
      );
    }

    test('BIOMETRIC checkInVerification forwarded to remote.checkIn', () async {
      final remote = FakeAttendanceRepo();
      final item = makePendingItem(
        checkInVerification: VerificationMethod.biometric,
      );
      final queue = FakeQueue()..pendingItems = [item];
      final svc = makeSvc(remote, queue);
      await svc.init();
      await svc.triggerSync();

      expect(remote.lastCheckInVerification, VerificationMethod.biometric);
    });

    test('NONE checkInVerification forwarded to remote.checkIn', () async {
      final remote = FakeAttendanceRepo();
      final item = makePendingItem(checkInVerification: VerificationMethod.none);
      final queue = FakeQueue()..pendingItems = [item];
      final svc = makeSvc(remote, queue);
      await svc.init();
      await svc.triggerSync();

      expect(remote.lastCheckInVerification, VerificationMethod.none);
    });

    test('null checkInVerification forwarded as null', () async {
      final remote = FakeAttendanceRepo();
      final item = makePendingItem(); // no verification
      final queue = FakeQueue()..pendingItems = [item];
      final svc = makeSvc(remote, queue);
      await svc.init();
      await svc.triggerSync();

      expect(remote.lastCheckInVerification, isNull);
    });

    test('DEVICE_CREDENTIAL checkOutVerification forwarded to remote.checkOut',
        () async {
      final remote = FakeAttendanceRepo();
      final item = makePendingItem(
        checkOutVerification: VerificationMethod.deviceCredential,
        status: FichajeQueueStatus.salidaSigned,
      );
      final queue = FakeQueue()..pendingItems = [item];
      final svc = makeSvc(remote, queue);
      await svc.init();
      await svc.triggerSync();

      expect(
        remote.lastCheckOutVerification,
        VerificationMethod.deviceCredential,
      );
    });
  });

  // ── LiderNovedadActionController — biometric gate ─────────────────────────

  group('LiderNovedadActionController — biometric gate', () {
    test('approve: cancelled → aborts, repo not called, state is error',
        () async {
      final repo = SpyNovedadRepo();
      final container = ProviderContainer(
        overrides: [
          liderNovedadActionControllerProvider('nov-1').overrideWith(
            (ref) => LiderNovedadActionController(
              repository: repo,
              biometric: FakeBiometric(
                const BiometricOutcome(result: BiometricResult.cancelled),
              ),
              ref: ref,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(liderNovedadActionControllerProvider('nov-1').notifier)
          .approve('nov-1');

      final state =
          container.read(liderNovedadActionControllerProvider('nov-1'));
      expect(state, isA<LiderNovedadActionError>());
      expect(repo.lastApproveVerification, isNull);
    });

    test('reject: cancelled → aborts, repo not called', () async {
      final repo = SpyNovedadRepo();
      final container = ProviderContainer(
        overrides: [
          liderNovedadActionControllerProvider('nov-1').overrideWith(
            (ref) => LiderNovedadActionController(
              repository: repo,
              biometric: FakeBiometric(
                const BiometricOutcome(result: BiometricResult.cancelled),
              ),
              ref: ref,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(liderNovedadActionControllerProvider('nov-1').notifier)
          .reject('nov-1');

      expect(repo.lastRejectVerification, isNull);
    });

    test('approve: BIOMETRIC → repo receives BIOMETRIC, state is done',
        () async {
      final repo = SpyNovedadRepo();
      final container = ProviderContainer(
        overrides: [
          // Stub out the list provider so ref.invalidate() in the success path
          // does not trigger a real Dio call (requires ServicesBinding).
          novedadesListProvider.overrideWith((_) async => []),
          liderNovedadActionControllerProvider('nov-1').overrideWith(
            (ref) => LiderNovedadActionController(
              repository: repo,
              biometric: FakeBiometric(
                const BiometricOutcome(
                  result: BiometricResult.authenticated,
                  verification: VerificationMethod.biometric,
                ),
              ),
              ref: ref,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(liderNovedadActionControllerProvider('nov-1').notifier)
          .approve('nov-1');

      expect(repo.lastApproveVerification, VerificationMethod.biometric);
      final state =
          container.read(liderNovedadActionControllerProvider('nov-1'));
      expect(state, isA<LiderNovedadActionDone>());
    });

    test('reject: DEVICE_CREDENTIAL → repo receives DEVICE_CREDENTIAL',
        () async {
      final repo = SpyNovedadRepo();
      final container = ProviderContainer(
        overrides: [
          novedadesListProvider.overrideWith((_) async => []),
          liderNovedadActionControllerProvider('nov-1').overrideWith(
            (ref) => LiderNovedadActionController(
              repository: repo,
              biometric: FakeBiometric(
                const BiometricOutcome(
                  result: BiometricResult.authenticated,
                  verification: VerificationMethod.deviceCredential,
                ),
              ),
              ref: ref,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(liderNovedadActionControllerProvider('nov-1').notifier)
          .reject('nov-1');

      expect(
        repo.lastRejectVerification,
        VerificationMethod.deviceCredential,
      );
    });

    test('approve: unavailable biometric → repo receives NONE', () async {
      final repo = SpyNovedadRepo();
      final container = ProviderContainer(
        overrides: [
          novedadesListProvider.overrideWith((_) async => []),
          liderNovedadActionControllerProvider('nov-1').overrideWith(
            (ref) => LiderNovedadActionController(
              repository: repo,
              biometric: FakeBiometric(
                const BiometricOutcome(
                  result: BiometricResult.unavailable,
                  verification: VerificationMethod.none,
                ),
              ),
              ref: ref,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(liderNovedadActionControllerProvider('nov-1').notifier)
          .approve('nov-1');

      expect(repo.lastApproveVerification, VerificationMethod.none);
    });
  });
}
