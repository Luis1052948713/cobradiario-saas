import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';
import '../../../core/services/online_id_mapper.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/session/session_manager.dart';
import '../../auditoria/data/auditoria_repository.dart';
import '../../clientes/models/cliente_model.dart';
import '../../cobros/data/cobro_repository.dart';
import '../../cobros/models/cobro_model.dart';
import '../../notificaciones/data/notificacion_repository.dart';
import '../../prestamos/models/prestamo_model.dart';
import '../models/ruta_cliente_detalle.dart';
import '../models/ruta_model.dart';
import '../models/ruta_reporte_model.dart';

class RutaRepository {
  const RutaRepository({
    this.auditoriaRepository = const AuditoriaRepository(),
    this.cobroRepository = const CobroRepository(),
    this.notificacionRepository = const NotificacionRepository(),
  });

  final AuditoriaRepository auditoriaRepository;
  final CobroRepository cobroRepository;
  final NotificacionRepository notificacionRepository;

  Future<Database> get _db => DatabaseHelper.instance.database;

  Future<int> crearRuta({
    required String nombre,
    required String zona,
    required int cobradorId,
  }) async {
    if (_usaSupabase) {
      final perfil = SessionManager.instance.perfilActual!;
      final cobradorUuid = OnlineIdMapper.instance.uuidFor(cobradorId);
      if (cobradorUuid == null) throw StateError('Cobrador no encontrado.');
      final row = await SupabaseService.requireClient
          .from('rutas')
          .insert({
            'empresa_id': perfil.companyId,
            'nombre': nombre.trim(),
            'zona': zona.trim(),
            'cobrador_id': cobradorUuid,
            'estado': RutaEstados.activa,
          })
          .select()
          .single();
      final id = OnlineIdMapper.instance.localIdFor(row['id'] as String);
      await auditoriaRepository.registrar(
        accion: 'crear',
        modulo: 'rutas',
        referenciaId: id,
        descripcion: 'Ruta creada: $nombre zona=$zona cobrador=$cobradorId',
      );
      return id;
    }

    final db = await _db;
    final id = await db.insert(
      DatabaseTables.rutas,
      RutaModel(
        nombre: nombre.trim(),
        zona: zona.trim(),
        cobradorId: cobradorId,
        fechaCreacion: DateTime.now(),
      ).toMap(),
    );
    await auditoriaRepository.registrar(
      accion: 'crear',
      modulo: 'rutas',
      referenciaId: id,
      descripcion: 'Ruta creada: $nombre zona=$zona cobrador=$cobradorId',
    );
    return id;
  }

  Future<List<RutaModel>> listar({int? cobradorId}) async {
    if (_usaSupabase) {
      final scope = cobradorId ?? _scopeCobrador();
      dynamic query = SupabaseService.requireClient.from('rutas').select();
      final cobradorUuid = OnlineIdMapper.instance.uuidFor(scope);
      if (cobradorUuid != null) query = query.eq('cobrador_id', cobradorUuid);
      final rows = await query.order('nombre');
      return rows.map<RutaModel>(_rutaFromOnline).toList();
    }

    final db = await _db;
    final scope = cobradorId ?? _scopeCobrador();
    final rows = await db.query(
      DatabaseTables.rutas,
      where: scope == null ? null : 'cobrador_id = ?',
      whereArgs: scope == null ? null : [scope],
      orderBy: 'estado ASC, nombre ASC',
    );

    return rows.map(RutaModel.fromMap).toList();
  }

  Future<List<ClienteModel>> clientesDisponiblesParaRuta({
    required int cobradorId,
    int? rutaId,
  }) async {
    if (_usaSupabase) {
      final cobradorUuid = OnlineIdMapper.instance.uuidFor(cobradorId);
      if (cobradorUuid == null) return [];
      final rows = await SupabaseService.requireClient
          .from('clientes')
          .select()
          .eq('cobrador_id', cobradorUuid)
          .eq('estado', AppEstados.activo)
          .order('nombre');
      return rows.map<ClienteModel>(_clienteFromOnline).toList();
    }

    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT c.*
      FROM ${DatabaseTables.clientes} c
      LEFT JOIN ${DatabaseTables.rutaClientes} rc
        ON rc.cliente_id = c.id
        AND rc.estado = ?
        AND (? IS NULL OR rc.ruta_id != ?)
      WHERE c.estado = ?
        AND c.cobrador_id = ?
        AND rc.id IS NULL
      ORDER BY c.nombre ASC
      ''',
      [
        RutaClienteEstados.activo,
        rutaId,
        rutaId,
        AppEstados.activo,
        cobradorId,
      ],
    );

    return rows.map(ClienteModel.fromMap).toList();
  }

  Future<List<RutaClienteDetalle>> listarClientesRuta(int rutaId) async {
    if (_usaSupabase) return _listarClientesRutaOnline(rutaId);

    await _validarAccesoRuta(rutaId);
    final db = await _db;
    final hoy = _dateKey(DateTime.now());
    final rows = await db.rawQuery(
      '''
      SELECT
        rc.id AS ruta_cliente_id,
        rc.ruta_id,
        rc.orden,
        c.*,
        COALESCE(p.id, pv.id) AS prestamo_id,
        COALESCE(p.monto, pv.monto) AS prestamo_monto,
        COALESCE(p.interes, pv.interes) AS prestamo_interes,
        COALESCE(p.total_pagar, pv.total_pagar) AS prestamo_total_pagar,
        COALESCE(p.cuotas, pv.cuotas) AS prestamo_cuotas,
        COALESCE(p.cuota_diaria, pv.cuota_diaria) AS prestamo_cuota_diaria,
        COALESCE(p.saldo, pv.saldo) AS prestamo_saldo,
        COALESCE(p.fecha_inicio, pv.fecha_inicio) AS prestamo_fecha_inicio,
        COALESCE(p.fecha_fin, pv.fecha_fin) AS prestamo_fecha_fin,
        COALESCE(p.estado, pv.estado) AS prestamo_estado,
        rv.estado_visita AS ultimo_estado_visita,
        rv.observacion AS ultima_observacion,
        rv.fecha_hora AS ultima_visita
      FROM ${DatabaseTables.rutaClientes} rc
      INNER JOIN ${DatabaseTables.clientes} c ON c.id = rc.cliente_id
      LEFT JOIN ${DatabaseTables.prestamos} p
        ON p.id = (
          SELECT p2.id
          FROM ${DatabaseTables.prestamos} p2
          WHERE p2.cliente_id = c.id
            AND p2.estado IN (?, ?)
          ORDER BY p2.fecha_inicio DESC
          LIMIT 1
        )
      LEFT JOIN ${DatabaseTables.rutaVisitas} rv
        ON rv.id = (
          SELECT rv2.id
          FROM ${DatabaseTables.rutaVisitas} rv2
          WHERE rv2.ruta_id = rc.ruta_id
            AND rv2.cliente_id = rc.cliente_id
            AND substr(rv2.fecha_hora, 1, 10) = ?
          ORDER BY rv2.fecha_hora DESC
          LIMIT 1
        )
      LEFT JOIN ${DatabaseTables.prestamos} pv ON pv.id = rv.prestamo_id
      WHERE rc.ruta_id = ?
        AND rc.estado = ?
        AND (p.id IS NOT NULL OR rv.id IS NOT NULL)
      ORDER BY
        CASE
          WHEN rv.estado_visita IS NULL THEN 0
          WHEN rv.estado_visita = ? THEN 1
          ELSE 2
        END,
        rc.orden ASC
      ''',
      [
        AppEstados.activo,
        AppEstados.atrasado,
        hoy,
        rutaId,
        RutaClienteEstados.activo,
        RutaVisitaEstados.pago,
      ],
    );

    return rows.map(_detalleFromRow).toList();
  }

  Future<void> agregarCliente({
    required int rutaId,
    required int clienteId,
  }) async {
    if (_usaSupabase) {
      final perfil = SessionManager.instance.perfilActual!;
      final rutaUuid = OnlineIdMapper.instance.uuidFor(rutaId);
      final clienteUuid = OnlineIdMapper.instance.uuidFor(clienteId);
      if (rutaUuid == null || clienteUuid == null) {
        throw StateError('Ruta o cliente online no encontrado.');
      }
      await SupabaseService.requireClient.from('ruta_clientes').insert({
        'empresa_id': perfil.companyId,
        'ruta_id': rutaUuid,
        'cliente_id': clienteUuid,
        'orden': 1,
        'estado': RutaClienteEstados.activo,
      });
      await auditoriaRepository.registrar(
        accion: 'agregar_cliente',
        modulo: 'rutas',
        referenciaId: rutaId,
        descripcion: 'Cliente $clienteId agregado a ruta $rutaId',
      );
      return;
    }

    final db = await _db;
    final ruta = await _buscarRuta(rutaId);
    if (ruta == null) throw StateError('La ruta no existe.');

    final cliente = await _buscarCliente(clienteId);
    if (cliente == null) throw StateError('El cliente no existe.');
    if (cliente.cobradorId != ruta.cobradorId) {
      throw StateError('El cliente no pertenece al cobrador de esta ruta.');
    }

    final existe = await db.query(
      DatabaseTables.rutaClientes,
      where: 'cliente_id = ? AND estado = ?',
      whereArgs: [clienteId, RutaClienteEstados.activo],
      limit: 1,
    );
    if (existe.isNotEmpty) {
      throw StateError('El cliente ya pertenece a una ruta activa.');
    }

    final ordenRow = await db.rawQuery(
      '''
      SELECT COALESCE(MAX(orden), 0) + 1 AS siguiente
      FROM ${DatabaseTables.rutaClientes}
      WHERE ruta_id = ? AND estado = ?
      ''',
      [rutaId, RutaClienteEstados.activo],
    );
    final orden = (ordenRow.first['siguiente'] as int?) ?? 1;

    await db.insert(DatabaseTables.rutaClientes, {
      'ruta_id': rutaId,
      'cliente_id': clienteId,
      'orden': orden,
      'estado': RutaClienteEstados.activo,
      'fecha_asignacion': DateTime.now().toIso8601String(),
    });
    await auditoriaRepository.registrar(
      accion: 'agregar_cliente',
      modulo: 'rutas',
      referenciaId: rutaId,
      descripcion: 'Cliente $clienteId agregado a ruta $rutaId',
    );
  }

  Future<int> agregarClienteARutaDelCobrador({
    required int cobradorId,
    required int clienteId,
  }) async {
    final db = await _db;
    final cliente = await _buscarCliente(clienteId);
    if (cliente == null) throw StateError('El cliente no existe.');
    if (cliente.cobradorId != cobradorId) {
      throw StateError('El cliente no pertenece al cobrador indicado.');
    }

    final asignado = await db.query(
      DatabaseTables.rutaClientes,
      where: 'cliente_id = ? AND estado = ?',
      whereArgs: [clienteId, RutaClienteEstados.activo],
      limit: 1,
    );
    if (asignado.isNotEmpty) {
      return asignado.first['ruta_id'] as int;
    }

    final rutas = await db.query(
      DatabaseTables.rutas,
      where: 'cobrador_id = ? AND estado = ?',
      whereArgs: [cobradorId, RutaEstados.activa],
      orderBy: 'fecha_creacion DESC',
      limit: 1,
    );

    final rutaId = rutas.isEmpty
        ? await crearRuta(
            nombre: 'Ruta diaria',
            zona: cliente.barrio?.isNotEmpty == true
                ? cliente.barrio!
                : 'General',
            cobradorId: cobradorId,
          )
        : rutas.first['id'] as int;

    await agregarCliente(rutaId: rutaId, clienteId: clienteId);
    await notificacionRepository.crear(
      usuarioId: cobradorId,
      titulo: 'Cliente agregado a ruta',
      mensaje: '${cliente.nombre} fue agregado automaticamente a tu ruta.',
      tipo: NotificacionTipos.informativa,
      modulo: 'rutas',
      referenciaId: rutaId,
    );
    return rutaId;
  }

  Future<void> quitarCliente({
    required int rutaClienteId,
    required int rutaId,
  }) async {
    final db = await _db;
    final cobros = await db.query(
      DatabaseTables.rutaVisitas,
      where: 'ruta_id = ? AND cobro_id IS NOT NULL',
      whereArgs: [rutaId],
      limit: 1,
    );
    if (cobros.isNotEmpty) {
      throw StateError(
        'No se puede quitar clientes de una ruta con cobros registrados.',
      );
    }

    await db.update(
      DatabaseTables.rutaClientes,
      {'estado': RutaClienteEstados.removido},
      where: 'id = ?',
      whereArgs: [rutaClienteId],
    );
    await auditoriaRepository.registrar(
      accion: 'quitar_cliente',
      modulo: 'rutas',
      referenciaId: rutaId,
      descripcion: 'Cliente removido de ruta $rutaId',
    );
  }

  Future<void> moverCliente({
    required int rutaId,
    required int rutaClienteId,
    required int direccion,
  }) async {
    final db = await _db;
    final clientes = await listarClientesRuta(rutaId);
    final index = clientes.indexWhere(
      (item) => item.rutaClienteId == rutaClienteId,
    );
    if (index < 0) return;

    final nuevoIndex = index + direccion;
    if (nuevoIndex < 0 || nuevoIndex >= clientes.length) return;

    final actual = clientes[index];
    final destino = clientes[nuevoIndex];

    await db.transaction((txn) async {
      await txn.update(
        DatabaseTables.rutaClientes,
        {'orden': destino.orden},
        where: 'id = ?',
        whereArgs: [actual.rutaClienteId],
      );
      await txn.update(
        DatabaseTables.rutaClientes,
        {'orden': actual.orden},
        where: 'id = ?',
        whereArgs: [destino.rutaClienteId],
      );
    });
    await auditoriaRepository.registrar(
      accion: 'reordenar',
      modulo: 'rutas',
      referenciaId: rutaId,
      descripcion: 'Orden de visita actualizado en ruta $rutaId',
    );
  }

  Future<void> registrarVisita({
    required int rutaId,
    required RutaClienteDetalle detalle,
    required String estadoVisita,
    double monto = 0,
    String? observacion,
  }) async {
    await _validarAccesoRuta(rutaId);
    final usuario = SessionManager.instance.usuarioActual;
    final ruta = await _buscarRuta(rutaId);
    if (ruta == null) throw StateError('La ruta no existe.');
    if (usuario?.esCobrador == true && usuario?.id != ruta.cobradorId) {
      throw StateError('No puedes gestionar rutas de otro cobrador.');
    }

    int? cobroId;
    int? prestamoId = detalle.prestamoActivo?.id;
    if (estadoVisita == RutaVisitaEstados.pago) {
      final prestamo = detalle.prestamoActivo;
      if (prestamo == null || prestamo.id == null) {
        throw StateError('El cliente no tiene un prestamo activo para cobrar.');
      }
      if (monto <= 0) {
        throw StateError('Ingresa un monto cobrado mayor a cero.');
      }
      cobroId = await cobroRepository.registrarCobro(
        CobroModel(
          prestamoId: prestamo.id!,
          cobradorId: ruta.cobradorId,
          monto: monto,
          observacion: observacion,
          fechaPago: DateTime.now(),
        ),
      );
      prestamoId = prestamo.id;
    }

    final db = await _db;
    await db.insert(DatabaseTables.rutaVisitas, {
      'ruta_id': rutaId,
      'cliente_id': detalle.cliente.id,
      'cobrador_id': ruta.cobradorId,
      'prestamo_id': prestamoId,
      'cobro_id': cobroId,
      'estado_visita': estadoVisita,
      'monto_cobrado': monto,
      'observacion': observacion,
      'fecha_hora': DateTime.now().toIso8601String(),
    });
    await auditoriaRepository.registrar(
      accion: estadoVisita == RutaVisitaEstados.pago
          ? 'cobro_ruta'
          : 'visita_ruta',
      modulo: 'rutas',
      referenciaId: rutaId,
      descripcion:
          'Ruta $rutaId cliente=${detalle.cliente.id} estado=$estadoVisita monto=$monto',
    );
    if (estadoVisita == RutaVisitaEstados.pago) {
      await notificacionRepository.marcarLeidasPorReferencia(
        modulo: 'rutas',
        referenciaId: rutaId,
      );
      await notificacionRepository.marcarLeidasPorReferencia(
        modulo: 'clientes',
        referenciaId: detalle.cliente.id,
      );
      if (prestamoId != null) {
        await notificacionRepository.marcarLeidasPorReferencia(
          modulo: 'prestamos',
          referenciaId: prestamoId,
        );
      }
    } else {
      await notificacionRepository.crear(
        usuarioId: ruta.cobradorId,
        titulo: 'Visita registrada',
        mensaje: 'Cliente ${detalle.cliente.nombre}: $estadoVisita.',
        tipo: estadoVisita == RutaVisitaEstados.noQuisoPagar
            ? NotificacionTipos.advertencia
            : NotificacionTipos.informativa,
        modulo: 'rutas',
        referenciaId: rutaId,
      );
    }

    final reporte = await reporteRuta(rutaId);
    if (reporte.totalClientes > 0 && reporte.clientesPendientes == 0) {
      await notificacionRepository.crearParaAdmins(
        titulo: 'Ruta finalizada',
        mensaje: 'La ruta ${ruta.nombre} fue completada.',
        tipo: NotificacionTipos.exito,
        modulo: 'rutas',
        referenciaId: rutaId,
      );
    }
  }

  Future<RutaReporteModel> reporteRuta(int rutaId) async {
    if (_usaSupabase) return _reporteRutaOnline(rutaId);

    final db = await _db;
    final hoy = _dateKey(DateTime.now());
    final totalRow = await db.rawQuery(
      '''
      SELECT COUNT(*) AS total
      FROM ${DatabaseTables.rutaClientes} rc
      WHERE rc.ruta_id = ?
        AND rc.estado = ?
        AND (
          EXISTS (
            SELECT 1
            FROM ${DatabaseTables.prestamos} p
            WHERE p.cliente_id = rc.cliente_id
              AND p.estado IN (?, ?)
          )
          OR EXISTS (
            SELECT 1
            FROM ${DatabaseTables.rutaVisitas} rv
            WHERE rv.ruta_id = rc.ruta_id
              AND rv.cliente_id = rc.cliente_id
              AND substr(rv.fecha_hora, 1, 10) = ?
          )
        )
      ''',
      [
        rutaId,
        RutaClienteEstados.activo,
        AppEstados.activo,
        AppEstados.atrasado,
        hoy,
      ],
    );
    final visitasRow = await db.rawQuery(
      '''
      SELECT
        COUNT(DISTINCT rv.cliente_id) AS visitados,
        SUM(CASE WHEN rv.cobro_id IS NOT NULL THEN 1 ELSE 0 END) AS cobros,
        COALESCE(SUM(rv.monto_cobrado), 0) AS recaudado
      FROM ${DatabaseTables.rutaVisitas} rv
      WHERE rv.ruta_id = ?
        AND substr(rv.fecha_hora, 1, 10) = ?
        AND EXISTS (
          SELECT 1
          FROM ${DatabaseTables.rutaClientes} rc
          WHERE rc.ruta_id = rv.ruta_id
            AND rc.cliente_id = rv.cliente_id
            AND rc.estado = ?
        )
      ''',
      [rutaId, hoy, RutaClienteEstados.activo],
    );

    final total = (totalRow.first['total'] as int?) ?? 0;
    final visitados = (visitasRow.first['visitados'] as int?) ?? 0;
    return RutaReporteModel(
      totalClientes: total,
      clientesVisitados: visitados,
      clientesPendientes: total - visitados,
      cobrosRealizados: (visitasRow.first['cobros'] as int?) ?? 0,
      totalRecaudado: (visitasRow.first['recaudado'] as num).toDouble(),
    );
  }

  Future<void> desactivarRuta(int rutaId) async {
    if (_usaSupabase) {
      final rutaUuid = OnlineIdMapper.instance.uuidFor(rutaId);
      if (rutaUuid == null) return;
      await SupabaseService.requireClient
          .from('rutas')
          .update({'estado': RutaEstados.inactiva}).eq('id', rutaUuid);
      await auditoriaRepository.registrar(
        accion: 'desactivar',
        modulo: 'rutas',
        referenciaId: rutaId,
        descripcion: 'Ruta desactivada',
      );
      return;
    }

    final db = await _db;
    final activos = await db.query(
      DatabaseTables.rutaClientes,
      where: 'ruta_id = ? AND estado = ?',
      whereArgs: [rutaId, RutaClienteEstados.activo],
      limit: 1,
    );
    final cobros = await db.query(
      DatabaseTables.rutaVisitas,
      where: 'ruta_id = ? AND cobro_id IS NOT NULL',
      whereArgs: [rutaId],
      limit: 1,
    );
    if (activos.isNotEmpty || cobros.isNotEmpty) {
      throw StateError(
        'No se puede eliminar una ruta con clientes activos o cobros.',
      );
    }

    await db.update(
      DatabaseTables.rutas,
      {'estado': RutaEstados.inactiva},
      where: 'id = ?',
      whereArgs: [rutaId],
    );
    await auditoriaRepository.registrar(
      accion: 'desactivar',
      modulo: 'rutas',
      referenciaId: rutaId,
      descripcion: 'Ruta desactivada',
    );
  }

  RutaClienteDetalle _detalleFromRow(Map<String, Object?> row) {
    PrestamoModel? prestamo;
    if (row['prestamo_id'] != null) {
      prestamo = PrestamoModel.fromMap({
        'id': row['prestamo_id'],
        'cliente_id': row['id'],
        'monto': row['prestamo_monto'],
        'interes': row['prestamo_interes'],
        'total_pagar': row['prestamo_total_pagar'],
        'cuotas': row['prestamo_cuotas'],
        'cuota_diaria': row['prestamo_cuota_diaria'],
        'saldo': row['prestamo_saldo'],
        'fecha_inicio': row['prestamo_fecha_inicio'],
        'fecha_fin': row['prestamo_fecha_fin'],
        'estado': row['prestamo_estado'],
      });
    }

    return RutaClienteDetalle(
      rutaClienteId: row['ruta_cliente_id'] as int,
      rutaId: row['ruta_id'] as int,
      orden: row['orden'] as int,
      cliente: ClienteModel.fromMap(row),
      prestamoActivo: prestamo,
      ultimoEstadoVisita: row['ultimo_estado_visita'] as String?,
      ultimaObservacion: row['ultima_observacion'] as String?,
      ultimaVisita: row['ultima_visita'] == null
          ? null
          : DateTime.parse(row['ultima_visita'] as String),
    );
  }

  int? _scopeCobrador() {
    final usuario = SessionManager.instance.usuarioActual;
    return usuario?.esCobrador == true ? usuario?.id : null;
  }

  Future<void> _validarAccesoRuta(int rutaId) async {
    final ruta = await _buscarRuta(rutaId);
    final usuario = SessionManager.instance.usuarioActual;
    if (ruta == null) throw StateError('La ruta no existe.');
    if (usuario?.esCobrador == true && ruta.cobradorId != usuario?.id) {
      throw StateError('No puedes ver rutas asignadas a otro cobrador.');
    }
  }

  Future<RutaModel?> _buscarRuta(int id) async {
    if (_usaSupabase) {
      final uuid = OnlineIdMapper.instance.uuidFor(id);
      if (uuid == null) return null;
      final row = await SupabaseService.requireClient
          .from('rutas')
          .select()
          .eq('id', uuid)
          .maybeSingle();
      return row == null ? null : _rutaFromOnline(row);
    }

    final db = await _db;
    final rows = await db.query(
      DatabaseTables.rutas,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return RutaModel.fromMap(rows.first);
  }

  Future<ClienteModel?> _buscarCliente(int id) async {
    if (_usaSupabase) {
      final uuid = OnlineIdMapper.instance.uuidFor(id);
      if (uuid == null) return null;
      final row = await SupabaseService.requireClient
          .from('clientes')
          .select()
          .eq('id', uuid)
          .maybeSingle();
      return row == null ? null : _clienteFromOnline(row);
    }

    final db = await _db;
    final rows = await db.query(
      DatabaseTables.clientes,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ClienteModel.fromMap(rows.first);
  }

  bool get _usaSupabase {
    return SupabaseService.isInitialized &&
        SessionManager.instance.perfilActual != null;
  }

  Future<List<RutaClienteDetalle>> _listarClientesRutaOnline(int rutaId) async {
    final rutaUuid = OnlineIdMapper.instance.uuidFor(rutaId);
    if (rutaUuid == null) return [];
    await _validarAccesoRuta(rutaId);

    final hoy = _dateKey(DateTime.now());
    final rows = await SupabaseService.requireClient
        .from('ruta_clientes')
        .select()
        .eq('ruta_id', rutaUuid)
        .eq('estado', RutaClienteEstados.activo)
        .order('orden');

    final detalles = <RutaClienteDetalle>[];
    for (final row in rows) {
      final clienteUuid = row['cliente_id'] as String;
      final clienteRow = await SupabaseService.requireClient
          .from('clientes')
          .select()
          .eq('id', clienteUuid)
          .maybeSingle();
      if (clienteRow == null) continue;

      final prestamos = await SupabaseService.requireClient
          .from('prestamos')
          .select()
          .eq('cliente_id', clienteUuid)
          .inFilter('estado', [AppEstados.activo, AppEstados.atrasado])
          .order('fecha_inicio', ascending: false)
          .limit(1);

      final visitas = await SupabaseService.requireClient
          .from('ruta_visitas')
          .select()
          .eq('ruta_id', rutaUuid)
          .eq('cliente_id', clienteUuid)
          .gte('fecha_hora', hoy)
          .order('fecha_hora', ascending: false)
          .limit(1);

      final prestamo = prestamos.isEmpty
          ? null
          : _prestamoFromOnline(prestamos.first);
      final visita = visitas.isEmpty ? null : visitas.first;
      if (prestamo == null && visita == null) continue;

      detalles.add(
        RutaClienteDetalle(
          rutaClienteId: OnlineIdMapper.instance.localIdFor(
            row['id'] as String,
          ),
          rutaId: rutaId,
          orden: (row['orden'] as num?)?.toInt() ?? 1,
          cliente: _clienteFromOnline(clienteRow),
          prestamoActivo: prestamo,
          ultimoEstadoVisita: visita?['estado_visita'] as String?,
          ultimaObservacion: visita?['observacion'] as String?,
          ultimaVisita: visita?['fecha_hora'] == null
              ? null
              : DateTime.parse(visita!['fecha_hora'] as String),
        ),
      );
    }

    detalles.sort((a, b) {
      final aGroup = a.ultimoEstadoVisita == null
          ? 0
          : a.ultimoEstadoVisita == RutaVisitaEstados.pago
          ? 1
          : 2;
      final bGroup = b.ultimoEstadoVisita == null
          ? 0
          : b.ultimoEstadoVisita == RutaVisitaEstados.pago
          ? 1
          : 2;
      final groupCompare = aGroup.compareTo(bGroup);
      return groupCompare == 0 ? a.orden.compareTo(b.orden) : groupCompare;
    });
    return detalles;
  }

  Future<RutaReporteModel> _reporteRutaOnline(int rutaId) async {
    final rutaUuid = OnlineIdMapper.instance.uuidFor(rutaId);
    final detalles = await _listarClientesRutaOnline(rutaId);
    final visitados = detalles.where((item) => item.tieneGestionHoy).length;
    final cobros = detalles.where((item) => item.tienePagoHoy).length;
    var recaudado = 0.0;
    if (rutaUuid != null) {
      final hoy = _dateKey(DateTime.now());
      final visitas = await SupabaseService.requireClient
          .from('ruta_visitas')
          .select('monto_cobrado')
          .eq('ruta_id', rutaUuid)
          .gte('fecha_hora', hoy);
      recaudado = visitas.fold<double>(
        0,
        (total, row) =>
            total + ((row['monto_cobrado'] as num?)?.toDouble() ?? 0),
      );
    }
    return RutaReporteModel(
      totalClientes: detalles.length,
      clientesVisitados: visitados,
      clientesPendientes: detalles.length - visitados,
      cobrosRealizados: cobros,
      totalRecaudado: recaudado,
    );
  }

  RutaModel _rutaFromOnline(Map<String, dynamic> row) {
    return RutaModel(
      id: OnlineIdMapper.instance.localIdFor(row['id'] as String),
      nombre: row['nombre'] as String? ?? 'Ruta',
      zona: row['zona'] as String? ?? 'General',
      cobradorId: OnlineIdMapper.instance.localIdFor(
        row['cobrador_id'] as String,
      ),
      estado: row['estado'] as String? ?? RutaEstados.activa,
      fechaCreacion: row['created_at'] == null
          ? DateTime.now()
          : DateTime.parse(row['created_at'] as String),
    );
  }

  ClienteModel _clienteFromOnline(Map<String, dynamic> row) {
    final cobradorUuid = row['cobrador_id'] as String?;
    return ClienteModel(
      id: OnlineIdMapper.instance.localIdFor(row['id'] as String),
      nombre: row['nombre'] as String? ?? '',
      cedula: row['cedula'] as String?,
      telefono: row['telefono'] as String?,
      direccion: row['direccion'] as String?,
      barrio: row['barrio'] as String?,
      referencia: row['referencia'] as String?,
      foto: row['foto_url'] as String?,
      cobradorId: cobradorUuid == null
          ? null
          : OnlineIdMapper.instance.localIdFor(cobradorUuid),
      latitud: (row['latitud'] as num?)?.toDouble(),
      longitud: (row['longitud'] as num?)?.toDouble(),
      estado: row['estado'] as String? ?? AppEstados.activo,
      fechaRegistro: row['created_at'] == null
          ? DateTime.now()
          : DateTime.parse(row['created_at'] as String),
    );
  }

  PrestamoModel _prestamoFromOnline(Map<String, dynamic> row) {
    return PrestamoModel(
      id: OnlineIdMapper.instance.localIdFor(row['id'] as String),
      clienteId: OnlineIdMapper.instance.localIdFor(row['cliente_id'] as String),
      monto: (row['monto'] as num).toDouble(),
      interes: (row['interes'] as num).toDouble(),
      totalPagar: (row['total_pagar'] as num).toDouble(),
      cuotas: row['cuotas'] as int,
      cuotaDiaria: (row['cuota_diaria'] as num).toDouble(),
      saldo: (row['saldo'] as num).toDouble(),
      fechaInicio: DateTime.parse(row['fecha_inicio'] as String),
      fechaFin: row['fecha_fin'] == null
          ? null
          : DateTime.parse(row['fecha_fin'] as String),
      estado: row['estado'] as String? ?? AppEstados.activo,
      frecuenciaPago:
          row['frecuencia_pago'] as String? ?? PrestamoFrecuencias.diario,
    );
  }
}

String _dateKey(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
