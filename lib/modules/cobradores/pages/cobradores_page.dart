import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../caja/data/control_financiero_repository.dart';
import '../../cobros/data/cobro_repository.dart';
import '../../prestamos/data/prestamo_repository.dart';
import '../../rutas/data/ruta_repository.dart';
import '../../usuarios/data/usuario_repository.dart';
import '../../usuarios/models/usuario_model.dart';
import '../../usuarios/pages/usuarios_page.dart';

enum _FiltroCobradores { todos, conRuta, sinRuta, cajaAbierta, saldoBajo }

class CobradoresPage extends StatefulWidget {
  const CobradoresPage({super.key});

  @override
  State<CobradoresPage> createState() => _CobradoresPageState();
}

class _CobradoresPageState extends State<CobradoresPage> {
  final _usuarioRepository = const UsuarioRepository();
  final _cajaRepository = const ControlFinancieroRepository();
  final _rutaRepository = const RutaRepository();
  final _buscarController = TextEditingController();

  bool _cargando = true;
  String? _error;
  List<UsuarioModel> _cobradores = [];
  Map<int, CajaResumenDiario> _resumenes = {};
  Map<int, int> _rutasAsignadas = {};
  _FiltroCobradores _filtro = _FiltroCobradores.todos;

  @override
  void initState() {
    super.initState();
    _cargar();
    _buscarController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _buscarController.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final usuarios = await _usuarioRepository.listarCobradoresActivos();
      final resumenes = <int, CajaResumenDiario>{};
      final rutas = <int, int>{};
      for (final cobrador in usuarios) {
        final id = cobrador.id;
        if (id == null) continue;
        resumenes[id] = await _cajaRepository.resumenDiario(id);
        rutas[id] = (await _rutaRepository.listar(
          cobradorId: id,
        )).where((ruta) => ruta.estaActiva).length;
      }
      if (!mounted) return;
      setState(() {
        _cobradores = usuarios;
        _resumenes = resumenes;
        _rutasAsignadas = rutas;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _cargando = false;
      });
    }
  }

  Future<void> _abrirDetalle(UsuarioModel cobrador) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CobradorDetallePage(cobrador: cobrador),
      ),
    );
    await _cargar();
  }

  List<UsuarioModel> get _cobradoresFiltrados {
    final query = _buscarController.text.trim().toLowerCase();
    return _cobradores.where((cobrador) {
      final id = cobrador.id;
      final resumen = id == null ? null : _resumenes[id];
      final rutas = id == null ? 0 : (_rutasAsignadas[id] ?? 0);
      final coincideBusqueda =
          query.isEmpty ||
          cobrador.nombre.toLowerCase().contains(query) ||
          cobrador.usuario.toLowerCase().contains(query);
      final coincideFiltro = switch (_filtro) {
        _FiltroCobradores.todos => true,
        _FiltroCobradores.conRuta => rutas > 0,
        _FiltroCobradores.sinRuta => rutas == 0,
        _FiltroCobradores.cajaAbierta =>
          resumen?.estadoCaja == CajaEstados.abierta,
        _FiltroCobradores.saldoBajo => (resumen?.saldoDisponible ?? 0) <= 0,
      };
      return coincideBusqueda && coincideFiltro;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cobradores = _cobradoresFiltrados;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cobradores'),
        actions: [
          IconButton(
            tooltip: 'Gestionar usuarios',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const UsuariosPage()),
              );
              await _cargar();
            },
            icon: const Icon(Icons.manage_accounts),
          ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _CobradoresError(error: _error!, onRetry: _cargar)
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _CobradoresResumen(
                    cobradores: _cobradores,
                    resumenes: _resumenes,
                    rutasAsignadas: _rutasAsignadas,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _buscarController,
                    decoration: InputDecoration(
                      labelText: 'Buscar cobrador',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _buscarController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpiar busqueda',
                              onPressed: _buscarController.clear,
                              icon: const Icon(Icons.close),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FiltrosCobradores(
                    filtro: _filtro,
                    onChanged: (value) => setState(() => _filtro = value),
                  ),
                  const SizedBox(height: 16),
                  _SeccionCobradores(
                    visibles: cobradores.length,
                    total: _cobradores.length,
                  ),
                  const SizedBox(height: 8),
                  if (cobradores.isEmpty)
                    const _CobradoresEmpty()
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth > 900
                            ? 2
                            : 1;
                        final spacing = 10.0;
                        final width =
                            (constraints.maxWidth -
                                (spacing * (columns - 1))) /
                            columns;
                        return Wrap(
                          spacing: spacing,
                          runSpacing: spacing,
                          children: [
                            for (final cobrador in cobradores)
                              SizedBox(
                                width: width,
                                child: _CobradorCard(
                                  cobrador: cobrador,
                                  resumen: _resumenes[cobrador.id],
                                  rutasAsignadas:
                                      _rutasAsignadas[cobrador.id] ?? 0,
                                  onTap: () => _abrirDetalle(cobrador),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }
}

class CobradorDetallePage extends StatefulWidget {
  const CobradorDetallePage({super.key, required this.cobrador});

  final UsuarioModel cobrador;

  @override
  State<CobradorDetallePage> createState() => _CobradorDetallePageState();
}

class _CobradorDetallePageState extends State<CobradorDetallePage> {
  final _cajaRepository = const ControlFinancieroRepository();
  final _prestamoRepository = const PrestamoRepository();
  final _cobroRepository = const CobroRepository();
  final _rutaRepository = const RutaRepository();

  bool _cargando = true;
  CajaResumenDiario? _resumen;
  int _prestamos = 0;
  int _cobros = 0;
  int _gastos = 0;
  int _rutas = 0;
  List<Map<String, Object?>> _movimientos = [];
  List<Map<String, Object?>> _cierres = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final id = widget.cobrador.id;
    if (id == null) return;
    setState(() => _cargando = true);
    final resumen = await _cajaRepository.resumenDiario(id);
    final prestamos = await _prestamoRepository.listarPorCobrador(id);
    final cobros = await _cobroRepository.listar(cobradorId: id);
    final gastos = await _cajaRepository.gastos(cobradorId: id);
    final rutas = await _rutaRepository.listar(cobradorId: id);
    final movimientos = await _cajaRepository.movimientos(cobradorId: id);
    final cierres = await _cajaRepository.cierresPorCobrador(id);
    if (!mounted) return;
    setState(() {
      _resumen = resumen;
      _prestamos = prestamos.length;
      _cobros = cobros.length;
      _gastos = gastos.length;
      _rutas = rutas.where((ruta) => ruta.estaActiva).length;
      _movimientos = movimientos;
      _cierres = cierres;
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final resumen = _resumen;
    return Scaffold(
      appBar: AppBar(title: Text(widget.cobrador.nombre)),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  if (resumen != null) _EstadoCajaDetalle(resumen: resumen),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _DetalleMetric('Prestamos', '$_prestamos', Colors.orange),
                      _DetalleMetric('Cobros', '$_cobros', Colors.green),
                      _DetalleMetric('Gastos', '$_gastos', Colors.red),
                      _DetalleMetric('Rutas', '$_rutas', Colors.deepOrange),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _ListaSimple(
                    titulo: 'Cierres de caja',
                    items: _cierres,
                    empty: 'Sin cierres registrados',
                    itemBuilder: (item) =>
                        '${item['fecha']} - ${item['estado']}',
                  ),
                  const SizedBox(height: 18),
                  _ListaSimple(
                    titulo: 'Historial de movimientos',
                    items: _movimientos,
                    empty: 'Sin movimientos registrados',
                    itemBuilder: (item) =>
                        '${item['tipo']} - ${CurrencyFormatter.pesos((item['monto'] as num).toDouble())}',
                  ),
                ],
              ),
            ),
    );
  }
}

class _CobradoresResumen extends StatelessWidget {
  const _CobradoresResumen({
    required this.cobradores,
    required this.resumenes,
    required this.rutasAsignadas,
  });

  final List<UsuarioModel> cobradores;
  final Map<int, CajaResumenDiario> resumenes;
  final Map<int, int> rutasAsignadas;

  @override
  Widget build(BuildContext context) {
    final cajasAbiertas = resumenes.values
        .where((item) => item.estadoCaja == CajaEstados.abierta)
        .length;
    final saldoTotal = resumenes.values.fold<double>(
      0,
      (total, item) => total + item.saldoDisponible,
    );
    final rutasActivas = rutasAsignadas.values.fold<int>(
      0,
      (total, value) => total + value,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 760 ? 4 : 2;
        final spacing = 8.0;
        final width =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: width,
              child: _ResumenItem(
                icono: Icons.badge,
                valor: '${cobradores.length}',
                titulo: 'Activos',
                color: Colors.indigo,
              ),
            ),
            SizedBox(
              width: width,
              child: _ResumenItem(
                icono: Icons.lock_open,
                valor: '$cajasAbiertas',
                titulo: 'Cajas abiertas',
                color: Colors.green,
              ),
            ),
            SizedBox(
              width: width,
              child: _ResumenItem(
                icono: Icons.route,
                valor: '$rutasActivas',
                titulo: 'Rutas',
                color: Colors.deepOrange,
              ),
            ),
            SizedBox(
              width: width,
              child: _ResumenItem(
                icono: Icons.account_balance_wallet,
                valor: CurrencyFormatter.pesos(saldoTotal),
                titulo: 'Saldo total',
                color: Colors.teal,
              ),
            ),
          ],
        );
      },
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _CobradorCard extends StatelessWidget {
  const _CobradorCard({
    required this.cobrador,
    required this.resumen,
    required this.rutasAsignadas,
    required this.onTap,
  });

  final UsuarioModel cobrador;
  final CajaResumenDiario? resumen;
  final int rutasAsignadas;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final estado = resumen?.estadoCaja ?? CajaEstados.cerrada;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: _estadoColor(estado).withValues(alpha: 0.12),
                child: Icon(Icons.person_pin, color: _estadoColor(estado)),
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
                            cobrador.nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        _EstadoChip(estado: estado),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _InfoLine(icono: Icons.person, texto: cobrador.usuario),
                    _InfoLine(
                      icono: Icons.route,
                      texto: '$rutasAsignadas rutas activas',
                    ),
                    _InfoLine(
                      icono: Icons.account_balance_wallet,
                      texto:
                          'Saldo ${CurrencyFormatter.pesos(resumen?.saldoDisponible ?? 0)}',
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MiniMetric(
                          label: 'Recaudado',
                          value: CurrencyFormatter.pesos(
                            resumen?.totalRecaudado ?? 0,
                          ),
                          color: Colors.green,
                        ),
                        _MiniMetric(
                          label: 'Prestado',
                          value: CurrencyFormatter.pesos(
                            resumen?.totalPrestado ?? 0,
                          ),
                          color: Colors.orange,
                        ),
                        _MiniMetric(
                          label: 'Gastos',
                          value: CurrencyFormatter.pesos(resumen?.gastos ?? 0),
                          color: Colors.red,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _FiltrosCobradores extends StatelessWidget {
  const _FiltrosCobradores({required this.filtro, required this.onChanged});

  final _FiltroCobradores filtro;
  final ValueChanged<_FiltroCobradores> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<_FiltroCobradores>(
        selected: {filtro},
        onSelectionChanged: (value) => onChanged(value.first),
        segments: const [
          ButtonSegment(
            value: _FiltroCobradores.todos,
            label: Text('Todos'),
            icon: Icon(Icons.list),
          ),
          ButtonSegment(
            value: _FiltroCobradores.conRuta,
            label: Text('Con ruta'),
            icon: Icon(Icons.route),
          ),
          ButtonSegment(
            value: _FiltroCobradores.sinRuta,
            label: Text('Sin ruta'),
            icon: Icon(Icons.route_outlined),
          ),
          ButtonSegment(
            value: _FiltroCobradores.cajaAbierta,
            label: Text('Caja abierta'),
            icon: Icon(Icons.lock_open),
          ),
          ButtonSegment(
            value: _FiltroCobradores.saldoBajo,
            label: Text('Saldo bajo'),
            icon: Icon(Icons.warning),
          ),
        ],
      ),
    );
  }
}

class _SeccionCobradores extends StatelessWidget {
  const _SeccionCobradores({required this.visibles, required this.total});

  final int visibles;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Listado', style: Theme.of(context).textTheme.titleMedium),
              Text('$visibles de $total cobradores visibles'),
            ],
          ),
        ),
        const Icon(Icons.view_module),
      ],
    );
  }
}

class _EstadoChip extends StatelessWidget {
  const _EstadoChip({required this.estado});

  final String estado;

  @override
  Widget build(BuildContext context) {
    final color = _estadoColor(estado);
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(_estadoLabel(estado)),
      side: BorderSide(color: color.withValues(alpha: 0.35)),
      avatar: Icon(Icons.circle, size: 12, color: color),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
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
      padding: const EdgeInsets.only(bottom: 3),
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

class _CobradoresEmpty extends StatelessWidget {
  const _CobradoresEmpty();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 72),
      child: Column(
        children: [
          Icon(Icons.badge_outlined, size: 56, color: Colors.grey),
          SizedBox(height: 10),
          Text(
            'No hay cobradores para mostrar',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 4),
          Text('Cambia el filtro o crea un cobrador desde usuarios.'),
        ],
      ),
    );
  }
}

class _CobradoresError extends StatelessWidget {
  const _CobradoresError({required this.error, required this.onRetry});

  final String error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.red),
            const SizedBox(height: 12),
            const Text(
              'No se pudo cargar cobradores',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EstadoCajaDetalle extends StatelessWidget {
  const _EstadoCajaDetalle({required this.resumen});

  final CajaResumenDiario resumen;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estado de caja',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _DetalleMetric(
                  _estadoLabel(resumen.estadoCaja),
                  CurrencyFormatter.pesos(resumen.saldoDisponible),
                  _estadoColor(resumen.estadoCaja),
                ),
                _DetalleMetric(
                  'Recaudado',
                  CurrencyFormatter.pesos(resumen.totalRecaudado),
                  Colors.green,
                ),
                _DetalleMetric(
                  'Prestado',
                  CurrencyFormatter.pesos(resumen.totalPrestado),
                  Colors.orange,
                ),
                _DetalleMetric(
                  'Gastos',
                  CurrencyFormatter.pesos(resumen.gastos),
                  Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetalleMetric extends StatelessWidget {
  const _DetalleMetric(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 156,
      child: Card(
        color: color.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.circle, size: 12, color: color),
              const SizedBox(height: 8),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

class _ListaSimple extends StatelessWidget {
  const _ListaSimple({
    required this.titulo,
    required this.items,
    required this.empty,
    required this.itemBuilder,
  });

  final String titulo;
  final List<Map<String, Object?>> items;
  final String empty;
  final String Function(Map<String, Object?> item) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Card(child: ListTile(title: Text(empty)))
        else
          for (final item in items.take(8))
            Card(
              child: ListTile(
                leading: const Icon(Icons.history),
                title: Text(itemBuilder(item)),
              ),
            ),
      ],
    );
  }
}

String _estadoLabel(String estado) {
  return switch (estado) {
    CajaEstados.abierta => 'Abierta',
    CajaEstados.pendienteRevision => 'Pendiente revision',
    CajaEstados.bloqueada => 'Bloqueada',
    _ => 'Cerrada',
  };
}

Color _estadoColor(String estado) {
  return switch (estado) {
    CajaEstados.abierta => Colors.green,
    CajaEstados.pendienteRevision => Colors.orange,
    CajaEstados.bloqueada => Colors.red,
    _ => Colors.grey,
  };
}
