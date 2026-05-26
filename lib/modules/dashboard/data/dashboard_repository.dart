import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';
import '../../../core/services/online_id_mapper.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/session/session_manager.dart';

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
    if (_usaSupabase) return _obtenerResumenOnline(cobradorId: cobradorId);

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

  bool get _usaSupabase {
    return SupabaseService.isInitialized &&
        SessionManager.instance.perfilActual?.companyId != null;
  }

  Future<DashboardResumen> _obtenerResumenOnline({int? cobradorId}) async {
    final inicioDia = _inicioDia(DateTime.now());
    final finDia = _finDia(DateTime.now());
    final cobradorUuid = OnlineIdMapper.instance.uuidFor(cobradorId);

    final cobros = await SupabaseService.requireClient
        .from('cobros')
        .select('monto, cobrador_id, fecha_pago')
        .gte('fecha_pago', inicioDia.toIso8601String())
        .lte('fecha_pago', finDia.toIso8601String());
    final cobrosFiltrados = cobradorUuid == null
        ? cobros
        : cobros.where((row) => row['cobrador_id'] == cobradorUuid).toList();
    final totalCobradoHoy = cobrosFiltrados.fold<double>(
      0,
      (total, row) => total + ((row['monto'] as num?)?.toDouble() ?? 0),
    );

    final clientes = await SupabaseService.requireClient
        .from('clientes')
        .select('id, estado, cobrador_id');
    final clientesFiltrados = cobradorUuid == null
        ? clientes
        : clientes.where((row) => row['cobrador_id'] == cobradorUuid).toList();
    final clienteIds = clientesFiltrados.map((row) => row['id']).toSet();
    final clientesActivos = clientesFiltrados
        .where((row) => row['estado'] == AppEstados.activo)
        .length;

    final prestamos = await SupabaseService.requireClient
        .from('prestamos')
        .select('id, cliente_id, saldo, estado, fecha_inicio');
    final prestamosFiltrados = cobradorUuid == null
        ? prestamos
        : prestamos.where((row) => clienteIds.contains(row['cliente_id'])).toList();
    final prestamosActivos = prestamosFiltrados
        .where(
          (row) =>
              row['estado'] == AppEstados.activo ||
              row['estado'] == AppEstados.atrasado,
        )
        .length;
    final prestamosHoy = prestamosFiltrados.where((row) {
      final fecha = DateTime.tryParse(row['fecha_inicio'] as String? ?? '');
      if (fecha == null) return false;
      return !fecha.isBefore(inicioDia) && !fecha.isAfter(finDia);
    }).length;
    final saldoPendiente = prestamosFiltrados.fold<double>(
      0,
      (total, row) {
        final estado = row['estado'];
        if (estado != AppEstados.activo && estado != AppEstados.atrasado) {
          return total;
        }
        return total + ((row['saldo'] as num?)?.toDouble() ?? 0);
      },
    );
    final clientesAtrasados = prestamosFiltrados
        .where((row) => row['estado'] == AppEstados.atrasado)
        .map((row) => row['cliente_id'])
        .toSet()
        .length;

    final cajas = await SupabaseService.requireClient
        .from('cajas')
        .select('id, estado, cobrador_id');
    final cajasAbiertas = cajas.where((row) {
      if (row['estado'] != CajaEstados.abierta) return false;
      return cobradorUuid == null || row['cobrador_id'] == cobradorUuid;
    }).length;

    final cobradores = await SupabaseService.requireClient
        .from('perfiles')
        .select('id, rol, estado')
        .eq('rol', AppRoles.cobrador)
        .eq('estado', AppEstados.activo);

    return DashboardResumen(
      totalCobradoHoy: totalCobradoHoy,
      prestamosHoy: prestamosHoy,
      clientesActivos: clientesActivos,
      prestamosActivos: prestamosActivos,
      cobrosPendientes: prestamosActivos,
      clientesAtrasados: clientesAtrasados,
      saldoPendiente: saldoPendiente,
      capitalDisponible: 0.0,
      cajasAbiertas: cajasAbiertas,
      cobradoresActivos: cobradores.length,
    );
  }
}
