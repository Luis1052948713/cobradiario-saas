import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/navigation/app_route_observer.dart';
import '../../../core/permissions/permission_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../data/reportes_repository.dart';
import '../services/reporte_export_service.dart';

enum _PeriodoReporte { diario, semanal, mensual }

class ReportesPage extends StatefulWidget {
  const ReportesPage({super.key});

  @override
  State<ReportesPage> createState() => _ReportesPageState();
}

class _ReportesPageState extends State<ReportesPage> with RouteAware {
  final _repository = const ReportesRepository();
  final _exportService = const ReporteExportService();
  final _permissionService = const PermissionService();

  _PeriodoReporte _periodo = _PeriodoReporte.diario;
  late Future<ReporteCobros> _reporteFuture;
  String? _exportando;

  @override
  void initState() {
    super.initState();
    _reporteFuture = _cargarReporte();
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
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    _recargar();
  }

  Future<ReporteCobros> _cargarReporte() {
    final rango = _rangoActual();

    return _repository.reportePorRango(
      desde: rango.desde,
      hasta: rango.hasta,
      cobradorId: _permissionService.cobradorScope(),
    );
  }

  Future<void> _recargar() async {
    setState(() => _reporteFuture = _cargarReporte());
    await _reporteFuture;
  }

  void _cambiarPeriodo(_PeriodoReporte periodo) {
    setState(() {
      _periodo = periodo;
      _reporteFuture = _cargarReporte();
    });
  }

  Future<void> _exportarPdf(ReporteCobros reporte) async {
    await _exportar(
      tipo: 'PDF',
      action: () => _exportService.exportarPdf(
        reporte: reporte,
        incluyeGlobal: _permissionService.puedeVerReportesGlobales(),
      ),
    );
  }

  Future<void> _exportarExcel(ReporteCobros reporte) async {
    await _exportar(
      tipo: 'Excel',
      action: () => _exportService.exportarExcel(
        reporte: reporte,
        incluyeGlobal: _permissionService.puedeVerReportesGlobales(),
      ),
    );
  }

  Future<void> _exportar({
    required String tipo,
    required Future<File> Function() action,
  }) async {
    setState(() => _exportando = tipo);

    try {
      final file = await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$tipo exportado: ${file.path}'),
          action: SnackBarAction(
            label: 'Copiar',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: file.path));
            },
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo exportar $tipo: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _exportando = null);
      }
    }
  }

  _RangoReporte _rangoActual() {
    final now = DateTime.now();
    final hasta = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    final desde = switch (_periodo) {
      _PeriodoReporte.diario => DateTime(now.year, now.month, now.day),
      _PeriodoReporte.semanal => DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 6)),
      _PeriodoReporte.mensual => DateTime(now.year, now.month),
    };

    return _RangoReporte(desde: desde, hasta: hasta);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportes'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _recargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _recargar,
        child: FutureBuilder<ReporteCobros>(
          future: _reporteFuture,
          builder: (context, snapshot) {
            final reporte = snapshot.data;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _PeriodoSelector(
                  periodo: _periodo,
                  onChanged: _cambiarPeriodo,
                ),
                const SizedBox(height: 12),
                if (reporte != null) _RangoCard(reporte: reporte),
                const SizedBox(height: 16),
                if (snapshot.connectionState == ConnectionState.waiting &&
                    reporte == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snapshot.hasError)
                  _ErrorReporte(onRetry: _recargar)
                else if (reporte != null)
                  _ReporteContenido(
                    reporte: reporte,
                    puedeVerGlobal: _permissionService.puedeVerReportesGlobales(),
                    puedeExportar: _permissionService.puedeExportarReportes(),
                    exportando: _exportando,
                    onExportPdf: () => _exportarPdf(reporte),
                    onExportExcel: () => _exportarExcel(reporte),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PeriodoSelector extends StatelessWidget {
  const _PeriodoSelector({
    required this.periodo,
    required this.onChanged,
  });

  final _PeriodoReporte periodo;
  final ValueChanged<_PeriodoReporte> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<_PeriodoReporte>(
        selected: {periodo},
        onSelectionChanged: (value) => onChanged(value.first),
        segments: const [
          ButtonSegment(
            value: _PeriodoReporte.diario,
            label: Text('Hoy'),
            icon: Icon(Icons.today),
          ),
          ButtonSegment(
            value: _PeriodoReporte.semanal,
            label: Text('Semana'),
            icon: Icon(Icons.date_range),
          ),
          ButtonSegment(
            value: _PeriodoReporte.mensual,
            label: Text('Mes'),
            icon: Icon(Icons.calendar_month),
          ),
        ],
      ),
    );
  }
}

class _RangoCard extends StatelessWidget {
  const _RangoCard({required this.reporte});

  final ReporteCobros reporte;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.event),
        title: const Text('Período consultado'),
        subtitle: Text('${_date(reporte.desde)} - ${_date(reporte.hasta)}'),
        trailing: const Icon(Icons.sync),
      ),
    );
  }
}

class _ReporteContenido extends StatelessWidget {
  const _ReporteContenido({
    required this.reporte,
    required this.puedeVerGlobal,
    required this.puedeExportar,
    required this.exportando,
    required this.onExportPdf,
    required this.onExportExcel,
  });

  final ReporteCobros reporte;
  final bool puedeVerGlobal;
  final bool puedeExportar;
  final String? exportando;
  final VoidCallback onExportPdf;
  final VoidCallback onExportExcel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SeccionTitulo(titulo: 'Resumen de cobros'),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 4 : 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.35,
          children: [
            _ReporteMetricCard(
              icono: Icons.payments,
              titulo: 'Cobrado',
              valor: _money(reporte.totalCobrado),
              color: Colors.green,
            ),
            _ReporteMetricCard(
              icono: Icons.receipt_long,
              titulo: 'Pagos',
              valor: '${reporte.cantidadPagos}',
              color: Colors.blue,
            ),
            _ReporteMetricCard(
              icono: Icons.directions_walk,
              titulo: 'Visitas',
              valor: '${reporte.cantidadVisitas}',
              color: Colors.purple,
            ),
            _ReporteMetricCard(
              icono: Icons.trending_up,
              titulo: 'Promedio',
              valor: _money(reporte.promedioPorPago),
              color: Colors.orange,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SeccionTitulo(titulo: 'Estado de cartera'),
        _ReporteWideCard(
          icono: Icons.account_balance_wallet,
          titulo: 'Saldo pendiente',
          valor: _money(reporte.saldoPendiente),
          subtitulo: 'Dinero que falta por cobrar en préstamos activos.',
          color: Colors.orange,
        ),
        if (puedeVerGlobal) ...[
          _ReporteWideCard(
            icono: Icons.attach_money,
            titulo: 'Total prestado',
            valor: _money(reporte.totalPrestado),
            subtitulo: 'Capital entregado registrado en el sistema.',
            color: Colors.blue,
          ),
          _ReporteWideCard(
            icono: Icons.savings,
            titulo: 'Ganancia estimada',
            valor: _money(reporte.gananciaEstimada),
            subtitulo: 'Intereses calculados sobre los préstamos registrados.',
            color: Colors.green,
          ),
        ],
        const SizedBox(height: 18),
        _SeccionTitulo(titulo: 'Alertas'),
        Row(
          children: [
            Expanded(
              child: _ReporteMetricCard(
                icono: Icons.warning,
                titulo: 'Atrasados',
                valor: '${reporte.prestamosAtrasados}',
                color: Colors.red,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ReporteMetricCard(
                icono: Icons.people,
                titulo: 'Morosos',
                valor: '${reporte.clientesMorosos}',
                color: Colors.deepOrange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _SeccionTitulo(titulo: 'Préstamos'),
        Row(
          children: [
            Expanded(
              child: _EstadoPrestamoItem(
                label: 'Activos',
                value: reporte.prestamosActivos,
                color: Colors.orange,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _EstadoPrestamoItem(
                label: 'Pagados',
                value: reporte.prestamosPagados,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _EstadoPrestamoItem(
                label: 'Atrasados',
                value: reporte.prestamosAtrasados,
                color: Colors.red,
              ),
            ),
          ],
        ),
        if (puedeExportar) ...[
          const SizedBox(height: 18),
          _SeccionTitulo(titulo: 'Exportar'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf),
                  title: const Text('Exportar PDF'),
                  subtitle: const Text('Genera un archivo PDF del reporte actual'),
                  trailing: exportando == 'PDF'
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: exportando == null ? onExportPdf : null,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.table_chart),
                  title: const Text('Exportar Excel'),
                  subtitle: const Text('Genera un archivo XLSX editable'),
                  trailing: exportando == 'Excel'
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: exportando == null ? onExportExcel : null,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SeccionTitulo extends StatelessWidget {
  const _SeccionTitulo({required this.titulo});

  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        titulo,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

class _ReporteMetricCard extends StatelessWidget {
  const _ReporteMetricCard({
    required this.icono,
    required this.titulo,
    required this.valor,
    required this.color,
  });

  final IconData icono;
  final String titulo;
  final String valor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icono, color: color),
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

class _ReporteWideCard extends StatelessWidget {
  const _ReporteWideCard({
    required this.icono,
    required this.titulo,
    required this.valor,
    required this.subtitulo,
    required this.color,
  });

  final IconData icono;
  final String titulo;
  final String valor;
  final String subtitulo;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icono, color: color),
        title: Text(titulo),
        subtitle: Text(subtitulo),
        trailing: Text(
          valor,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _EstadoPrestamoItem extends StatelessWidget {
  const _EstadoPrestamoItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                color: color,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _ErrorReporte extends StatelessWidget {
  const _ErrorReporte({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
          const SizedBox(height: 12),
          const Text(
            'No se pudo cargar el reporte',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

class _RangoReporte {
  const _RangoReporte({required this.desde, required this.hasta});

  final DateTime desde;
  final DateTime hasta;
}

String _money(double value) => CurrencyFormatter.pesos(value);

String _date(DateTime value) {
  return '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.year}';
}
