import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';
import '../../../core/services/online_id_mapper.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/session/session_manager.dart';
import '../../auditoria/data/auditoria_repository.dart';
import '../models/cliente_model.dart';

class ClienteRepository {
  const ClienteRepository({this.auditoriaRepository = const AuditoriaRepository()});

  final AuditoriaRepository auditoriaRepository;

  Future<Database> get _db => DatabaseHelper.instance.database;

  Future<int> crear(ClienteModel cliente) async {
    if (_usaSupabase) {
      final perfil = SessionManager.instance.perfilActual!;
      final cobradorUuid = OnlineIdMapper.instance.uuidFor(cliente.cobradorId);
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
          .single();
      final id = OnlineIdMapper.instance.localIdFor(row['id'] as String);
      await auditoriaRepository.registrar(
        accion: 'crear',
        modulo: 'clientes',
        referenciaId: id,
        descripcion: 'Cliente creado: ${cliente.nombre}',
      );
      return id;
    }

    final db = await _db;
    final id = await db.insert(DatabaseTables.clientes, cliente.toMap());
    await auditoriaRepository.registrar(
      accion: 'crear',
      modulo: 'clientes',
      referenciaId: id,
      descripcion: 'Cliente creado: ${cliente.nombre}',
    );
    return id;
  }

  Future<List<ClienteModel>> listar({int? cobradorId}) async {
    if (_usaSupabase) {
      dynamic query = SupabaseService.requireClient.from('clientes').select();
      final cobradorUuid = OnlineIdMapper.instance.uuidFor(cobradorId);
      if (cobradorUuid != null) query = query.eq('cobrador_id', cobradorUuid);
      final rows = await query.order('nombre');
      return rows.map<ClienteModel>(_fromOnline).toList();
    }

    final db = await _db;
    final rows = await db.query(
      DatabaseTables.clientes,
      where: cobradorId == null ? null : 'cobrador_id = ?',
      whereArgs: cobradorId == null ? null : [cobradorId],
      orderBy: 'nombre ASC',
    );

    return rows.map(ClienteModel.fromMap).toList();
  }

  Future<List<ClienteModel>> buscar(String query, {int? cobradorId}) async {
    if (_usaSupabase) {
      final texto = query.trim();
      dynamic request = SupabaseService.requireClient
          .from('clientes')
          .select()
          .or('nombre.ilike.%$texto%,cedula.ilike.%$texto%,telefono.ilike.%$texto%,barrio.ilike.%$texto%');
      final cobradorUuid = OnlineIdMapper.instance.uuidFor(cobradorId);
      if (cobradorUuid != null) request = request.eq('cobrador_id', cobradorUuid);
      final rows = await request.order('nombre');
      return rows.map<ClienteModel>(_fromOnline).toList();
    }

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

  Future<ClienteModel?> buscarPorId(int id) async {
    if (_usaSupabase) {
      final uuid = OnlineIdMapper.instance.uuidFor(id);
      if (uuid == null) return null;
      final row = await SupabaseService.requireClient
          .from('clientes')
          .select()
          .eq('id', uuid)
          .maybeSingle();
      if (row == null) return null;
      return _fromOnline(row);
    }

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

  Future<int> actualizar(ClienteModel cliente) async {
    if (_usaSupabase) {
      final uuid = OnlineIdMapper.instance.uuidFor(cliente.id);
      if (uuid == null) throw StateError('Cliente online no encontrado.');
      final cobradorUuid = OnlineIdMapper.instance.uuidFor(cliente.cobradorId);
      await SupabaseService.requireClient.from('clientes').update({
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
      }).eq('id', uuid);
      await auditoriaRepository.registrar(
        accion: 'actualizar',
        modulo: 'clientes',
        referenciaId: cliente.id,
        descripcion: 'Cliente actualizado: ${cliente.nombre}',
      );
      return 1;
    }

    final db = await _db;
    final result = await db.update(
      DatabaseTables.clientes,
      cliente.toMap(),
      where: 'id = ?',
      whereArgs: [cliente.id],
    );
    await auditoriaRepository.registrar(
      accion: 'actualizar',
      modulo: 'clientes',
      referenciaId: cliente.id,
      descripcion: 'Cliente actualizado: ${cliente.nombre}',
    );
    return result;
  }

  Future<int> asignarCobrador({
    required int clienteId,
    required int cobradorId,
  }) async {
    if (_usaSupabase) {
      final clienteUuid = OnlineIdMapper.instance.uuidFor(clienteId);
      final cobradorUuid = OnlineIdMapper.instance.uuidFor(cobradorId);
      if (clienteUuid == null || cobradorUuid == null) {
        throw StateError('Cliente o cobrador online no encontrado.');
      }
      await SupabaseService.requireClient
          .from('clientes')
          .update({'cobrador_id': cobradorUuid}).eq('id', clienteUuid);
      await auditoriaRepository.registrar(
        accion: 'asignar_cobrador',
        modulo: 'clientes',
        referenciaId: clienteId,
        descripcion: 'Cliente asignado al cobrador ID $cobradorId',
      );
      return 1;
    }

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
  }

  Future<int> desactivar(int id) async {
    if (_usaSupabase) {
      final uuid = OnlineIdMapper.instance.uuidFor(id);
      if (uuid == null) throw StateError('Cliente online no encontrado.');
      await SupabaseService.requireClient
          .from('clientes')
          .update({'estado': AppEstados.inactivo}).eq('id', uuid);
      await auditoriaRepository.registrar(
        accion: 'desactivar',
        modulo: 'clientes',
        referenciaId: id,
        descripcion: 'Cliente desactivado',
      );
      return 1;
    }

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
  }

  bool get _usaSupabase {
    return SupabaseService.isInitialized &&
        SessionManager.instance.perfilActual?.companyId != null;
  }

  ClienteModel _fromOnline(Map<String, dynamic> row) {
    final uuid = row['id'] as String;
    final cobradorUuid = row['cobrador_id'] as String?;
    return ClienteModel(
      id: OnlineIdMapper.instance.localIdFor(uuid),
      nombre: row['nombre'] as String? ?? '',
      cedula: row['cedula'] as String?,
      telefono: row['telefono'] as String?,
      direccion: row['direccion'] as String?,
      barrio: row['barrio'] as String?,
      referencia: row['referencia'] as String?,
      foto: row['foto_url'] as String?,
      cobradorId: cobradorUuid == null
          ? null
          : OnlineIdMapper.instance.localIdFor(cobradorUuid),
      latitud: (row['latitud'] as num?)?.toDouble(),
      longitud: (row['longitud'] as num?)?.toDouble(),
      estado: row['estado'] as String? ?? AppEstados.activo,
      fechaRegistro: row['created_at'] == null
          ? DateTime.now()
          : DateTime.parse(row['created_at'] as String),
    );
  }
}
