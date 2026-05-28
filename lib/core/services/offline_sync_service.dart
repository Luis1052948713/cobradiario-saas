import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../modules/caja/data/control_financiero_repository.dart';
import '../constants/app_constants.dart';
import '../database/database_helper.dart';
import '../database/database_tables.dart';
import '../session/session_manager.dart';
import 'online_id_mapper.dart';
import 'supabase_service.dart';

class OfflineSyncService {
  OfflineSyncService._internal();

  static final OfflineSyncService instance = OfflineSyncService._internal();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _sincronizando = false;

  static Future<void> encolarCobro({
    required DatabaseExecutor executor,
    required int cobroId,
    required Map<String, Object?> payload,
  }) async {
    await executor.insert(DatabaseTables.syncQueue, {
      'tabla': DatabaseTables.cobros,
      'accion': 'insert',
      'referencia_id': cobroId,
      'payload': jsonEncode(payload),
      'estado': 'pendiente',
      'intentos': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> encolarCliente({
    required DatabaseExecutor executor,
    required String accion,
    required int clienteId,
    required Map<String, Object?> payload,
  }) async {
    await executor.insert(DatabaseTables.syncQueue, {
      'tabla': DatabaseTables.clientes,
      'accion': accion,
      'referencia_id': clienteId,
      'payload': jsonEncode(payload),
      'estado': 'pendiente',
      'intentos': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  void iniciarSincronizacionAutomatica() {
    if (kIsWeb) return;

    if (_connectivitySubscription != null) return;

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      resultados,
    ) async {
      if (_tieneConexionBasica(resultados)) {
        await sincronizarPendientes();
      }
    });

    Future.microtask(() async {
      await _sincronizarSiHayConexion();
    });
  }

  Future<void> detenerSincronizacionAutomatica() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  Future<void> _sincronizarSiHayConexion() async {
    if (kIsWeb) return;

    final resultados = await Connectivity().checkConnectivity();

    if (_tieneConexionBasica(resultados)) {
      await sincronizarPendientes();
    }
  }

  bool _tieneConexionBasica(List<ConnectivityResult> resultados) {
    if (resultados.isEmpty) return false;

    return resultados.any((item) => item != ConnectivityResult.none);
  }

  Future<int> pendientesCount() async {
    if (kIsWeb) return 0;

    final db = await DatabaseHelper.instance.database;

    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM ${DatabaseTables.syncQueue}
      WHERE estado IN (?, ?)
      ''',
      ['pendiente', 'error'],
    );

    return (rows.first['total'] as int?) ?? 0;
  }

  Future<void> sincronizarPendientes({int limit = 50}) async {
    if (kIsWeb) return;

    if (_sincronizando) return;

    if (!_puedeSincronizar) return;

    _sincronizando = true;

    try {
      await OnlineIdMapper.instance.hydrateFromLocalDatabase();

      final db = await DatabaseHelper.instance.database;

      final rows = await db.query(
        DatabaseTables.syncQueue,
        where: 'estado IN (?, ?)',
        whereArgs: ['pendiente', 'error'],
        orderBy: 'created_at ASC',
        limit: limit,
      );

      for (final row in rows) {
        await _sincronizarEvento(db, row);
      }
    } finally {
      _sincronizando = false;
    }
  }

  bool get _puedeSincronizar {
    return SupabaseService.isInitialized &&
        SessionManager.instance.perfilActual?.companyId != null;
  }

  Future<void> _sincronizarEvento(Database db, Map<String, Object?> row) async {
    final id = row['id'] as int;

    try {
      final tabla = row['tabla'] as String;
      final accion = row['accion'] as String;

      if (tabla == DatabaseTables.cobros && accion == 'insert') {
        await _sincronizarCobro(row).timeout(const Duration(seconds: 15));
      } else if (tabla == DatabaseTables.clientes && accion == 'insert') {
        await _sincronizarClienteInsert(
          db,
          row,
        ).timeout(const Duration(seconds: 15));
      } else if (tabla == DatabaseTables.clientes && accion == 'update') {
        await _sincronizarClienteUpdate(
          row,
        ).timeout(const Duration(seconds: 15));
      } else if (tabla == DatabaseTables.clientes &&
          accion == 'asignar_cobrador') {
        await _sincronizarClienteAsignarCobrador(
          row,
        ).timeout(const Duration(seconds: 15));
      } else if (tabla == DatabaseTables.clientes && accion == 'desactivar') {
        await _sincronizarClienteDesactivar(
          row,
        ).timeout(const Duration(seconds: 15));
      } else {
        throw StateError(
          'Evento de sincronizacion no soportado todavia: $tabla/$accion',
        );
      }

      await db.update(
        DatabaseTables.syncQueue,
        {
          'estado': 'sincronizado',
          'error': null,
          'synced_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (error) {
      final intentos = ((row['intentos'] as int?) ?? 0) + 1;

      await db.update(
        DatabaseTables.syncQueue,
        {'estado': 'error', 'intentos': intentos, 'error': error.toString()},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> _sincronizarClienteInsert(
    Database db,
    Map<String, Object?> row,
  ) async {
    final perfil = SessionManager.instance.perfilActual!;
    final payload =
        jsonDecode(row['payload'] as String) as Map<String, dynamic>;
    final localId = row['referencia_id'] as int?;

    if (localId == null) {
      throw StateError('Cliente local sin referencia_id.');
    }

    final cobradorLocalId = payload['cobrador_id'] as int?;
    final cobradorUuid = OnlineIdMapper.instance.uuidFor(
      cobradorLocalId,
      tabla: DatabaseTables.usuarios,
    );

    final inserted = await SupabaseService.requireClient
        .from('clientes')
        .insert({
          'empresa_id': perfil.companyId,
          'nombre': payload['nombre'],
          'cedula': payload['cedula'],
          'telefono': payload['telefono'],
          'direccion': payload['direccion'],
          'barrio': payload['barrio'],
          'referencia': payload['referencia'],
          'foto_url': payload['foto'],
          'cobrador_id': cobradorUuid,
          'latitud': payload['latitud'],
          'longitud': payload['longitud'],
          'estado': payload['estado'] ?? AppEstados.activo,
          'created_at': payload['fecha_registro'],
        })
        .select('id')
        .single();

    final uuid = inserted['id'] as String;

    await OnlineIdMapper.instance.rememberPersisted(
      tabla: DatabaseTables.clientes,
      uuid: uuid,
      localId: localId,
      executor: db,
    );
  }

  Future<void> _sincronizarClienteUpdate(Map<String, Object?> row) async {
    final payload =
        jsonDecode(row['payload'] as String) as Map<String, dynamic>;
    final localId = row['referencia_id'] as int?;

    if (localId == null) {
      throw StateError('Cliente local sin referencia_id.');
    }

    final uuid = OnlineIdMapper.instance.uuidFor(
      localId,
      tabla: DatabaseTables.clientes,
    );

    if (uuid == null) {
      throw StateError('Cliente online no encontrado para actualizar.');
    }

    final cobradorLocalId = payload['cobrador_id'] as int?;
    final cobradorUuid = OnlineIdMapper.instance.uuidFor(
      cobradorLocalId,
      tabla: DatabaseTables.usuarios,
    );

    await SupabaseService.requireClient
        .from('clientes')
        .update({
          'nombre': payload['nombre'],
          'cedula': payload['cedula'],
          'telefono': payload['telefono'],
          'direccion': payload['direccion'],
          'barrio': payload['barrio'],
          'referencia': payload['referencia'],
          'foto_url': payload['foto'],
          'cobrador_id': cobradorUuid,
          'latitud': payload['latitud'],
          'longitud': payload['longitud'],
          'estado': payload['estado'] ?? AppEstados.activo,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', uuid);
  }

  Future<void> _sincronizarClienteAsignarCobrador(
    Map<String, Object?> row,
  ) async {
    final payload =
        jsonDecode(row['payload'] as String) as Map<String, dynamic>;
    final localId = row['referencia_id'] as int?;

    if (localId == null) {
      throw StateError('Cliente local sin referencia_id.');
    }

    final clienteUuid = OnlineIdMapper.instance.uuidFor(
      localId,
      tabla: DatabaseTables.clientes,
    );

    final cobradorLocalId = payload['cobrador_id'] as int?;
    final cobradorUuid = OnlineIdMapper.instance.uuidFor(
      cobradorLocalId,
      tabla: DatabaseTables.usuarios,
    );

    if (clienteUuid == null || cobradorUuid == null) {
      throw StateError('Cliente o cobrador online no encontrado.');
    }

    await SupabaseService.requireClient
        .from('clientes')
        .update({
          'cobrador_id': cobradorUuid,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', clienteUuid);
  }

  Future<void> _sincronizarClienteDesactivar(Map<String, Object?> row) async {
    final localId = row['referencia_id'] as int?;

    if (localId == null) {
      throw StateError('Cliente local sin referencia_id.');
    }

    final uuid = OnlineIdMapper.instance.uuidFor(
      localId,
      tabla: DatabaseTables.clientes,
    );

    if (uuid == null) {
      throw StateError('Cliente online no encontrado para desactivar.');
    }

    await SupabaseService.requireClient
        .from('clientes')
        .update({
          'estado': AppEstados.inactivo,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', uuid);
  }

  Future<void> _sincronizarCobro(Map<String, Object?> row) async {
    final perfil = SessionManager.instance.perfilActual!;

    final payload =
        jsonDecode(row['payload'] as String) as Map<String, dynamic>;

    final referenciaId = row['referencia_id'];

    final prestamoId = payload['prestamo_id'] as int;

    final cobradorId = payload['cobrador_id'] as int;

    final monto = (payload['monto'] as num).toDouble();

    final prestamoUuid = OnlineIdMapper.instance.uuidFor(
      prestamoId,
      tabla: DatabaseTables.prestamos,
    );

    final cobradorUuid = OnlineIdMapper.instance.uuidFor(
      cobradorId,
      tabla: DatabaseTables.usuarios,
    );

    if (prestamoUuid == null || cobradorUuid == null) {
      throw StateError('Falta relacion online para prestamo o cobrador.');
    }

    final client = SupabaseService.requireClient;

    final prestamo = await client
        .from('prestamos')
        .select('id, cliente_id, saldo, estado')
        .eq('id', prestamoUuid)
        .single();

    final estado = prestamo['estado'] as String;

    final saldo = (prestamo['saldo'] as num).toDouble();

    if (estado != AppEstados.activo && estado != AppEstados.atrasado) {
      throw StateError('El prestamo online ya no esta activo.');
    }

    if (monto > saldo) {
      throw StateError('El cobro supera el saldo online pendiente.');
    }

    final saldoActual = (saldo - monto).clamp(0, double.infinity).toDouble();

    final nuevoEstado = saldoActual <= 0 ? AppEstados.pagado : estado;

    final inserted = await client
        .from('cobros')
        .insert({
          'empresa_id': perfil.companyId,
          'prestamo_id': prestamoUuid,
          'cobrador_id': cobradorUuid,
          'monto': monto,
          'saldo_anterior': saldo,
          'saldo_actual': saldoActual,
          'observacion': payload['observacion'],
          'fecha_pago': payload['fecha_pago'],
          'estado': payload['estado'] ?? 'registrado',
        })
        .select('id')
        .single();

    await client
        .from('prestamos')
        .update({
          'saldo': saldoActual,
          'estado': nuevoEstado,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', prestamoUuid);

    await const ControlFinancieroRepository().aumentarCobroOnline(
      cobradorId: cobradorId,
      monto: monto,
    );

    await client.from('auditoria').insert({
      'empresa_id': perfil.companyId,
      'usuario_id': perfil.id,
      'accion': monto == 0 ? 'registrar_visita' : 'registrar_cobro',
      'modulo': 'cobros',
      'descripcion':
          'Cobro local=$referenciaId monto=$monto saldo_anterior=$saldo saldo_actual=$saldoActual',
      'metadata': {
        'local_referencia_id': referenciaId,
        'online_cobro_id': inserted['id'],
      },
    });
  }
}
