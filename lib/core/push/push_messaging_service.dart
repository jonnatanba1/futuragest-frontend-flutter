import 'dart:developer' as dev;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/push_token_service.dart';
import '../../features/novedades/presentation/lider_novedades_screen.dart';

// ── Background handler ───────────────────────────────────────────────────────
// Must be a top-level function and annotated so the Dart VM keeps it alive
// when the app is terminated / in background isolate.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // NOTE: Firebase.initializeApp() is NOT needed here — firebase_messaging
  // initializes Firebase automatically in the background isolate.
  dev.log(
    '[PushMessagingService] Background message: ${message.messageId}',
    name: 'push',
  );
  // We only log here. Navigation requires the main isolate — it will happen
  // via getInitialMessage() or onMessageOpenedApp when the user taps.
}

// ── Navigator key ────────────────────────────────────────────────────────────
// Exposed so main.dart can attach it to MaterialApp. The push service uses it
// to navigate without a BuildContext.
final GlobalKey<NavigatorState> pushNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'pushNavigatorKey');

// ── Service ──────────────────────────────────────────────────────────────────

/// Encapsulates all Firebase Cloud Messaging logic for the app.
///
/// Responsibilities:
///   - Request notification permission (Android 13+)
///   - Get and refresh the FCM token, registering it with the backend
///   - Handle foreground messages (SnackBar heads-up)
///   - Handle tap on notification (background → onMessageOpenedApp;
///     terminated → getInitialMessage)
///
/// Call [initialize] once after Firebase.initializeApp() and after the user
/// is authenticated (so the PushTokenService can call POST /auth/push-token).
class PushMessagingService {
  PushMessagingService(this._pushTokenService);

  final PushTokenService _pushTokenService;

  /// Wire up all FCM listeners and register the token with the backend.
  ///
  /// Safe to call multiple times — subsequent calls are no-ops if already set.
  Future<void> initialize() async {
    // 1. Register the top-level background handler.
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 2. Request permission (shows system dialog on Android 13+ / iOS).
    await _requestPermission();

    // 3. Get the current token and register it.
    await _fetchAndRegisterToken();

    // 4. Re-register on token rotation.
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      _safeRegister(newToken);
    });

    // 5. Foreground message → SnackBar heads-up.
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 6. Background tap (app was in background, user tapped notification).
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

    // 7. Terminated tap (app was killed, opened via notification).
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      // Delay one frame so the widget tree is fully built before navigating.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleMessageTap(initial);
      });
    }
  }

  // ── Permission ─────────────────────────────────────────────────────────────

  Future<void> _requestPermission() async {
    try {
      final settings =
          await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      dev.log(
        '[PushMessagingService] Permission: ${settings.authorizationStatus}',
        name: 'push',
      );
    } catch (e) {
      dev.log(
        '[PushMessagingService] Permission request failed: $e',
        name: 'push',
      );
    }
  }

  // ── Token ──────────────────────────────────────────────────────────────────

  Future<void> _fetchAndRegisterToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        dev.log(
          '[PushMessagingService] getToken() returned null — '
          'check google-services.json and network.',
          name: 'push',
        );
        return;
      }
      dev.log(
        '[PushMessagingService] FCM token obtained (length=${token.length})',
        name: 'push',
      );
      await _safeRegister(token);
    } catch (e) {
      dev.log(
        '[PushMessagingService] Token fetch error: $e',
        name: 'push',
      );
    }
  }

  Future<void> _safeRegister(String token) async {
    try {
      await _pushTokenService.register(token, pushPlatform: 'android');
      dev.log(
        '[PushMessagingService] Token registered with backend.',
        name: 'push',
      );
    } catch (e) {
      // Non-fatal: registration failure must never crash the app.
      dev.log(
        '[PushMessagingService] Token registration failed (non-fatal): $e',
        name: 'push',
      );
    }
  }

  // ── Message handlers ───────────────────────────────────────────────────────

  void _handleForegroundMessage(RemoteMessage message) {
    dev.log(
      '[PushMessagingService] Foreground message: ${message.messageId}',
      name: 'push',
    );

    final type = message.data['type'] as String?;
    if (type != 'NOVEDAD_CREATED') return;

    final context = pushNavigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Nueva novedad de horas extra recibida'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Ver',
          onPressed: () => _navigateToLiderScreen(),
        ),
      ),
    );
  }

  void _handleMessageTap(RemoteMessage message) {
    dev.log(
      '[PushMessagingService] Notification tapped: ${message.messageId}',
      name: 'push',
    );

    final type = message.data['type'] as String?;
    if (type != 'NOVEDAD_CREATED') return;

    _navigateToLiderScreen();
  }

  void _navigateToLiderScreen() {
    pushNavigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => const LiderNovedadesScreen(),
      ),
    );
  }
}

// ── Riverpod provider ─────────────────────────────────────────────────────────

/// Provider for [PushMessagingService].
///
/// Depends on [pushTokenServiceProvider] so token registration talks to the
/// backend through the existing auth repository.
final pushMessagingServiceProvider = Provider<PushMessagingService>((ref) {
  return PushMessagingService(ref.watch(pushTokenServiceProvider));
});
