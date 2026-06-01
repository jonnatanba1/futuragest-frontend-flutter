/// Application-level configuration.
///
/// Override [apiBaseUrl] at build time:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3001
///
/// For Android emulator, 10.0.2.2 maps to the host machine's localhost.
/// Default is http://localhost:3001 (works on iOS simulator and web).
class AppConfig {
  AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3001',
  );
}
