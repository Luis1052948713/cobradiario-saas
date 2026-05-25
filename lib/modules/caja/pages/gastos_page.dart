import 'package:flutter/material.dart';

import '../../../core/permissions/permission_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../data/control_financiero_repository.dart';

class GastosPage extends StatefulWidget {
  const GastosPage({super.key});

  @override
  State<GastosPage> createState() => _GastosPageState();
}

class _GastosPageState extends State<GastosPage> {
  final _repository = const ControlFinancieroRepository();
  final _permissionService = const PermissionService();

  bool _cargando = true;
  List<Map<String, Object?>> _gastos = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final gastos = await _repository.gastos(
      cobradorId: _permissionService.cobradorScope(),
    );
    if (!mounted) return;
    setState(() {
      _gastos = gastos;
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = _gastos.fold<double>(
      0,
      (sum, item) => sum + ((item['valor'] as num?)?.toDouble() ?? 0),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gastos'),
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
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.receipt_long),
                      ),
                      title: const Text('Historial de gastos'),
                      subtitle: const Text(
                        'Transporte, gasolina y gastos operativos',
                      ),
                      trailing: Text(
                        CurrencyFormatter.pesos(total),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_gastos.isEmpty)
                    const Card(
                      child: ListTile(title: Text('Sin gastos registrados')),
                    )
                  else
                    for (final gasto in _gastos)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.receipt),
                          title: Text('${gasto['tipo']}'),
                          subtitle: Text(
                            [
                              gasto['cobrador_nombre'] as String?,
                              gasto['descripcion'] as String?,
                              _date(gasto['fecha_hora'] as String?),
                            ].whereType<String>().join(' - '),
                          ),
                          trailing: Text(
                            CurrencyFormatter.pesos(
                              (gasto['valor'] as num).toDouble(),
                            ),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                ],
              ),
            ),
    );
  }
}

String? _date(String? value) {
  if (value == null || value.length < 10) return null;
  return value.substring(0, 10);
}
