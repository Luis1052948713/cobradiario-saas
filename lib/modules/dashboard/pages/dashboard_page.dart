import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/navigation/app_route_observer.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/services/offline_sync_service.dart';
import '../../../core/session/session_manager.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../auditoria/data/auditoria_repository.dart';
import '../../auditoria/pages/auditoria_page.dart';
import '../../auth/pages/login_page.dart';
import '../../auth/services/auth_service.dart';
import '../../caja/pages/caja_page.dart';
import '../../caja/pages/gastos_page.dart';
import '../../clientes/pages/clientes_page.dart';
import '../../cobros/pages/cobros_page.dart';
import '../../cobradores/pages/cobradores_page.dart';
import '../../configuracion/pages/configuracion_page.dart';
import '../../notificaciones/data/notificacion_repository.dart';
import '../../notificaciones/pages/notificaciones_page.dart';
import '../../prestamos/pages/prestamos_page.dart';
import '../../reportes/pages/reportes_page.dart';
import '../../rutas/pages/rutas_page.dart';
import '../../suscripcion/data/suscripcion_repository.dart';
import '../../suscripcion/pages/suscripcion_page.dart';
import '../../usuarios/pages/usuarios_page.dart';
import '../data/dashboard_repository.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with RouteAware {
  final _dashboardRepository = const DashboardRepository();
  final _notificacionRepository = const NotificacionRepository();
  final _auditoriaRepository = const AuditoriaRepository();
  final _suscripcionRepository = const SuscripcionRepository();
  final _permissionService = const PermissionService();
  final _authService = const AuthService();

  late Future<DashboardResumen> _resumenFuture;
  late Future<int> _notificacionesPendientesFuture;
  late Future<SuscripcionResumen> _suscripcionFuture;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _resumenFuture = _cargarResumen();
    _notificacionesPendientesFuture = _notificacionRepository.pendientesCount();
    _suscripcionFuture = _suscripcionRepository.obtenerResumen();
    _sincronizarPendientes();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        _sincronizarPendientes();
        unawaited(_recargarResumen(silent: true));
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _recargarResumen();
  }

  Future<DashboardResumen> _cargarResumen() {
    return _dashboardRepository.obtenerResumen(
      cobradorId: _permissionService.cobradorScope(),
    );
  }

  Future<void> _recargarResumen({bool silent = false}) async {
    if (!mounted) return;
    setState(() {
      _resumenFuture = _cargarResumen();
      _notificacionesPendientesFuture = _notificacionRepository
          .pendientesCount();
      _suscripcionFuture = _suscripcionRepository.obtenerResumen();
    });
    if (!silent) await _resumenFuture;
  }

  void _sincronizarPendientes() {
    unawaited(
      OfflineSyncService.instance
          .sincronizarPendientes()
          .catchError((Object error, StackTrace stackTrace) {}),
    );
  }

  Future<void> _abrir(String modulo, Widget page) async {
    try {
      final esSuperadmin = _permissionService.esSuperadmin;
      final licenciaActiva =
          esSuperadmin || await _suscripcionRepository.licenciaActiva();
      final modulosPermitidos = {
        'suscripcion',
        'configuracion',
        'notificaciones',
        'auditoria',
      };
      if (!licenciaActiva && !modulosPermitidos.contains(modulo)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La suscripcion esta vencida. Activa la licencia.'),
          ),
        );
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SuscripcionPage()),
        );
        await _recargarResumen();
        return;
      }

      await _auditoriaRepository.registrar(
        accion: 'navegar',
        modulo: modulo,
        descripcion: 'Apertura de modulo $modulo desde panel principal',
      );

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => page),
      );
      await _recargarResumen();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir $modulo: $error')),
      );
    }
  }

  Future<void> _cerrarSesion() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (_) => false,
    );
  }

  List<_MenuSection> _menuSections({
    required DashboardResumen? resumen,
    required int alertasPendientes,
    required SuscripcionResumen? suscripcion,
  }) {
    final esSuperadmin = _permissionService.esSuperadmin;
    final esAdmin = _permissionService.esAdministrador;
    final licenciaBloqueada = suscripcion != null && !suscripcion.activa;

    if (esSuperadmin) {
      return [
        _MenuSection(
          titulo: 'Panel comercial',
          items: [
            _MenuItem(
              icono: Icons.workspace_premium,
              titulo: 'Suscripcion',
              subtitulo: 'Planes, pagos, vencimientos y activaciones',
              color: Colors.deepPurple,
              indicador: suscripcion == null
                  ? '...'
                  : suscripcion.activa
                  ? '${suscripcion.diasRestantes}d'
                  : 'Vencida',
              detalle: 'Licencia',
              submodulos: const ['Estado', 'Activar', 'Eventos'],
              onTap: () => _abrir('suscripcion', const SuscripcionPage()),
            ),
            _MenuItem(
              icono: Icons.settings,
              titulo: 'Configuracion',
              subtitulo: 'Pasarela, API de licencias y datos base',
              color: Colors.blueGrey,
              indicador: 'Sistema',
              detalle: 'SaaS',
              submodulos: const ['Pasarela', 'Licencia', 'Empresa'],
              onTap: () => _abrir('configuracion', const ConfiguracionPage()),
            ),
            _MenuItem(
              icono: Icons.manage_search,
              titulo: 'Auditoria',
              subtitulo: 'Actividad comercial y eventos de licencia',
              color: Colors.cyan,
              indicador: 'Log',
              detalle: 'Control',
              submodulos: const ['Usuarios', 'Licencia', 'Pagos'],
              onTap: () => _abrir('auditoria', const AuditoriaPage()),
            ),
          ],
        ),
      ];
    }

    if (licenciaBloqueada) {
      return [
        _MenuSection(
          titulo: 'Licencia requerida',
          items: [
            _MenuItem(
              icono: Icons.workspace_premium,
              titulo: 'Suscripcion',
              subtitulo: esAdmin
                  ? 'Registra pago y reactiva el sistema'
                  : 'Contacta al administrador para renovar',
              color: Colors.red,
              indicador: 'Vencida',
              detalle: 'Bloqueado',
              submodulos: const ['Estado', 'Pago', 'Licencia'],
              onTap: () => _abrir('suscripcion', const SuscripcionPage()),
            ),
            if (esAdmin)
              _MenuItem(
                icono: Icons.settings,
                titulo: 'Configuracion',
                subtitulo: 'Parametros y datos de empresa',
                color: Colors.grey,
                indicador: 'Admin',
                detalle: 'Sistema',
                submodulos: const ['Empresa', 'Backup', 'Parametros'],
                onTap: () => _abrir('configuracion', const ConfiguracionPage()),
              ),
          ],
        ),
      ];
    }

    if (!esAdmin) {
      return [
        _MenuSection(
          titulo: 'Menu operativo',
          items: [
            _MenuItem(
              icono: Icons.route,
              titulo: 'Rutas',
              subtitulo: 'Clientes asignados y cobros en ruta',
              color: Colors.deepOrange,
              indicador: '${resumen?.cobrosPendientes ?? 0}',
              detalle: 'Pendientes',
              submodulos: const ['Activas', 'Clientes', 'Cobrar'],
              onTap: () => _abrir('rutas', const RutasPage()),
            ),
            _MenuItem(
              icono: Icons.payments,
              titulo: 'Cobros',
              subtitulo: 'Pagos diarios e historial',
              color: Colors.green,
              indicador: _money(resumen?.totalCobradoHoy ?? 0),
              detalle: 'Hoy',
              submodulos: const ['Registrar', 'Pendientes', 'Historial'],
              onTap: () => _abrir('cobros', const CobrosPage()),
            ),
            _MenuItem(
              icono: Icons.attach_money,
              titulo: 'Prestamos',
              subtitulo: 'Crear y consultar cartera asignada',
              color: Colors.orange,
              indicador: '${resumen?.prestamosActivos ?? 0}',
              detalle: 'Activos',
              submodulos: const ['Crear', 'Activos', 'Historial'],
              onTap: () => _abrir('prestamos', const PrestamosPage()),
            ),
            _MenuItem(
              icono: Icons.people,
              titulo: 'Clientes',
              subtitulo: 'Ver tus clientes asignados',
              color: Colors.blue,
              indicador: '${resumen?.clientesActivos ?? 0}',
              detalle: 'Activos',
              submodulos: const ['Listado', 'Mora', 'Prestamos'],
              onTap: () => _abrir('clientes', const ClientesPage()),
            ),
            _MenuItem(
              icono: Icons.receipt_long,
              titulo: 'Gastos',
              subtitulo: 'Gastos operativos registrados',
              color: Colors.red,
              indicador: 'Ver',
              detalle: 'Historial',
              submodulos: const ['Transporte', 'Gasolina', 'Otros'],
              onTap: () => _abrir('gastos', const GastosPage()),
            ),
            _MenuItem(
              icono: Icons.account_balance_wallet,
              titulo: 'Caja',
              subtitulo: 'Saldo, apertura y cierre diario',
              color: Colors.teal,
              indicador: '${resumen?.cajasAbiertas ?? 0}',
              detalle: 'Abiertas',
              submodulos: const ['Estado', 'Cierre', 'Movimientos'],
              onTap: () => _abrir('caja', const CajaPage()),
            ),
            _MenuItem(
              icono: Icons.notifications,
              titulo: 'Notificaciones',
              subtitulo: 'Alertas y avisos operativos',
              color: Colors.red,
              indicador: '$alertasPendientes',
              detalle: 'Pendientes',
              submodulos: const ['Pendientes', 'Criticas', 'Historial'],
              onTap: () => _abrir('notificaciones', const NotificacionesPage()),
            ),
            _MenuItem(
              icono: Icons.person,
              titulo: 'Perfil',
              subtitulo: 'Usuario y movimientos propios',
              color: Colors.purple,
              indicador: 'Yo',
              detalle: 'Cuenta',
              submodulos: const ['Actividad', 'Rol', 'Sesion'],
              onTap: () => _abrir('auditoria', const AuditoriaPage()),
            ),
          ],
        ),
      ];
    }

    return [
      _MenuSection(
        titulo: 'Administracion central',
        items: [
          _MenuItem(
            icono: Icons.badge,
            titulo: 'Cobradores',
            subtitulo: 'Estado operativo y rendimiento diario',
            color: Colors.purple,
            indicador: '${resumen?.cobradoresActivos ?? 0}',
            detalle: 'Activos',
            submodulos: const ['Listado', 'Caja', 'Rutas'],
            onTap: () => _abrir('cobradores', const CobradoresPage()),
          ),
          _MenuItem(
            icono: Icons.people_alt,
            titulo: 'Usuarios',
            subtitulo: 'Crear administradores y cobradores',
            color: Colors.deepPurple,
            indicador: '${resumen?.cobradoresActivos ?? 0}',
            detalle: 'Cobradores',
            submodulos: const ['Crear', 'Roles', 'Estados'],
            onTap: () => _abrir('usuarios', const UsuariosPage()),
          ),
          _MenuItem(
            icono: Icons.people,
            titulo: 'Clientes',
            subtitulo: 'Estado financiero, mora e historial',
            color: Colors.blue,
            indicador: '${resumen?.clientesActivos ?? 0}',
            detalle: 'Activos',
            submodulos: const ['Listado', 'Mora', 'Prestamos'],
            onTap: () => _abrir('clientes', const ClientesPage()),
          ),
          _MenuItem(
            icono: Icons.attach_money,
            titulo: 'Prestamos',
            subtitulo: 'Crear, activos, vencidos e historial',
            color: Colors.orange,
            indicador: '${resumen?.prestamosHoy ?? 0}',
            detalle: 'Hoy',
            submodulos: const ['Crear', 'Activos', 'Vencidos'],
            onTap: () => _abrir('prestamos', const PrestamosPage()),
          ),
          _MenuItem(
            icono: Icons.payments,
            titulo: 'Cobros',
            subtitulo: 'Registrar pagos y revisar pendientes',
            color: Colors.green,
            indicador: _money(resumen?.totalCobradoHoy ?? 0),
            detalle: 'Hoy',
            submodulos: const ['Registrar', 'Diarios', 'Historial'],
            onTap: () => _abrir('cobros', const CobrosPage()),
          ),
          _MenuItem(
            icono: Icons.route,
            titulo: 'Rutas',
            subtitulo: 'Rutas activas, visitas y cobros',
            color: Colors.deepOrange,
            indicador: '${resumen?.cobrosPendientes ?? 0}',
            detalle: 'Pendientes',
            submodulos: const ['Activas', 'Clientes', 'Recorridos'],
            onTap: () => _abrir('rutas', const RutasPage()),
          ),
          _MenuItem(
            icono: Icons.account_balance_wallet,
            titulo: 'Caja',
            subtitulo: 'Aperturas, cierres y diferencias',
            color: Colors.teal,
            indicador: _money(resumen?.capitalDisponible ?? 0),
            detalle: 'Disponible',
            submodulos: const ['Capital', 'Cierre', 'Entregas'],
            onTap: () => _abrir('caja', const CajaPage()),
          ),
          _MenuItem(
            icono: Icons.receipt_long,
            titulo: 'Gastos',
            subtitulo: 'Gastos operativos por cobrador',
            color: Colors.red,
            indicador: 'Ver',
            detalle: 'Historial',
            submodulos: const ['Diarios', 'Tipos', 'Auditoria'],
            onTap: () => _abrir('gastos', const GastosPage()),
          ),
          _MenuItem(
            icono: Icons.notifications,
            titulo: 'Notificaciones',
            subtitulo: 'Pendientes, criticas e historial',
            color: Colors.red,
            indicador: '$alertasPendientes',
            detalle: 'Pendientes',
            submodulos: const ['Pendientes', 'Criticas', 'Historial'],
            onTap: () => _abrir('notificaciones', const NotificacionesPage()),
          ),
          _MenuItem(
            icono: Icons.bar_chart,
            titulo: 'Reportes',
            subtitulo: 'Diarios, financieros y cobradores',
            color: Colors.indigo,
            indicador: 'PDF',
            detalle: 'Exportar',
            submodulos: const ['Diario', 'Mensual', 'Mora'],
            onTap: () => _abrir('reportes', const ReportesPage()),
          ),
          _MenuItem(
            icono: Icons.manage_search,
            titulo: 'Auditoria',
            subtitulo: 'Actividad de usuarios y sistema',
            color: Colors.cyan,
            indicador: 'Log',
            detalle: 'Sistema',
            submodulos: const ['Usuarios', 'Caja', 'Movimientos'],
            onTap: () => _abrir('auditoria', const AuditoriaPage()),
          ),
          _MenuItem(
            icono: Icons.settings,
            titulo: 'Configuracion',
            subtitulo: 'Interes, moneda, permisos y empresa',
            color: Colors.grey,
            indicador: 'Admin',
            detalle: 'Sistema',
            submodulos: const ['Parametros', 'Usuarios', 'Backup'],
            onTap: () => _abrir('configuracion', const ConfiguracionPage()),
          ),
          _MenuItem(
            icono: Icons.workspace_premium,
            titulo: 'Suscripcion',
            subtitulo: 'Plan, vencimiento y activaciones',
            color: Colors.deepPurple,
            indicador: suscripcion == null
                ? '...'
                : suscripcion.activa
                ? '${suscripcion.diasRestantes}d'
                : 'Vencida',
            detalle: 'Licencia',
            submodulos: const ['Plan', 'Pagos', 'Eventos'],
            onTap: () => _abrir('suscripcion', const SuscripcionPage()),
          ),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final usuario = SessionManager.instance.usuarioActual;
    final drawerSections = _menuSections(
      resumen: null,
      alertasPendientes: 0,
      suscripcion: null,
    );

    return Scaffold(
      drawer: _DashboardDrawer(
        usuarioNombre: usuario?.nombre ?? 'usuario',
        rol: usuario?.rol ?? 'sin sesion',
        sections: drawerSections,
        onLogout: _cerrarSesion,
      ),
      appBar: AppBar(
        title: const Text('Menu principal'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () => _recargarResumen(),
            icon: const Icon(Icons.refresh),
          ),
          FutureBuilder<int>(
            future: _notificacionesPendientesFuture,
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return _NotificationAction(
                count: count,
                onPressed: () =>
                    _abrir('notificaciones', const NotificacionesPage()),
              );
            },
          ),
          IconButton(
            tooltip: 'Cerrar sesion',
            onPressed: () {
              _cerrarSesion();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _recargarResumen(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Hola, ${usuario?.nombre ?? 'usuario'}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text('Rol: ${usuario?.rol ?? 'sin sesion'}'),
            const SizedBox(height: 16),
            FutureBuilder<SuscripcionResumen>(
              future: _suscripcionFuture,
              builder: (context, snapshot) {
                final resumen = snapshot.data;
                if (resumen == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SuscripcionBanner(
                    resumen: resumen,
                    onTap: () => _abrir('suscripcion', const SuscripcionPage()),
                  ),
                );
              },
            ),
            FutureBuilder<DashboardResumen>(
              future: _resumenFuture,
              builder: (context, resumenSnapshot) {
                return FutureBuilder<SuscripcionResumen>(
                  future: _suscripcionFuture,
                  builder: (context, suscripcionSnapshot) {
                    return FutureBuilder<int>(
                      future: _notificacionesPendientesFuture,
                      builder: (context, alertasSnapshot) {
                        final sections = _menuSections(
                          resumen: resumenSnapshot.data,
                          alertasPendientes: alertasSnapshot.data ?? 0,
                          suscripcion: suscripcionSnapshot.data,
                        );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _MenuHeader(
                              total: sections.fold<int>(0, (total, section) {
                                return total + section.items.length;
                              }),
                            ),
                            const SizedBox(height: 12),
                            for (final section in sections)
                              _MenuSectionView(section: section),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _money(double value) {
    return CurrencyFormatter.pesos(value);
  }
}

class _MenuHeader extends StatelessWidget {
  const _MenuHeader({required this.total});

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
                'Menu principal',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text('$total opciones disponibles para tu rol'),
            ],
          ),
        ),
        const Icon(Icons.apps),
      ],
    );
  }
}

class _NotificationAction extends StatelessWidget {
  const _NotificationAction({required this.count, required this.onPressed});

  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          tooltip: 'Notificaciones',
          onPressed: onPressed,
          icon: const Icon(Icons.notifications),
        ),
        if (count > 0)
          Positioned(
            right: 6,
            top: 7,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SuscripcionBanner extends StatelessWidget {
  const _SuscripcionBanner({required this.resumen, required this.onTap});

  final SuscripcionResumen resumen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final visible = !resumen.activa || resumen.diasRestantes <= 5;
    if (!visible) return const SizedBox.shrink();
    final color = resumen.activa ? Colors.orange : Colors.red;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(
                  resumen.activa ? Icons.schedule : Icons.block,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resumen.activa
                          ? 'Suscripcion por vencer'
                          : 'Suscripcion vencida',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      resumen.activa
                          ? 'Quedan ${resumen.diasRestantes} dias de licencia.'
                          : 'Activa un pago para desbloquear los modulos.',
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuSection {
  const _MenuSection({required this.titulo, required this.items});

  final String titulo;
  final List<_MenuItem> items;
}

class _MenuItem {
  const _MenuItem({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.color,
    required this.indicador,
    required this.detalle,
    required this.submodulos,
    required this.onTap,
  });

  final IconData icono;
  final String titulo;
  final String subtitulo;
  final Color color;
  final String indicador;
  final String detalle;
  final List<String> submodulos;
  final VoidCallback onTap;
}

class _MenuSectionView extends StatelessWidget {
  const _MenuSectionView({required this.section});

  final _MenuSection section;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.titulo,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 840
                  ? 3
                  : constraints.maxWidth > 520
                  ? 2
                  : 1;
              final spacing = 10.0;
              final width =
                  (constraints.maxWidth - (spacing * (columns - 1))) / columns;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final item in section.items)
                    SizedBox(
                      width: width,
                      child: _MenuButton(item: item),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.item});

  final _MenuItem item;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: item.color.withValues(alpha: 0.12),
                    child: Icon(item.icono, color: item.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.titulo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.subtitulo,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        item.indicador,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: item.color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        item.detalle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final submodulo in item.submodulos)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: item.color.withValues(alpha: 0.25),
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          submodulo,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
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

class _DashboardDrawer extends StatelessWidget {
  const _DashboardDrawer({
    required this.usuarioNombre,
    required this.rol,
    required this.sections,
    required this.onLogout,
  });

  final String usuarioNombre;
  final String rol;
  final List<_MenuSection> sections;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.account_balance_wallet),
              ),
              title: Text(
                usuarioNombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(rol),
            ),
            const Divider(height: 1),
            for (final section in sections) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Text(
                  section.titulo,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              for (final item in section.items)
                ListTile(
                  leading: Icon(item.icono, color: item.color),
                  title: Text(item.titulo),
                  onTap: () {
                    Navigator.pop(context);
                    item.onTap();
                  },
                ),
            ],
            const Divider(height: 24),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Cerrar sesion'),
              onTap: () {
                Navigator.pop(context);
                onLogout();
              },
            ),
          ],
        ),
      ),
    );
  }
}
