import '../../../core/constants/app_constants.dart';
import '../../clientes/models/cliente_model.dart';
import '../../prestamos/models/prestamo_model.dart';

class RutaClienteDetalle {
  const RutaClienteDetalle({
    required this.rutaClienteId,
    required this.rutaId,
    required this.orden,
    required this.cliente,
    this.prestamoActivo,
    this.ultimoEstadoVisita,
    this.ultimaObservacion,
    this.ultimaVisita,
  });

  final int rutaClienteId;
  final int rutaId;
  final int orden;
  final ClienteModel cliente;
  final PrestamoModel? prestamoActivo;
  final String? ultimoEstadoVisita;
  final String? ultimaObservacion;
  final DateTime? ultimaVisita;

  double get saldoPendiente => prestamoActivo?.saldo ?? 0;

  bool get tienePagoHoy => ultimoEstadoVisita == RutaVisitaEstados.pago;

  bool get tieneGestionHoy => ultimoEstadoVisita != null;

  bool get porCobrar => prestamoActivo != null && !tieneGestionHoy;

  bool get noPagoHoy => tieneGestionHoy && !tienePagoHoy;

  bool get pendienteVisita => ultimoEstadoVisita == null;
}
