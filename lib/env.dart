/// Build-time configuration, injected with `--dart-define-from-file=.env`.
///
/// Example `.env`:
/// ```
/// ENABLE_LOGIN=false
/// BASE_URL=
/// GITHUB_URL=
/// TELEGRAM_URL=
/// ```
class AppEnv {
  const AppEnv._();

  /// Whether the account / sign-in system is shown. When false the app skips
  /// the login screen and runs as a plain subscription client.
  static const bool enableLogin = bool.fromEnvironment('ENABLE_LOGIN', defaultValue: true);

  /// Control-panel base URL used for account login and plan subscriptions.
  /// Empty when the app is built without a control panel.
  static const String baseUrl = String.fromEnvironment('BASE_URL');

  /// About page: project repository link. Empty hides the row.
  /// Defaults to the project repo so the row shows out of the box; override
  /// via GITHUB_URL (e.g. for white-label builds), or set it empty to hide.
  static const String githubUrl = String.fromEnvironment(
    'GITHUB_URL',
    defaultValue: 'https://github.com/clashnova-dev/ClashNova-Mobile',
  );

  /// About page: chat group link. Empty hides the row.
  static const String telegramUrl = String.fromEnvironment('TELEGRAM_URL');
}
