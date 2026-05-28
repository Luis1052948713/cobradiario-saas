import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';
import '../../../core/services/online_id_mapper.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/session/session_manager.dart';

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
  double get efectividadVisitas =>
      movimientos == 0 ? 0 : (cantidadPagos / movimientos) * 100;
  double get coberturaRecaudo =>
      totalPrestado == 0 ? 0 : (totalCobrado / totalPrestado) * 100;

  factory ReporteCobros.vacio({
    required DateTime desde,
    required DateTime hasta,
  }) {
    return ReporteCobros(
      desde: desde,
      hasta: hasta,
      totalCobrado: 0,
      cantidadPagos: 0,
      cantidadVisitas: 0,
      saldoPendiente: 0,
      totalPrestado: 0,
      gananciaEstimada: 0,
      prestamosActivos: 0,
      prestamosPagados: 0,
      prestamosAtrasados: 0,
      clientesMorosos: 0,
    );
  }
}

class ReportesRepository {
  const ReportesRepository();

  Future<Database> get _db => DatabaseHelper.instance.database;

  Future<ReporteCobros> reportePorRango({
    required DateTime desde,
    required DateTime hasta,
    int? cobradorId,
  }) async {
    if (_usaSupabase) {
      return _reportePorRangoOnline(
        desde: desde,
        hasta: hasta,
        cobradorId: cobradorId,
      );
    }

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

  bool get _usaSupabase {
    return SupabaseService.isInitialized &&
        SessionManager.instance.perfilActual != null;
  }

  Future<ReporteCobros> _reportePorRangoOnline({
    required DateTime desde,
    required DateTime hasta,
    int? cobradorId,
  }) async {
    final cobradorUuid = OnlineIdMapper.instance.uuidFor(cobradorId);
    final desdeIso = desde.toIso8601String();
    final hastaIso = hasta.toIso8601String();

    dynamic cobrosQuery = SupabaseService.requireClient
        .from('cobros')
        .select('monto, cobrador_id, fecha_pago, estado')
        .gte('fecha_pago', desdeIso)
        .lte('fecha_pago', hastaIso);
    if (cobradorUuid != null) {
      cobrosQuery = cobrosQuery.eq('cobrador_id', cobradorUuid);
    }
    final cobros = _rows(await cobrosQuery);

    final cobrosRegistrados = cobros.where((row) {
      return (row['estado'] as String?) != 'anulado';
    }).toList();
    final totalCobrado = cobrosRegistrados.fold<double>(
      0,
      (total, row) => total + _toDouble(row['monto']),
    );
    final cantidadPagos = cobrosRegistrados.where((row) {
      return _toDouble(row['monto']) > 0;
    }).length;
    final cantidadVisitas = cobrosRegistrados.where((row) {
      return _toDouble(row['monto']) == 0;
    }).length;

    var clienteIds = <String>[];
    if (cobradorUuid != null) {
      final clientes = await SupabaseService.requireClient
          .from('clientes')
          .select('id')
          .eq('cobrador_id', cobradorUuid);
      clienteIds = _rows(clientes)
          .map<String>((row) => row['id'] as String)
          .toList();
      if (clienteIds.isEmpty) {
        return ReporteCobros.vacio(desde: desde, hasta: hasta);
      }
    }

    dynamic prestamosQuery = SupabaseService.requireClient
        .from('prestamos')
        .select('monto, total_pagar, saldo, estado, cliente_id');
    if (clienteIds.isNotEmpty) {
      prestamosQuery = prestamosQuery.inFilter('cliente_id', clienteIds);
    }
    final prestamos = _rows(await prestamosQuery);

    final totalPrestado = prestamos.fold<double>(
      0,
      (total, row) => total + _toDouble(row['monto']),
    );
    final saldoPendiente = prestamos.fold<double>(0, (total, row) {
      final estado = row['estado'] as String?;
      if (estado == AppEstados.activo || estado == AppEstados.atrasado) {
        return total + _toDouble(row['saldo']);
      }
      return total;
    });
    final gananciaEstimada = prestamos.fold<double>(
      0,
      (total, row) => total + _toDouble(row['total_pagar']) - _toDouble(row['monto']),
    );
    final prestamosActivos = prestamos.where((row) {
      return row['estado'] == AppEstados.activo;
    }).length;
    final prestamosPagados = prestamos.where((row) {
      return row['estado'] == AppEstados.pagado;
    }).length;
    final prestamosAtrasados = prestamos.where((row) {
      return row['estado'] == AppEstados.atrasado;
    }).length;
    final clientesMorosos = prestamos
        .where((row) => row['estado'] == AppEstados.atrasado)
        .map((row) => row['cliente_id'] as String?)
        .whereType<String>()
        .toSet()
        .length;

    return ReporteCobros(
      desde: desde,
      hasta: hasta,
      totalCobrado: totalCobrado,
      cantidadPagos: cantidadPagos,
      cantidadVisitas: cantidadVisitas,
      saldoPendiente: saldoPendiente,
      totalPrestado: totalPrestado,
      gananciaEstimada: gananciaEstimada,
      prestamosActivos: prestamosActivos,
      prestamosPagados: prestamosPagados,
      prestamosAtrasados: prestamosAtrasados,
      clientesMorosos: clientesMorosos,
    );
  }
}

double _toDouble(Object? value) => (value as num?)?.toDouble() ?? 0;

List<Map<String, dynamic>> _rows(Object? value) {
  final rows = value as List<dynamic>? ?? const [];
  return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
}
