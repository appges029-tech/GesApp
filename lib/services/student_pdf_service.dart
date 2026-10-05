import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/models/student.dart';
import '../data/repositories/settings_repository.dart';
import 'document_identity.dart';
import 'student_media_service.dart';

class StudentPdfService {
  Future<Uint8List> build({
    required StudentDetailBundle bundle,
    EstablishmentData? establishment,
    String? reference,
  }) async {
    final s = bundle.student;
    final identity = await DocumentIdentity.fromEstablishment(establishment);
    pw.MemoryImage? photo;
    if (s.photoPath != null) {
      final bytes = await StudentMediaService().readStoredFileBytes(s.photoPath!);
      if (bytes != null && bytes.isNotEmpty) photo = pw.MemoryImage(bytes);
    }
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 24),
        header: (_) => DocumentPdfChrome.header(identity),
        footer: (context) => DocumentPdfChrome.footer(context, identity, reference: reference),
        build: (_) => [
          pw.SizedBox(height: 10),
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            if (photo != null)
              pw.Container(width: 72, height: 86, child: pw.Image(photo, fit: pw.BoxFit.cover))
            else
              pw.Container(width: 72, height: 86, alignment: pw.Alignment.center, decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)), child: pw.Text('PHOTO', style: const pw.TextStyle(fontSize: 9))),
            pw.SizedBox(width: 14),
            pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('FICHE ÉLÈVE', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              if ((reference ?? '').isNotEmpty) pw.Text('Référence : $reference', style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 5),
              pw.Text(s.fullName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.Text(s.registrationNumber ?? 'Sans matricule'),
            ])),
          ]),
          pw.SizedBox(height: 16),
          _section('Identité', [
            ['Nom', s.lastName], ['Prénom', s.firstName], ['Sexe', s.gender ?? '—'],
            ['Date de naissance', s.birthDate?.toIso8601String().split('T').first ?? '—'], ['Lieu de naissance', s.birthPlace ?? '—'],
            ['Cycle', s.cycleName], ['Classe', s.classroomName], ['Statut', s.status], ['Date inscription', s.enrollmentDate?.toIso8601String().split('T').first ?? '—'],
          ]),
          _section('Responsable & famille', [
            ['Parent / tuteur', s.guardianName ?? '—'], ['Téléphone', s.guardianPhone ?? '—'], ['Famille', s.familyName ?? '—'],
          ]),
          _section('Situation financière', [
            ['Montant attendu', '${bundle.finance.expected} FCFA'], ['Payé', '${bundle.finance.paid} FCFA'], ['Reste', '${bundle.finance.outstanding} FCFA'],
            ['Dont en retard', '${bundle.finance.overdue} FCFA'], ['Nombre de paiements', '${bundle.finance.paymentCount}'], ['Forfait actif', s.hasPackage ? 'Oui' : 'Non'],
          ]),
          pw.Text('Pièces du dossier', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          if (bundle.documents.isEmpty)
            pw.Text('Aucune pièce enregistrée.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Type', 'Obligatoire', 'Ajoutée le', 'Code vérification', 'Statut'],
              data: bundle.documents.map((d) => [
                d.documentType,
                d.isRequired ? 'Oui' : 'Non',
                d.addedAt.toIso8601String().split('T').first,
                d.verificationCode ?? '—',
                d.isVerificationValid ? 'Valide' : 'Révoquée',
              ]).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 7.5),
            ),
          pw.SizedBox(height: 14),
          pw.Text('Échéances', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          if (bundle.dues.isEmpty)
            pw.Text('Aucune échéance.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Rubrique', 'Période', 'Dû', 'Payé', 'Reste', 'Statut'],
              data: bundle.dues.map((d) => [d.feeName, d.periodKey, '${d.amountDue}', '${d.amountPaid}', '${d.balance}', d.status]).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 8),
            ),
          pw.SizedBox(height: 14),
          pw.Text('Paiements', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          if (bundle.payments.isEmpty)
            pw.Text('Aucun paiement.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Date', 'Reçu', 'Mode', 'Montant'],
              data: bundle.payments.map((p) => [p.paidAt.toIso8601String().split('T').first, p.receiptNumber, p.method, '${p.amount} FCFA']).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 8),
            ),
          pw.SizedBox(height: 14),
          pw.Text('Historique des statuts', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          if (bundle.history.isEmpty)
            pw.Text('Aucun historique.')
          else
            pw.TableHelper.fromTextArray(
              headers: const ['Date', 'Ancien', 'Nouveau', 'Note'],
              data: bundle.history.map((h) => [h.changedAt.toIso8601String().split('T').first, h.oldStatus ?? '—', h.newStatus, h.note ?? '']).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 8),
            ),
        ],
      ),
    );
    return pdf.save();
  }

  pw.Widget _section(String title, List<List<String>> rows) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
    pw.Text(title, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
    pw.SizedBox(height: 6),
    pw.TableHelper.fromTextArray(data: rows, cellStyle: const pw.TextStyle(fontSize: 9), columnWidths: {0: const pw.FixedColumnWidth(115)}),
    pw.SizedBox(height: 14),
  ]);
}
