import '../../../core/constants/app_constants.dart';
import '../../../core/services/online_id_mapper.dart';
import '../../usuarios/models/usuario_model.dart';

class AuthProfile {
  const AuthProfile({
    required this.id,
    required this.nombre,
    required this.email,
    required this.rol,
    required this.estado,
    required this.createdAt,
    this.companyId,
    this.usuario,
    this.saldoDisponible = 0,
  });

  final String id;
  final String? companyId;
  final String nombre;
  final String email;
  final String? usuario;
  final String rol;
  final String estado;
  final double saldoDisponible;
  final DateTime createdAt;

  bool get estaActivo => estado == AppEstados.activo;
  bool get esSuperadmin => rol == AppRoles.superadmin;
  bool get esAdministrador => rol == AppRoles.administrador && !esSuperadmin;
  bool get esCobrador => rol == AppRoles.cobrador;

  UsuarioModel toLegacyUsuario() {
    return UsuarioModel(
      id: OnlineIdMapper.instance.localIdFor(id),
      nombre: nombre,
      usuario: usuario?.isNotEmpty == true ? usuario! : email,
      contrasena: '',
      rol: rol,
      estado: estado,
      saldoDisponible: saldoDisponible,
      fechaCreacion: createdAt,
    );
  }

  factory AuthProfile.fromMap(
    Map<String, dynamic> map, {
    required String email,
  }) {
    return AuthProfile(
      id: map['id'] as String,
      companyId: map['empresa_id'] as String?,
      nombre: map['nombre'] as String? ?? email,
      email: email,
      usuario: map['usuario'] as String?,
      rol: map['rol'] as String? ?? AppRoles.cobrador,
      estado: map['estado'] as String? ?? AppEstados.inactivo,
      saldoDisponible: (map['saldo_disponible'] as num?)?.toDouble() ?? 0,
      createdAt: map['created_at'] == null
          ? DateTime.now()
          : DateTime.parse(map['created_at'] as String),
    );
  }
}
