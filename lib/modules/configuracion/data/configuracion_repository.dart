import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/session/session_manager.dart';
import '../models/configuracion_model.dart';

class ConfiguracionRepository {
  const ConfiguracionRepository();

  Future<Database> get _db => DatabaseHelper.instance.database;

  Future<List<ConfiguracionModel>> listar() async {
    if (_usaSupabase) return _onlineDefaults();

    final db = await _db;
    final rows = await db.query(
      DatabaseTables.configuraciones,
      orderBy: 'clave ASC',
    );

    return rows.map(ConfiguracionModel.fromMap).toList();
  }

  Future<String?> obtenerValor(String clave) async {
    if (_usaSupabase) {
      return {
        for (final config in _onlineDefaults()) config.clave: config.valor,
      }[clave];
    }

    final db = await _db;
    final rows = await db.query(
      DatabaseTables.configuraciones,
      columns: ['valor'],
      where: 'clave = ?',
      whereArgs: [clave],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return rows.first['valor'] as String;
  }

  Future<void> guardarValor({
    required String clave,
    required String valor,
    String tipo = 'texto',
  }) async {
    if (_usaSupabase) return;

    final db = await _db;
    await db.insert(DatabaseTables.configuraciones, {
      'clave': clave,
      'valor': valor,
      'tipo': tipo,
      'fecha_actualizacion': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  bool get _usaSupabase {
    return SupabaseService.isInitialized &&
        SessionManager.instance.perfilActual != null;
  }

  List<ConfiguracionModel> _onlineDefaults() {
    final now = DateTime.now();
    return [
      ConfiguracionModel(
        clave: AppConfigKeys.moneda,
        valor: 'COP',
        fechaActualizacion: now,
      ),
      ConfiguracionModel(
        clave: AppConfigKeys.interesDefecto,
        valor: '20',
        tipo: 'numero',
        fechaActualizacion: now,
      ),
      ConfiguracionModel(
        clave: AppConfigKeys.cuotasDefecto,
        valor: '24',
        tipo: 'numero',
        fechaActualizacion: now,
      ),
      ConfiguracionModel(
        clave: AppConfigKeys.empresaNombre,
        valor: 'Cobra Diario',
        fechaActualizacion: now,
      ),
    ];
  }
}
