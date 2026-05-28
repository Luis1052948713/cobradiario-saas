import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';
import '../../../core/services/online_id_mapper.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/session/session_manager.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../auditoria/data/auditoria_repository.dart';
import '../../notificaciones/data/notificacion_repository.dart';
import '../../usuarios/models/usuario_model.dart';

class CajaResumenDiario {
  const CajaResumenDiario({
    this.cajaId,
    required this.cobradorId,
    required this.nombre,
    required this.estadoCaja,
    required this.saldoInicial,
    required this.saldoDisponible,
    required this.totalPrestado,
    required this.totalRecaudado,
    required this.gastos,
    required this.cantidadPrestamos,
    required this.cantidadCobros,
    required this.clientesVisitados,
    required this.cierreRealizado,
    required this.cierrePendiente,
    this.horaApertura,
    this.cierreEstado,
  });

  final int? cajaId;
  final int cobradorId;
  final String nombre;
  final String estadoCaja;
  final double saldoInicial;
  final double saldoDisponible;
  final double totalPrestado;
  final double totalRecaudado;
  final double gastos;
  final int cantidadPrestamos;
  final int cantidadCobros;
  final int clientesVisitados;
  final bool cierreRealizado;
  final bool cierrePendiente;
  final String? horaApertura;
  final String? cierreEstado;

  bool get cajaAbierta => estadoCaja == CajaEstados.abierta;
}

class CapitalResumen {
  const CapitalResumen({
    required this.capitalId,
    required this.capitalInicial,
    required this.capitalDisponible,
    required this.saldoOperativoCobradores,
    required this.capitalPrestado,
    required this.dineroEnCalle,
    required this.dineroRecaudado,
    required this.ganancias,
    required this.gastos,
    required this.saldoDistribuidoHoy,
    required this.totalPrestadoHoy,
    required this.totalRecaudadoHoy,
    required this.gastosHoy,
  });

  final int? capitalId;
  final double capitalInicial;
  final double capitalDisponible;
  final double saldoOperativoCobradores;
  final double capitalPrestado;
  final double dineroEnCalle;
  final double dineroRecaudado;
  final double ganancias;
  final double gastos;
  final double saldoDistribuidoHoy;
  final double totalPrestadoHoy;
  final double totalRecaudadoHoy;
  final double gastosHoy;

  bool get registrado => capitalId != null;

  double get capitalFinal =>
      capitalDisponible + saldoOperativoCobradores + dineroEnCalle;
}

class ControlFinancieroRepository {
  const ControlFinancieroRepository({
    this.auditoriaRepository = const AuditoriaRepository(),
    this.notificacionRepository = const NotificacionRepository(),
  });

  final AuditoriaRepository auditoriaRepository;
  final NotificacionRepository notificacionRepository;

  Future<Database> get _db => DatabaseHelper.instance.database;

  Future<double> saldoDisponible(int cobradorId) async {
    if (_usaSupabase) {
      final uuid = OnlineIdMapper.instance.uuidFor(cobradorId);
      if (uuid == null) return 0;
      final row = await SupabaseService.requireClient
          .from('perfiles')
          .select('saldo_disponible')
          .eq('id', uuid)
          .maybeSingle();
      return (row?['saldo_disponible'] as num?)?.toDouble() ?? 0;
    }

    final db = await _db;
    final rows = await db.query(
      DatabaseTables.usuarios,
      columns: ['saldo_disponible'],
      where: 'id = ?',
      whereArgs: [cobradorId],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.first['saldo_disponible'] as num?)?.toDouble() ?? 0;
  }

  Future<CapitalResumen> resumenCapital() async {
    if (_usaSupabase) return _capitalResumenOnline();

    final db = await _db;
    final capital = await _capitalActivoEn(db);
    final capitalId = capital?['id'] as int?;
    final capitalInicial = (capital?['monto_inicial'] as num?)?.toDouble() ?? 0;
    final capitalDisponible =
        (capital?['capital_disponible'] as num?)?.toDouble() ?? 0;
    final hoy = _dateKey(DateTime.now());

    final saldoCobradores = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(saldo_disponible), 0) AS total
      FROM ${DatabaseTables.usuarios}
      WHERE rol = ?
      ''',
      [AppRoles.cobrador],
    );
    final cartera = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(monto), 0) AS capital_prestado,
        COALESCE(SUM(saldo), 0) AS dinero_en_calle
      FROM ${DatabaseTables.prestamos}
      WHERE estado IN (?, ?)
      ''',
      [AppEstados.activo, AppEstados.atrasado],
    );
    final cobros = await db.rawQuery('''
      SELECT COALESCE(SUM(monto), 0) AS total
      FROM ${DatabaseTables.cobros}
      WHERE estado = 'registrado'
      ''');
    final ganancias = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(total_pagar - monto), 0) AS total
      FROM ${DatabaseTables.prestamos}
      WHERE estado = ?
      ''',
      [AppEstados.pagado],
    );
    final gastos = await db.rawQuery('''
      SELECT COALESCE(SUM(valor), 0) AS total
      FROM ${DatabaseTables.gastos}
      ''');
    final asignacionesHoy = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(monto), 0) AS total
      FROM ${DatabaseTables.asignacionesSaldo}
      WHERE substr(fecha_hora, 1, 10) = ?
      ''',
      [hoy],
    );
    final movimientosHoy = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN tipo = ? THEN monto ELSE 0 END), 0) AS prestado,
        COALESCE(SUM(CASE WHEN tipo = ? THEN monto ELSE 0 END), 0) AS recaudado,
        COALESCE(SUM(CASE WHEN tipo = ? THEN monto ELSE 0 END), 0) AS gastos
      FROM ${DatabaseTables.movimientosFinancieros}
      WHERE substr(fecha_hora, 1, 10) = ?
      ''',
      [
        MovimientoFinancieroTipos.prestamo,
        MovimientoFinancieroTipos.cobro,
        MovimientoFinancieroTipos.gasto,
        hoy,
      ],
    );

    return CapitalResumen(
      capitalId: capitalId,
      capitalInicial: capitalInicial,
      capitalDisponible: capitalDisponible,
      saldoOperativoCobradores: _toDouble(saldoCobradores.first['total']),
      capitalPrestado: _toDouble(cartera.first['capital_prestado']),
      dineroEnCalle: _toDouble(cartera.first['dinero_en_calle']),
      dineroRecaudado: _toDouble(cobros.first['total']),
      ganancias: _toDouble(ganancias.first['total']),
      gastos: _toDouble(gastos.first['total']),
      saldoDistribuidoHoy: _toDouble(asignacionesHoy.first['total']),
      totalPrestadoHoy: _toDouble(movimientosHoy.first['prestado']),
      totalRecaudadoHoy: _toDouble(movimientosHoy.first['recaudado']),
      gastosHoy: _toDouble(movimientosHoy.first['gastos']),
    );
  }

  Future<List<Map<String, Object?>>> movimientosCapital() async {
    if (_usaSupabase) {
      final rows = await SupabaseService.requireClient
          .from('movimientos_capital')
          .select()
          .order('created_at', ascending: false)
          .limit(100);
      final result = <Map<String, Object?>>[];
      for (final row in rows) {
        final usuarioId = row['usuario_id'] == null
            ? null
            : OnlineIdMapper.instance.localIdFor(row['usuario_id'] as String);
        result.add({
          'id': OnlineIdMapper.instance.localIdFor(row['id'] as String),
          'capital_id': row['capital_id'] == null
              ? null
              : OnlineIdMapper.instance.localIdFor(row['capital_id'] as String),
          'usuario_id': usuarioId,
          'usuario_nombre': usuarioId == null
              ? null
              : await _nombreUsuario(usuarioId),
          'tipo': row['tipo'],
          'monto': row['monto'],
          'saldo_antes': row['saldo_antes'],
          'saldo_despues': row['saldo_despues'],
          'observacion': row['observacion'],
          'fecha_hora': row['created_at'],
        });
      }
      return result;
    }

    final db = await _db;
    return db.rawQuery('''
      SELECT m.*, u.nombre AS usuario_nombre
      FROM ${DatabaseTables.movimientosCapital} m
      INNER JOIN ${DatabaseTables.usuarios} u ON u.id = m.usuario_id
      ORDER BY m.fecha_hora DESC
      LIMIT 100
      ''');
  }

  Future<void> registrarCapitalInicial({
    required double monto,
    String? observacion,
  }) async {
    if (_usaSupabase) {
      await _registrarCapitalInicialOnline(
        monto: monto,
        observacion: observacion,
      );
      return;
    }

    final admin = _adminActual();
    if (monto <= 0) {
      throw StateError('El capital inicial debe ser mayor a cero.');
    }
    final db = await _db;
    final now = DateTime.now();
    final capitalId = await db.transaction((txn) async {
      final activo = await _capitalActivoEn(txn);
      if (activo != null) {
        throw StateError('Ya existe un capital activo registrado.');
      }
      final id = await txn.insert(DatabaseTables.capitalGeneral, {
        'monto_inicial': monto,
        'capital_disponible': monto,
        'observacion': observacion,
        'usuario_id': admin.id,
        'estado': 'activo',
        'fecha_hora': now.toIso8601String(),
      });
      await txn.insert(DatabaseTables.movimientosCapital, {
        'capital_id': id,
        'usuario_id': admin.id,
        'tipo': CapitalMovimientoTipos.capitalInicial,
        'monto': monto,
        'saldo_antes': 0,
        'saldo_despues': monto,
        'observacion': observacion ?? 'Capital inicial',
        'referencia_tabla': DatabaseTables.capitalGeneral,
        'referencia_id': id,
        'fecha_hora': now.toIso8601String(),
      });
      return id;
    });
    await auditoriaRepository.registrar(
      accion: 'registrar_capital_inicial',
      modulo: 'capital',
      referenciaId: capitalId,
      descripcion: 'Capital inicial monto=$monto',
    );
  }

  Future<void> registrarIngresoCapital({
    required double monto,
    String? observacion,
  }) async {
    if (_usaSupabase) {
      await _ajustarCapitalOnline(
        tipo: CapitalMovimientoTipos.ingresoAdicional,
        monto: monto,
        delta: monto,
        observacion: observacion ?? 'Ingreso adicional',
      );
      await auditoriaRepository.registrar(
        accion: 'ingreso_capital',
        modulo: 'capital',
        descripcion: 'Ingreso capital monto=$monto',
      );
      return;
    }

    final admin = _adminActual();
    if (monto <= 0) throw StateError('El ingreso debe ser mayor a cero.');
    final db = await _db;
    await db.transaction((txn) async {
      await _ajustarCapital(
        txn: txn,
        usuarioId: admin.id!,
        tipo: CapitalMovimientoTipos.ingresoAdicional,
        monto: monto,
        delta: monto,
        observacion: observacion ?? 'Ingreso adicional',
      );
    });
    await auditoriaRepository.registrar(
      accion: 'ingreso_capital',
      modulo: 'capital',
      descripcion: 'Ingreso capital monto=$monto',
    );
  }

  Future<void> registrarRetiroCapital({
    required double monto,
    String? observacion,
  }) async {
    if (_usaSupabase) {
      await _ajustarCapitalOnline(
        tipo: CapitalMovimientoTipos.retiroAdministrativo,
        monto: monto,
        delta: -monto,
        observacion: observacion ?? 'Retiro administrativo',
      );
      await auditoriaRepository.registrar(
        accion: 'retiro_capital',
        modulo: 'capital',
        descripcion: 'Retiro capital monto=$monto',
      );
      return;
    }

    final admin = _adminActual();
    if (monto <= 0) throw StateError('El retiro debe ser mayor a cero.');
    final db = await _db;
    await db.transaction((txn) async {
      await _ajustarCapital(
        txn: txn,
        usuarioId: admin.id!,
        tipo: CapitalMovimientoTipos.retiroAdministrativo,
        monto: monto,
        delta: -monto,
        observacion: observacion ?? 'Retiro administrativo',
      );
    });
    await auditoriaRepository.registrar(
      accion: 'retiro_capital',
      modulo: 'capital',
      descripcion: 'Retiro capital monto=$monto',
    );
  }

  Future<void> cerrarFinancieroDiario({String? observacion}) async {
    if (_usaSupabase) {
      await _cerrarFinancieroDiarioOnline(observacion: observacion);
      return;
    }

    final admin = _adminActual();
    final resumen = await resumenCapital();
    if (!resumen.registrado) {
      throw StateError('Registra el capital inicial antes de cerrar.');
    }
    final db = await _db;
    final now = DateTime.now();
    final fecha = _dateKey(now);
    final cierreId = await db.transaction((txn) async {
      final id = await txn.insert(
        DatabaseTables.cierresFinancieros,
        {
          'capital_id': resumen.capitalId,
          'admin_id': admin.id,
          'fecha': fecha,
          'capital_inicial': resumen.capitalInicial,
          'saldo_distribuido': resumen.saldoDistribuidoHoy,
          'total_prestado': resumen.totalPrestadoHoy,
          'total_recaudado': resumen.totalRecaudadoHoy,
          'gastos': resumen.gastosHoy,
          'ganancias': resumen.ganancias,
          'capital_final': resumen.capitalFinal,
          'observacion': observacion,
          'fecha_hora': now.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      await txn.insert(DatabaseTables.movimientosCapital, {
        'capital_id': resumen.capitalId,
        'usuario_id': admin.id,
        'tipo': CapitalMovimientoTipos.cierreFinanciero,
        'monto': resumen.capitalFinal,
        'saldo_antes': resumen.capitalDisponible,
        'saldo_despues': resumen.capitalDisponible,
        'observacion': observacion ?? 'Cierre financiero diario',
        'referencia_tabla': DatabaseTables.cierresFinancieros,
        'referencia_id': id,
        'fecha_hora': now.toIso8601String(),
      });
      return id;
    });
    await auditoriaRepository.registrar(
      accion: 'cierre_financiero',
      modulo: 'capital',
      referenciaId: cierreId,
      descripcion: 'Cierre financiero fecha=$fecha',
    );
  }

  Future<void> validarCobradorPuedeOperar(
    int cobradorId, {
    bool localOnly = false,
  }) async {
    if (_usaSupabase && !localOnly) {
      final cajaAbierta = await cajaAbiertaDeCobrador(cobradorId);
      if (cajaAbierta == null) {
        throw StateError('Debes tener una caja abierta para operar.');
      }
      if (cajaAbierta['estado'] == CajaEstados.bloqueada) {
        throw StateError('La caja esta bloqueada. Contacta al administrador.');
      }
      if (cajaAbierta['estado'] != CajaEstados.abierta) {
        throw StateError('La caja no esta abierta para operar.');
      }
      return;
    }

    final db = await _db;
    final hoy = _dateKey(DateTime.now());
    final cajas = await db.query(
      DatabaseTables.cajas,
      where: 'cobrador_id = ? AND estado = ?',
      whereArgs: [cobradorId, CajaEstados.abierta],
      orderBy: 'fecha_creacion DESC',
      limit: 1,
    );
    final cajaAbierta = cajas.isEmpty ? null : cajas.first;
    if (cajaAbierta == null) {
      if (_usaSupabase && localOnly) return;
      throw StateError('Debes tener una caja abierta para operar.');
    }
    if (cajaAbierta['estado'] == CajaEstados.bloqueada) {
      throw StateError('La caja esta bloqueada. Contacta al administrador.');
    }

    final rows = await db.rawQuery(
      '''
      SELECT DISTINCT substr(fecha_hora, 1, 10) AS fecha
      FROM ${DatabaseTables.movimientosFinancieros}
      WHERE usuario_id = ?
        AND substr(fecha_hora, 1, 10) < ?
        AND substr(fecha_hora, 1, 10) NOT IN (
          SELECT fecha
          FROM ${DatabaseTables.cierresCaja}
          WHERE cobrador_id = ?
        )
      LIMIT 1
      ''',
      [cobradorId, hoy, cobradorId],
    );
    if (rows.isNotEmpty) {
      throw StateError(
        'Tienes un cierre de caja pendiente de un dia anterior.',
      );
    }
  }

  Future<Map<String, Object?>?> cajaAbiertaDeCobrador(int cobradorId) async {
    if (_usaSupabase) {
      final cobradorUuid = OnlineIdMapper.instance.uuidFor(cobradorId);
      if (cobradorUuid == null) return null;
      final row = await SupabaseService.requireClient
          .from('cajas')
          .select()
          .eq('cobrador_id', cobradorUuid)
          .inFilter('estado', [
            CajaEstados.abierta,
            CajaEstados.pendienteRevision,
            CajaEstados.bloqueada,
          ])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row == null) return null;
      return _cajaOnlineToMap(row);
    }

    final db = await _db;
    final rows = await db.query(
      DatabaseTables.cajas,
      where: 'cobrador_id = ? AND estado = ?',
      whereArgs: [cobradorId, CajaEstados.abierta],
      orderBy: 'fecha_creacion DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> abrirCaja({
    required int cobradorId,
    required double saldoInicial,
    String? observacion,
  }) async {
    if (_usaSupabase) {
      return _abrirCajaOnline(
        cobradorId: cobradorId,
        saldoInicial: saldoInicial,
        observacion: observacion,
      );
    }
    final admin = SessionManager.instance.usuarioActual;
    if (admin?.esAdministrador != true || admin?.id == null) {
      throw StateError('Solo el administrador puede abrir caja.');
    }
    final adminId = admin!.id!;
    if (saldoInicial < 0) {
      throw StateError('El saldo inicial no puede ser negativo.');
    }
    await _validarPuedeAbrirCaja(cobradorId);

    final db = await _db;
    final now = DateTime.now();
    final fecha = _dateKey(now);
    final cajaId = await db.transaction((txn) async {
      final id = await txn.insert(DatabaseTables.cajas, {
        'cobrador_id': cobradorId,
        'admin_id': adminId,
        'fecha': fecha,
        'hora_apertura': _timeKey(now),
        'saldo_inicial': saldoInicial,
        'saldo_actual': saldoInicial,
        'observacion_apertura': observacion,
        'estado': CajaEstados.abierta,
        'fecha_creacion': now.toIso8601String(),
      });
      if (saldoInicial > 0) {
        await _registrarAsignacionDesdeCapital(
          txn: txn,
          cobradorId: cobradorId,
          adminId: adminId,
          monto: saldoInicial,
          observacion: observacion ?? 'Apertura de caja',
          referenciaTabla: DatabaseTables.cajas,
          referenciaId: id,
        );
      }
      await txn.update(
        DatabaseTables.usuarios,
        {'saldo_disponible': saldoInicial},
        where: 'id = ?',
        whereArgs: [cobradorId],
      );
      await txn.insert(DatabaseTables.movimientosFinancieros, {
        'usuario_id': cobradorId,
        'tipo': MovimientoFinancieroTipos.asignacionSaldo,
        'monto': saldoInicial,
        'saldo_antes': 0,
        'saldo_despues': saldoInicial,
        'observacion': observacion ?? 'Apertura de caja',
        'referencia_tabla': DatabaseTables.cajas,
        'referencia_id': id,
        'fecha_hora': now.toIso8601String(),
      });
      await txn.insert(DatabaseTables.movimientosCaja, {
        'caja_id': id,
        'usuario_id': cobradorId,
        'tipo': MovimientoFinancieroTipos.asignacionSaldo,
        'monto': saldoInicial,
        'saldo_antes': 0,
        'saldo_despues': saldoInicial,
        'observacion': observacion ?? 'Apertura de caja',
        'referencia_tabla': DatabaseTables.cajas,
        'referencia_id': id,
        'fecha_hora': now.toIso8601String(),
      });
      return id;
    });
    await auditoriaRepository.registrar(
      accion: 'abrir_caja',
      modulo: 'caja',
      referenciaId: cajaId,
      descripcion: 'Caja abierta cobrador=$cobradorId saldo=$saldoInicial',
    );
    await notificacionRepository.crear(
      usuarioId: cobradorId,
      titulo: 'Caja abierta',
      mensaje: 'Tu caja fue abierta con saldo ${_money(saldoInicial)}.',
      tipo: NotificacionTipos.exito,
      modulo: 'caja',
      referenciaId: cajaId,
    );
    return cajaId;
  }

  Future<void> _validarPuedeAbrirCaja(int cobradorId) async {
    if (_usaSupabase) {
      await _validarPuedeAbrirCajaOnline(cobradorId);
      return;
    }

    final db = await _db;
    final abierta = await db.query(
      DatabaseTables.cajas,
      where: 'cobrador_id = ? AND estado IN (?, ?, ?)',
      whereArgs: [
        cobradorId,
        CajaEstados.abierta,
        CajaEstados.pendienteRevision,
        CajaEstados.bloqueada,
      ],
      limit: 1,
    );
    if (abierta.isNotEmpty) {
      throw StateError('El cobrador tiene una caja abierta o pendiente.');
    }
    final cierrePendiente = await db.query(
      DatabaseTables.cierresCaja,
      where: 'cobrador_id = ? AND estado = ?',
      whereArgs: [cobradorId, CierreCajaEstados.pendienteRevision],
      limit: 1,
    );
    if (cierrePendiente.isNotEmpty) {
      throw StateError('Existe un cierre pendiente de revision.');
    }
    final diferencia = await db.query(
      DatabaseTables.cierresCaja,
      where: 'cobrador_id = ? AND diferencia != 0 AND estado != ?',
      whereArgs: [cobradorId, CierreCajaEstados.aprobado],
      limit: 1,
    );
    if (diferencia.isNotEmpty) {
      throw StateError('Existe una diferencia de caja sin resolver.');
    }
  }

  Future<void> descontarPorPrestamo({
    required Transaction txn,
    required int cobradorId,
    required int clienteId,
    required double monto,
    required int prestamoId,
  }) async {
    await _ajustarSaldo(
      txn: txn,
      cobradorId: cobradorId,
      clienteId: clienteId,
      montoMovimiento: monto,
      deltaSaldo: -monto,
      tipo: MovimientoFinancieroTipos.prestamo,
      observacion: 'Prestamo registrado',
      referenciaTabla: DatabaseTables.prestamos,
      referenciaId: prestamoId,
      validarSaldo: true,
    );
  }

  Future<void> aumentarPorCobro({
    required Transaction txn,
    required int cobradorId,
    required int clienteId,
    required double monto,
    required int cobroId,
  }) async {
    if (monto <= 0) return;
    await _ajustarSaldo(
      txn: txn,
      cobradorId: cobradorId,
      clienteId: clienteId,
      montoMovimiento: monto,
      deltaSaldo: monto,
      tipo: MovimientoFinancieroTipos.cobro,
      observacion: 'Cobro registrado',
      referenciaTabla: DatabaseTables.cobros,
      referenciaId: cobroId,
    );
  }

  Future<void> descontarPrestamoOnline({
    required int cobradorId,
    required double monto,
  }) async {
    if (!_usaSupabase || monto <= 0) return;
    await validarCobradorPuedeOperar(cobradorId);
    final cobradorUuid = _uuidRequerido(cobradorId, 'Cobrador');
    final caja = await _cajaAbiertaOnline(cobradorUuid);
    final cajaUuid = _rowIdRequerido(caja, 'No hay caja abierta para operar.');
    final saldoDespues = await _saldoDisponibleOnline(cobradorUuid) - monto;
    if (saldoDespues < 0) {
      throw StateError(
        'No posee fondos disponibles para realizar la operacion.',
      );
    }
    await _actualizarSaldoOnline(
      cobradorUuid: cobradorUuid,
      cajaUuid: cajaUuid,
      saldo: saldoDespues,
    );
  }

  Future<void> aumentarCobroOnline({
    required int cobradorId,
    required double monto,
  }) async {
    if (!_usaSupabase || monto <= 0) return;
    await validarCobradorPuedeOperar(cobradorId);
    final cobradorUuid = _uuidRequerido(cobradorId, 'Cobrador');
    final caja = await _cajaAbiertaOnline(cobradorUuid);
    final cajaUuid = _rowIdRequerido(caja, 'No hay caja abierta para operar.');
    final saldoDespues = await _saldoDisponibleOnline(cobradorUuid) + monto;
    await _actualizarSaldoOnline(
      cobradorUuid: cobradorUuid,
      cajaUuid: cajaUuid,
      saldo: saldoDespues,
    );
  }

  Future<void> registrarGasto({
    required int cobradorId,
    required String tipo,
    required double valor,
    String? descripcion,
  }) async {
    if (_usaSupabase) {
      return _registrarGastoOnline(
        cobradorId: cobradorId,
        tipo: tipo,
        valor: valor,
        descripcion: descripcion,
      );
    }

    if (valor <= 0) throw StateError('El gasto debe ser mayor a cero.');
    await validarCobradorPuedeOperar(cobradorId);
    final db = await _db;
    await db.transaction((txn) async {
      final gastoId = await txn.insert(DatabaseTables.gastos, {
        'cobrador_id': cobradorId,
        'tipo': tipo,
        'valor': valor,
        'descripcion': descripcion,
        'fecha_hora': DateTime.now().toIso8601String(),
      });
      await _ajustarSaldo(
        txn: txn,
        cobradorId: cobradorId,
        montoMovimiento: valor,
        deltaSaldo: -valor,
        tipo: MovimientoFinancieroTipos.gasto,
        observacion: descripcion ?? 'Gasto operativo',
        referenciaTabla: DatabaseTables.gastos,
        referenciaId: gastoId,
        validarSaldo: true,
      );
    });
    await auditoriaRepository.registrar(
      accion: 'registrar_gasto',
      modulo: 'caja',
      descripcion: 'Gasto $tipo valor=$valor cobrador=$cobradorId',
    );
    final nombreCobrador = await _nombreUsuario(cobradorId);
    await notificacionRepository.crearParaAdmins(
      titulo: 'Gasto registrado',
      mensaje:
          '$nombreCobrador registro un gasto de ${_money(valor)} en $tipo.',
      tipo: NotificacionTipos.informativa,
      modulo: 'caja',
    );
  }

  Future<void> solicitarSaldo({
    required int cobradorId,
    required double monto,
    String? observacion,
  }) async {
    if (_usaSupabase) {
      return _solicitarSaldoOnline(
        cobradorId: cobradorId,
        monto: monto,
        observacion: observacion,
      );
    }

    if (monto <= 0) {
      throw StateError('El monto solicitado debe ser mayor a cero.');
    }
    final db = await _db;
    final id = await db.insert(DatabaseTables.solicitudesSaldo, {
      'cobrador_id': cobradorId,
      'monto_solicitado': monto,
      'observacion': observacion,
      'estado': SolicitudSaldoEstados.pendiente,
      'fecha_hora': DateTime.now().toIso8601String(),
    });
    await _registrarMovimientoSinSaldo(
      usuarioId: cobradorId,
      tipo: MovimientoFinancieroTipos.solicitudSaldo,
      monto: monto,
      observacion: observacion ?? 'Solicitud de saldo',
      referenciaTabla: DatabaseTables.solicitudesSaldo,
      referenciaId: id,
    );
    await auditoriaRepository.registrar(
      accion: 'solicitar_saldo',
      modulo: 'caja',
      referenciaId: id,
      descripcion: 'Solicitud de saldo cobrador=$cobradorId monto=$monto',
    );
    final nombreCobrador = await _nombreUsuario(cobradorId);
    await notificacionRepository.crearParaAdmins(
      titulo: 'Solicitud de saldo pendiente',
      mensaje: '$nombreCobrador solicita saldo por ${_money(monto)}.',
      tipo: NotificacionTipos.advertencia,
      modulo: 'caja',
      referenciaId: id,
    );
  }

  Future<void> responderSolicitud({
    required int solicitudId,
    required bool aprobar,
    required double montoAprobado,
    String? observacionAdmin,
  }) async {
    if (_usaSupabase) {
      return _responderSolicitudOnline(
        solicitudId: solicitudId,
        aprobar: aprobar,
        montoAprobado: montoAprobado,
        observacionAdmin: observacionAdmin,
      );
    }

    final db = await _db;
    final admin = SessionManager.instance.usuarioActual;
    if (admin?.esAdministrador != true || admin?.id == null) {
      throw StateError('Solo el administrador puede responder solicitudes.');
    }
    final adminId = admin!.id!;

    await db.transaction((txn) async {
      final rows = await txn.query(
        DatabaseTables.solicitudesSaldo,
        where: 'id = ? AND estado = ?',
        whereArgs: [solicitudId, SolicitudSaldoEstados.pendiente],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('La solicitud ya fue respondida.');

      final solicitud = rows.first;
      final cobradorId = solicitud['cobrador_id'] as int;
      final monto = aprobar ? montoAprobado : 0.0;
      if (aprobar && monto <= 0) {
        throw StateError('Ingresa un monto aprobado mayor a cero.');
      }

      await txn.update(
        DatabaseTables.solicitudesSaldo,
        {
          'estado': aprobar
              ? SolicitudSaldoEstados.aprobada
              : SolicitudSaldoEstados.rechazada,
          'monto_aprobado': monto,
          'observacion_admin': observacionAdmin,
          'fecha_respuesta': DateTime.now().toIso8601String(),
          'admin_id': adminId,
        },
        where: 'id = ?',
        whereArgs: [solicitudId],
      );

      if (aprobar) {
        await _registrarAsignacionDesdeCapital(
          txn: txn,
          cobradorId: cobradorId,
          adminId: adminId,
          monto: monto,
          observacion: observacionAdmin ?? 'Saldo aprobado por admin',
          referenciaTabla: DatabaseTables.solicitudesSaldo,
          referenciaId: solicitudId,
        );
        await _ajustarSaldo(
          txn: txn,
          cobradorId: cobradorId,
          montoMovimiento: monto,
          deltaSaldo: monto,
          tipo: MovimientoFinancieroTipos.asignacionSaldo,
          observacion: observacionAdmin ?? 'Saldo aprobado por admin',
          referenciaTabla: DatabaseTables.solicitudesSaldo,
          referenciaId: solicitudId,
        );
      }
    });
    await auditoriaRepository.registrar(
      accion: aprobar ? 'aprobar_saldo' : 'rechazar_saldo',
      modulo: 'caja',
      referenciaId: solicitudId,
      descripcion:
          'Solicitud saldo=$solicitudId aprobar=$aprobar monto=$montoAprobado',
    );
    final estado = aprobar ? 'aprobada' : 'rechazada';
    await notificacionRepository.crear(
      usuarioId: await _cobradorDeSolicitud(solicitudId),
      titulo: 'Solicitud de saldo $estado',
      mensaje: aprobar
          ? 'Tu solicitud fue aprobada por ${_money(montoAprobado)}.'
          : 'Tu solicitud de saldo fue rechazada.',
      tipo: aprobar ? NotificacionTipos.exito : NotificacionTipos.advertencia,
      modulo: 'caja',
      referenciaId: solicitudId,
    );
  }

  Future<void> asignarSaldo({
    required int cobradorId,
    required double monto,
    String? observacion,
  }) async {
    if (_usaSupabase) {
      return _asignarSaldoOnline(
        cobradorId: cobradorId,
        monto: monto,
        observacion: observacion,
      );
    }

    final usuario = SessionManager.instance.usuarioActual;
    if (usuario?.esAdministrador != true || usuario?.id == null) {
      throw StateError('Solo el administrador puede asignar saldo.');
    }
    if (monto <= 0) throw StateError('El monto debe ser mayor a cero.');
    final cajaAbierta = await cajaAbiertaDeCobrador(cobradorId);
    if (cajaAbierta == null) {
      await abrirCaja(
        cobradorId: cobradorId,
        saldoInicial: monto,
        observacion: observacion,
      );
      return;
    }
    final db = await _db;
    await db.transaction((txn) async {
      await _registrarAsignacionDesdeCapital(
        txn: txn,
        cobradorId: cobradorId,
        adminId: usuario!.id!,
        monto: monto,
        observacion: observacion ?? 'Saldo asignado por admin',
        referenciaTabla: DatabaseTables.usuarios,
        referenciaId: cobradorId,
      );
      await _ajustarSaldo(
        txn: txn,
        cobradorId: cobradorId,
        montoMovimiento: monto,
        deltaSaldo: monto,
        tipo: MovimientoFinancieroTipos.asignacionSaldo,
        observacion: observacion ?? 'Saldo asignado por admin',
        referenciaTabla: DatabaseTables.usuarios,
        referenciaId: cobradorId,
      );
    });
    await auditoriaRepository.registrar(
      accion: 'asignar_saldo',
      modulo: 'caja',
      referenciaId: cobradorId,
      descripcion: 'Saldo asignado cobrador=$cobradorId monto=$monto',
    );
    await notificacionRepository.crear(
      usuarioId: cobradorId,
      titulo: 'Saldo asignado',
      mensaje: 'El administrador asigno saldo por ${_money(monto)}.',
      tipo: NotificacionTipos.exito,
      modulo: 'caja',
      referenciaId: cobradorId,
    );
  }

  Future<void> cerrarCaja({
    required int cobradorId,
    required double dineroReportado,
    String? observacion,
  }) async {
    if (_usaSupabase) {
      return _cerrarCajaOnline(
        cobradorId: cobradorId,
        dineroReportado: dineroReportado,
        observacion: observacion,
      );
    }

    final db = await _db;
    final caja = await cajaAbiertaDeCobrador(cobradorId);
    if (caja == null) {
      throw StateError('No hay caja abierta para cerrar.');
    }
    final resumen = await resumenDiario(cobradorId);
    final now = DateTime.now();
    final fecha = caja['fecha'] as String? ?? _dateKey(now);
    final diferencia = dineroReportado - resumen.saldoDisponible;
    final cierreId = await db.transaction((txn) async {
      final id = await txn.insert(DatabaseTables.cierresCaja, {
        'caja_id': caja['id'],
        'cobrador_id': cobradorId,
        'fecha': fecha,
        'total_recaudado': resumen.totalRecaudado,
        'total_prestado': resumen.totalPrestado,
        'cantidad_cobros': resumen.cantidadCobros,
        'cantidad_prestamos': resumen.cantidadPrestamos,
        'gastos': resumen.gastos,
        'saldo_restante': resumen.saldoDisponible,
        'dinero_reportado': dineroReportado,
        'dinero_entregado': 0,
        'diferencia': diferencia,
        'observacion': observacion,
        'estado': CierreCajaEstados.pendienteRevision,
        'fecha_hora': now.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.update(
        DatabaseTables.cajas,
        {
          'estado': CajaEstados.pendienteRevision,
          'hora_cierre': _timeKey(now),
          'observacion_cierre': observacion,
          'cierre_id': id,
        },
        where: 'id = ?',
        whereArgs: [caja['id']],
      );
      return id;
    });
    await _registrarMovimientoSinSaldo(
      usuarioId: cobradorId,
      tipo: MovimientoFinancieroTipos.cierreCaja,
      monto: dineroReportado,
      observacion: 'Cierre caja diferencia=$diferencia ${observacion ?? ''}',
      referenciaTabla: DatabaseTables.cierresCaja,
      referenciaId: cierreId,
    );
    await auditoriaRepository.registrar(
      accion: 'cerrar_caja',
      modulo: 'caja',
      descripcion: 'Cierre caja cobrador=$cobradorId diferencia=$diferencia',
    );
    if (diferencia != 0) {
      final nombreCobrador = await _nombreUsuario(cobradorId);
      await auditoriaRepository.registrar(
        accion: 'diferencia_caja',
        modulo: 'caja',
        referenciaId: cierreId,
        descripcion: 'Diferencia caja cobrador=$cobradorId valor=$diferencia',
      );
      await notificacionRepository.crearParaAdmins(
        titulo: 'Diferencia en caja',
        mensaje:
            '$nombreCobrador cerro caja con diferencia de ${_money(diferencia)}.',
        tipo: NotificacionTipos.critica,
        modulo: 'caja',
        referenciaId: cierreId,
      );
    }
  }

  Future<void> registrarEntregaDinero({
    required int cierreId,
    required double montoEntregado,
    String? observacion,
  }) async {
    if (_usaSupabase) {
      return _registrarEntregaDineroOnline(
        cierreId: cierreId,
        montoEntregado: montoEntregado,
        observacion: observacion,
      );
    }

    final admin = SessionManager.instance.usuarioActual;
    if (admin?.esAdministrador != true || admin?.id == null) {
      throw StateError('Solo el administrador puede recibir dinero.');
    }
    if (montoEntregado < 0) {
      throw StateError('El monto entregado no puede ser negativo.');
    }
    final adminId = admin!.id!;
    final db = await _db;
    final cierres = await db.query(
      DatabaseTables.cierresCaja,
      where: 'id = ?',
      whereArgs: [cierreId],
      limit: 1,
    );
    if (cierres.isEmpty) throw StateError('El cierre no existe.');
    final cierre = cierres.first;
    if ([
      CierreCajaEstados.aprobado,
      CierreCajaEstados.rechazado,
    ].contains(cierre['estado'])) {
      throw StateError('Un cierre evaluado no puede modificarse.');
    }
    final cobradorId = cierre['cobrador_id'] as int;
    final entregadoAntes =
        (cierre['dinero_entregado'] as num?)?.toDouble() ?? 0;
    final deltaEntrega = montoEntregado - entregadoAntes;
    await db.transaction((txn) async {
      await txn.update(
        DatabaseTables.cierresCaja,
        {
          'dinero_entregado': montoEntregado,
          'admin_id': adminId,
          'observacion_admin': observacion,
        },
        where: 'id = ?',
        whereArgs: [cierreId],
      );
      if (deltaEntrega != 0) {
        await _registrarEntregaEnSaldo(
          txn: txn,
          cobradorId: cobradorId,
          adminId: adminId,
          cierreId: cierreId,
          cajaId: cierre['caja_id'] as int?,
          montoMovimiento: deltaEntrega.abs(),
          deltaEntrega: deltaEntrega,
          observacion: observacion ?? 'Entrega de dinero al administrador',
        );
        await _ajustarCapital(
          txn: txn,
          usuarioId: adminId,
          tipo: CapitalMovimientoTipos.entregaDinero,
          monto: deltaEntrega.abs(),
          delta: deltaEntrega,
          observacion: observacion ?? 'Entrega de dinero al administrador',
          referenciaTabla: DatabaseTables.cierresCaja,
          referenciaId: cierreId,
        );
      }
    });
    await auditoriaRepository.registrar(
      accion: 'entrega_dinero',
      modulo: 'caja',
      referenciaId: cierreId,
      descripcion: 'Entrega dinero cierre=$cierreId monto=$montoEntregado',
    );
  }

  Future<void> revisarCierre({
    required int cierreId,
    required String estado,
    String? observacionAdmin,
  }) async {
    if (_usaSupabase) {
      return _revisarCierreOnline(
        cierreId: cierreId,
        estado: estado,
        observacionAdmin: observacionAdmin,
      );
    }

    final admin = SessionManager.instance.usuarioActual;
    if (admin?.esAdministrador != true || admin?.id == null) {
      throw StateError('Solo el administrador puede revisar cierres.');
    }
    final adminId = admin!.id!;
    if (![
      CierreCajaEstados.aprobado,
      CierreCajaEstados.rechazado,
      CierreCajaEstados.pendienteRevision,
    ].contains(estado)) {
      throw StateError('Estado de cierre invalido.');
    }
    final db = await _db;
    final cierres = await db.query(
      DatabaseTables.cierresCaja,
      where: 'id = ?',
      whereArgs: [cierreId],
      limit: 1,
    );
    if (cierres.isEmpty) throw StateError('El cierre no existe.');
    final cierre = cierres.first;
    if ([
      CierreCajaEstados.aprobado,
      CierreCajaEstados.rechazado,
    ].contains(cierre['estado'])) {
      throw StateError('Un cierre evaluado no puede modificarse.');
    }
    final cajaId = cierre['caja_id'] as int?;
    await db.transaction((txn) async {
      await txn.update(
        DatabaseTables.cierresCaja,
        {
          'estado': estado,
          'observacion_admin': observacionAdmin,
          'admin_id': adminId,
          'fecha_revision': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [cierreId],
      );
      if (cajaId != null) {
        await txn.update(
          DatabaseTables.cajas,
          {
            'estado': estado == CierreCajaEstados.aprobado
                ? CajaEstados.cerrada
                : estado == CierreCajaEstados.rechazado
                ? CajaEstados.bloqueada
                : CajaEstados.pendienteRevision,
          },
          where: 'id = ?',
          whereArgs: [cajaId],
        );
      }
    });
    await auditoriaRepository.registrar(
      accion: estado == CierreCajaEstados.aprobado
          ? 'aprobar_cierre'
          : estado == CierreCajaEstados.rechazado
          ? 'rechazar_cierre'
          : 'solicitar_revision_cierre',
      modulo: 'caja',
      referenciaId: cierreId,
      descripcion: 'Revision cierre=$cierreId estado=$estado',
    );
    await notificacionRepository.crear(
      usuarioId: cierre['cobrador_id'] as int,
      titulo: estado == CierreCajaEstados.aprobado
          ? 'Cierre aprobado'
          : estado == CierreCajaEstados.rechazado
          ? 'Cierre rechazado'
          : 'Cierre en revision',
      mensaje: observacionAdmin ?? 'El administrador actualizo tu cierre.',
      tipo: estado == CierreCajaEstados.aprobado
          ? NotificacionTipos.exito
          : NotificacionTipos.advertencia,
      modulo: 'caja',
      referenciaId: cierreId,
    );
  }

  Future<List<CajaResumenDiario>> resumenesHoy() async {
    if (_usaSupabase) {
      final cobradores = await SupabaseService.requireClient
          .from('perfiles')
          .select('id, nombre, saldo_disponible')
          .eq('rol', AppRoles.cobrador)
          .eq('estado', AppEstados.activo);
      final result = <CajaResumenDiario>[];
      for (final row in cobradores) {
        final id = OnlineIdMapper.instance.localIdFor(row['id'] as String);
        result.add(await resumenDiario(id));
      }
      return result;
    }

    final db = await _db;
    final cobradores = await db.query(
      DatabaseTables.usuarios,
      where: 'rol = ?',
      whereArgs: [AppRoles.cobrador],
      orderBy: 'nombre ASC',
    );
    final result = <CajaResumenDiario>[];
    for (final cobrador in cobradores) {
      result.add(await resumenDiario(cobrador['id'] as int));
    }
    return result;
  }

  Future<CajaResumenDiario> resumenDiario(int cobradorId) async {
    if (_usaSupabase) {
      final cobradorUuid = OnlineIdMapper.instance.uuidFor(cobradorId);
      if (cobradorUuid == null) {
        return _emptyResumenDiario(cobradorId: cobradorId, nombre: 'Cobrador');
      }
      final usuario = await SupabaseService.requireClient
          .from('perfiles')
          .select('nombre, saldo_disponible')
          .eq('id', cobradorUuid)
          .maybeSingle();
      if (usuario == null) {
        return _emptyResumenDiario(cobradorId: cobradorId, nombre: 'Cobrador');
      }

      final caja = await SupabaseService.requireClient
          .from('cajas')
          .select()
          .eq('cobrador_id', cobradorUuid)
          .inFilter('estado', [
            CajaEstados.abierta,
            CajaEstados.pendienteRevision,
            CajaEstados.bloqueada,
          ])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final desde =
          (caja?['created_at'] as String?) ?? _startOfToday().toIso8601String();

      final clientes = await SupabaseService.requireClient
          .from('clientes')
          .select('id')
          .eq('cobrador_id', cobradorUuid);
      final clienteIds = clientes
          .map<String>((row) => row['id'] as String)
          .toList();

      var totalPrestado = 0.0;
      var cantidadPrestamos = 0;
      if (clienteIds.isNotEmpty) {
        final prestamos = await SupabaseService.requireClient
            .from('prestamos')
            .select('monto')
            .inFilter('cliente_id', clienteIds)
            .gte('created_at', desde);
        cantidadPrestamos = prestamos.length;
        totalPrestado = prestamos.fold<double>(
          0,
          (total, row) => total + _toDouble(row['monto']),
        );
      }

      final cobros = await SupabaseService.requireClient
          .from('cobros')
          .select('monto, prestamo_id')
          .eq('cobrador_id', cobradorUuid)
          .eq('estado', 'registrado')
          .gte('fecha_pago', desde);
      final totalRecaudado = cobros.fold<double>(
        0,
        (total, row) => total + _toDouble(row['monto']),
      );

      final gastoRows = await SupabaseService.requireClient
          .from('gastos')
          .select('valor')
          .eq('cobrador_id', cobradorUuid)
          .gte('fecha_hora', desde);
      final totalGastos = gastoRows.fold<double>(
        0,
        (total, row) => total + _toDouble(row['valor']),
      );

      final cierreEstado = caja == null ? null : _cierreEstadoDesdeCaja(caja);
      final cajaId = caja == null
          ? null
          : OnlineIdMapper.instance.localIdFor(
              _rowIdRequerido(caja, 'Caja online no encontrada.'),
            );
      return CajaResumenDiario(
        cajaId: cajaId,
        cobradorId: cobradorId,
        nombre: usuario['nombre'] as String? ?? 'Cobrador',
        estadoCaja: caja?['estado'] as String? ?? CajaEstados.cerrada,
        saldoInicial: _toDouble(caja?['saldo_inicial']),
        saldoDisponible: _toDouble(usuario['saldo_disponible']),
        totalPrestado: totalPrestado,
        totalRecaudado: totalRecaudado,
        gastos: totalGastos,
        cantidadPrestamos: cantidadPrestamos,
        cantidadCobros: cobros.length,
        clientesVisitados: cobros
            .map((row) => row['prestamo_id'] as String?)
            .whereType<String>()
            .toSet()
            .length,
        cierreRealizado: cierreEstado != null,
        cierrePendiente: cierreEstado == CierreCajaEstados.pendienteRevision,
        horaApertura: caja?['hora_apertura'] as String?,
        cierreEstado: cierreEstado,
      );
    }

    final db = await _db;
    final cajaRows = await db.query(
      DatabaseTables.cajas,
      where: 'cobrador_id = ? AND estado IN (?, ?, ?)',
      whereArgs: [
        cobradorId,
        CajaEstados.abierta,
        CajaEstados.pendienteRevision,
        CajaEstados.bloqueada,
      ],
      orderBy: 'fecha_creacion DESC',
      limit: 1,
    );
    final caja = cajaRows.isEmpty ? null : cajaRows.first;
    final desde = caja == null
        ? _startOfToday().toIso8601String()
        : caja['fecha_creacion'] as String;
    final hasta = DateTime.now().toIso8601String();
    final usuarioRows = await db.query(
      DatabaseTables.usuarios,
      where: 'id = ?',
      whereArgs: [cobradorId],
      limit: 1,
    );
    final usuario = usuarioRows.first;
    final movimientos = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN tipo = ? THEN monto ELSE 0 END), 0) AS prestado,
        COALESCE(SUM(CASE WHEN tipo = ? THEN monto ELSE 0 END), 0) AS recaudado,
        COALESCE(SUM(CASE WHEN tipo = ? THEN monto ELSE 0 END), 0) AS gastos,
        SUM(CASE WHEN tipo = ? THEN 1 ELSE 0 END) AS cant_prestamos,
        SUM(CASE WHEN tipo = ? THEN 1 ELSE 0 END) AS cant_cobros,
        COUNT(DISTINCT cliente_id) AS clientes_visitados
      FROM ${DatabaseTables.movimientosFinancieros}
      WHERE usuario_id = ?
        AND fecha_hora BETWEEN ? AND ?
      ''',
      [
        MovimientoFinancieroTipos.prestamo,
        MovimientoFinancieroTipos.cobro,
        MovimientoFinancieroTipos.gasto,
        MovimientoFinancieroTipos.prestamo,
        MovimientoFinancieroTipos.cobro,
        cobradorId,
        desde,
        hasta,
      ],
    );
    final cierre = await db.query(
      DatabaseTables.cierresCaja,
      where: caja == null ? 'cobrador_id = ? AND fecha = ?' : 'caja_id = ?',
      whereArgs: caja == null
          ? [cobradorId, _dateKey(DateTime.now())]
          : [caja['id']],
      limit: 1,
    );
    final row = movimientos.first;
    final cierreEstado = cierre.isEmpty ? null : cierre.first['estado'];
    return CajaResumenDiario(
      cajaId: caja?['id'] as int?,
      cobradorId: cobradorId,
      nombre: usuario['nombre'] as String,
      estadoCaja: caja?['estado'] as String? ?? CajaEstados.cerrada,
      saldoInicial: (caja?['saldo_inicial'] as num?)?.toDouble() ?? 0,
      saldoDisponible: (usuario['saldo_disponible'] as num?)?.toDouble() ?? 0,
      totalPrestado: (row['prestado'] as num).toDouble(),
      totalRecaudado: (row['recaudado'] as num).toDouble(),
      gastos: (row['gastos'] as num).toDouble(),
      cantidadPrestamos: (row['cant_prestamos'] as int?) ?? 0,
      cantidadCobros: (row['cant_cobros'] as int?) ?? 0,
      clientesVisitados: (row['clientes_visitados'] as int?) ?? 0,
      cierreRealizado:
          cierreEstado == CierreCajaEstados.aprobado ||
          cierreEstado == CierreCajaEstados.pendienteRevision ||
          cierreEstado == CierreCajaEstados.rechazado,
      cierrePendiente: cierreEstado == CierreCajaEstados.pendienteRevision,
      horaApertura: caja?['hora_apertura'] as String?,
      cierreEstado: cierreEstado as String?,
    );
  }

  Future<List<Map<String, Object?>>> solicitudesPendientes() async {
    if (_usaSupabase) {
      final rows = await SupabaseService.requireClient
          .from('solicitudes_saldo')
          .select()
          .eq('estado', SolicitudSaldoEstados.pendiente)
          .order('created_at', ascending: false);
      final result = <Map<String, Object?>>[];
      for (final row in rows) {
        final cobradorId = OnlineIdMapper.instance.localIdFor(
          row['cobrador_id'] as String,
        );
        result.add({
          'id': OnlineIdMapper.instance.localIdFor(row['id'] as String),
          'cobrador_id': cobradorId,
          'cobrador_nombre': await _nombreUsuario(cobradorId),
          'monto_solicitado': row['monto_solicitado'],
          'observacion': row['observacion'],
          'estado': row['estado'],
          'fecha_hora': row['created_at'],
        });
      }
      return result;
    }

    final db = await _db;
    return db.rawQuery(
      '''
      SELECT s.*, u.nombre AS cobrador_nombre
      FROM ${DatabaseTables.solicitudesSaldo} s
      INNER JOIN ${DatabaseTables.usuarios} u ON u.id = s.cobrador_id
      WHERE s.estado = ?
      ORDER BY s.fecha_hora DESC
      ''',
      [SolicitudSaldoEstados.pendiente],
    );
  }

  Future<List<Map<String, Object?>>> cierresRecientes() async {
    if (_usaSupabase) {
      final rows = await SupabaseService.requireClient
          .from('cajas')
          .select()
          .or(
            'dinero_reportado.not.is.null,estado.eq.pendiente_revision,estado.eq.bloqueada',
          )
          .order('updated_at', ascending: false)
          .limit(100);
      final result = <Map<String, Object?>>[];
      for (final row in rows) {
        result.add(await _cierreOnlineToMap(row));
      }
      return result;
    }

    final db = await _db;
    return db.rawQuery('''
      SELECT c.*, u.nombre AS cobrador_nombre
      FROM ${DatabaseTables.cierresCaja} c
      INNER JOIN ${DatabaseTables.usuarios} u ON u.id = c.cobrador_id
      ORDER BY c.fecha_hora DESC
      LIMIT 100
      ''');
  }

  Future<List<Map<String, Object?>>> cajasRecientes() async {
    if (_usaSupabase) {
      final rows = await SupabaseService.requireClient
          .from('cajas')
          .select()
          .order('created_at', ascending: false)
          .limit(80);
      final result = <Map<String, Object?>>[];
      for (final row in rows) {
        final cobradorId = OnlineIdMapper.instance.localIdFor(
          row['cobrador_id'] as String,
        );
        result.add({
          ..._cajaOnlineToMap(row),
          'cobrador_nombre': await _nombreUsuario(cobradorId),
        });
      }
      return result;
    }

    final db = await _db;
    return db.rawQuery('''
      SELECT cj.*, u.nombre AS cobrador_nombre, a.nombre AS admin_nombre
      FROM ${DatabaseTables.cajas} cj
      INNER JOIN ${DatabaseTables.usuarios} u ON u.id = cj.cobrador_id
      LEFT JOIN ${DatabaseTables.usuarios} a ON a.id = cj.admin_id
      ORDER BY cj.fecha_creacion DESC
      LIMIT 100
      ''');
  }

  Future<List<Map<String, Object?>>> movimientos({int? cobradorId}) async {
    if (_usaSupabase) {
      final cobradorUuid = OnlineIdMapper.instance.uuidFor(cobradorId);
      final items = <Map<String, Object?>>[];

      dynamic prestamosQuery = SupabaseService.requireClient
          .from('prestamos')
          .select('id, cliente_id, monto, created_at');
      if (cobradorUuid != null) {
        final clientes = await SupabaseService.requireClient
            .from('clientes')
            .select('id')
            .eq('cobrador_id', cobradorUuid);
        final clienteIds = clientes
            .map<String>((row) => row['id'] as String)
            .toList();
        if (clienteIds.isEmpty) {
          prestamosQuery = null;
        } else {
          prestamosQuery = prestamosQuery.inFilter('cliente_id', clienteIds);
        }
      }

      if (prestamosQuery != null) {
        final prestamos = await prestamosQuery
            .order('created_at', ascending: false)
            .limit(80);
        for (final row in prestamos) {
          final clienteId = OnlineIdMapper.instance.localIdFor(
            row['cliente_id'] as String,
          );
          items.add({
            'id': OnlineIdMapper.instance.localIdFor(row['id'] as String),
            'tipo': MovimientoFinancieroTipos.prestamo,
            'monto': row['monto'],
            'usuario_nombre': cobradorId == null
                ? 'Cobrador'
                : await _nombreUsuario(cobradorId),
            'cliente_nombre': await _nombreCliente(clienteId),
            'fecha_hora': row['created_at'],
          });
        }
      }

      dynamic cobrosQuery = SupabaseService.requireClient
          .from('cobros')
          .select('id, cobrador_id, monto, fecha_pago');
      if (cobradorUuid != null) {
        cobrosQuery = cobrosQuery.eq('cobrador_id', cobradorUuid);
      }
      final cobros = await cobrosQuery
          .order('fecha_pago', ascending: false)
          .limit(80);
      for (final row in cobros) {
        final localCobradorId = OnlineIdMapper.instance.localIdFor(
          row['cobrador_id'] as String,
        );
        items.add({
          'id': OnlineIdMapper.instance.localIdFor(row['id'] as String),
          'tipo': MovimientoFinancieroTipos.cobro,
          'monto': row['monto'],
          'usuario_nombre': await _nombreUsuario(localCobradorId),
          'cliente_nombre': null,
          'fecha_hora': row['fecha_pago'],
        });
      }

      for (final row in await gastos(cobradorId: cobradorId)) {
        items.add({
          'id': row['id'],
          'tipo': MovimientoFinancieroTipos.gasto,
          'monto': row['valor'],
          'usuario_nombre': row['cobrador_nombre'],
          'cliente_nombre': null,
          'fecha_hora': row['fecha_hora'],
        });
      }

      items.sort((a, b) {
        final left = DateTime.tryParse(a['fecha_hora']?.toString() ?? '');
        final right = DateTime.tryParse(b['fecha_hora']?.toString() ?? '');
        return (right ?? DateTime(1900)).compareTo(left ?? DateTime(1900));
      });
      return items.take(200).toList();
    }

    final db = await _db;
    return db.rawQuery('''
      SELECT m.*, u.nombre AS usuario_nombre, c.nombre AS cliente_nombre
      FROM ${DatabaseTables.movimientosFinancieros} m
      INNER JOIN ${DatabaseTables.usuarios} u ON u.id = m.usuario_id
      LEFT JOIN ${DatabaseTables.clientes} c ON c.id = m.cliente_id
      ${cobradorId == null ? '' : 'WHERE m.usuario_id = ?'}
      ORDER BY m.fecha_hora DESC
      LIMIT 200
      ''', cobradorId == null ? [] : [cobradorId]);
  }

  Future<List<Map<String, Object?>>> gastos({int? cobradorId}) async {
    if (_usaSupabase) {
      dynamic query = SupabaseService.requireClient.from('gastos').select();
      final cobradorUuid = OnlineIdMapper.instance.uuidFor(cobradorId);
      if (cobradorUuid != null) query = query.eq('cobrador_id', cobradorUuid);
      final rows = await query.order('fecha_hora', ascending: false);
      final result = <Map<String, Object?>>[];
      for (final row in rows) {
        final localCobradorId = OnlineIdMapper.instance.localIdFor(
          row['cobrador_id'] as String,
        );
        result.add({
          'id': OnlineIdMapper.instance.localIdFor(row['id'] as String),
          'cobrador_id': localCobradorId,
          'cobrador_nombre': await _nombreUsuario(localCobradorId),
          'tipo': row['tipo'],
          'valor': row['valor'],
          'descripcion': row['descripcion'],
          'fecha_hora': row['fecha_hora'],
        });
      }
      return result;
    }

    final db = await _db;
    return db.rawQuery('''
      SELECT g.*, u.nombre AS cobrador_nombre
      FROM ${DatabaseTables.gastos} g
      INNER JOIN ${DatabaseTables.usuarios} u ON u.id = g.cobrador_id
      ${cobradorId == null ? '' : 'WHERE g.cobrador_id = ?'}
      ORDER BY g.fecha_hora DESC
      LIMIT 200
      ''', cobradorId == null ? [] : [cobradorId]);
  }

  Future<List<Map<String, Object?>>> cierresPorCobrador(int cobradorId) async {
    if (_usaSupabase) {
      final cobradorUuid = OnlineIdMapper.instance.uuidFor(cobradorId);
      if (cobradorUuid == null) return [];
      final rows = await SupabaseService.requireClient
          .from('cajas')
          .select()
          .eq('cobrador_id', cobradorUuid)
          .or(
            'dinero_reportado.not.is.null,estado.eq.pendiente_revision,estado.eq.bloqueada',
          )
          .order('updated_at', ascending: false)
          .limit(50);
      final result = <Map<String, Object?>>[];
      for (final row in rows) {
        result.add(await _cierreOnlineToMap(row));
      }
      return result;
    }

    final db = await _db;
    return db.query(
      DatabaseTables.cierresCaja,
      where: 'cobrador_id = ?',
      whereArgs: [cobradorId],
      orderBy: 'fecha_hora DESC',
      limit: 50,
    );
  }

  Future<int> _abrirCajaOnline({
    required int cobradorId,
    required double saldoInicial,
    String? observacion,
  }) async {
    final perfil = _perfilActualOnline();
    _validarAdminOnline(perfil);
    if (saldoInicial < 0) {
      throw StateError('El saldo inicial no puede ser negativo.');
    }
    final cobradorUuid = _uuidRequerido(cobradorId, 'Cobrador');
    await _validarPuedeAbrirCajaOnline(cobradorId);

    final now = DateTime.now();
    final row = await SupabaseService.requireClient
        .from('cajas')
        .insert({
          'empresa_id': perfil.companyId,
          'cobrador_id': cobradorUuid,
          'admin_id': perfil.id,
          'fecha': _dateKey(now),
          'hora_apertura': _timeKey(now),
          'saldo_inicial': saldoInicial,
          'saldo_actual': saldoInicial,
          'observacion_apertura': observacion,
          'estado': CajaEstados.abierta,
        })
        .select()
        .single();

    if (saldoInicial > 0) {
      await _ajustarCapitalOnline(
        tipo: CapitalMovimientoTipos.asignacionCobrador,
        monto: saldoInicial,
        delta: -saldoInicial,
        observacion: observacion ?? 'Apertura de caja',
      );
    }

    await SupabaseService.requireClient
        .from('perfiles')
        .update({
          'saldo_disponible': saldoInicial,
          'updated_at': now.toIso8601String(),
        })
        .eq('id', cobradorUuid);

    final cajaId = OnlineIdMapper.instance.localIdFor(row['id'] as String);
    await auditoriaRepository.registrar(
      accion: 'abrir_caja',
      modulo: 'caja',
      referenciaId: cajaId,
      descripcion: 'Caja abierta cobrador=$cobradorId saldo=$saldoInicial',
    );
    await notificacionRepository.crear(
      usuarioId: cobradorId,
      titulo: 'Caja abierta',
      mensaje: 'Tu caja fue abierta con saldo ${_money(saldoInicial)}.',
      tipo: NotificacionTipos.exito,
      modulo: 'caja',
      referenciaId: cajaId,
    );
    return cajaId;
  }

  Future<void> _validarPuedeAbrirCajaOnline(int cobradorId) async {
    final cobradorUuid = _uuidRequerido(cobradorId, 'Cobrador');
    final abierta = await SupabaseService.requireClient
        .from('cajas')
        .select('id')
        .eq('cobrador_id', cobradorUuid)
        .inFilter('estado', [
          CajaEstados.abierta,
          CajaEstados.pendienteRevision,
          CajaEstados.bloqueada,
        ])
        .limit(1)
        .maybeSingle();
    if (abierta != null) {
      throw StateError('El cobrador tiene una caja abierta o pendiente.');
    }
  }

  Future<void> _registrarGastoOnline({
    required int cobradorId,
    required String tipo,
    required double valor,
    String? descripcion,
  }) async {
    final perfil = _perfilActualOnline();
    if (valor <= 0) throw StateError('El gasto debe ser mayor a cero.');
    await validarCobradorPuedeOperar(cobradorId);
    final cobradorUuid = _uuidRequerido(cobradorId, 'Cobrador');
    final caja = await _cajaAbiertaOnline(cobradorUuid);
    final cajaUuid = _rowIdRequerido(caja, 'No hay caja abierta para operar.');
    final saldoAntes = await _saldoDisponibleOnline(cobradorUuid);
    final saldoDespues = saldoAntes - valor;
    if (saldoDespues < 0) {
      throw StateError(
        'No posee fondos disponibles para realizar la operacion.',
      );
    }

    await SupabaseService.requireClient.from('gastos').insert({
      'empresa_id': perfil.companyId,
      'cobrador_id': cobradorUuid,
      'tipo': tipo,
      'valor': valor,
      'descripcion': descripcion,
      'fecha_hora': DateTime.now().toIso8601String(),
    });
    await _actualizarSaldoOnline(
      cobradorUuid: cobradorUuid,
      cajaUuid: cajaUuid,
      saldo: saldoDespues,
    );
    await auditoriaRepository.registrar(
      accion: 'registrar_gasto',
      modulo: 'caja',
      descripcion: 'Gasto $tipo valor=$valor cobrador=$cobradorId',
    );
    final nombreCobrador = await _nombreUsuario(cobradorId);
    await notificacionRepository.crearParaAdmins(
      titulo: 'Gasto registrado',
      mensaje:
          '$nombreCobrador registro un gasto de ${_money(valor)} en $tipo.',
      tipo: NotificacionTipos.informativa,
      modulo: 'caja',
    );
  }

  Future<void> _solicitarSaldoOnline({
    required int cobradorId,
    required double monto,
    String? observacion,
  }) async {
    final perfil = _perfilActualOnline();
    if (monto <= 0) {
      throw StateError('El monto solicitado debe ser mayor a cero.');
    }
    final cobradorUuid = _uuidRequerido(cobradorId, 'Cobrador');
    final row = await SupabaseService.requireClient
        .from('solicitudes_saldo')
        .insert({
          'empresa_id': perfil.companyId,
          'cobrador_id': cobradorUuid,
          'monto_solicitado': monto,
          'observacion': observacion,
          'estado': SolicitudSaldoEstados.pendiente,
        })
        .select()
        .single();
    final solicitudId = OnlineIdMapper.instance.localIdFor(row['id'] as String);
    await auditoriaRepository.registrar(
      accion: 'solicitar_saldo',
      modulo: 'caja',
      referenciaId: solicitudId,
      descripcion: 'Solicitud de saldo cobrador=$cobradorId monto=$monto',
    );
    final nombreCobrador = await _nombreUsuario(cobradorId);
    await notificacionRepository.crearParaAdmins(
      titulo: 'Solicitud de saldo pendiente',
      mensaje: '$nombreCobrador solicita saldo por ${_money(monto)}.',
      tipo: NotificacionTipos.advertencia,
      modulo: 'caja',
      referenciaId: solicitudId,
    );
  }

  Future<void> _responderSolicitudOnline({
    required int solicitudId,
    required bool aprobar,
    required double montoAprobado,
    String? observacionAdmin,
  }) async {
    final perfil = _perfilActualOnline();
    _validarAdminOnline(perfil);
    final solicitudUuid = _uuidRequerido(solicitudId, 'Solicitud');
    final solicitud = await SupabaseService.requireClient
        .from('solicitudes_saldo')
        .select()
        .eq('id', solicitudUuid)
        .eq('estado', SolicitudSaldoEstados.pendiente)
        .maybeSingle();
    if (solicitud == null) throw StateError('La solicitud ya fue respondida.');
    final solicitudRow = solicitud;
    if (aprobar && montoAprobado <= 0) {
      throw StateError('Ingresa un monto aprobado mayor a cero.');
    }

    final monto = aprobar ? montoAprobado : 0.0;
    await SupabaseService.requireClient
        .from('solicitudes_saldo')
        .update({
          'estado': aprobar
              ? SolicitudSaldoEstados.aprobada
              : SolicitudSaldoEstados.rechazada,
          'monto_aprobado': monto,
          'observacion_admin': observacionAdmin,
          'fecha_respuesta': DateTime.now().toIso8601String(),
          'admin_id': perfil.id,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', solicitudUuid);

    final cobradorId = OnlineIdMapper.instance.localIdFor(
      solicitudRow['cobrador_id'] as String,
    );
    if (aprobar) {
      await _asignarSaldoOnline(
        cobradorId: cobradorId,
        monto: monto,
        observacion: observacionAdmin ?? 'Saldo aprobado por admin',
      );
    }
    await auditoriaRepository.registrar(
      accion: aprobar ? 'aprobar_saldo' : 'rechazar_saldo',
      modulo: 'caja',
      referenciaId: solicitudId,
      descripcion:
          'Solicitud saldo=$solicitudId aprobar=$aprobar monto=$montoAprobado',
    );
    await notificacionRepository.crear(
      usuarioId: cobradorId,
      titulo: 'Solicitud de saldo ${aprobar ? 'aprobada' : 'rechazada'}',
      mensaje: aprobar
          ? 'Tu solicitud fue aprobada por ${_money(montoAprobado)}.'
          : 'Tu solicitud de saldo fue rechazada.',
      tipo: aprobar ? NotificacionTipos.exito : NotificacionTipos.advertencia,
      modulo: 'caja',
      referenciaId: solicitudId,
    );
  }

  Future<void> _asignarSaldoOnline({
    required int cobradorId,
    required double monto,
    String? observacion,
  }) async {
    final perfil = _perfilActualOnline();
    _validarAdminOnline(perfil);
    if (monto <= 0) throw StateError('El monto debe ser mayor a cero.');
    final cobradorUuid = _uuidRequerido(cobradorId, 'Cobrador');
    final caja = await _cajaAbiertaOnline(cobradorUuid);
    if (caja == null) {
      await _abrirCajaOnline(
        cobradorId: cobradorId,
        saldoInicial: monto,
        observacion: observacion,
      );
      return;
    }
    final cajaUuid = _rowIdRequerido(caja, 'No hay caja abierta.');
    final saldoDespues = await _saldoDisponibleOnline(cobradorUuid) + monto;
    await _actualizarSaldoOnline(
      cobradorUuid: cobradorUuid,
      cajaUuid: cajaUuid,
      saldo: saldoDespues,
    );
    await auditoriaRepository.registrar(
      accion: 'asignar_saldo',
      modulo: 'caja',
      referenciaId: cobradorId,
      descripcion: 'Saldo asignado cobrador=$cobradorId monto=$monto',
    );
    await notificacionRepository.crear(
      usuarioId: cobradorId,
      titulo: 'Saldo asignado',
      mensaje: 'El administrador asigno saldo por ${_money(monto)}.',
      tipo: NotificacionTipos.exito,
      modulo: 'caja',
      referenciaId: cobradorId,
    );
  }

  Future<void> _cerrarCajaOnline({
    required int cobradorId,
    required double dineroReportado,
    String? observacion,
  }) async {
    final cobradorUuid = _uuidRequerido(cobradorId, 'Cobrador');
    final caja = await _cajaAbiertaOnline(cobradorUuid);
    final cajaUuid = _rowIdRequerido(caja, 'No hay caja abierta para cerrar.');
    final resumen = await resumenDiario(cobradorId);
    final diferencia = dineroReportado - resumen.saldoDisponible;
    final now = DateTime.now();
    await SupabaseService.requireClient
        .from('cajas')
        .update({
          'estado': CajaEstados.pendienteRevision,
          'hora_cierre': _timeKey(now),
          'dinero_reportado': dineroReportado,
          'diferencia': diferencia,
          'observacion_cierre': observacion,
          'updated_at': now.toIso8601String(),
        })
        .eq('id', cajaUuid);
    final cierreId = OnlineIdMapper.instance.localIdFor(cajaUuid);
    await auditoriaRepository.registrar(
      accion: 'cerrar_caja',
      modulo: 'caja',
      referenciaId: cierreId,
      descripcion: 'Cierre caja cobrador=$cobradorId diferencia=$diferencia',
    );
    if (diferencia != 0) {
      final nombreCobrador = await _nombreUsuario(cobradorId);
      await notificacionRepository.crearParaAdmins(
        titulo: 'Diferencia en caja',
        mensaje:
            '$nombreCobrador cerro caja con diferencia de ${_money(diferencia)}.',
        tipo: NotificacionTipos.critica,
        modulo: 'caja',
        referenciaId: cierreId,
      );
    }
  }

  Future<void> _registrarEntregaDineroOnline({
    required int cierreId,
    required double montoEntregado,
    String? observacion,
  }) async {
    final perfil = _perfilActualOnline();
    _validarAdminOnline(perfil);
    if (montoEntregado < 0) {
      throw StateError('El monto entregado no puede ser negativo.');
    }
    final cajaUuid = _uuidRequerido(cierreId, 'Cierre');
    final cierre = await SupabaseService.requireClient
        .from('cajas')
        .select('dinero_reportado, estado')
        .eq('id', cajaUuid)
        .maybeSingle();
    if (cierre == null) throw StateError('El cierre no existe.');
    final cierreRow = cierre;
    if (cierreRow['estado'] == CajaEstados.cerrada ||
        cierreRow['estado'] == CajaEstados.bloqueada) {
      throw StateError('Un cierre evaluado no puede modificarse.');
    }
    final reportado = _toDouble(cierreRow['dinero_reportado']);
    await SupabaseService.requireClient
        .from('cajas')
        .update({
          'dinero_entregado': montoEntregado,
          'diferencia': montoEntregado - reportado,
          'admin_id': perfil.id,
          'observacion_admin': observacion,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', cajaUuid);
    await auditoriaRepository.registrar(
      accion: 'entrega_dinero',
      modulo: 'caja',
      referenciaId: cierreId,
      descripcion: 'Entrega dinero cierre=$cierreId monto=$montoEntregado',
    );
  }

  Future<void> _revisarCierreOnline({
    required int cierreId,
    required String estado,
    String? observacionAdmin,
  }) async {
    final perfil = _perfilActualOnline();
    _validarAdminOnline(perfil);
    if (![
      CierreCajaEstados.aprobado,
      CierreCajaEstados.rechazado,
      CierreCajaEstados.pendienteRevision,
    ].contains(estado)) {
      throw StateError('Estado de cierre invalido.');
    }
    final cajaUuid = _uuidRequerido(cierreId, 'Cierre');
    final cierre = await SupabaseService.requireClient
        .from('cajas')
        .select('cobrador_id, estado')
        .eq('id', cajaUuid)
        .maybeSingle();
    if (cierre == null) throw StateError('El cierre no existe.');
    final cierreRow = cierre;
    if (cierreRow['estado'] == CajaEstados.cerrada ||
        cierreRow['estado'] == CajaEstados.bloqueada) {
      throw StateError('Un cierre evaluado no puede modificarse.');
    }
    final estadoCaja = estado == CierreCajaEstados.aprobado
        ? CajaEstados.cerrada
        : estado == CierreCajaEstados.rechazado
        ? CajaEstados.bloqueada
        : CajaEstados.pendienteRevision;
    await SupabaseService.requireClient
        .from('cajas')
        .update({
          'estado': estadoCaja,
          'observacion_admin': observacionAdmin,
          'admin_id': perfil.id,
          'fecha_revision': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', cajaUuid);

    final cobradorId = OnlineIdMapper.instance.localIdFor(
      cierreRow['cobrador_id'] as String,
    );
    await auditoriaRepository.registrar(
      accion: estado == CierreCajaEstados.aprobado
          ? 'aprobar_cierre'
          : estado == CierreCajaEstados.rechazado
          ? 'rechazar_cierre'
          : 'solicitar_revision_cierre',
      modulo: 'caja',
      referenciaId: cierreId,
      descripcion: 'Revision cierre=$cierreId estado=$estado',
    );
    await notificacionRepository.crear(
      usuarioId: cobradorId,
      titulo: estado == CierreCajaEstados.aprobado
          ? 'Cierre aprobado'
          : estado == CierreCajaEstados.rechazado
          ? 'Cierre rechazado'
          : 'Cierre en revision',
      mensaje: observacionAdmin ?? 'El administrador actualizo tu cierre.',
      tipo: estado == CierreCajaEstados.aprobado
          ? NotificacionTipos.exito
          : NotificacionTipos.advertencia,
      modulo: 'caja',
      referenciaId: cierreId,
    );
  }

  UsuarioModel _adminActual() {
    final admin = SessionManager.instance.usuarioActual;
    if (admin?.esAdministrador != true || admin?.id == null) {
      throw StateError('Solo el administrador puede gestionar capital.');
    }
    return admin!;
  }

  Future<Map<String, Object?>?> _capitalActivoEn(
    DatabaseExecutor executor,
  ) async {
    final rows = await executor.query(
      DatabaseTables.capitalGeneral,
      where: 'estado = ?',
      whereArgs: ['activo'],
      orderBy: 'fecha_hora DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<_CapitalAjuste> _ajustarCapital({
    required Transaction txn,
    required int usuarioId,
    required String tipo,
    required double monto,
    required double delta,
    String? observacion,
    String? referenciaTabla,
    int? referenciaId,
  }) async {
    final capital = await _capitalActivoEn(txn);
    if (capital == null) {
      throw StateError('Registra el capital inicial antes de asignar saldo.');
    }
    final capitalId = capital['id'] as int;
    final saldoAntes = (capital['capital_disponible'] as num?)?.toDouble() ?? 0;
    final saldoDespues = saldoAntes + delta;
    if (saldoDespues < 0) {
      throw StateError('Capital general insuficiente para esta operacion.');
    }
    final now = DateTime.now().toIso8601String();
    await txn.update(
      DatabaseTables.capitalGeneral,
      {'capital_disponible': saldoDespues},
      where: 'id = ?',
      whereArgs: [capitalId],
    );
    await txn.insert(DatabaseTables.movimientosCapital, {
      'capital_id': capitalId,
      'usuario_id': usuarioId,
      'tipo': tipo,
      'monto': monto,
      'saldo_antes': saldoAntes,
      'saldo_despues': saldoDespues,
      'observacion': observacion,
      'referencia_tabla': referenciaTabla,
      'referencia_id': referenciaId,
      'fecha_hora': now,
    });
    await _alertarCapitalBajo(
      txn: txn,
      capitalId: capitalId,
      capitalInicial: (capital['monto_inicial'] as num?)?.toDouble() ?? 0,
      saldoDisponible: saldoDespues,
      fechaHora: now,
    );
    return _CapitalAjuste(
      capitalId: capitalId,
      saldoAntes: saldoAntes,
      saldoDespues: saldoDespues,
    );
  }

  Future<void> _registrarAsignacionDesdeCapital({
    required Transaction txn,
    required int cobradorId,
    required int adminId,
    required double monto,
    String? observacion,
    String? referenciaTabla,
    int? referenciaId,
  }) async {
    final ajuste = await _ajustarCapital(
      txn: txn,
      usuarioId: adminId,
      tipo: CapitalMovimientoTipos.asignacionCobrador,
      monto: monto,
      delta: -monto,
      observacion: observacion ?? 'Asignacion de saldo a cobrador',
      referenciaTabla: referenciaTabla,
      referenciaId: referenciaId,
    );
    await txn.insert(DatabaseTables.asignacionesSaldo, {
      'capital_id': ajuste.capitalId,
      'cobrador_id': cobradorId,
      'admin_id': adminId,
      'monto': monto,
      'saldo_antes': ajuste.saldoAntes,
      'saldo_despues': ajuste.saldoDespues,
      'observacion': observacion,
      'fecha_hora': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _registrarEntregaEnSaldo({
    required Transaction txn,
    required int cobradorId,
    required int adminId,
    required int cierreId,
    required int? cajaId,
    required double montoMovimiento,
    required double deltaEntrega,
    String? observacion,
  }) async {
    final rows = await txn.query(
      DatabaseTables.usuarios,
      columns: ['saldo_disponible'],
      where: 'id = ?',
      whereArgs: [cobradorId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('El cobrador no existe.');
    final saldoAntes =
        (rows.first['saldo_disponible'] as num?)?.toDouble() ?? 0;
    final saldoDespues = (saldoAntes - deltaEntrega)
        .clamp(0, double.infinity)
        .toDouble();
    final now = DateTime.now().toIso8601String();
    await txn.update(
      DatabaseTables.usuarios,
      {'saldo_disponible': saldoDespues},
      where: 'id = ?',
      whereArgs: [cobradorId],
    );
    await txn.insert(DatabaseTables.movimientosFinancieros, {
      'usuario_id': cobradorId,
      'tipo': MovimientoFinancieroTipos.cierreCaja,
      'monto': montoMovimiento,
      'saldo_antes': saldoAntes,
      'saldo_despues': saldoDespues,
      'observacion': observacion,
      'referencia_tabla': DatabaseTables.cierresCaja,
      'referencia_id': cierreId,
      'fecha_hora': now,
    });
    await txn.insert(DatabaseTables.movimientosCaja, {
      'caja_id': cajaId,
      'usuario_id': adminId,
      'tipo': MovimientoFinancieroTipos.cierreCaja,
      'monto': montoMovimiento,
      'saldo_antes': saldoAntes,
      'saldo_despues': saldoDespues,
      'observacion': observacion,
      'referencia_tabla': DatabaseTables.cierresCaja,
      'referencia_id': cierreId,
      'fecha_hora': now,
    });
  }

  Future<void> _registrarMovimientoCapitalOperativo({
    required Transaction txn,
    required int usuarioId,
    required String tipo,
    required double monto,
    required String fechaHora,
    String? observacion,
    String? referenciaTabla,
    int? referenciaId,
  }) async {
    final capital = await _capitalActivoEn(txn);
    if (capital == null) return;
    final saldo = (capital['capital_disponible'] as num?)?.toDouble() ?? 0;
    await txn.insert(DatabaseTables.movimientosCapital, {
      'capital_id': capital['id'],
      'usuario_id': usuarioId,
      'tipo': tipo,
      'monto': monto,
      'saldo_antes': saldo,
      'saldo_despues': saldo,
      'observacion': observacion,
      'referencia_tabla': referenciaTabla,
      'referencia_id': referenciaId,
      'fecha_hora': fechaHora,
    });
  }

  Future<void> _alertarCapitalBajo({
    required Transaction txn,
    required int capitalId,
    required double capitalInicial,
    required double saldoDisponible,
    required String fechaHora,
  }) async {
    final limite = capitalInicial <= 0 ? 0 : capitalInicial * 0.1;
    if (saldoDisponible > limite) return;
    final existentes = await txn.query(
      DatabaseTables.notificaciones,
      where: 'titulo = ? AND estado = ? AND modulo = ?',
      whereArgs: ['Capital bajo', NotificacionEstados.pendiente, 'caja'],
      limit: 1,
    );
    if (existentes.isNotEmpty) return;
    await txn.insert(DatabaseTables.notificaciones, {
      'usuario_id': null,
      'titulo': 'Capital bajo',
      'mensaje': 'El capital disponible esta por debajo del limite operativo.',
      'tipo': NotificacionTipos.advertencia,
      'modulo': 'caja',
      'referencia_id': capitalId,
      'estado': NotificacionEstados.pendiente,
      'fecha_hora': fechaHora,
    });
  }

  Future<void> _ajustarSaldo({
    required Transaction txn,
    required int cobradorId,
    int? clienteId,
    required double montoMovimiento,
    required double deltaSaldo,
    required String tipo,
    String? observacion,
    String? referenciaTabla,
    int? referenciaId,
    bool validarSaldo = false,
  }) async {
    final rows = await txn.query(
      DatabaseTables.usuarios,
      columns: ['saldo_disponible'],
      where: 'id = ?',
      whereArgs: [cobradorId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('El cobrador no existe.');
    final saldoAntes =
        (rows.first['saldo_disponible'] as num?)?.toDouble() ?? 0;
    final saldoDespues = saldoAntes + deltaSaldo;
    if (validarSaldo && saldoDespues < 0) {
      throw StateError(
        'No posee fondos disponibles para realizar la operacion.',
      );
    }
    final cajaRows = await txn.query(
      DatabaseTables.cajas,
      where: 'cobrador_id = ? AND estado = ?',
      whereArgs: [cobradorId, CajaEstados.abierta],
      orderBy: 'fecha_creacion DESC',
      limit: 1,
    );
    final cajaId = cajaRows.isEmpty ? null : cajaRows.first['id'] as int;
    await txn.update(
      DatabaseTables.usuarios,
      {'saldo_disponible': saldoDespues},
      where: 'id = ?',
      whereArgs: [cobradorId],
    );
    if (cajaId != null) {
      await txn.update(
        DatabaseTables.cajas,
        {'saldo_actual': saldoDespues},
        where: 'id = ?',
        whereArgs: [cajaId],
      );
    }
    final now = DateTime.now().toIso8601String();
    await txn.insert(DatabaseTables.movimientosFinancieros, {
      'usuario_id': cobradorId,
      'tipo': tipo,
      'monto': montoMovimiento,
      'cliente_id': clienteId,
      'saldo_antes': saldoAntes,
      'saldo_despues': saldoDespues,
      'observacion': observacion,
      'referencia_tabla': referenciaTabla,
      'referencia_id': referenciaId,
      'fecha_hora': now,
    });
    if (cajaId != null) {
      await txn.insert(DatabaseTables.movimientosCaja, {
        'caja_id': cajaId,
        'usuario_id': cobradorId,
        'tipo': tipo,
        'monto': montoMovimiento,
        'saldo_antes': saldoAntes,
        'saldo_despues': saldoDespues,
        'observacion': observacion,
        'referencia_tabla': referenciaTabla,
        'referencia_id': referenciaId,
        'fecha_hora': now,
      });
    }
    if ([
      MovimientoFinancieroTipos.prestamo,
      MovimientoFinancieroTipos.cobro,
      MovimientoFinancieroTipos.gasto,
    ].contains(tipo)) {
      await _registrarMovimientoCapitalOperativo(
        txn: txn,
        usuarioId: cobradorId,
        tipo: tipo,
        monto: montoMovimiento,
        observacion: observacion,
        referenciaTabla: referenciaTabla,
        referenciaId: referenciaId,
        fechaHora: now,
      );
    }
    if (saldoDespues <= 0) {
      final existentes = await txn.query(
        DatabaseTables.notificaciones,
        where: 'usuario_id = ? AND titulo = ? AND estado = ?',
        whereArgs: [
          cobradorId,
          'Saldo insuficiente',
          NotificacionEstados.pendiente,
        ],
        limit: 1,
      );
      if (existentes.isNotEmpty) return;

      await txn.insert(DatabaseTables.notificaciones, {
        'usuario_id': cobradorId,
        'titulo': 'Saldo insuficiente',
        'mensaje':
            'Tu saldo disponible llego a cero. Solicita saldo al administrador.',
        'tipo': NotificacionTipos.critica,
        'modulo': 'caja',
        'referencia_id': cajaId ?? referenciaId,
        'estado': NotificacionEstados.pendiente,
        'fecha_hora': now,
      });
    }
  }

  Future<void> _registrarMovimientoSinSaldo({
    required int usuarioId,
    required String tipo,
    required double monto,
    String? observacion,
    String? referenciaTabla,
    int? referenciaId,
  }) async {
    final db = await _db;
    final saldo = await saldoDisponible(usuarioId);
    final caja = await cajaAbiertaDeCobrador(usuarioId);
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.insert(DatabaseTables.movimientosFinancieros, {
        'usuario_id': usuarioId,
        'tipo': tipo,
        'monto': monto,
        'saldo_antes': saldo,
        'saldo_despues': saldo,
        'observacion': observacion,
        'referencia_tabla': referenciaTabla,
        'referencia_id': referenciaId,
        'fecha_hora': now,
      });
      if (caja != null) {
        await txn.insert(DatabaseTables.movimientosCaja, {
          'caja_id': caja['id'],
          'usuario_id': usuarioId,
          'tipo': tipo,
          'monto': monto,
          'saldo_antes': saldo,
          'saldo_despues': saldo,
          'observacion': observacion,
          'referencia_tabla': referenciaTabla,
          'referencia_id': referenciaId,
          'fecha_hora': now,
        });
      }
    });
  }

  Future<int?> _cobradorDeSolicitud(int solicitudId) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseTables.solicitudesSaldo,
      columns: ['cobrador_id'],
      where: 'id = ?',
      whereArgs: [solicitudId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['cobrador_id'] as int?;
  }

  Future<String> _nombreUsuario(int usuarioId) async {
    if (_usaSupabase) {
      final uuid = OnlineIdMapper.instance.uuidFor(usuarioId);
      if (uuid == null) return 'Cobrador #$usuarioId';
      final row = await SupabaseService.requireClient
          .from('perfiles')
          .select('nombre')
          .eq('id', uuid)
          .maybeSingle();
      return row?['nombre'] as String? ?? 'Cobrador #$usuarioId';
    }

    final db = await _db;
    final rows = await db.query(
      DatabaseTables.usuarios,
      columns: ['nombre'],
      where: 'id = ?',
      whereArgs: [usuarioId],
      limit: 1,
    );
    if (rows.isEmpty) return 'Cobrador #$usuarioId';
    return rows.first['nombre'] as String;
  }

  Future<String> _nombreCliente(int clienteId) async {
    if (_usaSupabase) {
      final uuid = OnlineIdMapper.instance.uuidFor(clienteId);
      if (uuid == null) return 'Cliente #$clienteId';
      final row = await SupabaseService.requireClient
          .from('clientes')
          .select('nombre')
          .eq('id', uuid)
          .maybeSingle();
      return row?['nombre'] as String? ?? 'Cliente #$clienteId';
    }

    final db = await _db;
    final rows = await db.query(
      DatabaseTables.clientes,
      columns: ['nombre'],
      where: 'id = ?',
      whereArgs: [clienteId],
      limit: 1,
    );
    if (rows.isEmpty) return 'Cliente #$clienteId';
    return rows.first['nombre'] as String;
  }

  dynamic _perfilActualOnline() {
    final perfil = SessionManager.instance.perfilActual;
    if (perfil?.companyId == null) {
      throw StateError('No hay empresa activa en la sesion.');
    }
    return perfil!;
  }

  void _validarAdminOnline(dynamic perfil) {
    if (perfil.esAdministrador != true && perfil.esSuperadmin != true) {
      throw StateError('Solo el administrador puede realizar esta operacion.');
    }
  }

  String _uuidRequerido(int localId, String entidad) {
    final uuid = OnlineIdMapper.instance.uuidFor(localId);
    if (uuid == null) throw StateError('$entidad online no encontrado.');
    return uuid;
  }

  String _rowIdRequerido(Map<String, dynamic>? row, String mensaje) {
    final id = row?['id'] as String?;
    if (id == null) throw StateError(mensaje);
    return id;
  }

  Future<Map<String, dynamic>?> _cajaAbiertaOnline(String cobradorUuid) async {
    return SupabaseService.requireClient
        .from('cajas')
        .select()
        .eq('cobrador_id', cobradorUuid)
        .eq('estado', CajaEstados.abierta)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  Future<double> _saldoDisponibleOnline(String cobradorUuid) async {
    final row = await SupabaseService.requireClient
        .from('perfiles')
        .select('saldo_disponible')
        .eq('id', cobradorUuid)
        .maybeSingle();
    if (row == null) throw StateError('El cobrador no existe.');
    return _toDouble(row['saldo_disponible']);
  }

  Future<void> _actualizarSaldoOnline({
    required String cobradorUuid,
    required String cajaUuid,
    required double saldo,
  }) async {
    final now = DateTime.now().toIso8601String();
    await SupabaseService.requireClient
        .from('perfiles')
        .update({'saldo_disponible': saldo, 'updated_at': now})
        .eq('id', cobradorUuid);
    await SupabaseService.requireClient
        .from('cajas')
        .update({'saldo_actual': saldo, 'updated_at': now})
        .eq('id', cajaUuid);
  }

  Map<String, Object?> _cajaOnlineToMap(Map<String, dynamic> row) {
    return {
      'id': OnlineIdMapper.instance.localIdFor(row['id'] as String),
      'cobrador_id': OnlineIdMapper.instance.localIdFor(
        row['cobrador_id'] as String,
      ),
      'admin_id': row['admin_id'] == null
          ? null
          : OnlineIdMapper.instance.localIdFor(row['admin_id'] as String),
      'estado': row['estado'],
      'saldo_inicial': row['saldo_inicial'],
      'saldo_actual': row['saldo_actual'],
      'fecha': row['fecha'],
      'hora_apertura': row['hora_apertura'],
      'hora_cierre': row['hora_cierre'],
      'dinero_reportado': row['dinero_reportado'],
      'dinero_entregado': row['dinero_entregado'],
      'diferencia': row['diferencia'],
      'observacion_apertura': row['observacion_apertura'],
      'observacion_cierre': row['observacion_cierre'],
      'observacion_admin': row['observacion_admin'],
      'fecha_creacion': row['created_at'],
      'fecha_revision': row['fecha_revision'],
    };
  }

  Future<Map<String, Object?>> _cierreOnlineToMap(
    Map<String, dynamic> row,
  ) async {
    final cobradorId = OnlineIdMapper.instance.localIdFor(
      row['cobrador_id'] as String,
    );
    final resumen = await _resumenCajaOnline(row);
    return {
      'id': OnlineIdMapper.instance.localIdFor(row['id'] as String),
      'caja_id': OnlineIdMapper.instance.localIdFor(row['id'] as String),
      'cobrador_id': cobradorId,
      'cobrador_nombre': await _nombreUsuario(cobradorId),
      'fecha': row['fecha'],
      'estado': _cierreEstadoDesdeCaja(row),
      'total_recaudado': resumen.totalRecaudado,
      'total_prestado': resumen.totalPrestado,
      'cantidad_cobros': resumen.cantidadCobros,
      'cantidad_prestamos': resumen.cantidadPrestamos,
      'gastos': resumen.gastos,
      'saldo_restante': row['saldo_actual'],
      'dinero_reportado': row['dinero_reportado'],
      'dinero_entregado': row['dinero_entregado'],
      'diferencia': row['diferencia'],
      'observacion': row['observacion_cierre'],
      'observacion_admin': row['observacion_admin'],
      'fecha_hora': row['updated_at'] ?? row['created_at'],
    };
  }

  String? _cierreEstadoDesdeCaja(Map<String, dynamic> row) {
    final estadoCaja = row['estado'] as String?;
    if (estadoCaja == CajaEstados.pendienteRevision) {
      return CierreCajaEstados.pendienteRevision;
    }
    if (estadoCaja == CajaEstados.bloqueada) return CierreCajaEstados.rechazado;
    if (estadoCaja == CajaEstados.cerrada) return CierreCajaEstados.aprobado;
    return row['dinero_reportado'] == null
        ? null
        : CierreCajaEstados.pendienteRevision;
  }

  Future<CajaResumenDiario> _resumenCajaOnline(Map<String, dynamic> caja) async {
    final cobradorUuid = caja['cobrador_id'] as String;
    final cobradorId = OnlineIdMapper.instance.localIdFor(cobradorUuid);
    final desde =
        (caja['created_at'] as String?) ?? _startOfToday().toIso8601String();
    final hasta =
        (caja['updated_at'] as String?) ?? DateTime.now().toIso8601String();

    final clientes = await SupabaseService.requireClient
        .from('clientes')
        .select('id')
        .eq('cobrador_id', cobradorUuid);
    final clienteIds = clientes.map<String>((row) => row['id'] as String).toList();

    var totalPrestado = 0.0;
    var cantidadPrestamos = 0;
    if (clienteIds.isNotEmpty) {
      final prestamos = await SupabaseService.requireClient
          .from('prestamos')
          .select('monto')
          .inFilter('cliente_id', clienteIds)
          .gte('created_at', desde)
          .lte('created_at', hasta);
      cantidadPrestamos = prestamos.length;
      totalPrestado = prestamos.fold<double>(
        0,
        (total, row) => total + _toDouble(row['monto']),
      );
    }

    final cobros = await SupabaseService.requireClient
        .from('cobros')
        .select('monto, prestamo_id')
        .eq('cobrador_id', cobradorUuid)
        .eq('estado', 'registrado')
        .gte('fecha_pago', desde)
        .lte('fecha_pago', hasta);
    final totalRecaudado = cobros.fold<double>(
      0,
      (total, row) => total + _toDouble(row['monto']),
    );

    final gastos = await SupabaseService.requireClient
        .from('gastos')
        .select('valor')
        .eq('cobrador_id', cobradorUuid)
        .gte('fecha_hora', desde)
        .lte('fecha_hora', hasta);
    final totalGastos = gastos.fold<double>(
      0,
      (total, row) => total + _toDouble(row['valor']),
    );

    return CajaResumenDiario(
      cajaId: OnlineIdMapper.instance.localIdFor(caja['id'] as String),
      cobradorId: cobradorId,
      nombre: await _nombreUsuario(cobradorId),
      estadoCaja: caja['estado'] as String? ?? CajaEstados.cerrada,
      saldoInicial: _toDouble(caja['saldo_inicial']),
      saldoDisponible: _toDouble(caja['saldo_actual']),
      totalPrestado: totalPrestado,
      totalRecaudado: totalRecaudado,
      gastos: totalGastos,
      cantidadPrestamos: cantidadPrestamos,
      cantidadCobros: cobros.length,
      clientesVisitados: cobros
          .map((row) => row['prestamo_id'] as String?)
          .whereType<String>()
          .toSet()
          .length,
      cierreRealizado: true,
      cierrePendiente:
          _cierreEstadoDesdeCaja(caja) == CierreCajaEstados.pendienteRevision,
    );
  }

  bool get _usaSupabase {
    return SupabaseService.isInitialized &&
        SessionManager.instance.perfilActual != null;
  }

  Future<void> _registrarCapitalInicialOnline({
    required double monto,
    String? observacion,
  }) async {
    final perfil = _perfilActualOnline();
    _validarAdminOnline(perfil);
    if (monto <= 0) {
      throw StateError('El capital inicial debe ser mayor a cero.');
    }
    final activo = await _capitalActivoOnline();
    if (activo != null) {
      throw StateError('Ya existe un capital activo registrado.');
    }
    final row = await SupabaseService.requireClient
        .from('capital_general')
        .insert({
          'empresa_id': perfil.companyId,
          'monto_inicial': monto,
          'capital_disponible': monto,
          'observacion': observacion,
          'usuario_id': perfil.id,
          'estado': 'activo',
        })
        .select()
        .single();
    await _registrarMovimientoCapitalOnline(
      capitalUuid: row['id'] as String,
      usuarioUuid: perfil.id as String,
      tipo: CapitalMovimientoTipos.capitalInicial,
      monto: monto,
      saldoAntes: 0,
      saldoDespues: monto,
      observacion: observacion ?? 'Capital inicial',
      referenciaTabla: 'capital_general',
      referenciaUuid: row['id'] as String,
    );
    await auditoriaRepository.registrar(
      accion: 'registrar_capital_inicial',
      modulo: 'capital',
      referenciaId: OnlineIdMapper.instance.localIdFor(row['id'] as String),
      descripcion: 'Capital inicial monto=$monto',
    );
  }

  Future<void> _ajustarCapitalOnline({
    required String tipo,
    required double monto,
    required double delta,
    String? observacion,
    String? referenciaTabla,
    String? referenciaUuid,
  }) async {
    final perfil = _perfilActualOnline();
    _validarAdminOnline(perfil);
    if (monto <= 0) throw StateError('El monto debe ser mayor a cero.');
    final capital = await _capitalActivoOnline();
    if (capital == null) {
      throw StateError('Registra el capital inicial antes de continuar.');
    }
    final capitalRow = capital;
    final capitalUuid = _rowIdRequerido(capitalRow, 'Capital no encontrado.');
    final saldoAntes = _toDouble(capitalRow['capital_disponible']);
    final saldoDespues = saldoAntes + delta;
    if (saldoDespues < 0) {
      throw StateError('Capital general insuficiente para esta operacion.');
    }
    await SupabaseService.requireClient
        .from('capital_general')
        .update({'capital_disponible': saldoDespues})
        .eq('id', capitalUuid);
    await _registrarMovimientoCapitalOnline(
      capitalUuid: capitalUuid,
      usuarioUuid: perfil.id as String,
      tipo: tipo,
      monto: monto,
      saldoAntes: saldoAntes,
      saldoDespues: saldoDespues,
      observacion: observacion,
      referenciaTabla: referenciaTabla,
      referenciaUuid: referenciaUuid,
    );
  }

  Future<void> _cerrarFinancieroDiarioOnline({String? observacion}) async {
    final perfil = _perfilActualOnline();
    _validarAdminOnline(perfil);
    final resumen = await _capitalResumenOnline();
    if (!resumen.registrado) {
      throw StateError('Registra el capital inicial antes de cerrar.');
    }
    final fecha = _dateKey(DateTime.now());
    final row = await SupabaseService.requireClient
        .from('cierres_financieros')
        .insert({
          'empresa_id': perfil.companyId,
          'capital_id': _uuidRequerido(resumen.capitalId!, 'Capital'),
          'admin_id': perfil.id,
          'fecha': fecha,
          'capital_inicial': resumen.capitalInicial,
          'saldo_distribuido': resumen.saldoDistribuidoHoy,
          'total_prestado': resumen.totalPrestadoHoy,
          'total_recaudado': resumen.totalRecaudadoHoy,
          'gastos': resumen.gastosHoy,
          'ganancias': resumen.ganancias,
          'capital_final': resumen.capitalFinal,
          'observacion': observacion,
        })
        .select()
        .single();
    await _registrarMovimientoCapitalOnline(
      capitalUuid: _uuidRequerido(resumen.capitalId!, 'Capital'),
      usuarioUuid: perfil.id as String,
      tipo: CapitalMovimientoTipos.cierreFinanciero,
      monto: resumen.capitalFinal,
      saldoAntes: resumen.capitalDisponible,
      saldoDespues: resumen.capitalDisponible,
      observacion: observacion ?? 'Cierre financiero diario',
      referenciaTabla: 'cierres_financieros',
      referenciaUuid: row['id'] as String,
    );
    await auditoriaRepository.registrar(
      accion: 'cierre_financiero',
      modulo: 'capital',
      referenciaId: OnlineIdMapper.instance.localIdFor(row['id'] as String),
      descripcion: 'Cierre financiero fecha=$fecha',
    );
  }

  Future<Map<String, dynamic>?> _capitalActivoOnline() {
    final empresaId = SessionManager.instance.perfilActual?.companyId;
    dynamic query = SupabaseService.requireClient
        .from('capital_general')
        .select()
        .eq('estado', 'activo');
    if (empresaId != null) query = query.eq('empresa_id', empresaId);
    return query.order('created_at', ascending: false).limit(1).maybeSingle();
  }

  Future<void> _registrarMovimientoCapitalOnline({
    required String capitalUuid,
    required String usuarioUuid,
    required String tipo,
    required double monto,
    required double saldoAntes,
    required double saldoDespues,
    String? observacion,
    String? referenciaTabla,
    String? referenciaUuid,
  }) async {
    final perfil = _perfilActualOnline();
    await SupabaseService.requireClient.from('movimientos_capital').insert({
      'empresa_id': perfil.companyId,
      'capital_id': capitalUuid,
      'usuario_id': usuarioUuid,
      'tipo': tipo,
      'monto': monto,
      'saldo_antes': saldoAntes,
      'saldo_despues': saldoDespues,
      'observacion': observacion,
      'referencia_tabla': referenciaTabla,
      'referencia_id': referenciaUuid,
    });
  }

  Future<CapitalResumen> _capitalResumenOnline() async {
    final capital = await _capitalActivoOnline();
    final hoy = _dateKey(DateTime.now());
    final saldoCobradores = await SupabaseService.requireClient
        .from('perfiles')
        .select('saldo_disponible')
        .eq('rol', AppRoles.cobrador)
        .eq('estado', AppEstados.activo);
    final prestamosActivos = await SupabaseService.requireClient
        .from('prestamos')
        .select('monto, saldo, estado, created_at')
        .inFilter('estado', [AppEstados.activo, AppEstados.atrasado]);
    final cobros = await SupabaseService.requireClient
        .from('cobros')
        .select('monto, fecha_pago')
        .eq('estado', 'registrado');
    final gastos = await SupabaseService.requireClient
        .from('gastos')
        .select('valor, fecha_hora');

    final saldoOperativo = saldoCobradores.fold<double>(
      0,
      (total, row) => total + _toDouble(row['saldo_disponible']),
    );
    final capitalPrestado = prestamosActivos.fold<double>(
      0,
      (total, row) => total + _toDouble(row['monto']),
    );
    final dineroEnCalle = prestamosActivos.fold<double>(
      0,
      (total, row) => total + _toDouble(row['saldo']),
    );
    final dineroRecaudado = cobros.fold<double>(
      0,
      (total, row) => total + _toDouble(row['monto']),
    );
    final gastosTotal = gastos.fold<double>(
      0,
      (total, row) => total + _toDouble(row['valor']),
    );
    final totalPrestadoHoy = prestamosActivos
        .where((row) => row['created_at']?.toString().startsWith(hoy) == true)
        .fold<double>(0, (total, row) => total + _toDouble(row['monto']));
    final totalRecaudadoHoy = cobros
        .where((row) => row['fecha_pago']?.toString().startsWith(hoy) == true)
        .fold<double>(0, (total, row) => total + _toDouble(row['monto']));
    final gastosHoy = gastos
        .where((row) => row['fecha_hora']?.toString().startsWith(hoy) == true)
        .fold<double>(0, (total, row) => total + _toDouble(row['valor']));
    final capitalId = capital == null
        ? null
        : OnlineIdMapper.instance.localIdFor(
            _rowIdRequerido(capital, 'Capital no encontrado.'),
          );

    return CapitalResumen(
      capitalId: capitalId,
      capitalInicial: _toDouble(capital?['monto_inicial']),
      capitalDisponible: _toDouble(capital?['capital_disponible']),
      saldoOperativoCobradores: saldoOperativo,
      capitalPrestado: capitalPrestado,
      dineroEnCalle: dineroEnCalle,
      dineroRecaudado: dineroRecaudado,
      ganancias: dineroRecaudado - gastosTotal,
      gastos: gastosTotal,
      saldoDistribuidoHoy: 0,
      totalPrestadoHoy: totalPrestadoHoy,
      totalRecaudadoHoy: totalRecaudadoHoy,
      gastosHoy: gastosHoy,
    );
  }

  CajaResumenDiario _emptyResumenDiario({
    required int cobradorId,
    required String nombre,
    double saldoDisponible = 0,
  }) {
    return CajaResumenDiario(
      cobradorId: cobradorId,
      nombre: nombre,
      estadoCaja: CajaEstados.cerrada,
      saldoInicial: 0,
      saldoDisponible: saldoDisponible,
      totalPrestado: 0,
      totalRecaudado: 0,
      gastos: 0,
      cantidadPrestamos: 0,
      cantidadCobros: 0,
      clientesVisitados: 0,
      cierreRealizado: false,
      cierrePendiente: false,
    );
  }
}

class _CapitalAjuste {
  const _CapitalAjuste({
    required this.capitalId,
    required this.saldoAntes,
    required this.saldoDespues,
  });

  final int capitalId;
  final double saldoAntes;
  final double saldoDespues;
}

double _toDouble(Object? value) => (value as num?)?.toDouble() ?? 0;

DateTime _startOfToday() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

String _dateKey(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

String _timeKey(DateTime value) {
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

String _money(double value) => CurrencyFormatter.pesos(value);
