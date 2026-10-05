import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/models/hr.dart';
import 'document_identity.dart';

class PayrollPdfService {
  Future<Uint8List> payslip({
    required PayrollEntryItem entry,
    required String periodLabel,
    required List<Map<String, Object?>> items,
    required DocumentIdentity identity,
    required String reference,
    String employeeNumber = '',
    String position = '',
    String department = '',
  }) async {
    final pdf = pw.Document();
    final money = NumberFormat('#,##0', 'fr_FR');
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => DocumentPdfChrome.header(identity),
        footer: (context) => DocumentPdfChrome.footer(context, identity, reference: reference),
        build: (_) => [
          pw.SizedBox(height: 12),
          pw.Text('BULLETIN DE PAIE', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.Text('Période : $periodLabel · Référence : $reference'),
          pw.SizedBox(height: 14),
          pw.TableHelper.fromTextArray(data: [
            ['Employé', entry.employeeName],
            if (employeeNumber.isNotEmpty) ['Matricule', employeeNumber],
            if (position.isNotEmpty) ['Fonction', position],
            if (department.isNotEmpty) ['Service', department],
            ['Statut', entry.status],
          ], columnWidths: {0: const pw.FixedColumnWidth(110)}),
          pw.SizedBox(height: 14),
          pw.TableHelper.fromTextArray(
            headers: const ['Élément', 'Type', 'Montant'],
            data: items.map((item) => [
              item['label']?.toString() ?? '',
              item['kind'] == 'deduction' ? 'Retenue' : 'Gain',
              '${money.format((item['amount'] as num?)?.toInt() ?? 0)} XAF',
            ]).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 16),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('Brut : ${money.format(entry.grossSalary)} XAF'),
            pw.Text('Retenues : ${money.format(entry.totalDeductions)} XAF'),
          ]),
          pw.SizedBox(height: 8),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(color: PdfColors.blueGrey50, border: pw.Border.all(color: PdfColors.blueGrey300)),
            child: pw.Text('NET À PAYER : ${money.format(entry.netSalary)} XAF', style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold)),
          ),
          if (entry.status == 'paid') ...[
            pw.SizedBox(height: 12),
            pw.Text('Payé${entry.paidAt == null ? '' : ' le ${DateFormat('dd/MM/yyyy').format(entry.paidAt!)}'}${entry.paymentMethod == null ? '' : ' par ${entry.paymentMethod}'}'),
            if ((entry.paymentReference ?? '').trim().isNotEmpty) pw.Text('Référence du paiement : ${entry.paymentReference}'),
          ],
          pw.SizedBox(height: 32),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('Salarié'),
            pw.Text('Gestionnaire / cachet'),
          ]),
          pw.SizedBox(height: 26),
          pw.Text('Document généré par GesApp · Référence permanente $reference', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ],
      ),
    );
    return pdf.save();
  }
}
