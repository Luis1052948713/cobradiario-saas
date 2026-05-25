import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';
import '../../auditoria/data/auditoria_repository.dart';
import '../models/cliente_model.dart';

class ClienteRepository {
  const ClienteRepository({this.auditoriaRepository = const AuditoriaRepository()});

  final AuditoriaRepository auditoriaRepository;

  Future<Database> get _db => DatabaseHelper.instance.database;

  Future<int> crear(ClienteModel cliente) async {
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
}
