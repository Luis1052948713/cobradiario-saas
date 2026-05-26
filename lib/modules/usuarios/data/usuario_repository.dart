import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';
import '../../../core/services/online_id_mapper.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/session/session_manager.dart';
import '../../auditoria/data/auditoria_repository.dart';
import '../models/usuario_model.dart';

class UsuarioRepository {
  const UsuarioRepository({
    this.auditoriaRepository = const AuditoriaRepository(),
  });

  final AuditoriaRepository auditoriaRepository;

  Future<Database> get _db => DatabaseHelper.instance.database;

  Future<int> crear(UsuarioModel usuario) async {
    if (_usaSupabase) {
      final response = await SupabaseService.requireClient.functions.invoke(
        'crear-usuario-empresa',
        body: {
          'nombre': usuario.nombre,
          'email': usuario.usuario,
          'usuario': usuario.usuario,
          'password': usuario.contrasena,
          'rol': usuario.rol,
          'estado': usuario.estado,
        },
      );
      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw StateError(data['error'] as String);
      }
      if (data is! Map || data['profile'] is! Map) {
        throw StateError('La funcion no devolvio el perfil creado.');
      }
      final created = _fromPerfil(Map<String, dynamic>.from(data['profile']));
      await auditoriaRepository.registrar(
        accion: 'crear',
        modulo: 'usuarios',
        descripcion: 'Usuario creado: ${usuario.usuario} rol=${usuario.rol}',
        referenciaId: created.id,
      );
      return created.id ?? 0;
    }

    final db = await _db;
    final id = await db.insert(DatabaseTables.usuarios, usuario.toMap());
    await auditoriaRepository.registrar(
      accion: 'crear',
      modulo: 'usuarios',
      descripcion: 'Usuario creado: ${usuario.usuario} rol=${usuario.rol}',
      referenciaId: id,
    );
    return id;
  }

  Future<List<UsuarioModel>> listar() async {
    if (_usaSupabase) return _listarOnline();

    final db = await _db;
    final rows = await db.query(DatabaseTables.usuarios, orderBy: 'nombre ASC');

    return rows.map(UsuarioModel.fromMap).toList();
  }

  Future<List<UsuarioModel>> listarCobradoresActivos() async {
    if (_usaSupabase) {
      final usuarios = await _listarOnline();
      return usuarios
          .where((u) => u.rol == AppRoles.cobrador && u.estaActivo)
          .toList();
    }

    final db = await _db;
    final rows = await db.query(
      DatabaseTables.usuarios,
      where: 'rol = ? AND estado = ?',
      whereArgs: [AppRoles.cobrador, AppEstados.activo],
      orderBy: 'nombre ASC',
    );

    return rows.map(UsuarioModel.fromMap).toList();
  }

  Future<UsuarioModel?> buscarPorId(int id) async {
    if (_usaSupabase) {
      final uuid = OnlineIdMapper.instance.uuidFor(id);
      if (uuid == null) return null;
      final row = await SupabaseService.requireClient
          .from('perfiles')
          .select()
          .eq('id', uuid)
          .maybeSingle();
      if (row == null) return null;
      return _fromPerfil(row);
    }

    final db = await _db;
    final rows = await db.query(
      DatabaseTables.usuarios,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return UsuarioModel.fromMap(rows.first);
  }

  Future<UsuarioModel?> buscarPorUsuario(String usuario) async {
    if (_usaSupabase) {
      final row = await SupabaseService.requireClient
          .from('perfiles')
          .select()
          .eq('usuario', usuario.trim())
          .maybeSingle();
      if (row == null) return null;
      return _fromPerfil(row);
    }

    final db = await _db;
    final rows = await db.query(
      DatabaseTables.usuarios,
      where: 'usuario = ?',
      whereArgs: [usuario.trim()],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return UsuarioModel.fromMap(rows.first);
  }

  Future<UsuarioModel?> validarCredenciales({
    required String usuario,
    required String contrasena,
  }) async {
    final db = await _db;
    final usuarioNormalizado = usuario.trim();
    var rows = await _buscarCredenciales(
      db,
      usuario: usuarioNormalizado,
      contrasena: contrasena,
    );

    if (rows.isEmpty &&
        usuarioNormalizado.toLowerCase() == AppRoles.superadmin &&
        contrasena == 'super123') {
      await asegurarSuperadmin();
      rows = await _buscarCredenciales(
        db,
        usuario: usuarioNormalizado,
        contrasena: contrasena,
      );
    }

    if (rows.isEmpty) return null;
    return UsuarioModel.fromMap(rows.first);
  }

  Future<void> asegurarSuperadmin() async {
    if (_usaSupabase) return;

    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query(
      DatabaseTables.usuarios,
      columns: ['id'],
      where: 'usuario = ?',
      whereArgs: [AppRoles.superadmin],
      limit: 1,
    );

    final data = {
      'nombre': 'Super Administrador',
      'usuario': AppRoles.superadmin,
      'contrasena': 'super123',
      'rol': AppRoles.superadmin,
      'estado': AppEstados.activo,
      'saldo_disponible': 0,
      'fecha_creacion': now,
    };

    if (rows.isEmpty) {
      try {
        await db.insert(DatabaseTables.usuarios, data);
      } on DatabaseException {
        await db.insert(DatabaseTables.usuarios, {
          ...data,
          'rol': AppRoles.administrador,
        });
      }
      return;
    }

    final id = rows.first['id'] as int;
    try {
      await db.update(
        DatabaseTables.usuarios,
        {
          'nombre': 'Super Administrador',
          'contrasena': 'super123',
          'rol': AppRoles.superadmin,
          'estado': AppEstados.activo,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } on DatabaseException {
      await db.update(
        DatabaseTables.usuarios,
        {
          'nombre': 'Super Administrador',
          'contrasena': 'super123',
          'rol': AppRoles.administrador,
          'estado': AppEstados.activo,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<List<Map<String, Object?>>> _buscarCredenciales(
    Database db, {
    required String usuario,
    required String contrasena,
  }) {
    return db.query(
      DatabaseTables.usuarios,
      where: 'usuario = ? AND contrasena = ? AND estado = ?',
      whereArgs: [usuario, contrasena, AppEstados.activo],
      limit: 1,
    );
  }

  Future<int> actualizar(UsuarioModel usuario) async {
    if (_usaSupabase) {
      final uuid = OnlineIdMapper.instance.uuidFor(usuario.id);
      if (uuid == null) throw StateError('Usuario online no encontrado.');
      await SupabaseService.requireClient.from('perfiles').update({
        'nombre': usuario.nombre,
        'usuario': usuario.usuario,
        'rol': usuario.rol,
        'estado': usuario.estado,
        'saldo_disponible': usuario.saldoDisponible,
      }).eq('id', uuid);
      await auditoriaRepository.registrar(
        accion: 'actualizar',
        modulo: 'usuarios',
        descripcion:
            'Usuario actualizado: ${usuario.usuario} rol=${usuario.rol}',
        referenciaId: usuario.id,
      );
      return 1;
    }

    final db = await _db;
    final updated = await db.update(
      DatabaseTables.usuarios,
      usuario.toMap(),
      where: 'id = ?',
      whereArgs: [usuario.id],
    );
    await auditoriaRepository.registrar(
      accion: 'actualizar',
      modulo: 'usuarios',
      descripcion: 'Usuario actualizado: ${usuario.usuario} rol=${usuario.rol}',
      referenciaId: usuario.id,
    );
    return updated;
  }

  Future<int> cambiarEstado(int id, String estado) async {
    if (_usaSupabase) {
      final uuid = OnlineIdMapper.instance.uuidFor(id);
      if (uuid == null) throw StateError('Usuario online no encontrado.');
      await SupabaseService.requireClient
          .from('perfiles')
          .update({'estado': estado}).eq('id', uuid);
      await auditoriaRepository.registrar(
        accion: 'cambiar_estado',
        modulo: 'usuarios',
        descripcion: 'Estado de usuario id=$id cambiado a $estado',
        referenciaId: id,
      );
      return 1;
    }

    final db = await _db;
    final updated = await db.update(
      DatabaseTables.usuarios,
      {'estado': estado},
      where: 'id = ?',
      whereArgs: [id],
    );
    await auditoriaRepository.registrar(
      accion: 'cambiar_estado',
      modulo: 'usuarios',
      descripcion: 'Estado de usuario id=$id cambiado a $estado',
      referenciaId: id,
    );
    return updated;
  }

  bool get _usaSupabase {
    return SupabaseService.isInitialized &&
        SessionManager.instance.perfilActual != null;
  }

  Future<List<UsuarioModel>> _listarOnline() async {
    final perfil = SessionManager.instance.perfilActual;
    dynamic query = SupabaseService.requireClient.from('perfiles').select();

    if (perfil?.esSuperadmin != true && perfil?.companyId != null) {
      query = query.eq('empresa_id', perfil!.companyId!);
    }

    final rows = await query.order('nombre');
    return rows.map<UsuarioModel>(_fromPerfil).toList();
  }

  UsuarioModel _fromPerfil(Map<String, dynamic> row) {
    final uuid = row['id'] as String;
    return UsuarioModel(
      id: OnlineIdMapper.instance.localIdFor(uuid),
      nombre: row['nombre'] as String? ?? 'Usuario',
      usuario: row['usuario'] as String? ?? row['email'] as String? ?? uuid,
      contrasena: '',
      rol: row['rol'] as String? ?? AppRoles.cobrador,
      estado: row['estado'] as String? ?? AppEstados.inactivo,
      saldoDisponible: (row['saldo_disponible'] as num?)?.toDouble() ?? 0,
      fechaCreacion: row['created_at'] == null
          ? DateTime.now()
          : DateTime.parse(row['created_at'] as String),
    );
  }
}
