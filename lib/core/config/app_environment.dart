enum AppEnvironment {
  development,
  staging,
  production;

  static AppEnvironment fromValue(String value) {
    switch (value.trim().toLowerCase()) {
      case 'production':
      case 'prod':
        return AppEnvironment.production;
      case 'staging':
      case 'stage':
        return AppEnvironment.staging;
      case 'development':
      case 'dev':
      default:
        return AppEnvironment.development;
    }
  }

  bool get isProduction => this == AppEnvironment.production;
  bool get isStaging => this == AppEnvironment.staging;
  bool get isDevelopment => this == AppEnvironment.development;
}
