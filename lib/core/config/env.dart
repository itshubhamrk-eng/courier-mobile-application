/// Build-time settings, passed with `--dart-define`:
///
/// ```
/// flutter run --dart-define=API_BASE_URL=https://dev.example.com --dart-define=APP_ENV=dev
/// ```
class Env {
  const Env._();

  /// Backend origin without a trailing slash; endpoints add `/api/v1/...`.
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8080');

  /// `dev` or `prod`. Network logging is on only in `dev`.
  static const appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'dev');

  static bool get isDev => appEnv == 'dev';
}
