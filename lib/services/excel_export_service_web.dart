import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../core/platform/download_service.dart';

class ExcelExportService {
  Future<String> export({required String fileName, required List<String> headers, required List<List<String>> rows}) async {
    final workbook = Excel.createExcel();
    const sheetName = 'Données';
    final defaultSheet = workbook.getDefaultSheet();
    final sheet = workbook[sheetName];
    sheet.appendRow(headers.map(TextCellValue.new).toList());
    for (final row in rows) {
      sheet.appendRow(row.map(TextCellValue.new).toList());
    }
    workbook.setDefaultSheet(sheetName);
    if (defaultSheet != null && defaultSheet != sheetName) workbook.delete(defaultSheet);
    final encoded = workbook.save();
    if (encoded == null) throw StateError('Impossible de générer le fichier Excel.');

    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final name = '${safe}_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    await downloadBytes(
      bytes: Uint8List.fromList(encoded),
      fileName: name,
      mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    return name;
  }
}
