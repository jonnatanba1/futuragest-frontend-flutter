import 'dart:developer' as dev;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/push/push_messaging_service.dart';
import 'features/auth/presentation/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase. Push notifications are non-critical — a failure here
  // must NOT prevent the app from booting (fichaje / attendance is core).
  try {
    await Firebase.initializeApp();
  } catch (e) {
    dev.log(
      '[main] Firebase.initializeApp() failed: $e — push will not work.',
      name: 'firebase',
    );
  }

  runApp(
    // ProviderScope is required at the root for Riverpod to work.
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
      // Global navigator key used by PushMessagingService to navigate without
      // a BuildContext (e.g. when a notification tap wakes the app).
      navigatorKey: pushNavigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0), // company blue
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      initialRoute: '/login',
      routes: {
        '/login': (_) => const LoginScreen(),
      },
    );
  }
}
