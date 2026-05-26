import '../../modules/auth/models/auth_profile.dart';
import '../../modules/usuarios/models/usuario_model.dart';
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
    OnlineIdMapper.instance.localIdFor(perfil.id);
  }

  void cerrarSesion() {
    _perfilActual = null;
    _usuarioActual = null;
    OnlineIdMapper.instance.clear();
  }
}
