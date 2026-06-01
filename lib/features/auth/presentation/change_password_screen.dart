import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/change_password_controller.dart';
import '../application/change_password_state.dart';
import '../domain/user_profile.dart';
import 'home_screen.dart';

/// Shown when the logged-in user has [UserProfile.mustChangePassword] == true.
///
/// After a successful password change, re-fetches /auth/me and navigates
/// to [HomeScreen]. The back button is intentionally hidden so the user
/// cannot bypass this screen.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key, required this.profile});

  /// The profile obtained from /auth/me immediately after login.
  /// Passed to [HomeScreen] after a successful change + re-fetch.
  final UserProfile profile;

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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    await ref.read(changePasswordControllerProvider.notifier).changePassword(
          oldPassword: _oldPasswordController.text,
          newPassword: _newPasswordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(changePasswordControllerProvider);
    final theme = Theme.of(context);

    // On success: navigate to HomeScreen (profile is already up-to-date from
    // login; after password change the backend sets mustChangePassword=false,
    // but we don't need to re-fetch /auth/me since the UI no longer checks it).
    ref.listen<ChangePasswordState>(changePasswordControllerProvider,
        (previous, next) {
      if (next is ChangePasswordSuccess && context.mounted) {
        // Replace both the change-password screen AND the previous route so
        // the user cannot navigate back to this screen.
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) => HomeScreen(profile: widget.profile),
          ),
          (_) => false,
        );
      }
    });

    final isLoading = state is ChangePasswordLoading;

    return PopScope(
      // Prevent back-navigation so the user cannot skip the password change.
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cambiar contraseña'),
          automaticallyImplyLeading: false,
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.lock_reset,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Cambiá tu contraseña',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tu cuenta requiere que establezcas una nueva contraseña '
                      'antes de continuar.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── Contraseña actual ──────────────────────────────────
                    TextFormField(
                      controller: _oldPasswordController,
                      obscureText: _obscureOld,
                      textInputAction: TextInputAction.next,
                      enabled: !isLoading,
                      decoration: InputDecoration(
                        labelText: 'Contraseña actual',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureOld
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () =>
                              setState(() => _obscureOld = !_obscureOld),
                        ),
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
                      decoration: InputDecoration(
                        labelText: 'Nueva contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureNew
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () =>
                              setState(() => _obscureNew = !_obscureNew),
                        ),
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
                      decoration: InputDecoration(
                        labelText: 'Confirmar contraseña',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirm
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(
                              () => _obscureConfirm = !_obscureConfirm),
                        ),
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
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: theme.colorScheme.onErrorContainer,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                state.message,
                                style: TextStyle(
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),

                    // ── Submit button ──────────────────────────────────────
                    FilledButton(
                      onPressed: isLoading ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
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
                          : const Text('Cambiar contraseña'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
