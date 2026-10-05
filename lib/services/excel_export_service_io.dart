import 'dart:io';

import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
    final bytes = workbook.save();
    if (bytes == null) throw StateError('Impossible de générer le fichier Excel.');

    final root = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'GesApp'));
    await dir.create(recursive: true);
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final file = File(p.join(dir.path, '${safe}_${DateTime.now().millisecondsSinceEpoch}.xlsx'));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
