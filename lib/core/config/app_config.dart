/// Application-level configuration.
///
/// Override [apiBaseUrl] at build time:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3001
///
/// For Android emulator, 10.0.2.2 maps to the host machine's localhost.
/// The default points at the HTTPS production backend, so a plain
/// `flutter build apk` ships a prod-ready app; pass --dart-define for local dev.
class AppConfig {
  AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://backfuturagest.jjsoftech.com',
  );
}
