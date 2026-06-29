import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../application/novedad_providers.dart';
import '../domain/novedad.dart';

/// Screen that lists LLEGADA_TARDE novedades — shown to LIDER_OPERATIVO
/// and COORDINADOR roles.
///
/// Each card shows: operario name, date, minutosTarde, and PENDING status.
/// Tapping a card opens the detail where the leader can accept as justified
/// or reject (both require biometric confirmation).
class LlegadasTardeScreen extends ConsumerWidget {
  const LlegadasTardeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final novedadesAsync = ref.watch(novedadesListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
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
                message: err.toString(),
                onRetry: () => ref.invalidate(novedadesListProvider),
              ),
              data: (novedades) {
                // Filter only LLEGADA_TARDE and PENDING novedades.
                final lateArrivals = novedades
                    .where((n) =>
                        n.tipoNovedad == 'LLEGADA_TARDE' &&
                        n.status == NovedadStatus.pending)
                    .toList();

                if (lateArrivals.isEmpty) {
                  return _EmptyBody();
                }

                return ListView.separated(
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 16,
                    left: 16,
                    right: 16,
                    bottom: 24,
                  ),
                  itemCount: lateArrivals.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) =>
                      _LateArrivalCard(novedad: lateArrivals[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card ─────────────────────────────────────────────────────────────────────

class _LateArrivalCard extends StatelessWidget {
  const _LateArrivalCard({required this.novedad});

  final Novedad novedad;

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    return '$d/$mo ${local.hour}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final minutosTarde = novedad.minutosTarde ?? 0;

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
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber, size: 20, color: Color(0xFFff8a00)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Llegada Tarde',
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1a1c1e),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFeeeef0),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _formatDate(novedad.createdAt),
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF3e4944),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$minutosTarde min tarde',
              style: GoogleFonts.manrope(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFff8a00),
              ),
            ),
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
            Row(
              children: [
                _StatusBadge(
                  label: 'Pendiente',
                  color: const Color(0xFF00597d),
                ),
                const Spacer(),
                const Icon(Icons.chevron_right, color: Color(0xFFbdc9c2), size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status badge ─────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
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

// ── Empty / error views ──────────────────────────────────────────────────────

class _EmptyBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_outline,
              size: 72,
              color: Color(0x8000597d),
            ),
            const SizedBox(height: 16),
            Text(
              'Sin llegadas tarde',
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF3e4944),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'No hay llegadas tarde pendientes de revisión.',
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
              'Error al cargar llegadas tarde',
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
