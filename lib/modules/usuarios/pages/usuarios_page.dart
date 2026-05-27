import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/session/session_manager.dart';
import '../data/usuario_repository.dart';
import '../models/usuario_model.dart';

enum _FiltroUsuarios { todos, administradores, cobradores, activos, inactivos }

class UsuariosPage extends StatefulWidget {
  const UsuariosPage({super.key});

  @override
  State<UsuariosPage> createState() => _UsuariosPageState();
}

class _UsuariosPageState extends State<UsuariosPage> {
  final _repository = const UsuarioRepository();
  final _buscarController = TextEditingController();

  List<UsuarioModel> _usuarios = [];
  _FiltroUsuarios _filtro = _FiltroUsuarios.todos;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarUsuarios();
  }

  @override
  void dispose() {
    _buscarController.dispose();
    super.dispose();
  }

  Future<void> _cargarUsuarios() async {
    setState(() => _cargando = true);
    final usuarios = await _repository.listar();

    if (!mounted) return;
    setState(() {
      _usuarios = usuarios;
      _cargando = false;
    });
  }

  List<UsuarioModel> get _usuariosFiltrados {
    final query = _buscarController.text.trim().toLowerCase();
    final usuarioActual = SessionManager.instance.usuarioActual;
    final visibles = usuarioActual?.esSuperadmin == true
        ? _usuarios
        : _usuarios.where((usuario) => !usuario.esSuperadmin);

    return visibles.where((usuario) {
      final coincideBusqueda =
          query.isEmpty ||
          usuario.nombre.toLowerCase().contains(query) ||
          usuario.usuario.toLowerCase().contains(query) ||
          usuario.rol.toLowerCase().contains(query);

      final coincideFiltro = switch (_filtro) {
        _FiltroUsuarios.administradores => usuario.esAdministrador,
        _FiltroUsuarios.cobradores => usuario.esCobrador,
        _FiltroUsuarios.activos => usuario.estaActivo,
        _FiltroUsuarios.inactivos => !usuario.estaActivo,
        _FiltroUsuarios.todos => true,
      };

      return coincideBusqueda && coincideFiltro;
    }).toList();
  }

  Future<void> _abrirFormulario({UsuarioModel? usuario}) async {
    if (usuario?.esSuperadmin == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El superadmin no se edita desde aqui.')),
      );
      return;
    }

    final resultado = await showModalBottomSheet<UsuarioModel>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _UsuarioFormSheet(usuario: usuario),
    );

    if (resultado == null) return;

    try {
      if (usuario?.id == null) {
        await _repository.crear(resultado);
      } else {
        await _repository.actualizar(resultado);
      }
      await _cargarUsuarios();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _cambiarEstado(UsuarioModel usuario) async {
    if (usuario.id == null) return;

    final usuarioActual = SessionManager.instance.usuarioActual;
    if (usuario.esSuperadmin && usuarioActual?.esSuperadmin != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No puedes modificar el superadmin.')),
      );
      return;
    }
    if (usuarioActual?.id == usuario.id && usuario.estaActivo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No puedes desactivar tu propio usuario activo.'),
        ),
      );
      return;
    }

    final nuevoEstado = usuario.estaActivo
        ? AppEstados.inactivo
        : AppEstados.activo;
    await _repository.cambiarEstado(usuario.id!, nuevoEstado);
    await _cargarUsuarios();
  }

  void _verDetalle(UsuarioModel usuario) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (context) => _UsuarioDetalleSheet(
        usuario: usuario,
        onEditar: () {
          Navigator.pop(context);
          _abrirFormulario(usuario: usuario);
        },
        onCambiarEstado: () {
          Navigator.pop(context);
          _cambiarEstado(usuario);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usuarios = _usuariosFiltrados;
    final usuarioActual = SessionManager.instance.usuarioActual;
    final usuariosVisibles = usuarioActual?.esSuperadmin == true
        ? _usuarios
        : _usuarios.where((usuario) => !usuario.esSuperadmin).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Usuarios'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargarUsuarios,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.person_add),
        label: const Text('Nuevo usuario'),
      ),
      body: RefreshIndicator(
        onRefresh: _cargarUsuarios,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            _ResumenUsuarios(usuarios: usuariosVisibles),
            const SizedBox(height: 16),
            TextField(
              controller: _buscarController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Buscar por nombre, usuario o rol',
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
            const SizedBox(height: 12),
            _FiltrosUsuarios(
              filtro: _filtro,
              onChanged: (filtro) => setState(() => _filtro = filtro),
            ),
            const SizedBox(height: 16),
            if (_cargando)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (usuarios.isEmpty)
              const _EmptyUsuarios()
            else
              ...usuarios.map(
                (usuario) => _UsuarioCard(
                  usuario: usuario,
                  onTap: () => _verDetalle(usuario),
                  onEditar: () => _abrirFormulario(usuario: usuario),
                  onCambiarEstado: () => _cambiarEstado(usuario),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ResumenUsuarios extends StatelessWidget {
  const _ResumenUsuarios({required this.usuarios});

  final List<UsuarioModel> usuarios;

  @override
  Widget build(BuildContext context) {
    final administradores = usuarios.where((u) => u.esAdministrador).length;
    final cobradores = usuarios.where((u) => u.esCobrador).length;
    final activos = usuarios.where((u) => u.estaActivo).length;

    return Row(
      children: [
        Expanded(
          child: _ResumenItem(
            icono: Icons.people,
            valor: '${usuarios.length}',
            titulo: 'Total',
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ResumenItem(
            icono: Icons.admin_panel_settings,
            valor: '$administradores',
            titulo: 'Admins',
            color: Colors.deepPurple,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ResumenItem(
            icono: Icons.badge,
            valor: '$cobradores',
            titulo: 'Cobradores',
            color: Colors.orange,
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
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono, color: color),
            const SizedBox(height: 8),
            Text(
              valor,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _FiltrosUsuarios extends StatelessWidget {
  const _FiltrosUsuarios({required this.filtro, required this.onChanged});

  final _FiltroUsuarios filtro;
  final ValueChanged<_FiltroUsuarios> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<_FiltroUsuarios>(
        selected: {filtro},
        onSelectionChanged: (value) => onChanged(value.first),
        segments: const [
          ButtonSegment(
            value: _FiltroUsuarios.todos,
            label: Text('Todos'),
            icon: Icon(Icons.list),
          ),
          ButtonSegment(
            value: _FiltroUsuarios.administradores,
            label: Text('Admins'),
            icon: Icon(Icons.admin_panel_settings),
          ),
          ButtonSegment(
            value: _FiltroUsuarios.cobradores,
            label: Text('Cobradores'),
            icon: Icon(Icons.badge),
          ),
          ButtonSegment(
            value: _FiltroUsuarios.activos,
            label: Text('Activos'),
            icon: Icon(Icons.check_circle),
          ),
          ButtonSegment(
            value: _FiltroUsuarios.inactivos,
            label: Text('Inactivos'),
            icon: Icon(Icons.pause_circle),
          ),
        ],
      ),
    );
  }
}

class _UsuarioCard extends StatelessWidget {
  const _UsuarioCard({
    required this.usuario,
    required this.onTap,
    required this.onEditar,
    required this.onCambiarEstado,
  });

  final UsuarioModel usuario;
  final VoidCallback onTap;
  final VoidCallback onEditar;
  final VoidCallback onCambiarEstado;

  @override
  Widget build(BuildContext context) {
    final color = _rolColor(usuario);

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
                backgroundColor: color.shade50,
                child: Icon(_rolIcon(usuario), color: color),
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
                            usuario.nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _EstadoUsuarioChip(activo: usuario.estaActivo),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _InfoLine(icono: Icons.person, texto: usuario.usuario),
                    _InfoLine(icono: Icons.security, texto: _rolLabel(usuario)),
                    _InfoLine(
                      icono: Icons.calendar_month,
                      texto: 'Creado ${_date(usuario.fechaCreacion)}',
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: onTap,
                          icon: const Icon(Icons.visibility),
                          label: const Text('Ver'),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Editar usuario',
                          onPressed: onEditar,
                          icon: const Icon(Icons.edit),
                        ),
                        IconButton.filledTonal(
                          tooltip: usuario.estaActivo
                              ? 'Desactivar usuario'
                              : 'Activar usuario',
                          onPressed: onCambiarEstado,
                          icon: Icon(
                            usuario.estaActivo
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

class _EstadoUsuarioChip extends StatelessWidget {
  const _EstadoUsuarioChip({required this.activo});

  final bool activo;

  @override
  Widget build(BuildContext context) {
    final MaterialColor color = activo ? Colors.green : Colors.grey;

    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(activo ? Icons.check : Icons.pause, size: 16, color: color),
      label: Text(activo ? 'Activo' : 'Inactivo'),
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

class _UsuarioDetalleSheet extends StatelessWidget {
  const _UsuarioDetalleSheet({
    required this.usuario,
    required this.onEditar,
    required this.onCambiarEstado,
  });

  final UsuarioModel usuario;
  final VoidCallback onEditar;
  final VoidCallback onCambiarEstado;

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
              CircleAvatar(child: Icon(_rolIcon(usuario))),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  usuario.nombre,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              _EstadoUsuarioChip(activo: usuario.estaActivo),
            ],
          ),
          const SizedBox(height: 18),
          _DetalleItem(label: 'Usuario', value: usuario.usuario),
          _DetalleItem(label: 'Rol', value: _rolLabel(usuario)),
          _DetalleItem(label: 'Estado', value: usuario.estado),
          _DetalleItem(label: 'Creado', value: _date(usuario.fechaCreacion)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onEditar,
                  icon: const Icon(Icons.edit),
                  label: const Text('Editar'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCambiarEstado,
                  icon: Icon(
                    usuario.estaActivo ? Icons.pause_circle : Icons.play_circle,
                  ),
                  label: Text(usuario.estaActivo ? 'Desactivar' : 'Activar'),
                ),
              ),
            ],
          ),
        ],
      ),
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
            width: 80,
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

class _UsuarioFormSheet extends StatefulWidget {
  const _UsuarioFormSheet({this.usuario});

  final UsuarioModel? usuario;

  @override
  State<_UsuarioFormSheet> createState() => _UsuarioFormSheetState();
}

class _UsuarioFormSheetState extends State<_UsuarioFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _usuarioController = TextEditingController();
  final _contrasenaController = TextEditingController();

  String _rol = AppRoles.cobrador;
  String _estado = AppEstados.activo;

  @override
  void initState() {
    super.initState();
    final usuario = widget.usuario;
    if (usuario == null) return;

    _nombreController.text = usuario.nombre;
    _usuarioController.text = usuario.usuario;
    _contrasenaController.text = usuario.contrasena;
    _rol = usuario.rol;
    _estado = usuario.estado;
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _usuarioController.dispose();
    _contrasenaController.dispose();
    super.dispose();
  }

  void _guardar() {
    if (!_formKey.currentState!.validate()) return;

    final actual = widget.usuario;
    final contrasena = _contrasenaController.text.isEmpty && actual != null
        ? actual.contrasena
        : _contrasenaController.text;
    Navigator.pop(
      context,
      UsuarioModel(
        id: actual?.id,
        nombre: _nombreController.text.trim(),
        usuario: _usuarioController.text.trim(),
        contrasena: contrasena,
        rol: _rol,
        estado: _estado,
        saldoDisponible: actual?.saldoDisponible ?? 0,
        fechaCreacion: actual?.fechaCreacion ?? DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final editando = widget.usuario != null;

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
                editando ? 'Editar usuario' : 'Nuevo usuario',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              const Text('Define acceso, rol y estado dentro del sistema.'),
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
              TextFormField(
                controller: _usuarioController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Correo electronico',
                  prefixIcon: Icon(Icons.email),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'El correo es obligatorio';
                  }
                  if (!value.contains('@')) {
                    return 'Ingresa un correo valido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contrasenaController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Contrasena',
                  prefixIcon: Icon(Icons.lock),
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (!editando && (value == null || value.isEmpty)) {
                    return 'La contrasena es obligatoria';
                  }
                  if (value != null && value.isNotEmpty && value.length < 6) {
                    return 'Usa al menos 6 caracteres';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _rol,
                      items: const [
                        DropdownMenuItem(
                          value: AppRoles.cobrador,
                          child: Text('Cobrador'),
                        ),
                        DropdownMenuItem(
                          value: AppRoles.administrador,
                          child: Text('Administrador'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _rol = value ?? _rol),
                      decoration: const InputDecoration(
                        labelText: 'Rol',
                        prefixIcon: Icon(Icons.security),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _estado,
                      items: const [
                        DropdownMenuItem(
                          value: AppEstados.activo,
                          child: Text('Activo'),
                        ),
                        DropdownMenuItem(
                          value: AppEstados.inactivo,
                          child: Text('Inactivo'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() => _estado = value ?? _estado);
                      },
                      decoration: const InputDecoration(
                        labelText: 'Estado',
                        prefixIcon: Icon(Icons.toggle_on),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _guardar,
                  icon: const Icon(Icons.save),
                  label: Text(editando ? 'Guardar cambios' : 'Crear usuario'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyUsuarios extends StatelessWidget {
  const _EmptyUsuarios();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey.shade500),
          const SizedBox(height: 12),
          const Text(
            'No hay usuarios para mostrar',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Crea un usuario o cambia el filtro seleccionado.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

String _rolLabel(UsuarioModel usuario) {
  if (usuario.esSuperadmin) return 'Superadmin';
  return switch (usuario.rol) {
    AppRoles.administrador => 'Administrador',
    AppRoles.cobrador => 'Cobrador',
    _ => usuario.rol,
  };
}

MaterialColor _rolColor(UsuarioModel usuario) {
  if (usuario.esSuperadmin) return Colors.blueGrey;
  if (usuario.esAdministrador) return Colors.deepPurple;
  return Colors.orange;
}

IconData _rolIcon(UsuarioModel usuario) {
  if (usuario.esSuperadmin) return Icons.workspace_premium;
  if (usuario.esAdministrador) return Icons.admin_panel_settings;
  return Icons.badge;
}

String _date(DateTime value) {
  return '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.year}';
}
