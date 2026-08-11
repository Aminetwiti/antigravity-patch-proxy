/// Environment Configuration for Antigravity Remote Mobile App
/// Passed via `--dart-define` or default fallback to localhost loopback.
class EnvConfig {
  static const String environment = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: 'development',
  );

  static const String daemonHost = String.fromEnvironment(
    'DAEMON_HOST',
    defaultValue: '127.0.0.1',
  );

  static const int daemonPort = int.fromEnvironment(
    'DAEMON_PORT',
    defaultValue: 8080,
  );

  static const bool useSsl = bool.fromEnvironment(
    'USE_SSL',
    defaultValue: false,
  );

  static const bool enableLogging = bool.fromEnvironment(
    'ENABLE_LOGGING',
    defaultValue: true,
  );

  static String get wsUrl =>
      '${useSsl ? 'wss' : 'ws'}://$daemonHost:$daemonPort/ws';

  static String get httpUrl =>
      '${useSsl ? 'https' : 'http'}://$daemonHost:$daemonPort';
}
