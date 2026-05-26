import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env_config.dart';

class SupabaseService {
  const SupabaseService._();

  static bool _initialized = false;

  static bool get isConfigured => EnvConfig.hasSupabaseConfig;
  static bool get isInitialized => _initialized;

  static SupabaseClient? get client {
    if (!_initialized) return null;
    return Supabase.instance.client;
  }

  static SupabaseClient get requireClient {
    final currentClient = client;
    if (currentClient == null) {
      throw StateError('Supabase no esta configurado o no fue inicializado.');
    }
    return currentClient;
  }

  static Future<bool> initializeIfConfigured() async {
    if (_initialized) return true;

    if (!isConfigured) {
      debugPrint(
        'Supabase no configurado: la app continua en modo local SQLite.',
      );
      return false;
    }

    await Supabase.initialize(
      url: EnvConfig.supabaseUrl,
      anonKey: EnvConfig.supabaseAnonKey,
    );

    _initialized = true;
    debugPrint('Supabase conectado: ${EnvConfig.environment.name}');
    return true;
  }
}
