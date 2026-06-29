import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:flutter/services.dart';

/// Thrown when biometric authentication fails with an unrecoverable platform
/// error (e.g. lockedOut, permanentlyLockedOut).
class BiometricException implements Exception {
  const BiometricException(this.message);

  final String message;

  @override
  String toString() => 'BiometricException: $message';
}

/// High-level outcome of a biometric confirmation attempt.
enum BiometricResult {
  /// User authenticated successfully.
  authenticated,

  /// User cancelled the prompt or failed authentication.
  cancelled,

  /// The device cannot verify the user (no hardware, no enrolled biometrics,
  /// or passcode not set). Callers may degrade gracefully.
  unavailable,
}

/// Wire-compatible verification method string constants.
///
/// These match the backend VerificationMethod enum exactly.
/// AUDIT LABELS ONLY — no authorization logic may depend on these values.
abstract final class VerificationMethod {
  static const String biometric = 'BIOMETRIC';
  static const String deviceCredential = 'DEVICE_CREDENTIAL';
  static const String none = 'NONE';
}

/// Result from [BiometricService.confirm] that includes both the outcome and
/// the audit label for the method used.
///
/// [verification] is non-null only when [result] == [BiometricResult.authenticated]
/// or [BiometricResult.unavailable].  It is null on [BiometricResult.cancelled].
class BiometricOutcome {
  const BiometricOutcome({required this.result, this.verification});

  final BiometricResult result;

  /// Wire string for the backend audit field: 'BIOMETRIC' | 'DEVICE_CREDENTIAL'
  /// | 'NONE' | null (cancelled — no method label).
  final String? verification;
}

/// Local biometric gate — wraps [LocalAuthentication].
///
/// Nothing biometric is sent to the backend; this is purely an on-device
/// identity confirmation before a fichaje or novedad action is committed.
/// The [BiometricOutcome.verification] label is an audit field only.
///
/// Logic:
///   1. Device unsupported → (unavailable, NONE).
///   2. Biometrics enrolled → biometricOnly:true.
///      - success → (authenticated, BIOMETRIC).
///      - lockedOut → fallback to deviceCredential.
///   3. No biometrics enrolled but device has a credential →
///      biometricOnly:false → (authenticated, DEVICE_CREDENTIAL).
///   4. passcodeNotSet → (unavailable, NONE).
///   5. User cancel at any point → (cancelled, null).
///
/// Throws [BiometricException] only for unrecoverable platform errors that
/// are not lock-outs and cannot be gracefully degraded.
class BiometricService {
  BiometricService() : _auth = LocalAuthentication();

  // Visible for testing.
  BiometricService.withAuth(LocalAuthentication auth) : _auth = auth;

  final LocalAuthentication _auth;

  /// Asks the user to confirm their identity via biometric or device credential.
  ///
  /// Returns a [BiometricOutcome] that carries:
  ///   - the high-level [BiometricResult], and
  ///   - the [VerificationMethod] string used (null when cancelled).
  ///
  /// Never throws unless the platform raises an unexpected error.
  Future<BiometricOutcome> confirm(String reason) async {
    try {
      // 1. Check hardware support.
      final bool isDeviceSupported = await _auth.isDeviceSupported();
      if (!isDeviceSupported) {
        return const BiometricOutcome(
          result: BiometricResult.unavailable,
          verification: VerificationMethod.none,
        );
      }

      // 2. Check enrolled biometrics.
      final List<BiometricType> available = await _auth.getAvailableBiometrics();
      final bool hasBiometrics = available.isNotEmpty;

      if (hasBiometrics) {
        return await _authenticateBiometric(reason);
      }

      // 3. No biometrics enrolled — attempt device credential (PIN/pattern/password).
      return await _authenticateDeviceCredential(reason);
    } on PlatformException catch (e) {
      // notEnrolled / notAvailable → degrade gracefully.
      if (e.code == auth_error.notEnrolled ||
          e.code == auth_error.notAvailable) {
        return const BiometricOutcome(
          result: BiometricResult.unavailable,
          verification: VerificationMethod.none,
        );
      }
      if (e.code == auth_error.passcodeNotSet) {
        return const BiometricOutcome(
          result: BiometricResult.unavailable,
          verification: VerificationMethod.none,
        );
      }
      throw BiometricException(
        'Error inesperado en la autenticación biométrica: ${e.message}',
      );
    }
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  /// Attempts biometric-only authentication.
  ///
  /// On lockout, falls back to device credential.
  Future<BiometricOutcome> _authenticateBiometric(String reason) async {
    try {
      final bool ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      if (!ok) {
        return const BiometricOutcome(result: BiometricResult.cancelled);
      }
      return const BiometricOutcome(
        result: BiometricResult.authenticated,
        verification: VerificationMethod.biometric,
      );
    } on PlatformException catch (e) {
      if (e.code == auth_error.lockedOut ||
          e.code == auth_error.permanentlyLockedOut) {
        // Sensor is locked — fall back to device credential.
        return await _authenticateDeviceCredential(reason);
      }
      // notEnrolled / notAvailable at this level → degrade.
      if (e.code == auth_error.notEnrolled ||
          e.code == auth_error.notAvailable) {
        return const BiometricOutcome(
          result: BiometricResult.unavailable,
          verification: VerificationMethod.none,
        );
      }
      rethrow;
    }
  }

  /// Attempts authentication with any device credential (PIN / pattern / password).
  Future<BiometricOutcome> _authenticateDeviceCredential(String reason) async {
    try {
      final bool ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
      if (!ok) {
        return const BiometricOutcome(result: BiometricResult.cancelled);
      }
      return const BiometricOutcome(
        result: BiometricResult.authenticated,
        verification: VerificationMethod.deviceCredential,
      );
    } on PlatformException catch (e) {
      if (e.code == auth_error.passcodeNotSet) {
        return const BiometricOutcome(
          result: BiometricResult.unavailable,
          verification: VerificationMethod.none,
        );
      }
      if (e.code == auth_error.lockedOut ||
          e.code == auth_error.permanentlyLockedOut) {
        throw const BiometricException(
          'El sensor biométrico está bloqueado. Desbloqueá el dispositivo con tu PIN e intentá de nuevo.',
        );
      }
      rethrow;
    }
  }
}
