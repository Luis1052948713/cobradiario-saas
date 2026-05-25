import '../../../core/session/session_manager.dart';
import '../../auditoria/data/auditoria_repository.dart';
import '../../usuarios/data/usuario_repository.dart';
import '../../usuarios/models/usuario_model.dart';

class AuthService {
  const AuthService({
    this.usuarioRepository = const UsuarioRepository(),
    this.auditoriaRepository = const AuditoriaRepository(),
  });

  final UsuarioRepository usuarioRepository;
  final AuditoriaRepository auditoriaRepository;

  Future<UsuarioModel?> login({
    required String usuario,
    required String contrasena,
  }) async {
    final usuarioValido = await usuarioRepository.validarCredenciales(
      usuario: usuario,
      contrasena: contrasena,
    );

    if (usuarioValido != null) {
      SessionManager.instance.iniciarSesion(usuarioValido);
      await auditoriaRepository.registrar(
        accion: 'login',
        modulo: 'auth',
        descripcion: 'Inicio de sesion de ${usuarioValido.usuario}',
        usuarioId: usuarioValido.id,
      );
    }

    return usuarioValido;
  }

  Future<void> logout() async {
    final usuarioActual = SessionManager.instance.usuarioActual;
    if (usuarioActual != null) {
      await auditoriaRepository.registrar(
        accion: 'logout',
        modulo: 'auth',
        descripcion: 'Cierre de sesion de ${usuarioActual.usuario}',
        usuarioId: usuarioActual.id,
      );
    }
    SessionManager.instance.cerrarSesion();
  }
}
