import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';
import '../../../core/session/session_manager.dart';
import '../models/notificacion_model.dart';

class NotificacionRepository {
  const NotificacionRepository();

  Future<Database> get _db => DatabaseHelper.instance.database;

  Future<int> crear({
    int? usuarioId,
    required String titulo,
    required String mensaje,
    required String tipo,
    String? modulo,
    int? referenciaId,
  }) async {
    final db = await _db;
    return db.insert(
      DatabaseTables.notificaciones,
      NotificacionModel(
        usuarioId: usuarioId,
        titulo: titulo,
        mensaje: mensaje,
        tipo: tipo,
        modulo: modulo,
        referenciaId: referenciaId,
        fechaHora: DateTime.now(),
      ).toMap(),
    );
  }

  Future<void> crearParaAdmins({
    required String titulo,
    required String mensaje,
    required String tipo,
    String? modulo,
    int? referenciaId,
  }) async {
    final db = await _db;
    final admins = await db.query(
      DatabaseTables.usuarios,
      columns: ['id'],
      where: 'rol = ? AND estado = ? AND usuario != ?',
      whereArgs: [AppRoles.administrador, AppEstados.activo, 'superadmin'],
    );

    for (final admin in admins) {
      await crear(
        usuarioId: admin['id'] as int,
        titulo: titulo,
        mensaje: mensaje,
        tipo: tipo,
        modulo: modulo,
        referenciaId: referenciaId,
      );
    }
  }

  Future<List<NotificacionModel>> listar() async {
    final db = await _db;
    final usuario = SessionManager.instance.usuarioActual;
    final esAdmin = usuario?.esAdministrador == true;
    final rows = await db.rawQuery('''
      SELECT n.*, u.nombre AS usuario_nombre
      FROM ${DatabaseTables.notificaciones} n
      LEFT JOIN ${DatabaseTables.usuarios} u ON u.id = n.usuario_id
      ${esAdmin ? '' : 'WHERE n.usuario_id = ?'}
      ORDER BY
        CASE n.tipo WHEN 'critica' THEN 0 ELSE 1 END ASC,
        CASE n.estado WHEN 'pendiente' THEN 0 ELSE 1 END ASC,
        n.fecha_hora DESC
      LIMIT 300
      ''', esAdmin ? [] : [usuario?.id]);

    return rows.map(NotificacionModel.fromMap).toList();
  }

  Future<int> pendientesCount() async {
    final db = await _db;
    final usuario = SessionManager.instance.usuarioActual;
    final esAdmin = usuario?.esAdministrador == true;
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM ${DatabaseTables.notificaciones}
      WHERE estado = ?
      ${esAdmin ? '' : 'AND usuario_id = ?'}
      ''',
      esAdmin
          ? [NotificacionEstados.pendiente]
          : [NotificacionEstados.pendiente, usuario?.id],
    );
    return (rows.first['total'] as int?) ?? 0;
  }

  Future<void> marcarLeida(int id) async {
    final db = await _db;
    await db.update(
      DatabaseTables.notificaciones,
      {'estado': NotificacionEstados.leida},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> marcarLeidasPorReferencia({
    required String modulo,
    int? referenciaId,
  }) async {
    final db = await _db;
    final where = StringBuffer('modulo = ? AND estado = ?');
    final args = <Object?>[modulo, NotificacionEstados.pendiente];
    if (referenciaId != null) {
      where.write(' AND referencia_id = ?');
      args.add(referenciaId);
    }

    await db.update(
      DatabaseTables.notificaciones,
      {'estado': NotificacionEstados.leida},
      where: where.toString(),
      whereArgs: args,
    );
  }

  Future<void> marcarPendiente(int id) async {
    final db = await _db;
    await db.update(
      DatabaseTables.notificaciones,
      {'estado': NotificacionEstados.pendiente},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
