import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';
import '../../../core/services/online_id_mapper.dart';
import '../../../core/services/supabase_service.dart';
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
    final perfil = SessionManager.instance.perfilActual;
    if (SupabaseService.isInitialized && perfil != null) {
      try {
        await SupabaseService.requireClient.from('auditoria').insert({
          'empresa_id': perfil.companyId,
          'usuario_id': perfil.id,
          'accion': accion,
          'modulo': modulo,
          'descripcion': descripcion,
          'metadata': {
            if (referenciaId != null) 'local_referencia_id': referenciaId,
            if (usuarioId != null) 'local_usuario_id': usuarioId,
          },
        });
        return 0;
      } catch (error) {
        debugPrint('No se pudo registrar auditoria online: $error');
        if (kIsWeb) return 0;
      }
    }

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
    final perfil = SessionManager.instance.perfilActual;
    if (SupabaseService.isInitialized && perfil != null) {
      dynamic query = SupabaseService.requireClient.from('auditoria').select();
      final usuarioUuid = OnlineIdMapper.instance.uuidFor(usuarioId);
      if (usuarioUuid != null) query = query.eq('usuario_id', usuarioUuid);
      final rows = await query.order('created_at', ascending: false).limit(300);
      return rows.map<AuditoriaModel>(_fromOnline).toList();
    }

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

  AuditoriaModel _fromOnline(Map<String, dynamic> row) {
    final uuid = row['id'] as String;
    final usuarioUuid = row['usuario_id'] as String?;
    return AuditoriaModel(
      id: OnlineIdMapper.instance.localIdFor(uuid),
      usuarioId: usuarioUuid == null
          ? null
          : OnlineIdMapper.instance.localIdFor(usuarioUuid),
      accion: row['accion'] as String,
      modulo: row['modulo'] as String,
      descripcion: row['descripcion'] as String,
      referenciaId: null,
      fechaHora: DateTime.parse(row['created_at'] as String),
    );
  }
}
