import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../prestamos/models/prestamo_model.dart';
import '../data/historial_financiero_repository.dart';

class HistorialFinancieroPage extends StatefulWidget {
  const HistorialFinancieroPage({super.key, this.clienteId, this.prestamoId});

  final int? clienteId;
  final int? prestamoId;

  @override
  State<HistorialFinancieroPage> createState() =>
      _HistorialFinancieroPageState();
}

class _HistorialFinancieroPageState extends State<HistorialFinancieroPage> {
  final _repository = const HistorialFinancieroRepository();
  final _buscarController = TextEditingController();

  bool _cargando = true;
  bool _cargandoDetalle = false;
  List<ClienteHistorialResumen> _clientes = [];
  HistorialFinancieroDetalle? _detalle;

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _buscarController.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    if (widget.prestamoId != null) {
      await _cargarPorPrestamo(widget.prestamoId!);
      return;
    }
    if (widget.clienteId != null) {
      await _cargarDetalle(widget.clienteId!);
      return;
    }
    await _buscar();
  }

  Future<void> _buscar() async {
    setState(() => _cargando = true);
    final clientes = await _repository.buscarClientes(_buscarController.text);
    if (!mounted) return;
    setState(() {
      _clientes = clientes;
      _detalle = null;
      _cargando = false;
    });
  }

  Future<void> _cargarPorPrestamo(int prestamoId) async {
    setState(() {
      _cargando = false;
      _cargandoDetalle = true;
    });
    final detalle = await _repository.detallePorPrestamo(prestamoId);
    if (!mounted) return;
    setState(() {
      _detalle = detalle;
      _cargandoDetalle = false;
    });
  }

  Future<void> _cargarDetalle(int clienteId) async {
    setState(() {
      _cargando = false;
      _cargandoDetalle = true;
    });
    final detalle = await _repository.detallePorCliente(clienteId);
    if (!mounted) return;
    setState(() {
      _detalle = detalle;
      _cargandoDetalle = false;
    });
  }

  void _volverBusqueda() {
    setState(() {
      _detalle = null;
      _cargandoDetalle = false;
    });
    _buscar();
  }

  @override
  Widget build(BuildContext context) {
    final detalle = _detalle;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial financiero'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: detalle == null
                ? _buscar
                : () => _cargarDetalle(detalle.resumen.cliente.id!),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: detalle == null
            ? _buscar
            : () => _cargarDetalle(detalle.resumen.cliente.id!),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            if (detalle == null) ...[
              _BuscadorHistorial(
                controller: _buscarController,
                onChanged: (_) => _buscar(),
                onClear: () {
                  _buscarController.clear();
                  _buscar();
                },
              ),
              const SizedBox(height: 16),
              if (_cargando)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_clientes.isEmpty)
                const _EmptyHistorial()
              else
                for (final cliente in _clientes)
                  _ClienteResultadoCard(
                    resumen: cliente,
                    onTap: () => _cargarDetalle(cliente.cliente.id!),
                  ),
            ] else ...[
              if (_cargandoDetalle)
                const LinearProgressIndicator()
              else ...[
                _DetalleHeader(detalle: detalle, onBack: _volverBusqueda),
                const SizedBox(height: 14),
                _PrestamosResumen(prestamos: detalle.prestamos),
                const SizedBox(height: 14),
                _MovimientosTimeline(movimientos: detalle.movimientos),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _BuscadorHistorial extends StatelessWidget {
  const _BuscadorHistorial({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: 'Buscar cliente, cedula, telefono o prestamo',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpiar busqueda',
                onPressed: onClear,
                icon: const Icon(Icons.close),
              ),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _ClienteResultadoCard extends StatelessWidget {
  const _ClienteResultadoCard({required this.resumen, required this.onTap});

  final ClienteHistorialResumen resumen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: resumen.saldoPendiente > 0
              ? Colors.orange.withValues(alpha: 0.12)
              : Colors.green.withValues(alpha: 0.12),
          child: Icon(
            resumen.saldoPendiente > 0 ? Icons.pending_actions : Icons.done,
            color: resumen.saldoPendiente > 0 ? Colors.orange : Colors.green,
          ),
        ),
        title: Text(
          resumen.cliente.nombre,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          'Cobrador: ${resumen.cobradorNombre} - '
          'Prestamos: ${resumen.prestamosTotal}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              CurrencyFormatter.pesos(resumen.saldoPendiente),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              resumen.saldoPendiente > 0 ? 'Debe' : 'Al dia',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _DetalleHeader extends StatelessWidget {
  const _DetalleHeader({required this.detalle, required this.onBack});

  final HistorialFinancieroDetalle detalle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final resumen = detalle.resumen;
    final debe = resumen.saldoPendiente > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: (debe ? Colors.orange : Colors.green)
                      .withValues(alpha: 0.12),
                  child: Icon(
                    debe ? Icons.account_balance_wallet : Icons.check_circle,
                    color: debe ? Colors.orange : Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        resumen.cliente.nombre,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('Cobrador: ${resumen.cobradorNombre}'),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Cambiar cliente',
                  onPressed: onBack,
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _ResumenDato(
                  label: 'Saldo pendiente',
                  value: CurrencyFormatter.pesos(resumen.saldoPendiente),
                  color: debe ? Colors.orange : Colors.green,
                ),
                _ResumenDato(
                  label: 'Total pagado',
                  value: CurrencyFormatter.pesos(resumen.totalPagado),
                  color: Colors.green,
                ),
                _ResumenDato(
                  label: 'Prestado',
                  value: CurrencyFormatter.pesos(detalle.totalPrestado),
                  color: Colors.blue,
                ),
                _ResumenDato(
                  label: 'Activos',
                  value: '${resumen.prestamosActivos}',
                  color: Colors.teal,
                ),
                _ResumenDato(
                  label: 'Atrasados',
                  value: '${resumen.prestamosAtrasados}',
                  color: Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumenDato extends StatelessWidget {
  const _ResumenDato({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          border: Border.all(color: color.withValues(alpha: 0.24)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrestamosResumen extends StatelessWidget {
  const _PrestamosResumen({required this.prestamos});

  final List<PrestamoModel> prestamos;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Prestamos', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (prestamos.isEmpty)
          const Card(child: ListTile(title: Text('Sin prestamos registrados')))
        else
          for (final prestamo in prestamos)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Prestamo #${prestamo.id ?? '-'}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        _EstadoPrestamo(estado: prestamo.estado),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _MiniDato(
                          'Monto',
                          CurrencyFormatter.pesos(prestamo.monto),
                        ),
                        _MiniDato(
                          'Saldo',
                          CurrencyFormatter.pesos(prestamo.saldo),
                        ),
                        _MiniDato(
                          prestamo.cuotaLabel,
                          CurrencyFormatter.pesos(prestamo.cuotaDiaria),
                        ),
                        _MiniDato('Inicio', _date(prestamo.fechaInicio)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

class _MovimientosTimeline extends StatelessWidget {
  const _MovimientosTimeline({required this.movimientos});

  final List<HistorialMovimiento> movimientos;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Movimientos', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (movimientos.isEmpty)
          const Card(child: ListTile(title: Text('Sin movimientos')))
        else
          for (final movimiento in movimientos)
            _MovimientoCard(movimiento: movimiento),
      ],
    );
  }
}

class _MovimientoCard extends StatelessWidget {
  const _MovimientoCard({required this.movimiento});

  final HistorialMovimiento movimiento;

  @override
  Widget build(BuildContext context) {
    final color = _movimientoColor(movimiento.tipo);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(_movimientoIcon(movimiento.tipo), color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          movimiento.titulo,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(_dateTime(movimiento.fecha)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(movimiento.descripcion),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (movimiento.prestamoId != null)
                        _InfoChip('Prestamo #${movimiento.prestamoId}'),
                      if (movimiento.monto > 0)
                        _InfoChip(CurrencyFormatter.pesos(movimiento.monto)),
                      if (movimiento.saldoAnterior != null)
                        _InfoChip(
                          'Antes ${CurrencyFormatter.pesos(movimiento.saldoAnterior!)}',
                        ),
                      if (movimiento.saldoActual != null)
                        _InfoChip(
                          'Saldo ${CurrencyFormatter.pesos(movimiento.saldoActual!)}',
                        ),
                      if (movimiento.cobradorNombre?.isNotEmpty == true)
                        _InfoChip(movimiento.cobradorNombre!),
                      if (movimiento.rutaNombre?.isNotEmpty == true)
                        _InfoChip(movimiento.rutaNombre!),
                    ],
                  ),
                  if (movimiento.observacion?.isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Text('Obs: ${movimiento.observacion}'),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniDato extends StatelessWidget {
  const _MiniDato(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 125,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(text),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _EstadoPrestamo extends StatelessWidget {
  const _EstadoPrestamo({required this.estado});

  final String estado;

  @override
  Widget build(BuildContext context) {
    final color = switch (estado) {
      AppEstados.pagado => Colors.green,
      AppEstados.atrasado => Colors.red,
      AppEstados.cancelado => Colors.grey,
      _ => Colors.orange,
    };
    return Chip(
      label: Text(estado),
      backgroundColor: color.withValues(alpha: 0.12),
    );
  }
}

class _EmptyHistorial extends StatelessWidget {
  const _EmptyHistorial();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(Icons.history, size: 56, color: Colors.grey),
          SizedBox(height: 8),
          Text('Sin resultados'),
          Text('Busca por cliente, cedula, telefono o numero de prestamo.'),
        ],
      ),
    );
  }
}

Color _movimientoColor(String tipo) {
  return switch (tipo) {
    'pago' => Colors.green,
    'prestamo' => Colors.orange,
    'visita' => Colors.blueGrey,
    'ruta' => Colors.red,
    _ => Colors.grey,
  };
}

IconData _movimientoIcon(String tipo) {
  return switch (tipo) {
    'pago' => Icons.payments,
    'prestamo' => Icons.receipt_long,
    'visita' => Icons.directions_walk,
    'ruta' => Icons.route,
    _ => Icons.swap_vert,
  };
}

String _date(DateTime value) {
  return '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.year}';
}

String _dateTime(DateTime value) {
  return '${_date(value)} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
