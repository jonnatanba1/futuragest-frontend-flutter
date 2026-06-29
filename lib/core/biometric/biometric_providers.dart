import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'biometric_service.dart';

/// Shared provider for the [BiometricService] singleton.
///
/// Lives in core so both the attendance feature and the novedades feature can
/// import it without creating a feature → feature dependency.
final biometricServiceProvider = Provider<BiometricService>(
  (ref) => BiometricService(),
);
