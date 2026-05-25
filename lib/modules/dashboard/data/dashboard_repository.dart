import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';

class DashboardResumen {
  const DashboardResumen({
    required this.totalCobradoHoy,
    required this.prestamosHoy,
    required this.clientesActivos,
    required this.prestamosActivos,
    required this.cobrosPendientes,
    required this.clientesAtrasados,
    required this.saldoPendiente,
    required this.capitalDisponible,
    required this.cajasAbiertas,
    required this.cobradoresActivos,
  });

  final double totalCobradoHoy;
  final int prestamosHoy;
  final int clientesActivos;
  final int prestamosActivos;
  final int cobrosPendientes;
  final int clientesAtrasados;
  final double saldoPendiente;
  final double capitalDisponible;
  final int cajasAbiertas;
  final int cobradoresActivos;
}

class DashboardRepository {
  const DashboardRepository();

  Future<Database> get _db => DatabaseHelper.instance.database;

  Future<DashboardResumen> obtenerResumen({int? cobradorId}) async {
    final db = await _db;
    final inicioDia = _inicioDia(DateTime.now()).toIso8601String();
    final finDia = _finDia(DateTime.now()).toIso8601String();

    final totalCobradoHoy = await _sumarCobrado(
      db,
      inicioDia: inicioDia,
      finDia: finDia,
      cobradorId: cobradorId,
    );
    final clientesActivos = await _contarClientesActivos(db, cobradorId);
    final prestamosActivos = await _contarPrestamosActivos(db, cobradorId);
    final prestamosHoy = await _contarPrestamosHoy(
      db,
      inicioDia: inicioDia,
      finDia: finDia,
      cobradorId: cobradorId,
    );
    final saldoPendiente = await _sumarSaldoPendiente(db, cobradorId);
    final clientesAtrasados = await _contarClientesAtrasados(db, cobradorId);
    final capitalDisponible = cobradorId == null
        ? await _capitalDisponible(db)
        : 0.0;
    final cajasAbiertas = await _contarCajasAbiertas(db, cobradorId);
    final cobradoresActivos = await _contarCobradoresActivos(db);

    return DashboardResumen(
      totalCobradoHoy: totalCobradoHoy,
      prestamosHoy: prestamosHoy,
      clientesActivos: clientesActivos,
      prestamosActivos: prestamosActivos,
      cobrosPendientes: prestamosActivos,
      clientesAtrasados: clientesAtrasados,
      saldoPendiente: saldoPendiente,
      capitalDisponible: capitalDisponible,
      cajasAbiertas: cajasAbiertas,
      cobradoresActivos: cobradoresActivos,
    );
  }

  Future<double> _sumarCobrado(
    Database db, {
    required String inicioDia,
    required String finDia,
    int? cobradorId,
  }) async {
    final where = StringBuffer('fecha_pago BETWEEN ? AND ?');
    final args = <Object?>[inicioDia, finDia];

    if (cobradorId != null) {
      where.write(' AND cobrador_id = ?');
      args.add(cobradorId);
    }

    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(monto), 0) AS total
      FROM ${DatabaseTables.cobros}
      WHERE $where
      ''', args);

    return (rows.first['total'] as num).toDouble();
  }

  Future<int> _contarClientesActivos(Database db, int? cobradorId) async {
    final where = StringBuffer('estado = ?');
    final args = <Object?>[AppEstados.activo];

    if (cobradorId != null) {
      where.write(' AND cobrador_id = ?');
      args.add(cobradorId);
    }

    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS total
      FROM ${DatabaseTables.clientes}
      WHERE $where
      ''', args);

    return (rows.first['total'] as int?) ?? 0;
  }

  Future<int> _contarPrestamosActivos(Database db, int? cobradorId) async {
    final args = <Object?>[AppEstados.activo, AppEstados.atrasado];
    final cobradorFilter = cobradorId == null ? '' : 'AND c.cobrador_id = ?';
    if (cobradorId != null) args.add(cobradorId);

    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS total
      FROM ${DatabaseTables.prestamos} p
      INNER JOIN ${DatabaseTables.clientes} c ON c.id = p.cliente_id
      WHERE p.estado IN (?, ?) $cobradorFilter
      ''', args);

    return (rows.first['total'] as int?) ?? 0;
  }

  Future<int> _contarPrestamosHoy(
    Database db, {
    required String inicioDia,
    required String finDia,
    int? cobradorId,
  }) async {
    final args = <Object?>[inicioDia, finDia];
    final cobradorFilter = cobradorId == null ? '' : 'AND c.cobrador_id = ?';
    if (cobradorId != null) args.add(cobradorId);

    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS total
      FROM ${DatabaseTables.prestamos} p
      INNER JOIN ${DatabaseTables.clientes} c ON c.id = p.cliente_id
      WHERE p.fecha_inicio BETWEEN ? AND ? $cobradorFilter
      ''', args);

    return (rows.first['total'] as int?) ?? 0;
  }

  Future<double> _sumarSaldoPendiente(Database db, int? cobradorId) async {
    final args = <Object?>[AppEstados.activo, AppEstados.atrasado];
    final cobradorFilter = cobradorId == null ? '' : 'AND c.cobrador_id = ?';
    if (cobradorId != null) args.add(cobradorId);

    final rows = await db.rawQuery('''
      SELECT COALESCE(SUM(p.saldo), 0) AS total
      FROM ${DatabaseTables.prestamos} p
      INNER JOIN ${DatabaseTables.clientes} c ON c.id = p.cliente_id
      WHERE p.estado IN (?, ?) $cobradorFilter
      ''', args);

    return (rows.first['total'] as num).toDouble();
  }

  Future<int> _contarClientesAtrasados(Database db, int? cobradorId) async {
    final args = <Object?>[AppEstados.atrasado];
    final cobradorFilter = cobradorId == null ? '' : 'AND c.cobrador_id = ?';
    if (cobradorId != null) args.add(cobradorId);

    final rows = await db.rawQuery('''
      SELECT COUNT(DISTINCT c.id) AS total
      FROM ${DatabaseTables.clientes} c
      INNER JOIN ${DatabaseTables.prestamos} p ON p.cliente_id = c.id
      WHERE p.estado = ? $cobradorFilter
      ''', args);

    return (rows.first['total'] as int?) ?? 0;
  }

  Future<int> _contarCajasAbiertas(Database db, int? cobradorId) async {
    final where = StringBuffer('estado = ?');
    final args = <Object?>[CajaEstados.abierta];
    if (cobradorId != null) {
      where.write(' AND cobrador_id = ?');
      args.add(cobradorId);
    }

    final rows = await db.rawQuery('''
      SELECT COUNT(*) AS total
      FROM ${DatabaseTables.cajas}
      WHERE $where
      ''', args);

    return (rows.first['total'] as int?) ?? 0;
  }

  Future<double> _capitalDisponible(Database db) async {
    final rows = await db.rawQuery('''
      SELECT COALESCE(capital_disponible, 0) AS total
      FROM ${DatabaseTables.capitalGeneral}
      WHERE estado = 'activo'
      ORDER BY fecha_hora DESC
      LIMIT 1
      ''');

    if (rows.isEmpty) return 0;
    return (rows.first['total'] as num?)?.toDouble() ?? 0;
  }

  Future<int> _contarCobradoresActivos(Database db) async {
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM ${DatabaseTables.usuarios}
      WHERE rol = ? AND estado = ?
      ''',
      [AppRoles.cobrador, AppEstados.activo],
    );

    return (rows.first['total'] as int?) ?? 0;
  }

  DateTime _inicioDia(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _finDia(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
  }
}
