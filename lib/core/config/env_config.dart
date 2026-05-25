import 'app_environment.dart';

class EnvConfig {
  const EnvConfig._();

  static final AppEnvironment environment = AppEnvironment.fromValue(
    const String.fromEnvironment('APP_ENV', defaultValue: 'development'),
  );

  static const String appName = String.fromEnvironment(
    'APP_NAME',
    defaultValue: 'Cobra Diario',
  );

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );
  static const String stripePublishableKey = String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
  );
  static const String webBaseUrl = String.fromEnvironment(
    'WEB_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );
  static const String supportEmail = String.fromEnvironment(
    'SUPPORT_EMAIL',
    defaultValue: 'soporte@cobradiario.local',
  );
  static const String minSupportedVersion = String.fromEnvironment(
    'MIN_SUPPORTED_VERSION',
    defaultValue: '1.0.0',
  );
  static const String recommendedVersion = String.fromEnvironment(
    'RECOMMENDED_VERSION',
    defaultValue: '1.0.0',
  );

  static bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get hasStripeConfig => stripePublishableKey.isNotEmpty;
}
