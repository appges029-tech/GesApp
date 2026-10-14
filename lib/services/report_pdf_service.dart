import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'document_identity.dart';

class ReportPdfService {
  Future<Uint8List> table({
    required String title,
    String? subtitle,
    required List<String> headers,
    required List<List<String>> rows,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
    DocumentIdentity? identity,
    String? reference,
    String? periodLabel,
  }) async {
    final effectiveIdentity = identity ?? const DocumentIdentity(name: 'Établissement scolaire');
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 24),
        header: (_) => DocumentPdfChrome.header(effectiveIdentity),
        footer: (context) => DocumentPdfChrome.footer(context, effectiveIdentity, reference: reference),
        build: (_) => [
          pw.SizedBox(height: 10),
          pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          if ((reference ?? '').trim().isNotEmpty)
            pw.Text('Référence : ${reference!.trim()}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          if ((periodLabel ?? '').trim().isNotEmpty)
            pw.Text('Période : ${periodLabel!.trim()}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          if (subtitle != null && subtitle.trim().isNotEmpty)
            pw.Text(subtitle, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 14),
          ..._tableChunks(headers, rows),
          pw.SizedBox(height: 10),
          pw.Text('Total lignes : ${rows.length}', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
        ],
      ),
    );
    return pdf.save();
  }


  List<pw.Widget> _tableChunks(List<String> headers, List<List<String>> rows) {
    const chunkSize = 400;
    final widgets = <pw.Widget>[];
    for (var start = 0; start < rows.length; start += chunkSize) {
      final end = (start + chunkSize < rows.length) ? start + chunkSize : rows.length;
      widgets.add(
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: rows.sublist(start, end),
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold,
            color: PdfColors.white, fontSize: headers.length >= 10 ? 6.8 : 8),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
          cellStyle: pw.TextStyle(fontSize: headers.length >= 10 ? 6.8 : 8.5),
          cellPadding: pw.EdgeInsets.symmetric(horizontal:
            headers.length >= 10 ? 2.5 : 5, vertical: 4),
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        ),
      );
      if (end < rows.length) widgets.add(pw.SizedBox(height: 8));
    }
    return widgets;
  }
}
