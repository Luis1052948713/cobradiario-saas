import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';
import '../../../core/session/session_manager.dart';
import '../../auditoria/data/auditoria_repository.dart';

class SuscripcionResumen {
  const SuscripcionResumen({
    required this.empresaId,
    required this.empresaNombre,
    required this.suscripcionId,
    required this.plan,
    required this.estado,
    required this.proveedor,
    required this.referenciaPago,
    required this.monto,
    required this.fechaInicio,
    required this.fechaFin,
    required this.observacion,
  });

  final int empresaId;
  final String empresaNombre;
  final int? suscripcionId;
  final String plan;
  final String estado;
  final String proveedor;
  final String? referenciaPago;
  final double monto;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final String? observacion;

  bool get activa {
    final vigente = !DateTime.now().isAfter(fechaFin);
    return vigente &&
        (estado == SuscripcionEstados.activa ||
            estado == SuscripcionEstados.prueba);
  }

  bool get enPrueba => estado == SuscripcionEstados.prueba && activa;
  bool get vencida => !activa;

  int get diasRestantes {
    final diff = fechaFin.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff + 1;
  }
}

class SuscripcionRepository {
  const SuscripcionRepository({
    this.auditoriaRepository = const AuditoriaRepository(),
  });

  final AuditoriaRepository auditoriaRepository;

  Future<SuscripcionResumen> obtenerResumen() async {
    final db = await DatabaseHelper.instance.database;
    final empresaId = await _empresaActivaId();
    final rows = await db.rawQuery(
      '''
      SELECT
        e.id AS empresa_id,
        e.nombre AS empresa_nombre,
        s.id AS suscripcion_id,
        s.plan,
        s.estado,
        s.proveedor,
        s.referencia_pago,
        s.monto,
        s.fecha_inicio,
        s.fecha_fin,
        s.observacion
      FROM ${DatabaseTables.empresas} e
      LEFT JOIN ${DatabaseTables.suscripciones} s
        ON s.id = (
          SELECT s2.id
          FROM ${DatabaseTables.suscripciones} s2
          WHERE s2.empresa_id = e.id
          ORDER BY s2.fecha_actualizacion DESC
          LIMIT 1
        )
      WHERE e.id = ?
      LIMIT 1
      ''',
      [empresaId],
    );

    if (rows.isEmpty) {
      throw StateError('No existe empresa configurada para la licencia.');
    }
    final resumen = _fromRow(rows.first);
    if (resumen.vencida &&
        resumen.estado != SuscripcionEstados.vencida &&
        resumen.estado != SuscripcionEstados.cancelada &&
        resumen.suscripcionId != null) {
      await _marcarVencida(resumen);
      return obtenerResumen();
    }
    return resumen;
  }

  Future<bool> licenciaActiva() async {
    return (await obtenerResumen()).activa;
  }

  Future<int> registrarPagoManual({
    required String plan,
    required int meses,
    required double monto,
    String? referenciaPago,
    String? observacion,
  }) async {
    final usuario = SessionManager.instance.usuarioActual;
    if (usuario?.esSuperadmin != true || usuario?.id == null) {
      throw StateError('Solo el superadmin puede activar suscripciones.');
    }
    if (!SuscripcionPlanes.todos.contains(plan)) {
      throw StateError('Plan de suscripcion invalido.');
    }
    if (meses <= 0) throw StateError('Los meses deben ser mayores a cero.');
    if (monto < 0) throw StateError('El monto no puede ser negativo.');

    final db = await DatabaseHelper.instance.database;
    final empresaId = await _empresaActivaId();
    final actual = await obtenerResumen();
    final now = DateTime.now();
    final inicio = actual.activa && actual.fechaFin.isAfter(now)
        ? actual.fechaFin
        : now;
    final fin = _addMonths(inicio, meses);

    final id = await db.transaction((txn) async {
      final suscripcionId = await txn.insert(DatabaseTables.suscripciones, {
        'empresa_id': empresaId,
        'plan': plan,
        'estado': SuscripcionEstados.activa,
        'proveedor': SuscripcionProveedores.manual,
        'referencia_pago': referenciaPago,
        'monto': monto,
        'fecha_inicio': inicio.toIso8601String(),
        'fecha_fin': fin.toIso8601String(),
        'fecha_ultimo_pago': now.toIso8601String(),
        'observacion': observacion,
        'fecha_actualizacion': now.toIso8601String(),
        'usuario_id': usuario!.id,
      });
      await txn.insert(DatabaseTables.licenciaEventos, {
        'empresa_id': empresaId,
        'suscripcion_id': suscripcionId,
        'tipo': 'pago_manual',
        'descripcion': 'Pago manual plan=$plan meses=$meses monto=$monto',
        'fecha_hora': now.toIso8601String(),
        'usuario_id': usuario.id,
      });
      return suscripcionId;
    });

    await auditoriaRepository.registrar(
      accion: 'activar_suscripcion',
      modulo: 'suscripcion',
      referenciaId: id,
      descripcion: 'Suscripcion activada plan=$plan meses=$meses monto=$monto',
    );
    return id;
  }

  Future<String> registrarSolicitudPago({
    required String plan,
    required int meses,
    required double monto,
    String? observacion,
  }) async {
    final usuario = SessionManager.instance.usuarioActual;
    if (usuario?.id == null) {
      throw StateError('Debes iniciar sesion para solicitar renovacion.');
    }
    if (usuario?.esSuperadmin == true) {
      throw StateError('El superadmin registra pagos, no solicitudes.');
    }
    if (!SuscripcionPlanes.todos.contains(plan)) {
      throw StateError('Plan de suscripcion invalido.');
    }
    if (meses <= 0) throw StateError('Los meses deben ser mayores a cero.');
    if (monto < 0) throw StateError('El monto no puede ser negativo.');

    final db = await DatabaseHelper.instance.database;
    final resumen = await obtenerResumen();
    final now = DateTime.now();
    final referencia = 'SUB-${resumen.empresaId}-${now.millisecondsSinceEpoch}';
    final descripcion =
        'Solicitud de pago referencia=$referencia plan=$plan '
        'meses=$meses monto=$monto';

    await db.insert(DatabaseTables.licenciaEventos, {
      'empresa_id': resumen.empresaId,
      'suscripcion_id': resumen.suscripcionId,
      'tipo': 'solicitud_pago',
      'descripcion': observacion?.trim().isNotEmpty == true
          ? '$descripcion observacion=${observacion!.trim()}'
          : descripcion,
      'fecha_hora': now.toIso8601String(),
      'usuario_id': usuario!.id,
    });

    await auditoriaRepository.registrar(
      accion: 'solicitar_pago_suscripcion',
      modulo: 'suscripcion',
      referenciaId: resumen.suscripcionId,
      descripcion: descripcion,
    );
    return referencia;
  }

  Future<void> cancelar(String observacion) async {
    final usuario = SessionManager.instance.usuarioActual;
    if (usuario?.esSuperadmin != true || usuario?.id == null) {
      throw StateError('Solo el superadmin puede cancelar suscripciones.');
    }
    final resumen = await obtenerResumen();
    if (resumen.suscripcionId == null) return;
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now();
    await db.transaction((txn) async {
      await txn.update(
        DatabaseTables.suscripciones,
        {
          'estado': SuscripcionEstados.cancelada,
          'observacion': observacion,
          'fecha_actualizacion': now.toIso8601String(),
          'usuario_id': usuario!.id,
        },
        where: 'id = ?',
        whereArgs: [resumen.suscripcionId],
      );
      await txn.insert(DatabaseTables.licenciaEventos, {
        'empresa_id': resumen.empresaId,
        'suscripcion_id': resumen.suscripcionId,
        'tipo': 'cancelacion',
        'descripcion': observacion,
        'fecha_hora': now.toIso8601String(),
        'usuario_id': usuario.id,
      });
    });
  }

  Future<List<Map<String, Object?>>> eventos() async {
    final db = await DatabaseHelper.instance.database;
    return db.rawQuery('''
      SELECT le.*, u.nombre AS usuario_nombre
      FROM ${DatabaseTables.licenciaEventos} le
      LEFT JOIN ${DatabaseTables.usuarios} u ON u.id = le.usuario_id
      ORDER BY le.fecha_hora DESC
      LIMIT 80
      ''');
  }

  Future<int> _empresaActivaId() async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      DatabaseTables.empresas,
      columns: ['id'],
      where: 'estado = ?',
      whereArgs: ['activa'],
      orderBy: 'id ASC',
      limit: 1,
    );
    if (rows.isNotEmpty) return rows.first['id'] as int;
    return db.insert(DatabaseTables.empresas, {
      'nombre': 'Empresa Demo',
      'identificacion': null,
      'email': null,
      'telefono': null,
      'estado': 'activa',
      'fecha_creacion': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _marcarVencida(SuscripcionResumen resumen) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
        DatabaseTables.suscripciones,
        {'estado': SuscripcionEstados.vencida, 'fecha_actualizacion': now},
        where: 'id = ?',
        whereArgs: [resumen.suscripcionId],
      );
      await txn.insert(DatabaseTables.licenciaEventos, {
        'empresa_id': resumen.empresaId,
        'suscripcion_id': resumen.suscripcionId,
        'tipo': 'vencimiento',
        'descripcion': 'La suscripcion vencio automaticamente.',
        'fecha_hora': now,
        'usuario_id': null,
      });
    });
  }

  SuscripcionResumen _fromRow(Map<String, Object?> row) {
    final now = DateTime.now();
    return SuscripcionResumen(
      empresaId: row['empresa_id'] as int,
      empresaNombre: row['empresa_nombre'] as String? ?? 'Empresa',
      suscripcionId: row['suscripcion_id'] as int?,
      plan: row['plan'] as String? ?? SuscripcionPlanes.pro,
      estado: row['estado'] as String? ?? SuscripcionEstados.vencida,
      proveedor: row['proveedor'] as String? ?? SuscripcionProveedores.manual,
      referenciaPago: row['referencia_pago'] as String?,
      monto: (row['monto'] as num?)?.toDouble() ?? 0,
      fechaInicio: row['fecha_inicio'] == null
          ? now
          : DateTime.parse(row['fecha_inicio'] as String),
      fechaFin: row['fecha_fin'] == null
          ? now
          : DateTime.parse(row['fecha_fin'] as String),
      observacion: row['observacion'] as String?,
    );
  }

  DateTime _addMonths(DateTime value, int months) {
    final targetMonth = value.month + months;
    return DateTime(
      value.year,
      targetMonth,
      value.day,
      value.hour,
      value.minute,
      value.second,
      value.millisecond,
    );
  }
}
