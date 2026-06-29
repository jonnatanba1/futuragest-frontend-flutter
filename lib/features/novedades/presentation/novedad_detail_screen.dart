import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../application/lider_novedad_action_controller.dart';
import '../application/lider_novedad_action_state.dart';
import '../application/novedad_providers.dart';
import '../domain/novedad.dart';

/// Detail screen for a single novedad — shown when a LIDER_OPERATIVO or
/// COORDINADOR taps a solicitud card.
///
/// Shows:
///  - Novedad info: horasExtra, motivo, date, status
///  - Operario history (last 30 days of solicitudes)
///  - "Aprobar" button → biometric prompt → PATCH /novedades/:id/approve
///  - "Rechazar" button → optional reason dialog → biometric → PATCH /novedades/:id/reject
///  - Confirmation screen with green checkmark (approved) or red X (rejected)
class NovedadDetailScreen extends ConsumerStatefulWidget {
  const NovedadDetailScreen({
    super.key,
    required this.novedad,
  });

  final Novedad novedad;

  @override
  ConsumerState<NovedadDetailScreen> createState() =>
      _NovedadDetailScreenState();
}

class _NovedadDetailScreenState extends ConsumerState<NovedadDetailScreen> {
  Novedad get novedad => widget.novedad;

  bool _confirmationVisible = false;

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    final y = local.year.toString();
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$d/$mo/$y $h:$min';
  }

  String _formatHoras(String horasExtra) {
    final d = double.tryParse(horasExtra);
    if (d == null) return horasExtra;
    if (d == d.truncateToDouble()) return d.toInt().toString();
    return d.toStringAsFixed(2);
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _approve() async {
    await ref
        .read(liderNovedadActionControllerProvider(novedad.id).notifier)
        .approve(novedad.id);
  }

  Future<void> _reject() async {
    // Ask for optional rejection reason.
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rechazar novedad'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '¿Estás seguro de que querés rechazar esta solicitud?',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Motivo del rechazo (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
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

    reasonController.dispose();

    if (confirmed == true && mounted) {
      await ref
          .read(liderNovedadActionControllerProvider(novedad.id).notifier)
          .reject(novedad.id);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final actionState =
        ref.watch(liderNovedadActionControllerProvider(novedad.id));

    // Respond to action completion.
    ref.listen<LiderNovedadActionState>(
      liderNovedadActionControllerProvider(novedad.id),
      (previous, next) {
        if (next is LiderNovedadActionDone) {
          setState(() => _confirmationVisible = true);
          ref.invalidate(novedadesListProvider);
          ref
              .read(liderNovedadActionControllerProvider(novedad.id).notifier)
              .reset();
        } else if (next is LiderNovedadActionError && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(next.message),
              backgroundColor: next.isAlreadyDecided
                  ? Colors.orange.shade700
                  : Theme.of(context).colorScheme.error,
            ),
          );
          ref
              .read(liderNovedadActionControllerProvider(novedad.id).notifier)
              .reset();
        }
      },
    );

    // Confirmation screen
    if (_confirmationVisible) {
      return _ConfirmationView(
        isApproved: novedad.status == NovedadStatus.approved ||
            // After action, the novedad in state may be stale; we show the action result
            actionState is LiderNovedadActionDone,
        onBack: () => Navigator.of(context).pop(),
      );
    }

    final isPending = novedad.status == NovedadStatus.pending;
    final isActing = actionState is LiderNovedadActionActing;

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
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF3e4944)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                title: Text(
                  'Detalle de Solicitud',
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
                colors: [
                  Color(0xFFF0FDF4),
                  Color(0xFFE0F2FE),
                  Color(0xFFFFF7ED)
                ],
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Info card ───────────────────────────────────────────
                  _GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Status chip
                        Row(
                          children: [
                            _StatusChip(status: novedad.status),
                            const Spacer(),
                            Text(
                              _formatDate(novedad.createdAt),
                              style: GoogleFonts.manrope(
                                fontSize: 12,
                                color: const Color(0xFF3e4944),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Hours
                        Text(
                          '${_formatHoras(novedad.horasExtra)} hs extra',
                          style: GoogleFonts.manrope(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF005f48),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Supervisor
                        _InfoRow(
                          icon: Icons.person_outline,
                          label: 'Supervisor',
                          value: novedad.supervisorId,
                        ),
                        const SizedBox(height: 8),

                        // Attendance ID
                        _InfoRow(
                          icon: Icons.fingerprint,
                          label: 'Asistencia',
                          value: novedad.attendanceId,
                        ),
                        if (novedad.zoneId != null) ...[
                          const SizedBox(height: 8),
                          _InfoRow(
                            icon: Icons.location_on_outlined,
                            label: 'Zona',
                            value: novedad.zoneId!,
                          ),
                        ],

                        // Motivo
                        if (novedad.motivo != null &&
                            novedad.motivo!.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00597d)
                                  .withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Motivo',
                                  style: GoogleFonts.manrope(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF3e4944),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  novedad.motivo!,
                                  style: GoogleFonts.manrope(
                                    fontSize: 14,
                                    color: const Color(0xFF1a1c1e),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Decision info
                        if (!isPending && novedad.decidedAt != null) ...[
                          const SizedBox(height: 12),
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

                  const SizedBox(height: 24),

                  // ── Operario history ────────────────────────────────────
                  // TODO: fetch operario-specific history (last 30 days)
                  // via GET /novedades?operarioId=X&days=30 once backend supports it.
                  _GlassCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Historial del operario',
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF1a1c1e),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Últimos 30 días — próximamente disponible',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            color: const Color(0xFF6e7a74),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Action buttons (only for pending) ────────────────────
                  if (isPending) ...[
                    if (isActing)
                      const Center(child: CircularProgressIndicator())
                    else ...[
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF005f48)
                                        .withValues(alpha: 0.4),
                                    blurRadius: 16,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: FilledButton.icon(
                                onPressed: _approve,
                                icon: const Icon(Icons.check),
                                label: Text(
                                  'Aprobar',
                                  style: GoogleFonts.manrope(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF005f48),
                                  minimumSize: const Size.fromHeight(56),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _reject,
                              icon: const Icon(Icons.close),
                              label: Text(
                                'Rechazar',
                                style: GoogleFonts.manrope(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFba1a1a),
                                side: const BorderSide(
                                    color: Color(0xFFba1a1a), width: 1.5),
                                minimumSize: const Size.fromHeight(56),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Se requerirá autenticación biométrica para confirmar.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: const Color(0xFF6e7a74),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Confirmation screen ───────────────────────────────────────────────────

class _ConfirmationView extends StatelessWidget {
  const _ConfirmationView({
    required this.isApproved,
    required this.onBack,
  });

  final bool isApproved;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF0FDF4),
                  Color(0xFFE0F2FE),
                  Color(0xFFFFF7ED)
                ],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isApproved ? Icons.check_circle : Icons.cancel,
                      size: 96,
                      color: isApproved
                          ? const Color(0xFF005f48)
                          : const Color(0xFFba1a1a),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      isApproved ? '¡Aprobada!' : 'Rechazada',
                      style: GoogleFonts.manrope(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: isApproved
                            ? const Color(0xFF005f48)
                            : const Color(0xFFba1a1a),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isApproved
                          ? 'La solicitud de horas extra fue aprobada correctamente.'
                          : 'La solicitud de horas extra fue rechazada.',
                      style: GoogleFonts.manrope(
                        fontSize: 15,
                        color: const Color(0xFF3e4944),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF005f48)
                                .withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: FilledButton.icon(
                        onPressed: onBack,
                        icon: const Icon(Icons.arrow_back),
                        label: Text(
                          'Volver',
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF005f48),
                          minimumSize: const Size.fromHeight(56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF6e7a74)),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF3e4944),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.manrope(
              fontSize: 13,
              color: const Color(0xFF1a1c1e),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

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
