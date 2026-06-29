import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/widgets/notifications_sheet.dart';
import '../application/novedad_providers.dart';
import '../domain/novedad.dart';
import 'novedad_detail_screen.dart';

/// LIDER_OPERATIVO screen: lists all novedades across all zones.
///
/// Defaults to the PENDING tab for quick approval. A second tab shows all
/// already-decided records (approved + rejected) for reference.
/// Pull-to-refresh re-fetches GET /novedades.
///
/// When opened from a push notification, [highlightNovedadId] points at the
/// novedad that triggered the notification; after the list loads the screen
/// best-effort scrolls to and visually highlights that card. If the id is
/// absent or not found, the plain list is shown.
class LiderNovedadesScreen extends ConsumerWidget {
  const LiderNovedadesScreen({super.key, this.highlightNovedadId});

  /// Optional novedad id to scroll to / highlight (deep-link from push tap).
  final String? highlightNovedadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight + 52),
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                color: Colors.white.withValues(alpha: 0.7),
                child: Column(
                  children: [
                    AppBar(
                      backgroundColor: Colors.transparent,
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
                        IconButton(
                          icon: const Icon(Icons.notifications_none_outlined),
                          tooltip: 'Notificaciones',
                          onPressed: () => showNotificationsSheet(context),
                        ),
                      ],
                    ),
                    TabBar(
                      labelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 13),
                      unselectedLabelStyle: GoogleFonts.manrope(fontWeight: FontWeight.w400, fontSize: 13),
                      labelColor: const Color(0xFF005f48),
                      unselectedLabelColor: const Color(0xFF3e4944),
                      indicatorColor: const Color(0xFF005f48),
                      indicatorWeight: 3,
                      tabs: const [
                        Tab(text: 'Pendientes'),
                        Tab(text: 'Historial'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        body: _NovedadesTabBody(highlightNovedadId: highlightNovedadId),
      ),
    );
  }
}

class _NovedadesTabBody extends ConsumerWidget {
  const _NovedadesTabBody({this.highlightNovedadId});

  final String? highlightNovedadId;

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
                highlightNovedadId: highlightNovedadId,
              ),
              _NovedadesList(
                novedades: decided,
                emptyMessage: 'Sin historial todavía.',
                emptySubtitle: 'Las novedades decididas aparecerán acá.',
                highlightNovedadId: highlightNovedadId,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Novedad list ────────────────────────────────────────────────────────────

class _NovedadesList extends StatefulWidget {
  const _NovedadesList({
    required this.novedades,
    required this.emptyMessage,
    required this.emptySubtitle,
    this.highlightNovedadId,
  });

  final List<Novedad> novedades;
  final String emptyMessage;
  final String emptySubtitle;
  final String? highlightNovedadId;

  @override
  State<_NovedadesList> createState() => _NovedadesListState();
}

class _NovedadesListState extends State<_NovedadesList> {
  final ScrollController _scrollController = ScrollController();

  /// Estimated card height (incl. separator) used to scroll the highlighted
  /// card roughly into view. Best-effort — exact positioning is not required.
  static const double _estimatedItemExtent = 200;

  @override
  void initState() {
    super.initState();
    _maybeScrollToHighlight();
  }

  void _maybeScrollToHighlight() {
    final id = widget.highlightNovedadId;
    if (id == null) return;
    final index = widget.novedades.indexWhere((n) => n.id == id);
    if (index < 0) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = (index * _estimatedItemExtent).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.novedades.isEmpty) {
      return _EmptyBody(
        message: widget.emptyMessage,
        subtitle: widget.emptySubtitle,
      );
    }
    return ListView.separated(
      controller: _scrollController,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + kToolbarHeight + 52 + 8,
        left: 16,
        right: 16,
        bottom: 16,
      ),
      itemCount: widget.novedades.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final novedad = widget.novedades[index];
        return _LiderNovedadCard(
          novedad: novedad,
          highlighted: novedad.id == widget.highlightNovedadId,
        );
      },
    );
  }
}

// ── Novedad card ────────────────────────────────────────────────────────────

class _LiderNovedadCard extends ConsumerWidget {
  const _LiderNovedadCard({
    required this.novedad,
    this.highlighted = false,
  });

  final Novedad novedad;

  /// When true (deep-linked from a push tap), the card is rendered with an
  /// accent border so the user can spot the relevant novedad.
  final bool highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => NovedadDetailScreen(novedad: novedad),
          ),
        ).then((_) {
          // Refresh list on return (in case novedad was approved/rejected).
          ref.invalidate(novedadesListProvider);
        });
      },
      child: Container(
      decoration: BoxDecoration(
        color: highlighted
            ? const Color(0xFF005f48).withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highlighted
              ? const Color(0xFF005f48).withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.6),
          width: highlighted ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: date + status chip
            Row(
              children: [
                const Icon(Icons.access_time, size: 16, color: Color(0xFF914c00)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _formatDate(novedad.createdAt),
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: const Color(0xFF914c00),
                    ),
                  ),
                ),
                _StatusChip(status: novedad.status),
              ],
            ),
            const SizedBox(height: 12),

            // Horas extra
            Text(
              '${_formatHoras(novedad.horasExtra)} hs extra',
              style: GoogleFonts.manrope(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF005f48),
              ),
            ),

            // Zone
            if (novedad.zoneId != null) ...[
              const SizedBox(height: 4),
              Text(
                'Zona: ${novedad.zoneId}',
                style: GoogleFonts.manrope(fontSize: 13, color: const Color(0xFF3e4944)),
              ),
            ],

            // Motivo
            if (novedad.motivo != null && novedad.motivo!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                novedad.motivo!,
                style: GoogleFonts.manrope(fontSize: 14),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // Decision info
            if (novedad.status != NovedadStatus.pending && novedad.decidedAt != null) ...[
              const SizedBox(height: 8),
              Text(
                '${novedad.status == NovedadStatus.approved ? 'Aprobada' : 'Rechazada'} el ${_formatDate(novedad.decidedAt!)}',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: const Color(0xFF3e4944),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],

          ],
        ),
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
    final (label, color) = switch (status) {
      NovedadStatus.pending => ('Pendiente', const Color(0xFF00597d)),
      NovedadStatus.approved => ('Aprobada', const Color(0xFF005f48)),
      NovedadStatus.rejected => ('Rechazada', const Color(0xFFba1a1a)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
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
