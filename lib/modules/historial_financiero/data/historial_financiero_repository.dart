import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';
import '../../../core/session/session_manager.dart';
import '../../clientes/models/cliente_model.dart';
import '../../prestamos/models/prestamo_model.dart';

class ClienteHistorialResumen {
  const ClienteHistorialResumen({
    required this.cliente,
    required this.cobradorNombre,
    required this.prestamosTotal,
    required this.prestamosActivos,
    required this.prestamosAtrasados,
    required this.saldoPendiente,
    required this.totalPagado,
  });

  final ClienteModel cliente;
  final String cobradorNombre;
  final int prestamosTotal;
  final int prestamosActivos;
  final int prestamosAtrasados;
  final double saldoPendiente;
  final double totalPagado;
}

class HistorialFinancieroDetalle {
  const HistorialFinancieroDetalle({
    required this.resumen,
    required this.prestamos,
    required this.movimientos,
  });

  final ClienteHistorialResumen resumen;
  final List<PrestamoModel> prestamos;
  final List<HistorialMovimiento> movimientos;

  double get totalPrestado =>
      prestamos.fold(0, (total, item) => total + item.monto);

  double get saldoPendiente => resumen.saldoPendiente;
}

class HistorialMovimiento {
  const HistorialMovimiento({
    required this.tipo,
    required this.fecha,
    required this.titulo,
    required this.descripcion,
    required this.prestamoId,
    required this.monto,
    this.saldoAnterior,
    this.saldoActual,
    this.cobradorNombre,
    this.rutaNombre,
    this.observacion,
  });

  final String tipo;
  final DateTime fecha;
  final String titulo;
  final String descripcion;
  final int? prestamoId;
  final double monto;
  final double? saldoAnterior;
  final double? saldoActual;
  final String? cobradorNombre;
  final String? rutaNombre;
  final String? observacion;

  bool get esPago => tipo == 'pago';
  bool get esPrestamo => tipo == 'prestamo';
}

class HistorialFinancieroRepository {
  const HistorialFinancieroRepository();

  Future<List<ClienteHistorialResumen>> buscarClientes(String query) async {
    final db = await DatabaseHelper.instance.database;
    final usuario = SessionManager.instance.usuarioActual;
    final scopeCobrador = usuario?.esCobrador == true ? usuario?.id : null;
    final filtro = query.trim().toLowerCase();
    final prestamoId = int.tryParse(filtro);
    final args = <Object?>[
      AppEstados.activo,
      AppEstados.atrasado,
      AppEstados.atrasado,
      AppRoles.cobrador,
      filtro,
      '%$filtro%',
      '%$filtro%',
      '%$filtro%',
      '%$filtro%',
      prestamoId,
      prestamoId,
      scopeCobrador,
      scopeCobrador,
    ];

    final rows = await db.rawQuery('''
      SELECT
        c.*,
        COALESCE(u.nombre, 'Sin asignar') AS cobrador_nombre,
        COUNT(DISTINCT p.id) AS prestamos_total,
        COUNT(DISTINCT CASE WHEN p.estado IN (?, ?) THEN p.id END)
          AS prestamos_activos,
        COUNT(DISTINCT CASE WHEN p.estado = ? THEN p.id END)
          AS prestamos_atrasados,
        COALESCE(SUM(CASE WHEN p.estado IN ('activo', 'atrasado')
          THEN p.saldo ELSE 0 END), 0) AS saldo_pendiente,
        COALESCE((
          SELECT SUM(co.monto)
          FROM ${DatabaseTables.cobros} co
          INNER JOIN ${DatabaseTables.prestamos} pc
            ON pc.id = co.prestamo_id
          WHERE pc.cliente_id = c.id
            AND co.estado = 'registrado'
        ), 0) AS total_pagado
      FROM ${DatabaseTables.clientes} c
      LEFT JOIN ${DatabaseTables.usuarios} u
        ON u.id = c.cobrador_id AND u.rol = ?
      LEFT JOIN ${DatabaseTables.prestamos} p ON p.cliente_id = c.id
      WHERE
        (? = ''
          OR lower(c.nombre) LIKE ?
          OR lower(COALESCE(c.cedula, '')) LIKE ?
          OR lower(COALESCE(c.telefono, '')) LIKE ?
          OR CAST(c.id AS TEXT) LIKE ?
          OR (? IS NOT NULL AND EXISTS (
            SELECT 1
            FROM ${DatabaseTables.prestamos} pb
            WHERE pb.cliente_id = c.id AND pb.id = ?
          ))
        )
        AND (? IS NULL OR c.cobrador_id = ?)
      GROUP BY c.id
      ORDER BY c.nombre ASC
      LIMIT 60
      ''', args);

    return rows.map(_resumenFromRow).toList();
  }

  Future<HistorialFinancieroDetalle?> detallePorCliente(int clienteId) async {
    final resumenes = await buscarClientes('$clienteId');
    ClienteHistorialResumen? resumen;
    for (final item in resumenes) {
      if (item.cliente.id == clienteId) {
        resumen = item;
        break;
      }
    }
    if (resumen == null) return null;

    final db = await DatabaseHelper.instance.database;
    final prestamosRows = await db.query(
      DatabaseTables.prestamos,
      where: 'cliente_id = ?',
      whereArgs: [clienteId],
      orderBy: 'fecha_inicio DESC',
    );
    final prestamos = prestamosRows.map(PrestamoModel.fromMap).toList();
    final movimientos = <HistorialMovimiento>[];

    for (final prestamo in prestamos) {
      movimientos.add(
        HistorialMovimiento(
          tipo: 'prestamo',
          fecha: prestamo.fechaInicio,
          titulo: 'Prestamo #${prestamo.id ?? '-'} creado',
          descripcion:
              'Monto ${prestamo.monto} - total ${prestamo.totalPagar} - cuota ${prestamo.cuotaDiaria}',
          prestamoId: prestamo.id,
          monto: prestamo.monto,
          saldoActual: prestamo.totalPagar,
          observacion: 'Estado actual: ${prestamo.estado}',
        ),
      );
    }

    movimientos.addAll(await _movimientosCobros(clienteId));
    movimientos.addAll(await _movimientosRuta(clienteId));
    movimientos.sort((a, b) => b.fecha.compareTo(a.fecha));

    return HistorialFinancieroDetalle(
      resumen: resumen,
      prestamos: prestamos,
      movimientos: movimientos,
    );
  }

  Future<HistorialFinancieroDetalle?> detallePorPrestamo(int prestamoId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      DatabaseTables.prestamos,
      columns: ['cliente_id'],
      where: 'id = ?',
      whereArgs: [prestamoId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return detallePorCliente(rows.first['cliente_id'] as int);
  }

  Future<List<HistorialMovimiento>> _movimientosCobros(int clienteId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        co.*,
        u.nombre AS cobrador_nombre
      FROM ${DatabaseTables.cobros} co
      INNER JOIN ${DatabaseTables.prestamos} p ON p.id = co.prestamo_id
      LEFT JOIN ${DatabaseTables.usuarios} u ON u.id = co.cobrador_id
      WHERE p.cliente_id = ?
      ORDER BY co.fecha_pago DESC
      ''',
      [clienteId],
    );

    return rows.map((row) {
      final monto = (row['monto'] as num).toDouble();
      final esVisita = monto == 0;
      return HistorialMovimiento(
        tipo: esVisita ? 'visita' : 'pago',
        fecha: DateTime.parse(row['fecha_pago'] as String),
        titulo: esVisita ? 'Visita sin pago' : 'Pago registrado',
        descripcion: esVisita
            ? 'Visita registrada sin recaudo'
            : 'Pago aplicado al prestamo #${row['prestamo_id']}',
        prestamoId: row['prestamo_id'] as int?,
        monto: monto,
        saldoAnterior: (row['saldo_anterior'] as num?)?.toDouble(),
        saldoActual: (row['saldo_actual'] as num?)?.toDouble(),
        cobradorNombre: row['cobrador_nombre'] as String?,
        observacion: row['observacion'] as String?,
      );
    }).toList();
  }

  Future<List<HistorialMovimiento>> _movimientosRuta(int clienteId) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        rv.*,
        r.nombre AS ruta_nombre,
        u.nombre AS cobrador_nombre
      FROM ${DatabaseTables.rutaVisitas} rv
      INNER JOIN ${DatabaseTables.rutas} r ON r.id = rv.ruta_id
      LEFT JOIN ${DatabaseTables.usuarios} u ON u.id = rv.cobrador_id
      WHERE rv.cliente_id = ?
        AND rv.cobro_id IS NULL
      ORDER BY rv.fecha_hora DESC
      ''',
      [clienteId],
    );

    return rows.map((row) {
      final estado = row['estado_visita'] as String;
      return HistorialMovimiento(
        tipo: 'ruta',
        fecha: DateTime.parse(row['fecha_hora'] as String),
        titulo: _estadoRutaLabel(estado),
        descripcion: 'Resultado de visita en ruta',
        prestamoId: row['prestamo_id'] as int?,
        monto: (row['monto_cobrado'] as num?)?.toDouble() ?? 0,
        cobradorNombre: row['cobrador_nombre'] as String?,
        rutaNombre: row['ruta_nombre'] as String?,
        observacion: row['observacion'] as String?,
      );
    }).toList();
  }

  ClienteHistorialResumen _resumenFromRow(Map<String, Object?> row) {
    return ClienteHistorialResumen(
      cliente: ClienteModel.fromMap(row),
      cobradorNombre: row['cobrador_nombre'] as String? ?? 'Sin asignar',
      prestamosTotal: (row['prestamos_total'] as int?) ?? 0,
      prestamosActivos: (row['prestamos_activos'] as int?) ?? 0,
      prestamosAtrasados: (row['prestamos_atrasados'] as int?) ?? 0,
      saldoPendiente: (row['saldo_pendiente'] as num?)?.toDouble() ?? 0,
      totalPagado: (row['total_pagado'] as num?)?.toDouble() ?? 0,
    );
  }

  String _estadoRutaLabel(String estado) {
    return switch (estado) {
      RutaVisitaEstados.pago => 'Pago en ruta',
      RutaVisitaEstados.noEncontrado => 'Cliente no encontrado',
      RutaVisitaEstados.negocioCerrado => 'Negocio cerrado',
      RutaVisitaEstados.prometePagar => 'Promesa de pago',
      RutaVisitaEstados.noQuisoPagar => 'No quiso pagar',
      _ => 'Visita pendiente',
    };
  }
}
