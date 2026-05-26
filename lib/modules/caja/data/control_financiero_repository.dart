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
    if (_usaSupabase) return [];

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

  Future<void> validarCobradorPuedeOperar(int cobradorId) async {
    final db = await _db;
    final hoy = _dateKey(DateTime.now());
    final cajaAbierta = await cajaAbiertaDeCobrador(cobradorId);
    if (cajaAbierta == null) {
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

  Future<void> registrarGasto({
    required int cobradorId,
    required String tipo,
    required double valor,
    String? descripcion,
  }) async {
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
      return cobradores.map<CajaResumenDiario>((row) {
        final id = OnlineIdMapper.instance.localIdFor(row['id'] as String);
        return _emptyResumenDiario(
          cobradorId: id,
          nombre: row['nombre'] as String? ?? 'Cobrador',
          saldoDisponible:
              (row['saldo_disponible'] as num?)?.toDouble() ?? 0,
        );
      }).toList();
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
      final uuid = OnlineIdMapper.instance.uuidFor(cobradorId);
      if (uuid == null) {
        return _emptyResumenDiario(cobradorId: cobradorId, nombre: 'Cobrador');
      }
      final row = await SupabaseService.requireClient
          .from('perfiles')
          .select('nombre, saldo_disponible')
          .eq('id', uuid)
          .maybeSingle();
      return _emptyResumenDiario(
        cobradorId: cobradorId,
        nombre: row?['nombre'] as String? ?? 'Cobrador',
        saldoDisponible: (row?['saldo_disponible'] as num?)?.toDouble() ?? 0,
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
    if (_usaSupabase) return [];

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
    if (_usaSupabase) return [];

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
      return rows.map<Map<String, Object?>>((row) {
        return {
          'id': OnlineIdMapper.instance.localIdFor(row['id'] as String),
          'cobrador_id': OnlineIdMapper.instance.localIdFor(
            row['cobrador_id'] as String,
          ),
          'cobrador_nombre': 'Cobrador',
          'estado': row['estado'],
          'saldo_inicial': row['saldo_inicial'],
          'saldo_actual': row['saldo_actual'],
          'fecha': row['fecha'],
          'hora_apertura': row['hora_apertura'],
          'hora_cierre': row['hora_cierre'],
        };
      }).toList();
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
    if (_usaSupabase) return [];

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
      dynamic query = SupabaseService.requireClient
          .from('gastos')
          .select();
      final cobradorUuid = OnlineIdMapper.instance.uuidFor(cobradorId);
      if (cobradorUuid != null) query = query.eq('cobrador_id', cobradorUuid);
      final rows = await query.order('fecha_hora', ascending: false);
      return rows.map<Map<String, Object?>>((row) {
        return {
          'id': OnlineIdMapper.instance.localIdFor(row['id'] as String),
          'cobrador_id': OnlineIdMapper.instance.localIdFor(
            row['cobrador_id'] as String,
          ),
          'cobrador_nombre': 'Cobrador',
          'tipo': row['tipo'],
          'valor': row['valor'],
          'descripcion': row['descripcion'],
          'fecha_hora': row['fecha_hora'],
        };
      }).toList();
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
    final db = await _db;
    return db.query(
      DatabaseTables.cierresCaja,
      where: 'cobrador_id = ?',
      whereArgs: [cobradorId],
      orderBy: 'fecha_hora DESC',
      limit: 50,
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

  bool get _usaSupabase {
    return SupabaseService.isInitialized &&
        SessionManager.instance.perfilActual?.companyId != null;
  }

  CapitalResumen _capitalResumenOnline() {
    return const CapitalResumen(
      capitalId: null,
      capitalInicial: 0,
      capitalDisponible: 0,
      saldoOperativoCobradores: 0,
      capitalPrestado: 0,
      dineroEnCalle: 0,
      dineroRecaudado: 0,
      ganancias: 0,
      gastos: 0,
      saldoDistribuidoHoy: 0,
      totalPrestadoHoy: 0,
      totalRecaudadoHoy: 0,
      gastosHoy: 0,
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
