import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';
import '../../../core/session/session_manager.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../auditoria/data/auditoria_repository.dart';
import '../../caja/data/control_financiero_repository.dart';
import '../../notificaciones/data/notificacion_repository.dart';
import '../../rutas/data/ruta_repository.dart';
import '../models/prestamo_model.dart';

class PrestamoRepository {
  const PrestamoRepository({
    this.auditoriaRepository = const AuditoriaRepository(),
    this.controlFinancieroRepository = const ControlFinancieroRepository(),
    this.notificacionRepository = const NotificacionRepository(),
    this.rutaRepository = const RutaRepository(),
  });

  final AuditoriaRepository auditoriaRepository;
  final ControlFinancieroRepository controlFinancieroRepository;
  final NotificacionRepository notificacionRepository;
  final RutaRepository rutaRepository;

  Future<Database> get _db => DatabaseHelper.instance.database;

  Future<int> crearCalculado({
    required int clienteId,
    required double monto,
    required double interes,
    required int cuotas,
    DateTime? fechaInicio,
  }) async {
    if (cuotas <= 0) {
      throw ArgumentError('El numero de cuotas debe ser mayor a cero.');
    }

    final totalPagar = monto + (monto * interes / 100);
    final cuotaDiaria = totalPagar / cuotas;
    final inicio = fechaInicio ?? DateTime.now();
    final fin = inicio.add(Duration(days: cuotas));

    final prestamo = PrestamoModel(
      clienteId: clienteId,
      monto: monto,
      interes: interes,
      totalPagar: totalPagar,
      cuotas: cuotas,
      cuotaDiaria: cuotaDiaria,
      saldo: totalPagar,
      fechaInicio: inicio,
      fechaFin: fin,
    );

    final db = await _db;
    final usuarioActual = SessionManager.instance.usuarioActual;
    final clientes = await db.query(
      DatabaseTables.clientes,
      columns: ['cobrador_id'],
      where: 'id = ?',
      whereArgs: [clienteId],
      limit: 1,
    );
    if (clientes.isEmpty) throw StateError('El cliente no existe.');
    final cobradorId = clientes.first['cobrador_id'] as int?;
    if (cobradorId == null) {
      throw StateError('El cliente debe tener un cobrador asignado.');
    }
    if (usuarioActual?.esCobrador == true && usuarioActual?.id != cobradorId) {
      throw StateError('No puedes prestar a clientes de otro cobrador.');
    }
    await controlFinancieroRepository.validarCobradorPuedeOperar(cobradorId);

    final id = await db.transaction((txn) async {
      final prestamoId = await txn.insert(
        DatabaseTables.prestamos,
        prestamo.toMap(),
      );
      await controlFinancieroRepository.descontarPorPrestamo(
        txn: txn,
        cobradorId: cobradorId,
        clienteId: clienteId,
        monto: monto,
        prestamoId: prestamoId,
      );
      return prestamoId;
    });
    await auditoriaRepository.registrar(
      accion: 'crear',
      modulo: 'prestamos',
      referenciaId: id,
      descripcion:
          'Prestamo creado cliente=$clienteId monto=$monto interes=$interes cuotas=$cuotas',
    );
    if (monto >= 1000000) {
      await notificacionRepository.crearParaAdmins(
        titulo: 'Prestamo de alto valor',
        mensaje:
            'Se registro un prestamo por ${CurrencyFormatter.pesos(monto)} para cliente $clienteId.',
        tipo: NotificacionTipos.advertencia,
        modulo: 'prestamos',
        referenciaId: id,
      );
    }
    await rutaRepository.agregarClienteARutaDelCobrador(
      cobradorId: cobradorId,
      clienteId: clienteId,
    );
    return id;
  }

  Future<List<PrestamoModel>> listar({int? clienteId}) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseTables.prestamos,
      where: clienteId == null ? null : 'cliente_id = ?',
      whereArgs: clienteId == null ? null : [clienteId],
      orderBy: 'fecha_inicio DESC',
    );

    return rows.map(PrestamoModel.fromMap).toList();
  }

  Future<List<PrestamoModel>> listarPorCobrador(int cobradorId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT p.*
      FROM ${DatabaseTables.prestamos} p
      INNER JOIN ${DatabaseTables.clientes} c ON c.id = p.cliente_id
      WHERE c.cobrador_id = ?
      ORDER BY p.fecha_inicio DESC
      ''',
      [cobradorId],
    );

    return rows.map(PrestamoModel.fromMap).toList();
  }

  Future<List<PrestamoModel>> listarActivos({int? cobradorId}) async {
    final db = await _db;

    if (cobradorId == null) {
      final rows = await db.query(
        DatabaseTables.prestamos,
        where: 'estado IN (?, ?)',
        whereArgs: [AppEstados.activo, AppEstados.atrasado],
        orderBy: 'fecha_inicio DESC',
      );
      return rows.map(PrestamoModel.fromMap).toList();
    }

    final rows = await db.rawQuery(
      '''
      SELECT p.*
      FROM ${DatabaseTables.prestamos} p
      INNER JOIN ${DatabaseTables.clientes} c ON c.id = p.cliente_id
      WHERE p.estado IN (?, ?) AND c.cobrador_id = ?
      ORDER BY p.fecha_inicio DESC
      ''',
      [AppEstados.activo, AppEstados.atrasado, cobradorId],
    );

    return rows.map(PrestamoModel.fromMap).toList();
  }

  Future<PrestamoModel?> buscarPorId(int id) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseTables.prestamos,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return PrestamoModel.fromMap(rows.first);
  }

  Future<int> actualizar(PrestamoModel prestamo) async {
    final db = await _db;
    final result = await db.update(
      DatabaseTables.prestamos,
      prestamo.toMap(),
      where: 'id = ?',
      whereArgs: [prestamo.id],
    );
    await auditoriaRepository.registrar(
      accion: 'actualizar',
      modulo: 'prestamos',
      referenciaId: prestamo.id,
      descripcion: 'Prestamo actualizado',
    );
    return result;
  }

  Future<int> cancelar(int id) async {
    final db = await _db;
    final result = await db.update(
      DatabaseTables.prestamos,
      {'estado': AppEstados.cancelado},
      where: 'id = ?',
      whereArgs: [id],
    );
    await auditoriaRepository.registrar(
      accion: 'cancelar',
      modulo: 'prestamos',
      referenciaId: id,
      descripcion: 'Prestamo cancelado',
    );
    return result;
  }

  Future<int> cambiarEstado(int id, String estado) async {
    final db = await _db;
    final result = await db.update(
      DatabaseTables.prestamos,
      {'estado': estado},
      where: 'id = ?',
      whereArgs: [id],
    );
    await auditoriaRepository.registrar(
      accion: 'cambiar_estado',
      modulo: 'prestamos',
      referenciaId: id,
      descripcion: 'Prestamo cambio estado a $estado',
    );
    return result;
  }
}
