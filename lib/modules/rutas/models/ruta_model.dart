import '../../../core/constants/app_constants.dart';

class RutaModel {
  const RutaModel({
    this.id,
    required this.nombre,
    required this.zona,
    required this.cobradorId,
    this.estado = RutaEstados.activa,
    required this.fechaCreacion,
  });

  final int? id;
  final String nombre;
  final String zona;
  final int cobradorId;
  final String estado;
  final DateTime fechaCreacion;

  bool get estaActiva => estado == RutaEstados.activa;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nombre': nombre,
      'zona': zona,
      'cobrador_id': cobradorId,
      'estado': estado,
      'fecha_creacion': fechaCreacion.toIso8601String(),
    };
  }

  factory RutaModel.fromMap(Map<String, dynamic> map) {
    return RutaModel(
      id: map['id'] as int?,
      nombre: map['nombre'] as String,
      zona: map['zona'] as String,
      cobradorId: map['cobrador_id'] as int,
      estado: map['estado'] as String,
      fechaCreacion: DateTime.parse(map['fecha_creacion'] as String),
    );
  }
}
