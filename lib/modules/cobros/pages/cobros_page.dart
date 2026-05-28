import 'package:flutter/material.dart';

import '../../../core/permissions/permission_service.dart';
import '../../../core/session/session_manager.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../clientes/data/cliente_repository.dart';
import '../../clientes/models/cliente_model.dart';
import '../../historial_financiero/pages/historial_financiero_page.dart';
import '../../prestamos/data/prestamo_repository.dart';
import '../../prestamos/models/prestamo_model.dart';
import '../data/cobro_repository.dart';
import '../models/cobro_model.dart';

enum _VistaCobros { pendientes, historial }

class CobrosPage extends StatefulWidget {
  const CobrosPage({
    super.key,
    this.cobroInicialId,
    this.mostrarHistorial = false,
  });

  final int? cobroInicialId;
  final bool mostrarHistorial;

  @override
  State<CobrosPage> createState() => _CobrosPageState();
}

class _CobrosPageState extends State<CobrosPage> {
  final _cobroRepository = const CobroRepository();
  final _prestamoRepository = const PrestamoRepository();
  final _clienteRepository = const ClienteRepository();
  final _permissionService = const PermissionService();
  final _buscarController = TextEditingController();

  List<CobroModel> _cobros = [];
  List<PrestamoModel> _prestamosActivos = [];
  List<ClienteModel> _clientes = [];
  _VistaCobros _vista = _VistaCobros.pendientes;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    if (widget.mostrarHistorial) {
      _vista = _VistaCobros.historial;
    }
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
      final cobros = await _cobroRepository.listar(cobradorId: cobradorId);
      final clientes = await _clienteRepository.listar(cobradorId: cobradorId);
      final prestamos = await _prestamoRepository.listarActivos(
        cobradorId: cobradorId,
      );

      if (!mounted) return;
      setState(() {
        _cobros = cobros;
        _prestamosActivos = prestamos;
        _clientes = clientes;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar los cobros: $error')),
      );
    }
  }

  List<PrestamoModel> get _prestamosFiltrados {
    final query = _buscarController.text.trim().toLowerCase();

    if (query.isEmpty) return _prestamosActivos;

    return _prestamosActivos.where((prestamo) {
      final cliente = _clientePorId(prestamo.clienteId);
      return (cliente?.nombre.toLowerCase().contains(query) ?? false) ||
          (cliente?.cedula?.toLowerCase().contains(query) ?? false) ||
          '${prestamo.id}'.contains(query);
    }).toList();
  }

  ClienteModel? _clientePorId(int id) {
    for (final cliente in _clientes) {
      if (cliente.id == id) return cliente;
    }
    return null;
  }

  PrestamoModel? _prestamoPorId(int id) {
    for (final prestamo in _prestamosActivos) {
      if (prestamo.id == id) return prestamo;
    }
    return null;
  }

  Future<void> _abrirRegistro({PrestamoModel? prestamo}) async {
    if (_prestamosActivos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay préstamos activos para cobrar.')),
      );
      return;
    }

    final cobro = await showModalBottomSheet<CobroModel>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _CobroFormSheet(
        prestamos: _prestamosActivos,
        clientes: _clientes,
        prestamoInicial: prestamo,
        cobradorId: SessionManager.instance.usuarioActual?.id ?? 1,
      ),
    );

    if (cobro == null) return;

    try {
      await _cobroRepository.registrarCobro(cobro);
      await _cargarDatos();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cobro registrado correctamente.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _registrarVisita(PrestamoModel prestamo) async {
    final observacion = await showDialog<String>(
      context: context,
      builder: (context) => const _VisitaDialog(),
    );

    if (observacion == null || observacion.trim().isEmpty) return;

    try {
      await _cobroRepository.marcarVisita(
        prestamoId: prestamo.id!,
        cobradorId: SessionManager.instance.usuarioActual?.id ?? 1,
        observacion: observacion.trim(),
      );
      await _cargarDatos();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Visita registrada.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _abrirHistorialFinanciero({int? prestamoId}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HistorialFinancieroPage(prestamoId: prestamoId),
      ),
    );
    await _cargarDatos();
  }

  @override
  Widget build(BuildContext context) {
    final prestamos = _prestamosFiltrados;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cobros'),
        actions: [
          IconButton(
            tooltip: 'Historial financiero',
            onPressed: () => _abrirHistorialFinanciero(),
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargarDatos,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirRegistro(),
        icon: const Icon(Icons.payments),
        label: const Text('Cobrar'),
      ),
      body: RefreshIndicator(
        onRefresh: _cargarDatos,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            _ResumenCobros(
              cobros: _cobros,
              prestamosActivos: _prestamosActivos,
            ),
            const SizedBox(height: 16),
            SegmentedButton<_VistaCobros>(
              selected: {_vista},
              onSelectionChanged: (value) => setState(() {
                _vista = value.first;
              }),
              segments: const [
                ButtonSegment(
                  value: _VistaCobros.pendientes,
                  label: Text('Pendientes'),
                  icon: Icon(Icons.route),
                ),
                ButtonSegment(
                  value: _VistaCobros.historial,
                  label: Text('Historial'),
                  icon: Icon(Icons.history),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _buscarController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Buscar cliente, cédula o préstamo',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _buscarController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar búsqueda',
                        onPressed: () {
                          _buscarController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            if (_cargando)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_vista == _VistaCobros.pendientes)
              _PendientesList(
                prestamos: prestamos,
                clientePorId: _clientePorId,
                onCobrar: (prestamo) {
                  _abrirRegistro(prestamo: prestamo);
                },
                onVisita: (prestamo) {
                  _registrarVisita(prestamo);
                },
              )
            else
              _HistorialList(
                cobros: _cobros,
                prestamoPorId: _prestamoPorId,
                clientePorId: _clientePorId,
                onVerHistorial: (cobro) =>
                    _abrirHistorialFinanciero(prestamoId: cobro.prestamoId),
              ),
          ],
        ),
      ),
    );
  }
}

class _ResumenCobros extends StatelessWidget {
  const _ResumenCobros({required this.cobros, required this.prestamosActivos});

  final List<CobroModel> cobros;
  final List<PrestamoModel> prestamosActivos;

  @override
  Widget build(BuildContext context) {
    final hoy = DateTime.now();
    final cobrosHoy = cobros.where((cobro) => _sameDay(cobro.fechaPago, hoy));
    final totalHoy = cobrosHoy.fold<double>(
      0,
      (total, cobro) => total + cobro.monto,
    );
    final visitasHoy = cobrosHoy.where((cobro) => cobro.monto == 0).length;
    final saldoPendiente = prestamosActivos.fold<double>(
      0,
      (total, prestamo) => total + prestamo.saldo,
    );

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ResumenItem(
                icono: Icons.payments,
                valor: _money(totalHoy),
                titulo: 'Cobrado hoy',
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ResumenItem(
                icono: Icons.route,
                valor: '${prestamosActivos.length}',
                titulo: 'Pendientes',
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
                icono: Icons.account_balance_wallet,
                valor: _money(saldoPendiente),
                titulo: 'Por cobrar',
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ResumenItem(
                icono: Icons.directions_walk,
                valor: '$visitasHoy',
                titulo: 'Visitas hoy',
                color: Colors.purple,
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

class _PendientesList extends StatelessWidget {
  const _PendientesList({
    required this.prestamos,
    required this.clientePorId,
    required this.onCobrar,
    required this.onVisita,
  });

  final List<PrestamoModel> prestamos;
  final ClienteModel? Function(int id) clientePorId;
  final ValueChanged<PrestamoModel> onCobrar;
  final ValueChanged<PrestamoModel> onVisita;

  @override
  Widget build(BuildContext context) {
    if (prestamos.isEmpty) {
      return const _EmptyState(
        icono: Icons.done_all,
        titulo: 'No hay cobros pendientes',
        mensaje: 'Cuando tengas préstamos activos aparecerán aquí.',
      );
    }

    return Column(
      children: [
        for (final prestamo in prestamos)
          _PendienteCard(
            prestamo: prestamo,
            cliente: clientePorId(prestamo.clienteId),
            onCobrar: () => onCobrar(prestamo),
            onVisita: () => onVisita(prestamo),
          ),
      ],
    );
  }
}

class _PendienteCard extends StatelessWidget {
  const _PendienteCard({
    required this.prestamo,
    required this.cliente,
    required this.onCobrar,
    required this.onVisita,
  });

  final PrestamoModel prestamo;
  final ClienteModel? cliente;
  final VoidCallback onCobrar;
  final VoidCallback onVisita;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.person_pin_circle)),
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
                        [
                          cliente?.telefono,
                          cliente?.barrio,
                          'Préstamo #${prestamo.id ?? '-'}',
                        ].whereType<String>().join(' - '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _DatoCobro(
                    label: 'Cuota sugerida',
                    value: _money(prestamo.cuotaDiaria),
                  ),
                ),
                Expanded(
                  child: _DatoCobro(
                    label: 'Saldo',
                    value: _money(prestamo.saldo),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onCobrar,
                    icon: const Icon(Icons.payments),
                    label: const Text('Cobrar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onVisita,
                    icon: const Icon(Icons.directions_walk),
                    label: const Text('Visita'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HistorialList extends StatelessWidget {
  const _HistorialList({
    required this.cobros,
    required this.prestamoPorId,
    required this.clientePorId,
    required this.onVerHistorial,
  });

  final List<CobroModel> cobros;
  final PrestamoModel? Function(int id) prestamoPorId;
  final ClienteModel? Function(int id) clientePorId;
  final ValueChanged<CobroModel> onVerHistorial;

  @override
  Widget build(BuildContext context) {
    if (cobros.isEmpty) {
      return const _EmptyState(
        icono: Icons.history,
        titulo: 'Aún no hay historial',
        mensaje: 'Los pagos y visitas aparecerán después de registrarlos.',
      );
    }

    return Column(
      children: [
        for (final cobro in cobros)
          _CobroHistorialCard(
            cobro: cobro,
            prestamo: prestamoPorId(cobro.prestamoId),
            cliente: _clienteFromCobro(cobro),
            onTap: () => onVerHistorial(cobro),
          ),
      ],
    );
  }

  ClienteModel? _clienteFromCobro(CobroModel cobro) {
    final prestamo = prestamoPorId(cobro.prestamoId);
    if (prestamo == null) return null;
    return clientePorId(prestamo.clienteId);
  }
}

class _CobroHistorialCard extends StatelessWidget {
  const _CobroHistorialCard({
    required this.cobro,
    required this.prestamo,
    required this.cliente,
    required this.onTap,
  });

  final CobroModel cobro;
  final PrestamoModel? prestamo;
  final ClienteModel? cliente;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final esVisita = cobro.monto == 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          child: Icon(esVisita ? Icons.directions_walk : Icons.payments),
        ),
        title: Text(
          esVisita ? 'Visita sin pago' : _money(cobro.monto),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            cliente?.nombre ?? 'Préstamo #${cobro.prestamoId}',
            _dateTime(cobro.fechaPago),
            cobro.observacion,
          ].whereType<String>().join(' - '),
        ),
        trailing: prestamo == null
            ? null
            : Text('Saldo ${_money(prestamo!.saldo)}'),
      ),
    );
  }
}

class _DatoCobro extends StatelessWidget {
  const _DatoCobro({required this.label, required this.value});

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
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ],
    );
  }
}

class _CobroFormSheet extends StatefulWidget {
  const _CobroFormSheet({
    required this.prestamos,
    required this.clientes,
    required this.cobradorId,
    this.prestamoInicial,
  });

  final List<PrestamoModel> prestamos;
  final List<ClienteModel> clientes;
  final int cobradorId;
  final PrestamoModel? prestamoInicial;

  @override
  State<_CobroFormSheet> createState() => _CobroFormSheetState();
}

class _CobroFormSheetState extends State<_CobroFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _montoController = TextEditingController();
  final _observacionController = TextEditingController();

  int? _prestamoId;

  @override
  void initState() {
    super.initState();
    final inicial = widget.prestamoInicial;
    _prestamoId = inicial?.id;
    if (inicial != null) {
      _montoController.text = CurrencyFormatter.numero(
        inicial.cuotaDiaria.clamp(0, inicial.saldo),
      );
    }
  }

  @override
  void dispose() {
    _montoController.dispose();
    _observacionController.dispose();
    super.dispose();
  }

  PrestamoModel? get _prestamoSeleccionado {
    for (final prestamo in widget.prestamos) {
      if (prestamo.id == _prestamoId) return prestamo;
    }
    return null;
  }

  ClienteModel? _clientePorId(int id) {
    for (final cliente in widget.clientes) {
      if (cliente.id == id) return cliente;
    }
    return null;
  }

  void _usarCuota() {
    final prestamo = _prestamoSeleccionado;
    if (prestamo == null) return;
    _montoController.text = CurrencyFormatter.numero(
      prestamo.cuotaDiaria.clamp(0, prestamo.saldo),
    );
    setState(() {});
  }

  void _pagarSaldo() {
    final prestamo = _prestamoSeleccionado;
    if (prestamo == null) return;
    _montoController.text = CurrencyFormatter.numero(prestamo.saldo);
    setState(() {});
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;

    Navigator.pop(
      context,
      CobroModel(
        prestamoId: _prestamoId!,
        cobradorId: widget.cobradorId,
        monto: CurrencyFormatter.parse(_montoController.text),
        observacion: _observacionController.text.trim().isEmpty
            ? null
            : _observacionController.text.trim(),
        fechaPago: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final prestamo = _prestamoSeleccionado;
    final cliente = prestamo == null ? null : _clientePorId(prestamo.clienteId);

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
                'Registrar cobro',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              const Text('Elige el préstamo y registra el pago recibido.'),
              const SizedBox(height: 18),
              DropdownButtonFormField<int>(
                initialValue: _prestamoId,
                items: [
                  for (final prestamo in widget.prestamos)
                    if (prestamo.id != null)
                      DropdownMenuItem<int>(
                        value: prestamo.id!,
                        child: Text(
                          '${_clientePorId(prestamo.clienteId)?.nombre ?? 'Cliente'} '
                          '- saldo ${_money(prestamo.saldo)}',
                        ),
                      ),
                ],
                onChanged: (value) {
                  setState(() {
                    _prestamoId = value;
                    _usarCuota();
                  });
                },
                decoration: const InputDecoration(
                  labelText: 'Préstamo',
                  prefixIcon: Icon(Icons.receipt_long),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null) return 'Selecciona un préstamo';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              if (prestamo != null)
                _PrestamoCobroResumen(prestamo: prestamo, cliente: cliente),
              const SizedBox(height: 12),
              TextFormField(
                controller: _montoController,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Monto pagado',
                  prefixIcon: Icon(Icons.payments),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final monto = CurrencyFormatter.parse(value ?? '');
                  final saldo = prestamo?.saldo ?? 0;

                  if (monto <= 0) {
                    return 'Ingresa un monto mayor a cero';
                  }
                  if (monto > saldo) {
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
                      onPressed: _usarCuota,
                      icon: const Icon(Icons.today),
                      label: const Text('Cuota'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pagarSaldo,
                      icon: const Icon(Icons.done_all),
                      label: const Text('Saldo'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _observacionController,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Observación',
                  hintText: 'Ej: pago parcial, cliente paga mañana',
                  prefixIcon: Icon(Icons.notes),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _guardar,
                  icon: const Icon(Icons.save),
                  label: const Text('Guardar cobro'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrestamoCobroResumen extends StatelessWidget {
  const _PrestamoCobroResumen({required this.prestamo, required this.cliente});

  final PrestamoModel prestamo;
  final ClienteModel? cliente;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cliente?.nombre ?? 'Cliente #${prestamo.clienteId}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _InfoResumen(
              label: 'Cuota sugerida',
              value: _money(prestamo.cuotaDiaria),
            ),
            _InfoResumen(label: 'Saldo actual', value: _money(prestamo.saldo)),
            _InfoResumen(label: 'Estado', value: prestamo.estado),
          ],
        ),
      ),
    );
  }
}

class _InfoResumen extends StatelessWidget {
  const _InfoResumen({required this.label, required this.value});

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

class _VisitaDialog extends StatefulWidget {
  const _VisitaDialog();

  @override
  State<_VisitaDialog> createState() => _VisitaDialogState();
}

class _VisitaDialogState extends State<_VisitaDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar visita'),
      content: TextField(
        controller: _controller,
        minLines: 2,
        maxLines: 3,
        decoration: const InputDecoration(
          labelText: 'Observación',
          hintText: 'Ej: no estaba, pidió pasar mañana',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Guardar visita'),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icono,
    required this.titulo,
    required this.mensaje,
  });

  final IconData icono;
  final String titulo;
  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(icono, size: 64, color: Colors.grey.shade500),
          const SizedBox(height: 12),
          Text(
            titulo,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(mensaje, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

String _money(double value) => CurrencyFormatter.pesos(value);

String _dateTime(DateTime value) {
  return '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.year} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

bool _sameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
