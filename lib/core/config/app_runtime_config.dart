enum AppEnvironment { development, staging, production }

class AppRuntimeConfig {
  const AppRuntimeConfig({
    required this.environment,
    required this.useFirebase,
    this.firebaseProjectId = '',
    this.storeId = '',
  });

  factory AppRuntimeConfig.fromEnvironment() {
    final environmentName = const String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'development',
    );
    final environment = AppEnvironment.values.firstWhere(
      (value) => value.name == environmentName,
      orElse: () => AppEnvironment.development,
    );

    return AppRuntimeConfig(
      environment: environment,
      useFirebase: const bool.fromEnvironment(
        'USE_FIREBASE',
        defaultValue: false,
      ),
      firebaseProjectId: const String.fromEnvironment(
        'FIREBASE_PROJECT_ID',
        defaultValue: '',
      ),
      storeId: const String.fromEnvironment('STORE_ID', defaultValue: ''),
    );
  }

  final AppEnvironment environment;
  final bool useFirebase;
  final String firebaseProjectId;
  final String storeId;

  bool get isProduction => environment == AppEnvironment.production;
}
