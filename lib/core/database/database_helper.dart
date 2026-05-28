import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'database_tables.dart';

class DatabaseHelper {
  DatabaseHelper._internal();

  static final DatabaseHelper instance = DatabaseHelper._internal();

  static const String _databaseName = 'cobra_diario.db';
  static const int _databaseVersion = 11;

  Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _openDatabase();
    return _database!;
  }

  Future<Database> _openDatabase() async {
    final appDirectory = await getApplicationDocumentsDirectory();
    final databasePath = path.join(appDirectory.path, _databaseName);

    return openDatabase(
      databasePath,
      version: _databaseVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.transaction((txn) async {
      await txn.execute(_createUsuariosTable);
      await txn.execute(_createClientesTable);
      await txn.execute(_createPrestamosTable);
      await txn.execute(_createCobrosTable);
      await txn.execute(_createConfiguracionesTable);
      await txn.execute(_createAuditoriaTable);
      await txn.execute(_createRutasTable);
      await txn.execute(_createRutaClientesTable);
      await txn.execute(_createRutaVisitasTable);
      await txn.execute(_createRutaClienteActivoIndex);
      await txn.execute(_createCajasTable);
      await txn.execute(_createCierresCajaTable);
      await txn.execute(_createGastosTable);
      await txn.execute(_createSolicitudesSaldoTable);
      await txn.execute(_createMovimientosFinancierosTable);
      await txn.execute(_createMovimientosCajaTable);
      await txn.execute(_createNotificacionesTable);
      await txn.execute(_createCapitalGeneralTable);
      await txn.execute(_createMovimientosCapitalTable);
      await txn.execute(_createAsignacionesSaldoTable);
      await txn.execute(_createCierresFinancierosTable);
      await txn.execute(_createEmpresasTable);
      await txn.execute(_createSuscripcionesTable);
      await txn.execute(_createLicenciaEventosTable);
      await txn.execute(_createSyncQueueTable);
      await _seedInitialData(txn);
      await _seedSubscriptionData(txn);
    });
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.transaction((txn) async {
        await txn.execute('DROP TABLE IF EXISTS ${DatabaseTables.cobros}');
        await txn.execute('DROP TABLE IF EXISTS ${DatabaseTables.prestamos}');
        await txn.execute('DROP TABLE IF EXISTS ${DatabaseTables.clientes}');
        await txn.execute('DROP TABLE IF EXISTS ${DatabaseTables.usuarios}');
        await txn.execute(
          'DROP TABLE IF EXISTS ${DatabaseTables.configuraciones}',
        );

        await txn.execute(_createUsuariosTable);
        await txn.execute(_createClientesTable);
        await txn.execute(_createPrestamosTable);
        await txn.execute(_createCobrosTable);
        await txn.execute(_createConfiguracionesTable);
        await txn.execute(_createAuditoriaTable);
        await txn.execute(_createRutasTable);
        await txn.execute(_createRutaClientesTable);
        await txn.execute(_createRutaVisitasTable);
        await txn.execute(_createRutaClienteActivoIndex);
        await txn.execute(_createCajasTable);
        await txn.execute(_createCierresCajaTable);
        await txn.execute(_createGastosTable);
        await txn.execute(_createSolicitudesSaldoTable);
        await txn.execute(_createMovimientosFinancierosTable);
        await txn.execute(_createMovimientosCajaTable);
        await txn.execute(_createNotificacionesTable);
        await txn.execute(_createCapitalGeneralTable);
        await txn.execute(_createMovimientosCapitalTable);
        await txn.execute(_createAsignacionesSaldoTable);
        await txn.execute(_createCierresFinancierosTable);
        await txn.execute(_createEmpresasTable);
        await txn.execute(_createSuscripcionesTable);
        await txn.execute(_createLicenciaEventosTable);
        await txn.execute(_createSyncQueueTable);
        await _seedInitialData(txn);
        await _seedSubscriptionData(txn);
      });
    }

    if (oldVersion >= 2 && oldVersion < 3) {
      await db.transaction((txn) async {
        await txn.execute(
          'ALTER TABLE ${DatabaseTables.cobros} '
          'ADD COLUMN saldo_anterior REAL',
        );
        await txn.execute(
          'ALTER TABLE ${DatabaseTables.cobros} '
          'ADD COLUMN saldo_actual REAL',
        );
        await txn.execute(
          'ALTER TABLE ${DatabaseTables.cobros} '
          "ADD COLUMN estado TEXT NOT NULL DEFAULT 'registrado'",
        );
        await txn.execute(_createAuditoriaTable);
      });
    }

    if (oldVersion < 4) {
      await db.transaction((txn) async {
        await _addColumnIfMissing(
          txn,
          table: DatabaseTables.clientes,
          column: 'latitud',
          definition: 'REAL',
        );
        await _addColumnIfMissing(
          txn,
          table: DatabaseTables.clientes,
          column: 'longitud',
          definition: 'REAL',
        );
        await txn.execute(_createRutasTable);
        await txn.execute(_createRutaClientesTable);
        await txn.execute(_createRutaVisitasTable);
        await txn.execute(_createRutaClienteActivoIndex);
      });
    }

    if (oldVersion < 5) {
      await db.transaction((txn) async {
        await _addColumnIfMissing(
          txn,
          table: DatabaseTables.usuarios,
          column: 'saldo_disponible',
          definition: 'REAL NOT NULL DEFAULT 0',
        );
        await txn.execute(_createCierresCajaTable);
        await txn.execute(_createGastosTable);
        await txn.execute(_createSolicitudesSaldoTable);
        await txn.execute(_createMovimientosFinancierosTable);
        await txn.execute(_createCajasTable);
        await txn.execute(_createMovimientosCajaTable);
      });
    }

    if (oldVersion < 6) {
      await db.transaction((txn) async {
        await txn.execute(_createNotificacionesTable);
      });
    }

    if (oldVersion < 7) {
      await db.transaction((txn) async {
        await txn.execute(_createCajasTable);
        await txn.execute(_createMovimientosCajaTable);
        await _addColumnIfMissing(
          txn,
          table: DatabaseTables.cierresCaja,
          column: 'caja_id',
          definition: 'INTEGER',
        );
        await _addColumnIfMissing(
          txn,
          table: DatabaseTables.cierresCaja,
          column: 'admin_id',
          definition: 'INTEGER',
        );
        await _addColumnIfMissing(
          txn,
          table: DatabaseTables.cierresCaja,
          column: 'observacion_admin',
          definition: 'TEXT',
        );
        await _addColumnIfMissing(
          txn,
          table: DatabaseTables.cierresCaja,
          column: 'fecha_revision',
          definition: 'TEXT',
        );
        await _addColumnIfMissing(
          txn,
          table: DatabaseTables.cierresCaja,
          column: 'dinero_entregado',
          definition: 'REAL NOT NULL DEFAULT 0',
        );
      });
    }

    if (oldVersion < 8) {
      await db.transaction((txn) async {
        await txn.execute(_createCapitalGeneralTable);
        await txn.execute(_createMovimientosCapitalTable);
        await txn.execute(_createAsignacionesSaldoTable);
        await txn.execute(_createCierresFinancierosTable);
      });
    }

    if (oldVersion < 9) {
      await db.transaction((txn) async {
        await txn.execute(_createEmpresasTable);
        await txn.execute(_createSuscripcionesTable);
        await txn.execute(_createLicenciaEventosTable);
        await _seedSubscriptionData(txn);
      });
    }

    if (oldVersion < 10) {
      await db.transaction((txn) async {
        await _seedSuperadminData(txn);
      });
    }

    if (oldVersion < 11) {
      await db.transaction((txn) async {
        await txn.execute(_createSyncQueueTable);
      });
    }
  }

  Future<void> _addColumnIfMissing(
    Transaction txn, {
    required String table,
    required String column,
    required String definition,
  }) async {
    final columns = await txn.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((item) => item['name'] == column);
    if (!exists) {
      await txn.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  Future<void> _seedInitialData(Transaction txn) async {
    final now = DateTime.now().toIso8601String();

    await _insertSuperadmin(txn, role: 'superadmin');

    await txn.insert(DatabaseTables.usuarios, {
      'nombre': 'Administrador',
      'usuario': 'admin',
      'contrasena': 'admin123',
      'rol': 'administrador',
      'estado': 'activo',
      'fecha_creacion': now,
    });

    await txn.insert(DatabaseTables.configuraciones, {
      'clave': 'moneda',
      'valor': 'COP',
      'tipo': 'texto',
      'fecha_actualizacion': now,
    });

    await txn.insert(DatabaseTables.configuraciones, {
      'clave': 'interes_defecto',
      'valor': '20',
      'tipo': 'numero',
      'fecha_actualizacion': now,
    });
  }

  Future<void> _seedSuperadminData(Transaction txn) async {
    final rows = await txn.query(
      DatabaseTables.usuarios,
      columns: ['id'],
      where: 'usuario = ?',
      whereArgs: ['superadmin'],
      limit: 1,
    );
    if (rows.isNotEmpty) return;

    try {
      await _insertSuperadmin(txn, role: 'superadmin');
    } on DatabaseException {
      await _insertSuperadmin(txn, role: 'administrador');
    }
  }

  Future<void> _insertSuperadmin(
    Transaction txn, {
    required String role,
  }) async {
    await txn.insert(DatabaseTables.usuarios, {
      'nombre': 'Super Administrador',
      'usuario': 'superadmin',
      'contrasena': 'super123',
      'rol': role,
      'estado': 'activo',
      'saldo_disponible': 0,
      'fecha_creacion': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _seedSubscriptionData(Transaction txn) async {
    final empresas = await txn.query(
      DatabaseTables.empresas,
      columns: ['id'],
      limit: 1,
    );
    if (empresas.isNotEmpty) return;

    final now = DateTime.now();
    final empresaId = await txn.insert(DatabaseTables.empresas, {
      'nombre': 'Empresa Demo',
      'identificacion': null,
      'email': null,
      'telefono': null,
      'estado': 'activa',
      'fecha_creacion': now.toIso8601String(),
    });
    final finPrueba = now.add(const Duration(days: 15));
    final suscripcionId = await txn.insert(DatabaseTables.suscripciones, {
      'empresa_id': empresaId,
      'plan': 'pro',
      'estado': 'prueba',
      'proveedor': 'manual',
      'referencia_pago': 'TRIAL-INICIAL',
      'monto': 0,
      'fecha_inicio': now.toIso8601String(),
      'fecha_fin': finPrueba.toIso8601String(),
      'fecha_ultimo_pago': null,
      'observacion': 'Prueba inicial de 15 dias',
      'fecha_actualizacion': now.toIso8601String(),
      'usuario_id': null,
    });
    await txn.insert(DatabaseTables.licenciaEventos, {
      'empresa_id': empresaId,
      'suscripcion_id': suscripcionId,
      'tipo': 'prueba_inicial',
      'descripcion': 'Prueba inicial activada por instalacion local',
      'fecha_hora': now.toIso8601String(),
      'usuario_id': null,
    });
  }

  Future<void> close() async {
    final db = _database;

    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  Future<bool> testConnection() async {
    final db = await database;
    final result = await db.rawQuery('SELECT 1 AS connected');

    return result.isNotEmpty && result.first['connected'] == 1;
  }

  static const String _createUsuariosTable =
      '''
    CREATE TABLE ${DatabaseTables.usuarios} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nombre TEXT NOT NULL,
      usuario TEXT NOT NULL UNIQUE,
      contrasena TEXT NOT NULL,
      rol TEXT NOT NULL CHECK (
        rol IN ('superadmin', 'administrador', 'cobrador')
      ),
      estado TEXT NOT NULL DEFAULT 'activo'
        CHECK (estado IN ('activo', 'inactivo')),
      saldo_disponible REAL NOT NULL DEFAULT 0,
      fecha_creacion TEXT NOT NULL
    )
  ''';

  static const String _createClientesTable =
      '''
    CREATE TABLE ${DatabaseTables.clientes} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nombre TEXT NOT NULL,
      cedula TEXT UNIQUE,
      telefono TEXT,
      direccion TEXT,
      barrio TEXT,
      referencia TEXT,
      foto TEXT,
      cobrador_id INTEGER,
      latitud REAL,
      longitud REAL,
      estado TEXT NOT NULL DEFAULT 'activo'
        CHECK (estado IN ('activo', 'inactivo')),
      fecha_registro TEXT NOT NULL,
      FOREIGN KEY (cobrador_id) REFERENCES ${DatabaseTables.usuarios} (id)
        ON DELETE RESTRICT ON UPDATE CASCADE
    )
  ''';

  static const String _createPrestamosTable =
      '''
    CREATE TABLE ${DatabaseTables.prestamos} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      cliente_id INTEGER NOT NULL,
      monto REAL NOT NULL,
      interes REAL NOT NULL DEFAULT 0,
      total_pagar REAL NOT NULL,
      cuotas INTEGER NOT NULL,
      cuota_diaria REAL NOT NULL,
      saldo REAL NOT NULL,
      fecha_inicio TEXT NOT NULL,
      fecha_fin TEXT,
      estado TEXT NOT NULL DEFAULT 'activo'
        CHECK (estado IN (
          'activo',
          'pagado',
          'atrasado',
          'cancelado',
          'refinanciado'
        )),
      FOREIGN KEY (cliente_id) REFERENCES ${DatabaseTables.clientes} (id)
        ON DELETE RESTRICT ON UPDATE CASCADE
    )
  ''';

  static const String _createCobrosTable =
      '''
    CREATE TABLE ${DatabaseTables.cobros} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      prestamo_id INTEGER NOT NULL,
      cobrador_id INTEGER NOT NULL,
      monto REAL NOT NULL,
      saldo_anterior REAL,
      saldo_actual REAL,
      observacion TEXT,
      fecha_pago TEXT NOT NULL,
      estado TEXT NOT NULL DEFAULT 'registrado'
        CHECK (estado IN ('registrado', 'anulado')),
      FOREIGN KEY (prestamo_id) REFERENCES ${DatabaseTables.prestamos} (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
      FOREIGN KEY (cobrador_id) REFERENCES ${DatabaseTables.usuarios} (id)
        ON DELETE RESTRICT ON UPDATE CASCADE
    )
  ''';

  static const String _createConfiguracionesTable =
      '''
    CREATE TABLE ${DatabaseTables.configuraciones} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      clave TEXT NOT NULL UNIQUE,
      valor TEXT NOT NULL,
      tipo TEXT NOT NULL DEFAULT 'texto',
      fecha_actualizacion TEXT NOT NULL
    )
  ''';

  static const String _createAuditoriaTable =
      '''
    CREATE TABLE IF NOT EXISTS ${DatabaseTables.auditoria} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      usuario_id INTEGER,
      accion TEXT NOT NULL,
      modulo TEXT NOT NULL,
      descripcion TEXT NOT NULL,
      referencia_id INTEGER,
      fecha_hora TEXT NOT NULL,
      FOREIGN KEY (usuario_id) REFERENCES ${DatabaseTables.usuarios} (id)
        ON DELETE SET NULL ON UPDATE CASCADE
    )
  ''';

  static const String _createRutasTable =
      '''
    CREATE TABLE IF NOT EXISTS ${DatabaseTables.rutas} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nombre TEXT NOT NULL,
      zona TEXT NOT NULL,
      cobrador_id INTEGER NOT NULL,
      estado TEXT NOT NULL DEFAULT 'activa'
        CHECK (estado IN ('activa', 'inactiva')),
      fecha_creacion TEXT NOT NULL,
      FOREIGN KEY (cobrador_id) REFERENCES ${DatabaseTables.usuarios} (id)
        ON DELETE RESTRICT ON UPDATE CASCADE
    )
  ''';

  static const String _createRutaClientesTable =
      '''
    CREATE TABLE IF NOT EXISTS ${DatabaseTables.rutaClientes} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      ruta_id INTEGER NOT NULL,
      cliente_id INTEGER NOT NULL,
      orden INTEGER NOT NULL,
      estado TEXT NOT NULL DEFAULT 'activo'
        CHECK (estado IN ('activo', 'removido')),
      fecha_asignacion TEXT NOT NULL,
      FOREIGN KEY (ruta_id) REFERENCES ${DatabaseTables.rutas} (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
      FOREIGN KEY (cliente_id) REFERENCES ${DatabaseTables.clientes} (id)
        ON DELETE RESTRICT ON UPDATE CASCADE
    )
  ''';

  static const String _createRutaVisitasTable =
      '''
    CREATE TABLE IF NOT EXISTS ${DatabaseTables.rutaVisitas} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      ruta_id INTEGER NOT NULL,
      cliente_id INTEGER NOT NULL,
      cobrador_id INTEGER NOT NULL,
      prestamo_id INTEGER,
      cobro_id INTEGER,
      estado_visita TEXT NOT NULL CHECK (estado_visita IN (
        'pago',
        'pendiente',
        'no_encontrado',
        'negocio_cerrado',
        'promete_pagar',
        'no_quiso_pagar'
      )),
      monto_cobrado REAL NOT NULL DEFAULT 0,
      observacion TEXT,
      fecha_hora TEXT NOT NULL,
      FOREIGN KEY (ruta_id) REFERENCES ${DatabaseTables.rutas} (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
      FOREIGN KEY (cliente_id) REFERENCES ${DatabaseTables.clientes} (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
      FOREIGN KEY (cobrador_id) REFERENCES ${DatabaseTables.usuarios} (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
      FOREIGN KEY (prestamo_id) REFERENCES ${DatabaseTables.prestamos} (id)
        ON DELETE SET NULL ON UPDATE CASCADE,
      FOREIGN KEY (cobro_id) REFERENCES ${DatabaseTables.cobros} (id)
        ON DELETE SET NULL ON UPDATE CASCADE
    )
  ''';

  static const String _createRutaClienteActivoIndex =
      '''
    CREATE UNIQUE INDEX IF NOT EXISTS idx_ruta_cliente_activo
    ON ${DatabaseTables.rutaClientes} (cliente_id)
    WHERE estado = 'activo'
  ''';

  static const String _createCajasTable =
      '''
    CREATE TABLE IF NOT EXISTS ${DatabaseTables.cajas} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      cobrador_id INTEGER NOT NULL,
      admin_id INTEGER,
      fecha TEXT NOT NULL,
      hora_apertura TEXT NOT NULL,
      hora_cierre TEXT,
      saldo_inicial REAL NOT NULL DEFAULT 0,
      saldo_actual REAL NOT NULL DEFAULT 0,
      observacion_apertura TEXT,
      observacion_cierre TEXT,
      estado TEXT NOT NULL DEFAULT 'abierta'
        CHECK (estado IN ('abierta', 'cerrada', 'pendiente_revision', 'bloqueada')),
      cierre_id INTEGER,
      fecha_creacion TEXT NOT NULL,
      FOREIGN KEY (cobrador_id) REFERENCES ${DatabaseTables.usuarios} (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
      FOREIGN KEY (admin_id) REFERENCES ${DatabaseTables.usuarios} (id)
        ON DELETE SET NULL ON UPDATE CASCADE,
      FOREIGN KEY (cierre_id) REFERENCES ${DatabaseTables.cierresCaja} (id)
        ON DELETE SET NULL ON UPDATE CASCADE
    )
  ''';

  static const String _createCierresCajaTable =
      '''
    CREATE TABLE IF NOT EXISTS ${DatabaseTables.cierresCaja} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      caja_id INTEGER,
      cobrador_id INTEGER NOT NULL,
      fecha TEXT NOT NULL,
      total_recaudado REAL NOT NULL DEFAULT 0,
      total_prestado REAL NOT NULL DEFAULT 0,
      cantidad_cobros INTEGER NOT NULL DEFAULT 0,
      cantidad_prestamos INTEGER NOT NULL DEFAULT 0,
      gastos REAL NOT NULL DEFAULT 0,
      saldo_restante REAL NOT NULL DEFAULT 0,
      dinero_reportado REAL NOT NULL DEFAULT 0,
      dinero_entregado REAL NOT NULL DEFAULT 0,
      diferencia REAL NOT NULL DEFAULT 0,
      observacion TEXT,
      observacion_admin TEXT,
      estado TEXT NOT NULL DEFAULT 'pendiente_revision'
        CHECK (estado IN ('pendiente_revision', 'aprobado', 'rechazado')),
      fecha_hora TEXT NOT NULL,
      fecha_revision TEXT,
      admin_id INTEGER,
      FOREIGN KEY (caja_id) REFERENCES ${DatabaseTables.cajas} (id)
        ON DELETE SET NULL ON UPDATE CASCADE,
      FOREIGN KEY (cobrador_id) REFERENCES ${DatabaseTables.usuarios} (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
      FOREIGN KEY (admin_id) REFERENCES ${DatabaseTables.usuarios} (id)
        ON DELETE SET NULL ON UPDATE CASCADE,
      UNIQUE (cobrador_id, fecha)
    )
  ''';

  static const String _createGastosTable =
      '''
    CREATE TABLE IF NOT EXISTS ${DatabaseTables.gastos} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      cobrador_id INTEGER NOT NULL,
      tipo TEXT NOT NULL,
      valor REAL NOT NULL,
      descripcion TEXT,
      fecha_hora TEXT NOT NULL,
      FOREIGN KEY (cobrador_id) REFERENCES ${DatabaseTables.usuarios} (id)
        ON DELETE RESTRICT ON UPDATE CASCADE
    )
  ''';

  static const String _createSolicitudesSaldoTable =
      '''
    CREATE TABLE IF NOT EXISTS ${DatabaseTables.solicitudesSaldo} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      cobrador_id INTEGER NOT NULL,
      monto_solicitado REAL NOT NULL,
      monto_aprobado REAL,
      observacion TEXT,
      observacion_admin TEXT,
      estado TEXT NOT NULL DEFAULT 'pendiente'
        CHECK (estado IN ('pendiente', 'aprobada', 'rechazada')),
      fecha_hora TEXT NOT NULL,
      fecha_respuesta TEXT,
      admin_id INTEGER,
      FOREIGN KEY (cobrador_id) REFERENCES ${DatabaseTables.usuarios} (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
      FOREIGN KEY (admin_id) REFERENCES ${DatabaseTables.usuarios} (id)
        ON DELETE SET NULL ON UPDATE CASCADE
    )
  ''';

  static const String _createMovimientosFinancierosTable =
      '''
    CREATE TABLE IF NOT EXISTS ${DatabaseTables.movimientosFinancieros} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      usuario_id INTEGER NOT NULL,
      tipo TEXT NOT NULL,
      monto REAL NOT NULL,
      cliente_id INTEGER,
      saldo_antes REAL NOT NULL,
      saldo_despues REAL NOT NULL,
      observacion TEXT,
      referencia_tabla TEXT,
      referencia_id INTEGER,
      fecha_hora TEXT NOT NULL,
      FOREIGN KEY (usuario_id) REFERENCES ${DatabaseTables.usuarios} (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
      FOREIGN KEY (cliente_id) REFERENCES ${DatabaseTables.clientes} (id)
        ON DELETE SET NULL ON UPDATE CASCADE
    )
  ''';

  static const String _createMovimientosCajaTable =
      '''
    CREATE TABLE IF NOT EXISTS ${DatabaseTables.movimientosCaja} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      caja_id INTEGER,
      usuario_id INTEGER NOT NULL,
      tipo TEXT NOT NULL,
      monto REAL NOT NULL,
      saldo_antes REAL NOT NULL,
      saldo_despues REAL NOT NULL,
      observacion TEXT,
      referencia_tabla TEXT,
      referencia_id INTEGER,
      fecha_hora TEXT NOT NULL,
      FOREIGN KEY (caja_id) REFERENCES ${DatabaseTables.cajas} (id)
        ON DELETE SET NULL ON UPDATE CASCADE,
      FOREIGN KEY (usuario_id) REFERENCES ${DatabaseTables.usuarios} (id)
        ON DELETE RESTRICT ON UPDATE CASCADE
    )
  ''';

  static const String _createNotificacionesTable =
      '''
    CREATE TABLE IF NOT EXISTS ${DatabaseTables.notificaciones} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      usuario_id INTEGER,
      titulo TEXT NOT NULL,
      mensaje TEXT NOT NULL,
      tipo TEXT NOT NULL CHECK (tipo IN (
        'informativa',
        'advertencia',
        'critica',
        'exito'
      )),
      modulo TEXT,
      referencia_id INTEGER,
      estado TEXT NOT NULL DEFAULT 'pendiente'
        CHECK (estado IN ('pendiente', 'leida')),
      fecha_hora TEXT NOT NULL,
      FOREIGN KEY (usuario_id) REFERENCES ${DatabaseTables.usuarios} (id)
        ON DELETE CASCADE ON UPDATE CASCADE
    )
  ''';

  static const String _createCapitalGeneralTable =
      '''
    CREATE TABLE IF NOT EXISTS ${DatabaseTables.capitalGeneral} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      monto_inicial REAL NOT NULL,
      capital_disponible REAL NOT NULL,
      observacion TEXT,
      usuario_id INTEGER NOT NULL,
      estado TEXT NOT NULL DEFAULT 'activo'
        CHECK (estado IN ('activo', 'cerrado')),
      fecha_hora TEXT NOT NULL,
      FOREIGN KEY (usuario_id) REFERENCES ${DatabaseTables.usuarios} (id)
        ON DELETE RESTRICT ON UPDATE CASCADE
    )
  ''';

  static const String _createMovimientosCapitalTable =
      '''
    CREATE TABLE IF NOT EXISTS ${DatabaseTables.movimientosCapital} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      capital_id INTEGER,
      usuario_id INTEGER NOT NULL,
      tipo TEXT NOT NULL,
      monto REAL NOT NULL,
      saldo_antes REAL NOT NULL,
      saldo_despues REAL NOT NULL,
      observacion TEXT,
      referencia_tabla TEXT,
      referencia_id INTEGER,
      fecha_hora TEXT NOT NULL,
      FOREIGN KEY (capital_id) REFERENCES ${DatabaseTables.capitalGeneral} (id)
        ON DELETE SET NULL ON UPDATE CASCADE,
      FOREIGN KEY (usuario_id) REFERENCES ${DatabaseTables.usuarios} (id)
        ON DELETE RESTRICT ON UPDATE CASCADE
    )
  ''';

  static const String _createAsignacionesSaldoTable =
      '''
    CREATE TABLE IF NOT EXISTS ${DatabaseTables.asignacionesSaldo} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      capital_id INTEGER,
      cobrador_id INTEGER NOT NULL,
      admin_id INTEGER NOT NULL,
      monto REAL NOT NULL,
      saldo_antes REAL NOT NULL,
      saldo_despues REAL NOT NULL,
      observacion TEXT,
      fecha_hora TEXT NOT NULL,
      FOREIGN KEY (capital_id) REFERENCES ${DatabaseTables.capitalGeneral} (id)
        ON DELETE SET NULL ON UPDATE CASCADE,
      FOREIGN KEY (cobrador_id) REFERENCES ${DatabaseTables.usuarios} (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
      FOREIGN KEY (admin_id) REFERENCES ${DatabaseTables.usuarios} (id)
        ON DELETE RESTRICT ON UPDATE CASCADE
    )
  ''';

  static const String _createCierresFinancierosTable =
      '''
    CREATE TABLE IF NOT EXISTS ${DatabaseTables.cierresFinancieros} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      capital_id INTEGER,
      admin_id INTEGER NOT NULL,
      fecha TEXT NOT NULL UNIQUE,
      capital_inicial REAL NOT NULL,
      saldo_distribuido REAL NOT NULL,
      total_prestado REAL NOT NULL,
      total_recaudado REAL NOT NULL,
      gastos REAL NOT NULL,
      ganancias REAL NOT NULL,
      capital_final REAL NOT NULL,
      observacion TEXT,
      fecha_hora TEXT NOT NULL,
      FOREIGN KEY (capital_id) REFERENCES ${DatabaseTables.capitalGeneral} (id)
        ON DELETE SET NULL ON UPDATE CASCADE,
      FOREIGN KEY (admin_id) REFERENCES ${DatabaseTables.usuarios} (id)
        ON DELETE RESTRICT ON UPDATE CASCADE
    )
  ''';

  static const String _createEmpresasTable =
      '''
    CREATE TABLE IF NOT EXISTS ${DatabaseTables.empresas} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nombre TEXT NOT NULL,
      identificacion TEXT,
      email TEXT,
      telefono TEXT,
      estado TEXT NOT NULL DEFAULT 'activa'
        CHECK (estado IN ('activa', 'inactiva')),
      fecha_creacion TEXT NOT NULL
    )
  ''';

  static const String _createSuscripcionesTable =
      '''
    CREATE TABLE IF NOT EXISTS ${DatabaseTables.suscripciones} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      empresa_id INTEGER NOT NULL,
      plan TEXT NOT NULL CHECK (plan IN ('basico', 'pro', 'empresa')),
      estado TEXT NOT NULL CHECK (estado IN (
        'prueba',
        'activa',
        'vencida',
        'cancelada'
      )),
      proveedor TEXT NOT NULL DEFAULT 'manual',
      referencia_pago TEXT,
      monto REAL NOT NULL DEFAULT 0,
      fecha_inicio TEXT NOT NULL,
      fecha_fin TEXT NOT NULL,
      fecha_ultimo_pago TEXT,
      observacion TEXT,
      fecha_actualizacion TEXT NOT NULL,
      usuario_id INTEGER,
      FOREIGN KEY (empresa_id) REFERENCES ${DatabaseTables.empresas} (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
      FOREIGN KEY (usuario_id) REFERENCES ${DatabaseTables.usuarios} (id)
        ON DELETE SET NULL ON UPDATE CASCADE
    )
  ''';

  static const String _createLicenciaEventosTable =
      '''
    CREATE TABLE IF NOT EXISTS ${DatabaseTables.licenciaEventos} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      empresa_id INTEGER NOT NULL,
      suscripcion_id INTEGER,
      tipo TEXT NOT NULL,
      descripcion TEXT NOT NULL,
      fecha_hora TEXT NOT NULL,
      usuario_id INTEGER,
      FOREIGN KEY (empresa_id) REFERENCES ${DatabaseTables.empresas} (id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
      FOREIGN KEY (suscripcion_id) REFERENCES ${DatabaseTables.suscripciones} (id)
        ON DELETE SET NULL ON UPDATE CASCADE,
      FOREIGN KEY (usuario_id) REFERENCES ${DatabaseTables.usuarios} (id)
        ON DELETE SET NULL ON UPDATE CASCADE
    )
  ''';

  static const String _createSyncQueueTable =
      '''
    CREATE TABLE IF NOT EXISTS ${DatabaseTables.syncQueue} (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tabla TEXT NOT NULL,
      accion TEXT NOT NULL,
      referencia_id INTEGER,
      payload TEXT NOT NULL,
      estado TEXT NOT NULL DEFAULT 'pendiente'
        CHECK (estado IN ('pendiente', 'sincronizado', 'error')),
      intentos INTEGER NOT NULL DEFAULT 0,
      error TEXT,
      created_at TEXT NOT NULL,
      synced_at TEXT
    )
  ''';
}
