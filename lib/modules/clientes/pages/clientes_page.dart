import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/session/session_manager.dart';
import '../../historial_financiero/pages/historial_financiero_page.dart';
import '../../usuarios/data/usuario_repository.dart';
import '../../usuarios/models/usuario_model.dart';
import '../data/cliente_repository.dart';
import '../models/cliente_model.dart';

enum _FiltroClientes { todos, activos, inactivos, sinCobrador }

class ClientesPage extends StatefulWidget {
  const ClientesPage({super.key, this.clienteInicialId});

  final int? clienteInicialId;

  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  final _clienteRepository = const ClienteRepository();
  final _usuarioRepository = const UsuarioRepository();
  final _permissionService = const PermissionService();
  final _buscarController = TextEditingController();

  List<ClienteModel> _clientes = [];
  Map<int, UsuarioModel> _usuarios = {};
  _FiltroClientes _filtro = _FiltroClientes.todos;
  bool _cargando = true;
  bool _detalleInicialMostrado = false;

  @override
  void initState() {
    super.initState();
    _cargarClientes();
  }

  @override
  void dispose() {
    _buscarController.dispose();
    super.dispose();
  }

  Future<void> _cargarClientes() async {
    setState(() => _cargando = true);

    final cobradorId = _permissionService.cobradorScope();
    final query = _buscarController.text.trim();
    final clientes = query.isEmpty
        ? await _clienteRepository.listar(cobradorId: cobradorId)
        : await _clienteRepository.buscar(query, cobradorId: cobradorId);
    final usuarios = await _usuarioRepository.listar();

    if (!mounted) return;
    setState(() {
      _clientes = clientes;
      _usuarios = {
        for (final usuario in usuarios)
          if (usuario.id != null) usuario.id!: usuario,
      };
      _cargando = false;
    });
    _mostrarDetalleInicial();
  }

  void _mostrarDetalleInicial() {
    if (_detalleInicialMostrado || widget.clienteInicialId == null) return;
    ClienteModel? cliente;
    for (final item in _clientes) {
      if (item.id == widget.clienteInicialId) {
        cliente = item;
        break;
      }
    }
    if (cliente == null) return;
    final clienteEncontrado = cliente;
    _detalleInicialMostrado = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _verDetalle(clienteEncontrado);
    });
  }

  List<ClienteModel> get _clientesFiltrados {
    return switch (_filtro) {
      _FiltroClientes.activos =>
        _clientes
            .where((cliente) => cliente.estado == AppEstados.activo)
            .toList(),
      _FiltroClientes.inactivos =>
        _clientes
            .where((cliente) => cliente.estado == AppEstados.inactivo)
            .toList(),
      _FiltroClientes.sinCobrador =>
        _clientes.where((cliente) => cliente.cobradorId == null).toList(),
      _FiltroClientes.todos => _clientes,
    };
  }

  Future<void> _abrirFormulario({ClienteModel? cliente}) async {
    final resultado = await showModalBottomSheet<ClienteModel>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _ClienteFormSheet(cliente: cliente),
    );

    if (resultado == null) return;
    final usuarioActual = SessionManager.instance.usuarioActual;
    final clienteAGuardar = resultado.copyWith(
      cobradorId:
          cliente?.cobradorId ??
          (_permissionService.esCobrador ? usuarioActual?.id : null),
    );

    if (cliente?.id == null) {
      await _clienteRepository.crear(clienteAGuardar);
    } else {
      await _clienteRepository.actualizar(clienteAGuardar);
    }

    await _cargarClientes();
  }

  Future<void> _asignarCobrador(ClienteModel cliente) async {
    final cobradores = await _usuarioRepository.listarCobradoresActivos();
    if (!mounted) return;

    if (cobradores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Primero crea un usuario cobrador activo.'),
        ),
      );
      return;
    }

    final cobrador = await showModalBottomSheet<UsuarioModel>(
      context: context,
      builder: (context) => _CobradoresSheet(cobradores: cobradores),
    );

    if (cobrador?.id == null || cliente.id == null) return;

    await _clienteRepository.asignarCobrador(
      clienteId: cliente.id!,
      cobradorId: cobrador!.id!,
    );
    await _cargarClientes();
  }

  Future<void> _cambiarEstado(ClienteModel cliente) async {
    if (cliente.id == null) return;

    final nuevoEstado = cliente.estaActivo
        ? AppEstados.inactivo
        : AppEstados.activo;
    await _clienteRepository.actualizar(cliente.copyWith(estado: nuevoEstado));
    await _cargarClientes();
  }

  void _verDetalle(ClienteModel cliente) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (context) => _ClienteDetalleSheet(
        cliente: cliente,
        cobradorNombre: _nombreCobrador(cliente.cobradorId),
        puedeEditar: _permissionService.puedeEditarClientes(),
        puedeAsignar: _permissionService.puedeAsignarClientes(),
        puedeCambiarEstado: _permissionService.puedeCambiarEstadoClientes(),
        onEditar: () {
          Navigator.pop(context);
          _abrirFormulario(cliente: cliente);
        },
        onAsignar: () {
          Navigator.pop(context);
          _asignarCobrador(cliente);
        },
        onCambiarEstado: () {
          Navigator.pop(context);
          _cambiarEstado(cliente);
        },
        onHistorial: () {
          Navigator.pop(context);
          _verHistorialCliente(cliente);
        },
      ),
    );
  }

  Future<void> _verHistorialCliente(ClienteModel cliente) async {
    if (cliente.id == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HistorialFinancieroPage(clienteId: cliente.id),
      ),
    );
  }

  String _nombreCobrador(int? cobradorId) {
    if (cobradorId == null) return 'Sin asignar';
    return _usuarios[cobradorId]?.nombre ?? 'Cobrador #$cobradorId';
  }

  @override
  Widget build(BuildContext context) {
    final clientes = _clientesFiltrados;
    final puedeEditar = _permissionService.puedeEditarClientes();
    final puedeAsignar = _permissionService.puedeAsignarClientes();
    final puedeCambiarEstado = _permissionService.puedeCambiarEstadoClientes();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargarClientes,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: _permissionService.puedeCrearClientes()
          ? FloatingActionButton.extended(
              onPressed: () => _abrirFormulario(),
              icon: const Icon(Icons.person_add),
              label: const Text('Nuevo'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _cargarClientes,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            _ResumenClientes(clientes: _clientes),
            const SizedBox(height: 16),
            TextField(
              controller: _buscarController,
              onChanged: (_) => _cargarClientes(),
              decoration: InputDecoration(
                labelText: 'Buscar por nombre, cedula, telefono o barrio',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _buscarController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar busqueda',
                        onPressed: () {
                          _buscarController.clear();
                          _cargarClientes();
                        },
                        icon: const Icon(Icons.close),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            _FiltrosClientes(
              filtro: _filtro,
              puedeVerSinCobrador: puedeAsignar,
              onChanged: (filtro) => setState(() => _filtro = filtro),
            ),
            const SizedBox(height: 16),
            if (_cargando)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (clientes.isEmpty)
              const _EmptyClientes()
            else
              ...clientes.map(
                (cliente) => _ClienteCard(
                  cliente: cliente,
                  cobradorNombre: _nombreCobrador(cliente.cobradorId),
                  puedeEditar: puedeEditar,
                  puedeAsignar: puedeAsignar,
                  puedeCambiarEstado: puedeCambiarEstado,
                  onTap: () => _verDetalle(cliente),
                  onEditar: () => _abrirFormulario(cliente: cliente),
                  onAsignar: () => _asignarCobrador(cliente),
                  onCambiarEstado: () => _cambiarEstado(cliente),
                  onHistorial: () => _verHistorialCliente(cliente),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ResumenClientes extends StatelessWidget {
  const _ResumenClientes({required this.clientes});

  final List<ClienteModel> clientes;

  @override
  Widget build(BuildContext context) {
    final activos = clientes.where((cliente) => cliente.estaActivo).length;
    final sinCobrador = clientes
        .where((cliente) => cliente.cobradorId == null)
        .length;

    return Row(
      children: [
        Expanded(
          child: _ResumenItem(
            icono: Icons.people,
            valor: '${clientes.length}',
            titulo: 'Total',
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ResumenItem(
            icono: Icons.check_circle,
            valor: '$activos',
            titulo: 'Activos',
            color: Colors.green,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ResumenItem(
            icono: Icons.assignment_ind,
            valor: '$sinCobrador',
            titulo: 'Sin cobrador',
            color: Colors.orange,
          ),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, color: color),
            const SizedBox(height: 8),
            Text(
              valor,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _FiltrosClientes extends StatelessWidget {
  const _FiltrosClientes({
    required this.filtro,
    required this.puedeVerSinCobrador,
    required this.onChanged,
  });

  final _FiltroClientes filtro;
  final bool puedeVerSinCobrador;
  final ValueChanged<_FiltroClientes> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<_FiltroClientes>(
        selected: {filtro},
        onSelectionChanged: (value) => onChanged(value.first),
        segments: [
          const ButtonSegment(
            value: _FiltroClientes.todos,
            label: Text('Todos'),
            icon: Icon(Icons.list),
          ),
          const ButtonSegment(
            value: _FiltroClientes.activos,
            label: Text('Activos'),
            icon: Icon(Icons.check_circle),
          ),
          const ButtonSegment(
            value: _FiltroClientes.inactivos,
            label: Text('Inactivos'),
            icon: Icon(Icons.pause_circle),
          ),
          if (puedeVerSinCobrador)
            const ButtonSegment(
              value: _FiltroClientes.sinCobrador,
              label: Text('Sin cobrador'),
              icon: Icon(Icons.assignment_ind),
            ),
        ],
      ),
    );
  }
}

class _ClienteCard extends StatelessWidget {
  const _ClienteCard({
    required this.cliente,
    required this.cobradorNombre,
    required this.puedeEditar,
    required this.puedeAsignar,
    required this.puedeCambiarEstado,
    required this.onTap,
    required this.onEditar,
    required this.onAsignar,
    required this.onCambiarEstado,
    required this.onHistorial,
  });

  final ClienteModel cliente;
  final String cobradorNombre;
  final bool puedeEditar;
  final bool puedeAsignar;
  final bool puedeCambiarEstado;
  final VoidCallback onTap;
  final VoidCallback onEditar;
  final VoidCallback onAsignar;
  final VoidCallback onCambiarEstado;
  final VoidCallback onHistorial;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: cliente.estaActivo
                    ? Colors.green.shade50
                    : Colors.grey.shade200,
                child: Icon(
                  Icons.person,
                  color: cliente.estaActivo ? Colors.green : Colors.grey,
                ),
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
                            cliente.nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _EstadoChip(activo: cliente.estaActivo),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _InfoLine(
                      icono: Icons.badge,
                      texto: cliente.cedula ?? 'Sin cedula',
                    ),
                    _InfoLine(
                      icono: Icons.phone,
                      texto: cliente.telefono ?? 'Sin telefono',
                    ),
                    _InfoLine(
                      icono: Icons.place,
                      texto: [cliente.barrio, cliente.direccion]
                          .whereType<String>()
                          .join(' - ')
                          .ifEmpty('Sin direccion'),
                    ),
                    _InfoLine(
                      icono: Icons.assignment_ind,
                      texto: cobradorNombre,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: onTap,
                          icon: const Icon(Icons.visibility),
                          label: const Text('Ver información'),
                        ),
                        OutlinedButton.icon(
                          onPressed: onHistorial,
                          icon: const Icon(Icons.history),
                          label: const Text('Historial'),
                        ),
                        if (puedeAsignar)
                          OutlinedButton.icon(
                            onPressed: onAsignar,
                            icon: const Icon(Icons.assignment_ind),
                            label: Text(
                              cliente.cobradorId == null
                                  ? 'Asignar cobrador'
                                  : 'Cambiar cobrador',
                            ),
                          ),
                        if (puedeEditar)
                          IconButton.filledTonal(
                            tooltip: 'Editar cliente',
                            onPressed: onEditar,
                            icon: const Icon(Icons.edit),
                          ),
                        if (puedeCambiarEstado)
                          IconButton.filledTonal(
                            tooltip: cliente.estaActivo
                                ? 'Desactivar cliente'
                                : 'Activar cliente',
                            onPressed: onCambiarEstado,
                            icon: Icon(
                              cliente.estaActivo
                                  ? Icons.pause_circle
                                  : Icons.play_circle,
                            ),
                          ),
                      ],
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

class _EstadoChip extends StatelessWidget {
  const _EstadoChip({required this.activo});

  final bool activo;

  @override
  Widget build(BuildContext context) {
    final MaterialColor color = activo ? Colors.green : Colors.grey;
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(activo ? 'Activo' : 'Inactivo'),
      avatar: Icon(activo ? Icons.check : Icons.pause, size: 16, color: color),
      side: BorderSide(color: color.shade300),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icono, size: 16, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Expanded(
            child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

class _ClienteDetalleSheet extends StatelessWidget {
  const _ClienteDetalleSheet({
    required this.cliente,
    required this.cobradorNombre,
    required this.puedeEditar,
    required this.puedeAsignar,
    required this.puedeCambiarEstado,
    required this.onEditar,
    required this.onAsignar,
    required this.onCambiarEstado,
    required this.onHistorial,
  });

  final ClienteModel cliente;
  final String cobradorNombre;
  final bool puedeEditar;
  final bool puedeAsignar;
  final bool puedeCambiarEstado;
  final VoidCallback onEditar;
  final VoidCallback onAsignar;
  final VoidCallback onCambiarEstado;
  final VoidCallback onHistorial;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(child: Icon(Icons.person)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  cliente.nombre,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              _EstadoChip(activo: cliente.estaActivo),
            ],
          ),
          const SizedBox(height: 18),
          _DetalleItem(label: 'Cedula', value: cliente.cedula),
          _DetalleItem(label: 'Telefono', value: cliente.telefono),
          _DetalleItem(label: 'Direccion', value: cliente.direccion),
          _DetalleItem(label: 'Barrio', value: cliente.barrio),
          _DetalleItem(label: 'Referencia', value: cliente.referencia),
          _DetalleItem(label: 'Cobrador', value: cobradorNombre),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onHistorial,
              icon: const Icon(Icons.history),
              label: const Text('Historial financiero'),
            ),
          ),
          if (puedeEditar || puedeAsignar || puedeCambiarEstado) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                if (puedeEditar)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onEditar,
                      icon: const Icon(Icons.edit),
                      label: const Text('Editar'),
                    ),
                  ),
                if (puedeEditar && puedeAsignar) const SizedBox(width: 8),
                if (puedeAsignar)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onAsignar,
                      icon: const Icon(Icons.assignment_ind),
                      label: const Text('Cobrador'),
                    ),
                  ),
              ],
            ),
            if (puedeCambiarEstado) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: onCambiarEstado,
                  icon: Icon(
                    cliente.estaActivo ? Icons.pause_circle : Icons.play_circle,
                  ),
                  label: Text(cliente.estaActivo ? 'Desactivar' : 'Activar'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _DetalleItem extends StatelessWidget {
  const _DetalleItem({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text(value?.isNotEmpty == true ? value! : 'Sin dato'),
          ),
        ],
      ),
    );
  }
}

class _ClienteFormSheet extends StatefulWidget {
  const _ClienteFormSheet({this.cliente});

  final ClienteModel? cliente;

  @override
  State<_ClienteFormSheet> createState() => _ClienteFormSheetState();
}

class _ClienteFormSheetState extends State<_ClienteFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _cedulaController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _direccionController = TextEditingController();
  final _barrioController = TextEditingController();
  final _referenciaController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final cliente = widget.cliente;
    if (cliente == null) return;

    _nombreController.text = cliente.nombre;
    _cedulaController.text = cliente.cedula ?? '';
    _telefonoController.text = cliente.telefono ?? '';
    _direccionController.text = cliente.direccion ?? '';
    _barrioController.text = cliente.barrio ?? '';
    _referenciaController.text = cliente.referencia ?? '';
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _cedulaController.dispose();
    _telefonoController.dispose();
    _direccionController.dispose();
    _barrioController.dispose();
    _referenciaController.dispose();
    super.dispose();
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;

    final actual = widget.cliente;
    Navigator.pop(
      context,
      ClienteModel(
        id: actual?.id,
        nombre: _nombreController.text.trim(),
        cedula: _emptyToNull(_cedulaController.text),
        telefono: _emptyToNull(_telefonoController.text),
        direccion: _emptyToNull(_direccionController.text),
        barrio: _emptyToNull(_barrioController.text),
        referencia: _emptyToNull(_referenciaController.text),
        foto: actual?.foto,
        cobradorId: actual?.cobradorId,
        estado: actual?.estado ?? AppEstados.activo,
        fechaRegistro: actual?.fechaRegistro ?? DateTime.now(),
      ),
    );
  }

  String? _emptyToNull(String value) {
    final clean = value.trim();
    return clean.isEmpty ? null : clean;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final editando = widget.cliente != null;

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
                editando ? 'Editar cliente' : 'Nuevo cliente',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              const Text(
                'Completa los datos que el administrador necesita ver.',
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _nombreController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'El nombre es obligatorio';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _cedulaController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Cedula',
                        prefixIcon: Icon(Icons.badge),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _telefonoController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Telefono',
                        prefixIcon: Icon(Icons.phone),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _direccionController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Direccion',
                  prefixIcon: Icon(Icons.home),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _barrioController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Barrio',
                  prefixIcon: Icon(Icons.map),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _referenciaController,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Referencia',
                  hintText: 'Ej: casa azul, frente a la tienda',
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
                  label: Text(editando ? 'Guardar cambios' : 'Crear cliente'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CobradoresSheet extends StatelessWidget {
  const _CobradoresSheet({required this.cobradores});

  final List<UsuarioModel> cobradores;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Seleccionar cobrador',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        for (final cobrador in cobradores)
          Card(
            child: ListTile(
              leading: const Icon(Icons.badge),
              title: Text(cobrador.nombre),
              subtitle: Text(cobrador.usuario),
              onTap: () => Navigator.pop(context, cobrador),
            ),
          ),
      ],
    );
  }
}

class _EmptyClientes extends StatelessWidget {
  const _EmptyClientes();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey.shade500),
          const SizedBox(height: 12),
          const Text(
            'No hay clientes para mostrar',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Crea un cliente o cambia el filtro seleccionado.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
