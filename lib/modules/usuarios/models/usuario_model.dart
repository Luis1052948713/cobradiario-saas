import '../../../core/constants/app_constants.dart';

class UsuarioModel {
  const UsuarioModel({
    this.id,
    required this.nombre,
    required this.usuario,
    required this.contrasena,
    required this.rol,
    this.estado = AppEstados.activo,
    this.saldoDisponible = 0,
    required this.fechaCreacion,
  });

  final int? id;
  final String nombre;
  final String usuario;
  final String contrasena;
  final String rol;
  final String estado;
  final double saldoDisponible;
  final DateTime fechaCreacion;

  bool get estaActivo => estado == AppEstados.activo;
  bool get esSuperadmin {
    return rol == AppRoles.superadmin ||
        usuario.trim().toLowerCase() == AppRoles.superadmin;
  }

  bool get esAdministrador => rol == AppRoles.administrador && !esSuperadmin;
  bool get esCobrador => rol == AppRoles.cobrador;

  UsuarioModel copyWith({
    int? id,
    String? nombre,
    String? usuario,
    String? contrasena,
    String? rol,
    String? estado,
    double? saldoDisponible,
    DateTime? fechaCreacion,
  }) {
    return UsuarioModel(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      usuario: usuario ?? this.usuario,
      contrasena: contrasena ?? this.contrasena,
      rol: rol ?? this.rol,
      estado: estado ?? this.estado,
      saldoDisponible: saldoDisponible ?? this.saldoDisponible,
      fechaCreacion: fechaCreacion ?? this.fechaCreacion,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'usuario': usuario,
      'contrasena': contrasena,
      'rol': rol,
      'estado': estado,
      'saldo_disponible': saldoDisponible,
      'fecha_creacion': fechaCreacion.toIso8601String(),
    };
  }

  factory UsuarioModel.fromMap(Map<String, dynamic> map) {
    return UsuarioModel(
      id: map['id'] as int?,
      nombre: map['nombre'] as String,
      usuario: map['usuario'] as String,
      contrasena: map['contrasena'] as String,
      rol: map['rol'] as String,
      estado: map['estado'] as String,
      saldoDisponible: (map['saldo_disponible'] as num?)?.toDouble() ?? 0,
      fechaCreacion: DateTime.parse(map['fecha_creacion'] as String),
    );
  }
}
