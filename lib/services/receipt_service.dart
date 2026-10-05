import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'document_identity.dart';

enum ReceiptFormat { a5, pos80, pos58 }

extension ReceiptFormatX on ReceiptFormat {
  String get storageKey => switch (this) {
        ReceiptFormat.a5 => 'a5',
        ReceiptFormat.pos80 => 'pos80',
        ReceiptFormat.pos58 => 'pos58',
      };

  String get label => switch (this) {
        ReceiptFormat.a5 => 'A5 administratif',
        ReceiptFormat.pos80 => 'POS 80 mm',
        ReceiptFormat.pos58 => 'POS 58 mm',
      };

  bool get isPos => this != ReceiptFormat.a5;

  double get pageWidthMm => switch (this) {
        ReceiptFormat.a5 => 148,
        ReceiptFormat.pos80 => 80,
        ReceiptFormat.pos58 => 58,
      };

  PdfPageFormat pageFormatFor({int detailLines = 0}) {
    if (this == ReceiptFormat.a5) return PdfPageFormat.a5;
    // Thermal rolls have an infinite height in pdf's predefined roll formats.
    // A finite document is more reliable with Windows printer drivers.
    final baseMm = this == ReceiptFormat.pos80 ? 122.0 : 136.0;
    final perLineMm = this == ReceiptFormat.pos80 ? 9.0 : 12.0;
    final heightMm = (baseMm + (detailLines * perLineMm)).clamp(122.0, 480.0).toDouble();
    return PdfPageFormat(
      pageWidthMm * PdfPageFormat.mm,
      heightMm * PdfPageFormat.mm,
    );
  }

  static ReceiptFormat fromStorageKey(String? value) => switch (value) {
        'pos80' => ReceiptFormat.pos80,
        'pos58' => ReceiptFormat.pos58,
        _ => ReceiptFormat.a5,
      };
}

class ReceiptLine {
  const ReceiptLine({required this.label, required this.amount});
  final String label;
  final int amount;
}

class ReceiptData {
  const ReceiptData({
    required this.identity,
    required this.receiptNumber,
    required this.studentName,
    required this.amount,
    required this.currency,
    required this.paymentMethod,
    required this.dateLabel,
    this.paymentReference = '',
    this.lines = const [],
  });

  final DocumentIdentity identity;
  final String receiptNumber;
  final String studentName;
  final int amount;
  final String currency;
  final String paymentMethod;
  final String dateLabel;
  final String paymentReference;
  final List<ReceiptLine> lines;
}

class ReceiptService {
  Future<Uint8List> generate(
    ReceiptData data, {
    ReceiptFormat format = ReceiptFormat.a5,
    bool showLogo = true,
    bool includeDetails = true,
  }) async {
    final pdf = pw.Document();
    if (format.isPos) {
      pdf.addPage(_buildPosPage(data, format: format, showLogo: showLogo, includeDetails: includeDetails));
    } else {
      pdf.addPage(_buildA5Page(data));
    }
    return pdf.save();
  }

  pw.Page _buildA5Page(ReceiptData data) => pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            DocumentPdfChrome.header(data.identity),
            pw.SizedBox(height: 12),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(vertical: 8),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey700)),
              child: pw.Center(
                child: pw.Text('REÇU DE PAIEMENT N° ${data.receiptNumber}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              ),
            ),
            pw.SizedBox(height: 14),
            pw.Text('Bénéficiaire : ${data.studentName}'),
            pw.Text('Date : ${data.dateLabel}'),
            pw.Text('Mode de paiement : ${data.paymentMethod}'),
            if (data.paymentReference.trim().isNotEmpty) pw.Text('Référence transaction : ${data.paymentReference.trim()}'),
            pw.SizedBox(height: 10),
            if (data.lines.isNotEmpty) ...[
              pw.Text('Affectation du paiement', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey500),
                columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1.4)},
                children: [
                  for (final line in data.lines)
                    pw.TableRow(children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(line.label)),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${line.amount} ${data.currency}', textAlign: pw.TextAlign.right)),
                    ]),
                ],
              ),
              pw.SizedBox(height: 12),
            ],
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(color: PdfColors.grey200, borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Text('TOTAL REÇU : ${data.amount} ${data.currency}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(height: 8),
            pw.Text('Authenticité : vérifiez ce document dans GesApp avec le numéro ${data.receiptNumber}.', style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700)),
            pw.Spacer(),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text(data.identity.generatedBy.trim().isEmpty ? 'Gestionnaire' : data.identity.generatedBy),
              pw.Column(children: [pw.SizedBox(height: 28), pw.Container(width: 110, height: 1, color: PdfColors.grey700), pw.SizedBox(height: 3), pw.Text('Signature / cachet')]),
            ]),
            pw.SizedBox(height: 8),
            DocumentPdfChrome.footer(context, data.identity, reference: data.receiptNumber),
          ],
        ),
      );

  pw.Page _buildPosPage(
    ReceiptData data, {
    required ReceiptFormat format,
    required bool showLogo,
    required bool includeDetails,
  }) {
    final detailLines = includeDetails ? data.lines.length : 0;
    final pageFormat = format.pageFormatFor(detailLines: detailLines);
    final horizontal = format == ReceiptFormat.pos80 ? 4.5 : 3.0;
    final small = format == ReceiptFormat.pos80 ? 8.0 : 7.1;
    final normal = format == ReceiptFormat.pos80 ? 9.2 : 8.0;
    final title = format == ReceiptFormat.pos80 ? 12.0 : 10.0;
    final logo = showLogo && data.identity.logoBytes != null && data.identity.logoBytes!.isNotEmpty
        ? pw.MemoryImage(data.identity.logoBytes!)
        : null;

    pw.Widget rule({double top = 5, double bottom = 5}) => pw.Padding(
          padding: pw.EdgeInsets.only(top: top, bottom: bottom),
          child: pw.Container(height: .65, color: PdfColors.grey700),
        );

    pw.Widget row(String label, String value, {bool strong = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(width: format == ReceiptFormat.pos80 ? 58 : 42, child: pw.Text(label, style: pw.TextStyle(fontSize: small, fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal))),
              pw.Expanded(child: pw.Text(value, style: pw.TextStyle(fontSize: normal, fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal))),
            ],
          ),
        );

    return pw.Page(
      pageFormat: pageFormat,
      margin: pw.EdgeInsets.fromLTRB(
        horizontal * PdfPageFormat.mm,
        4 * PdfPageFormat.mm,
        horizontal * PdfPageFormat.mm,
        4 * PdfPageFormat.mm,
      ),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (logo != null) ...[
            pw.Center(child: pw.Container(width: format == ReceiptFormat.pos80 ? 30 : 23, height: format == ReceiptFormat.pos80 ? 30 : 23, child: pw.Image(logo, fit: pw.BoxFit.contain))),
            pw.SizedBox(height: 3),
          ],
          pw.Text(data.identity.name.toUpperCase(), textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: title, fontWeight: pw.FontWeight.bold)),
          if (data.identity.address.isNotEmpty) pw.Text(data.identity.address, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: small)),
          if (data.identity.phone.isNotEmpty) pw.Text('Tél. ${data.identity.phone}', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: small)),
          if (data.identity.schoolYear.isNotEmpty) pw.Text('Année scolaire ${data.identity.schoolYear}', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: small)),
          rule(),
          pw.Text('REÇU DE PAIEMENT', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: title, fontWeight: pw.FontWeight.bold)),
          pw.Text('N° ${data.receiptNumber}', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: normal, fontWeight: pw.FontWeight.bold)),
          rule(),
          row('Élève / payeur', data.studentName, strong: true),
          row('Date', data.dateLabel),
          row('Paiement', data.paymentMethod),
          if (data.paymentReference.trim().isNotEmpty) row('Référence', data.paymentReference.trim()),
          if (includeDetails && data.lines.isNotEmpty) ...[
            rule(top: 4, bottom: 3),
            pw.Text('DÉTAIL', style: pw.TextStyle(fontSize: small, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            for (final line in data.lines)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(child: pw.Text(line.label, style: pw.TextStyle(fontSize: small))),
                    pw.SizedBox(width: 5),
                    pw.Text(_amount(line.amount, data.currency), textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: small, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
          ],
          rule(top: 4, bottom: 4),
          pw.Text('TOTAL : ${_amount(data.amount, data.currency)}', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: title + 1, fontWeight: pw.FontWeight.bold)),
          rule(top: 4, bottom: 4),
          if (data.identity.generatedBy.trim().isNotEmpty) pw.Text('Caissier : ${data.identity.generatedBy.trim()}', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: small)),
          pw.SizedBox(height: 4),
          pw.Text('Authenticité : ${data.receiptNumber}', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: small, fontWeight: pw.FontWeight.bold)),
          pw.Text('Vérifiable dans GesApp', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: small, color: PdfColors.grey700)),
          pw.SizedBox(height: 5),
          pw.Text('Merci.', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: normal, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  static String _amount(int amount, String currency) {
    final raw = amount.abs().toString();
    final chunks = <String>[];
    for (var end = raw.length; end > 0; end -= 3) {
      final start = end - 3 < 0 ? 0 : end - 3;
      chunks.insert(0, raw.substring(start, end));
    }
    return '${amount < 0 ? '-' : ''}${chunks.join(' ')} $currency';
  }
}
