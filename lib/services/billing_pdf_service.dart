import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'document_identity.dart';

class BillingPdfService {
  Future<Uint8List> build({
    required Map<String, Object?> data,
    required bool invoice,
    required String reference,
    required DocumentIdentity identity,
  }) async {
    final pdf = pw.Document();
    String v(String key) => '${data[key] ?? ''}';
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => DocumentPdfChrome.header(identity),
        footer: (context) => DocumentPdfChrome.footer(context, identity, reference: reference),
        build: (_) => [
          pw.SizedBox(height: 12),
          pw.Text(invoice ? 'FACTURE D’ÉCHÉANCE' : 'AVIS D’ÉCHÉANCE', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.Text('Référence : $reference', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            data: [
              ['Année scolaire', v('school_year_label')],
              ['Élève', v('student')],
              ['Matricule', v('registration_number')],
              ['Cycle / classe', '${v('cycle')} · ${v('classroom')}'],
              ['Famille', v('family').isEmpty ? '—' : v('family')],
              ['Parent / tuteur', v('guardian_name')],
              ['Téléphone', v('guardian_phone')],
              ['Rubrique', v('fee')],
              ['Période', v('period_key')],
              ['Date limite', v('due_date').isEmpty ? '—' : v('due_date').split('T').first],
              ['Montant dû', '${data['amount_due']} FCFA'],
              ['Déjà payé', '${data['amount_paid']} FCFA'],
              ['Reste à payer', '${data['balance']} FCFA'],
            ],
            columnWidths: {0: const pw.FixedColumnWidth(120)},
          ),
          pw.SizedBox(height: 22),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(color: PdfColors.grey100, border: pw.Border.all(color: PdfColors.grey300)),
            child: pw.Text(
              invoice
                  ? 'Document établi à partir de la situation comptable enregistrée dans GesApp. Référence permanente : $reference.'
                  : 'Merci de régulariser le montant restant avant la date limite indiquée. Ce document n’est pas un reçu de paiement.',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
        ],
      ),
    );
    return pdf.save();
  }
}
