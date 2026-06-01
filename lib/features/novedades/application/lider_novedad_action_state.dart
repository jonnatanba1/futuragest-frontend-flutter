/// Per-novedad action state for the LIDER_OPERATIVO approval/rejection flow.
sealed class LiderNovedadActionState {
  const LiderNovedadActionState();
}

/// No action in progress.
final class LiderNovedadActionIdle extends LiderNovedadActionState {
  const LiderNovedadActionIdle();
}

/// An approve or reject call is in flight for this novedad.
final class LiderNovedadActionActing extends LiderNovedadActionState {
  const LiderNovedadActionActing();
}

/// The action completed successfully.
final class LiderNovedadActionDone extends LiderNovedadActionState {
  const LiderNovedadActionDone(this.message);

  final String message;
}

/// The action failed. [isAlreadyDecided] is true when the backend returned 409.
final class LiderNovedadActionError extends LiderNovedadActionState {
  const LiderNovedadActionError({
    required this.message,
    this.isAlreadyDecided = false,
  });

  final String message;
  final bool isAlreadyDecided;
}
