import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

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
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: Colors.white.withValues(alpha: 0.8),
              child: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                centerTitle: true,
                title: Text(
                  'Mis novedades',
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF005f48),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Gradient background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFF0FDF4), Color(0xFFE0F2FE), Color(0xFFFFF7ED)],
              ),
            ),
          ),
          RefreshIndicator(
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
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + kToolbarHeight + 16,
                    left: 16,
                    right: 16,
                    bottom: 24,
                  ),
                  itemCount: novedades.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) =>
                      _NovedadCard(novedad: novedades[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card ───────────────────────────────────────────────────────────────────

class _NovedadCard extends StatelessWidget {
  const _NovedadCard({required this.novedad});

  final Novedad novedad;

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    const months = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    return '${local.day} ${months[local.month - 1]}';
  }

  String _formatHoras(String horasExtra) {
    final d = double.tryParse(horasExtra);
    if (d == null) return horasExtra;
    if (d == d.truncateToDouble()) return d.toInt().toString();
    return d.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = _formatDate(novedad.createdAt);
    final horasLabel = _formatHoras(novedad.horasExtra);

    final (statusColor, statusBg) = switch (novedad.status) {
      NovedadStatus.pending => (
          const Color(0xFF00597d),
          const Color(0xFF00597d),
        ),
      NovedadStatus.approved => (
          const Color(0xFF005f48),
          const Color(0xFF005f48),
        ),
      NovedadStatus.rejected => (
          const Color(0xFFba1a1a),
          const Color(0xFFba1a1a),
        ),
    };
    final statusLabel = switch (novedad.status) {
      NovedadStatus.pending => 'Pendiente',
      NovedadStatus.approved => 'Aprobada',
      NovedadStatus.rejected => 'Rechazada',
    };

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFbdc9c2).withValues(alpha: 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Semantic icon circle ─────────────────────────────────────
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF005f48).withValues(alpha: 0.1),
              ),
              child: const Icon(
                Icons.more_time,
                color: Color(0xFF005f48),
                size: 22,
              ),
            ),
            const SizedBox(width: 16),

            // ── Content ──────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row + date badge
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          'Horas Extra Solicitadas',
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1a1c1e),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFeeeef0),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          dateLabel,
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF3e4944),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Motivo / subtitle
                  if (novedad.motivo != null && novedad.motivo!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      novedad.motivo!,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        color: const Color(0xFF3e4944),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Tags row
                  Row(
                    children: [
                      // Horas tag
                      _Tag(
                        icon: Icons.add_circle_outline,
                        label: '+$horasLabel horas',
                        color: const Color(0xFF005f48),
                      ),
                      const SizedBox(width: 8),
                      // Status tag
                      _Tag(
                        label: statusLabel,
                        color: statusColor,
                        bg: statusBg,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Chevron ───────────────────────────────────────────────────
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right,
              color: Color(0xFFbdc9c2),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color, this.icon, this.bg});
  final String label;
  final Color color;
  final IconData? icon;
  final Color? bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (bg ?? color).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
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

// ── Empty / error bodies ───────────────────────────────────────────────────

class _EmptyBody extends StatelessWidget {
  const _EmptyBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inbox_outlined,
              size: 72,
              color: Color(0x8000597d),
            ),
            const SizedBox(height: 16),
            Text(
              'Sin novedades todavía',
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF3e4944),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Las horas extra que registrés aparecerán acá.',
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: const Color(0xFF6e7a74),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 72,
              color: Color(0xFFba1a1a),
            ),
            const SizedBox(height: 16),
            Text(
              'Error al cargar las novedades',
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFba1a1a),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: const Color(0xFF3e4944),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF005f48),
                side: const BorderSide(color: Color(0xFF005f48)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
