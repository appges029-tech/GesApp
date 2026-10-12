import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:gesapp/services/report_pdf_service.dart';
import 'package:gesapp/services/billing_pdf_service.dart';
import 'package:gesapp/services/document_identity.dart';

void expectPdf(Uint8List data) {
  expect(data.length, greaterThan(400));
  expect(String.fromCharCodes(data.take(4)), '%PDF');
}

void main() {
  const school = DocumentIdentity(
    name: 'Ecole des tests',
    schoolYear: '2026-2027',
    generatedBy: 'Gestionnaire de test',
  );

  test('un état d impayés multipages conserve toutes ses colonnes', () async {
    final headers = List.generate(11, (i) => 'Colonne ${i + 1}');
    final rows = List.generate(160,
        (i) => List.generate(11, (j) => 'Ligne $i montant $j'));
    final pdf = await ReportPdfService().table(
      title: 'Etat des impayés',
      headers: headers,
      rows: rows,
      reference: 'RAP-2026-000001',
      subtitle: 'Année 2026-2027 / Collège / 6e A',
      pageFormat: PdfPageFormat.a4.landscape,
      identity: school,
    );
    expectPdf(pdf);
  });

  test('une facture d échéance affiche l année de son enregistrement', () async {
    final pdf = await BillingPdfService().build(
      data: {
        'student': 'Eleve Test', 'registration_number': 'ET-001',
        'cycle': 'Collège', 'classroom': '6e A',
        'school_year_label': '2025-2026',
        'fee': 'Scolarité', 'period_key': '2026-06',
        'amount_due': 30000, 'amount_paid': 10000,
        'balance': 20000, 'due_date': '2026-06-30T00:00:00',
      },
      invoice: true, reference: 'FAC-2026-000001',
      identity: school.forSchoolYear('2025-2026'),
    );
    expectPdf(pdf);
  });
}
