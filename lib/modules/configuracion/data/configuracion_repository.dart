import 'package:sqflite/sqflite.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';
import '../models/configuracion_model.dart';

class ConfiguracionRepository {
  const ConfiguracionRepository();

  Future<Database> get _db => DatabaseHelper.instance.database;

  Future<List<ConfiguracionModel>> listar() async {
    final db = await _db;
    final rows = await db.query(
      DatabaseTables.configuraciones,
      orderBy: 'clave ASC',
    );

    return rows.map(ConfiguracionModel.fromMap).toList();
  }

  Future<String?> obtenerValor(String clave) async {
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
    final db = await _db;
    await db.insert(DatabaseTables.configuraciones, {
      'clave': clave,
      'valor': valor,
      'tipo': tipo,
      'fecha_actualizacion': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
