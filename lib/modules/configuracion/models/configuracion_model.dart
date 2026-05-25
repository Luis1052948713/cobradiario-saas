class ConfiguracionModel {
  const ConfiguracionModel({
    this.id,
    required this.clave,
    required this.valor,
    this.tipo = 'texto',
    required this.fechaActualizacion,
  });

  final int? id;
  final String clave;
  final String valor;
  final String tipo;
  final DateTime fechaActualizacion;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'clave': clave,
      'valor': valor,
      'tipo': tipo,
      'fecha_actualizacion': fechaActualizacion.toIso8601String(),
    };
  }

  factory ConfiguracionModel.fromMap(Map<String, dynamic> map) {
    return ConfiguracionModel(
      id: map['id'] as int?,
      clave: map['clave'] as String,
      valor: map['valor'] as String,
      tipo: map['tipo'] as String,
      fechaActualizacion: DateTime.parse(
        map['fecha_actualizacion'] as String,
      ),
    );
  }
}
