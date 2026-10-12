
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'document_identity.dart';

/// Facture scolaire consolidée ou avis des sommes restant à régler.
class BillingPdfService {
  Future<Uint8List> build({
    required Map<String, Object?> data,
    required bool invoice,
    required String reference,
    required DocumentIdentity identity,
    List<Map<String, Object?>>? lines,
  }) async {
    final pdf = pw.Document();
    final allLines = lines ?? [data];
    final selected = invoice ? allLines : allLines.where(
      (row) => _number(row['balance']) > 0,
    ).toList();
    final amountDue = selected.fold<int>(
      0, (sum, row) => sum + _number(row['amount_due']),
    );
    final amountPaid = selected.fold<int>(
      0, (sum, row) => sum + _number(row['amount_paid']),
    );
    final balance = amountDue - amountPaid;
    String v(String key) => '${data[key] ?? ''}';
    final title = invoice ? 'FACTURE SCOLAIRE DÉTAILLÉE' : 'AVIS D’ÉCHÉANCE';
    final issuedAt = DateTime.now();
    final issueDate = '${issuedAt.day.toString().padLeft(2, '0')}/'
        '${issuedAt.month.toString().padLeft(2, '0')}/${issuedAt.year}';
    final dates = selected.map((r) => _dateRaw(r['due_date']))
        .whereType<DateTime>().toList()..sort();
    final dueDate = dates.isEmpty ? null : dates.first;

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(38, 32, 38, 34),
      header: (_) => DocumentPdfChrome.header(identity),
      footer: (context) => DocumentPdfChrome.footer(
          context, identity, reference: reference),
      build: (_) => [
        pw.SizedBox(height: 16),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: PdfColors.blueGrey800,
          child: pw.Row(children: [
            pw.Expanded(child: pw.Text(title, style: pw.TextStyle(
              color: PdfColors.white, fontSize: 17,
              fontWeight: pw.FontWeight.bold,
            ))),
            pw.Text('N° $reference', style: pw.TextStyle(
              color: PdfColors.white, fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            )),
          ]),
        ),
        pw.SizedBox(height: 13),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(child: _addressBox('DESTINATAIRE', [
            'Élève : ${v('student')}',
            'Matricule : ${v('registration_number')}',
            'Classe : ${v('cycle')} / ${v('classroom')}',
            if (v('guardian_name').trim().isNotEmpty)
              'Responsable : ${v('guardian_name')}',
            if (v('guardian_phone').trim().isNotEmpty)
              'Téléphone : ${v('guardian_phone')}',
          ])),
          pw.SizedBox(width: 16),
          pw.Expanded(child: _addressBox('INFORMATIONS', [
            'Émise le : $issueDate',
            'Année scolaire : ${v('school_year_label')}',
            'Nombre de rubriques : ${selected.length}',
            'Première date limite : ${_date(dueDate)}',
          ])),
        ]),
        pw.SizedBox(height: 16),
        pw.Text(invoice
            ? 'DÉTAIL DES FRAIS SCOLAIRES'
            : 'DÉTAIL DES SOMMES NON SOLDÉES',
          style: pw.TextStyle(fontSize: 11.5,
              fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900),
        ),
        pw.SizedBox(height: 7),
        pw.TableHelper.fromTextArray(
          headers: const ['Rubrique', 'Période', 'Échéance', 'Dû', 'Payé', 'Reste'],
          data: [
            for (final row in selected)
              [
                '${row['fee'] ?? ''}',
                '${row['period_key'] ?? ''}',
                _date(_dateRaw(row['due_date'])),
                _money(_number(row['amount_due'])),
                _money(_number(row['amount_paid'])),
                _money(_number(row['balance'])),
              ],
          ],
          columnWidths: {
            0: const pw.FlexColumnWidth(2),
            1: const pw.FlexColumnWidth(1.2),
            2: const pw.FlexColumnWidth(1.2),
            3: const pw.FlexColumnWidth(1.1),
            4: const pw.FlexColumnWidth(1.1),
            5: const pw.FlexColumnWidth(1.1),
          },
          headerDecoration: const pw.BoxDecoration(
            color: PdfColors.blueGrey800,
          ),
          headerStyle: pw.TextStyle(color: PdfColors.white,
              fontSize: 9, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 5, vertical: 7),
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
        ),
        pw.SizedBox(height: 14),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(invoice ? 'Situation à la date d’émission'
                    : 'Date limite de régularisation',
                style: pw.TextStyle(fontSize: 9,
                    fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text(
                invoice
                    ? 'Les règlements enregistrés sont déduits du total. '
                      'Une facture n’est pas une preuve de paiement.'
                    : 'Merci de régler les sommes restant dues avant la date '
                      'limite indiquée. Cet avis n’est pas un reçu.',
                style: const pw.TextStyle(
                    fontSize: 9, color: PdfColors.grey700),
              ),
              if (!invoice) pw.Text(_date(dueDate),
                style: pw.TextStyle(fontSize: 11,
                    fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
            ],
          )),
          pw.SizedBox(width: 18),
          pw.Container(
            width: 210, padding: const pw.EdgeInsets.all(11),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              border: pw.Border.all(color: PdfColors.grey400),
            ),
            child: pw.Column(children: [
              _totalRow('Total dû', _money(amountDue)),
              pw.SizedBox(height: 5),
              _totalRow('Déjà payé', _money(amountPaid)),
              pw.Divider(color: PdfColors.grey500),
              _totalRow('RESTE À PAYER', _money(balance), strong: true),
            ]),
          ),
        ]),
        pw.SizedBox(height: 16),
        pw.Text(
          'Référence documentaire : $reference · Année scolaire : '
          '${identity.schoolYear.isEmpty ? v('school_year_label') : identity.schoolYear}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ],
    ));
    return pdf.save();
  }

  int _number(Object? value) =>
      value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;

  String _money(int value) {
    final digits = value.abs().toString();
    final parts = <String>[];
    for (var end = digits.length; end > 0; end -= 3) {
      final start = end - 3 < 0 ? 0 : end - 3;
      parts.insert(0, digits.substring(start, end));
    }
    return "${value < 0 ? '-' : ''}${parts.join(' ')} FCFA";
  }

  DateTime? _dateRaw(Object? raw) => raw == null
      ? null : DateTime.tryParse('$raw');

  String _date(DateTime? date) => date == null
      ? '—' : '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/${date.year}';

  pw.Widget _addressBox(String title, List<String> values) =>
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(title, style: pw.TextStyle(fontSize: 9,
                fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
            pw.SizedBox(height: 6),
            for (final value in values)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 3),
                child: pw.Text(value,
                    style: const pw.TextStyle(fontSize: 9.5)),
              ),
          ],
        ),
      );

  pw.Widget _totalRow(String label, String amount, {bool strong = false}) =>
      pw.Row(children: [
        pw.Expanded(child: pw.Text(label,
          style: pw.TextStyle(fontSize: strong ? 10 : 9,
              fontWeight: strong ? pw.FontWeight.bold : pw.FontWeight.normal))),
        pw.Text(amount, style: pw.TextStyle(fontSize: strong ? 11 : 9,
            fontWeight: pw.FontWeight.bold)),
      ]);
}
