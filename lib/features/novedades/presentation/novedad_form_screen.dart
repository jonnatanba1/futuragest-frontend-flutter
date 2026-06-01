import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/create_novedad_state.dart';
import '../application/novedad_providers.dart';

/// Form screen for creating a new overtime novedad on a completed attendance.
///
/// Entry points:
///  1. FichajeScreen "done" state → "Registrar horas extra" button
///     (primary path — the supervisor just completed the fichaje).
///  2. NovedadesListScreen (future: from a list of completed attendances).
///
/// The [attendanceId] is the server ID of the completed [AttendanceRecord].
class NovedadFormScreen extends ConsumerStatefulWidget {
  const NovedadFormScreen({
    super.key,
    required this.attendanceId,
  });

  final String attendanceId;

  @override
  ConsumerState<NovedadFormScreen> createState() => _NovedadFormScreenState();
}

class _NovedadFormScreenState extends ConsumerState<NovedadFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _horasController = TextEditingController();
  final _motivoController = TextEditingController();

  @override
  void dispose() {
    _horasController.dispose();
    _motivoController.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    // Basic form validation (required field feedback via TextFormField).
    if (!(_formKey.currentState?.validate() ?? false)) return;

    await ref
        .read(createNovedadControllerProvider(widget.attendanceId).notifier)
        .submit(
          attendanceId: widget.attendanceId,
          horasExtraInput: _horasController.text,
          motivo: _motivoController.text,
        );
  }

  void _onReset() {
    ref
        .read(createNovedadControllerProvider(widget.attendanceId).notifier)
        .reset();
  }

  @override
  Widget build(BuildContext context) {
    final state =
        ref.watch(createNovedadControllerProvider(widget.attendanceId));

    // Navigate back after a successful create so the caller's list refreshes.
    ref.listen<CreateNovedadState>(
      createNovedadControllerProvider(widget.attendanceId),
      (_, next) {
        if (next is CreateNovedadSuccess && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Novedad registrada correctamente.'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(next.novedad);
        }
      },
    );

    final isSubmitting = state is CreateNovedadSubmitting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar horas extra'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Error banner ─────────────────────────────────────────────
                if (state is CreateNovedadError) ...[
                  _ErrorBanner(
                    message: state.message,
                    onDismiss: _onReset,
                  ),
                  const SizedBox(height: 20),
                ],

                // ── Horas extra field ────────────────────────────────────────
                TextFormField(
                  controller: _horasController,
                  enabled: !isSubmitting,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    // Allow digits and one decimal separator.
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Horas extra',
                    hintText: 'Ej: 2.5',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.access_time),
                    helperText: 'Valor entre 0.01 y 24 horas.',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingresá las horas extra.';
                    }
                    final parsed = double.tryParse(value.trim());
                    if (parsed == null) return 'Ingresá un número válido.';
                    if (parsed <= 0) return 'Debe ser mayor a 0.';
                    if (parsed > 24) return 'No puede superar 24 horas.';
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // ── Motivo field ─────────────────────────────────────────────
                TextFormField(
                  controller: _motivoController,
                  enabled: !isSubmitting,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    labelText: 'Motivo (opcional)',
                    hintText: 'Describí el motivo de las horas extra…',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(bottom: 48),
                      child: Icon(Icons.notes),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // ── Submit button ────────────────────────────────────────────
                FilledButton.icon(
                  onPressed: isSubmitting ? null : _onSubmit,
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(isSubmitting ? 'Enviando…' : 'Registrar novedad'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: theme.colorScheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              color: theme.colorScheme.error,
              onPressed: onDismiss,
              tooltip: 'Cerrar',
            ),
          ],
        ),
      ),
    );
  }
}
