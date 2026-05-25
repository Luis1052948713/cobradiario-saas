class CobroModel {
  const CobroModel({
    this.id,
    required this.prestamoId,
    required this.cobradorId,
    required this.monto,
    this.saldoAnterior,
    this.saldoActual,
    this.observacion,
    required this.fechaPago,
    this.estado = 'registrado',
  });

  final int? id;
  final int prestamoId;
  final int cobradorId;
  final double monto;
  final double? saldoAnterior;
  final double? saldoActual;
  final String? observacion;
  final DateTime fechaPago;
  final String estado;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'prestamo_id': prestamoId,
      'cobrador_id': cobradorId,
      'monto': monto,
      'saldo_anterior': saldoAnterior,
      'saldo_actual': saldoActual,
      'observacion': observacion,
      'fecha_pago': fechaPago.toIso8601String(),
      'estado': estado,
    };
  }

  factory CobroModel.fromMap(Map<String, dynamic> map) {
    return CobroModel(
      id: map['id'] as int?,
      prestamoId: map['prestamo_id'] as int,
      cobradorId: map['cobrador_id'] as int,
      monto: (map['monto'] as num).toDouble(),
      saldoAnterior: (map['saldo_anterior'] as num?)?.toDouble(),
      saldoActual: (map['saldo_actual'] as num?)?.toDouble(),
      observacion: map['observacion'] as String?,
      fechaPago: DateTime.parse(map['fecha_pago'] as String),
      estado: (map['estado'] as String?) ?? 'registrado',
    );
  }
}
