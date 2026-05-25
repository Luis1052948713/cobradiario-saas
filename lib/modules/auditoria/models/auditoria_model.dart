class AuditoriaModel {
  const AuditoriaModel({
    this.id,
    this.usuarioId,
    required this.accion,
    required this.modulo,
    required this.descripcion,
    this.referenciaId,
    required this.fechaHora,
  });

  final int? id;
  final int? usuarioId;
  final String accion;
  final String modulo;
  final String descripcion;
  final int? referenciaId;
  final DateTime fechaHora;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'usuario_id': usuarioId,
      'accion': accion,
      'modulo': modulo,
      'descripcion': descripcion,
      'referencia_id': referenciaId,
      'fecha_hora': fechaHora.toIso8601String(),
    };
  }

  factory AuditoriaModel.fromMap(Map<String, dynamic> map) {
    return AuditoriaModel(
      id: map['id'] as int?,
      usuarioId: map['usuario_id'] as int?,
      accion: map['accion'] as String,
      modulo: map['modulo'] as String,
      descripcion: map['descripcion'] as String,
      referenciaId: map['referencia_id'] as int?,
      fechaHora: DateTime.parse(map['fecha_hora'] as String),
    );
  }
}
