import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../features/novedades/presentation/novedad_form_screen.dart';
import '../application/fichaje_controller.dart';
import '../application/fichaje_state.dart';
import '../domain/operario.dart';

/// Full fichaje flow for a single operario — supports both INGRESO and SALIDA.
///
/// INGRESO (mode: FichajeMode.ingreso):
///   1. Biometric + GPS → enqueue check-in (via controller.start())
///   2. Camera photo capture → saveCheckInPhoto
///   3. Done: "Ingreso registrado"
///
/// SALIDA (mode: FichajeMode.salida):
///   1. Biometric + GPS → (controller.start())
///   2. Camera photo capture → saveSalidaPhoto
///   3. Done: "Salida registrada" (+ overtime button when serverAttendanceId known)
class FichajeScreen extends ConsumerStatefulWidget {
  const FichajeScreen({super.key, required this.params});

  final FichajeParams params;

  Operario get operario => params.operario;

  @override
  ConsumerState<FichajeScreen> createState() => _FichajeScreenState();
}

class _FichajeScreenState extends ConsumerState<FichajeScreen> {
  // Captured photo — null means no photo taken yet.
  XFile? _capturedPhoto;

  @override
  void initState() {
    super.initState();
    // Auto-start the flow on first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(fichajeControllerProvider(widget.params).notifier)
          .start();
    });
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _onTakePhoto() async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 70,
      maxWidth: 1280,
    );
    // If the user cancelled the camera, do nothing — stay on the capture view.
    if (photo == null) return;
    if (!mounted) return;
    setState(() {
      _capturedPhoto = photo;
    });
  }

  Future<void> _onConfirmPhoto() async {
    final photo = _capturedPhoto;
    if (photo == null) return;

    final bytes = await File(photo.path).readAsBytes();
    if (!mounted) return;

    await ref
        .read(fichajeControllerProvider(widget.params).notifier)
        .uploadPhoto(bytes.toList());
  }

  void _onRetakePhoto() {
    setState(() {
      _capturedPhoto = null;
    });
  }

  Future<void> _onRetry() async {
    setState(() {
      _capturedPhoto = null;
    });
    await ref
        .read(fichajeControllerProvider(widget.params).notifier)
        .retry();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fichajeControllerProvider(widget.params));
    final operario = widget.operario;

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
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Operario profile card ──────────────────────────────────
                  _OperarioCard(operario: operario),
                  const SizedBox(height: 16),
                  // ── Flow body ──────────────────────────────────────────────
                  _buildBody(context, state),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, FichajeState state) {
    return switch (state) {
      FichajeIdle() => const _BusyView(message: 'Iniciando…'),
      FichajeCheckingIn() => _BusyView(
          message: widget.params.mode == FichajeMode.ingreso
              ? 'Verificando identidad y registrando entrada…'
              : 'Verificando identidad y obteniendo ubicación…',
        ),
      FichajeAwaitingPhoto(:final mode, :final isOffline) => _PhotoView(
          capturedPhoto: _capturedPhoto,
          onTakePhoto: _onTakePhoto,
          onRetakePhoto: _onRetakePhoto,
          onConfirmPhoto: _onConfirmPhoto,
          mode: mode,
          isOffline: isOffline,
        ),
      FichajeUploadingPhoto() => const _BusyView(
          message: 'Guardando foto…',
        ),
      FichajeDone(:final mode, :final serverAttendanceId) => _DoneView(
          mode: mode,
          serverAttendanceId: serverAttendanceId,
        ),
      FichajeError(:final message, :final previous) => _ErrorView(
          message: message,
          previous: previous,
          onRetry: _onRetry,
        ),
    };
  }
}

// ── Operario profile card ──────────────────────────────────────────────────

class _OperarioCard extends StatelessWidget {
  const _OperarioCard({required this.operario});

  final Operario operario;

  String get _initials {
    final parts = operario.fullName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Avatar with ring
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF005f48).withValues(alpha: 0.3),
                width: 2.5,
              ),
            ),
            child: CircleAvatar(
              radius: 30,
              backgroundColor: const Color(0xFF005f48).withValues(alpha: 0.1),
              child: Text(
                _initials,
                style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF005f48),
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
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1a1c1b),
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00597d).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'ID: ${operario.documento}',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF00597d),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step views ─────────────────────────────────────────────────────────────

class _PhotoView extends StatelessWidget {
  const _PhotoView({
    required this.capturedPhoto,
    required this.onTakePhoto,
    required this.onRetakePhoto,
    required this.onConfirmPhoto,
    required this.mode,
    this.isOffline = false,
  });

  final XFile? capturedPhoto;
  final VoidCallback onTakePhoto;
  final VoidCallback onRetakePhoto;
  final VoidCallback onConfirmPhoto;
  final FichajeMode mode;
  final bool isOffline;

  @override
  Widget build(BuildContext context) {
    final isIngreso = mode == FichajeMode.ingreso;
    final hasPhoto = capturedPhoto != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Status card
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Color(0xFF005f48)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isIngreso ? 'Entrada registrada' : 'Ubicación capturada',
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF005f48),
                  ),
                ),
              ),
              if (isOffline) const _OfflineBadge(),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          isIngreso ? 'Foto de ingreso' : 'Foto de salida',
          style: GoogleFonts.manrope(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1a1c1b),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tomá una foto del operario para confirmar su identidad.',
          style: GoogleFonts.manrope(
            fontSize: 13,
            color: const Color(0xFF6e7a74),
          ),
        ),
        const SizedBox(height: 16),
        if (!hasPhoto) ...[
          // No photo yet — show the "Tomar foto" button.
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF005f48).withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: FilledButton.icon(
              onPressed: onTakePhoto,
              icon: const Icon(Icons.camera_alt),
              label: Text(
                'Tomar foto',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF005f48),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                minimumSize: const Size(double.infinity, 52),
              ),
            ),
          ),
        ] else ...[
          // Photo captured — show preview and action buttons.
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            height: 280,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(
                File(capturedPhoto!.path),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFF005f48).withValues(alpha: 0.3),
                    ),
                  ),
                  child: OutlinedButton.icon(
                    onPressed: onRetakePhoto,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Repetir'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF005f48),
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF005f48).withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: FilledButton.icon(
                    onPressed: onConfirmPhoto,
                    icon: const Icon(Icons.check),
                    label: const Text('Guardar foto'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF005f48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _BusyView extends StatelessWidget {
  const _BusyView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 32),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const CircularProgressIndicator(color: Color(0xFF005f48)),
          const SizedBox(height: 24),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 15,
              color: const Color(0xFF3e4944),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView({
    required this.mode,
    this.serverAttendanceId,
  });

  final FichajeMode mode;
  final String? serverAttendanceId;

  @override
  Widget build(BuildContext context) {
    final isIngreso = mode == FichajeMode.ingreso;
    // Overtime can be pre-authorized after the ingreso too (operario is now working,
    // before any salida) — it only needs the synced server attendance id.
    final canOvertime =
        serverAttendanceId != null && serverAttendanceId!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
          child: Column(
            children: [
              const Icon(
                Icons.check_circle,
                size: 80,
                color: Color(0xFF005f48),
              ),
              const SizedBox(height: 24),
              Text(
                isIngreso ? 'Ingreso registrado' : 'Salida registrada',
                style: GoogleFonts.manrope(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1a1c1b),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isIngreso
                    ? 'Entrada y foto de ingreso guardadas correctamente.'
                    : 'Foto de salida guardada. La asistencia quedará completa al sincronizar.',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  color: const Color(0xFF6e7a74),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Overtime button — shown after ingreso or salida, whenever the server id
        // is known, so the supervisor can pre-authorize extra hours before checkout.
        if (canOvertime) ...[
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF005f48).withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: FilledButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        NovedadFormScreen(attendanceId: serverAttendanceId!),
                  ),
                );
              },
              icon: const Icon(Icons.more_time),
              label: Text(
                'Registrar horas extra',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF005f48),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                minimumSize: const Size(double.infinity, 52),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF005f48).withValues(alpha: 0.3),
            ),
          ),
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
            label: Text(
              'Volver a la lista',
              style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF005f48),
              side: BorderSide.none,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              minimumSize: const Size(double.infinity, 52),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.previous,
    required this.onRetry,
  });

  final String message;
  final FichajeState previous;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(
                Icons.error_outline,
                size: 72,
                color: Color(0xFFba1a1a),
              ),
              const SizedBox(height: 24),
              Text(
                'Ocurrió un error',
                style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFba1a1a),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFba1a1a).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  message,
                  style: GoogleFonts.manrope(
                    color: const Color(0xFFba1a1a),
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF005f48).withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: Text(
              'Reintentar',
              style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF005f48),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              minimumSize: const Size(double.infinity, 52),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.1),
            ),
          ),
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF3e4944),
              side: BorderSide.none,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              minimumSize: const Size(double.infinity, 52),
            ),
            child: Text(
              'Cancelar',
              style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}

/// Small chip shown when the underlying ingreso hasn't synced yet.
class _OfflineBadge extends StatelessWidget {
  const _OfflineBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFff8a00).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 12, color: Color(0xFF914c00)),
          const SizedBox(width: 4),
          Text(
            'Pendiente',
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF914c00),
            ),
          ),
        ],
      ),
    );
  }
}
