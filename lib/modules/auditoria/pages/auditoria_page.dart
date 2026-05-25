import 'package:flutter/material.dart';

import '../../../core/permissions/permission_service.dart';
import '../../usuarios/data/usuario_repository.dart';
import '../../usuarios/models/usuario_model.dart';
import '../data/auditoria_repository.dart';
import '../models/auditoria_model.dart';

class AuditoriaPage extends StatefulWidget {
  const AuditoriaPage({super.key});

  @override
  State<AuditoriaPage> createState() => _AuditoriaPageState();
}

class _AuditoriaPageState extends State<AuditoriaPage> {
  final _auditoriaRepository = const AuditoriaRepository();
  final _usuarioRepository = const UsuarioRepository();
  final _permissionService = const PermissionService();
  final _buscarController = TextEditingController();

  late Future<_AuditoriaData> _dataFuture;
  String _moduloSeleccionado = 'todos';
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    _dataFuture = _cargar();
    _buscarController.addListener(() {
      setState(() => _busqueda = _buscarController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _buscarController.dispose();
    super.dispose();
  }

  Future<_AuditoriaData> _cargar() async {
    final scopeUsuarioId = _permissionService.puedeVerAuditoriaGlobal()
        ? null
        : _permissionService.cobradorScope();
    final movimientos = await _auditoriaRepository.listar(
      usuarioId: scopeUsuarioId,
    );
    final usuarios = await _usuarioRepository.listar();

    return _AuditoriaData(
      movimientos: movimientos,
      usuariosPorId: {
        for (final usuario in usuarios)
          if (usuario.id != null) usuario.id!: usuario,
      },
    );
  }

  Future<void> _recargar() async {
    setState(() => _dataFuture = _cargar());
    await _dataFuture;
  }

  @override
  Widget build(BuildContext context) {
    final esGlobal = _permissionService.puedeVerAuditoriaGlobal();

    return Scaffold(
      appBar: AppBar(
        title: Text(esGlobal ? 'Auditoria' : 'Mis movimientos'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () {
              _recargar();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<_AuditoriaData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _EstadoVacio(
              icono: Icons.error_outline,
              titulo: 'No se pudo cargar la auditoria',
              mensaje: snapshot.error.toString(),
            );
          }

          final data = snapshot.data ?? const _AuditoriaData();
          final movimientos = _filtrar(data.movimientos);

          return RefreshIndicator(
            onRefresh: _recargar,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _ResumenAuditoria(
                  total: data.movimientos.length,
                  hoy: data.movimientosHoy(),
                  cobros: data.porModulo('cobros'),
                  prestamos: data.porModulo('prestamos'),
                  clientes: data.porModulo('clientes'),
                  usuarios: data.porModulo('usuarios'),
                ),
                const SizedBox(height: 14),
                _FiltroPanel(
                  buscarController: _buscarController,
                  seleccionado: _moduloSeleccionado,
                  onChanged: (value) {
                    setState(() => _moduloSeleccionado = value);
                  },
                ),
                const SizedBox(height: 18),
                _SeccionMovimientos(
                  cantidad: movimientos.length,
                  total: data.movimientos.length,
                ),
                const SizedBox(height: 8),
                if (movimientos.isEmpty)
                  const _EstadoVacio(
                    icono: Icons.manage_search,
                    titulo: 'Sin movimientos',
                    mensaje: 'No hay registros para los filtros actuales.',
                  )
                else
                  ...movimientos.map(
                    (movimiento) => _MovimientoCard(
                      movimiento: movimiento,
                      usuario: data.usuariosPorId[movimiento.usuarioId],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<AuditoriaModel> _filtrar(List<AuditoriaModel> movimientos) {
    return movimientos.where((movimiento) {
      final coincideModulo =
          _moduloSeleccionado == 'todos' ||
          movimiento.modulo == _moduloSeleccionado;
      final texto = [
        movimiento.accion,
        movimiento.modulo,
        movimiento.descripcion,
      ].join(' ').toLowerCase();
      final coincideBusqueda = _busqueda.isEmpty || texto.contains(_busqueda);

      return coincideModulo && coincideBusqueda;
    }).toList();
  }
}

class _AuditoriaData {
  const _AuditoriaData({
    this.movimientos = const [],
    this.usuariosPorId = const {},
  });

  final List<AuditoriaModel> movimientos;
  final Map<int, UsuarioModel> usuariosPorId;

  int porModulo(String modulo) {
    return movimientos.where((item) => item.modulo == modulo).length;
  }

  int movimientosHoy() {
    final hoy = DateTime.now();
    return movimientos.where((item) {
      final fecha = item.fechaHora;
      return fecha.year == hoy.year &&
          fecha.month == hoy.month &&
          fecha.day == hoy.day;
    }).length;
  }
}

class _ResumenAuditoria extends StatelessWidget {
  const _ResumenAuditoria({
    required this.total,
    required this.hoy,
    required this.cobros,
    required this.prestamos,
    required this.clientes,
    required this.usuarios,
  });

  final int total;
  final int hoy;
  final int cobros;
  final int prestamos;
  final int clientes;
  final int usuarios;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: MediaQuery.sizeOf(context).width > 900 ? 3 : 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.85,
      children: [
        _ResumenCard(
          titulo: 'Total registrado',
          valor: '$total',
          icono: Icons.receipt_long,
          color: Colors.indigo,
        ),
        _ResumenCard(
          titulo: 'Movimientos hoy',
          valor: '$hoy',
          icono: Icons.today,
          color: Colors.teal,
        ),
        _ResumenCard(
          titulo: 'Cobros',
          valor: '$cobros',
          icono: Icons.payments,
          color: Colors.green,
        ),
        _ResumenCard(
          titulo: 'Prestamos',
          valor: '$prestamos',
          icono: Icons.attach_money,
          color: Colors.orange,
        ),
        _ResumenCard(
          titulo: 'Clientes',
          valor: '$clientes',
          icono: Icons.people,
          color: Colors.blue,
        ),
        _ResumenCard(
          titulo: 'Usuarios',
          valor: '$usuarios',
          icono: Icons.badge,
          color: Colors.purple,
        ),
      ],
    );
  }
}

class _ResumenCard extends StatelessWidget {
  const _ResumenCard({
    required this.titulo,
    required this.valor,
    required this.icono,
    required this.color,
  });

  final String titulo;
  final String valor;
  final IconData icono;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(icono, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    valor,
                    style: const TextStyle(
                      fontSize: 22,
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

class _FiltroPanel extends StatelessWidget {
  const _FiltroPanel({
    required this.buscarController,
    required this.seleccionado,
    required this.onChanged,
  });

  final TextEditingController buscarController;
  final String seleccionado;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const filtros = [
      _FiltroItem(valor: 'todos', etiqueta: 'Todos'),
      _FiltroItem(valor: 'cobros', etiqueta: 'Cobros'),
      _FiltroItem(valor: 'prestamos', etiqueta: 'Prestamos'),
      _FiltroItem(valor: 'clientes', etiqueta: 'Clientes'),
      _FiltroItem(valor: 'rutas', etiqueta: 'Rutas'),
      _FiltroItem(valor: 'caja', etiqueta: 'Caja'),
      _FiltroItem(valor: 'usuarios', etiqueta: 'Usuarios'),
      _FiltroItem(valor: 'auth', etiqueta: 'Accesos'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: buscarController,
              decoration: const InputDecoration(
                labelText: 'Buscar por accion, modulo o detalle',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final filtro in filtros)
                  ChoiceChip(
                    label: Text(filtro.etiqueta),
                    selected: seleccionado == filtro.valor,
                    onSelected: (_) => onChanged(filtro.valor),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FiltroItem {
  const _FiltroItem({required this.valor, required this.etiqueta});

  final String valor;
  final String etiqueta;
}

class _MovimientoCard extends StatelessWidget {
  const _MovimientoCard({required this.movimiento, required this.usuario});

  final AuditoriaModel movimiento;
  final UsuarioModel? usuario;

  @override
  Widget build(BuildContext context) {
    final color = _colorPorModulo(movimiento.modulo);
    final usuarioNombre = usuario?.nombre ?? 'Usuario eliminado';
    final referencia = movimiento.referenciaId == null
        ? null
        : '#${movimiento.referenciaId}';

    return Card(
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(width: 5, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundColor: color.withValues(alpha: 0.12),
                          child: Icon(
                            _iconoPorModulo(movimiento.modulo),
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _accionLabel(movimiento.accion),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                usuarioNombre,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _hora(movimiento.fechaHora),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(movimiento.descripcion),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _InfoChip(
                          icono: Icons.folder_open,
                          texto: _moduloLabel(movimiento.modulo),
                          color: color,
                        ),
                        _InfoChip(
                          icono: Icons.calendar_month,
                          texto: _fecha(movimiento.fechaHora),
                          color: Colors.grey,
                        ),
                        if (referencia != null)
                          _InfoChip(
                            icono: Icons.tag,
                            texto: referencia,
                            color: Colors.grey,
                          ),
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

  IconData _iconoPorModulo(String modulo) {
    switch (modulo) {
      case 'cobros':
        return Icons.payments;
      case 'prestamos':
        return Icons.attach_money;
      case 'clientes':
        return Icons.people;
      case 'rutas':
        return Icons.route;
      case 'caja':
        return Icons.account_balance_wallet;
      case 'usuarios':
        return Icons.person;
      case 'configuracion':
        return Icons.settings;
      case 'auth':
        return Icons.login;
      default:
        return Icons.receipt_long;
    }
  }

  Color _colorPorModulo(String modulo) {
    switch (modulo) {
      case 'cobros':
        return Colors.green;
      case 'prestamos':
        return Colors.orange;
      case 'clientes':
        return Colors.blue;
      case 'rutas':
        return Colors.deepOrange;
      case 'caja':
        return Colors.green;
      case 'usuarios':
        return Colors.purple;
      case 'configuracion':
        return Colors.teal;
      case 'auth':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }
}

class _SeccionMovimientos extends StatelessWidget {
  const _SeccionMovimientos({required this.cantidad, required this.total});

  final int cantidad;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Movimientos',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text('$cantidad de $total registros visibles'),
            ],
          ),
        ),
        const Icon(Icons.history),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icono,
    required this.texto,
    required this.color,
  });

  final IconData icono;
  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            texto,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _EstadoVacio extends StatelessWidget {
  const _EstadoVacio({
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
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(icono, size: 48, color: Colors.grey),
          const SizedBox(height: 10),
          Text(titulo, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(mensaje, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

String _fecha(DateTime value) {
  return '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.year}';
}

String _hora(DateTime value) {
  return '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

String _moduloLabel(String modulo) {
  switch (modulo) {
    case 'auth':
      return 'Accesos';
    case 'clientes':
      return 'Clientes';
    case 'rutas':
      return 'Rutas';
    case 'caja':
      return 'Caja';
    case 'prestamos':
      return 'Prestamos';
    case 'cobros':
      return 'Cobros';
    case 'usuarios':
      return 'Usuarios';
    case 'configuracion':
      return 'Configuracion';
    default:
      return modulo;
  }
}

String _accionLabel(String accion) {
  switch (accion) {
    case 'login':
      return 'Inicio de sesion';
    case 'logout':
      return 'Cierre de sesion';
    case 'crear':
      return 'Registro creado';
    case 'actualizar':
      return 'Registro actualizado';
    case 'desactivar':
      return 'Registro desactivado';
    case 'asignar_cobrador':
      return 'Cobrador asignado';
    case 'cambiar_estado':
      return 'Cambio de estado';
    case 'registrar_cobro':
      return 'Cobro registrado';
    case 'registrar_visita':
      return 'Visita registrada';
    case 'cancelar':
      return 'Registro cancelado';
    case 'backup':
      return 'Backup registrado';
    case 'agregar_cliente':
      return 'Cliente agregado';
    case 'quitar_cliente':
      return 'Cliente removido';
    case 'reordenar':
      return 'Ruta reordenada';
    case 'cobro_ruta':
      return 'Cobro en ruta';
    case 'visita_ruta':
      return 'Visita en ruta';
    case 'registrar_gasto':
      return 'Gasto registrado';
    case 'solicitar_saldo':
      return 'Solicitud de saldo';
    case 'aprobar_saldo':
      return 'Saldo aprobado';
    case 'rechazar_saldo':
      return 'Saldo rechazado';
    case 'asignar_saldo':
      return 'Saldo asignado';
    case 'cerrar_caja':
      return 'Cierre de caja';
    default:
      final limpio = accion.replaceAll('_', ' ');
      return limpio.isEmpty
          ? 'Movimiento'
          : '${limpio[0].toUpperCase()}${limpio.substring(1)}';
  }
}
