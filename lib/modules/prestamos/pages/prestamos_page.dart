import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../configuracion/data/configuracion_repository.dart';
import '../../clientes/data/cliente_repository.dart';
import '../../clientes/models/cliente_model.dart';
import '../../historial_financiero/pages/historial_financiero_page.dart';
import '../data/prestamo_repository.dart';
import '../models/prestamo_model.dart';

enum _FiltroPrestamos { todos, activos, atrasados, pagados, cancelados }

class PrestamosPage extends StatefulWidget {
  const PrestamosPage({super.key, this.prestamoInicialId});

  final int? prestamoInicialId;

  @override
  State<PrestamosPage> createState() => _PrestamosPageState();
}

class _PrestamosPageState extends State<PrestamosPage> {
  final _prestamoRepository = const PrestamoRepository();
  final _clienteRepository = const ClienteRepository();
  final _configuracionRepository = const ConfiguracionRepository();
  final _permissionService = const PermissionService();
  final _buscarController = TextEditingController();

  List<PrestamoModel> _prestamos = [];
  List<ClienteModel> _clientes = [];
  _FiltroPrestamos _filtro = _FiltroPrestamos.todos;
  bool _cargando = true;
  bool _detalleInicialMostrado = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _buscarController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);

    try {
      final cobradorId = _permissionService.cobradorScope();
      final prestamos = cobradorId == null
          ? await _prestamoRepository.listar()
          : await _prestamoRepository.listarPorCobrador(cobradorId);
      final clientes = await _clienteRepository.listar(cobradorId: cobradorId);

      if (!mounted) return;
      setState(() {
        _prestamos = prestamos;
        _clientes = clientes;
        _cargando = false;
      });
      _mostrarDetalleInicial();
    } catch (error) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar los prestamos: $error')),
      );
    }
  }

  void _mostrarDetalleInicial() {
    if (_detalleInicialMostrado || widget.prestamoInicialId == null) return;
    PrestamoModel? prestamo;
    for (final item in _prestamos) {
      if (item.id == widget.prestamoInicialId) {
        prestamo = item;
        break;
      }
    }
    if (prestamo == null) return;
    final prestamoEncontrado = prestamo;
    _detalleInicialMostrado = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _verDetalle(prestamoEncontrado);
    });
  }

  List<PrestamoModel> get _prestamosFiltrados {
    final query = _buscarController.text.trim().toLowerCase();

    return _prestamos.where((prestamo) {
      final cliente = _clientePorId(prestamo.clienteId);
      final coincideBusqueda =
          query.isEmpty ||
          (cliente?.nombre.toLowerCase().contains(query) ?? false) ||
          (cliente?.cedula?.toLowerCase().contains(query) ?? false) ||
          '${prestamo.id}'.contains(query);

      final coincideFiltro = switch (_filtro) {
        _FiltroPrestamos.activos => prestamo.estado == AppEstados.activo,
        _FiltroPrestamos.atrasados => prestamo.estado == AppEstados.atrasado,
        _FiltroPrestamos.pagados => prestamo.estado == AppEstados.pagado,
        _FiltroPrestamos.cancelados => prestamo.estado == AppEstados.cancelado,
        _FiltroPrestamos.todos => true,
      };

      return coincideBusqueda && coincideFiltro;
    }).toList();
  }

  ClienteModel? _clientePorId(int id) {
    for (final cliente in _clientes) {
      if (cliente.id == id) return cliente;
    }
    return null;
  }

  Future<void> _crearPrestamo() async {
    final clientesActivos = _clientes
        .where((cliente) => cliente.estaActivo && cliente.id != null)
        .toList();

    if (clientesActivos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero crea un cliente activo.')),
      );
      return;
    }

    final interesesPermitidos = await _obtenerInteresesPermitidos();
    final montoMaximoCobrador = await _obtenerMontoMaximoCobrador();
    final cuotasDefecto = await _obtenerCuotasDefecto();
    if (!mounted) return;

    final data = await showModalBottomSheet<_PrestamoFormData>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _PrestamoFormSheet(
        clientes: clientesActivos,
        esCobrador: _permissionService.esCobrador,
        interesesPermitidos: interesesPermitidos,
        montoMaximoCobrador: montoMaximoCobrador,
        cuotasDefecto: cuotasDefecto,
      ),
    );

    if (data == null) return;

    try {
      await _prestamoRepository.crearCalculado(
        clienteId: data.clienteId,
        monto: data.monto,
        interes: data.interes,
        cuotas: data.cuotas,
      );
      await _cargarDatos();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<List<double>> _obtenerInteresesPermitidos() async {
    final value = await _configuracionRepository.obtenerValor(
      AppConfigKeys.interesesPermitidos,
    );
    final intereses = (value ?? '20,30,40')
        .split(',')
        .map((item) => double.tryParse(item.trim()))
        .whereType<double>()
        .where((item) => item >= 0)
        .toList();

    return intereses.isEmpty ? [20, 30, 40] : intereses;
  }

  Future<double> _obtenerMontoMaximoCobrador() async {
    final value = await _configuracionRepository.obtenerValor(
      AppConfigKeys.montoMaximoCobrador,
    );
    final monto = CurrencyFormatter.parse(value ?? '');
    return monto <= 0 ? 500000 : monto;
  }

  Future<int> _obtenerCuotasDefecto() async {
    final value = await _configuracionRepository.obtenerValor(
      AppConfigKeys.cuotasDefecto,
    );
    return int.tryParse(value ?? '') ?? 24;
  }

  Future<void> _cambiarEstado(PrestamoModel prestamo, String estado) async {
    if (prestamo.id == null) return;

    await _prestamoRepository.cambiarEstado(prestamo.id!, estado);
    await _cargarDatos();
  }

  void _verDetalle(PrestamoModel prestamo) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (context) => _PrestamoDetalleSheet(
        prestamo: prestamo,
        cliente: _clientePorId(prestamo.clienteId),
        puedeGestionar: _permissionService.puedeEditarPrestamos(),
        onAtrasar: () {
          Navigator.pop(context);
          _cambiarEstado(prestamo, AppEstados.atrasado);
        },
        onCancelar: () {
          Navigator.pop(context);
          _confirmarCancelar(prestamo);
        },
        onHistorial: () {
          Navigator.pop(context);
          _verHistorialPrestamo(prestamo);
        },
      ),
    );
  }

  Future<void> _verHistorialPrestamo(PrestamoModel prestamo) async {
    if (prestamo.id == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HistorialFinancieroPage(prestamoId: prestamo.id),
      ),
    );
  }

  Future<void> _confirmarCancelar(PrestamoModel prestamo) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar préstamo'),
        content: const Text(
          'El préstamo quedará cancelado y no aparecerá como cartera activa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar préstamo'),
          ),
        ],
      ),
    );

    if (confirmar != true || prestamo.id == null) return;
    await _prestamoRepository.cancelar(prestamo.id!);
    await _cargarDatos();
  }

  @override
  Widget build(BuildContext context) {
    final prestamos = _prestamosFiltrados;
    final puedeGestionar = _permissionService.puedeEditarPrestamos();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Préstamos'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargarDatos,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _permissionService.puedeCrearPrestamos()
          ? FloatingActionButton.extended(
              onPressed: _crearPrestamo,
              icon: const Icon(Icons.add),
              label: const Text('Nuevo'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _cargarDatos,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            _ResumenPrestamos(prestamos: _prestamos),
            const SizedBox(height: 16),
            TextField(
              controller: _buscarController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Buscar por cliente, cedula o numero de préstamo',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _buscarController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar busqueda',
                        onPressed: () {
                          _buscarController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            _FiltrosPrestamos(
              filtro: _filtro,
              onChanged: (filtro) => setState(() => _filtro = filtro),
            ),
            const SizedBox(height: 16),
            if (_cargando)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (prestamos.isEmpty)
              const _EmptyPrestamos()
            else
              ...prestamos.map(
                (prestamo) => _PrestamoCard(
                  prestamo: prestamo,
                  cliente: _clientePorId(prestamo.clienteId),
                  puedeGestionar: puedeGestionar,
                  onTap: () => _verDetalle(prestamo),
                  onHistorial: () => _verHistorialPrestamo(prestamo),
                  onAtrasar: () =>
                      _cambiarEstado(prestamo, AppEstados.atrasado),
                  onCancelar: () => _confirmarCancelar(prestamo),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ResumenPrestamos extends StatelessWidget {
  const _ResumenPrestamos({required this.prestamos});

  final List<PrestamoModel> prestamos;

  @override
  Widget build(BuildContext context) {
    final activos = prestamos
        .where(
          (prestamo) =>
              prestamo.estado == AppEstados.activo ||
              prestamo.estado == AppEstados.atrasado,
        )
        .toList();
    final totalPrestado = prestamos.fold<double>(
      0,
      (total, prestamo) => total + prestamo.monto,
    );
    final saldoPendiente = activos.fold<double>(
      0,
      (total, prestamo) => total + prestamo.saldo,
    );

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ResumenItem(
                icono: Icons.attach_money,
                valor: _money(totalPrestado),
                titulo: 'Prestado',
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ResumenItem(
                icono: Icons.account_balance_wallet,
                valor: _money(saldoPendiente),
                titulo: 'Por cobrar',
                color: Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _ResumenItem(
                icono: Icons.receipt_long,
                valor: '${activos.length}',
                titulo: 'Activos',
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ResumenItem(
                icono: Icons.warning,
                valor:
                    '${prestamos.where((p) => p.estado == AppEstados.atrasado).length}',
                titulo: 'Atrasados',
                color: Colors.red,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ResumenItem extends StatelessWidget {
  const _ResumenItem({
    required this.icono,
    required this.valor,
    required this.titulo,
    required this.color,
  });

  final IconData icono;
  final String valor;
  final String titulo;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icono, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    valor,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FiltrosPrestamos extends StatelessWidget {
  const _FiltrosPrestamos({required this.filtro, required this.onChanged});

  final _FiltroPrestamos filtro;
  final ValueChanged<_FiltroPrestamos> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<_FiltroPrestamos>(
        selected: {filtro},
        onSelectionChanged: (value) => onChanged(value.first),
        segments: const [
          ButtonSegment(
            value: _FiltroPrestamos.todos,
            label: Text('Todos'),
            icon: Icon(Icons.list),
          ),
          ButtonSegment(
            value: _FiltroPrestamos.activos,
            label: Text('Activos'),
            icon: Icon(Icons.check_circle),
          ),
          ButtonSegment(
            value: _FiltroPrestamos.atrasados,
            label: Text('Atrasados'),
            icon: Icon(Icons.warning),
          ),
          ButtonSegment(
            value: _FiltroPrestamos.pagados,
            label: Text('Pagados'),
            icon: Icon(Icons.done_all),
          ),
          ButtonSegment(
            value: _FiltroPrestamos.cancelados,
            label: Text('Cancelados'),
            icon: Icon(Icons.cancel),
          ),
        ],
      ),
    );
  }
}

class _PrestamoCard extends StatelessWidget {
  const _PrestamoCard({
    required this.prestamo,
    required this.cliente,
    required this.puedeGestionar,
    required this.onTap,
    required this.onHistorial,
    required this.onAtrasar,
    required this.onCancelar,
  });

  final PrestamoModel prestamo;
  final ClienteModel? cliente;
  final bool puedeGestionar;
  final VoidCallback onTap;
  final VoidCallback onHistorial;
  final VoidCallback onAtrasar;
  final VoidCallback onCancelar;

  @override
  Widget build(BuildContext context) {
    final progreso = prestamo.totalPagar == 0
        ? 0.0
        : ((prestamo.totalPagar - prestamo.saldo) / prestamo.totalPagar).clamp(
            0.0,
            1.0,
          );

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _estadoColor(prestamo.estado).shade50,
                    child: Icon(
                      Icons.receipt_long,
                      color: _estadoColor(prestamo.estado),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cliente?.nombre ?? 'Cliente #${prestamo.clienteId}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Préstamo #${prestamo.id ?? '-'}',
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                  _EstadoPrestamoChip(estado: prestamo.estado),
                ],
              ),
              const SizedBox(height: 14),
              LinearProgressIndicator(value: progreso),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _DatoPrestamo(
                      label: 'Monto',
                      value: _money(prestamo.monto),
                    ),
                  ),
                  Expanded(
                    child: _DatoPrestamo(
                      label: 'Saldo',
                      value: _money(prestamo.saldo),
                    ),
                  ),
                  Expanded(
                    child: _DatoPrestamo(
                      label: 'Cuota',
                      value: _money(prestamo.cuotaDiaria),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.visibility),
                    label: const Text('Ver detalle'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onHistorial,
                    icon: const Icon(Icons.history),
                    label: const Text('Movimientos'),
                  ),
                  if (puedeGestionar && prestamo.estado == AppEstados.activo)
                    IconButton.filledTonal(
                      tooltip: 'Marcar atrasado',
                      onPressed: onAtrasar,
                      icon: const Icon(Icons.warning),
                    ),
                  if (puedeGestionar &&
                      (prestamo.estado == AppEstados.activo ||
                          prestamo.estado == AppEstados.atrasado))
                    IconButton.filledTonal(
                      tooltip: 'Cancelar préstamo',
                      onPressed: onCancelar,
                      icon: const Icon(Icons.cancel),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DatoPrestamo extends StatelessWidget {
  const _DatoPrestamo({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade700)),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _EstadoPrestamoChip extends StatelessWidget {
  const _EstadoPrestamoChip({required this.estado});

  final String estado;

  @override
  Widget build(BuildContext context) {
    final color = _estadoColor(estado);
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(_estadoIcon(estado), size: 16, color: color),
      label: Text(estado),
      side: BorderSide(color: color.shade300),
    );
  }
}

class _PrestamoDetalleSheet extends StatelessWidget {
  const _PrestamoDetalleSheet({
    required this.prestamo,
    required this.cliente,
    required this.puedeGestionar,
    required this.onAtrasar,
    required this.onCancelar,
    required this.onHistorial,
  });

  final PrestamoModel prestamo;
  final ClienteModel? cliente;
  final bool puedeGestionar;
  final VoidCallback onAtrasar;
  final VoidCallback onCancelar;
  final VoidCallback onHistorial;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const CircleAvatar(child: Icon(Icons.receipt_long)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                cliente?.nombre ?? 'Cliente #${prestamo.clienteId}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            _EstadoPrestamoChip(estado: prestamo.estado),
          ],
        ),
        const SizedBox(height: 18),
        _DetalleItem(label: 'Número', value: '#${prestamo.id ?? '-'}'),
        _DetalleItem(label: 'Monto', value: _money(prestamo.monto)),
        _DetalleItem(label: 'Interés', value: '${prestamo.interes}%'),
        _DetalleItem(
          label: 'Total a pagar',
          value: _money(prestamo.totalPagar),
        ),
        _DetalleItem(label: 'Saldo', value: _money(prestamo.saldo)),
        _DetalleItem(label: 'Cuotas', value: '${prestamo.cuotas}'),
        _DetalleItem(
          label: 'Cuota diaria',
          value: _money(prestamo.cuotaDiaria),
        ),
        _DetalleItem(label: 'Inicio', value: _date(prestamo.fechaInicio)),
        _DetalleItem(label: 'Fin', value: _date(prestamo.fechaFin)),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onHistorial,
          icon: const Icon(Icons.history),
          label: const Text('Ver movimientos del cliente'),
        ),
        const SizedBox(height: 8),
        if (puedeGestionar && prestamo.estado == AppEstados.activo)
          ElevatedButton.icon(
            onPressed: onAtrasar,
            icon: const Icon(Icons.warning),
            label: const Text('Marcar como atrasado'),
          ),
        if (puedeGestionar &&
            (prestamo.estado == AppEstados.activo ||
                prestamo.estado == AppEstados.atrasado))
          TextButton.icon(
            onPressed: onCancelar,
            icon: const Icon(Icons.cancel),
            label: const Text('Cancelar préstamo'),
          ),
      ],
    );
  }
}

class _DetalleItem extends StatelessWidget {
  const _DetalleItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _PrestamoFormSheet extends StatefulWidget {
  const _PrestamoFormSheet({
    required this.clientes,
    required this.esCobrador,
    required this.interesesPermitidos,
    required this.montoMaximoCobrador,
    required this.cuotasDefecto,
  });

  final List<ClienteModel> clientes;
  final bool esCobrador;
  final List<double> interesesPermitidos;
  final double montoMaximoCobrador;
  final int cuotasDefecto;

  @override
  State<_PrestamoFormSheet> createState() => _PrestamoFormSheetState();
}

class _PrestamoFormSheetState extends State<_PrestamoFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _montoController = TextEditingController();
  late final TextEditingController _cuotasController;

  int? _clienteId;
  late double _interesSeleccionado;

  double get _monto => CurrencyFormatter.parse(_montoController.text);
  double get _interes => _interesSeleccionado;
  int get _cuotas => int.tryParse(_cuotasController.text) ?? 0;
  double get _total => _monto + (_monto * _interes / 100);
  double get _cuotaDiaria => _cuotas <= 0 ? 0 : _total / _cuotas;

  @override
  void initState() {
    super.initState();
    _interesSeleccionado = widget.interesesPermitidos.first;
    _cuotasController = TextEditingController(
      text: widget.cuotasDefecto.toString(),
    );
  }

  @override
  void dispose() {
    _montoController.dispose();
    _cuotasController.dispose();
    super.dispose();
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.pop(
      context,
      _PrestamoFormData(
        clienteId: _clienteId!,
        monto: _monto,
        interes: _interes,
        cuotas: _cuotas,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottom + 20),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nuevo préstamo',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              const Text('Selecciona el cliente y confirma el cálculo.'),
              const SizedBox(height: 18),
              DropdownButtonFormField<int>(
                initialValue: _clienteId,
                items: [
                  for (final cliente in widget.clientes)
                    DropdownMenuItem<int>(
                      value: cliente.id!,
                      child: Text(cliente.nombre),
                    ),
                ],
                onChanged: (value) => setState(() => _clienteId = value),
                decoration: const InputDecoration(
                  labelText: 'Cliente',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null) return 'Selecciona un cliente';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _montoController,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Monto entregado',
                  prefixIcon: Icon(Icons.attach_money),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final monto = CurrencyFormatter.parse(value ?? '');
                  if (monto <= 0) {
                    return 'Ingresa un monto válido';
                  }
                  if (widget.esCobrador && monto > widget.montoMaximoCobrador) {
                    return 'Máximo: ${_money(widget.montoMaximoCobrador)}';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<double>(
                      initialValue: _interesSeleccionado,
                      items: [
                        for (final interes in widget.interesesPermitidos)
                          DropdownMenuItem<double>(
                            value: interes,
                            child: Text('${interes.toStringAsFixed(0)}%'),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _interesSeleccionado = value ?? _interesSeleccionado;
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: 'Interés permitido',
                        prefixIcon: Icon(Icons.percent),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _cuotasController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Cuotas',
                        prefixIcon: Icon(Icons.calendar_month),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final cuotas = int.tryParse(value ?? '');
                        if (cuotas == null || cuotas <= 0) {
                          return 'Inválido';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _CalculoPrestamo(
                total: _total,
                cuotaDiaria: _cuotaDiaria,
                cuotas: _cuotas,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _guardar,
                  icon: const Icon(Icons.save),
                  label: const Text('Crear préstamo'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalculoPrestamo extends StatelessWidget {
  const _CalculoPrestamo({
    required this.total,
    required this.cuotaDiaria,
    required this.cuotas,
  });

  final double total;
  final double cuotaDiaria;
  final int cuotas;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cálculo del préstamo',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _InfoCalculo(label: 'Total a pagar', value: _money(total)),
            _InfoCalculo(label: 'Cuota diaria', value: _money(cuotaDiaria)),
            _InfoCalculo(label: 'Duración', value: '$cuotas días'),
          ],
        ),
      ),
    );
  }
}

class _InfoCalculo extends StatelessWidget {
  const _InfoCalculo({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _EmptyPrestamos extends StatelessWidget {
  const _EmptyPrestamos();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 64,
            color: Colors.grey.shade500,
          ),
          const SizedBox(height: 12),
          const Text(
            'No hay préstamos para mostrar',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Crea un préstamo o cambia el filtro seleccionado.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PrestamoFormData {
  const _PrestamoFormData({
    required this.clienteId,
    required this.monto,
    required this.interes,
    required this.cuotas,
  });

  final int clienteId;
  final double monto;
  final double interes;
  final int cuotas;
}

MaterialColor _estadoColor(String estado) {
  return switch (estado) {
    AppEstados.pagado => Colors.green,
    AppEstados.atrasado => Colors.red,
    AppEstados.cancelado => Colors.grey,
    AppEstados.refinanciado => Colors.purple,
    _ => Colors.orange,
  };
}

IconData _estadoIcon(String estado) {
  return switch (estado) {
    AppEstados.pagado => Icons.done_all,
    AppEstados.atrasado => Icons.warning,
    AppEstados.cancelado => Icons.cancel,
    AppEstados.refinanciado => Icons.sync,
    _ => Icons.schedule,
  };
}

String _money(double value) => CurrencyFormatter.pesos(value);

String _date(DateTime? value) {
  if (value == null) return 'Sin fecha';
  return '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.year}';
}
