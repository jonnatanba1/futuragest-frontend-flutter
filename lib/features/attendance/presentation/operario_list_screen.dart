import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/widgets/notifications_sheet.dart';
import '../application/attendance_providers.dart';
import '../application/fichaje_sync_service.dart';
import '../domain/operario.dart';
import '../domain/pending_fichaje.dart';
import '../domain/ports/fichaje_queue_repository.dart';
import 'operario_detail_screen.dart';

/// Displays the list of operarios scoped to the logged-in supervisor.
///
/// Tapping any active operario opens [OperarioDetailScreen] where
/// ingreso, salida, and overtime actions are presented contextually.
class OperarioListScreen extends ConsumerStatefulWidget {
  const OperarioListScreen({super.key});

  @override
  ConsumerState<OperarioListScreen> createState() => _OperarioListScreenState();
}

class _OperarioListScreenState extends ConsumerState<OperarioListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showPendingSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PendingQueueSheet(
        repository: ref.read(fichajeQueueRepositoryProvider),
      ),
    );
  }

  String _formattedDate() {
    final now = DateTime.now();
    const months = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];
    const days = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
    final dayName = days[now.weekday - 1];
    return '$dayName ${now.day} de ${months[now.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final operariosAsync = ref.watch(operarioListProvider);
    final syncStats = ref.watch(syncStatsProvider);
    final recordedToday = ref.watch(recordedTodayProvider).valueOrNull ??
        const <String, TodayFichaje>{};

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: _buildGlassAppBar(context, syncStats),
      body: operariosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorView(
          message: error.toString(),
          onRetry: () {
            ref.invalidate(operarioListProvider);
            ref.invalidate(recordedTodayProvider);
          },
        ),
        data: (operarios) {
          String normalize(String text) {
            const withDia = 'ÀÁÂÃÄÅàáâãäåÒÓÔÕÕÖØòóôõöøÈÉÊËèéêëðÇçÐÌÍÎÏìíîïÙÚÛÜùúûüÑñŠšŸÿýŽž';
            const withoutDia = 'AAAAAAaaaaaaOOOOOOOooooooEEEEeeeeeCcDIIIIiiiiUUUUuuuuNnSsYyyZz';
            String res = text;
            for (int i = 0; i < withDia.length; i++) {
              res = res.replaceAll(withDia[i], withoutDia[i]);
            }
            return res.toLowerCase();
          }

          final filteredOperarios = operarios.where((o) {
            final query = normalize(_searchQuery.trim());
            if (query.isEmpty) return true;
            return normalize(o.fullName).contains(query) ||
                normalize(o.documento).contains(query);
          }).toList();

          return Column(
            children: [
              // Top safe area spacer
              SizedBox(height: MediaQuery.of(context).padding.top + kToolbarHeight + 16),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Lista de Asistencia',
                            style: GoogleFonts.manrope(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF1a1c1e),
                            ),
                          ),
                          Text(
                            _formattedDate(),
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              color: const Color(0xFF3e4944),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                      ),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Buscar operario (nombre o cédula)...',
                          prefixIcon: const Icon(Icons.search, color: Color(0xFF3e4944)),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () => _searchController.clear(),
                                )
                              : null,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          hintStyle: const TextStyle(color: Color(0xFF6e7a74)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // List
              Expanded(
                child: _OperarioList(
                  operarios: filteredOperarios,
                  recordedToday: recordedToday,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildGlassAppBar(BuildContext context, SyncStats syncStats) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: AppBar(
            backgroundColor: Colors.white.withValues(alpha: 0.7),
            elevation: 0,
            centerTitle: true,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/isotipo.png',
                  height: 26,
                  width: 26,
                ),
                const SizedBox(width: 8),
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFF005f48), Color(0xFF00597d)],
                  ).createShader(bounds),
                  child: Text(
                    'FuturaGest',
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              _SyncStatusChip(
                stats: syncStats,
                onTap: () => _showPendingSheet(context),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.notifications_none_outlined),
                tooltip: 'Notificaciones',
                onPressed: () => showNotificationsSheet(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sync status chip ───────────────────────────────────────────────────────

class _SyncStatusChip extends StatelessWidget {
  const _SyncStatusChip({required this.stats, this.onTap});

  final SyncStats stats;
  final VoidCallback? onTap;

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
      return ActionChip(
        avatar: const Icon(Icons.error_outline, size: 14, color: Colors.red),
        label: Text(
          '${stats.failed} con error',
          style: const TextStyle(fontSize: 11),
        ),
        padding: EdgeInsets.zero,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        tooltip: 'Ver fichajes con error',
        onPressed: onTap,
      );
    }

    if (stats.pending > 0) {
      return ActionChip(
        avatar: const Icon(Icons.cloud_upload_outlined, size: 14),
        label: Text(
          '${stats.pending} pendiente${stats.pending == 1 ? '' : 's'}',
          style: const TextStyle(fontSize: 11),
        ),
        padding: EdgeInsets.zero,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        tooltip: 'Ver fichajes pendientes de sincronizar',
        onPressed: onTap,
      );
    }

    return const SizedBox.shrink();
  }
}

// ── Private widgets ────────────────────────────────────────────────────────

class _OperarioList extends StatelessWidget {
  const _OperarioList({required this.operarios, required this.recordedToday});

  final List<Operario> operarios;

  /// operarioId -> today's fichaje state. Absent = no record today.
  final Map<String, TodayFichaje> recordedToday;

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

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      itemCount: operarios.length,
      itemBuilder: (context, index) {
        final operario = operarios[index];
        return _OperarioTile(
          operario: operario,
          today: recordedToday[operario.id],
        );
      },
    );
  }
}

class _OperarioTile extends ConsumerWidget {
  const _OperarioTile({required this.operario, required this.today});

  final Operario operario;

  /// Today's fichaje state for this operario; null when there is no record yet.
  final TodayFichaje? today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final completed = today?.completed ?? false;
    final hasOpenRecord = today != null && !completed;

    final statusLabel = completed
        ? 'PRESENTE'
        : hasOpenRecord
            ? 'TARDE'
            : operario.active
                ? 'AUSENTE'
                : 'INACTIVO';
    final statusColor = completed
        ? const Color(0xFF005f48)
        : hasOpenRecord
            ? const Color(0xFFff8a00)
            : operario.active
                ? const Color(0xFFba1a1a)
                : const Color(0xFF6e7a74);

    final avatarLetter = operario.fullName.isNotEmpty
        ? operario.fullName[0].toUpperCase()
        : '?';

    return GestureDetector(
      onTap: operario.active
          ? () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      OperarioDetailScreen(operario: operario),
                ),
              );
              ref.invalidate(recordedTodayProvider);
            }
          : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFFbdc9c2).withValues(alpha: 0.1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar with color ring
            Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: statusColor, width: 2),
              ),
              child: CircleAvatar(
                radius: 24,
                backgroundColor: statusColor.withValues(alpha: 0.1),
                child: Text(
                  avatarLetter,
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Name + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    operario.fullName,
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1a1c1e),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Doc: ${operario.documento}',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: const Color(0xFF3e4944),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Status chip + chevron
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _StatusPill(
                  label: statusLabel,
                  color: statusColor,
                  icon: completed
                      ? Icons.check_circle
                      : hasOpenRecord
                          ? Icons.schedule
                          : operario.active
                              ? Icons.cancel
                              : Icons.block,
                ),
                if (operario.active) ...[
                  const SizedBox(height: 6),
                  const Icon(
                    Icons.chevron_right,
                    color: Color(0xFF6e7a74),
                    size: 20,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

}

// ── Status pill chip ───────────────────────────────────────────────────────

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.icon,
  });
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.10),
            color.withValues(alpha: 0.18),
          ],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Pending queue bottom sheet ──────────────────────────────────────────────

class _PendingQueueSheet extends StatelessWidget {
  const _PendingQueueSheet({required this.repository});

  final FichajeQueueRepository repository;

  String _statusLabel(FichajeQueueStatus s) {
    switch (s) {
      case FichajeQueueStatus.pendingCheckIn:
        return 'Esperando enviar ingreso';
      case FichajeQueueStatus.checkedIn:
        return 'Subiendo foto de ingreso…';
      case FichajeQueueStatus.ingresoComplete:
        return 'Ingreso completo — esperando salida';
      case FichajeQueueStatus.salidaSigned:
        return 'Esperando enviar salida';
      case FichajeQueueStatus.failed:
        return 'Error al sincronizar';
      case FichajeQueueStatus.completed:
        return 'Completado';
    }
  }

  IconData _statusIcon(FichajeQueueStatus s) {
    if (s == FichajeQueueStatus.failed) return Icons.error_outline;
    if (s == FichajeQueueStatus.ingresoComplete) return Icons.hourglass_top_outlined;
    return Icons.cloud_upload_outlined;
  }

  Color _statusColor(FichajeQueueStatus s, ColorScheme cs) {
    if (s == FichajeQueueStatus.failed) return cs.error;
    if (s == FichajeQueueStatus.ingresoComplete) return cs.tertiary;
    return cs.primary;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (_, scrollController) {
        return Column(
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
              child: Row(
                children: [
                  Icon(Icons.cloud_upload_outlined, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Fichajes pendientes de sincronizar',
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<List<PendingFichaje>>(
                future: repository.listPending(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final items = snapshot.data ?? [];
                  if (items.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.cloud_done_outlined, size: 48, color: cs.outlineVariant),
                          const SizedBox(height: 12),
                          Text('Todo sincronizado', style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                    itemBuilder: (_, i) {
                      final f = items[i];
                      final color = _statusColor(f.status, cs);
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withValues(alpha: 0.12),
                          child: Icon(
                            _statusIcon(f.status),
                            color: color,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          f.operarioName,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text('${f.date} · ${_statusLabel(f.status)}'),
                        trailing: f.status == FichajeQueueStatus.failed && f.failureReason != null
                            ? Tooltip(
                                message: f.failureReason!,
                                child: Icon(Icons.info_outline, size: 16, color: cs.error),
                              )
                            : null,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
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
