import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signature/signature.dart';

import '../../../features/novedades/presentation/novedad_form_screen.dart';
import '../application/fichaje_controller.dart';
import '../application/fichaje_state.dart';
import '../domain/attendance_record.dart';
import '../domain/operario.dart';

/// Full fichaje flow for a single operario.
///
/// Screen steps (enforced by state machine in [FichajeController]):
///   1. Biometric confirmation + "Marcar entrada" → GPS + queue write
///   2. Signature pad      → capture PNG + queue write (upload on sync)
///   3. Biometric confirmation + "Marcar salida" → GPS + queue write
///   4. Done confirmation  (sync badge if still pending)
class FichajeScreen extends ConsumerStatefulWidget {
  const FichajeScreen({super.key, required this.operario});

  final Operario operario;

  @override
  ConsumerState<FichajeScreen> createState() => _FichajeScreenState();
}

class _FichajeScreenState extends ConsumerState<FichajeScreen> {
  late final SignatureController _signatureController;

  @override
  void initState() {
    super.initState();
    _signatureController = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );
  }

  @override
  void dispose() {
    _signatureController.dispose();
    super.dispose();
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _onCheckIn() async {
    await ref
        .read(fichajeControllerProvider(widget.operario).notifier)
        .checkIn();
  }

  Future<void> _onSaveSignature() async {
    if (_signatureController.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dibujá la firma del operario antes de guardar.'),
        ),
      );
      return;
    }

    final pngBytes = await _signatureController.toPngBytes();
    if (!mounted) return;

    if (pngBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo exportar la firma.')),
      );
      return;
    }

    await ref
        .read(fichajeControllerProvider(widget.operario).notifier)
        .uploadSignature(pngBytes.toList());
  }

  Future<void> _onCheckOut() async {
    await ref
        .read(fichajeControllerProvider(widget.operario).notifier)
        .checkOut();
  }

  void _onRetry() {
    ref
        .read(fichajeControllerProvider(widget.operario).notifier)
        .retry();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fichajeControllerProvider(widget.operario));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.operario.fullName),
            Text(
              'Doc: ${widget.operario.documento}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _buildBody(context, state),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, FichajeState state) {
    return switch (state) {
      FichajeIdle() => _CheckInView(onCheckIn: _onCheckIn),
      FichajeCheckingIn() => const _BusyView(
          message: 'Verificando identidad y registrando entrada…',
        ),
      FichajeAwaitingSignature(:final record, :final isOffline) =>
        _SignatureView(
          controller: _signatureController,
          onSave: _onSaveSignature,
          recordId: record.id,
          isOffline: isOffline,
        ),
      FichajeUploadingSignature() => const _BusyView(
          message: 'Guardando firma…',
        ),
      FichajeSignatureDone(:final record) => _CheckOutView(
          record: record,
          onCheckOut: _onCheckOut,
        ),
      FichajeCheckingOut() => const _BusyView(
          message: 'Verificando identidad y registrando salida…',
        ),
      FichajeDone(:final record) => _DoneView(record: record),
      FichajeError(:final message, :final previous) => _ErrorView(
          message: message,
          previous: previous,
          onRetry: _onRetry,
        ),
    };
  }
}

// ── Step views ─────────────────────────────────────────────────────────────

class _CheckInView extends StatelessWidget {
  const _CheckInView({required this.onCheckIn});

  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        Icon(
          Icons.login,
          size: 72,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          'Registrar entrada',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Se solicitará tu huella o Face ID y se capturará tu ubicación GPS.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.secondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),
        FilledButton.icon(
          onPressed: onCheckIn,
          icon: const Icon(Icons.login),
          label: const Text('Marcar entrada'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }
}

class _SignatureView extends StatelessWidget {
  const _SignatureView({
    required this.controller,
    required this.onSave,
    required this.recordId,
    this.isOffline = false,
  });

  final SignatureController controller;
  final VoidCallback onSave;
  final String recordId;
  final bool isOffline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(Icons.check_circle, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Entrada registrada',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            if (isOffline) const _OfflineBadge(),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Firma del operario',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Pedile al operario que firme en el recuadro de abajo.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.secondary,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.colorScheme.outline,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          height: 240,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Signature(
              controller: controller,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: controller.clear,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Limpiar firma'),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onSave,
          icon: const Icon(Icons.upload),
          label: const Text('Guardar firma'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }
}

class _CheckOutView extends StatelessWidget {
  const _CheckOutView({
    required this.record,
    required this.onCheckOut,
  });

  final AttendanceRecord record;
  final VoidCallback onCheckOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        Row(
          children: [
            Icon(Icons.check_circle, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Entrada y firma registradas',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Icon(Icons.logout, size: 72, color: theme.colorScheme.secondary),
        const SizedBox(height: 24),
        Text(
          'Registrar salida',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Se solicitará tu huella o Face ID y se capturará tu ubicación GPS.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.secondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),
        FilledButton.icon(
          onPressed: onCheckOut,
          icon: const Icon(Icons.logout),
          label: const Text('Marcar salida'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }
}

class _BusyView extends StatelessWidget {
  const _BusyView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView({required this.record});

  final AttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // The novedad form requires a real server ID. When the check-out was
    // captured offline (id == ''), the button is disabled with a note.
    final hasServerId = record.id.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 48),
        Icon(
          Icons.check_circle,
          size: 80,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          'Asistencia completa',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Entrada, firma y salida registradas correctamente.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.secondary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        // ── Novedad shortcut ─────────────────────────────────────────────
        FilledButton.icon(
          onPressed: hasServerId
              ? () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          NovedadFormScreen(attendanceId: record.id),
                    ),
                  );
                }
              : null,
          icon: const Icon(Icons.more_time),
          label: const Text('Registrar horas extra'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        if (!hasServerId) ...[
          const SizedBox(height: 6),
          Text(
            'Disponible una vez que la asistencia se sincronice.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.secondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Volver a la lista'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
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
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 48),
        Icon(
          Icons.error_outline,
          size: 72,
          color: theme.colorScheme.error,
        ),
        const SizedBox(height: 24),
        Text(
          'Ocurrió un error',
          style: theme.textTheme.headlineSmall?.copyWith(
            color: theme.colorScheme.error,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Card(
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              message,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

/// Small chip shown when the check-in is queued but not yet synced.
class _OfflineBadge extends StatelessWidget {
  const _OfflineBadge();

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const Icon(Icons.cloud_off, size: 14),
      label: const Text(
        'Pendiente',
        style: TextStyle(fontSize: 11),
      ),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
