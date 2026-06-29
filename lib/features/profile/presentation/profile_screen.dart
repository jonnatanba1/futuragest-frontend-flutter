import 'dart:developer' as dev;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/push/push_messaging_service.dart';
import '../../attendance/application/attendance_providers.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/user_profile.dart';
import '../../auth/presentation/change_password_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _loggingOut = false;

  String _roleLabel(UserRole role) {
    switch (role) {
      case UserRole.systemAdmin:
        return 'Administrador del sistema';
      case UserRole.gerencia:
        return 'Gerencia';
      case UserRole.talentoHumano:
        return 'Talento Humano';
      case UserRole.liderOperativo:
        return 'Líder Operativo';
      case UserRole.coordinador:
        return 'Coordinador';
      case UserRole.supervisor:
        return 'Supervisor';
    }
  }

  String _initials(String email) {
    final local = email.split('@').first;
    final parts = local.split('.');
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return local.isNotEmpty ? local[0].toUpperCase() : '?';
  }

  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    try {
      await ref.read(pushMessagingServiceProvider).unregisterToken();
    } catch (e) {
      dev.log('[ProfileScreen] Push unregister failed: $e', name: 'push');
    }
    try {
      await ref.read(pushMessagingServiceProvider).dispose();
    } catch (e) {
      dev.log('[ProfileScreen] Push dispose failed: $e', name: 'push');
    }
    try {
      await ref.read(fichajeQueueRepositoryProvider).wipeAll();
    } catch (e) {
      dev.log('[ProfileScreen] Queue wipe failed: $e', name: 'logout');
    }
    await ref.read(tokenStorageProvider).clearSession();
    if (context.mounted) {
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'FuturaGest',
      applicationVersion: '1.0.0',
      applicationLegalese: '© 2026 FuturaGest. Todos los derechos reservados.',
      children: [
        const SizedBox(height: 12),
        const Text('Plataforma de gestión de personal de campo para equipos colombianos.'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;

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
                  'Mi Perfil',
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
          ListView(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + kToolbarHeight,
              bottom: 40,
            ),
            children: [
              // ── Avatar + info ──────────────────────────────────────────────────
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF005f48), Color(0xFF007a5e)],
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      child: Text(
                        _initials(profile.email),
                        style: GoogleFonts.manrope(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      profile.email,
                      style: GoogleFonts.manrope(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        _roleLabel(profile.role),
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Cuenta ────────────────────────────────────────────────────────
              _SectionHeader('Cuenta'),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Column(
                    children: [
                      _SettingsTile(
                        leading: const Icon(Icons.lock_outline, color: Color(0xFF005f48)),
                        title: 'Cambiar contraseña',
                        trailing: const Icon(Icons.chevron_right, color: Color(0xFF6e7a74)),
                        isFirst: true,
                        isLast: true,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ChangePasswordScreen(
                                profile: profile,
                                isVoluntary: true,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // ── Aplicación ────────────────────────────────────────────────────
              _SectionHeader('Aplicación'),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Column(
                    children: [
                      _SettingsTile(
                        leading: const Icon(Icons.info_outline, color: Color(0xFF005f48)),
                        title: 'Versión',
                        trailing: Text(
                          '1.0.0',
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            color: const Color(0xFF6e7a74),
                          ),
                        ),
                        isFirst: true,
                        isLast: false,
                      ),
                      Container(height: 1, color: const Color(0x14000000), margin: const EdgeInsets.only(left: 56)),
                      _SettingsTile(
                        leading: const Icon(Icons.article_outlined, color: Color(0xFF005f48)),
                        title: 'Acerca de FuturaGest',
                        trailing: const Icon(Icons.chevron_right, color: Color(0xFF6e7a74)),
                        isFirst: false,
                        isLast: true,
                        onTap: _showAbout,
                      ),
                    ],
                  ),
                ),
              ),

              // ── Cerrar sesión ─────────────────────────────────────────────────
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFba1a1a).withValues(alpha: 0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: FilledButton.icon(
                    onPressed: _loggingOut ? null : _logout,
                    icon: _loggingOut
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.logout),
                    label: const Text('Cerrar sesión'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFba1a1a),
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Settings tile ─────────────────────────────────────────────────────────────

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.leading,
    required this.title,
    this.trailing,
    required this.isFirst,
    required this.isLast,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final Widget? trailing;
  final bool isFirst;
  final bool isLast;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.only(
      topLeft: isFirst ? const Radius.circular(16) : Radius.zero,
      topRight: isFirst ? const Radius.circular(16) : Radius.zero,
      bottomLeft: isLast ? const Radius.circular(16) : Radius.zero,
      bottomRight: isLast ? const Radius.circular(16) : Radius.zero,
    );

    return Material(
      color: Colors.white.withValues(alpha: 0.7),
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF1a1c1b),
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: const Color(0xFF005f48),
        ),
      ),
    );
  }
}
