import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_providers.dart';
import '../../features/auth/application/push_token_service.dart';
import '../../features/novedades/presentation/lider_novedades_screen.dart';
import '../storage/token_storage.dart';

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
  PushMessagingService(this._pushTokenService, this._tokenStorage);

  final PushTokenService _pushTokenService;
  final TokenStorage _tokenStorage;

  /// Guards against duplicate initialization (e.g. logout + login mounts a new
  /// HomeScreen, which would otherwise attach a second set of FCM listeners and
  /// produce double SnackBars).
  bool _initialized = false;

  // Stored subscriptions so [dispose] can cancel them and prevent leaks /
  // duplicate listeners across re-initialization.
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSub;
  StreamSubscription<String>? _onTokenRefreshSub;

  /// Wire up all FCM listeners and register the token with the backend.
  ///
  /// Idempotent — subsequent calls are no-ops while already initialized. Call
  /// [dispose] before re-initializing if you need a fresh set of listeners.
  Future<void> initialize() async {
    if (_initialized) {
      dev.log(
        '[PushMessagingService] initialize() skipped — already initialized.',
        name: 'push',
      );
      return;
    }
    _initialized = true;

    // 1. Register the top-level background handler.
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 2. Request permission (shows system dialog on Android 13+ / iOS).
    await _requestPermission();

    // 3. Get the current token and register it.
    await _fetchAndRegisterToken();

    // 4. Re-register on token rotation.
    _onTokenRefreshSub =
        FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      _safeRegister(newToken);
    });

    // 5. Foreground message → SnackBar heads-up.
    _onMessageSub = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 6. Background tap (app was in background, user tapped notification).
    _onMessageOpenedAppSub =
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

  /// Cancels all FCM stream listeners and resets the initialized flag so a
  /// later [initialize] re-attaches a fresh set. Call this on logout to avoid
  /// duplicate listeners (and duplicate SnackBars) after a re-login.
  Future<void> dispose() async {
    await _onMessageSub?.cancel();
    await _onMessageOpenedAppSub?.cancel();
    await _onTokenRefreshSub?.cancel();
    _onMessageSub = null;
    _onMessageOpenedAppSub = null;
    _onTokenRefreshSub = null;
    _initialized = false;
  }

  /// Deletes the device FCM token (Firebase) and clears it on the backend.
  ///
  /// Failure-safe at every step — a failure must never block logout.
  Future<void> unregisterToken() async {
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      dev.log(
        '[PushMessagingService] deleteToken() failed (non-fatal): $e',
        name: 'push',
      );
    }
    await _pushTokenService.unregister();
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

    final novedadId = message.data['novedadId'] as String?;

    final context = pushNavigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Nueva novedad de horas extra recibida'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Ver',
          onPressed: () => _navigateToLiderScreen(novedadId),
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

    final novedadId = message.data['novedadId'] as String?;
    _navigateToLiderScreen(novedadId);
  }

  /// Opens the lider approval screen — but ONLY for roles allowed to approve
  /// novedades (LIDER_OPERATIVO / SYSTEM_ADMIN). A push can land on any device,
  /// so we re-check the current user's role (from the stored access token) before
  /// navigating; the backend still enforces approve/reject, this avoids a
  /// non-lider user landing on the approval screen.
  Future<void> _navigateToLiderScreen([String? highlightNovedadId]) async {
    final token = await _tokenStorage.readAccessToken();
    final role = token != null ? _decodeRole(token) : null;
    if (role != 'LIDER_OPERATIVO' && role != 'COORDINADOR' && role != 'SYSTEM_ADMIN') {
      dev.log(
        '[PushMessagingService] Ignoring lider deep-link for role "$role".',
        name: 'push',
      );
      return;
    }
    pushNavigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) =>
            LiderNovedadesScreen(highlightNovedadId: highlightNovedadId),
      ),
    );
  }

  /// Decode (does not verify) the `role` claim from a JWT access token.
  String? _decodeRole(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      final payload = json.decode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      return payload['role'] as String?;
    } catch (_) {
      return null;
    }
  }
}

// ── Riverpod provider ─────────────────────────────────────────────────────────

/// Provider for [PushMessagingService].
///
/// Depends on [pushTokenServiceProvider] so token registration talks to the
/// backend through the existing auth repository.
final pushMessagingServiceProvider = Provider<PushMessagingService>((ref) {
  return PushMessagingService(
    ref.watch(pushTokenServiceProvider),
    ref.watch(tokenStorageProvider),
  );
});
