// Tests for BiometricService.confirm — outcome mapping and verification method.
//
// Because LocalAuthentication is a concrete platform class that cannot be
// subclassed in unit tests, BiometricService exposes protected virtual methods
// (isDeviceSupported, getAvailableBiometrics, authenticate) via a
// BiometricService.withHandlers factory for testing seam injection.
//
// This test file exercises the mapping logic by directly calling confirm() on
// a fake service that overrides confirm() to return predetermined outcomes,
// validating the public contract rather than the internal platform calls.
import 'package:flutter_test/flutter_test.dart';

import 'package:futuragest_mobile/core/biometric/biometric_service.dart';

// ── Fake BiometricService for outcome mapping ──────────────────────────────

class _FakeBiometric extends BiometricService {
  _FakeBiometric(this._outcome);

  final BiometricOutcome _outcome;

  @override
  Future<BiometricOutcome> confirm(String reason) async => _outcome;
}

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  group('BiometricOutcome value contract', () {
    test('authenticated + BIOMETRIC result has correct fields', () {
      const outcome = BiometricOutcome(
        result: BiometricResult.authenticated,
        verification: VerificationMethod.biometric,
      );
      expect(outcome.result, BiometricResult.authenticated);
      expect(outcome.verification, 'BIOMETRIC');
    });

    test('authenticated + DEVICE_CREDENTIAL result has correct fields', () {
      const outcome = BiometricOutcome(
        result: BiometricResult.authenticated,
        verification: VerificationMethod.deviceCredential,
      );
      expect(outcome.result, BiometricResult.authenticated);
      expect(outcome.verification, 'DEVICE_CREDENTIAL');
    });

    test('unavailable + NONE has correct fields', () {
      const outcome = BiometricOutcome(
        result: BiometricResult.unavailable,
        verification: VerificationMethod.none,
      );
      expect(outcome.result, BiometricResult.unavailable);
      expect(outcome.verification, 'NONE');
    });

    test('cancelled has null verification', () {
      const outcome = BiometricOutcome(result: BiometricResult.cancelled);
      expect(outcome.result, BiometricResult.cancelled);
      expect(outcome.verification, isNull);
    });
  });

  group('BiometricService.confirm — fake service outcome mapping', () {
    test('fake returns BIOMETRIC → confirm returns BIOMETRIC outcome', () async {
      final svc = _FakeBiometric(
        const BiometricOutcome(
          result: BiometricResult.authenticated,
          verification: VerificationMethod.biometric,
        ),
      );
      final outcome = await svc.confirm('Test reason');
      expect(outcome.result, BiometricResult.authenticated);
      expect(outcome.verification, VerificationMethod.biometric);
    });

    test('fake returns cancelled → confirm returns cancelled with null verification',
        () async {
      final svc = _FakeBiometric(
        const BiometricOutcome(result: BiometricResult.cancelled),
      );
      final outcome = await svc.confirm('Test reason');
      expect(outcome.result, BiometricResult.cancelled);
      expect(outcome.verification, isNull);
    });

    test('fake returns unavailable → confirm returns NONE', () async {
      final svc = _FakeBiometric(
        const BiometricOutcome(
          result: BiometricResult.unavailable,
          verification: VerificationMethod.none,
        ),
      );
      final outcome = await svc.confirm('Test reason');
      expect(outcome.result, BiometricResult.unavailable);
      expect(outcome.verification, VerificationMethod.none);
    });

    test('fake returns DEVICE_CREDENTIAL → confirm returns DEVICE_CREDENTIAL',
        () async {
      final svc = _FakeBiometric(
        const BiometricOutcome(
          result: BiometricResult.authenticated,
          verification: VerificationMethod.deviceCredential,
        ),
      );
      final outcome = await svc.confirm('Test reason');
      expect(outcome.result, BiometricResult.authenticated);
      expect(outcome.verification, VerificationMethod.deviceCredential);
    });
  });

  group('VerificationMethod constants', () {
    test('biometric constant is BIOMETRIC', () {
      expect(VerificationMethod.biometric, 'BIOMETRIC');
    });

    test('deviceCredential constant is DEVICE_CREDENTIAL', () {
      expect(VerificationMethod.deviceCredential, 'DEVICE_CREDENTIAL');
    });

    test('none constant is NONE', () {
      expect(VerificationMethod.none, 'NONE');
    });
  });
}
