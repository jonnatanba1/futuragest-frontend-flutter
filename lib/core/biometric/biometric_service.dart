import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:flutter/services.dart';

/// Thrown when biometric authentication fails or is unavailable.
class BiometricException implements Exception {
  const BiometricException(this.message);

  final String message;

  @override
  String toString() => 'BiometricException: $message';
}

/// Result from [BiometricService.confirm].
enum BiometricResult {
  /// User authenticated successfully.
  authenticated,

  /// User cancelled the prompt or failed authentication.
  cancelled,

  /// The device has no biometric hardware or none enrolled.
  /// The caller may degrade gracefully (allow without biometric).
  unavailable,
}

/// Local biometric gate — wraps [LocalAuthentication].
///
/// Nothing biometric is sent to the backend; this is purely an on-device
/// identity confirmation before a fichaje action is committed.
///
/// Usage:
///   final result = await biometricService.confirm('Confirmá tu identidad para registrar la entrada.');
class BiometricService {
  BiometricService() : _auth = LocalAuthentication();

  // Visible for testing.
  BiometricService.withAuth(LocalAuthentication auth) : _auth = auth;

  final LocalAuthentication _auth;

  /// Whether biometric confirmation is required. When [false] (e.g. the device
  /// has no biometric sensor), the fichaje action is allowed to proceed without
  /// biometric gate.
  ///
  /// Default [true]. Set to [false] only when the device genuinely reports no
  /// biometric support so real supervisors on low-end devices aren't blocked.
  ///
  /// TODO(STEP 3): make this a remote-config flag so ops can toggle it per fleet.
  bool requireBiometric = true;

  /// Asks the supervisor to confirm their identity via biometric.
  ///
  /// Returns [BiometricResult.authenticated] on success.
  /// Returns [BiometricResult.cancelled] when the user dismisses the prompt.
  /// Returns [BiometricResult.unavailable] when the device has no biometric
  /// hardware or no enrolled biometrics — the caller may allow the action
  /// without biometric if [requireBiometric] is [false].
  ///
  /// Throws [BiometricException] only for unexpected platform errors.
  Future<BiometricResult> confirm(String reason) async {
    try {
      // 1. Check hardware support.
      final bool isDeviceSupported = await _auth.isDeviceSupported();
      if (!isDeviceSupported) {
        requireBiometric = false; // degrade automatically
        return BiometricResult.unavailable;
      }

      // 2. Check whether any biometric is enrolled.
      final bool canCheck = await _auth.canCheckBiometrics;
      if (!canCheck) {
        requireBiometric = false;
        return BiometricResult.unavailable;
      }

      // 3. Attempt authentication.
      final bool authenticated = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // allow PIN fallback on Android
        ),
      );

      return authenticated
          ? BiometricResult.authenticated
          : BiometricResult.cancelled;
    } on PlatformException catch (e) {
      // NotEnrolled / NotAvailable → degrade
      if (e.code == auth_error.notEnrolled ||
          e.code == auth_error.notAvailable ||
          e.code == auth_error.passcodeNotSet) {
        requireBiometric = false;
        return BiometricResult.unavailable;
      }
      // lockedOut / permanentlyLockedOut
      if (e.code == auth_error.lockedOut ||
          e.code == auth_error.permanentlyLockedOut) {
        throw const BiometricException(
          'El sensor biométrico está bloqueado. Desbloqueá el dispositivo con tu PIN e intentá de nuevo.',
        );
      }
      throw BiometricException(
        'Error inesperado en la autenticación biométrica: ${e.message}',
      );
    }
  }
}
