import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:gesapp/services/report_pdf_service.dart';
import 'package:gesapp/services/billing_pdf_service.dart';
import 'package:gesapp/services/document_identity.dart';
import 'package:gesapp/services/payment_notice_batch_pdf_service.dart';

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
  test('facture A4 consolidée de 30 échéances avec nom long', () async {
    final lines = List.generate(30, (index) => <String, Object?>{
      'fee': 'Frais scolaires et activités pédagogiques très détaillées $index',
      'period_key': '2026-${(index % 12 + 1).toString().padLeft(2, '0')}',
      'due_date': '2026-10-15T00:00:00',
      'amount_due': 25000,
      'amount_paid': 5000,
      'balance': 20000,
    });
    final bytes = await BillingPdfService().build(
      data: {
        'student': 'Élève au nom et prénom particulièrement longs',
        'school_year_label': '2026-2027',
        'registration_number': 'EL-00001',
        'cycle': 'Collège', 'classroom': '6e A',
        'guardian_name': 'Parent au nom très long',
      },
      lines: lines,
      invoice: true,
      reference: 'FAC-2026-999999',
      identity: school,
    );
    expectPdf(bytes);
  });

  test('avis global : plusieurs échéances et paiements partiels', () async {
    final bytes = await BillingPdfService().build(
      data: {
        'student': 'Élève Test',
        'school_year_label': '2026-2027',
        'registration_number': 'EL-00002',
        'cycle': 'Primaire', 'classroom': 'CM2',
      },
      invoice: false,
      reference: 'ECH-2026-999999',
      identity: school,
      lines: [
        {
          'fee': 'Scolarité octobre',
          'period_key': '2026-10',
          'due_date': '2026-10-15',
          'amount_due': 25000,
          'amount_paid': 10000,
          'balance': 15000,
        },
        {
          'fee': 'Scolarité novembre',
          'period_key': '2026-11',
          'due_date': '2026-11-15',
          'amount_due': 25000,
          'amount_paid': 0,
          'balance': 25000,
        },
        {
          'fee': 'Rubrique soldée',
          'period_key': '2026-10',
          'due_date': '2026-10-15',
          'amount_due': 1000,
          'amount_paid': 1000,
          'balance': 0,
        },
      ],
    );
    expectPdf(bytes);
  });

  test('appels A4 haute lisibilité : 19 élèves et plusieurs frais', () async {
    final students = List.generate(19, (index) {
      final student = StudentNoticeData(
        studentId: 'student-$index',
        studentName: 'Élève au nom suffisamment long $index',
        registrationNumber: 'EL-2026-$index',
        cycle: 'Collège', classroom: '6e A',
        family: 'Famille', guardianName: 'Responsable légal',
        guardianPhone: '060000000',
        periodKey: '2026-10',
      );
      for (var i = 0; i < (index == 0 ? 24 : 3); i++) {
        student.lines.add((
          fee: 'Rubrique scolaire numéro $i',
          amountDue: 15000, amountPaid: 1000,
          dueDate: '2026-10-31',
        ));
      }
      return student;
    });
    final bytes = await PaymentNoticeBatchPdfService().build(
      students: students,
      periodLabel: 'Octobre 2026',
      establishmentName: 'Un établissement scolaire avec un nom long',
      establishmentAddress: '90 avenue des 3 Martyrs',
      establishmentPhone: '060000000',
      approvalNumber: 'AGR-100',
      schoolYearLabel: '2026-2027',
      batchReference: 'APP-2026-000001',
    );
    expectPdf(bytes);
  });

}
