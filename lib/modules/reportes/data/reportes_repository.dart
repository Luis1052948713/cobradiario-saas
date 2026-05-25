import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';

class ReporteCobros {
  const ReporteCobros({
    required this.desde,
    required this.hasta,
    required this.totalCobrado,
    required this.cantidadPagos,
    required this.cantidadVisitas,
    required this.saldoPendiente,
    required this.totalPrestado,
    required this.gananciaEstimada,
    required this.prestamosActivos,
    required this.prestamosPagados,
    required this.prestamosAtrasados,
    required this.clientesMorosos,
  });

  final DateTime desde;
  final DateTime hasta;
  final double totalCobrado;
  final int cantidadPagos;
  final int cantidadVisitas;
  final double saldoPendiente;
  final double totalPrestado;
  final double gananciaEstimada;
  final int prestamosActivos;
  final int prestamosPagados;
  final int prestamosAtrasados;
  final int clientesMorosos;

  int get movimientos => cantidadPagos + cantidadVisitas;
  double get promedioPorPago =>
      cantidadPagos == 0 ? 0 : totalCobrado / cantidadPagos;
}

class ReportesRepository {
  const ReportesRepository();

  Future<Database> get _db => DatabaseHelper.instance.database;

  Future<ReporteCobros> reportePorRango({
    required DateTime desde,
    required DateTime hasta,
    int? cobradorId,
  }) async {
    final db = await _db;
    final cobros = await _consultarCobros(
      db,
      desde: desde,
      hasta: hasta,
      cobradorId: cobradorId,
    );
    final cartera = await _consultarCartera(db, cobradorId: cobradorId);

    return ReporteCobros(
      desde: desde,
      hasta: hasta,
      totalCobrado: (cobros['total_cobrado'] as num).toDouble(),
      cantidadPagos: (cobros['cantidad_pagos'] as int?) ?? 0,
      cantidadVisitas: (cobros['cantidad_visitas'] as int?) ?? 0,
      saldoPendiente: (cartera['saldo_pendiente'] as num).toDouble(),
      totalPrestado: (cartera['total_prestado'] as num).toDouble(),
      gananciaEstimada: (cartera['ganancia_estimada'] as num).toDouble(),
      prestamosActivos: (cartera['prestamos_activos'] as int?) ?? 0,
      prestamosPagados: (cartera['prestamos_pagados'] as int?) ?? 0,
      prestamosAtrasados: (cartera['prestamos_atrasados'] as int?) ?? 0,
      clientesMorosos: (cartera['clientes_morosos'] as int?) ?? 0,
    );
  }

  Future<Map<String, Object?>> _consultarCobros(
    Database db, {
    required DateTime desde,
    required DateTime hasta,
    int? cobradorId,
  }) async {
    final where = StringBuffer('fecha_pago BETWEEN ? AND ?');
    final args = <Object?>[desde.toIso8601String(), hasta.toIso8601String()];

    if (cobradorId != null) {
      where.write(' AND cobrador_id = ?');
      args.add(cobradorId);
    }

    final rows = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN monto > 0 THEN monto ELSE 0 END), 0)
          AS total_cobrado,
        SUM(CASE WHEN monto > 0 THEN 1 ELSE 0 END) AS cantidad_pagos,
        SUM(CASE WHEN monto = 0 THEN 1 ELSE 0 END) AS cantidad_visitas
      FROM ${DatabaseTables.cobros}
      WHERE $where
      ''',
      args,
    );

    return rows.first;
  }

  Future<Map<String, Object?>> _consultarCartera(
    Database db, {
    int? cobradorId,
  }) async {
    final cobradorFilter = cobradorId == null ? '' : 'AND c.cobrador_id = ?';
    final args = <Object?>[];
    if (cobradorId != null) args.add(cobradorId);

    final rows = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(p.monto), 0) AS total_prestado,
        COALESCE(SUM(CASE
          WHEN p.estado IN ('activo', 'atrasado') THEN p.saldo
          ELSE 0
        END), 0) AS saldo_pendiente,
        COALESCE(SUM(p.total_pagar - p.monto), 0) AS ganancia_estimada,
        SUM(CASE WHEN p.estado = ? THEN 1 ELSE 0 END) AS prestamos_activos,
        SUM(CASE WHEN p.estado = ? THEN 1 ELSE 0 END) AS prestamos_pagados,
        SUM(CASE WHEN p.estado = ? THEN 1 ELSE 0 END) AS prestamos_atrasados,
        COUNT(DISTINCT CASE WHEN p.estado = ? THEN c.id ELSE NULL END)
          AS clientes_morosos
      FROM ${DatabaseTables.prestamos} p
      INNER JOIN ${DatabaseTables.clientes} c ON c.id = p.cliente_id
      WHERE 1 = 1 $cobradorFilter
      ''',
      [
        AppEstados.activo,
        AppEstados.pagado,
        AppEstados.atrasado,
        AppEstados.atrasado,
        ...args,
      ],
    );

    return rows.first;
  }
}
