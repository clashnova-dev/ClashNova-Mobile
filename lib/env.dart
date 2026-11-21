/// Build-time configuration, injected with `--dart-define-from-file=.env`.
///
/// Example `.env`:
/// ```
/// ENABLE_LOGIN=false
/// BASE_URL=
/// GITHUB_URL=
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
  static const String githubUrl = String.fromEnvironment('GITHUB_URL', defaultValue: 'https://github.com/clashnova-dev/ClashNova-Mobile');

}
