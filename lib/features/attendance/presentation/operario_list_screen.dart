import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/attendance_providers.dart';
import '../application/fichaje_sync_service.dart';
import '../domain/operario.dart';
import 'fichaje_screen.dart';

/// Displays the list of operarios scoped to the logged-in supervisor.
/// Tapping an operario navigates to [FichajeScreen] to start the fichaje flow.
class OperarioListScreen extends ConsumerWidget {
  const OperarioListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operariosAsync = ref.watch(operarioListProvider);
    final syncStats = ref.watch(syncStatsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tomar asistencia'),
        actions: [
          _SyncStatusChip(stats: syncStats),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar lista',
            onPressed: () => ref.invalidate(operarioListProvider),
          ),
        ],
      ),
      body: operariosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorView(
          message: error.toString(),
          onRetry: () => ref.invalidate(operarioListProvider),
        ),
        data: (operarios) => _OperarioList(operarios: operarios),
      ),
    );
  }
}

// ── Sync status chip ───────────────────────────────────────────────────────

class _SyncStatusChip extends StatelessWidget {
  const _SyncStatusChip({required this.stats});

  final SyncStats stats;

  @override
  Widget build(BuildContext context) {
    if (stats.syncing) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 6),
            Text('Sincronizando…', style: TextStyle(fontSize: 12)),
          ],
        ),
      );
    }

    if (stats.failed > 0) {
      return Chip(
        avatar: const Icon(Icons.error_outline, size: 14, color: Colors.red),
        label: Text(
          '${stats.failed} con error',
          style: const TextStyle(fontSize: 11),
        ),
        padding: EdgeInsets.zero,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }

    if (stats.pending > 0) {
      return Chip(
        avatar: const Icon(Icons.cloud_off, size: 14),
        label: Text(
          '${stats.pending} pendiente${stats.pending == 1 ? '' : 's'}',
          style: const TextStyle(fontSize: 11),
        ),
        padding: EdgeInsets.zero,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
    }

    // Up to date — show nothing (no clutter when everything is synced).
    return const SizedBox.shrink();
  }
}

// ── Private widgets ────────────────────────────────────────────────────────

class _OperarioList extends StatelessWidget {
  const _OperarioList({required this.operarios});

  final List<Operario> operarios;

  @override
  Widget build(BuildContext context) {
    if (operarios.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No tenés operarios asignados.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: operarios.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final operario = operarios[index];
        return _OperarioTile(operario: operario);
      },
    );
  }
}

class _OperarioTile extends StatelessWidget {
  const _OperarioTile({required this.operario});

  final Operario operario;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Text(
          operario.fullName.isNotEmpty
              ? operario.fullName[0].toUpperCase()
              : '?',
          style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
        ),
      ),
      title: Text(operario.fullName),
      subtitle: Text('Doc: ${operario.documento}'),
      trailing: const Icon(Icons.chevron_right),
      enabled: operario.active,
      onTap: operario.active
          ? () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FichajeScreen(operario: operario),
                ),
              );
            }
          : null,
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'No se pudo cargar la lista de operarios.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
