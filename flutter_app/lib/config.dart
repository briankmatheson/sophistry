class AppConfig {
  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'https://app.sophistry.online',
  );
  static const int questionsPerSession = 4;
}
