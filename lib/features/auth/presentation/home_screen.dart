import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/attendance/presentation/operario_list_screen.dart';
import '../application/auth_providers.dart';
import '../domain/user_profile.dart';

/// Minimal home screen shown after a successful login.
/// Displays email + role to prove the /auth/me round-trip works.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.profile});

  final UserProfile profile;

  String _roleLabel(UserRole role) {
    switch (role) {
      case UserRole.systemAdmin:
        return 'Administrador del sistema';
      case UserRole.gerencia:
        return 'Gerencia';
      case UserRole.talentoHumano:
        return 'Talento Humano';
      case UserRole.liderOperativo:
        return 'Líder Operativo';
      case UserRole.coordinador:
        return 'Coordinador';
      case UserRole.supervisor:
        return 'Supervisor';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('FuturaGest'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              // Clear tokens and go back to login.
              await ref.read(tokenStorageProvider).clearAll();
              if (context.mounted) {
                Navigator.of(context).pushReplacementNamed('/login');
              }
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline,
                color: theme.colorScheme.primary,
                size: 64,
              ),
              const SizedBox(height: 24),
              Text(
                'Bienvenido',
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                profile.email,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Rol: ${_roleLabel(profile.role)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.secondary,
                ),
              ),
              if (profile.mustChangePassword) ...[
                const SizedBox(height: 16),
                // TODO(next-slice): Navigate to ChangePasswordScreen
                // when mustChangePassword == true.
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Debe cambiar su contraseña antes de continuar.',
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ],
              // Attendance entry point — only shown for SUPERVISOR role.
              if (profile.role == UserRole.supervisor) ...[
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const OperarioListScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.assignment_ind),
                  label: const Text('Tomar asistencia'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
