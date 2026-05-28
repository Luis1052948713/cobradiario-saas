import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../clientes/models/cliente_model.dart';
import '../../cobros/data/cobro_repository.dart';
import '../../cobros/models/cobro_model.dart';
import '../../prestamos/models/prestamo_model.dart';
import '../../usuarios/data/usuario_repository.dart';
import '../../usuarios/models/usuario_model.dart';
import '../data/ruta_repository.dart';
import '../models/ruta_cliente_detalle.dart';
import '../models/ruta_model.dart';
import '../models/ruta_reporte_model.dart';

class RutasPage extends StatefulWidget {
  const RutasPage({super.key, this.rutaInicialId});

  final int? rutaInicialId;

  @override
  State<RutasPage> createState() => _RutasPageState();
}

class _RutasPageState extends State<RutasPage> {
  final _repository = const RutaRepository();
  final _usuarioRepository = const UsuarioRepository();
  final _permissionService = const PermissionService();

  List<RutaModel> _rutas = [];
  Map<int, UsuarioModel> _usuarios = {};
  bool _cargando = true;
  bool _rutaInicialAbierta = false;

  bool get _esAdmin => _permissionService.puedeVerAuditoriaGlobal();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final rutas = await _repository.listar();
      final usuarios = await _usuarioRepository.listar();
      if (!mounted) return;
      setState(() {
        _rutas = rutas;
        _usuarios = {
          for (final usuario in usuarios)
            if (usuario.id != null) usuario.id!: usuario,
        };
        _cargando = false;
      });
      _abrirRutaInicial();
    } catch (error) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar las rutas: $error')),
      );
    }
  }

  void _abrirRutaInicial() {
    if (_rutaInicialAbierta || widget.rutaInicialId == null) return;
    RutaModel? ruta;
    for (final item in _rutas) {
      if (item.id == widget.rutaInicialId) {
        ruta = item;
        break;
      }
    }
    if (ruta == null) return;
    final rutaEncontrada = ruta;
    _rutaInicialAbierta = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _abrirRuta(rutaEncontrada);
    });
  }

  Future<void> _crearRuta() async {
    final data = await showDialog<_RutaFormData>(
      context: context,
      builder: (context) => _RutaFormDialog(
        cobradores: _usuarios.values.where((item) => item.esCobrador).toList(),
      ),
    );
    if (data == null) return;

    try {
      await _repository.crearRuta(
        nombre: data.nombre,
        zona: data.zona,
        cobradorId: data.cobradorId,
      );
      await _cargar();
    } catch (error) {
      _mostrarError(error);
    }
  }

  Future<void> _abrirRuta(RutaModel ruta) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            RutaDetallePage(ruta: ruta, cobrador: _usuarios[ruta.cobradorId]),
      ),
    );
    await _cargar();
  }

  void _mostrarError(Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rutas'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _esAdmin
          ? FloatingActionButton.extended(
              onPressed: _crearRuta,
              icon: const Icon(Icons.add_road),
              label: const Text('Nueva ruta'),
            )
          : null,
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  _RutasHeader(
                    total: _rutas.length,
                    titulo: _esAdmin ? 'Rutas de cobranza' : 'Mis rutas',
                    subtitulo: _esAdmin
                        ? 'Organiza recorridos por cobrador y zona.'
                        : 'Consulta tus recorridos asignados.',
                  ),
                  const SizedBox(height: 12),
                  if (_rutas.isEmpty)
                    const _EstadoVacio(
                      titulo: 'Sin rutas',
                      mensaje: 'Todavia no hay rutas registradas.',
                    )
                  else
                    for (final ruta in _rutas)
                      _RutaCard(
                        ruta: ruta,
                        cobrador: _usuarios[ruta.cobradorId],
                        onTap: () => _abrirRuta(ruta),
                      ),
                ],
              ),
            ),
    );
  }
}

class RutaDetallePage extends StatefulWidget {
  const RutaDetallePage({super.key, required this.ruta, this.cobrador});

  final RutaModel ruta;
  final UsuarioModel? cobrador;

  @override
  State<RutaDetallePage> createState() => _RutaDetallePageState();
}

class _RutaDetallePageState extends State<RutaDetallePage> {
  final _repository = const RutaRepository();
  final _cobroRepository = const CobroRepository();
  final _permissionService = const PermissionService();

  List<RutaClienteDetalle> _clientes = [];
  RutaReporteModel? _reporte;
  bool _cargando = true;

  bool get _esAdmin => _permissionService.puedeVerAuditoriaGlobal();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final clientes = await _repository.listarClientesRuta(widget.ruta.id!);
      final reporte = await _repository.reporteRuta(widget.ruta.id!);
      if (!mounted) return;
      setState(() {
        _clientes = clientes;
        _reporte = reporte;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _cargando = false);
      _mostrarError(error);
    }
  }

  Future<void> _agregarCliente() async {
    final disponibles = await _repository.clientesDisponiblesParaRuta(
      cobradorId: widget.ruta.cobradorId,
      rutaId: widget.ruta.id,
    );
    if (!mounted) return;
    final cliente = await showDialog<ClienteModel>(
      context: context,
      builder: (context) => _AgregarClienteDialog(clientes: disponibles),
    );
    if (cliente?.id == null) return;

    try {
      await _repository.agregarCliente(
        rutaId: widget.ruta.id!,
        clienteId: cliente!.id!,
      );
      await _cargar();
    } catch (error) {
      _mostrarError(error);
    }
  }

  Future<void> _registrarVisita(RutaClienteDetalle detalle) async {
    final historial = detalle.prestamoActivo?.id == null
        ? <CobroModel>[]
        : await _cobroRepository.listar(prestamoId: detalle.prestamoActivo!.id);
    if (!mounted) return;
    final data = await showDialog<_VisitaFormData>(
      context: context,
      builder: (context) => _VisitaDialog(
        detalle: detalle,
        historial: historial.take(3).toList(),
      ),
    );
    if (data == null) return;

    try {
      await _repository.registrarVisita(
        rutaId: widget.ruta.id!,
        detalle: detalle,
        estadoVisita: data.estado,
        monto: data.monto,
        observacion: data.observacion,
      );
      await _cargar();
    } catch (error) {
      _mostrarError(error);
    }
  }

  Future<void> _mover(RutaClienteDetalle detalle, int direccion) async {
    await _repository.moverCliente(
      rutaId: widget.ruta.id!,
      rutaClienteId: detalle.rutaClienteId,
      direccion: direccion,
    );
    await _cargar();
  }

  Future<void> _quitar(RutaClienteDetalle detalle) async {
    try {
      await _repository.quitarCliente(
        rutaClienteId: detalle.rutaClienteId,
        rutaId: widget.ruta.id!,
      );
      await _cargar();
    } catch (error) {
      _mostrarError(error);
    }
  }

  Future<void> _desactivarRuta() async {
    try {
      await _repository.desactivarRuta(widget.ruta.id!);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      _mostrarError(error);
    }
  }

  void _mostrarError(Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  @override
  Widget build(BuildContext context) {
    final reporte = _reporte;
    final porCobrar = _clientes.where((item) => item.porCobrar).toList();
    final pagaron = _clientes.where((item) => item.tienePagoHoy).toList();
    final noPagaron = _clientes.where((item) => item.noPagoHoy).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.ruta.nombre),
        actions: [
          if (_esAdmin)
            IconButton(
              tooltip: 'Desactivar ruta',
              onPressed: _desactivarRuta,
              icon: const Icon(Icons.delete_outline),
            ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _esAdmin
          ? FloatingActionButton.extended(
              onPressed: _agregarCliente,
              icon: const Icon(Icons.person_add),
              label: const Text('Agregar cliente'),
            )
          : null,
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  _RutaDetalleHeader(
                    ruta: widget.ruta,
                    cobrador: widget.cobrador,
                  ),
                  if (reporte != null) ...[
                    const SizedBox(height: 12),
                    _RutaReporte(reporte: reporte),
                  ],
                  const SizedBox(height: 18),
                  _RutaGestionHeader(
                    porCobrar: porCobrar.length,
                    pagaron: pagaron.length,
                    noPagaron: noPagaron.length,
                  ),
                  const SizedBox(height: 8),
                  if (_clientes.isEmpty)
                    const _EstadoVacio(
                      titulo: 'Sin prestamos por cobrar',
                      mensaje:
                          'La ruta no tiene prestamos activos o atrasados para gestionar hoy.',
                    )
                  else ...[
                    _RutaClientesSection(
                      titulo: 'Por cobrar',
                      subtitulo: 'Prestamos activos pendientes de visita',
                      icono: Icons.payments,
                      color: Colors.orange,
                      clientes: porCobrar,
                      emptyMessage:
                          'No quedan prestamos pendientes por cobrar.',
                      itemBuilder: (detalle) => _RutaClienteCard(
                        detalle: detalle,
                        index: _clientes.indexOf(detalle),
                        total: _clientes.length,
                        puedeAdministrar: _esAdmin,
                        onVisita: () => _registrarVisita(detalle),
                        onSubir: () => _mover(detalle, -1),
                        onBajar: () => _mover(detalle, 1),
                        onQuitar: () => _quitar(detalle),
                      ),
                    ),
                    _RutaClientesSection(
                      titulo: 'Pagaron',
                      subtitulo: 'Clientes que ya pagaron cuota hoy',
                      icono: Icons.check_circle,
                      color: Colors.green,
                      clientes: pagaron,
                      emptyMessage: 'Aun no hay pagos registrados en la ruta.',
                      itemBuilder: (detalle) => _RutaClienteCard(
                        detalle: detalle,
                        index: _clientes.indexOf(detalle),
                        total: _clientes.length,
                        puedeAdministrar: _esAdmin,
                        onVisita: () => _registrarVisita(detalle),
                        onSubir: () => _mover(detalle, -1),
                        onBajar: () => _mover(detalle, 1),
                        onQuitar: () => _quitar(detalle),
                      ),
                    ),
                    _RutaClientesSection(
                      titulo: 'No pagaron',
                      subtitulo: 'Visitas sin pago, promesas o no encontrados',
                      icono: Icons.report_problem,
                      color: Colors.red,
                      clientes: noPagaron,
                      emptyMessage: 'No hay visitas sin pago registradas.',
                      itemBuilder: (detalle) => _RutaClienteCard(
                        detalle: detalle,
                        index: _clientes.indexOf(detalle),
                        total: _clientes.length,
                        puedeAdministrar: _esAdmin,
                        onVisita: () => _registrarVisita(detalle),
                        onSubir: () => _mover(detalle, -1),
                        onBajar: () => _mover(detalle, 1),
                        onQuitar: () => _quitar(detalle),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _RutasHeader extends StatelessWidget {
  const _RutasHeader({
    required this.total,
    required this.titulo,
    required this.subtitulo,
  });

  final int total;
  final String titulo;
  final String subtitulo;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.route)),
        title: Text(titulo),
        subtitle: Text(subtitulo),
        trailing: Text(
          '$total',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _RutaCard extends StatelessWidget {
  const _RutaCard({
    required this.ruta,
    required this.cobrador,
    required this.onTap,
  });

  final RutaModel ruta;
  final UsuarioModel? cobrador;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: ruta.estaActiva
              ? Colors.green.withValues(alpha: 0.12)
              : Colors.grey.withValues(alpha: 0.12),
          child: Icon(
            Icons.route,
            color: ruta.estaActiva ? Colors.green : Colors.grey,
          ),
        ),
        title: Text(ruta.nombre),
        subtitle: Text('${ruta.zona} - ${cobrador?.nombre ?? 'Cobrador'}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _RutaDetalleHeader extends StatelessWidget {
  const _RutaDetalleHeader({required this.ruta, required this.cobrador});

  final RutaModel ruta;
  final UsuarioModel? cobrador;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const CircleAvatar(child: Icon(Icons.map)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ruta.zona,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text('Cobrador: ${cobrador?.nombre ?? ruta.cobradorId}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RutaReporte extends StatelessWidget {
  const _RutaReporte({required this.reporte});

  final RutaReporteModel reporte;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: MediaQuery.sizeOf(context).width > 720 ? 5 : 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.45,
      children: [
        _MiniMetric('Clientes', '${reporte.totalClientes}', Colors.blue),
        _MiniMetric('Visitados', '${reporte.clientesVisitados}', Colors.green),
        _MiniMetric(
          'Pendientes',
          '${reporte.clientesPendientes}',
          Colors.amber,
        ),
        _MiniMetric('Cobros', '${reporte.cobrosRealizados}', Colors.teal),
        _MiniMetric(
          'Recaudado',
          CurrencyFormatter.pesos(reporte.totalRecaudado),
          Colors.indigo,
        ),
      ],
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(Icons.circle, size: 12, color: color),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _RutaGestionHeader extends StatelessWidget {
  const _RutaGestionHeader({
    required this.porCobrar,
    required this.pagaron,
    required this.noPagaron,
  });

  final int porCobrar;
  final int pagaron;
  final int noPagaron;

  @override
  Widget build(BuildContext context) {
    final total = porCobrar + pagaron + noPagaron;
    final progreso = total == 0 ? 0.0 : (pagaron + noPagaron) / total;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.route)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gestion de ruta',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('$porCobrar prestamos pendientes por cobrar'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progreso.clamp(0.0, 1.0).toDouble()),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _EstadoConteo(
                  label: 'Por cobrar',
                  value: '$porCobrar',
                  color: Colors.orange,
                  icono: Icons.payments,
                ),
                _EstadoConteo(
                  label: 'Pagaron',
                  value: '$pagaron',
                  color: Colors.green,
                  icono: Icons.check_circle,
                ),
                _EstadoConteo(
                  label: 'No pagaron',
                  value: '$noPagaron',
                  color: Colors.red,
                  icono: Icons.report_problem,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EstadoConteo extends StatelessWidget {
  const _EstadoConteo({
    required this.label,
    required this.value,
    required this.color,
    required this.icono,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Icon(icono, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RutaClientesSection extends StatelessWidget {
  const _RutaClientesSection({
    required this.titulo,
    required this.subtitulo,
    required this.icono,
    required this.color,
    required this.clientes,
    required this.emptyMessage,
    required this.itemBuilder,
  });

  final String titulo;
  final String subtitulo;
  final IconData icono;
  final Color color;
  final List<RutaClienteDetalle> clientes;
  final String emptyMessage;
  final Widget Function(RutaClienteDetalle detalle) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(subtitulo),
                  ],
                ),
              ),
              Chip(
                label: Text('${clientes.length}'),
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (clientes.isEmpty)
            Card(
              child: ListTile(
                leading: Icon(Icons.check, color: color),
                title: Text(emptyMessage),
              ),
            )
          else
            for (final detalle in clientes) itemBuilder(detalle),
        ],
      ),
    );
  }
}

class _RutaClienteCard extends StatelessWidget {
  const _RutaClienteCard({
    required this.detalle,
    required this.index,
    required this.total,
    required this.puedeAdministrar,
    required this.onVisita,
    required this.onSubir,
    required this.onBajar,
    required this.onQuitar,
  });

  final RutaClienteDetalle detalle;
  final int index;
  final int total;
  final bool puedeAdministrar;
  final VoidCallback onVisita;
  final VoidCallback onSubir;
  final VoidCallback onBajar;
  final VoidCallback onQuitar;

  @override
  Widget build(BuildContext context) {
    final color = _estadoColor(detalle);
    final accionLabel = detalle.porCobrar
        ? 'Registrar cobro'
        : detalle.tienePagoHoy
        ? 'Pago registrado'
        : 'Actualizar visita';
    final accionIcon = detalle.porCobrar
        ? Icons.payments
        : detalle.tienePagoHoy
        ? Icons.check_circle
        : Icons.edit_note;

    return Card(
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(width: 5, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: color.withValues(alpha: 0.12),
                          child: Text('${detalle.orden}'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                detalle.cliente.nombre,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                detalle.cliente.direccion?.isNotEmpty == true
                                    ? detalle.cliente.direccion!
                                    : 'Sin direccion',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoChip(
                          Icons.phone,
                          detalle.cliente.telefono ?? 'Sin telefono',
                        ),
                        _InfoChip(
                          Icons.account_balance_wallet,
                          CurrencyFormatter.pesos(detalle.saldoPendiente),
                        ),
                        _InfoChip(
                          Icons.today,
                          CurrencyFormatter.pesos(
                            detalle.prestamoActivo?.cuotaDiaria ?? 0,
                          ),
                        ),
                        _InfoChip(
                          Icons.receipt_long,
                          detalle.prestamoActivo?.estado ?? 'Sin prestamo',
                        ),
                        _InfoChip(
                          Icons.flag,
                          _estadoLabel(detalle.ultimoEstadoVisita),
                        ),
                      ],
                    ),
                    if (detalle.ultimaObservacion?.isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      Text('Obs: ${detalle.ultimaObservacion}'),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                detalle.tienePagoHoy &&
                                    detalle.saldoPendiente <= 0
                                ? null
                                : onVisita,
                            icon: Icon(accionIcon),
                            label: Text(accionLabel),
                          ),
                        ),
                        if (puedeAdministrar) ...[
                          IconButton(
                            tooltip: 'Subir',
                            onPressed: index == 0 ? null : onSubir,
                            icon: const Icon(Icons.arrow_upward),
                          ),
                          IconButton(
                            tooltip: 'Bajar',
                            onPressed: index == total - 1 ? null : onBajar,
                            icon: const Icon(Icons.arrow_downward),
                          ),
                          IconButton(
                            tooltip: 'Quitar',
                            onPressed: onQuitar,
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _estadoColor(RutaClienteDetalle detalle) {
    if (detalle.ultimoEstadoVisita == RutaVisitaEstados.pago) {
      return Colors.green;
    }
    if (detalle.ultimoEstadoVisita == null) {
      return Colors.grey;
    }
    if (detalle.prestamoActivo?.estado == AppEstados.atrasado ||
        detalle.ultimoEstadoVisita == RutaVisitaEstados.noQuisoPagar) {
      return Colors.red;
    }
    return Colors.amber.shade700;
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.icono, this.texto);

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icono, size: 16),
      label: Text(texto),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _RutaFormDialog extends StatefulWidget {
  const _RutaFormDialog({required this.cobradores});

  final List<UsuarioModel> cobradores;

  @override
  State<_RutaFormDialog> createState() => _RutaFormDialogState();
}

class _RutaFormDialogState extends State<_RutaFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _zonaController = TextEditingController();
  int? _cobradorId;

  @override
  void dispose() {
    _nombreController.dispose();
    _zonaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva ruta'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nombreController,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Requerido' : null,
              ),
              TextFormField(
                controller: _zonaController,
                decoration: const InputDecoration(labelText: 'Zona'),
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'Requerido' : null,
              ),
              DropdownButtonFormField<int>(
                initialValue: _cobradorId,
                decoration: const InputDecoration(labelText: 'Cobrador'),
                items: [
                  for (final cobrador in widget.cobradores)
                    if (cobrador.id != null)
                      DropdownMenuItem(
                        value: cobrador.id,
                        child: Text(cobrador.nombre),
                      ),
                ],
                onChanged: (value) => setState(() => _cobradorId = value),
                validator: (value) =>
                    value == null ? 'Selecciona cobrador' : null,
              ),
            ],
          ),
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
              _RutaFormData(
                nombre: _nombreController.text.trim(),
                zona: _zonaController.text.trim(),
                cobradorId: _cobradorId!,
              ),
            );
          },
          child: const Text('Crear'),
        ),
      ],
    );
  }
}

class _RutaFormData {
  const _RutaFormData({
    required this.nombre,
    required this.zona,
    required this.cobradorId,
  });

  final String nombre;
  final String zona;
  final int cobradorId;
}

class _AgregarClienteDialog extends StatelessWidget {
  const _AgregarClienteDialog({required this.clientes});

  final List<ClienteModel> clientes;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar cliente'),
      content: SizedBox(
        width: double.maxFinite,
        child: clientes.isEmpty
            ? const Text('No hay clientes disponibles para esta ruta.')
            : ListView.builder(
                shrinkWrap: true,
                itemCount: clientes.length,
                itemBuilder: (context, index) {
                  final cliente = clientes[index];
                  return ListTile(
                    title: Text(cliente.nombre),
                    subtitle: Text(cliente.direccion ?? 'Sin direccion'),
                    onTap: () => Navigator.pop(context, cliente),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _VisitaDialog extends StatefulWidget {
  const _VisitaDialog({required this.detalle, required this.historial});

  final RutaClienteDetalle detalle;
  final List<CobroModel> historial;

  @override
  State<_VisitaDialog> createState() => _VisitaDialogState();
}

class _VisitaDialogState extends State<_VisitaDialog> {
  final _formKey = GlobalKey<FormState>();
  final _montoController = TextEditingController();
  final _observacionController = TextEditingController();
  String _estado = RutaVisitaEstados.pendiente;

  @override
  void initState() {
    super.initState();
    final prestamo = widget.detalle.prestamoActivo;
    if (widget.detalle.ultimoEstadoVisita != null) {
      _estado = widget.detalle.ultimoEstadoVisita!;
    } else if (prestamo != null) {
      _estado = RutaVisitaEstados.pago;
    }
    if (prestamo != null && _estado == RutaVisitaEstados.pago) {
      _montoController.text = CurrencyFormatter.numero(
        prestamo.cuotaDiaria.clamp(0, prestamo.saldo),
      );
    }
  }

  @override
  void dispose() {
    _montoController.dispose();
    _observacionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prestamo = widget.detalle.prestamoActivo;
    return AlertDialog(
      title: Text(prestamo == null ? 'Resultado de visita' : 'Registrar cobro'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (prestamo != null) ...[
                _CobroRutaResumen(
                  prestamo: prestamo,
                  historial: widget.historial,
                ),
                const SizedBox(height: 10),
              ],
              DropdownButtonFormField<String>(
                initialValue: _estado,
                decoration: const InputDecoration(labelText: 'Estado'),
                items: [
                  for (final estado in RutaVisitaEstados.todos)
                    DropdownMenuItem(
                      value: estado,
                      child: Text(_estadoLabel(estado)),
                    ),
                ],
                onChanged: (value) {
                  setState(() {
                    _estado = value ?? RutaVisitaEstados.pendiente;
                    if (_estado == RutaVisitaEstados.pago &&
                        prestamo != null &&
                        _montoController.text.trim().isEmpty) {
                      _montoController.text = CurrencyFormatter.numero(
                        prestamo.cuotaDiaria.clamp(0, prestamo.saldo),
                      );
                    }
                  });
                },
              ),
              if (_estado == RutaVisitaEstados.pago) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _montoController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Monto cobrado',
                    helperText:
                        'Sugerido: ${CurrencyFormatter.pesos(prestamo?.cuotaDiaria ?? 0)}',
                  ),
                  validator: (value) {
                    final monto = CurrencyFormatter.parse(value ?? '');
                    if (monto <= 0) return 'Ingresa el monto cobrado';
                    if (monto > widget.detalle.saldoPendiente) {
                      return 'No puede superar el saldo';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          _montoController.text = CurrencyFormatter.numero(
                            (prestamo?.cuotaDiaria ?? 0).clamp(
                              0,
                              widget.detalle.saldoPendiente,
                            ),
                          );
                        },
                        icon: const Icon(Icons.today),
                        label: const Text('Cuota'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          _montoController.text = CurrencyFormatter.numero(
                            widget.detalle.saldoPendiente,
                          );
                        },
                        icon: const Icon(Icons.done_all),
                        label: const Text('Saldo'),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              TextFormField(
                controller: _observacionController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Observacion'),
              ),
            ],
          ),
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
              _VisitaFormData(
                estado: _estado,
                monto: _estado == RutaVisitaEstados.pago
                    ? CurrencyFormatter.parse(_montoController.text)
                    : 0,
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

class _CobroRutaResumen extends StatelessWidget {
  const _CobroRutaResumen({
    required this.prestamo,
    required this.historial,
  });

  final PrestamoModel prestamo;
  final List<CobroModel> historial;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ResumenLinea(
              label: 'Saldo pendiente',
              value: CurrencyFormatter.pesos(prestamo.saldo),
            ),
            _ResumenLinea(
              label: prestamo.cuotaLabel,
              value: CurrencyFormatter.pesos(prestamo.cuotaDiaria),
            ),
            _ResumenLinea(label: 'Estado', value: prestamo.estado),
            const SizedBox(height: 6),
            Text(
              'Historial reciente',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            if (historial.isEmpty)
              const Text('Sin pagos previos')
            else
              for (final cobro in historial)
                Text(
                  '${_date(cobro.fechaPago)} - ${CurrencyFormatter.pesos(cobro.monto)}',
                ),
          ],
        ),
      ),
    );
  }
}

class _ResumenLinea extends StatelessWidget {
  const _ResumenLinea({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _VisitaFormData {
  const _VisitaFormData({
    required this.estado,
    required this.monto,
    this.observacion,
  });

  final String estado;
  final double monto;
  final String? observacion;
}

class _EstadoVacio extends StatelessWidget {
  const _EstadoVacio({required this.titulo, required this.mensaje});

  final String titulo;
  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          const Icon(Icons.route, size: 48, color: Colors.grey),
          const SizedBox(height: 8),
          Text(titulo, style: Theme.of(context).textTheme.titleMedium),
          Text(mensaje, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

String _estadoLabel(String? estado) {
  switch (estado) {
    case RutaVisitaEstados.pago:
      return 'Pago';
    case RutaVisitaEstados.pendiente:
      return 'Pendiente';
    case RutaVisitaEstados.noEncontrado:
      return 'No encontrado';
    case RutaVisitaEstados.negocioCerrado:
      return 'Negocio cerrado';
    case RutaVisitaEstados.prometePagar:
      return 'Promete pagar';
    case RutaVisitaEstados.noQuisoPagar:
      return 'No quiso pagar';
    default:
      return 'No visitado';
  }
}

String _date(DateTime value) {
  return '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.year}';
}
