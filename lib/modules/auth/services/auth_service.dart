import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/session/session_manager.dart';
import '../models/auth_profile.dart';

class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthService {
  const AuthService();

  SupabaseClient get _client {
    if (!SupabaseService.isConfigured || !SupabaseService.isInitialized) {
      throw const AuthFailure(
        'Supabase no esta configurado. Define SUPABASE_URL y SUPABASE_ANON_KEY.',
      );
    }
    return SupabaseService.requireClient;
  }

  Session? get currentSession {
    if (!SupabaseService.isInitialized) return null;
    return SupabaseService.requireClient.auth.currentSession;
  }

  User? get currentUser {
    if (!SupabaseService.isInitialized) return null;
    return SupabaseService.requireClient.auth.currentUser;
  }

  AuthProfile? get currentProfile => SessionManager.instance.perfilActual;

  bool get hasValidSession => currentSession != null && currentUser != null;

  Stream<AuthState> get authStateChanges {
    return _client.auth.onAuthStateChange;
  }

  Future<AuthProfile?> restoreSession() async {
    if (!SupabaseService.isConfigured || !SupabaseService.isInitialized) {
      SessionManager.instance.cerrarSesion();
      return null;
    }

    final user = _client.auth.currentUser;
    final session = _client.auth.currentSession;
    if (user == null || session == null) {
      SessionManager.instance.cerrarSesion();
      return null;
    }

    final profile = await _loadProfileForUser(user);
    SessionManager.instance.iniciarSesion(profile);
    await _cacheProfile(profile);
    return profile;
  }

  Future<AuthProfile> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      final user = response.user;
      if (user == null) {
        throw const AuthFailure('No se pudo iniciar sesion.');
      }

      final profile = await _loadProfileForUser(user);
      if (!profile.estaActivo) {
        await _client.auth.signOut();
        SessionManager.instance.cerrarSesion();
        throw const AuthFailure('El usuario esta inactivo.');
      }

      SessionManager.instance.iniciarSesion(profile);
      await _cacheProfile(profile);
      return profile;
    } on AuthFailure {
      rethrow;
    } on AuthException catch (error) {
      throw AuthFailure(error.message);
    } on PostgrestException catch (error) {
      throw AuthFailure(error.message);
    } catch (error) {
      throw AuthFailure('Error al iniciar sesion: $error');
    }
  }

  Future<AuthProfile> registerCompanyAdmin({
    required String companyName,
    required String adminName,
    required String email,
    required String password,
    String? username,
    String? companyPhone,
    String? companyIdentification,
  }) async {
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'nombre': adminName.trim(),
          'empresa': companyName.trim(),
        },
      );

      final user = response.user;
      if (user == null) {
        throw const AuthFailure('No se pudo crear el usuario.');
      }

      if (response.session == null) {
        throw const AuthFailure(
          'Usuario creado. Revisa tu correo para confirmar la cuenta antes de ingresar.',
        );
      }

      await _client.rpc(
        'registrar_empresa_admin',
        params: {
          'p_empresa_nombre': companyName.trim(),
          'p_admin_nombre': adminName.trim(),
          'p_usuario': username?.trim(),
          'p_empresa_telefono': companyPhone?.trim(),
          'p_empresa_identificacion': companyIdentification?.trim(),
        },
      );

      final profile = await _loadProfileForUser(user);
      SessionManager.instance.iniciarSesion(profile);
      await _cacheProfile(profile);
      return profile;
    } on AuthFailure {
      rethrow;
    } on AuthException catch (error) {
      throw AuthFailure(error.message);
    } on PostgrestException catch (error) {
      throw AuthFailure(error.message);
    } catch (error) {
      throw AuthFailure('No se pudo registrar la empresa: $error');
    }
  }

  Future<void> logout() async {
    if (SupabaseService.isInitialized) {
      await SupabaseService.requireClient.auth.signOut();
    }
    SessionManager.instance.cerrarSesion();
  }

  Future<void> resetPasswordForEmail(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email.trim());
    } on AuthException catch (error) {
      throw AuthFailure(error.message);
    } catch (error) {
      throw AuthFailure('No se pudo enviar la recuperacion: $error');
    }
  }

  Future<AuthProfile> _loadProfileForUser(User user) async {
    final email = user.email ?? '';
    final row = await _client
        .from('perfiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (row == null) {
      throw const AuthFailure(
        'El usuario no tiene perfil asignado en Cobra Diario.',
      );
    }

    final profile = AuthProfile.fromMap(row, email: email);
    _validateProfile(profile);
    return profile;
  }

  void _validateProfile(AuthProfile profile) {
    const roles = {
      AppRoles.superadmin,
      AppRoles.administrador,
      AppRoles.cobrador,
    };

    if (!roles.contains(profile.rol)) {
      throw AuthFailure('Rol no permitido: ${profile.rol}.');
    }

    if (!profile.esSuperadmin && profile.companyId == null) {
      throw const AuthFailure('El usuario no tiene empresa asignada.');
    }
  }

  Future<void> _cacheProfile(AuthProfile profile) async {
    final usuario = profile.toLegacyUsuario();
    final id = usuario.id;
    if (id == null) return;

    final db = await DatabaseHelper.instance.database;
    await db.insert(
      DatabaseTables.usuarios,
      usuario.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await db.update(
      DatabaseTables.usuarios,
      usuario.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
