import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';
import '../../../core/services/offline_sync_service.dart';
import '../../../core/services/online_id_mapper.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/session/session_manager.dart';
import '../../auditoria/data/auditoria_repository.dart';
import '../models/cliente_model.dart';

class ClienteRepository {
  const ClienteRepository({
    this.auditoriaRepository = const AuditoriaRepository(),
  });

  final AuditoriaRepository auditoriaRepository;

  Future<Database> get _db => DatabaseHelper.instance.database;

  Future<int> crear(ClienteModel cliente) async {
    if (_usaSupabase) {
      try {
        final id = await _crearOnline(cliente);

        await auditoriaRepository.registrar(
          accion: 'crear',
          modulo: 'clientes',
          referenciaId: id,
          descripcion: 'Cliente creado: ${cliente.nombre}',
        );

        return id;
      } catch (_) {
        return _crearLocalYEncolar(cliente);
      }
    }

    return _crearLocalYEncolar(cliente);
  }

  Future<List<ClienteModel>> listar({int? cobradorId}) async {
    final clientesLocales = await _listarLocal(cobradorId: cobradorId);

    if (!_usaSupabase) {
      return clientesLocales;
    }

    try {
      dynamic query = SupabaseService.requireClient.from('clientes').select();

      final cobradorUuid = OnlineIdMapper.instance.uuidFor(
        cobradorId,
        tabla: DatabaseTables.usuarios,
      );

      if (cobradorUuid != null) {
        query = query.eq('cobrador_id', cobradorUuid);
      }

      final rows = await query
          .order('nombre')
          .timeout(const Duration(seconds: 8));

      final clientesOnline = <ClienteModel>[];

      for (final row in rows) {
        clientesOnline.add(await _fromOnline(row as Map<String, dynamic>));
      }

      await _cacheClientes(clientesOnline);

      return _unirClientesSinDuplicar(
        locales: clientesLocales,
        online: clientesOnline,
      );
    } catch (_) {
      return clientesLocales;
    }
  }

  Future<List<ClienteModel>> buscar(String query, {int? cobradorId}) async {
    final clientesLocales = await _buscarLocal(query, cobradorId: cobradorId);

    if (!_usaSupabase) {
      return clientesLocales;
    }

    try {
      final texto = query.trim();

      dynamic request = SupabaseService.requireClient
          .from('clientes')
          .select()
          .or(
            'nombre.ilike.%$texto%,cedula.ilike.%$texto%,telefono.ilike.%$texto%,barrio.ilike.%$texto%',
          );

      final cobradorUuid = OnlineIdMapper.instance.uuidFor(
        cobradorId,
        tabla: DatabaseTables.usuarios,
      );

      if (cobradorUuid != null) {
        request = request.eq('cobrador_id', cobradorUuid);
      }

      final rows = await request
          .order('nombre')
          .timeout(const Duration(seconds: 8));

      final clientesOnline = <ClienteModel>[];

      for (final row in rows) {
        clientesOnline.add(await _fromOnline(row as Map<String, dynamic>));
      }

      await _cacheClientes(clientesOnline);

      return _unirClientesSinDuplicar(
        locales: clientesLocales,
        online: clientesOnline,
      );
    } catch (_) {
      return clientesLocales;
    }
  }

  Future<ClienteModel?> buscarPorId(int id) async {
    final clienteLocal = await _buscarPorIdLocal(id);

    if (!_usaSupabase) {
      return clienteLocal;
    }

    try {
      final uuid = OnlineIdMapper.instance.uuidFor(
        id,
        tabla: DatabaseTables.clientes,
      );

      if (uuid == null) {
        return clienteLocal;
      }

      final row = await SupabaseService.requireClient
          .from('clientes')
          .select()
          .eq('id', uuid)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (row == null) return clienteLocal;

      final clienteOnline = await _fromOnline(row);

      await _cacheClientes([clienteOnline]);

      return clienteOnline;
    } catch (_) {
      return clienteLocal;
    }
  }

  Future<int> actualizar(ClienteModel cliente) async {
    if (_usaSupabase) {
      try {
        final uuid = OnlineIdMapper.instance.uuidFor(
          cliente.id,
          tabla: DatabaseTables.clientes,
        );

        if (uuid == null) {
          return _actualizarLocalYEncolar(cliente);
        }

        final cobradorUuid = OnlineIdMapper.instance.uuidFor(
          cliente.cobradorId,
          tabla: DatabaseTables.usuarios,
        );

        await SupabaseService.requireClient
            .from('clientes')
            .update({
              'nombre': cliente.nombre,
              'cedula': cliente.cedula,
              'telefono': cliente.telefono,
              'direccion': cliente.direccion,
              'barrio': cliente.barrio,
              'referencia': cliente.referencia,
              'foto_url': cliente.foto,
              'cobrador_id': cobradorUuid,
              'latitud': cliente.latitud,
              'longitud': cliente.longitud,
              'estado': cliente.estado,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', uuid)
            .timeout(const Duration(seconds: 8));

        await _guardarClienteLocal(cliente);

        await auditoriaRepository.registrar(
          accion: 'actualizar',
          modulo: 'clientes',
          referenciaId: cliente.id,
          descripcion: 'Cliente actualizado: ${cliente.nombre}',
        );

        return 1;
      } catch (_) {
        return _actualizarLocalYEncolar(cliente);
      }
    }

    return _actualizarLocalYEncolar(cliente);
  }

  Future<int> asignarCobrador({
    required int clienteId,
    required int cobradorId,
  }) async {
    if (_usaSupabase) {
      try {
        final clienteUuid = OnlineIdMapper.instance.uuidFor(
          clienteId,
          tabla: DatabaseTables.clientes,
        );

        final cobradorUuid = OnlineIdMapper.instance.uuidFor(
          cobradorId,
          tabla: DatabaseTables.usuarios,
        );

        if (clienteUuid == null || cobradorUuid == null) {
          return _asignarCobradorLocalYEncolar(
            clienteId: clienteId,
            cobradorId: cobradorId,
          );
        }

        await SupabaseService.requireClient
            .from('clientes')
            .update({
              'cobrador_id': cobradorUuid,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', clienteUuid)
            .timeout(const Duration(seconds: 8));

        final db = await _db;

        final result = await db.update(
          DatabaseTables.clientes,
          {'cobrador_id': cobradorId},
          where: 'id = ?',
          whereArgs: [clienteId],
        );

        await auditoriaRepository.registrar(
          accion: 'asignar_cobrador',
          modulo: 'clientes',
          referenciaId: clienteId,
          descripcion: 'Cliente asignado al cobrador ID $cobradorId',
        );

        return result;
      } catch (_) {
        return _asignarCobradorLocalYEncolar(
          clienteId: clienteId,
          cobradorId: cobradorId,
        );
      }
    }

    return _asignarCobradorLocalYEncolar(
      clienteId: clienteId,
      cobradorId: cobradorId,
    );
  }

  Future<int> desactivar(int id) async {
    if (_usaSupabase) {
      try {
        final uuid = OnlineIdMapper.instance.uuidFor(
          id,
          tabla: DatabaseTables.clientes,
        );

        if (uuid == null) {
          return _desactivarLocalYEncolar(id);
        }

        await SupabaseService.requireClient
            .from('clientes')
            .update({
              'estado': AppEstados.inactivo,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', uuid)
            .timeout(const Duration(seconds: 8));

        final db = await _db;

        final result = await db.update(
          DatabaseTables.clientes,
          {'estado': AppEstados.inactivo},
          where: 'id = ?',
          whereArgs: [id],
        );

        await auditoriaRepository.registrar(
          accion: 'desactivar',
          modulo: 'clientes',
          referenciaId: id,
          descripcion: 'Cliente desactivado',
        );

        return result;
      } catch (_) {
        return _desactivarLocalYEncolar(id);
      }
    }

    return _desactivarLocalYEncolar(id);
  }

  Future<int> _crearOnline(ClienteModel cliente) async {
    final perfil = SessionManager.instance.perfilActual!;

    final cobradorUuid = OnlineIdMapper.instance.uuidFor(
      cliente.cobradorId,
      tabla: DatabaseTables.usuarios,
    );

    final row = await SupabaseService.requireClient
        .from('clientes')
        .insert({
          'empresa_id': perfil.companyId,
          'nombre': cliente.nombre,
          'cedula': cliente.cedula,
          'telefono': cliente.telefono,
          'direccion': cliente.direccion,
          'barrio': cliente.barrio,
          'referencia': cliente.referencia,
          'foto_url': cliente.foto,
          'cobrador_id': cobradorUuid,
          'latitud': cliente.latitud,
          'longitud': cliente.longitud,
          'estado': cliente.estado,
          'created_at': cliente.fechaRegistro.toIso8601String(),
        })
        .select()
        .single()
        .timeout(const Duration(seconds: 8));

    final uuid = row['id'] as String;

    final localId = OnlineIdMapper.instance.localIdFor(
      uuid,
      tabla: DatabaseTables.clientes,
    );

    await OnlineIdMapper.instance.rememberPersisted(
      tabla: DatabaseTables.clientes,
      uuid: uuid,
      localId: localId,
    );

    final clienteLocal = cliente.copyWith(id: localId);

    await _guardarClienteLocal(clienteLocal);

    return localId;
  }

  Future<int> _crearLocalYEncolar(ClienteModel cliente) async {
    final db = await _db;

    final id = await db.transaction((txn) async {
      final localId = await txn.insert(
        DatabaseTables.clientes,
        cliente.toMap()..remove('id'),
      );

      await OfflineSyncService.encolarCliente(
        executor: txn,
        accion: 'insert',
        clienteId: localId,
        payload: _payloadCliente(cliente.copyWith(id: localId)),
      );

      return localId;
    });

    await auditoriaRepository.registrar(
      accion: 'crear',
      modulo: 'clientes',
      referenciaId: id,
      descripcion: 'Cliente creado: ${cliente.nombre}',
    );

    return id;
  }

  Future<int> _actualizarLocalYEncolar(ClienteModel cliente) async {
    final db = await _db;

    final result = await db.transaction((txn) async {
      final updated = await txn.update(
        DatabaseTables.clientes,
        cliente.toMap(),
        where: 'id = ?',
        whereArgs: [cliente.id],
      );

      final id = cliente.id;

      if (id != null) {
        await OfflineSyncService.encolarCliente(
          executor: txn,
          accion: 'update',
          clienteId: id,
          payload: _payloadCliente(cliente),
        );
      }

      return updated;
    });

    await auditoriaRepository.registrar(
      accion: 'actualizar',
      modulo: 'clientes',
      referenciaId: cliente.id,
      descripcion: 'Cliente actualizado: ${cliente.nombre}',
    );

    return result;
  }

  Future<int> _asignarCobradorLocalYEncolar({
    required int clienteId,
    required int cobradorId,
  }) async {
    final db = await _db;

    final result = await db.transaction((txn) async {
      final updated = await txn.update(
        DatabaseTables.clientes,
        {'cobrador_id': cobradorId},
        where: 'id = ?',
        whereArgs: [clienteId],
      );

      await OfflineSyncService.encolarCliente(
        executor: txn,
        accion: 'asignar_cobrador',
        clienteId: clienteId,
        payload: {'cobrador_id': cobradorId},
      );

      return updated;
    });

    await auditoriaRepository.registrar(
      accion: 'asignar_cobrador',
      modulo: 'clientes',
      referenciaId: clienteId,
      descripcion: 'Cliente asignado al cobrador ID $cobradorId',
    );

    return result;
  }

  Future<int> _desactivarLocalYEncolar(int id) async {
    final db = await _db;

    final result = await db.transaction((txn) async {
      final updated = await txn.update(
        DatabaseTables.clientes,
        {'estado': AppEstados.inactivo},
        where: 'id = ?',
        whereArgs: [id],
      );

      await OfflineSyncService.encolarCliente(
        executor: txn,
        accion: 'desactivar',
        clienteId: id,
        payload: {'estado': AppEstados.inactivo},
      );

      return updated;
    });

    await auditoriaRepository.registrar(
      accion: 'desactivar',
      modulo: 'clientes',
      referenciaId: id,
      descripcion: 'Cliente desactivado',
    );

    return result;
  }

  Future<List<ClienteModel>> _listarLocal({int? cobradorId}) async {
    final db = await _db;

    final rows = await db.query(
      DatabaseTables.clientes,
      where: cobradorId == null ? null : 'cobrador_id = ?',
      whereArgs: cobradorId == null ? null : [cobradorId],
      orderBy: 'nombre ASC',
    );

    return rows.map(ClienteModel.fromMap).toList();
  }

  Future<List<ClienteModel>> _buscarLocal(
    String query, {
    int? cobradorId,
  }) async {
    final db = await _db;

    final likeQuery = '%${query.trim()}%';

    final where = StringBuffer(
      '(nombre LIKE ? OR cedula LIKE ? OR telefono LIKE ? OR barrio LIKE ?)',
    );

    final args = <Object?>[likeQuery, likeQuery, likeQuery, likeQuery];

    if (cobradorId != null) {
      where.write(' AND cobrador_id = ?');
      args.add(cobradorId);
    }

    final rows = await db.query(
      DatabaseTables.clientes,
      where: where.toString(),
      whereArgs: args,
      orderBy: 'nombre ASC',
    );

    return rows.map(ClienteModel.fromMap).toList();
  }

  Future<ClienteModel?> _buscarPorIdLocal(int id) async {
    final db = await _db;

    final rows = await db.query(
      DatabaseTables.clientes,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    return ClienteModel.fromMap(rows.first);
  }

  Future<void> _guardarClienteLocal(ClienteModel cliente) async {
    if (kIsWeb) return;

    final id = cliente.id;

    if (id == null) return;

    final db = await _db;

    await db.insert(
      DatabaseTables.clientes,
      cliente.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );

    await db.update(
      DatabaseTables.clientes,
      cliente.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<ClienteModel> _fromOnline(Map<String, dynamic> row) async {
    final uuid = row['id'] as String;

    final cobradorUuid = row['cobrador_id'] as String?;

    final id = OnlineIdMapper.instance.localIdFor(
      uuid,
      tabla: DatabaseTables.clientes,
    );

    await OnlineIdMapper.instance.rememberPersisted(
      tabla: DatabaseTables.clientes,
      uuid: uuid,
      localId: id,
    );

    int? cobradorId;

    if (cobradorUuid != null) {
      cobradorId = OnlineIdMapper.instance.localIdFor(
        cobradorUuid,
        tabla: DatabaseTables.usuarios,
      );

      await OnlineIdMapper.instance.rememberPersisted(
        tabla: DatabaseTables.usuarios,
        uuid: cobradorUuid,
        localId: cobradorId,
      );
    }

    return ClienteModel(
      id: id,
      nombre: row['nombre'] as String? ?? '',
      cedula: row['cedula'] as String?,
      telefono: row['telefono'] as String?,
      direccion: row['direccion'] as String?,
      barrio: row['barrio'] as String?,
      referencia: row['referencia'] as String?,
      foto: row['foto_url'] as String?,
      cobradorId: cobradorId,
      latitud: (row['latitud'] as num?)?.toDouble(),
      longitud: (row['longitud'] as num?)?.toDouble(),
      estado: row['estado'] as String? ?? AppEstados.activo,
      fechaRegistro: row['created_at'] == null
          ? DateTime.now()
          : DateTime.parse(row['created_at'] as String),
    );
  }

  Future<void> _cacheClientes(List<ClienteModel> clientes) async {
    if (kIsWeb) return;

    if (clientes.isEmpty) return;

    final db = await _db;

    for (final cliente in clientes) {
      final id = cliente.id;

      if (id == null) continue;

      try {
        await db.insert(
          DatabaseTables.clientes,
          cliente.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );

        await db.update(
          DatabaseTables.clientes,
          cliente.toMap(),
          where: 'id = ?',
          whereArgs: [id],
        );
      } on DatabaseException {
        // Si falta una relacion local, no bloqueamos la lectura online.
      }
    }
  }

  Map<String, Object?> _payloadCliente(ClienteModel cliente) {
    return {
      'id': cliente.id,
      'nombre': cliente.nombre,
      'cedula': cliente.cedula,
      'telefono': cliente.telefono,
      'direccion': cliente.direccion,
      'barrio': cliente.barrio,
      'referencia': cliente.referencia,
      'foto': cliente.foto,
      'cobrador_id': cliente.cobradorId,
      'latitud': cliente.latitud,
      'longitud': cliente.longitud,
      'estado': cliente.estado,
      'fecha_registro': cliente.fechaRegistro.toIso8601String(),
    };
  }

  List<ClienteModel> _unirClientesSinDuplicar({
    required List<ClienteModel> locales,
    required List<ClienteModel> online,
  }) {
    final Map<int, ClienteModel> resultado = {};

    for (final cliente in online) {
      final id = cliente.id;

      if (id != null) {
        resultado[id] = cliente;
      }
    }

    for (final cliente in locales) {
      final id = cliente.id;

      if (id != null) {
        resultado[id] = cliente;
      }
    }

    final lista = resultado.values.toList();

    lista.sort(
      (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
    );

    return lista;
  }

  bool get _usaSupabase {
    return SupabaseService.isInitialized &&
        SessionManager.instance.perfilActual != null;
  }
}
