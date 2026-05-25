import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';
import '../../../core/session/session_manager.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../caja/data/control_financiero_repository.dart';
import '../../notificaciones/data/notificacion_repository.dart';
import '../models/cobro_model.dart';

class CobroRepository {
  const CobroRepository({
    this.controlFinancieroRepository = const ControlFinancieroRepository(),
    this.notificacionRepository = const NotificacionRepository(),
  });

  final ControlFinancieroRepository controlFinancieroRepository;
  final NotificacionRepository notificacionRepository;

  Future<Database> get _db => DatabaseHelper.instance.database;

  Future<int> registrarCobro(CobroModel cobro) async {
    final db = await _db;
    await controlFinancieroRepository.validarCobradorPuedeOperar(
      cobro.cobradorId,
    );

    final cobroId = await db.transaction((txn) async {
      final prestamos = await txn.query(
        DatabaseTables.prestamos,
        where: 'id = ?',
        whereArgs: [cobro.prestamoId],
        limit: 1,
      );

      if (prestamos.isEmpty) {
        throw StateError('El prestamo no existe.');
      }

      final prestamo = prestamos.first;
      final estado = prestamo['estado'] as String;
      final saldo = (prestamo['saldo'] as num).toDouble();
      final clienteId = prestamo['cliente_id'] as int;

      final clientes = await txn.query(
        DatabaseTables.clientes,
        columns: ['cobrador_id'],
        where: 'id = ?',
        whereArgs: [clienteId],
        limit: 1,
      );

      if (clientes.isEmpty) {
        throw StateError('El cliente del prestamo no existe.');
      }

      final cobradorAsignadoId = clientes.first['cobrador_id'] as int?;
      final usuarioActual = SessionManager.instance.usuarioActual;
      if (usuarioActual?.esCobrador == true) {
        final usuarioActualId = usuarioActual!.id;
        if (usuarioActualId == null ||
            cobro.cobradorId != usuarioActualId ||
            cobradorAsignadoId != usuarioActualId) {
          throw StateError(
            'No puedes cobrar un cliente asignado a otro cobrador.',
          );
        }
      }

      if (estado != AppEstados.activo && estado != AppEstados.atrasado) {
        throw StateError(
          'Solo se pueden cobrar prestamos activos o atrasados.',
        );
      }

      if (cobro.monto < 0) {
        throw ArgumentError('El monto del cobro no puede ser negativo.');
      }

      if (cobro.monto > saldo) {
        throw ArgumentError('El cobro no puede superar el saldo pendiente.');
      }

      final nuevoSaldo = saldo - cobro.monto;
      final nuevoEstado = nuevoSaldo <= 0 ? AppEstados.pagado : estado;
      final saldoActual = nuevoSaldo < 0 ? 0 : nuevoSaldo;
      final cobroMap = cobro.toMap()
        ..['saldo_anterior'] = saldo
        ..['saldo_actual'] = saldoActual;

      final cobroId = await txn.insert(DatabaseTables.cobros, cobroMap);

      await txn.update(
        DatabaseTables.prestamos,
        {'saldo': saldoActual, 'estado': nuevoEstado},
        where: 'id = ?',
        whereArgs: [cobro.prestamoId],
      );

      await txn.insert(DatabaseTables.auditoria, {
        'usuario_id': usuarioActual?.id ?? cobro.cobradorId,
        'accion': cobro.monto == 0 ? 'registrar_visita' : 'registrar_cobro',
        'modulo': 'cobros',
        'descripcion':
            'Cobro prestamo=${cobro.prestamoId} monto=${cobro.monto} saldo_anterior=$saldo saldo_actual=$saldoActual',
        'referencia_id': cobroId,
        'fecha_hora': DateTime.now().toIso8601String(),
      });

      await controlFinancieroRepository.aumentarPorCobro(
        txn: txn,
        cobradorId: cobro.cobradorId,
        clienteId: clienteId,
        monto: cobro.monto,
        cobroId: cobroId,
      );

      return cobroId;
    });
    if (cobro.monto > 0) {
      await notificacionRepository.crear(
        usuarioId: cobro.cobradorId,
        titulo: 'Cobro registrado',
        mensaje: 'Cobro exitoso por ${CurrencyFormatter.pesos(cobro.monto)}.',
        tipo: NotificacionTipos.exito,
        modulo: 'cobros',
        referenciaId: cobroId,
      );
    }
    return cobroId;
  }

  Future<int> marcarVisita({
    required int prestamoId,
    required int cobradorId,
    required String observacion,
    DateTime? fechaPago,
  }) {
    return registrarCobro(
      CobroModel(
        prestamoId: prestamoId,
        cobradorId: cobradorId,
        monto: 0,
        observacion: 'Visita sin pago: $observacion',
        fechaPago: fechaPago ?? DateTime.now(),
      ),
    );
  }

  Future<List<CobroModel>> listar({int? prestamoId, int? cobradorId}) async {
    final db = await _db;
    final whereParts = <String>[];
    final args = <Object?>[];

    if (prestamoId != null) {
      whereParts.add('prestamo_id = ?');
      args.add(prestamoId);
    }

    if (cobradorId != null) {
      whereParts.add('cobrador_id = ?');
      args.add(cobradorId);
    }

    final rows = await db.query(
      DatabaseTables.cobros,
      where: whereParts.isEmpty ? null : whereParts.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'fecha_pago DESC',
    );

    return rows.map(CobroModel.fromMap).toList();
  }
}
