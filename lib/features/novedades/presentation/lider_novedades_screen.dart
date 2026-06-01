import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/lider_novedad_action_controller.dart';
import '../application/lider_novedad_action_state.dart';
import '../application/novedad_providers.dart';
import '../domain/novedad.dart';

/// LIDER_OPERATIVO screen: lists all novedades across all zones.
///
/// Defaults to the PENDING tab for quick approval. A second tab shows all
/// already-decided records (approved + rejected) for reference.
/// Pull-to-refresh re-fetches GET /novedades.
class LiderNovedadesScreen extends ConsumerWidget {
  const LiderNovedadesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Novedades pendientes'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Pendientes'),
              Tab(text: 'Historial'),
            ],
          ),
        ),
        body: const _NovedadesTabBody(),
      ),
    );
  }
}

class _NovedadesTabBody extends ConsumerWidget {
  const _NovedadesTabBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final novedadesAsync = ref.watch(novedadesListProvider);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(novedadesListProvider.future),
      child: novedadesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorBody(
          message: err is Exception ? err.toString() : 'Error desconocido.',
          onRetry: () => ref.invalidate(novedadesListProvider),
        ),
        data: (novedades) {
          final pending = novedades
              .where((n) => n.status == NovedadStatus.pending)
              .toList();
          final decided = novedades
              .where((n) => n.status != NovedadStatus.pending)
              .toList();

          return TabBarView(
            children: [
              _NovedadesList(
                novedades: pending,
                emptyMessage: 'Sin novedades pendientes.',
                emptySubtitle: 'Todas las novedades han sido revisadas.',
                showActions: true,
              ),
              _NovedadesList(
                novedades: decided,
                emptyMessage: 'Sin historial todavía.',
                emptySubtitle: 'Las novedades decididas aparecerán acá.',
                showActions: false,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Novedad list ────────────────────────────────────────────────────────────

class _NovedadesList extends StatelessWidget {
  const _NovedadesList({
    required this.novedades,
    required this.emptyMessage,
    required this.emptySubtitle,
    required this.showActions,
  });

  final List<Novedad> novedades;
  final String emptyMessage;
  final String emptySubtitle;
  final bool showActions;

  @override
  Widget build(BuildContext context) {
    if (novedades.isEmpty) {
      return _EmptyBody(message: emptyMessage, subtitle: emptySubtitle);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: novedades.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _LiderNovedadCard(
        novedad: novedades[index],
        showActions: showActions,
      ),
    );
  }
}

// ── Novedad card ────────────────────────────────────────────────────────────

class _LiderNovedadCard extends ConsumerWidget {
  const _LiderNovedadCard({
    required this.novedad,
    required this.showActions,
  });

  final Novedad novedad;
  final bool showActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final actionState =
        ref.watch(liderNovedadActionControllerProvider(novedad.id));

    // Show snackbar once on done/error, then reset.
    ref.listen<LiderNovedadActionState>(
      liderNovedadActionControllerProvider(novedad.id),
      (previous, next) {
        if (!context.mounted) return;
        if (next is LiderNovedadActionDone) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(next.message),
              backgroundColor: Colors.green.shade700,
            ),
          );
          ref
              .read(liderNovedadActionControllerProvider(novedad.id).notifier)
              .reset();
        } else if (next is LiderNovedadActionError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(next.message),
              backgroundColor: theme.colorScheme.error,
            ),
          );
          ref
              .read(liderNovedadActionControllerProvider(novedad.id).notifier)
              .reset();
        }
      },
    );

    final isActing = actionState is LiderNovedadActionActing;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: date + status ──────────────────────────────────────
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 16,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _formatDate(novedad.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                ),
                _StatusChip(status: novedad.status),
              ],
            ),
            const SizedBox(height: 12),

            // ── Horas extra ────────────────────────────────────────────────
            Text(
              '${_formatHoras(novedad.horasExtra)} hs extra',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),

            // ── Zone info ──────────────────────────────────────────────────
            if (novedad.zoneId != null) ...[
              const SizedBox(height: 4),
              Text(
                'Zona: ${novedad.zoneId}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],

            // ── Motivo ─────────────────────────────────────────────────────
            if (novedad.motivo != null && novedad.motivo!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                novedad.motivo!,
                style: theme.textTheme.bodyMedium,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // ── Decision info (history tab) ────────────────────────────────
            if (novedad.status != NovedadStatus.pending &&
                novedad.decidedAt != null) ...[
              const SizedBox(height: 8),
              Text(
                '${novedad.status == NovedadStatus.approved ? 'Aprobada' : 'Rechazada'} el ${_formatDate(novedad.decidedAt!)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.secondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],

            // ── Action buttons (pending tab only) ──────────────────────────
            if (showActions) ...[
              const SizedBox(height: 16),
              isActing
                  ? const Center(child: CircularProgressIndicator())
                  : Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => ref
                                .read(
                                  liderNovedadActionControllerProvider(
                                          novedad.id)
                                      .notifier,
                                )
                                .approve(novedad.id),
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('Aprobar'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _confirmReject(context, ref, novedad.id),
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Rechazar'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: theme.colorScheme.error,
                              side: BorderSide(
                                  color: theme.colorScheme.error),
                            ),
                          ),
                        ),
                      ],
                    ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmReject(
    BuildContext context,
    WidgetRef ref,
    String novedadId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar novedad'),
        content: const Text(
          '¿Estás seguro de que querés rechazar esta novedad? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref
          .read(liderNovedadActionControllerProvider(novedadId).notifier)
          .reject(novedadId);
    }
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    final y = local.year.toString();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$d/$mo/$y $h:$m';
  }

  String _formatHoras(String horasExtra) {
    final d = double.tryParse(horasExtra);
    if (d == null) return horasExtra;
    if (d == d.truncateToDouble()) return d.toInt().toString();
    return d.toStringAsFixed(2);
  }
}

// ── Status chip ─────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final NovedadStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (status) {
      NovedadStatus.pending => ('Pendiente', theme.colorScheme.tertiary),
      NovedadStatus.approved => ('Aprobada', Colors.green.shade700),
      NovedadStatus.rejected => ('Rechazada', theme.colorScheme.error),
    };

    return Chip(
      label: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: color,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}

// ── Empty body ───────────────────────────────────────────────────────────────

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.message, required this.subtitle});

  final String message;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 72,
              color: theme.colorScheme.secondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.secondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.secondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error body ───────────────────────────────────────────────────────────────

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Error al cargar las novedades',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.error),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
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
