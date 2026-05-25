import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../configuracion/data/configuracion_repository.dart';
import '../data/suscripcion_repository.dart';

class SuscripcionPage extends StatefulWidget {
  const SuscripcionPage({super.key});

  @override
  State<SuscripcionPage> createState() => _SuscripcionPageState();
}

class _SuscripcionPageState extends State<SuscripcionPage> {
  final _repository = const SuscripcionRepository();
  final _configuracionRepository = const ConfiguracionRepository();
  final _permissionService = const PermissionService();

  bool _cargando = true;
  SuscripcionResumen? _resumen;
  List<Map<String, Object?>> _eventos = [];
  String _pasarelaNombre = 'Pago externo';
  String _pasarelaUrl = '';
  String _nequiTitular = '';
  String _nequiTelefono = '';

  bool get _esSuperadmin => _permissionService.esSuperadmin;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final resumen = await _repository.obtenerResumen();
    final eventos = await _repository.eventos();
    final pasarelaNombre = await _configuracionRepository.obtenerValor(
      AppConfigKeys.pasarelaPagoNombre,
    );
    final pasarelaUrl = await _configuracionRepository.obtenerValor(
      AppConfigKeys.pasarelaPagoUrl,
    );
    final nequiTitular = await _configuracionRepository.obtenerValor(
      AppConfigKeys.nequiTitular,
    );
    final nequiTelefono = await _configuracionRepository.obtenerValor(
      AppConfigKeys.nequiTelefono,
    );
    if (!mounted) return;
    setState(() {
      _resumen = resumen;
      _eventos = eventos;
      _pasarelaNombre = pasarelaNombre?.trim().isNotEmpty == true
          ? pasarelaNombre!.trim()
          : 'Pago externo';
      _pasarelaUrl = pasarelaUrl?.trim() ?? '';
      _nequiTitular = nequiTitular?.trim() ?? '';
      _nequiTelefono = nequiTelefono?.trim() ?? '';
      _cargando = false;
    });
  }

  Future<void> _registrarPago() async {
    final data = await showDialog<_PagoSuscripcionData>(
      context: context,
      builder: (context) => const _PagoSuscripcionDialog(),
    );
    if (data == null) return;

    try {
      await _repository.registrarPagoManual(
        plan: data.plan,
        meses: data.meses,
        monto: data.monto,
        referenciaPago: data.referencia,
        observacion: data.observacion,
      );
      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Suscripcion activada correctamente.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _cancelar() async {
    final observacion = await showDialog<String>(
      context: context,
      builder: (context) => const _CancelarSuscripcionDialog(),
    );
    if (observacion == null || observacion.trim().isEmpty) return;
    await _repository.cancelar(observacion.trim());
    await _cargar();
  }

  Future<void> _solicitarPago() async {
    final data = await showDialog<_PagoSuscripcionData>(
      context: context,
      builder: (context) => const _PagoSuscripcionDialog(
        titulo: 'Solicitar renovacion',
        accion: 'Continuar pago',
        pedirReferencia: false,
      ),
    );
    if (data == null) return;

    try {
      final referencia = await _repository.registrarSolicitudPago(
        plan: data.plan,
        meses: data.meses,
        monto: data.monto,
        observacion: data.observacion,
      );
      final mensaje = _mensajePago(
        referencia: referencia,
        plan: data.plan,
        meses: data.meses,
        monto: data.monto,
      );
      await Clipboard.setData(ClipboardData(text: mensaje));
      await _cargar();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _PagoGeneradoDialog(
          referencia: referencia,
          mensaje: mensaje,
          pasarelaNombre: _pasarelaNombre,
          pasarelaUrl: _pasarelaUrl,
          nequiTitular: _nequiTitular,
          nequiTelefono: _nequiTelefono,
          monto: data.monto,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String _mensajePago({
    required String referencia,
    required String plan,
    required int meses,
    required double monto,
  }) {
    final buffer = StringBuffer()
      ..writeln('Solicitud de suscripcion Cobra Diario')
      ..writeln('Codigo de pago: $referencia')
      ..writeln('Plan: ${_planLabel(plan)}')
      ..writeln('Duracion: $meses mes(es)')
      ..writeln('Monto: ${CurrencyFormatter.pesos(monto)}');
    if (_nequiTelefono.isNotEmpty) {
      buffer.writeln('Pagar por Nequi al numero: $_nequiTelefono');
    }
    if (_nequiTitular.isNotEmpty) {
      buffer.writeln('Titular Nequi: $_nequiTitular');
    }
    if (_pasarelaUrl.isNotEmpty) {
      buffer.writeln('Link de pago: $_pasarelaUrl');
    }
    buffer
      ..writeln('Incluye o envia este codigo con el comprobante.')
      ..writeln('El superadmin activara la licencia al confirmar el pago.');
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final resumen = _resumen;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi suscripcion'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _esSuperadmin
          ? FloatingActionButton.extended(
              onPressed: _registrarPago,
              icon: const Icon(Icons.add_card),
              label: const Text('Registrar pago'),
            )
          : null,
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  if (resumen != null) _SuscripcionStatusCard(resumen: resumen),
                  const SizedBox(height: 14),
                  _PlanesInfoCard(
                    onRegistrar: _esSuperadmin ? _registrarPago : null,
                    onSolicitar: _esSuperadmin ? null : _solicitarPago,
                    pasarelaNombre: _pasarelaNombre,
                    pasarelaUrl: _pasarelaUrl,
                    nequiTitular: _nequiTitular,
                    nequiTelefono: _nequiTelefono,
                  ),
                  const SizedBox(height: 14),
                  if (_esSuperadmin && resumen?.activa == true)
                    OutlinedButton.icon(
                      onPressed: _cancelar,
                      icon: const Icon(Icons.cancel),
                      label: const Text('Cancelar suscripcion'),
                    ),
                  const SizedBox(height: 18),
                  Text(
                    'Historial de licencia',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (_eventos.isEmpty)
                    const Card(child: ListTile(title: Text('Sin eventos')))
                  else
                    for (final evento in _eventos)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.history),
                          title: Text('${evento['tipo']}'),
                          subtitle: Text('${evento['descripcion']}'),
                          trailing: Text(_dateTime('${evento['fecha_hora']}')),
                        ),
                      ),
                ],
              ),
            ),
    );
  }
}

class _SuscripcionStatusCard extends StatelessWidget {
  const _SuscripcionStatusCard({required this.resumen});

  final SuscripcionResumen resumen;

  @override
  Widget build(BuildContext context) {
    final color = resumen.activa
        ? resumen.enPrueba
              ? Colors.orange
              : Colors.green
        : Colors.red;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(
                    resumen.activa ? Icons.verified : Icons.block,
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        resumen.empresaNombre,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(_estadoLabel(resumen)),
                    ],
                  ),
                ),
                Chip(
                  label: Text(_planLabel(resumen.plan)),
                  backgroundColor: color.withValues(alpha: 0.12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _StatusMetric(
                  label: 'Estado',
                  value: resumen.estado,
                  color: color,
                ),
                _StatusMetric(
                  label: 'Dias restantes',
                  value: '${resumen.diasRestantes}',
                  color: color,
                ),
                _StatusMetric(
                  label: 'Vence',
                  value: _date(resumen.fechaFin),
                  color: Colors.blueGrey,
                ),
                _StatusMetric(
                  label: 'Ultimo pago',
                  value: CurrencyFormatter.pesos(resumen.monto),
                  color: Colors.green,
                ),
                _StatusMetric(
                  label: 'Proveedor',
                  value: resumen.proveedor,
                  color: Colors.indigo,
                ),
              ],
            ),
            if (resumen.referenciaPago?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text('Referencia: ${resumen.referenciaPago}'),
            ],
          ],
        ),
      ),
    );
  }

  String _estadoLabel(SuscripcionResumen resumen) {
    if (!resumen.activa) return 'Licencia vencida. Solicita renovacion.';
    if (resumen.enPrueba) {
      return 'Prueba activa por ${resumen.diasRestantes} dias.';
    }
    return 'Suscripcion activa hasta ${_date(resumen.fechaFin)}.';
  }
}

class _StatusMetric extends StatelessWidget {
  const _StatusMetric({
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
      width: 145,
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

class _PlanesInfoCard extends StatelessWidget {
  const _PlanesInfoCard({
    required this.onRegistrar,
    required this.onSolicitar,
    required this.pasarelaNombre,
    required this.pasarelaUrl,
    required this.nequiTitular,
    required this.nequiTelefono,
  });

  final VoidCallback? onRegistrar;
  final VoidCallback? onSolicitar;
  final String pasarelaNombre;
  final String pasarelaUrl;
  final String nequiTitular;
  final String nequiTelefono;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Planes sugeridos',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            const _PlanLine(
              plan: 'Basico',
              detalle: '1 cobrador, cartera pequeña',
              precio: '\$49.000 / mes',
            ),
            const _PlanLine(
              plan: 'Pro',
              detalle: 'Hasta 5 cobradores',
              precio: '\$99.000 / mes',
            ),
            const _PlanLine(
              plan: 'Empresa',
              detalle: 'Cobradores ilimitados',
              precio: '\$199.000 / mes',
            ),
            if (onRegistrar != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onRegistrar,
                  icon: const Icon(Icons.add_card),
                  label: const Text('Activar cliente despues del pago'),
                ),
              ),
            ],
            if (onSolicitar != null) ...[
              const SizedBox(height: 10),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.22),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListTile(
                  leading: const Icon(Icons.payment),
                  title: Text(
                    nequiTelefono.isEmpty
                        ? 'Nequi personal no configurado'
                        : 'Pagar por Nequi personal',
                  ),
                  subtitle: Text(
                    nequiTelefono.isEmpty
                        ? 'El superadmin debe configurar el numero Nequi.'
                        : [
                            'Numero: $nequiTelefono',
                            if (nequiTitular.isNotEmpty)
                              'Titular: $nequiTitular',
                          ].join(' - '),
                  ),
                  trailing: FilledButton.icon(
                    onPressed: nequiTelefono.isEmpty ? null : onSolicitar,
                    icon: const Icon(Icons.receipt_long),
                    label: const Text('Continuar'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlanLine extends StatelessWidget {
  const _PlanLine({
    required this.plan,
    required this.detalle,
    required this.precio,
  });

  final String plan;
  final String detalle;
  final String precio;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.workspace_premium),
      title: Text(plan),
      subtitle: Text(detalle),
      trailing: Text(
        precio,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _PagoSuscripcionDialog extends StatefulWidget {
  const _PagoSuscripcionDialog({
    this.titulo = 'Registrar pago',
    this.accion = 'Activar',
    this.pedirReferencia = true,
  });

  final String titulo;
  final String accion;
  final bool pedirReferencia;

  @override
  State<_PagoSuscripcionDialog> createState() => _PagoSuscripcionDialogState();
}

class _PagoSuscripcionDialogState extends State<_PagoSuscripcionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _montoController = TextEditingController();
  final _referenciaController = TextEditingController();
  final _observacionController = TextEditingController();
  String _plan = SuscripcionPlanes.pro;
  int _meses = 1;

  double get _montoCalculado => _calcularMonto(_plan, _meses);

  @override
  void initState() {
    super.initState();
    _actualizarMonto();
  }

  @override
  void dispose() {
    _montoController.dispose();
    _referenciaController.dispose();
    _observacionController.dispose();
    super.dispose();
  }

  void _actualizarMonto() {
    _montoController.text = CurrencyFormatter.numero(_montoCalculado);
  }

  void _cambiarPlan(String? value) {
    setState(() {
      _plan = value ?? _plan;
      _actualizarMonto();
    });
  }

  void _cambiarDuracion(int? value) {
    setState(() {
      _meses = value ?? _meses;
      _actualizarMonto();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PagoResumenBox(plan: _plan, meses: _meses),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _plan,
                decoration: const InputDecoration(
                  labelText: 'Plan',
                  prefixIcon: Icon(Icons.workspace_premium),
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final plan in SuscripcionPlanes.todos)
                    DropdownMenuItem(
                      value: plan,
                      child: Text(
                        '${_planLabel(plan)} - '
                        '${CurrencyFormatter.pesos(_planPrecioMensual(plan))}/mes',
                      ),
                    ),
                ],
                onChanged: _cambiarPlan,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _meses,
                decoration: const InputDecoration(
                  labelText: 'Duracion',
                  prefixIcon: Icon(Icons.calendar_month),
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 mes')),
                  DropdownMenuItem(value: 3, child: Text('3 meses')),
                  DropdownMenuItem(value: 6, child: Text('6 meses')),
                  DropdownMenuItem(value: 12, child: Text('12 meses')),
                ],
                onChanged: _cambiarDuracion,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _montoController,
                readOnly: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Total a pagar',
                  prefixIcon: Icon(Icons.payments),
                  suffixText: 'COP',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (CurrencyFormatter.parse(value ?? '') < 0) {
                    return 'Monto invalido';
                  }
                  return null;
                },
              ),
              if (widget.pedirReferencia) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _referenciaController,
                  decoration: const InputDecoration(
                    labelText: 'Codigo del comprobante',
                    hintText: 'Ej: Wompi, Nequi, banco o recibo',
                    prefixIcon: Icon(Icons.confirmation_number),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _observacionController,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Observacion',
                  prefixIcon: Icon(Icons.notes),
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
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              _PagoSuscripcionData(
                plan: _plan,
                meses: _meses,
                monto: _montoCalculado,
                referencia:
                    !widget.pedirReferencia ||
                        _referenciaController.text.trim().isEmpty
                    ? null
                    : _referenciaController.text.trim(),
                observacion: _observacionController.text.trim().isEmpty
                    ? null
                    : _observacionController.text.trim(),
              ),
            );
          },
          child: Text(widget.accion),
        ),
      ],
    );
  }
}

class _PagoResumenBox extends StatelessWidget {
  const _PagoResumenBox({required this.plan, required this.meses});

  final String plan;
  final int meses;

  @override
  Widget build(BuildContext context) {
    final mensual = _planPrecioMensual(plan);
    final total = _calcularMonto(plan, meses);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        border: Border.all(color: Colors.green.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_planLabel(plan)} - ${_duracionLabel(meses)}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(_planDetalle(plan)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _PagoResumenItem(
                    label: 'Mensual',
                    value: CurrencyFormatter.pesos(mensual),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PagoResumenItem(
                    label: 'Total',
                    value: CurrencyFormatter.pesos(total),
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

class _PagoResumenItem extends StatelessWidget {
  const _PagoResumenItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _PagoGeneradoDialog extends StatelessWidget {
  const _PagoGeneradoDialog({
    required this.referencia,
    required this.mensaje,
    required this.pasarelaNombre,
    required this.pasarelaUrl,
    required this.nequiTitular,
    required this.nequiTelefono,
    required this.monto,
  });

  final String referencia;
  final String mensaje;
  final String pasarelaNombre;
  final String pasarelaUrl;
  final String nequiTitular;
  final String nequiTelefono;
  final double monto;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pago listo'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Codigo de pago: $referencia'),
            const SizedBox(height: 8),
            Text('Monto exacto: ${CurrencyFormatter.pesos(monto)}'),
            const SizedBox(height: 8),
            Text('Paga por Nequi al numero: $nequiTelefono'),
            if (nequiTitular.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Titular: $nequiTitular'),
            ],
            const SizedBox(height: 8),
            Text('Metodo: $pasarelaNombre'),
            if (pasarelaUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(pasarelaUrl),
            ],
            const SizedBox(height: 12),
            const Text(
              'Este codigo identifica tu pago. Envia el comprobante con este codigo para que el superadmin confirme y active la licencia.',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: mensaje));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Informacion copiada')),
            );
          },
          child: const Text('Copiar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Entendido'),
        ),
      ],
    );
  }
}

class _CancelarSuscripcionDialog extends StatefulWidget {
  const _CancelarSuscripcionDialog();

  @override
  State<_CancelarSuscripcionDialog> createState() =>
      _CancelarSuscripcionDialogState();
}

class _CancelarSuscripcionDialogState
    extends State<_CancelarSuscripcionDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cancelar suscripcion'),
      content: TextField(
        controller: _controller,
        minLines: 2,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Motivo'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Volver'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Cancelar suscripcion'),
        ),
      ],
    );
  }
}

class _PagoSuscripcionData {
  const _PagoSuscripcionData({
    required this.plan,
    required this.meses,
    required this.monto,
    this.referencia,
    this.observacion,
  });

  final String plan;
  final int meses;
  final double monto;
  final String? referencia;
  final String? observacion;
}

String _planLabel(String plan) {
  return switch (plan) {
    SuscripcionPlanes.basico => 'Basico',
    SuscripcionPlanes.empresa => 'Empresa',
    _ => 'Pro',
  };
}

String _planDetalle(String plan) {
  return switch (plan) {
    SuscripcionPlanes.basico => '1 cobrador, cartera pequeña',
    SuscripcionPlanes.empresa => 'Cobradores ilimitados',
    _ => 'Hasta 5 cobradores',
  };
}

double _planPrecioMensual(String plan) {
  return switch (plan) {
    SuscripcionPlanes.basico => 49000,
    SuscripcionPlanes.empresa => 199000,
    _ => 99000,
  };
}

double _calcularMonto(String plan, int meses) {
  return _planPrecioMensual(plan) * meses;
}

String _duracionLabel(int meses) {
  return meses == 1 ? '1 mes' : '$meses meses';
}

String _date(DateTime value) {
  return '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.year}';
}

String _dateTime(String raw) {
  final value = DateTime.tryParse(raw);
  if (value == null) return raw;
  return '${_date(value)} ${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
