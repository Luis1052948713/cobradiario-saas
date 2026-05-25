import '../../../core/constants/app_constants.dart';

class PrestamoModel {
  const PrestamoModel({
    this.id,
    required this.clienteId,
    required this.monto,
    required this.interes,
    required this.totalPagar,
    required this.cuotas,
    required this.cuotaDiaria,
    required this.saldo,
    required this.fechaInicio,
    this.fechaFin,
    this.estado = AppEstados.activo,
  });

  final int? id;
  final int clienteId;
  final double monto;
  final double interes;
  final double totalPagar;
  final int cuotas;
  final double cuotaDiaria;
  final double saldo;
  final DateTime fechaInicio;
  final DateTime? fechaFin;
  final String estado;

  bool get estaActivo => estado == AppEstados.activo;
  bool get estaPagado => estado == AppEstados.pagado;

  PrestamoModel copyWith({
    int? id,
    int? clienteId,
    double? monto,
    double? interes,
    double? totalPagar,
    int? cuotas,
    double? cuotaDiaria,
    double? saldo,
    DateTime? fechaInicio,
    DateTime? fechaFin,
    String? estado,
  }) {
    return PrestamoModel(
      id: id ?? this.id,
      clienteId: clienteId ?? this.clienteId,
      monto: monto ?? this.monto,
      interes: interes ?? this.interes,
      totalPagar: totalPagar ?? this.totalPagar,
      cuotas: cuotas ?? this.cuotas,
      cuotaDiaria: cuotaDiaria ?? this.cuotaDiaria,
      saldo: saldo ?? this.saldo,
      fechaInicio: fechaInicio ?? this.fechaInicio,
      fechaFin: fechaFin ?? this.fechaFin,
      estado: estado ?? this.estado,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cliente_id': clienteId,
      'monto': monto,
      'interes': interes,
      'total_pagar': totalPagar,
      'cuotas': cuotas,
      'cuota_diaria': cuotaDiaria,
      'saldo': saldo,
      'fecha_inicio': fechaInicio.toIso8601String(),
      'fecha_fin': fechaFin?.toIso8601String(),
      'estado': estado,
    };
  }

  factory PrestamoModel.fromMap(Map<String, dynamic> map) {
    return PrestamoModel(
      id: map['id'] as int?,
      clienteId: map['cliente_id'] as int,
      monto: (map['monto'] as num).toDouble(),
      interes: (map['interes'] as num).toDouble(),
      totalPagar: (map['total_pagar'] as num).toDouble(),
      cuotas: map['cuotas'] as int,
      cuotaDiaria: (map['cuota_diaria'] as num).toDouble(),
      saldo: (map['saldo'] as num).toDouble(),
      fechaInicio: DateTime.parse(map['fecha_inicio'] as String),
      fechaFin: map['fecha_fin'] == null
          ? null
          : DateTime.parse(map['fecha_fin'] as String),
      estado: map['estado'] as String,
    );
  }
}
