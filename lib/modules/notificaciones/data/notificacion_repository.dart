import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';
import '../../../core/services/online_id_mapper.dart';
import '../../../core/services/supabase_service.dart';
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
    if (_usaSupabase) {
      final perfil = SessionManager.instance.perfilActual!;
      final usuarioUuid = OnlineIdMapper.instance.uuidFor(usuarioId);
      final row = await SupabaseService.requireClient
          .from('notificaciones')
          .insert({
            'empresa_id': perfil.companyId,
            'usuario_id': usuarioUuid,
            'titulo': titulo,
            'mensaje': mensaje,
            'tipo': tipo,
            'modulo': modulo,
            'estado': NotificacionEstados.pendiente,
          })
          .select()
          .single();
      return OnlineIdMapper.instance.localIdFor(row['id'] as String);
    }

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
    if (_usaSupabase) {
      final perfil = SessionManager.instance.perfilActual!;
      final admins = await SupabaseService.requireClient
          .from('perfiles')
          .select('id')
          .eq('empresa_id', perfil.companyId!)
          .eq('rol', AppRoles.administrador)
          .eq('estado', AppEstados.activo);

      for (final admin in admins) {
        await SupabaseService.requireClient.from('notificaciones').insert({
          'empresa_id': perfil.companyId,
          'usuario_id': admin['id'],
          'titulo': titulo,
          'mensaje': mensaje,
          'tipo': tipo,
          'modulo': modulo,
          'estado': NotificacionEstados.pendiente,
        });
      }
      return;
    }

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
    if (_usaSupabase) {
      final perfil = SessionManager.instance.perfilActual!;
      dynamic query = SupabaseService.requireClient
          .from('notificaciones')
          .select();
      if (!perfil.esAdministrador && !perfil.esSuperadmin) {
        query = query.eq('usuario_id', perfil.id);
      }
      final rows = await query.order('created_at', ascending: false).limit(300);
      return rows.map<NotificacionModel>(_fromOnline).toList();
    }

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
    if (_usaSupabase) {
      final perfil = SessionManager.instance.perfilActual!;
      final rows = await listar();
      if (perfil.esAdministrador || perfil.esSuperadmin) {
        return rows.where((n) => !n.estaLeida).length;
      }
      return rows
          .where((n) => !n.estaLeida && n.usuarioId == perfil.toLegacyUsuario().id)
          .length;
    }

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
    if (_usaSupabase) {
      final uuid = OnlineIdMapper.instance.uuidFor(id);
      if (uuid == null) return;
      await SupabaseService.requireClient
          .from('notificaciones')
          .update({'estado': NotificacionEstados.leida}).eq('id', uuid);
      return;
    }

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
    if (_usaSupabase) return;

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
    if (_usaSupabase) {
      final uuid = OnlineIdMapper.instance.uuidFor(id);
      if (uuid == null) return;
      await SupabaseService.requireClient
          .from('notificaciones')
          .update({'estado': NotificacionEstados.pendiente}).eq('id', uuid);
      return;
    }

    final db = await _db;
    await db.update(
      DatabaseTables.notificaciones,
      {'estado': NotificacionEstados.pendiente},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  bool get _usaSupabase {
    return SupabaseService.isInitialized &&
        SessionManager.instance.perfilActual != null;
  }

  NotificacionModel _fromOnline(Map<String, dynamic> row) {
    final uuid = row['id'] as String;
    final usuarioUuid = row['usuario_id'] as String?;
    return NotificacionModel(
      id: OnlineIdMapper.instance.localIdFor(uuid),
      usuarioId: usuarioUuid == null
          ? null
          : OnlineIdMapper.instance.localIdFor(usuarioUuid),
      titulo: row['titulo'] as String,
      mensaje: row['mensaje'] as String,
      tipo: row['tipo'] as String,
      modulo: row['modulo'] as String?,
      referenciaId: null,
      usuarioNombre: null,
      estado: row['estado'] as String? ?? NotificacionEstados.pendiente,
      fechaHora: DateTime.parse(row['created_at'] as String),
    );
  }
}
