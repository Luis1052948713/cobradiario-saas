import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../caja/data/control_financiero_repository.dart';
import '../../caja/pages/caja_page.dart';
import '../../caja/pages/gastos_page.dart';
import '../../clientes/pages/clientes_page.dart';
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
  final _controlFinancieroRepository = const ControlFinancieroRepository();
  final _permissionService = const PermissionService();
  final _buscarController = TextEditingController();

  List<RutaClienteDetalle> _clientes = [];
  RutaReporteModel? _reporte;
  CajaResumenDiario? _cajaResumen;
  DateTime _fechaRuta = DateTime.now();
  bool _cargando = true;

  bool get _esAdmin => _permissionService.puedeVerAuditoriaGlobal();

  List<RutaClienteDetalle> get _clientesFiltrados {
    final query = _buscarController.text.trim().toLowerCase();
    if (query.isEmpty) return _clientes;
    return _clientes.where((detalle) {
      final cliente = detalle.cliente;
      return cliente.nombre.toLowerCase().contains(query) ||
          (cliente.telefono?.toLowerCase().contains(query) ?? false) ||
          (cliente.cedula?.toLowerCase().contains(query) ?? false) ||
          (cliente.barrio?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscarController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final clientes = await _repository.listarClientesRuta(widget.ruta.id!);
      final reporte = await _repository.reporteRuta(widget.ruta.id!);
      final cajaResumen = await _controlFinancieroRepository.resumenDiario(
        widget.ruta.cobradorId,
      );
      if (!mounted) return;
      setState(() {
        _clientes = clientes;
        _reporte = reporte;
        _cajaResumen = cajaResumen;
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

  Future<void> _abrirClienteNuevo() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ClientesPage()),
    );
    await _cargar();
  }

  Future<void> _abrirGastos() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const GastosPage()),
    );
    await _cargar();
  }

  Future<void> _abrirCaja() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CajaPage()),
    );
    await _cargar();
  }

  Future<void> _seleccionarFechaRuta() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaRuta,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (fecha == null) return;
    setState(() => _fechaRuta = fecha);
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
    final clientes = _clientesFiltrados;
    final porCobrar = clientes.where((item) => item.porCobrar).toList();
    final pagaron = clientes.where((item) => item.tienePagoHoy).toList();
    final noPagaron = clientes.where((item) => item.noPagoHoy).toList();
    final sinPrestamo = clientes
        .where((item) => item.prestamoActivo == null && !item.tieneGestionHoy)
        .toList();

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
                  const SizedBox(height: 12),
                  _RutaCalendarioCard(
                    fecha: _fechaRuta,
                    onSeleccionarFecha: _seleccionarFechaRuta,
                  ),
                  const SizedBox(height: 12),
                  _RutaAccionesRapidas(
                    esAdmin: _esAdmin,
                    onAgregarClienteRuta: _agregarCliente,
                    onClienteNuevo: _abrirClienteNuevo,
                    onGastos: _abrirGastos,
                    onCaja: _abrirCaja,
                  ),
                  const SizedBox(height: 12),
                  _RutaBusqueda(
                    controller: _buscarController,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  _ResumenDiaRuta(
                    fecha: _fechaRuta,
                    clientes: _clientes,
                    reporte: reporte,
                    cajaResumen: _cajaResumen,
                  ),
                  const SizedBox(height: 18),
                  _RutaGestionHeader(
                    porCobrar: porCobrar.length,
                    pagaron: pagaron.length,
                    noPagaron: noPagaron.length + sinPrestamo.length,
                  ),
                  const SizedBox(height: 8),
                  if (clientes.isEmpty)
                    const _EstadoVacio(
                      titulo: 'Sin clientes',
                      mensaje:
                          'No hay clientes asignados que coincidan con la busqueda.',
                    )
                  else ...[
                    _RutaClientesSection(
                      titulo: 'Por cobrar',
                      subtitulo: 'Clientes con saldo pendiente',
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
                      subtitulo: 'Pagos registrados hoy',
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
                      titulo: 'Seguimiento',
                      subtitulo: 'No pago, ausentes o siguiente dia',
                      icono: Icons.report_problem,
                      color: Colors.red,
                      clientes: [...noPagaron, ...sinPrestamo],
                      emptyMessage: 'No hay seguimientos pendientes.',
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

class _RutaCalendarioCard extends StatelessWidget {
  const _RutaCalendarioCard({
    required this.fecha,
    required this.onSeleccionarFecha,
  });

  final DateTime fecha;
  final VoidCallback onSeleccionarFecha;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.calendar_month)),
        title: const Text('Fecha de ruta'),
        subtitle: Text(_date(fecha)),
        trailing: IconButton(
          tooltip: 'Cambiar fecha',
          onPressed: onSeleccionarFecha,
          icon: const Icon(Icons.edit_calendar),
        ),
      ),
    );
  }
}

class _RutaAccionesRapidas extends StatelessWidget {
  const _RutaAccionesRapidas({
    required this.esAdmin,
    required this.onAgregarClienteRuta,
    required this.onClienteNuevo,
    required this.onGastos,
    required this.onCaja,
  });

  final bool esAdmin;
  final VoidCallback onAgregarClienteRuta;
  final VoidCallback onClienteNuevo;
  final VoidCallback onGastos;
  final VoidCallback onCaja;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (esAdmin)
          FilledButton.icon(
            onPressed: onAgregarClienteRuta,
            icon: const Icon(Icons.playlist_add),
            label: const Text('Asignar'),
          ),
        OutlinedButton.icon(
          onPressed: onClienteNuevo,
          icon: const Icon(Icons.person_add),
          label: const Text('Cliente'),
        ),
        OutlinedButton.icon(
          onPressed: onGastos,
          icon: const Icon(Icons.receipt_long),
          label: const Text('Gastos'),
        ),
        OutlinedButton.icon(
          onPressed: onCaja,
          icon: const Icon(Icons.account_balance_wallet),
          label: const Text('Ingresos'),
        ),
      ],
    );
  }
}

class _RutaBusqueda extends StatelessWidget {
  const _RutaBusqueda({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: 'Buscar cliente',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpiar',
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                icon: const Icon(Icons.close),
              ),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _ResumenDiaRuta extends StatelessWidget {
  const _ResumenDiaRuta({
    required this.fecha,
    required this.clientes,
    required this.reporte,
    required this.cajaResumen,
  });

  final DateTime fecha;
  final List<RutaClienteDetalle> clientes;
  final RutaReporteModel? reporte;
  final CajaResumenDiario? cajaResumen;

  @override
  Widget build(BuildContext context) {
    final ausentes = clientes
        .where(
          (item) =>
              item.ultimoEstadoVisita == RutaVisitaEstados.noEncontrado ||
              item.ultimoEstadoVisita == RutaVisitaEstados.negocioCerrado,
        )
        .length;
    final aplazados = clientes
        .where((item) => item.ultimoEstadoVisita == RutaVisitaEstados.prometePagar)
        .length;
    final recaudoEsperado = clientes.fold<double>(
      0,
      (total, item) =>
          total +
          ((item.prestamoActivo?.cuotaDiaria ?? 0).clamp(
            0,
            item.saldoPendiente,
          )).toDouble(),
    );
    final clientesNuevos = clientes
        .where((item) => _sameDay(item.cliente.fechaRegistro, fecha))
        .length;
    final recaudoDia =
        reporte?.totalRecaudado ?? cajaResumen?.totalRecaudado ?? 0;
    final pagosRegistrados =
        reporte?.cobrosRealizados ?? cajaResumen?.cantidadCobros ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.summarize),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Resumen del dia',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _ResumenGrid(
              items: [
                _ResumenDato('Fecha ruta', _date(fecha)),
                _ResumenDato('Clientes', '${clientes.length}'),
                _ResumenDato('Clientes nuevos', '$clientesNuevos'),
                _ResumenDato('Ausentes', '$ausentes'),
                _ResumenDato('Siguiente dia', '$aplazados'),
                _ResumenDato('Pagos', '$pagosRegistrados'),
                _ResumenDato(
                  'Caja inicial',
                  CurrencyFormatter.pesos(cajaResumen?.saldoInicial ?? 0),
                ),
                _ResumenDato(
                  'Recaudo esperado',
                  CurrencyFormatter.pesos(recaudoEsperado),
                ),
                _ResumenDato(
                  'Recaudo dia',
                  CurrencyFormatter.pesos(recaudoDia),
                ),
                _ResumenDato('Efectivo', CurrencyFormatter.pesos(recaudoDia)),
                _ResumenDato('Transferencia', CurrencyFormatter.pesos(0)),
                _ResumenDato(
                  'Total ventas',
                  CurrencyFormatter.pesos(cajaResumen?.totalPrestado ?? 0),
                ),
                _ResumenDato('Retiros caja', CurrencyFormatter.pesos(0)),
                _ResumenDato(
                  'Egresos',
                  CurrencyFormatter.pesos(cajaResumen?.gastos ?? 0),
                ),
                _ResumenDato('Ingresos', CurrencyFormatter.pesos(recaudoDia)),
                _ResumenDato(
                  'Saldo en caja',
                  CurrencyFormatter.pesos(cajaResumen?.saldoDisponible ?? 0),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumenGrid extends StatelessWidget {
  const _ResumenGrid({required this.items});

  final List<_ResumenDato> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.15,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  item.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ResumenDato {
  const _ResumenDato(this.label, this.value);

  final String label;
  final String value;
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

    final prestamo = detalle.prestamoActivo;
    final cuota = prestamo == null
        ? 'Sin prestamo'
        : '${prestamo.cuotaLabel}: ${CurrencyFormatter.pesos(prestamo.cuotaDiaria)}';

    return Card(
      child: InkWell(
        onTap: onVisita,
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
                                  '$cuota - Saldo: ${CurrencyFormatter.pesos(detalle.saldoPendiente)}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
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
                            prestamo == null
                                ? 'Sin cuota'
                                : CurrencyFormatter.pesos(
                                    prestamo.cuotaDiaria,
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

class _AgregarClienteDialog extends StatefulWidget {
  const _AgregarClienteDialog({required this.clientes});

  final List<ClienteModel> clientes;

  @override
  State<_AgregarClienteDialog> createState() => _AgregarClienteDialogState();
}

class _AgregarClienteDialogState extends State<_AgregarClienteDialog> {
  final _buscarController = TextEditingController();

  @override
  void dispose() {
    _buscarController.dispose();
    super.dispose();
  }

  List<ClienteModel> get _clientesFiltrados {
    final query = _buscarController.text.trim().toLowerCase();
    if (query.isEmpty) return widget.clientes;
    return widget.clientes.where((cliente) {
      return cliente.nombre.toLowerCase().contains(query) ||
          (cliente.telefono?.toLowerCase().contains(query) ?? false) ||
          (cliente.cedula?.toLowerCase().contains(query) ?? false) ||
          (cliente.barrio?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final clientes = _clientesFiltrados;
    return AlertDialog(
      title: const Text('Agregar cliente'),
      content: SizedBox(
        width: double.maxFinite,
        child: widget.clientes.isEmpty
            ? const Text('No hay clientes disponibles para esta ruta.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _buscarController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Buscar cliente',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 360,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: clientes.length,
                      itemBuilder: (context, index) {
                        final cliente = clientes[index];
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(cliente.nombre),
                          subtitle: Text(
                            [
                              cliente.telefono,
                              cliente.barrio,
                              cliente.direccion,
                            ].whereType<String>().join(' - '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.pop(context, cliente),
                        );
                      },
                    ),
                  ),
                ],
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
  final _productoController = TextEditingController(text: 'Prestamo');
  final _totalVentaController = TextEditingController();
  final _montoController = TextEditingController();
  final _numeroCuotasController = TextEditingController();
  final _observacionController = TextEditingController();
  String _formaPago = 'efectivo';
  _GestionRutaTipo _tipoGestion = _GestionRutaTipo.cuota;
  String _estado = RutaVisitaEstados.pendiente;

  @override
  void initState() {
    super.initState();
    final prestamo = widget.detalle.prestamoActivo;
    if (widget.detalle.ultimoEstadoVisita != null) {
      _estado = widget.detalle.ultimoEstadoVisita!;
      _tipoGestion = switch (_estado) {
        RutaVisitaEstados.pago => _GestionRutaTipo.cuota,
        RutaVisitaEstados.prometePagar => _GestionRutaTipo.siguienteDia,
        _ => _GestionRutaTipo.noPago,
      };
    } else if (prestamo != null) {
      _estado = RutaVisitaEstados.pago;
    } else {
      _estado = RutaVisitaEstados.noQuisoPagar;
      _tipoGestion = _GestionRutaTipo.noPago;
    }
    if (prestamo != null && _estado == RutaVisitaEstados.pago) {
      _montoController.text = CurrencyFormatter.numero(
        prestamo.cuotaDiaria.clamp(0, prestamo.saldo),
      );
      _totalVentaController.text = CurrencyFormatter.numero(prestamo.totalPagar);
      _numeroCuotasController.text = prestamo.cuotas.toString();
    }
  }

  @override
  void dispose() {
    _productoController.dispose();
    _totalVentaController.dispose();
    _montoController.dispose();
    _numeroCuotasController.dispose();
    _observacionController.dispose();
    super.dispose();
  }

  int get _cuotasPagadas {
    final prestamo = widget.detalle.prestamoActivo;
    if (prestamo == null || prestamo.cuotaDiaria <= 0) return 0;
    return ((prestamo.totalPagar - prestamo.saldo) / prestamo.cuotaDiaria)
        .floor()
        .clamp(0, prestamo.cuotas)
        .toInt();
  }

  int get _cuotasPendientes {
    final prestamo = widget.detalle.prestamoActivo;
    if (prestamo == null) return 0;
    return (prestamo.cuotas - _cuotasPagadas)
        .clamp(0, prestamo.cuotas)
        .toInt();
  }

  double get _valorPagar => CurrencyFormatter.parse(_montoController.text);

  double get _nuevoSaldo {
    return (widget.detalle.saldoPendiente - _valorPagar)
        .clamp(0, double.infinity)
        .toDouble();
  }

  void _cambiarTipoGestion(_GestionRutaTipo tipo) {
    final prestamo = widget.detalle.prestamoActivo;
    if (prestamo == null &&
        (tipo == _GestionRutaTipo.cuota || tipo == _GestionRutaTipo.abono)) {
      tipo = _GestionRutaTipo.noPago;
    }
    setState(() {
      _tipoGestion = tipo;
      switch (tipo) {
        case _GestionRutaTipo.cuota:
          _estado = RutaVisitaEstados.pago;
          _montoController.text = CurrencyFormatter.numero(
            (prestamo?.cuotaDiaria ?? 0).clamp(0, widget.detalle.saldoPendiente),
          );
          break;
        case _GestionRutaTipo.abono:
          _estado = RutaVisitaEstados.pago;
          if (CurrencyFormatter.parse(_montoController.text) <= 0) {
            _montoController.text = CurrencyFormatter.numero(
              (prestamo?.cuotaDiaria ?? 0).clamp(
                0,
                widget.detalle.saldoPendiente,
              ),
            );
          }
          break;
        case _GestionRutaTipo.noPago:
          _estado = RutaVisitaEstados.noQuisoPagar;
          _montoController.text = '0';
          break;
        case _GestionRutaTipo.siguienteDia:
          _estado = RutaVisitaEstados.prometePagar;
          _montoController.text = '0';
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final prestamo = widget.detalle.prestamoActivo;
    return AlertDialog(
      title: Text(widget.detalle.cliente.nombre),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ClienteGestionHeader(
                detalle: widget.detalle,
                cuotasPagadas: _cuotasPagadas,
                cuotasPendientes: _cuotasPendientes,
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<_GestionRutaTipo>(
                  selected: {_tipoGestion},
                  onSelectionChanged: (values) =>
                      _cambiarTipoGestion(values.first),
                  segments: const [
                    ButtonSegment(
                      value: _GestionRutaTipo.cuota,
                      icon: Icon(Icons.today),
                      label: Text('Cuota'),
                    ),
                    ButtonSegment(
                      value: _GestionRutaTipo.abono,
                      icon: Icon(Icons.payments),
                      label: Text('Abono'),
                    ),
                    ButtonSegment(
                      value: _GestionRutaTipo.noPago,
                      icon: Icon(Icons.money_off),
                      label: Text('No pago'),
                    ),
                    ButtonSegment(
                      value: _GestionRutaTipo.siguienteDia,
                      icon: Icon(Icons.event_repeat),
                      label: Text('Siguiente dia'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (prestamo != null) ...[
                _CobroRutaResumen(
                  prestamo: prestamo,
                  historial: widget.historial,
                ),
                const SizedBox(height: 10),
              ],
              TextFormField(
                controller: _productoController,
                decoration: const InputDecoration(
                  labelText: 'Producto',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _totalVentaController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Total venta',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              _ResumenLinea(
                label: 'Saldo actual',
                value: CurrencyFormatter.pesos(widget.detalle.saldoPendiente),
              ),
              if (_estado == RutaVisitaEstados.pago) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _montoController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Valor a pagar',
                    border: const OutlineInputBorder(),
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
                TextFormField(
                  controller: _numeroCuotasController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Numero de cuotas',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              _ResumenLinea(
                label: 'Nuevo saldo',
                value: CurrencyFormatter.pesos(_nuevoSaldo),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _formaPago,
                decoration: const InputDecoration(
                  labelText: 'Forma de pago',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'efectivo', child: Text('Efectivo')),
                  DropdownMenuItem(
                    value: 'transferencia',
                    child: Text('Transferencia'),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _formaPago = value ?? _formaPago),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _observacionController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Observacion',
                  border: OutlineInputBorder(),
                ),
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
                observacion: _observacionFinal(),
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  String? _observacionFinal() {
    final partes = [
      'Gestion: ${_tipoGestion.label}',
      'Producto: ${_productoController.text.trim()}',
      'Forma de pago: $_formaPago',
      if (_totalVentaController.text.trim().isNotEmpty)
        'Total venta: ${_totalVentaController.text.trim()}',
      if (_numeroCuotasController.text.trim().isNotEmpty)
        'Cuotas: ${_numeroCuotasController.text.trim()}',
      if (_observacionController.text.trim().isNotEmpty)
        _observacionController.text.trim(),
    ];
    return partes.join(' | ');
  }
}

enum _GestionRutaTipo { cuota, abono, noPago, siguienteDia }

extension _GestionRutaTipoLabel on _GestionRutaTipo {
  String get label {
    return switch (this) {
      _GestionRutaTipo.cuota => 'Cuota',
      _GestionRutaTipo.abono => 'Abono',
      _GestionRutaTipo.noPago => 'No pago',
      _GestionRutaTipo.siguienteDia => 'Siguiente dia',
    };
  }
}

class _ClienteGestionHeader extends StatelessWidget {
  const _ClienteGestionHeader({
    required this.detalle,
    required this.cuotasPagadas,
    required this.cuotasPendientes,
  });

  final RutaClienteDetalle detalle;
  final int cuotasPagadas;
  final int cuotasPendientes;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              detalle.cliente.nombre,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(Icons.done_all, 'Pagadas: $cuotasPagadas'),
                _InfoChip(Icons.pending_actions, 'Pendientes: $cuotasPendientes'),
                _InfoChip(
                  Icons.phone,
                  detalle.cliente.telefono ?? 'Sin celular',
                ),
              ],
            ),
          ],
        ),
      ),
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

bool _sameDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}
