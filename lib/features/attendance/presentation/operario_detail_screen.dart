import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../novedades/application/novedad_providers.dart';
import '../../novedades/presentation/novedad_form_screen.dart';
import '../application/attendance_providers.dart';
import '../application/fichaje_controller.dart';
import '../application/fichaje_state.dart';
import '../domain/operario.dart';
import 'fichaje_screen.dart';

class OperarioDetailScreen extends ConsumerStatefulWidget {
  const OperarioDetailScreen({super.key, required this.operario});

  final Operario operario;

  @override
  ConsumerState<OperarioDetailScreen> createState() =>
      _OperarioDetailScreenState();
}

class _OperarioDetailScreenState extends ConsumerState<OperarioDetailScreen> {
  Operario get operario => widget.operario;

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _startIngresoFlow() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FichajeScreen(
          params: FichajeParams(
            operario: operario,
            mode: FichajeMode.ingreso,
          ),
        ),
      ),
    );
    ref.invalidate(recordedTodayProvider);
  }

  Future<void> _openOvertimeForm(String attendanceId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NovedadFormScreen(attendanceId: attendanceId),
      ),
    );
    ref.invalidate(novedadesListProvider);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final recordedToday =
        ref.watch(recordedTodayProvider).valueOrNull ?? {};
    final today = recordedToday[operario.id];

    final completed = today?.completed ?? false;
    final hasOpenRecord = today != null && !completed;
    final attendanceId = today?.attendanceId;
    final canFichar = operario.active && today == null;

    final statusLabel = completed
        ? 'PRESENTE'
        : hasOpenRecord
            ? 'EN JORNADA'
            : operario.active
                ? 'PENDIENTE INGRESO'
                : 'INACTIVO';

    final statusColor = completed
        ? const Color(0xFF005f48)
        : hasOpenRecord
            ? const Color(0xFFff8a00)
            : operario.active
                ? const Color(0xFF914c00)
                : const Color(0xFF6e7a74);

    final avatarLetter =
        operario.fullName.isNotEmpty ? operario.fullName[0].toUpperCase() : '?';

    final now = DateTime.now();
    const months = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    final dateLabel =
        '${now.day} ${months[now.month - 1]} ${now.year}';

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
                  icon: const Icon(Icons.arrow_back,
                      color: Color(0xFF3e4944)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                title: Text(
                  'Detalle',
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
          // Full-screen gradient background — prevents the black-box below content
          const SizedBox.expand(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFF0FDF4),
                    Color(0xFFE0F2FE),
                    Color(0xFFFFF7ED),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(
                  left: 20, right: 20, top: 16, bottom: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),

                // ── Profile card ─────────────────────────────────────────────
                _GlassCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: statusColor, width: 2.5),
                        ),
                        child: CircleAvatar(
                          radius: 32,
                          backgroundColor:
                              statusColor.withValues(alpha: 0.1),
                          child: Text(
                            avatarLetter,
                            style: GoogleFonts.manrope(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              operario.fullName.toUpperCase(),
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1a1c1e),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF005f48)
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Doc: ${operario.documento}',
                                style: GoogleFonts.manrope(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF005f48),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Estado Actual card ────────────────────────────────────────
                _GlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Estado Actual',
                            style: GoogleFonts.manrope(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF1a1c1e),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  completed
                                      ? Icons.check_circle_outline
                                      : hasOpenRecord
                                          ? Icons.timer_outlined
                                          : Icons.schedule_outlined,
                                  size: 14,
                                  color: statusColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  statusLabel,
                                  style: GoogleFonts.manrope(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: statusColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _InfoField(
                              label: 'FECHA',
                              value: dateLabel,
                            ),
                          ),
                          Expanded(
                            child: _InfoField(
                              label: 'DOCUMENTO',
                              value: operario.documento,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Action buttons ────────────────────────────────────────────
                if (canFichar)
                  _PrimaryButton(
                    icon: Icons.login,
                    label: 'Registrar Ingreso',
                    onPressed: _startIngresoFlow,
                  ),

                if (canFichar) const SizedBox(height: 12),

                if (attendanceId != null)
                  _SecondaryButton(
                    icon: Icons.more_time,
                    label: 'Solicitar Hora Extra',
                    onPressed: () => _openOvertimeForm(attendanceId),
                  ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        ],
      ),
    );
  }
}

// ── Shared helpers ──────────────────────────────────────────────────────────

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

class _InfoField extends StatelessWidget {
  const _InfoField({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: const Color(0xFF6e7a74),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.manrope(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: const Color(0xFF1a1c1e),
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF005f48),
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
          shadowColor: const Color(0xFF005f48).withValues(alpha: 0.3),
        ).copyWith(
          elevation: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.pressed) ? 0 : 2,
          ),
        ),
        icon: Icon(icon),
        label: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        onPressed: onPressed,
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF914c00),
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        side: const BorderSide(color: Color(0xFFff8a00), width: 1.5),
        backgroundColor: const Color(0xFFff8a00).withValues(alpha: 0.06),
      ),
      icon: Icon(icon, color: const Color(0xFFff8a00)),
      label: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF914c00),
        ),
      ),
      onPressed: onPressed,
    );
  }
}
