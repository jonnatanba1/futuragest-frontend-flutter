import '../domain/user_profile.dart';

/// Maps the raw role string from the API to [UserRole].
UserRole roleFromString(String raw) {
  switch (raw) {
    case 'SYSTEM_ADMIN':
      return UserRole.systemAdmin;
    case 'GERENCIA':
      return UserRole.gerencia;
    case 'TALENTO_HUMANO':
      return UserRole.talentoHumano;
    case 'LIDER_OPERATIVO':
      return UserRole.liderOperativo;
    case 'COORDINADOR':
      return UserRole.coordinador;
    case 'SUPERVISOR':
      return UserRole.supervisor;
    default:
      // Fallback: surface the raw value rather than crash.
      throw ArgumentError('Unknown role: $raw');
  }
}

/// Maps a raw JSON map from GET /auth/me to a [UserProfile].
UserProfile userProfileFromJson(Map<String, dynamic> json) {
  final role = roleFromString(json['role'] as String);

  ZoneInfo? zone;
  SupervisorInfo? supervisor;

  if (role == UserRole.coordinador && json['zone'] != null) {
    final z = json['zone'] as Map<String, dynamic>;
    zone = ZoneInfo(
      id: z['id'] as String,
      name: z['name'] as String,
    );
  }

  if (role == UserRole.supervisor && json['supervisor'] != null) {
    final s = json['supervisor'] as Map<String, dynamic>;
    // Backend returns zone/municipio as { id, name } objects, not strings.
    final z = s['zone'] as Map<String, dynamic>;
    final m = s['municipio'] as Map<String, dynamic>;
    supervisor = SupervisorInfo(
      id: s['id'] as String,
      area: s['area'] as String,
      zone: z['name'] as String,
      municipio: m['name'] as String,
    );
  }

  return UserProfile(
    id: json['id'] as String,
    email: json['email'] as String,
    role: role,
    mustChangePassword: json['mustChangePassword'] as bool? ?? false,
    zone: zone,
    supervisor: supervisor,
  );
}
