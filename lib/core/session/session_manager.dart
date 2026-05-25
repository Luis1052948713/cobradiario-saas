import '../../modules/usuarios/models/usuario_model.dart';

class SessionManager {
  SessionManager._internal();

  static final SessionManager instance = SessionManager._internal();

  UsuarioModel? _usuarioActual;

  UsuarioModel? get usuarioActual => _usuarioActual;
  bool get haySesionActiva => _usuarioActual != null;

  void iniciarSesion(UsuarioModel usuario) {
    _usuarioActual = usuario;
  }

  void cerrarSesion() {
    _usuarioActual = null;
  }
}
