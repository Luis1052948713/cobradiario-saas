import '../constants/app_constants.dart';
import '../session/session_manager.dart';

class PermissionService {
  const PermissionService();

  bool get esSuperadmin {
    return SessionManager.instance.perfilActual?.esSuperadmin == true ||
        SessionManager.instance.usuarioActual?.esSuperadmin == true;
  }

  bool get esAdministrador {
    return SessionManager.instance.perfilActual?.esAdministrador == true ||
        SessionManager.instance.usuarioActual?.esAdministrador == true;
  }

  bool get esCobrador {
    return SessionManager.instance.perfilActual?.esCobrador == true ||
        SessionManager.instance.usuarioActual?.rol == AppRoles.cobrador;
  }

  bool puedeAdministrarUsuarios() => esAdministrador;
  bool puedeVerConfiguracion() => esAdministrador || esSuperadmin;
  bool puedeVerReportesGlobales() => esAdministrador;
  bool puedeCrearClientes() => esAdministrador || esCobrador;
  bool puedeEditarClientes() => esAdministrador || esCobrador;
  bool puedeAsignarClientes() => esAdministrador;
  bool puedeCambiarEstadoClientes() => esAdministrador;
  bool puedeCrearPrestamos() => esAdministrador || esCobrador;
  bool puedeEditarPrestamos() => esAdministrador;
  bool puedeExportarReportes() => esAdministrador;
  bool puedeVerAuditoria() => esAdministrador || esCobrador || esSuperadmin;
  bool puedeVerAuditoriaGlobal() => esAdministrador || esSuperadmin;

  int? cobradorScope() {
    final usuario = SessionManager.instance.usuarioActual;
    final perfil = SessionManager.instance.perfilActual;
    if (perfil?.esCobrador == true) {
      return usuario?.id ?? -1;
    }
    if (usuario == null || usuario.esAdministrador || usuario.esSuperadmin) {
      return null;
    }
    return usuario.id;
  }
}
