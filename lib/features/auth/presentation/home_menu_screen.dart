import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../domain/user_profile.dart';

/// Welcome menu screen — shows module cards that navigate to other tabs.
class HomeMenuScreen extends StatelessWidget {
  const HomeMenuScreen({
    super.key,
    required this.profile,
    this.onAsistencia,
    this.onNovedades,
    this.onSolicitudes,
    this.onLlegadasTarde,
    this.onPerfil,
  });

  final UserProfile profile;

  /// Navigate to Asistencia tab. Omit if the role has no access.
  final VoidCallback? onAsistencia;

  /// Navigate to Novedades tab. Omit if the role has no access (Supervisor).
  final VoidCallback? onNovedades;

  /// Navigate to Solicitudes tab. Omit if the role has no access (Líder/Coord).
  final VoidCallback? onSolicitudes;

  /// Navigate to Llegadas Tarde tab. Omit if the role has no access.
  final VoidCallback? onLlegadasTarde;

  /// Navigate to Perfil tab.
  final VoidCallback? onPerfil;

  String get _roleLabel {
    switch (profile.role) {
      case UserRole.supervisor:
        return 'Supervisor';
      case UserRole.liderOperativo:
        return 'Líder Operativo';
      case UserRole.systemAdmin:
        return 'Administrador';
      default:
        return profile.email.split('@').first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = <_CardDef>[
      if (onAsistencia != null)
        _CardDef(
          icon: Icons.event_available,
          title: 'Asistencia',
          subtitle: 'Gestioná fichajes y presencias',
          gradient: const [Color(0xFF005f48), Color(0xFF007a5e)],
          onTap: onAsistencia!,
        ),
      if (onNovedades != null)
        _CardDef(
          icon: Icons.new_releases,
          title: 'Novedades',
          subtitle: 'Revisá y cargá novedades del día',
          gradient: const [Color(0xFF00597d), Color(0xFF00739f)],
          onTap: onNovedades!,
        ),
      if (onSolicitudes != null)
        _CardDef(
          icon: Icons.task_alt,
          title: 'Solicitudes',
          subtitle: 'Aprobá o rechazá horas extra',
          gradient: const [Color(0xFF005f48), Color(0xFF007a5e)],
          onTap: onSolicitudes!,
        ),
      if (onLlegadasTarde != null)
        _CardDef(
          icon: Icons.warning_amber,
          title: 'Llegadas Tarde',
          subtitle: 'Revisá llegadas tarde del equipo',
          gradient: const [Color(0xFF914c00), Color(0xFFff8a00)],
          onTap: onLlegadasTarde!,
        ),
      if (onPerfil != null)
        _CardDef(
          icon: Icons.person_outline,
          title: 'Perfil',
          subtitle: 'Tu cuenta y configuración',
          gradient: const [Color(0xFF3e4944), Color(0xFF6e7a74)],
          onTap: onPerfil!,
        ),
    ];

    return CustomScrollView(
      slivers: [
        // Glassmorphism AppBar
        SliverAppBar(
          pinned: true,
          expandedHeight: 72,
          backgroundColor: Colors.transparent,
          flexibleSpace: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  border: Border(
                    bottom: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                  ),
                ),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/isotipo.png',
                      height: 32,
                      width: 32,
                    ),
                    const SizedBox(width: 10),
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Color(0xFF005f48), Color(0xFF00597d)],
                      ).createShader(bounds),
                      blendMode: BlendMode.srcIn,
                      child: Text(
                        'FuturaGest',
                        style: GoogleFonts.manrope(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.48,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Greeting
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '¡Hola, $_roleLabel! 👋',
                  style: GoogleFonts.manrope(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1a1c1a),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '¿Qué necesitás gestionar hoy?',
                  style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF3e4944),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Module cards
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _ModuleCard(def: cards[i]),
              ),
              childCount: cards.length,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Internal data class
// ---------------------------------------------------------------------------

class _CardDef {
  const _CardDef({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final VoidCallback onTap;
}

// ---------------------------------------------------------------------------
// Module card widget
// ---------------------------------------------------------------------------

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.def});

  final _CardDef def;

  @override
  Widget build(BuildContext context) {
    final iconColor = def.gradient.first;

    return GestureDetector(
      onTap: def.onTap,
      child: Container(
        padding: const EdgeInsets.all(24),
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
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.4),
              blurRadius: 0,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon container with gradient
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: def.gradient,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: iconColor.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(def.icon, color: Colors.white, size: 30),
            ),
            const SizedBox(width: 16),
            // Texts
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    def.title,
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1a1c1a),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    def.subtitle,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFF3e4944),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: def.gradient.first.withValues(alpha: 0.08),
              ),
              child: Icon(
                Icons.arrow_forward_ios,
                color: def.gradient.first,
                size: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
