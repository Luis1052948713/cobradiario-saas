import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../auditoria/pages/auditoria_page.dart';
import '../../caja/pages/caja_page.dart';
import '../../clientes/pages/clientes_page.dart';
import '../../cobros/pages/cobros_page.dart';
import '../../prestamos/pages/prestamos_page.dart';
import '../../rutas/pages/rutas_page.dart';
import '../data/notificacion_repository.dart';
import '../models/notificacion_model.dart';

class NotificacionesPage extends StatefulWidget {
  const NotificacionesPage({super.key});

  @override
  State<NotificacionesPage> createState() => _NotificacionesPageState();
}

class _NotificacionesPageState extends State<NotificacionesPage> {
  final _repository = const NotificacionRepository();

  late Future<List<NotificacionModel>> _future;
  String _tipoFiltro = 'todos';
  String _estadoFiltro = 'todos';

  @override
  void initState() {
    super.initState();
    _future = _repository.listar();
  }

  Future<void> _recargar() async {
    setState(() => _future = _repository.listar());
    await _future;
  }

  Future<void> _toggle(NotificacionModel notificacion) async {
    if (notificacion.id == null) return;
    if (notificacion.estaLeida) {
      await _repository.marcarPendiente(notificacion.id!);
    } else {
      await _repository.marcarLeida(notificacion.id!);
    }
    await _recargar();
  }

  Future<void> _abrir(NotificacionModel notificacion) async {
    if (notificacion.id != null && !notificacion.estaLeida) {
      await _repository.marcarLeida(notificacion.id!);
    }

    if (!mounted) return;
    final page = _destinoNotificacion(notificacion);
    if (page == null) {
      await _mostrarDetalle(notificacion);
      await _recargar();
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
    await _recargar();
  }

  Future<void> _mostrarDetalle(NotificacionModel notificacion) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(notificacion.titulo),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notificacion.mensaje),
            const SizedBox(height: 12),
            Text('Tipo: ${_tipoLabel(notificacion.tipo)}'),
            Text('Fecha: ${_dateTime(notificacion.fechaHora)}'),
            if (notificacion.modulo?.isNotEmpty == true)
              Text('Modulo: ${notificacion.modulo}'),
            if (notificacion.referenciaId != null)
              Text('Referencia: ${notificacion.referenciaId}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget? _destinoNotificacion(NotificacionModel notificacion) {
    final modulo = (notificacion.modulo ?? '').toLowerCase();
    final referenciaId = notificacion.referenciaId;

    if (modulo.contains('cliente')) {
      return ClientesPage(clienteInicialId: referenciaId);
    }
    if (modulo.contains('prestamo')) {
      return PrestamosPage(prestamoInicialId: referenciaId);
    }
    if (modulo.contains('cobro')) {
      return CobrosPage(cobroInicialId: referenciaId, mostrarHistorial: true);
    }
    if (modulo.contains('ruta')) {
      return RutasPage(rutaInicialId: referenciaId);
    }
    if (modulo.contains('auditoria')) return const AuditoriaPage();
    if (modulo.contains('caja') ||
        modulo.contains('solicitud') ||
        modulo.contains('cierre') ||
        modulo.contains('financ')) {
      return const CajaPage();
    }

    final texto = '${notificacion.titulo} ${notificacion.mensaje}'
        .toLowerCase();
    if (texto.contains('cliente atrasado')) {
      return ClientesPage(clienteInicialId: referenciaId);
    }
    if (texto.contains('cobro registrado')) {
      return CobrosPage(cobroInicialId: referenciaId, mostrarHistorial: true);
    }
    if (texto.contains('solicitud de saldo') ||
        texto.contains('cierre de caja') ||
        texto.contains('diferencia en caja')) {
      return const CajaPage();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _recargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<NotificacionModel>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final todas = snapshot.data ?? [];
          final notificaciones = todas.where((item) {
            final coincideTipo =
                _tipoFiltro == 'todos' || item.tipo == _tipoFiltro;
            final coincideEstado =
                _estadoFiltro == 'todos' || item.estado == _estadoFiltro;
            return coincideTipo && coincideEstado;
          }).toList();
          return RefreshIndicator(
            onRefresh: _recargar,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _ResumenNotificaciones(notificaciones: todas),
                const SizedBox(height: 12),
                _FiltrosNotificaciones(
                  tipo: _tipoFiltro,
                  estado: _estadoFiltro,
                  onTipoChanged: (value) {
                    setState(() => _tipoFiltro = value);
                  },
                  onEstadoChanged: (value) {
                    setState(() => _estadoFiltro = value);
                  },
                ),
                const SizedBox(height: 12),
                if (notificaciones.isEmpty)
                  const _EstadoVacio()
                else
                  for (final notificacion in notificaciones)
                    _NotificacionCard(
                      notificacion: notificacion,
                      onToggle: () => _toggle(notificacion),
                      onOpen: () => _abrir(notificacion),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FiltrosNotificaciones extends StatelessWidget {
  const _FiltrosNotificaciones({
    required this.tipo,
    required this.estado,
    required this.onTipoChanged,
    required this.onEstadoChanged,
  });

  final String tipo;
  final String estado;
  final ValueChanged<String> onTipoChanged;
  final ValueChanged<String> onEstadoChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _FiltroChip(
              label: 'Todas',
              selected: tipo == 'todos',
              onSelected: () => onTipoChanged('todos'),
            ),
            _FiltroChip(
              label: 'Criticas',
              selected: tipo == NotificacionTipos.critica,
              onSelected: () => onTipoChanged(NotificacionTipos.critica),
            ),
            _FiltroChip(
              label: 'Advertencias',
              selected: tipo == NotificacionTipos.advertencia,
              onSelected: () => onTipoChanged(NotificacionTipos.advertencia),
            ),
            _FiltroChip(
              label: 'Exitos',
              selected: tipo == NotificacionTipos.exito,
              onSelected: () => onTipoChanged(NotificacionTipos.exito),
            ),
            _FiltroChip(
              label: 'Informativas',
              selected: tipo == NotificacionTipos.informativa,
              onSelected: () => onTipoChanged(NotificacionTipos.informativa),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'todos', label: Text('Todos')),
            ButtonSegment(
              value: NotificacionEstados.pendiente,
              label: Text('Pendientes'),
            ),
            ButtonSegment(
              value: NotificacionEstados.leida,
              label: Text('Leidas'),
            ),
          ],
          selected: {estado},
          onSelectionChanged: (value) => onEstadoChanged(value.first),
        ),
      ],
    );
  }
}

class _FiltroChip extends StatelessWidget {
  const _FiltroChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}

class _ResumenNotificaciones extends StatelessWidget {
  const _ResumenNotificaciones({required this.notificaciones});

  final List<NotificacionModel> notificaciones;

  @override
  Widget build(BuildContext context) {
    final pendientes = notificaciones.where((item) => !item.estaLeida).length;
    final criticas = notificaciones.where((item) => item.esCritica).length;
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.notifications)),
        title: const Text('Centro de notificaciones'),
        subtitle: Text('$pendientes pendientes - $criticas criticas'),
      ),
    );
  }
}

class _NotificacionCard extends StatelessWidget {
  const _NotificacionCard({
    required this.notificacion,
    required this.onToggle,
    required this.onOpen,
  });

  final NotificacionModel notificacion;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final color = _color(notificacion.tipo);

    return Card(
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(8),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 5, color: color),
              Expanded(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.12),
                    child: Icon(_icono(notificacion.tipo), color: color),
                  ),
                  title: Text(
                    notificacion.titulo,
                    style: TextStyle(
                      fontWeight: notificacion.estaLeida
                          ? FontWeight.w500
                          : FontWeight.w800,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(notificacion.mensaje),
                      const SizedBox(height: 4),
                      Text(
                        '${_tipoLabel(notificacion.tipo)} - ${_dateTime(notificacion.fechaHora)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (notificacion.usuarioNombre != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Usuario: ${notificacion.usuarioNombre}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                  trailing: Wrap(
                    spacing: 2,
                    children: [
                      IconButton(
                        tooltip: 'Abrir modulo',
                        onPressed: onOpen,
                        icon: const Icon(Icons.open_in_new),
                      ),
                      IconButton(
                        tooltip: notificacion.estaLeida
                            ? 'Marcar pendiente'
                            : 'Marcar leida',
                        onPressed: onToggle,
                        icon: Icon(
                          notificacion.estaLeida
                              ? Icons.mark_email_unread
                              : Icons.done_all,
                        ),
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

  Color _color(String tipo) {
    switch (tipo) {
      case NotificacionTipos.critica:
        return Colors.red;
      case NotificacionTipos.advertencia:
        return Colors.orange;
      case NotificacionTipos.exito:
        return Colors.green;
      default:
        return Colors.blue;
    }
  }

  IconData _icono(String tipo) {
    switch (tipo) {
      case NotificacionTipos.critica:
        return Icons.priority_high;
      case NotificacionTipos.advertencia:
        return Icons.warning;
      case NotificacionTipos.exito:
        return Icons.check_circle;
      default:
        return Icons.info;
    }
  }
}

class _EstadoVacio extends StatelessWidget {
  const _EstadoVacio();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          Icon(Icons.notifications_none, size: 56, color: Colors.grey),
          SizedBox(height: 8),
          Text('Sin notificaciones'),
        ],
      ),
    );
  }
}

String _tipoLabel(String tipo) {
  switch (tipo) {
    case NotificacionTipos.critica:
      return 'Critica';
    case NotificacionTipos.advertencia:
      return 'Advertencia';
    case NotificacionTipos.exito:
      return 'Exito';
    default:
      return 'Informativa';
  }
}

String _dateTime(DateTime value) {
  return '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.year} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}
