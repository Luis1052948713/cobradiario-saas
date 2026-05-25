class RutaReporteModel {
  const RutaReporteModel({
    required this.totalClientes,
    required this.clientesVisitados,
    required this.clientesPendientes,
    required this.cobrosRealizados,
    required this.totalRecaudado,
  });

  final int totalClientes;
  final int clientesVisitados;
  final int clientesPendientes;
  final int cobrosRealizados;
  final double totalRecaudado;
}
