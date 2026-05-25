import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../caja/data/control_financiero_repository.dart';
import '../../cobros/data/cobro_repository.dart';
import '../../prestamos/data/prestamo_repository.dart';
import '../../rutas/data/ruta_repository.dart';
import '../../usuarios/data/usuario_repository.dart';
import '../../usuarios/models/usuario_model.dart';

class CobradoresPage extends StatefulWidget {
  const CobradoresPage({super.key});

  @override
  State<CobradoresPage> createState() => _CobradoresPageState();
}

class _CobradoresPageState extends State<CobradoresPage> {
  final _usuarioRepository = const UsuarioRepository();
  final _cajaRepository = const ControlFinancieroRepository();
  final _rutaRepository = const RutaRepository();

  bool _cargando = true;
  List<UsuarioModel> _cobradores = [];
  Map<int, CajaResumenDiario> _resumenes = {};
  Map<int, int> _rutasAsignadas = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cobradores'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _CobradoresResumen(cobradores: _cobradores),
                  const SizedBox(height: 12),
                  for (final cobrador in _cobradores)
                    _CobradorCard(
                      cobrador: cobrador,
                      resumen: _resumenes[cobrador.id],
                      rutasAsignadas: _rutasAsignadas[cobrador.id] ?? 0,
                      onTap: () => _abrirDetalle(cobrador),
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
  const _CobradoresResumen({required this.cobradores});

  final List<UsuarioModel> cobradores;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.badge)),
        title: const Text('Cobradores activos'),
        subtitle: const Text('Estado operativo, caja y rutas asignadas'),
        trailing: Text(
          '${cobradores.length}',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _estadoColor(estado).withValues(alpha: 0.12),
          child: Icon(Icons.person_pin, color: _estadoColor(estado)),
        ),
        title: Text(cobrador.nombre),
        subtitle: Text(
          'Caja: ${_estadoLabel(estado)} - Rutas: $rutasAsignadas',
        ),
        trailing: Text(
          CurrencyFormatter.pesos(resumen?.saldoDisponible ?? 0),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        onTap: onTap,
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
