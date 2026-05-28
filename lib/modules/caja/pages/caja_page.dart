import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/session/session_manager.dart';
import '../../../core/utils/currency_formatter.dart';
import '../data/control_financiero_repository.dart';

class CajaPage extends StatefulWidget {
  const CajaPage({super.key});

  @override
  State<CajaPage> createState() => _CajaPageState();
}

class _CajaPageState extends State<CajaPage> {
  final _repository = const ControlFinancieroRepository();
  final _permissionService = const PermissionService();

  bool _cargando = true;
  bool _cerrandoCaja = false;
  CapitalResumen? _capital;
  CajaResumenDiario? _miResumen;
  List<CajaResumenDiario> _resumenes = [];
  List<Map<String, Object?>> _cajas = [];
  List<Map<String, Object?>> _solicitudes = [];
  List<Map<String, Object?>> _cierres = [];
  List<Map<String, Object?>> _movimientos = [];
  List<Map<String, Object?>> _movimientosCapital = [];

  bool get _esAdmin => _permissionService.puedeVerReportesGlobales();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    if (_esAdmin) {
      final resumenes = await _repository.resumenesHoy();
      final cajas = await _repository.cajasRecientes();
      final solicitudes = await _repository.solicitudesPendientes();
      final cierres = await _repository.cierresRecientes();
      final movimientos = await _repository.movimientos();
      final capital = await _repository.resumenCapital();
      final movimientosCapital = await _repository.movimientosCapital();
      if (!mounted) return;
      setState(() {
        _capital = capital;
        _resumenes = resumenes;
        _cajas = cajas;
        _solicitudes = solicitudes;
        _cierres = cierres;
        _movimientos = movimientos;
        _movimientosCapital = movimientosCapital;
        _cargando = false;
      });
    } else {
      final usuario = SessionManager.instance.usuarioActual;
      final resumen = await _repository.resumenDiario(usuario!.id!);
      final movimientos = await _repository.movimientos(cobradorId: usuario.id);
      if (!mounted) return;
      setState(() {
        _miResumen = resumen;
        _movimientos = movimientos;
        _cargando = false;
      });
    }
  }

  Future<void> _registrarGasto() async {
    final usuario = SessionManager.instance.usuarioActual;
    final data = await showDialog<_GastoData>(
      context: context,
      builder: (context) => const _GastoDialog(),
    );
    if (data == null || usuario?.id == null) return;
    try {
      await _repository.registrarGasto(
        cobradorId: usuario!.id!,
        tipo: data.tipo,
        valor: data.valor,
        descripcion: data.descripcion,
      );
      await _cargar();
    } catch (error) {
      _snack(error.toString());
    }
  }

  Future<void> _solicitarSaldo() async {
    final usuario = SessionManager.instance.usuarioActual;
    final data = await showDialog<_MontoData>(
      context: context,
      builder: (context) => const _MontoDialog(
        titulo: 'Solicitar saldo',
        label: 'Monto solicitado',
      ),
    );
    if (data == null || usuario?.id == null) return;
    try {
      await _repository.solicitarSaldo(
        cobradorId: usuario!.id!,
        monto: data.monto,
        observacion: data.observacion,
      );
      await _cargar();
    } catch (error) {
      _snack(error.toString());
    }
  }

  Future<void> _cerrarCaja() async {
    if (_cerrandoCaja) return;
    setState(() => _cerrandoCaja = true);
    final usuario = SessionManager.instance.usuarioActual;
    final data = await showDialog<_MontoData>(
      context: context,
      builder: (context) => const _MontoDialog(
        titulo: 'Cerrar caja',
        label: 'Dinero fisico reportado',
      ),
    );
    if (data == null || usuario?.id == null) {
      if (mounted) setState(() => _cerrandoCaja = false);
      return;
    }
    _snack('Procesando cierre de caja. Por favor espera...');
    try {
      await _repository.cerrarCaja(
        cobradorId: usuario!.id!,
        dineroReportado: data.monto,
        observacion: data.observacion,
      );
      _snack('Cierre de caja enviado para revision.');
      await _cargar();
    } catch (error) {
      _snack(error.toString());
    } finally {
      if (mounted) setState(() => _cerrandoCaja = false);
    }
  }

  Future<void> _asignarSaldo(CajaResumenDiario resumen) async {
    final data = await showDialog<_MontoData>(
      context: context,
      builder: (context) => _MontoDialog(
        titulo: 'Asignar saldo a ${resumen.nombre}',
        label: 'Monto a entregar',
      ),
    );
    if (data == null) return;
    try {
      await _repository.asignarSaldo(
        cobradorId: resumen.cobradorId,
        monto: data.monto,
        observacion: data.observacion,
      );
      await _cargar();
    } catch (error) {
      _snack(error.toString());
    }
  }

  Future<void> _registrarEntrega(Map<String, Object?> cierre) async {
    final data = await showDialog<_MontoData>(
      context: context,
      builder: (context) => _MontoDialog(
        titulo: 'Registrar entrega',
        label: 'Monto entregado',
        montoInicial:
            (cierre['saldo_restante'] as num?)?.toDouble() ??
            (cierre['dinero_reportado'] as num?)?.toDouble(),
      ),
    );
    if (data == null) return;
    try {
      await _repository.registrarEntregaDinero(
        cierreId: cierre['id'] as int,
        montoEntregado: data.monto,
        observacion: data.observacion,
      );
      await _cargar();
    } catch (error) {
      _snack(error.toString());
    }
  }

  Future<void> _revisarCierre(
    Map<String, Object?> cierre,
    String estado,
  ) async {
    final data = await showDialog<_RevisionData>(
      context: context,
      builder: (context) => _RevisionDialog(estado: estado),
    );
    if (data == null) return;
    try {
      await _repository.revisarCierre(
        cierreId: cierre['id'] as int,
        estado: estado,
        observacionAdmin: data.observacion,
      );
      await _cargar();
    } catch (error) {
      _snack(error.toString());
    }
  }

  Future<void> _responderSolicitud(
    Map<String, Object?> solicitud,
    bool aprobar,
  ) async {
    double monto = (solicitud['monto_solicitado'] as num).toDouble();
    String? observacion;
    if (aprobar) {
      final data = await showDialog<_MontoData>(
        context: context,
        builder: (context) => _MontoDialog(
          titulo: 'Aprobar solicitud',
          label: 'Monto aprobado',
          montoInicial: monto,
        ),
      );
      if (data == null) return;
      monto = data.monto;
      observacion = data.observacion;
    }
    try {
      await _repository.responderSolicitud(
        solicitudId: solicitud['id'] as int,
        aprobar: aprobar,
        montoAprobado: monto,
        observacionAdmin: observacion,
      );
      await _cargar();
    } catch (error) {
      _snack(error.toString());
    }
  }

  Future<void> _registrarCapitalInicial() async {
    final data = await showDialog<_MontoData>(
      context: context,
      builder: (context) =>
          const _MontoDialog(titulo: 'Capital inicial', label: 'Monto inicial'),
    );
    if (data == null) return;
    try {
      await _repository.registrarCapitalInicial(
        monto: data.monto,
        observacion: data.observacion,
      );
      await _cargar();
    } catch (error) {
      _snack(error.toString());
    }
  }

  Future<void> _registrarIngresoCapital() async {
    final data = await showDialog<_MontoData>(
      context: context,
      builder: (context) => const _MontoDialog(
        titulo: 'Ingreso de capital',
        label: 'Monto recibido',
      ),
    );
    if (data == null) return;
    try {
      await _repository.registrarIngresoCapital(
        monto: data.monto,
        observacion: data.observacion,
      );
      await _cargar();
    } catch (error) {
      _snack(error.toString());
    }
  }

  Future<void> _registrarRetiroCapital() async {
    final data = await showDialog<_MontoData>(
      context: context,
      builder: (context) => const _MontoDialog(
        titulo: 'Retiro administrativo',
        label: 'Monto retirado',
      ),
    );
    if (data == null) return;
    try {
      await _repository.registrarRetiroCapital(
        monto: data.monto,
        observacion: data.observacion,
      );
      await _cargar();
    } catch (error) {
      _snack(error.toString());
    }
  }

  Future<void> _cerrarFinanciero() async {
    final data = await showDialog<_RevisionData>(
      context: context,
      builder: (context) =>
          const _ObservacionDialog(titulo: 'Cierre financiero diario'),
    );
    if (data == null) return;
    try {
      await _repository.cerrarFinancieroDiario(observacion: data.observacion);
      await _cargar();
    } catch (error) {
      _snack(error.toString());
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Caja'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: _esAdmin ? _adminContent() : _cobradorContent(),
              ),
            ),
    );
  }

  List<Widget> _cobradorContent() {
    final resumen = _miResumen;
    if (resumen == null) return [const SizedBox.shrink()];
    return [
      _ResumenCajaCard(resumen: resumen),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: resumen.cajaAbierta ? _registrarGasto : null,
              icon: const Icon(Icons.receipt_long),
              label: const Text('Gasto'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _solicitarSaldo,
              icon: const Icon(Icons.request_quote),
              label: const Text('Solicitar saldo'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: resumen.cajaAbierta && !_cerrandoCaja ? _cerrarCaja : null,
          icon: _cerrandoCaja
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.lock_clock),
          label: Text(
            _cerrandoCaja
                ? 'Cerrando caja...'
                : resumen.cajaAbierta
                ? 'Cerrar caja'
                : 'Sin caja abierta',
          ),
        ),
      ),
      const SizedBox(height: 18),
      _MovimientosList(movimientos: _movimientos),
    ];
  }

  List<Widget> _adminContent() {
    return [
      if (_capital != null)
        _CapitalGeneralCard(
          resumen: _capital!,
          onCapitalInicial: _registrarCapitalInicial,
          onIngreso: _registrarIngresoCapital,
          onRetiro: _registrarRetiroCapital,
          onCierre: _cerrarFinanciero,
        ),
      if (_capital != null) const SizedBox(height: 18),
      Text('Panel financiero', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      for (final resumen in _resumenes)
        _AdminCobradorCard(
          resumen: resumen,
          onAsignarSaldo: () => _asignarSaldo(resumen),
        ),
      const SizedBox(height: 18),
      Text('Cajas operativas', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (_cajas.isEmpty)
        const Card(child: ListTile(title: Text('Sin cajas registradas')))
      else
        for (final caja in _cajas.take(10)) _CajaOperativaCard(caja: caja),
      const SizedBox(height: 18),
      Text(
        'Solicitudes pendientes',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      if (_solicitudes.isEmpty)
        const Card(
          child: ListTile(
            leading: Icon(Icons.check_circle),
            title: Text('No hay solicitudes pendientes'),
          ),
        )
      else
        for (final solicitud in _solicitudes)
          _SolicitudCard(
            solicitud: solicitud,
            onAprobar: () => _responderSolicitud(solicitud, true),
            onRechazar: () => _responderSolicitud(solicitud, false),
          ),
      const SizedBox(height: 18),
      Text('Cierres recientes', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (_cierres.isEmpty)
        const Card(child: ListTile(title: Text('Sin cierres registrados')))
      else
        for (final cierre in _cierres.take(10))
          _CierreCard(
            cierre: cierre,
            onEntrega: () => _registrarEntrega(cierre),
            onAprobar: () => _revisarCierre(cierre, CierreCajaEstados.aprobado),
            onRechazar: () =>
                _revisarCierre(cierre, CierreCajaEstados.rechazado),
            onRevision: () =>
                _revisarCierre(cierre, CierreCajaEstados.pendienteRevision),
          ),
      const SizedBox(height: 18),
      _MovimientosCapitalList(movimientos: _movimientosCapital),
      const SizedBox(height: 18),
      _MovimientosList(movimientos: _movimientos),
    ];
  }
}

class _ResumenCajaCard extends StatelessWidget {
  const _ResumenCajaCard({required this.resumen});

  final CajaResumenDiario resumen;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Caja de hoy', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Chip(
              avatar: Icon(_estadoCajaIcon(resumen.estadoCaja), size: 16),
              label: Text(_estadoCajaLabel(resumen.estadoCaja)),
              backgroundColor: _estadoCajaColor(
                resumen.estadoCaja,
              ).withValues(alpha: 0.15),
            ),
            if (resumen.cierreEstado != null) ...[
              const SizedBox(height: 6),
              Chip(
                avatar: Icon(
                  _estadoCierreIcon(resumen.cierreEstado!),
                  size: 16,
                ),
                label: Text(_estadoCierreLabel(resumen.cierreEstado!)),
                backgroundColor: _estadoCierreColor(
                  resumen.cierreEstado!,
                ).withValues(alpha: 0.15),
              ),
            ],
            if (resumen.horaApertura != null)
              Text('Apertura: ${resumen.horaApertura}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _Metric(
                  'Saldo inicial',
                  CurrencyFormatter.pesos(resumen.saldoInicial),
                ),
                _Metric(
                  'Disponible',
                  CurrencyFormatter.pesos(resumen.saldoDisponible),
                ),
                _Metric(
                  'Recaudado',
                  CurrencyFormatter.pesos(resumen.totalRecaudado),
                ),
                _Metric(
                  'Prestado',
                  CurrencyFormatter.pesos(resumen.totalPrestado),
                ),
                _Metric('Gastos', CurrencyFormatter.pesos(resumen.gastos)),
                _Metric('Cobros', '${resumen.cantidadCobros}'),
                _Metric('Prestamos', '${resumen.cantidadPrestamos}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CapitalGeneralCard extends StatelessWidget {
  const _CapitalGeneralCard({
    required this.resumen,
    required this.onCapitalInicial,
    required this.onIngreso,
    required this.onRetiro,
    required this.onCierre,
  });

  final CapitalResumen resumen;
  final VoidCallback onCapitalInicial;
  final VoidCallback onIngreso;
  final VoidCallback onRetiro;
  final VoidCallback onCierre;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.account_balance_wallet),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Capital general',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(
                  label: Text(resumen.registrado ? 'Activo' : 'Sin iniciar'),
                  backgroundColor:
                      (resumen.registrado ? Colors.green : Colors.orange)
                          .withValues(alpha: 0.15),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _Metric(
                  'Inicial',
                  CurrencyFormatter.pesos(resumen.capitalInicial),
                ),
                _Metric(
                  'Disponible',
                  CurrencyFormatter.pesos(resumen.capitalDisponible),
                ),
                _Metric(
                  'Saldo cobradores',
                  CurrencyFormatter.pesos(resumen.saldoOperativoCobradores),
                ),
                _Metric(
                  'Dinero en calle',
                  CurrencyFormatter.pesos(resumen.dineroEnCalle),
                ),
                _Metric(
                  'Capital prestado',
                  CurrencyFormatter.pesos(resumen.capitalPrestado),
                ),
                _Metric(
                  'Recaudado',
                  CurrencyFormatter.pesos(resumen.dineroRecaudado),
                ),
                _Metric(
                  'Ganancias',
                  CurrencyFormatter.pesos(resumen.ganancias),
                ),
                _Metric('Gastos', CurrencyFormatter.pesos(resumen.gastos)),
                _Metric(
                  'Capital final',
                  CurrencyFormatter.pesos(resumen.capitalFinal),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: resumen.registrado ? null : onCapitalInicial,
                  icon: const Icon(Icons.savings),
                  label: const Text('Capital inicial'),
                ),
                OutlinedButton.icon(
                  onPressed: resumen.registrado ? onIngreso : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Ingreso'),
                ),
                OutlinedButton.icon(
                  onPressed: resumen.registrado ? onRetiro : null,
                  icon: const Icon(Icons.remove),
                  label: const Text('Retiro'),
                ),
                OutlinedButton.icon(
                  onPressed: resumen.registrado ? onCierre : null,
                  icon: const Icon(Icons.fact_check),
                  label: const Text('Cerrar dia'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminCobradorCard extends StatelessWidget {
  const _AdminCobradorCard({
    required this.resumen,
    required this.onAsignarSaldo,
  });

  final CajaResumenDiario resumen;
  final VoidCallback onAsignarSaldo;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    resumen.nombre,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Chip(
                  label: Text(
                    resumen.cierreEstado == null
                        ? _estadoCajaLabel(resumen.estadoCaja)
                        : _estadoCierreLabel(resumen.cierreEstado!),
                  ),
                  backgroundColor:
                      (resumen.cierreEstado == null
                              ? _estadoCajaColor(resumen.estadoCaja)
                              : _estadoCierreColor(resumen.cierreEstado!))
                          .withValues(alpha: 0.15),
                ),
              ],
            ),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _Metric(
                  'Disponible',
                  CurrencyFormatter.pesos(resumen.saldoDisponible),
                ),
                _Metric(
                  'Prestado',
                  CurrencyFormatter.pesos(resumen.totalPrestado),
                ),
                _Metric(
                  'Recaudado',
                  CurrencyFormatter.pesos(resumen.totalRecaudado),
                ),
                _Metric('Gastos', CurrencyFormatter.pesos(resumen.gastos)),
                _Metric('Visitas', '${resumen.clientesVisitados}'),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: resumen.estadoCaja == CajaEstados.cerrada
                    ? onAsignarSaldo
                    : null,
                icon: const Icon(Icons.add_card),
                label: Text(
                  resumen.estadoCaja == CajaEstados.cerrada
                      ? 'Abrir caja'
                      : 'Jornada activa',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SolicitudCard extends StatelessWidget {
  const _SolicitudCard({
    required this.solicitud,
    required this.onAprobar,
    required this.onRechazar,
  });

  final Map<String, Object?> solicitud;
  final VoidCallback onAprobar;
  final VoidCallback onRechazar;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.request_quote),
        title: Text('${solicitud['cobrador_nombre']}'),
        subtitle: Text(
          'Solicita ${CurrencyFormatter.pesos((solicitud['monto_solicitado'] as num).toDouble())}',
        ),
        trailing: Wrap(
          children: [
            IconButton(
              tooltip: 'Aprobar',
              onPressed: onAprobar,
              icon: const Icon(Icons.check),
            ),
            IconButton(
              tooltip: 'Rechazar',
              onPressed: onRechazar,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

class _CajaOperativaCard extends StatelessWidget {
  const _CajaOperativaCard({required this.caja});

  final Map<String, Object?> caja;

  @override
  Widget build(BuildContext context) {
    final estado = caja['estado'] as String? ?? CajaEstados.cerrada;
    return Card(
      child: ListTile(
        leading: Icon(_estadoCajaIcon(estado), color: _estadoCajaColor(estado)),
        title: Text('${caja['cobrador_nombre']}'),
        subtitle: Text(
          'Fecha ${caja['fecha']} - Apertura ${caja['hora_apertura']}',
        ),
        trailing: Text(
          CurrencyFormatter.pesos(
            (caja['saldo_actual'] as num?)?.toDouble() ?? 0,
          ),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _CierreCard extends StatelessWidget {
  const _CierreCard({
    required this.cierre,
    required this.onEntrega,
    required this.onAprobar,
    required this.onRechazar,
    required this.onRevision,
  });

  final Map<String, Object?> cierre;
  final VoidCallback onEntrega;
  final VoidCallback onAprobar;
  final VoidCallback onRechazar;
  final VoidCallback onRevision;

  @override
  Widget build(BuildContext context) {
    final esperado = (cierre['saldo_restante'] as num?)?.toDouble() ?? 0;
    final reportado = (cierre['dinero_reportado'] as num?)?.toDouble() ?? 0;
    final entregado = (cierre['dinero_entregado'] as num?)?.toDouble() ?? 0;
    final descuadre = reportado - esperado;
    final recaudado = (cierre['total_recaudado'] as num?)?.toDouble() ?? 0;
    final gastos = (cierre['gastos'] as num?)?.toDouble() ?? 0;
    final estado =
        cierre['estado'] as String? ?? CierreCajaEstados.pendienteRevision;
    final evaluado =
        estado == CierreCajaEstados.aprobado ||
        estado == CierreCajaEstados.rechazado;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _estadoCierreIcon(estado),
                  color: _estadoCierreColor(estado),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${cierre['cobrador_nombre']} - ${cierre['fecha']}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Chip(
                  label: Text(_estadoCierreLabel(estado)),
                  backgroundColor: _estadoCierreColor(
                    estado,
                  ).withValues(alpha: 0.15),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _Metric('Debe cerrar', CurrencyFormatter.pesos(esperado)),
                _Metric('Reportado', CurrencyFormatter.pesos(reportado)),
                _Metric('Entregado', CurrencyFormatter.pesos(entregado)),
                _Metric('Descuadre', CurrencyFormatter.pesos(descuadre)),
                _Metric('Recaudado', CurrencyFormatter.pesos(recaudado)),
                _Metric('Gastos', CurrencyFormatter.pesos(gastos)),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 2,
                children: [
                  IconButton(
                    tooltip: 'Entrega',
                    onPressed: evaluado ? null : onEntrega,
                    icon: const Icon(Icons.handshake),
                  ),
                  IconButton(
                    tooltip: 'Aprobar',
                    onPressed: evaluado ? null : onAprobar,
                    icon: const Icon(Icons.check_circle),
                  ),
                  IconButton(
                    tooltip: 'Revision',
                    onPressed: evaluado ? null : onRevision,
                    icon: const Icon(Icons.manage_search),
                  ),
                  IconButton(
                    tooltip: 'Rechazar',
                    onPressed: evaluado ? null : onRechazar,
                    icon: const Icon(Icons.cancel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 145,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _MovimientosList extends StatelessWidget {
  const _MovimientosList({required this.movimientos});

  final List<Map<String, Object?>> movimientos;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Movimientos financieros',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (movimientos.isEmpty)
          const Card(
            child: ListTile(title: Text('Sin movimientos registrados')),
          )
        else
          for (final movimiento in movimientos.take(30))
            Card(
              child: ListTile(
                leading: const Icon(Icons.swap_vert),
                title: Text('${movimiento['tipo']}'),
                subtitle: Text(
                  '${movimiento['usuario_nombre']}'
                  '${movimiento['cliente_nombre'] == null ? '' : ' - ${movimiento['cliente_nombre']}'}',
                ),
                trailing: Text(
                  CurrencyFormatter.pesos(
                    (movimiento['monto'] as num).toDouble(),
                  ),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
      ],
    );
  }
}

class _MovimientosCapitalList extends StatelessWidget {
  const _MovimientosCapitalList({required this.movimientos});

  final List<Map<String, Object?>> movimientos;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Historial de capital',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (movimientos.isEmpty)
          const Card(child: ListTile(title: Text('Sin movimientos de capital')))
        else
          for (final movimiento in movimientos.take(20))
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_balance),
                title: Text('${movimiento['tipo']}'),
                subtitle: Text('${movimiento['usuario_nombre']}'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      CurrencyFormatter.pesos(
                        (movimiento['monto'] as num).toDouble(),
                      ),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      CurrencyFormatter.pesos(
                        (movimiento['saldo_despues'] as num).toDouble(),
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

class _MontoDialog extends StatefulWidget {
  const _MontoDialog({
    required this.titulo,
    required this.label,
    this.montoInicial,
  });

  final String titulo;
  final String label;
  final double? montoInicial;

  @override
  State<_MontoDialog> createState() => _MontoDialogState();
}

class _MontoDialogState extends State<_MontoDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _montoController;
  final _observacionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _montoController = TextEditingController(
      text: widget.montoInicial == null
          ? ''
          : CurrencyFormatter.numero(widget.montoInicial!),
    );
  }

  @override
  void dispose() {
    _montoController.dispose();
    _observacionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _montoController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: widget.label),
              validator: (value) {
                if (CurrencyFormatter.parse(value ?? '') <= 0) {
                  return 'Ingresa un monto valido';
                }
                return null;
              },
            ),
            TextFormField(
              controller: _observacionController,
              decoration: const InputDecoration(labelText: 'Observacion'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _MontoData(
                monto: CurrencyFormatter.parse(_montoController.text),
                observacion: _observacionController.text.trim().isEmpty
                    ? null
                    : _observacionController.text.trim(),
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _GastoDialog extends StatefulWidget {
  const _GastoDialog();

  @override
  State<_GastoDialog> createState() => _GastoDialogState();
}

class _GastoDialogState extends State<_GastoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _valorController = TextEditingController();
  final _descripcionController = TextEditingController();
  String _tipo = GastoTipos.transporte;

  @override
  void dispose() {
    _valorController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar gasto'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _tipo,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: [
                for (final tipo in GastoTipos.todos)
                  DropdownMenuItem(value: tipo, child: Text(tipo)),
              ],
              onChanged: (value) => setState(() => _tipo = value ?? _tipo),
            ),
            TextFormField(
              controller: _valorController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Valor'),
              validator: (value) {
                if (CurrencyFormatter.parse(value ?? '') <= 0) {
                  return 'Ingresa un valor valido';
                }
                return null;
              },
            ),
            TextFormField(
              controller: _descripcionController,
              decoration: const InputDecoration(labelText: 'Descripcion'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _GastoData(
                tipo: _tipo,
                valor: CurrencyFormatter.parse(_valorController.text),
                descripcion: _descripcionController.text.trim().isEmpty
                    ? null
                    : _descripcionController.text.trim(),
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _RevisionDialog extends StatefulWidget {
  const _RevisionDialog({required this.estado});

  final String estado;

  @override
  State<_RevisionDialog> createState() => _RevisionDialogState();
}

class _RevisionDialogState extends State<_RevisionDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_tituloRevision(widget.estado)),
      content: TextField(
        controller: _controller,
        minLines: 2,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Observacion administrativa',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(
              context,
              _RevisionData(
                observacion: _controller.text.trim().isEmpty
                    ? null
                    : _controller.text.trim(),
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _ObservacionDialog extends StatefulWidget {
  const _ObservacionDialog({required this.titulo});

  final String titulo;

  @override
  State<_ObservacionDialog> createState() => _ObservacionDialogState();
}

class _ObservacionDialogState extends State<_ObservacionDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: TextField(
        controller: _controller,
        minLines: 2,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Observacion'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(
              context,
              _RevisionData(
                observacion: _controller.text.trim().isEmpty
                    ? null
                    : _controller.text.trim(),
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _MontoData {
  const _MontoData({required this.monto, this.observacion});
  final double monto;
  final String? observacion;
}

class _GastoData {
  const _GastoData({required this.tipo, required this.valor, this.descripcion});
  final String tipo;
  final double valor;
  final String? descripcion;
}

class _RevisionData {
  const _RevisionData({this.observacion});

  final String? observacion;
}

String _estadoCajaLabel(String estado) {
  return switch (estado) {
    CajaEstados.abierta => 'Abierta',
    CajaEstados.pendienteRevision => 'Pendiente revision',
    CajaEstados.bloqueada => 'Bloqueada',
    _ => 'Cerrada',
  };
}

Color _estadoCajaColor(String estado) {
  return switch (estado) {
    CajaEstados.abierta => Colors.green,
    CajaEstados.pendienteRevision => Colors.orange,
    CajaEstados.bloqueada => Colors.red,
    _ => Colors.grey,
  };
}

IconData _estadoCajaIcon(String estado) {
  return switch (estado) {
    CajaEstados.abierta => Icons.lock_open,
    CajaEstados.pendienteRevision => Icons.manage_search,
    CajaEstados.bloqueada => Icons.block,
    _ => Icons.lock,
  };
}

String _estadoCierreLabel(String estado) {
  return switch (estado) {
    CierreCajaEstados.aprobado => 'Aprobado',
    CierreCajaEstados.rechazado => 'Rechazado',
    CierreCajaEstados.pendienteRevision => 'Pendiente revision',
    _ => estado,
  };
}

Color _estadoCierreColor(String estado) {
  return switch (estado) {
    CierreCajaEstados.aprobado => Colors.green,
    CierreCajaEstados.rechazado => Colors.red,
    CierreCajaEstados.pendienteRevision => Colors.orange,
    _ => Colors.grey,
  };
}

IconData _estadoCierreIcon(String estado) {
  return switch (estado) {
    CierreCajaEstados.aprobado => Icons.check_circle,
    CierreCajaEstados.rechazado => Icons.cancel,
    CierreCajaEstados.pendienteRevision => Icons.manage_search,
    _ => Icons.lock_clock,
  };
}

String _tituloRevision(String estado) {
  return switch (estado) {
    CierreCajaEstados.aprobado => 'Aprobar cierre',
    CierreCajaEstados.rechazado => 'Rechazar cierre',
    _ => 'Solicitar revision',
  };
}
