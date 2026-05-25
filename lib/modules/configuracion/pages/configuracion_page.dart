import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../auditoria/data/auditoria_repository.dart';
import '../../suscripcion/pages/suscripcion_page.dart';
import '../data/configuracion_repository.dart';
import '../models/configuracion_model.dart';

class ConfiguracionPage extends StatefulWidget {
  const ConfiguracionPage({super.key});

  @override
  State<ConfiguracionPage> createState() => _ConfiguracionPageState();
}

class _ConfiguracionPageState extends State<ConfiguracionPage> {
  final _repository = const ConfiguracionRepository();
  final _auditoriaRepository = const AuditoriaRepository();
  final _permissionService = const PermissionService();
  final _formKey = GlobalKey<FormState>();

  final _empresaController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _direccionController = TextEditingController();
  final _monedaController = TextEditingController(text: 'COP');
  final _interesController = TextEditingController(text: '20');
  final _interesesPermitidosController = TextEditingController(
    text: '20,30,40',
  );
  final _montoMaximoCobradorController = TextEditingController(text: '500000');
  final _cuotasController = TextEditingController(text: '24');
  final _licenciaApiController = TextEditingController();
  final _licenciaClaveController = TextEditingController();
  final _pasarelaNombreController = TextEditingController(text: 'Pago externo');
  final _pasarelaUrlController = TextEditingController();
  final _nequiTitularController = TextEditingController();
  final _nequiTelefonoController = TextEditingController();

  bool _temaOscuro = false;
  bool _backupAutomatico = false;
  String? _ultimoBackup;
  bool _sqliteOk = false;
  bool _cargando = true;
  bool _guardando = false;

  bool get _esSuperadmin => _permissionService.esSuperadmin;

  @override
  void initState() {
    super.initState();
    _cargarConfiguraciones();
  }

  @override
  void dispose() {
    _empresaController.dispose();
    _telefonoController.dispose();
    _direccionController.dispose();
    _monedaController.dispose();
    _interesController.dispose();
    _interesesPermitidosController.dispose();
    _montoMaximoCobradorController.dispose();
    _cuotasController.dispose();
    _licenciaApiController.dispose();
    _licenciaClaveController.dispose();
    _pasarelaNombreController.dispose();
    _pasarelaUrlController.dispose();
    _nequiTitularController.dispose();
    _nequiTelefonoController.dispose();
    super.dispose();
  }

  Future<void> _cargarConfiguraciones() async {
    setState(() => _cargando = true);

    final configs = await _repository.listar();
    final sqliteOk = await DatabaseHelper.instance.testConnection();

    _aplicarConfiguraciones(configs);

    if (!mounted) return;
    setState(() {
      _sqliteOk = sqliteOk;
      _cargando = false;
    });
  }

  void _aplicarConfiguraciones(List<ConfiguracionModel> configs) {
    final values = {for (final config in configs) config.clave: config.valor};

    _empresaController.text = values[AppConfigKeys.empresaNombre] ?? '';
    _telefonoController.text = values[AppConfigKeys.empresaTelefono] ?? '';
    _direccionController.text = values[AppConfigKeys.empresaDireccion] ?? '';
    _monedaController.text = values[AppConfigKeys.moneda] ?? 'COP';
    _interesController.text = values[AppConfigKeys.interesDefecto] ?? '20';
    _interesesPermitidosController.text =
        values[AppConfigKeys.interesesPermitidos] ?? '20,30,40';
    _montoMaximoCobradorController.text =
        values[AppConfigKeys.montoMaximoCobrador] ?? '500000';
    _cuotasController.text = values[AppConfigKeys.cuotasDefecto] ?? '24';
    _licenciaApiController.text = values[AppConfigKeys.licenciaApiUrl] ?? '';
    _licenciaClaveController.text = values[AppConfigKeys.licenciaClave] ?? '';
    _pasarelaNombreController.text =
        values[AppConfigKeys.pasarelaPagoNombre] ?? 'Pago externo';
    _pasarelaUrlController.text = values[AppConfigKeys.pasarelaPagoUrl] ?? '';
    _nequiTitularController.text = values[AppConfigKeys.nequiTitular] ?? '';
    _nequiTelefonoController.text = values[AppConfigKeys.nequiTelefono] ?? '';
    _temaOscuro = values[AppConfigKeys.temaOscuro] == 'true';
    _backupAutomatico = values[AppConfigKeys.backupAutomatico] == 'true';
    _ultimoBackup = values[AppConfigKeys.ultimoBackup];
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _guardando = true);

    await _repository.guardarValor(
      clave: AppConfigKeys.empresaNombre,
      valor: _empresaController.text.trim(),
    );
    await _repository.guardarValor(
      clave: AppConfigKeys.empresaTelefono,
      valor: _telefonoController.text.trim(),
    );
    await _repository.guardarValor(
      clave: AppConfigKeys.empresaDireccion,
      valor: _direccionController.text.trim(),
    );
    await _repository.guardarValor(
      clave: AppConfigKeys.moneda,
      valor: _monedaController.text.trim().isEmpty
          ? 'COP'
          : _monedaController.text.trim().toUpperCase(),
    );
    await _repository.guardarValor(
      clave: AppConfigKeys.interesDefecto,
      valor: _interesController.text.trim(),
      tipo: 'numero',
    );
    await _repository.guardarValor(
      clave: AppConfigKeys.interesesPermitidos,
      valor: _interesesPermitidosController.text.trim(),
      tipo: 'lista',
    );
    await _repository.guardarValor(
      clave: AppConfigKeys.montoMaximoCobrador,
      valor: _montoMaximoCobradorController.text.trim(),
      tipo: 'numero',
    );
    await _repository.guardarValor(
      clave: AppConfigKeys.cuotasDefecto,
      valor: _cuotasController.text.trim(),
      tipo: 'numero',
    );
    await _repository.guardarValor(
      clave: AppConfigKeys.temaOscuro,
      valor: _temaOscuro.toString(),
      tipo: 'booleano',
    );
    await _repository.guardarValor(
      clave: AppConfigKeys.backupAutomatico,
      valor: _backupAutomatico.toString(),
      tipo: 'booleano',
    );
    if (_esSuperadmin) {
      await _repository.guardarValor(
        clave: AppConfigKeys.licenciaApiUrl,
        valor: _licenciaApiController.text.trim(),
      );
      await _repository.guardarValor(
        clave: AppConfigKeys.licenciaClave,
        valor: _licenciaClaveController.text.trim(),
      );
      await _repository.guardarValor(
        clave: AppConfigKeys.pasarelaPagoNombre,
        valor: _pasarelaNombreController.text.trim().isEmpty
            ? 'Pago externo'
            : _pasarelaNombreController.text.trim(),
      );
      await _repository.guardarValor(
        clave: AppConfigKeys.pasarelaPagoUrl,
        valor: _pasarelaUrlController.text.trim(),
      );
      await _repository.guardarValor(
        clave: AppConfigKeys.nequiTitular,
        valor: _nequiTitularController.text.trim(),
      );
      await _repository.guardarValor(
        clave: AppConfigKeys.nequiTelefono,
        valor: _nequiTelefonoController.text.trim(),
      );
    }
    await _auditoriaRepository.registrar(
      accion: 'actualizar',
      modulo: 'configuracion',
      descripcion: 'Configuracion general actualizada',
    );

    if (!mounted) return;
    setState(() => _guardando = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Configuración guardada')));
  }

  Future<void> _registrarBackupManual() async {
    final now = DateTime.now().toIso8601String();
    await _repository.guardarValor(
      clave: AppConfigKeys.ultimoBackup,
      valor: now,
      tipo: 'fecha',
    );
    await _auditoriaRepository.registrar(
      accion: 'backup',
      modulo: 'configuracion',
      descripcion: 'Backup local registrado',
    );
    await _cargarConfiguraciones();

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Backup local registrado')));
  }

  void _mostrarRestaurarPendiente() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Restaurar datos queda preparado para una fase futura.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargarConfiguraciones,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  _EstadoSistemaCard(sqliteOk: _sqliteOk),
                  const SizedBox(height: 16),
                  _ConfigSection(
                    icono: Icons.business,
                    titulo: 'Datos de empresa',
                    subtitulo: 'Información visible para reportes y recibos.',
                    children: [
                      TextFormField(
                        controller: _empresaController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Nombre de empresa',
                          prefixIcon: Icon(Icons.store),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _telefonoController,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Teléfono',
                          prefixIcon: Icon(Icons.phone),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _direccionController,
                        decoration: const InputDecoration(
                          labelText: 'Dirección',
                          prefixIcon: Icon(Icons.place),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ConfigSection(
                    icono: Icons.attach_money,
                    titulo: 'Parámetros de préstamos',
                    subtitulo:
                        'Valores usados como sugerencia al crear préstamos.',
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _monedaController,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                labelText: 'Moneda',
                                prefixIcon: Icon(Icons.payments),
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Requerida';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _interesController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Interés %',
                                prefixIcon: Icon(Icons.percent),
                                border: OutlineInputBorder(),
                              ),
                              validator: (value) {
                                final interes = double.tryParse(value ?? '');
                                if (interes == null || interes < 0) {
                                  return 'Inválido';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _interesesPermitidosController,
                        decoration: const InputDecoration(
                          labelText: 'Intereses permitidos para cobrador',
                          hintText: 'Ej: 20,30,40',
                          prefixIcon: Icon(Icons.rule),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final intereses = _parseIntereses(value ?? '');
                          if (intereses.isEmpty) {
                            return 'Agrega al menos un interés permitido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _montoMaximoCobradorController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Monto máximo para cobrador',
                          prefixIcon: Icon(Icons.price_check),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final monto = CurrencyFormatter.parse(value ?? '');
                          if (monto <= 0) {
                            return 'Ingresa un monto válido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _cuotasController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Cuotas por defecto',
                          prefixIcon: Icon(Icons.calendar_month),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final cuotas = int.tryParse(value ?? '');
                          if (cuotas == null || cuotas <= 0) {
                            return 'Ingresa un número válido';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ConfigSection(
                    icono: Icons.workspace_premium,
                    titulo: 'Suscripcion y licencia',
                    subtitulo:
                        'Control comercial para activar clientes de pago.',
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.verified_user),
                        title: const Text('Estado de suscripcion'),
                        subtitle: const Text(
                          'Plan, vencimiento, pagos y eventos',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SuscripcionPage(),
                            ),
                          );
                        },
                      ),
                      if (_esSuperadmin) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _licenciaApiController,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'URL de API de licencias',
                            hintText: 'https://tu-dominio.com/api/licencias',
                            prefixIcon: Icon(Icons.cloud_sync),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _licenciaClaveController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Clave privada de licencia',
                            prefixIcon: Icon(Icons.key),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _pasarelaNombreController,
                          decoration: const InputDecoration(
                            labelText: 'Nombre de pasarela',
                            hintText: 'Ej: Wompi, MercadoPago, Stripe',
                            prefixIcon: Icon(Icons.payment),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _pasarelaUrlController,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'Link de pago o checkout',
                            hintText: 'https://checkout...',
                            prefixIcon: Icon(Icons.link),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _nequiTitularController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Titular Nequi personal',
                            hintText: 'Nombre de quien recibe el pago',
                            prefixIcon: Icon(Icons.person),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _nequiTelefonoController,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Numero Nequi personal',
                            hintText: 'Ej: 3001234567',
                            prefixIcon: Icon(Icons.phone_iphone),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ] else
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'La pasarela y las claves de licencia solo las configura el superadmin.',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ConfigSection(
                    icono: Icons.palette,
                    titulo: 'Apariencia',
                    subtitulo: 'Preferencias visuales de la aplicación.',
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _temaOscuro,
                        title: const Text('Tema oscuro'),
                        subtitle: const Text('Guardado como preferencia local'),
                        secondary: const Icon(Icons.dark_mode),
                        onChanged: (value) => setState(() {
                          _temaOscuro = value;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ConfigSection(
                    icono: Icons.storage,
                    titulo: 'Datos y respaldo',
                    subtitulo:
                        'Control básico para proteger la información local.',
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _backupAutomatico,
                        title: const Text('Backup automático'),
                        subtitle: const Text(
                          'Preferencia guardada para fase futura',
                        ),
                        secondary: const Icon(Icons.backup),
                        onChanged: (value) => setState(() {
                          _backupAutomatico = value;
                        }),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.save_alt),
                        title: const Text('Registrar backup local'),
                        subtitle: Text(
                          _ultimoBackup == null
                              ? 'Aún no hay backup registrado'
                              : 'Último backup: ${_dateTime(DateTime.parse(_ultimoBackup!))}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _registrarBackupManual,
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.restore),
                        title: const Text('Restaurar datos'),
                        subtitle: const Text('Preparado para implementar'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _mostrarRestaurarPendiente,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _guardando ? null : _guardar,
                      icon: _guardando
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: const Text('Guardar configuración'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _EstadoSistemaCard extends StatelessWidget {
  const _EstadoSistemaCard({required this.sqliteOk});

  final bool sqliteOk;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: sqliteOk
                  ? Colors.green.shade50
                  : Colors.red.shade50,
              child: Icon(
                sqliteOk ? Icons.check_circle : Icons.error,
                color: sqliteOk ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Estado del sistema',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    sqliteOk
                        ? 'Base de datos local conectada'
                        : 'No se pudo conectar SQLite',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfigSection extends StatelessWidget {
  const _ConfigSection({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.children,
  });

  final IconData icono;
  final String titulo;
  final String subtitulo;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icono, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(subtitulo),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

String _dateTime(DateTime value) {
  return '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.year} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

List<double> _parseIntereses(String value) {
  return value
      .split(',')
      .map((item) => double.tryParse(item.trim()))
      .whereType<double>()
      .where((item) => item >= 0)
      .toList();
}
