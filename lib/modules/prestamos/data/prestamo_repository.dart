import 'package:sqflite/sqflite.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/database_tables.dart';
import '../../../core/services/online_id_mapper.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/session/session_manager.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../auditoria/data/auditoria_repository.dart';
import '../../caja/data/control_financiero_repository.dart';
import '../../notificaciones/data/notificacion_repository.dart';
import '../../rutas/data/ruta_repository.dart';
import '../models/prestamo_model.dart';

class PrestamoRepository {
  const PrestamoRepository({
    this.auditoriaRepository = const AuditoriaRepository(),
    this.controlFinancieroRepository = const ControlFinancieroRepository(),
    this.notificacionRepository = const NotificacionRepository(),
    this.rutaRepository = const RutaRepository(),
  });

  final AuditoriaRepository auditoriaRepository;
  final ControlFinancieroRepository controlFinancieroRepository;
  final NotificacionRepository notificacionRepository;
  final RutaRepository rutaRepository;

  Future<Database> get _db => DatabaseHelper.instance.database;

  Future<int> crearCalculado({
    required int clienteId,
    required double monto,
    required double interes,
    required int cuotas,
    DateTime? fechaInicio,
  }) async {
    if (cuotas <= 0) {
      throw ArgumentError('El numero de cuotas debe ser mayor a cero.');
    }

    final totalPagar = monto + (monto * interes / 100);
    final cuotaDiaria = totalPagar / cuotas;
    final inicio = fechaInicio ?? DateTime.now();
    final fin = inicio.add(Duration(days: cuotas));

    final prestamo = PrestamoModel(
      clienteId: clienteId,
      monto: monto,
      interes: interes,
      totalPagar: totalPagar,
      cuotas: cuotas,
      cuotaDiaria: cuotaDiaria,
      saldo: totalPagar,
      fechaInicio: inicio,
      fechaFin: fin,
    );

    if (_usaSupabase) {
      return _crearCalculadoOnline(prestamo);
    }

    final db = await _db;
    final usuarioActual = SessionManager.instance.usuarioActual;
    final clientes = await db.query(
      DatabaseTables.clientes,
      columns: ['cobrador_id'],
      where: 'id = ?',
      whereArgs: [clienteId],
      limit: 1,
    );
    if (clientes.isEmpty) throw StateError('El cliente no existe.');
    final cobradorId = clientes.first['cobrador_id'] as int?;
    if (cobradorId == null) {
      throw StateError('El cliente debe tener un cobrador asignado.');
    }
    if (usuarioActual?.esCobrador == true && usuarioActual?.id != cobradorId) {
      throw StateError('No puedes prestar a clientes de otro cobrador.');
    }
    await controlFinancieroRepository.validarCobradorPuedeOperar(cobradorId);

    final id = await db.transaction((txn) async {
      final prestamoId = await txn.insert(
        DatabaseTables.prestamos,
        prestamo.toMap(),
      );
      await controlFinancieroRepository.descontarPorPrestamo(
        txn: txn,
        cobradorId: cobradorId,
        clienteId: clienteId,
        monto: monto,
        prestamoId: prestamoId,
      );
      return prestamoId;
    });
    await auditoriaRepository.registrar(
      accion: 'crear',
      modulo: 'prestamos',
      referenciaId: id,
      descripcion:
          'Prestamo creado cliente=$clienteId monto=$monto interes=$interes cuotas=$cuotas',
    );
    if (monto >= 1000000) {
      await notificacionRepository.crearParaAdmins(
        titulo: 'Prestamo de alto valor',
        mensaje:
            'Se registro un prestamo por ${CurrencyFormatter.pesos(monto)} para cliente $clienteId.',
        tipo: NotificacionTipos.advertencia,
        modulo: 'prestamos',
        referenciaId: id,
      );
    }
    await rutaRepository.agregarClienteARutaDelCobrador(
      cobradorId: cobradorId,
      clienteId: clienteId,
    );
    return id;
  }

  Future<List<PrestamoModel>> listar({int? clienteId}) async {
    if (_usaSupabase) {
      dynamic query = SupabaseService.requireClient.from('prestamos').select();
      final clienteUuid = OnlineIdMapper.instance.uuidFor(clienteId);
      if (clienteUuid != null) query = query.eq('cliente_id', clienteUuid);
      final rows = await query.order('fecha_inicio', ascending: false);
      return rows.map<PrestamoModel>(_fromOnline).toList();
    }

    final db = await _db;
    final rows = await db.query(
      DatabaseTables.prestamos,
      where: clienteId == null ? null : 'cliente_id = ?',
      whereArgs: clienteId == null ? null : [clienteId],
      orderBy: 'fecha_inicio DESC',
    );

    return rows.map(PrestamoModel.fromMap).toList();
  }

  Future<List<PrestamoModel>> listarPorCobrador(int cobradorId) async {
    if (_usaSupabase) {
      final cobradorUuid = OnlineIdMapper.instance.uuidFor(cobradorId);
      if (cobradorUuid == null) return [];
      final clientes = await SupabaseService.requireClient
          .from('clientes')
          .select('id')
          .eq('cobrador_id', cobradorUuid);
      final clienteIds = clientes.map<String>((row) => row['id'] as String).toList();
      if (clienteIds.isEmpty) return [];
      final rows = await SupabaseService.requireClient
          .from('prestamos')
          .select()
          .inFilter('cliente_id', clienteIds)
          .order('fecha_inicio', ascending: false);
      return rows.map<PrestamoModel>(_fromOnline).toList();
    }

    final db = await _db;
    final rows = await db.rawQuery(
      '''
      SELECT p.*
      FROM ${DatabaseTables.prestamos} p
      INNER JOIN ${DatabaseTables.clientes} c ON c.id = p.cliente_id
      WHERE c.cobrador_id = ?
      ORDER BY p.fecha_inicio DESC
      ''',
      [cobradorId],
    );

    return rows.map(PrestamoModel.fromMap).toList();
  }

  Future<List<PrestamoModel>> listarActivos({int? cobradorId}) async {
    if (_usaSupabase) {
      if (cobradorId != null) {
        final prestamos = await listarPorCobrador(cobradorId);
        return prestamos
            .where((p) => p.estado == AppEstados.activo || p.estado == AppEstados.atrasado)
            .toList();
      }
      final rows = await SupabaseService.requireClient
          .from('prestamos')
          .select()
          .inFilter('estado', [AppEstados.activo, AppEstados.atrasado])
          .order('fecha_inicio', ascending: false);
      return rows.map<PrestamoModel>(_fromOnline).toList();
    }

    final db = await _db;

    if (cobradorId == null) {
      final rows = await db.query(
        DatabaseTables.prestamos,
        where: 'estado IN (?, ?)',
        whereArgs: [AppEstados.activo, AppEstados.atrasado],
        orderBy: 'fecha_inicio DESC',
      );
      return rows.map(PrestamoModel.fromMap).toList();
    }

    final rows = await db.rawQuery(
      '''
      SELECT p.*
      FROM ${DatabaseTables.prestamos} p
      INNER JOIN ${DatabaseTables.clientes} c ON c.id = p.cliente_id
      WHERE p.estado IN (?, ?) AND c.cobrador_id = ?
      ORDER BY p.fecha_inicio DESC
      ''',
      [AppEstados.activo, AppEstados.atrasado, cobradorId],
    );

    return rows.map(PrestamoModel.fromMap).toList();
  }

  Future<PrestamoModel?> buscarPorId(int id) async {
    if (_usaSupabase) {
      final uuid = OnlineIdMapper.instance.uuidFor(id);
      if (uuid == null) return null;
      final row = await SupabaseService.requireClient
          .from('prestamos')
          .select()
          .eq('id', uuid)
          .maybeSingle();
      if (row == null) return null;
      return _fromOnline(row);
    }

    final db = await _db;
    final rows = await db.query(
      DatabaseTables.prestamos,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return PrestamoModel.fromMap(rows.first);
  }

  Future<int> actualizar(PrestamoModel prestamo) async {
    if (_usaSupabase) {
      final uuid = OnlineIdMapper.instance.uuidFor(prestamo.id);
      final clienteUuid = OnlineIdMapper.instance.uuidFor(prestamo.clienteId);
      if (uuid == null || clienteUuid == null) {
        throw StateError('Prestamo online no encontrado.');
      }
      await SupabaseService.requireClient.from('prestamos').update({
        'cliente_id': clienteUuid,
        'monto': prestamo.monto,
        'interes': prestamo.interes,
        'total_pagar': prestamo.totalPagar,
        'cuotas': prestamo.cuotas,
        'cuota_diaria': prestamo.cuotaDiaria,
        'saldo': prestamo.saldo,
        'fecha_inicio': prestamo.fechaInicio.toIso8601String(),
        'fecha_fin': prestamo.fechaFin?.toIso8601String(),
        'estado': prestamo.estado,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', uuid);
      await auditoriaRepository.registrar(
        accion: 'actualizar',
        modulo: 'prestamos',
        referenciaId: prestamo.id,
        descripcion: 'Prestamo actualizado',
      );
      return 1;
    }

    final db = await _db;
    final result = await db.update(
      DatabaseTables.prestamos,
      prestamo.toMap(),
      where: 'id = ?',
      whereArgs: [prestamo.id],
    );
    await auditoriaRepository.registrar(
      accion: 'actualizar',
      modulo: 'prestamos',
      referenciaId: prestamo.id,
      descripcion: 'Prestamo actualizado',
    );
    return result;
  }

  Future<int> cancelar(int id) async {
    if (_usaSupabase) return cambiarEstado(id, AppEstados.cancelado);

    final db = await _db;
    final result = await db.update(
      DatabaseTables.prestamos,
      {'estado': AppEstados.cancelado},
      where: 'id = ?',
      whereArgs: [id],
    );
    await auditoriaRepository.registrar(
      accion: 'cancelar',
      modulo: 'prestamos',
      referenciaId: id,
      descripcion: 'Prestamo cancelado',
    );
    return result;
  }

  Future<int> cambiarEstado(int id, String estado) async {
    if (_usaSupabase) {
      final uuid = OnlineIdMapper.instance.uuidFor(id);
      if (uuid == null) throw StateError('Prestamo online no encontrado.');
      await SupabaseService.requireClient
          .from('prestamos')
          .update({'estado': estado, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', uuid);
      await auditoriaRepository.registrar(
        accion: 'cambiar_estado',
        modulo: 'prestamos',
        referenciaId: id,
        descripcion: 'Prestamo cambio estado a $estado',
      );
      return 1;
    }

    final db = await _db;
    final result = await db.update(
      DatabaseTables.prestamos,
      {'estado': estado},
      where: 'id = ?',
      whereArgs: [id],
    );
    await auditoriaRepository.registrar(
      accion: 'cambiar_estado',
      modulo: 'prestamos',
      referenciaId: id,
      descripcion: 'Prestamo cambio estado a $estado',
    );
    return result;
  }

  bool get _usaSupabase {
    return SupabaseService.isInitialized &&
        SessionManager.instance.perfilActual?.companyId != null;
  }

  Future<int> _crearCalculadoOnline(PrestamoModel prestamo) async {
    final perfil = SessionManager.instance.perfilActual!;
    final clienteUuid = OnlineIdMapper.instance.uuidFor(prestamo.clienteId);
    if (clienteUuid == null) throw StateError('El cliente no existe.');

    final cliente = await SupabaseService.requireClient
        .from('clientes')
        .select('cobrador_id')
        .eq('id', clienteUuid)
        .single();
    final cobradorUuid = cliente['cobrador_id'] as String?;
    if (cobradorUuid == null) {
      throw StateError('El cliente debe tener un cobrador asignado.');
    }
    if (perfil.esCobrador && perfil.id != cobradorUuid) {
      throw StateError('No puedes prestar a clientes de otro cobrador.');
    }
    await controlFinancieroRepository.validarCobradorPuedeOperar(
      OnlineIdMapper.instance.localIdFor(cobradorUuid),
    );

    final row = await SupabaseService.requireClient
        .from('prestamos')
        .insert({
          'empresa_id': perfil.companyId,
          'cliente_id': clienteUuid,
          'monto': prestamo.monto,
          'interes': prestamo.interes,
          'total_pagar': prestamo.totalPagar,
          'cuotas': prestamo.cuotas,
          'cuota_diaria': prestamo.cuotaDiaria,
          'saldo': prestamo.saldo,
          'fecha_inicio': prestamo.fechaInicio.toIso8601String(),
          'fecha_fin': prestamo.fechaFin?.toIso8601String(),
          'estado': prestamo.estado,
        })
        .select()
        .single();
    await controlFinancieroRepository.descontarPrestamoOnline(
      cobradorId: OnlineIdMapper.instance.localIdFor(cobradorUuid),
      monto: prestamo.monto,
    );

    final id = OnlineIdMapper.instance.localIdFor(row['id'] as String);
    await auditoriaRepository.registrar(
      accion: 'crear',
      modulo: 'prestamos',
      referenciaId: id,
      descripcion:
          'Prestamo creado cliente=${prestamo.clienteId} monto=${prestamo.monto} interes=${prestamo.interes} cuotas=${prestamo.cuotas}',
    );
    return id;
  }

  PrestamoModel _fromOnline(Map<String, dynamic> row) {
    final uuid = row['id'] as String;
    final clienteUuid = row['cliente_id'] as String;
    return PrestamoModel(
      id: OnlineIdMapper.instance.localIdFor(uuid),
      clienteId: OnlineIdMapper.instance.localIdFor(clienteUuid),
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
    );
  }
}
