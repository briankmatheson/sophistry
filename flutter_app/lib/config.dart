class AppConfig {
  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'https://app.sophistry.online',
  );
  static const String appVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: 'dev',
  );
  static const int questionsPerSession = 4;
}
