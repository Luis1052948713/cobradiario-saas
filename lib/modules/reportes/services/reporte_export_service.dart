import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/currency_formatter.dart';
import '../data/reportes_repository.dart';
import 'reporte_file_saver_stub.dart'
    if (dart.library.html) 'reporte_file_saver_web.dart'
    if (dart.library.io) 'reporte_file_saver_io.dart';

class ReporteExportResult {
  const ReporteExportResult({required this.fileName, required this.location});

  final String fileName;
  final String location;
}

class ReporteExportService {
  const ReporteExportService();

  Future<ReporteExportResult> exportarPdf({
    required ReporteCobros reporte,
    required bool incluyeGlobal,
  }) async {
    final document = pw.Document();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Cobra Diario',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text('Reporte de cobros'),
                pw.Text(
                  'Periodo: ${_date(reporte.desde)} - ${_date(reporte.hasta)}',
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          _pdfTable(
            titulo: 'Resumen de cobros',
            rows: [
              ['Total cobrado', _money(reporte.totalCobrado)],
              ['Pagos realizados', '${reporte.cantidadPagos}'],
              ['Visitas sin pago', '${reporte.cantidadVisitas}'],
              ['Promedio por pago', _money(reporte.promedioPorPago)],
              ['Efectividad de visitas', _percent(reporte.efectividadVisitas)],
              ['Cobertura de recaudo', _percent(reporte.coberturaRecaudo)],
            ],
          ),
          pw.SizedBox(height: 14),
          _pdfTable(
            titulo: 'Estado de cartera',
            rows: [
              ['Saldo pendiente', _money(reporte.saldoPendiente)],
              if (incluyeGlobal)
                ['Total prestado', _money(reporte.totalPrestado)],
              if (incluyeGlobal)
                ['Ganancia estimada', _money(reporte.gananciaEstimada)],
            ],
          ),
          pw.SizedBox(height: 14),
          _pdfTable(
            titulo: 'Prestamos y alertas',
            rows: [
              ['Prestamos activos', '${reporte.prestamosActivos}'],
              ['Prestamos pagados', '${reporte.prestamosPagados}'],
              ['Prestamos atrasados', '${reporte.prestamosAtrasados}'],
              ['Clientes morosos', '${reporte.clientesMorosos}'],
            ],
          ),
        ],
      ),
    );

    return _guardarBytes(
      bytes: Uint8List.fromList(await document.save()),
      extension: 'pdf',
      mimeType: 'application/pdf',
    );
  }

  Future<ReporteExportResult> exportarExcel({
    required ReporteCobros reporte,
    required bool incluyeGlobal,
  }) async {
    final excel = xls.Excel.createExcel();
    const sheetName = 'Reporte';
    final sheet = excel[sheetName];
    final defaultSheet = excel.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != sheetName) {
      excel.delete(defaultSheet);
    }
    excel.setDefaultSheet(sheetName);

    sheet.appendRow([
      xls.TextCellValue('Cobra Diario'),
      xls.TextCellValue('Reporte de cobros'),
    ]);
    sheet.appendRow([
      xls.TextCellValue('Periodo'),
      xls.TextCellValue('${_date(reporte.desde)} - ${_date(reporte.hasta)}'),
    ]);
    sheet.appendRow([]);

    _appendSection(sheet, 'Resumen de cobros', [
      ['Total cobrado', reporte.totalCobrado],
      ['Pagos realizados', reporte.cantidadPagos],
      ['Visitas sin pago', reporte.cantidadVisitas],
      ['Promedio por pago', reporte.promedioPorPago],
      ['Efectividad de visitas', '${reporte.efectividadVisitas.toStringAsFixed(1)}%'],
      ['Cobertura de recaudo', '${reporte.coberturaRecaudo.toStringAsFixed(1)}%'],
    ]);

    _appendSection(sheet, 'Estado de cartera', [
      ['Saldo pendiente', reporte.saldoPendiente],
      if (incluyeGlobal) ['Total prestado', reporte.totalPrestado],
      if (incluyeGlobal) ['Ganancia estimada', reporte.gananciaEstimada],
    ]);

    _appendSection(sheet, 'Prestamos y alertas', [
      ['Prestamos activos', reporte.prestamosActivos],
      ['Prestamos pagados', reporte.prestamosPagados],
      ['Prestamos atrasados', reporte.prestamosAtrasados],
      ['Clientes morosos', reporte.clientesMorosos],
    ]);

    final bytes = excel.encode();
    if (bytes == null) {
      throw StateError('No se pudo generar el archivo Excel.');
    }

    return _guardarBytes(
      bytes: Uint8List.fromList(bytes),
      extension: 'xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  pw.Widget _pdfTable({
    required String titulo,
    required List<List<String>> rows,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          titulo,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellAlignment: pw.Alignment.centerLeft,
          headers: const ['Concepto', 'Valor'],
          data: rows,
        ),
      ],
    );
  }

  void _appendSection(xls.Sheet sheet, String title, List<List<Object>> rows) {
    sheet.appendRow([xls.TextCellValue(title)]);
    sheet.appendRow([
      xls.TextCellValue('Concepto'),
      xls.TextCellValue('Valor'),
    ]);

    for (final row in rows) {
      final value = row[1];
      sheet.appendRow([
        xls.TextCellValue(row[0].toString()),
        if (value is int)
          xls.IntCellValue(value)
        else if (value is double)
          xls.DoubleCellValue(value)
        else
          xls.TextCellValue(value.toString()),
      ]);
    }

    sheet.appendRow([]);
  }

  Future<ReporteExportResult> _guardarBytes({
    required Uint8List bytes,
    required String extension,
    required String mimeType,
  }) async {
    final fileName = 'reporte_${_fileStamp(DateTime.now())}.$extension';
    final location = await saveReportBytes(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );
    return ReporteExportResult(fileName: fileName, location: location);
  }
}

String _money(double value) => CurrencyFormatter.pesos(value);

String _percent(double value) => '${value.toStringAsFixed(1)}%';

String _date(DateTime value) {
  return '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.year}';
}

String _fileStamp(DateTime value) {
  return '${value.year}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}_'
      '${value.hour.toString().padLeft(2, '0')}'
      '${value.minute.toString().padLeft(2, '0')}'
      '${value.second.toString().padLeft(2, '0')}';
}
