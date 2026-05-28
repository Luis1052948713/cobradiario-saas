import '../../modules/auth/models/auth_profile.dart';

import '../../modules/usuarios/models/usuario_model.dart';

import '../database/database_tables.dart';
import '../services/online_id_mapper.dart';

class SessionManager {
  SessionManager._internal();

  static final SessionManager instance = SessionManager._internal();

  AuthProfile? _perfilActual;

  UsuarioModel? _usuarioActual;

  AuthProfile? get perfilActual => _perfilActual;

  UsuarioModel? get usuarioActual => _usuarioActual;

  bool get haySesionActiva => _perfilActual != null;

  String? get empresaId => _perfilActual?.companyId;

  String? get usuarioAuthId => _perfilActual?.id;

  void iniciarSesion(AuthProfile perfil) {
    _perfilActual = perfil;
    _usuarioActual = perfil.toLegacyUsuario();

    final localId = _usuarioActual?.id;

    if (localId != null) {
      OnlineIdMapper.instance.remember(
        uuid: perfil.id,
        localId: localId,
        tabla: DatabaseTables.usuarios,
      );
    }
  }

  void cerrarSesion({bool limpiarMapeoOnline = true}) {
    _perfilActual = null;

    _usuarioActual = null;

    if (limpiarMapeoOnline) {
      OnlineIdMapper.instance.clear();
    }
  }
}
