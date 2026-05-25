import '../../../core/constants/app_constants.dart';

class ClienteModel {
  const ClienteModel({
    this.id,
    required this.nombre,
    this.cedula,
    this.telefono,
    this.direccion,
    this.barrio,
    this.referencia,
    this.foto,
    this.cobradorId,
    this.latitud,
    this.longitud,
    this.estado = AppEstados.activo,
    required this.fechaRegistro,
  });

  final int? id;
  final String nombre;
  final String? cedula;
  final String? telefono;
  final String? direccion;
  final String? barrio;
  final String? referencia;
  final String? foto;
  final int? cobradorId;
  final double? latitud;
  final double? longitud;
  final String estado;
  final DateTime fechaRegistro;

  bool get estaActivo => estado == AppEstados.activo;

  ClienteModel copyWith({
    int? id,
    String? nombre,
    String? cedula,
    String? telefono,
    String? direccion,
    String? barrio,
    String? referencia,
    String? foto,
    int? cobradorId,
    double? latitud,
    double? longitud,
    String? estado,
    DateTime? fechaRegistro,
  }) {
    return ClienteModel(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      cedula: cedula ?? this.cedula,
      telefono: telefono ?? this.telefono,
      direccion: direccion ?? this.direccion,
      barrio: barrio ?? this.barrio,
      referencia: referencia ?? this.referencia,
      foto: foto ?? this.foto,
      cobradorId: cobradorId ?? this.cobradorId,
      latitud: latitud ?? this.latitud,
      longitud: longitud ?? this.longitud,
      estado: estado ?? this.estado,
      fechaRegistro: fechaRegistro ?? this.fechaRegistro,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'cedula': cedula,
      'telefono': telefono,
      'direccion': direccion,
      'barrio': barrio,
      'referencia': referencia,
      'foto': foto,
      'cobrador_id': cobradorId,
      'latitud': latitud,
      'longitud': longitud,
      'estado': estado,
      'fecha_registro': fechaRegistro.toIso8601String(),
    };
  }

  factory ClienteModel.fromMap(Map<String, dynamic> map) {
    return ClienteModel(
      id: map['id'] as int?,
      nombre: map['nombre'] as String,
      cedula: map['cedula'] as String?,
      telefono: map['telefono'] as String?,
      direccion: map['direccion'] as String?,
      barrio: map['barrio'] as String?,
      referencia: map['referencia'] as String?,
      foto: map['foto'] as String?,
      cobradorId: map['cobrador_id'] as int?,
      latitud: (map['latitud'] as num?)?.toDouble(),
      longitud: (map['longitud'] as num?)?.toDouble(),
      estado: map['estado'] as String,
      fechaRegistro: DateTime.parse(map['fecha_registro'] as String),
    );
  }
}
