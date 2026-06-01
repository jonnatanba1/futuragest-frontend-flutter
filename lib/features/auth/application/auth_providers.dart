import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/storage/token_storage.dart';
import '../data/auth_repository_impl.dart';
import '../domain/auth_repository.dart';

// ── Infrastructure providers ───────────────────────────────────────────────

/// Provides the [TokenStorage] singleton.
final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

/// Provides the configured [Dio] client (with auth interceptor).
final dioProvider = Provider((ref) {
  final storage = ref.watch(tokenStorageProvider);
  return buildDioClient(storage);
});

// ── Repository provider ────────────────────────────────────────────────────

/// Provides the [AuthRepository] implementation.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(
    dio: ref.watch(dioProvider),
    storage: ref.watch(tokenStorageProvider),
  );
});

// ── Device ID provider ─────────────────────────────────────────────────────

/// Resolves the stable device UUID, creating and persisting it on first run.
final deviceIdProvider = FutureProvider<String>((ref) async {
  final storage = ref.watch(tokenStorageProvider);
  final existing = await storage.readDeviceId();
  if (existing != null) return existing;

  const uuid = Uuid();
  final newId = uuid.v4();
  await storage.saveDeviceId(newId);
  return newId;
});
