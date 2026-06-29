import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../application/auth_providers.dart';
import '../application/change_password_controller.dart';
import '../application/change_password_state.dart';
import '../domain/user_profile.dart';

/// Shown in two contexts:
/// - Mandatory: when [UserProfile.mustChangePassword] == true (back blocked,
///   navigates to /home after success).
/// - Voluntary: launched from ProfileScreen ([isVoluntary] == true; back
///   allowed, pops on success).
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({
    super.key,
    required this.profile,
    this.isVoluntary = false,
  });

  final UserProfile profile;

  /// When true the screen is user-initiated (from ProfileScreen).
  /// Back navigation is allowed and success pops the screen.
  final bool isVoluntary;

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _navigateAfterMandatoryChange() async {
    UserProfile fresh = widget.profile;
    try {
      fresh = await ref.read(authRepositoryProvider).getMe();
    } catch (_) {
      // Fallback: navigate with stale profile — acceptable.
    }
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/home',
      (_) => false,
      arguments: fresh,
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    await ref.read(changePasswordControllerProvider.notifier).changePassword(
          email: widget.profile.email,
          oldPassword: _oldPasswordController.text,
          newPassword: _newPasswordController.text,
        );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData prefixIcon,
    required bool obscure,
    required VoidCallback onToggleObscure,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.manrope(color: const Color(0xFF3e4944)),
      prefixIcon: Icon(prefixIcon, color: const Color(0xFF005f48), size: 20),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF005f48), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFba1a1a)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFba1a1a), width: 1.5),
      ),
      suffixIcon: IconButton(
        icon: Icon(
          obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          color: const Color(0xFF6e7a74),
        ),
        onPressed: onToggleObscure,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(changePasswordControllerProvider);

    // On success the controller has already re-authenticated with the new
    // password, so storage holds a fresh token with mustChangePassword:false.
    // The DB flag is now cleared, so the cached profile is effectively stale on
    // that single field, but HomeScreen does not re-check it — navigate on.
    ref.listen<ChangePasswordState>(changePasswordControllerProvider,
        (previous, next) {
      if (next is ChangePasswordSuccess && context.mounted) {
        if (widget.isVoluntary) {
          Navigator.of(context).pop();
        } else {
          _navigateAfterMandatoryChange();
        }
      }
    });

    final isLoading = state is ChangePasswordLoading;

    return PopScope(
      canPop: widget.isVoluntary,
      child: Scaffold(
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
            // Green blob top-right
            Positioned(
              top: -80,
              right: -60,
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF005f48).withValues(alpha: 0.15),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Orange blob bottom-left
            Positioned(
              bottom: -60,
              left: -40,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFff8a00).withValues(alpha: 0.12),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Back button (voluntary only)
            if (widget.isVoluntary)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 8,
                child: SafeArea(
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new),
                    color: const Color(0xFF005f48),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            // Main content
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 32,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Icon
                              const Icon(
                                Icons.lock_reset,
                                size: 64,
                                color: Color(0xFF005f48),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Cambiá tu contraseña',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.manrope(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF1a1c1b),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                widget.isVoluntary
                                    ? 'Podés actualizar tu contraseña cuando quieras desde esta pantalla.'
                                    : 'Tu cuenta requiere que establezcas una nueva contraseña '
                                        'antes de continuar.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.manrope(
                                  fontSize: 14,
                                  color: const Color(0xFF6e7a74),
                                ),
                              ),
                              const SizedBox(height: 32),

                              // ── Contraseña actual ──────────────────────────────────
                              TextFormField(
                                controller: _oldPasswordController,
                                obscureText: _obscureOld,
                                textInputAction: TextInputAction.next,
                                enabled: !isLoading,
                                style: GoogleFonts.manrope(fontSize: 15),
                                decoration: _inputDecoration(
                                  label: 'Contraseña actual',
                                  prefixIcon: Icons.lock_outline,
                                  obscure: _obscureOld,
                                  onToggleObscure: () =>
                                      setState(() => _obscureOld = !_obscureOld),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return 'Ingresá tu contraseña actual';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),

                              // ── Nueva contraseña ───────────────────────────────────
                              TextFormField(
                                controller: _newPasswordController,
                                obscureText: _obscureNew,
                                textInputAction: TextInputAction.next,
                                enabled: !isLoading,
                                style: GoogleFonts.manrope(fontSize: 15),
                                decoration: _inputDecoration(
                                  label: 'Nueva contraseña',
                                  prefixIcon: Icons.lock_outline,
                                  obscure: _obscureNew,
                                  onToggleObscure: () =>
                                      setState(() => _obscureNew = !_obscureNew),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return 'Ingresá la nueva contraseña';
                                  }
                                  if (v.length < 8) {
                                    return 'La contraseña debe tener al menos 8 caracteres';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),

                              // ── Confirmar nueva contraseña ─────────────────────────
                              TextFormField(
                                controller: _confirmPasswordController,
                                obscureText: _obscureConfirm,
                                textInputAction: TextInputAction.done,
                                enabled: !isLoading,
                                onFieldSubmitted: (_) => _submit(),
                                style: GoogleFonts.manrope(fontSize: 15),
                                decoration: _inputDecoration(
                                  label: 'Confirmar contraseña',
                                  prefixIcon: Icons.lock_outline,
                                  obscure: _obscureConfirm,
                                  onToggleObscure: () => setState(
                                      () => _obscureConfirm = !_obscureConfirm),
                                ),
                                validator: (v) {
                                  if (v == null || v.isEmpty) {
                                    return 'Confirmá la nueva contraseña';
                                  }
                                  if (v != _newPasswordController.text) {
                                    return 'Las contraseñas no coinciden';
                                  }
                                  return null;
                                },
                              ),

                              // ── Error banner ───────────────────────────────────────
                              if (state is ChangePasswordError) ...[
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFba1a1a).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFba1a1a).withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.error_outline,
                                        color: Color(0xFFba1a1a),
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          state.message,
                                          style: GoogleFonts.manrope(
                                            color: const Color(0xFFba1a1a),
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 24),

                              // ── Submit button ──────────────────────────────────────
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
                                child: FilledButton(
                                  onPressed: isLoading ? null : _submit,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF005f48),
                                    minimumSize: const Size.fromHeight(52),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: isLoading
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(
                                          'Cambiar contraseña',
                                          style: GoogleFonts.manrope(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
