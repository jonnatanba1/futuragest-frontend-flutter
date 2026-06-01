import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Returns [true] if any of the given [ConnectivityResult]s indicates a
/// network connection.
bool _isConnected(List<ConnectivityResult> results) {
  return results.any(
    (r) =>
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.ethernet,
  );
}

/// Thin wrapper around [Connectivity] from connectivity_plus.
///
/// Exposes:
///  - [isOnlineStream] — broadcast stream of bool (true = connected).
///  - [isOnline()] — one-shot async check.
class ConnectivityService {
  ConnectivityService() : _connectivity = Connectivity();

  final Connectivity _connectivity;

  /// Stream that emits [true] when connected, [false] when not.
  Stream<bool> get isOnlineStream {
    return _connectivity.onConnectivityChanged.map(_isConnected);
  }

  /// Checks the current connectivity state once.
  Future<bool> isOnline() async {
    final results = await _connectivity.checkConnectivity();
    return _isConnected(results);
  }
}

// ── Providers ──────────────────────────────────────────────────────────────

/// Provides the singleton [ConnectivityService].
final connectivityServiceProvider = Provider<ConnectivityService>(
  (ref) => ConnectivityService(),
);

/// Stream provider that emits [true] when online, [false] when offline.
/// Automatically resubscribes when the provider is recreated.
final connectivityStreamProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  return service.isOnlineStream;
});
