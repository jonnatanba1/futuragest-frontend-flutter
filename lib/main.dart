import 'dart:developer' as dev;
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/push/push_messaging_service.dart';
import 'features/auth/domain/user_profile.dart';
import 'features/auth/presentation/home_screen.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase init is non-critical — a failure must NOT prevent the app from
  // booting (fichaje / attendance is core).
  try {
    await Firebase.initializeApp();
  } catch (e) {
    dev.log(
      '[main] Firebase.initializeApp() failed: $e — push will not work.',
      name: 'firebase',
    );
  }

  runApp(
    const ProviderScope(
      child: FuturagestApp(),
    ),
  );
}

class FuturagestApp extends StatelessWidget {
  const FuturagestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FuturaGest',
      debugShowCheckedModeBanner: false,
      navigatorKey: pushNavigatorKey,
      theme: _buildTheme(),
      initialRoute: '/splash',
      routes: {
        '/splash': (_) => const SplashScreen(),
        '/login': (_) => const LoginScreen(),
        '/home': (context) {
          final profile =
              ModalRoute.of(context)!.settings.arguments! as UserProfile;
          return HomeScreen(profile: profile);
        },
      },
    );
  }

  ThemeData _buildTheme() {
    const primary = Color(0xFF005f48);
    const primaryContainer = Color(0xFF007a5e);
    const onPrimary = Color(0xFFFFFFFF);
    const onPrimaryContainer = Color(0xFFa4ffdd);
    const secondary = Color(0xFF914c00);
    const secondaryContainer = Color(0xFFff8a00);
    const onSecondary = Color(0xFFFFFFFF);
    const tertiary = Color(0xFF00597d);
    const tertiaryContainer = Color(0xFF00739f);
    const onTertiary = Color(0xFFFFFFFF);
    const error = Color(0xFFba1a1a);
    const background = Color(0xFFf9f9fc);
    const surface = Color(0xFFf9f9fc);
    const surfaceContainerLowest = Color(0xFFFFFFFF);
    const surfaceContainerLow = Color(0xFFf3f3f6);
    const surfaceContainer = Color(0xFFeeeef0);
    const surfaceContainerHigh = Color(0xFFe8e8ea);
    const surfaceContainerHighest = Color(0xFFe2e2e5);
    const onSurface = Color(0xFF1a1c1e);
    const onSurfaceVariant = Color(0xFF3e4944);
    const outline = Color(0xFF6e7a74);
    const outlineVariant = Color(0xFFbdc9c2);
    const inversePrimary = Color(0xFF79d8b7);

    const cs = ColorScheme(
      brightness: Brightness.light,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,
      secondary: secondary,
      onSecondary: onSecondary,
      secondaryContainer: secondaryContainer,
      onSecondaryContainer: onSecondary,
      tertiary: tertiary,
      onTertiary: onTertiary,
      tertiaryContainer: tertiaryContainer,
      onTertiaryContainer: onTertiary,
      error: error,
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: surface,
      onSurface: onSurface,
      onSurfaceVariant: onSurfaceVariant,
      outline: outline,
      outlineVariant: outlineVariant,
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFF2f3133),
      onInverseSurface: Color(0xFFf1f0f4),
      inversePrimary: inversePrimary,
      surfaceContainerLowest: surfaceContainerLowest,
      surfaceContainerLow: surfaceContainerLow,
      surfaceContainer: surfaceContainer,
      surfaceContainerHigh: surfaceContainerHigh,
      surfaceContainerHighest: surfaceContainerHighest,
    );

    final manrope = GoogleFonts.manropeTextTheme();

    return ThemeData(
      colorScheme: cs,
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      textTheme: manrope.copyWith(
        displayLarge: manrope.displayLarge?.copyWith(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.02 * 32, color: onSurface),
        headlineLarge: manrope.headlineLarge?.copyWith(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.01 * 22, color: onSurface),
        headlineMedium: manrope.headlineMedium?.copyWith(fontSize: 20, fontWeight: FontWeight.w700, color: onSurface),
        titleLarge: manrope.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w600, color: onSurface),
        bodyLarge: manrope.bodyLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w400, color: onSurface),
        bodyMedium: manrope.bodyMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w400, color: onSurface),
        labelLarge: manrope.labelLarge?.copyWith(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.05 * 12, color: onSurface),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.manrope(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: primary,
        ),
        iconTheme: const IconThemeData(color: onSurface),
        actionsIconTheme: const IconThemeData(color: onSurfaceVariant),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        color: Colors.white.withValues(alpha: 0.7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainerLowest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        labelStyle: const TextStyle(color: onSurfaceVariant),
        floatingLabelBehavior: FloatingLabelBehavior.never,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600),
          elevation: 0,
        ).copyWith(
          shadowColor: WidgetStateProperty.all(const Color(0x40005f48)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      dividerTheme: DividerThemeData(
        color: outlineVariant.withValues(alpha: 0.5),
        thickness: 1,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        minLeadingWidth: 24,
      ),
    );
  }
}
