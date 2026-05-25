import '../../../core/constants/app_constants.dart';

class NotificacionModel {
  const NotificacionModel({
    this.id,
    this.usuarioId,
    required this.titulo,
    required this.mensaje,
    required this.tipo,
    this.modulo,
    this.referenciaId,
    this.usuarioNombre,
    this.estado = NotificacionEstados.pendiente,
    required this.fechaHora,
  });

  final int? id;
  final int? usuarioId;
  final String titulo;
  final String mensaje;
  final String tipo;
  final String? modulo;
  final int? referenciaId;
  final String? usuarioNombre;
  final String estado;
  final DateTime fechaHora;

  bool get estaLeida => estado == NotificacionEstados.leida;
  bool get esCritica => tipo == NotificacionTipos.critica;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'usuario_id': usuarioId,
      'titulo': titulo,
      'mensaje': mensaje,
      'tipo': tipo,
      'modulo': modulo,
      'referencia_id': referenciaId,
      'estado': estado,
      'fecha_hora': fechaHora.toIso8601String(),
    };
  }

  factory NotificacionModel.fromMap(Map<String, dynamic> map) {
    return NotificacionModel(
      id: map['id'] as int?,
      usuarioId: map['usuario_id'] as int?,
      titulo: map['titulo'] as String,
      mensaje: map['mensaje'] as String,
      tipo: map['tipo'] as String,
      modulo: map['modulo'] as String?,
      referenciaId: map['referencia_id'] as int?,
      usuarioNombre: map['usuario_nombre'] as String?,
      estado: map['estado'] as String,
      fechaHora: DateTime.parse(map['fecha_hora'] as String),
    );
  }
}
