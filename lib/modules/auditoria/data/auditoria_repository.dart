import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';
import '../../../core/session/session_manager.dart';
import '../models/auditoria_model.dart';

class AuditoriaRepository {
  const AuditoriaRepository();

  Future<Database> get _db => DatabaseHelper.instance.database;

  Future<int> registrar({
    required String accion,
    required String modulo,
    required String descripcion,
    int? referenciaId,
    int? usuarioId,
  }) async {
    final db = await _db;
    return db.insert(
      DatabaseTables.auditoria,
      AuditoriaModel(
        usuarioId: usuarioId ?? SessionManager.instance.usuarioActual?.id,
        accion: accion,
        modulo: modulo,
        descripcion: descripcion,
        referenciaId: referenciaId,
        fechaHora: DateTime.now(),
      ).toMap(),
    );
  }

  Future<List<AuditoriaModel>> listar({int? usuarioId}) async {
    final db = await _db;
    final rows = await db.query(
      DatabaseTables.auditoria,
      where: usuarioId == null ? null : 'usuario_id = ?',
      whereArgs: usuarioId == null ? null : [usuarioId],
      orderBy: 'fecha_hora DESC',
      limit: 300,
    );

    return rows.map(AuditoriaModel.fromMap).toList();
  }
}
