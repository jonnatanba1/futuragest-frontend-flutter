import 'dart:developer' as dev;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/push/push_messaging_service.dart';
import '../../../features/attendance/application/attendance_providers.dart';
import '../../../features/attendance/presentation/operario_list_screen.dart';
import '../../../features/novedades/presentation/lider_novedades_screen.dart';
import '../../../features/novedades/presentation/llegadas_tarde_screen.dart';
import '../../../features/novedades/presentation/novedades_list_screen.dart';
import '../../../features/profile/presentation/profile_screen.dart';
import '../domain/user_profile.dart';
import 'home_menu_screen.dart';

/// Shell screen shown after a successful login.
/// Hosts a floating pill bottom nav and switches between role-appropriate tabs.
/// FCM push-token registration is triggered from [initState] (post-auth hook).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;
  late List<_TabDef> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = _buildTabs();
    _initPush();
  }

  Future<void> _initPush() async {
    try {
      await ref.read(pushMessagingServiceProvider).initialize();
    } catch (e) {
      dev.log('[HomeScreen] Push init failed (non-fatal): $e', name: 'push');
    }
  }

  void _navigateTo(int i) => setState(() => _selectedIndex = i);

  List<_TabDef> _buildTabs() {
    final profileScreen = ProfileScreen(profile: widget.profile);
    switch (widget.profile.role) {
      case UserRole.supervisor:
        return [
          _TabDef(
            icon: Icons.home_outlined,
            activeIcon: Icons.home,
            label: 'Home',
            screen: HomeMenuScreen(
              profile: widget.profile,
              onAsistencia: () => _navigateTo(1),
              onNovedades: () => _navigateTo(2),
              onPerfil: () => _navigateTo(3),
            ),
          ),
          _TabDef(
            icon: Icons.assignment_ind_outlined,
            activeIcon: Icons.assignment_ind,
            label: 'Asistencia',
            screen: const OperarioListScreen(),
          ),
          _TabDef(
            icon: Icons.schedule_outlined,
            activeIcon: Icons.schedule,
            label: 'Novedades',
            screen: const NovedadesListScreen(),
          ),
          _TabDef(
            icon: Icons.person_outline,
            activeIcon: Icons.person,
            label: 'Perfil',
            screen: profileScreen,
          ),
        ];
      case UserRole.liderOperativo:
      case UserRole.coordinador:
      case UserRole.systemAdmin:
        return [
          _TabDef(
            icon: Icons.home_outlined,
            activeIcon: Icons.home,
            label: 'Home',
            screen: HomeMenuScreen(
              profile: widget.profile,
              onSolicitudes: () => _navigateTo(1),
              onLlegadasTarde: () => _navigateTo(2),
              onPerfil: () => _navigateTo(3),
            ),
          ),
          _TabDef(
            icon: Icons.task_alt_outlined,
            activeIcon: Icons.task_alt,
            label: 'Solicitudes',
            screen: const LiderNovedadesScreen(),
          ),
          _TabDef(
            icon: Icons.warning_amber_outlined,
            activeIcon: Icons.warning_amber,
            label: 'Llegadas Tarde',
            screen: const LlegadasTardeScreen(),
          ),
          _TabDef(
            icon: Icons.person_outline,
            activeIcon: Icons.person,
            label: 'Perfil',
            screen: profileScreen,
          ),
        ];
      default:
        return [
          _TabDef(
            icon: Icons.home_outlined,
            activeIcon: Icons.home,
            label: 'Home',
            screen: HomeMenuScreen(
              profile: widget.profile,
              onPerfil: () => _navigateTo(1),
            ),
          ),
          _TabDef(
            icon: Icons.person_outline,
            activeIcon: Icons.person,
            label: 'Perfil',
            screen: profileScreen,
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    final syncStats = ref.watch(syncStatsProvider);
    final pendingBadge = syncStats.pending + syncStats.failed;
    final safeIndex = _selectedIndex.clamp(0, tabs.length - 1);

    return Scaffold(
      extendBody: true,
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
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF005f48).withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Orange blob bottom-left
          Positioned(
            bottom: 80,
            left: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFff8a00).withValues(alpha: 0.1),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Main content (IndexedStack) with bottom padding for floating nav
          Padding(
            padding: const EdgeInsets.only(bottom: 104),
            child: IndexedStack(
              index: safeIndex,
              children: tabs.map((t) => t.screen).toList(),
            ),
          ),
          // Floating pill bottom nav
          if (tabs.length > 1)
            Positioned(
              bottom: 24,
              left: 16,
              right: 16,
              height: 80,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 24,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: tabs.asMap().entries.map((entry) {
                        final index = entry.key;
                        final tab = entry.value;
                        final isSelected = safeIndex == index;
                        final isAsistencia = tab.label == 'Asistencia';
                        final showBadge = isAsistencia && pendingBadge > 0;

                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedIndex = index),
                            behavior: HitTestBehavior.opaque,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? const Color(0xFF005f48).withValues(alpha: 0.12)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: Icon(
                                        isSelected ? tab.activeIcon : tab.icon,
                                        color: isSelected
                                            ? const Color(0xFF005f48)
                                            : const Color(0xFF3e4944),
                                        size: 22,
                                      ),
                                    ),
                                    if (showBadge)
                                      Positioned(
                                        top: -2,
                                        right: -2,
                                        child: Container(
                                          width: 10,
                                          height: 10,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFba1a1a),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  tab.label,
                                  style: GoogleFonts.manrope(
                                    fontSize: 11,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                    color: isSelected
                                        ? const Color(0xFF005f48)
                                        : const Color(0xFF3e4944),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabDef {
  const _TabDef({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.screen,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final Widget screen;
}
