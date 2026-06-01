import '../domain/novedad.dart';

/// Sealed state for the create-novedad form flow.
///
/// State machine:
///   CreateNovedadIdle
///     → CreateNovedadSubmitting (POST in progress)
///     → CreateNovedadSuccess(novedad)
///     → CreateNovedadError(message) (recoverable — user can fix input and retry)
sealed class CreateNovedadState {
  const CreateNovedadState();
}

/// Form is idle — ready for user input.
final class CreateNovedadIdle extends CreateNovedadState {
  const CreateNovedadIdle();
}

/// POST request in flight.
final class CreateNovedadSubmitting extends CreateNovedadState {
  const CreateNovedadSubmitting();
}

/// Novedad created successfully.
final class CreateNovedadSuccess extends CreateNovedadState {
  const CreateNovedadSuccess(this.novedad);

  final Novedad novedad;
}

/// A recoverable error occurred. The user can correct input and retry.
final class CreateNovedadError extends CreateNovedadState {
  const CreateNovedadError(this.message);

  final String message;
}
