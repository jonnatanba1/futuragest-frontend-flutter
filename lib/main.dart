import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/presentation/login_screen.dart';

void main() {
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
