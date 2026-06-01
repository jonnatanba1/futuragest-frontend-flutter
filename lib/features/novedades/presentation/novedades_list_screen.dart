import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/novedad_providers.dart';
import '../domain/novedad.dart';

/// Displays the full list of novedades scoped to the logged-in supervisor.
///
/// Reachable from HomeScreen via "Mis novedades" button (SUPERVISOR role only).
/// Pull-to-refresh re-fetches GET /novedades.
class NovedadesListScreen extends ConsumerWidget {
  const NovedadesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final novedadesAsync = ref.watch(novedadesListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis novedades'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(novedadesListProvider.future),
        child: novedadesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => _ErrorBody(
            message: err is Exception ? err.toString() : 'Error desconocido.',
            onRetry: () => ref.invalidate(novedadesListProvider),
          ),
          data: (novedades) {
            if (novedades.isEmpty) {
              return const _EmptyBody();
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: novedades.length,
              separatorBuilder: (context2, idx) => const SizedBox(height: 8),
              itemBuilder: (context, index) =>
                  _NovedadCard(novedad: novedades[index]),
            );
          },
        ),
      ),
    );
  }
}

// ── Card ───────────────────────────────────────────────────────────────────

class _NovedadCard extends StatelessWidget {
  const _NovedadCard({required this.novedad});

  final Novedad novedad;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formattedDate = _formatDate(novedad.createdAt);
    final horasLabel = _formatHoras(novedad.horasExtra);

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row: date + status chip ─────────────────────────────
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
                    formattedDate,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                ),
                _StatusChip(status: novedad.status),
              ],
            ),
            const SizedBox(height: 12),

            // ── Horas extra ─────────────────────────────────────────────────
            Text(
              horasLabel,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'horas extra',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.secondary,
              ),
            ),

            // ── Motivo ─────────────────────────────────────────────────────
            if (novedad.motivo != null && novedad.motivo!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                novedad.motivo!,
                style: theme.textTheme.bodyMedium,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // ── Decision info (for approved/rejected) ──────────────────────
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
          ],
        ),
      ),
    );
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
    // Show as integer if no decimal part, otherwise two decimal places.
    if (d == d.truncateToDouble()) return d.toInt().toString();
    return d.toStringAsFixed(2);
  }
}

// ── Status chip ────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final NovedadStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (label, color) = switch (status) {
      NovedadStatus.pending => (
          'Pendiente',
          theme.colorScheme.tertiary,
        ),
      NovedadStatus.approved => (
          'Aprobada',
          Colors.green.shade700,
        ),
      NovedadStatus.rejected => (
          'Rechazada',
          theme.colorScheme.error,
        ),
    };

    return Chip(
      label: Text(
        label,
        style: TextStyle(
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

// ── Empty / error bodies ───────────────────────────────────────────────────

class _EmptyBody extends StatelessWidget {
  const _EmptyBody();

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
              'Sin novedades todavía',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.secondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Las horas extra que registrés aparecerán acá.',
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
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Error al cargar las novedades',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
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
