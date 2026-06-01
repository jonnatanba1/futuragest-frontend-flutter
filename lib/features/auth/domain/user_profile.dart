/// Discriminated role values returned by the backend.
enum UserRole {
  systemAdmin,
  gerencia,
  talentoHumano,
  liderOperativo,
  coordinador,
  supervisor,
}

/// Minimal zone info attached to COORDINADOR profiles.
class ZoneInfo {
  const ZoneInfo({required this.id, required this.name});

  final String id;
  final String name;
}

/// Minimal supervisor info attached to SUPERVISOR profiles.
class SupervisorInfo {
  const SupervisorInfo({
    required this.id,
    required this.area,
    required this.zone,
    required this.municipio,
  });

  final String id;
  final String area;
  final String zone;
  final String municipio;
}

/// Profile returned by GET /auth/me after a successful login.
/// Role-discriminated — only COORDINADOR populates [zone],
/// only SUPERVISOR populates [supervisor].
class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.role,
    required this.mustChangePassword,
    this.zone,
    this.supervisor,
  });

  final String id;
  final String email;
  final UserRole role;
  final bool mustChangePassword;

  // Role-specific extras (null for roles that don't carry them)
  final ZoneInfo? zone;
  final SupervisorInfo? supervisor;
}
