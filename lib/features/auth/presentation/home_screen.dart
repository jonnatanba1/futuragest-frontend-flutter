import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/push/push_messaging_service.dart';
import '../../../features/attendance/presentation/operario_list_screen.dart';
import '../../../features/novedades/presentation/lider_novedades_screen.dart';
import '../../../features/novedades/presentation/novedades_list_screen.dart';
import '../application/auth_providers.dart';
import '../domain/user_profile.dart';

/// Home screen shown after a successful login.
/// Triggers FCM push-token registration on first mount (post-auth hook).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Initialize FCM after authentication is complete. Non-blocking and
    // failure-safe — a push failure must never break the core app flow.
    _initPush();
  }

  Future<void> _initPush() async {
    try {
      await ref.read(pushMessagingServiceProvider).initialize();
    } catch (e) {
      dev.log(
        '[HomeScreen] Push initialization failed (non-fatal): $e',
        name: 'push',
      );
    }
  }

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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = widget.profile;

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
              // Attendance + novedades entry points — only shown for SUPERVISOR role.
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
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const NovedadesListScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.schedule),
                  label: const Text('Mis novedades'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
              // Novedades approval — shown for LIDER_OPERATIVO and SYSTEM_ADMIN.
              if (profile.role == UserRole.liderOperativo ||
                  profile.role == UserRole.systemAdmin) ...[
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const LiderNovedadesScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.task_alt),
                  label: const Text('Novedades pendientes'),
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
