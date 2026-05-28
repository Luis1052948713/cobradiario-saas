import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';
import '../../../core/services/offline_sync_service.dart';
import '../../../core/services/online_id_mapper.dart';
import '../../../core/services/supabase_service.dart';
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
    if (_usaSupabase) return _registrarCobroOnline(cobro);

    final db = await _db;
    await controlFinancieroRepository.validarCobradorPuedeOperar(
      cobro.cobradorId,
      localOnly: true,
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
      if (_usaSupabase) {
        await OfflineSyncService.encolarCobro(
          executor: txn,
          cobroId: cobroId,
          payload: {
            ...cobroMap,
            'id': cobroId,
            'cliente_id': clienteId,
          },
        );
      }

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
    _sincronizarEnSegundoPlano();
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
    if (_usaSupabase) {
      dynamic query = SupabaseService.requireClient.from('cobros').select();
      final prestamoUuid = OnlineIdMapper.instance.uuidFor(prestamoId);
      final cobradorUuid = OnlineIdMapper.instance.uuidFor(cobradorId);
      if (prestamoUuid != null) query = query.eq('prestamo_id', prestamoUuid);
      if (cobradorUuid != null) query = query.eq('cobrador_id', cobradorUuid);
      final rows = await query.order('fecha_pago', ascending: false);
      return rows.map<CobroModel>(_fromOnline).toList();
    }

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

  void _sincronizarEnSegundoPlano() {
    if (!_usaSupabase) return;
    unawaited(
      OfflineSyncService.instance
          .sincronizarPendientes()
          .catchError((Object error, StackTrace stackTrace) {}),
    );
  }

  bool get _usaSupabase {
    return SupabaseService.isInitialized &&
        SessionManager.instance.perfilActual != null;
  }

  Future<int> _registrarCobroOnline(CobroModel cobro) async {
    final perfil = SessionManager.instance.perfilActual!;
    final prestamoUuid = OnlineIdMapper.instance.uuidFor(cobro.prestamoId);
    final cobradorUuid = OnlineIdMapper.instance.uuidFor(cobro.cobradorId);
    if (prestamoUuid == null || cobradorUuid == null) {
      throw StateError('Falta relacion online para prestamo o cobrador.');
    }

    final prestamo = await SupabaseService.requireClient
        .from('prestamos')
        .select('id, saldo, estado, cliente_id')
        .eq('id', prestamoUuid)
        .single();
    final estado = prestamo['estado'] as String;
    final saldo = (prestamo['saldo'] as num).toDouble();
    if (estado != AppEstados.activo && estado != AppEstados.atrasado) {
      throw StateError('Solo se pueden cobrar prestamos activos o atrasados.');
    }
    if (cobro.monto < 0) {
      throw ArgumentError('El monto del cobro no puede ser negativo.');
    }
    if (cobro.monto > saldo) {
      throw ArgumentError('El cobro no puede superar el saldo pendiente.');
    }

    final saldoActual = (saldo - cobro.monto).clamp(0, double.infinity).toDouble();
    final nuevoEstado = saldoActual <= 0 ? AppEstados.pagado : estado;
    final row = await SupabaseService.requireClient
        .from('cobros')
        .insert({
          'empresa_id': perfil.companyId,
          'prestamo_id': prestamoUuid,
          'cobrador_id': cobradorUuid,
          'monto': cobro.monto,
          'saldo_anterior': saldo,
          'saldo_actual': saldoActual,
          'observacion': cobro.observacion,
          'fecha_pago': cobro.fechaPago.toIso8601String(),
          'estado': cobro.estado,
        })
        .select()
        .single();

    await SupabaseService.requireClient.from('prestamos').update({
      'saldo': saldoActual,
      'estado': nuevoEstado,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', prestamoUuid);

    await controlFinancieroRepository.aumentarCobroOnline(
      cobradorId: cobro.cobradorId,
      monto: cobro.monto,
    );

    final id = OnlineIdMapper.instance.localIdFor(row['id'] as String);
    if (cobro.monto > 0) {
      await notificacionRepository.crear(
        usuarioId: cobro.cobradorId,
        titulo: 'Cobro registrado',
        mensaje: 'Cobro exitoso por ${CurrencyFormatter.pesos(cobro.monto)}.',
        tipo: NotificacionTipos.exito,
        modulo: 'cobros',
        referenciaId: id,
      );
    }
    return id;
  }

  CobroModel _fromOnline(Map<String, dynamic> row) {
    final uuid = row['id'] as String;
    final prestamoUuid = row['prestamo_id'] as String;
    final cobradorUuid = row['cobrador_id'] as String;
    return CobroModel(
      id: OnlineIdMapper.instance.localIdFor(uuid),
      prestamoId: OnlineIdMapper.instance.localIdFor(prestamoUuid),
      cobradorId: OnlineIdMapper.instance.localIdFor(cobradorUuid),
      monto: (row['monto'] as num).toDouble(),
      saldoAnterior: (row['saldo_anterior'] as num?)?.toDouble(),
      saldoActual: (row['saldo_actual'] as num?)?.toDouble(),
      observacion: row['observacion'] as String?,
      fechaPago: DateTime.parse(row['fecha_pago'] as String),
      estado: row['estado'] as String? ?? 'registrado',
    );
  }
}
