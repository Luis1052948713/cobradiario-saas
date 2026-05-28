import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../database/database_tables.dart';

class OnlineIdMapper {
  OnlineIdMapper._internal();

  static final OnlineIdMapper instance = OnlineIdMapper._internal();

  final Map<String, int> _uuidToLocal = {};
  final Map<int, String> _localToUuid = {};

  final Map<String, Map<String, int>> _uuidToLocalByTable = {};
  final Map<String, Map<int, String>> _localToUuidByTable = {};

  int _nextLocalId = -1;
  bool _hydrated = false;

  int localIdFor(String uuid, {String? tabla}) {
    if (tabla != null) {
      final tableMap = _uuidToLocalByTable.putIfAbsent(tabla, () => {});
      final cached = tableMap[uuid];

      if (cached != null) return cached;

      final localId = _nextLocalId--;
      tableMap[uuid] = localId;

      final reverseMap = _localToUuidByTable.putIfAbsent(tabla, () => {});
      reverseMap[localId] = uuid;

      _uuidToLocal[uuid] = localId;
      _localToUuid[localId] = uuid;

      return localId;
    }

    final cached = _uuidToLocal[uuid];

    if (cached != null) return cached;

    final localId = _nextLocalId--;

    _uuidToLocal[uuid] = localId;
    _localToUuid[localId] = uuid;

    return localId;
  }

  String? uuidFor(int? localId, {String? tabla}) {
    if (localId == null) return null;

    if (tabla != null) {
      final byTable = _localToUuidByTable[tabla]?[localId];
      if (byTable != null) return byTable;
    }

    return _localToUuid[localId];
  }

  void remember({required String uuid, required int localId, String? tabla}) {
    _uuidToLocal[uuid] = localId;
    _localToUuid[localId] = uuid;

    if (tabla != null) {
      final tableMap = _uuidToLocalByTable.putIfAbsent(tabla, () => {});
      tableMap[uuid] = localId;

      final reverseMap = _localToUuidByTable.putIfAbsent(tabla, () => {});
      reverseMap[localId] = uuid;
    }
  }

  Future<void> hydrateFromLocalDatabase() async {
    if (kIsWeb || _hydrated) return;

    final db = await DatabaseHelper.instance.database;

    final rows = await db.query(DatabaseTables.onlineIdMap);

    for (final row in rows) {
      final tabla = row['tabla'] as String;
      final uuid = row['uuid'] as String;
      final localId = row['local_id'] as int;

      remember(uuid: uuid, localId: localId, tabla: tabla);
    }

    _hydrated = true;
  }

  Future<void> rememberPersisted({
    required String tabla,
    required String uuid,
    required int localId,
    DatabaseExecutor? executor,
  }) async {
    remember(uuid: uuid, localId: localId, tabla: tabla);

    if (kIsWeb) return;

    final now = DateTime.now().toIso8601String();
    final db = executor ?? await DatabaseHelper.instance.database;

    await db.insert(DatabaseTables.onlineIdMap, {
      'tabla': tabla,
      'uuid': uuid,
      'local_id': localId,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearPersisted() async {
    clear();

    if (kIsWeb) return;

    final db = await DatabaseHelper.instance.database;
    await db.delete(DatabaseTables.onlineIdMap);
  }

  void clear() {
    _uuidToLocal.clear();
    _localToUuid.clear();
    _uuidToLocalByTable.clear();
    _localToUuidByTable.clear();
    _nextLocalId = -1;
    _hydrated = false;
  }
}
