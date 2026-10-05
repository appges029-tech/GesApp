import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Un appel à paiement pour un seul élève, pouvant regrouper plusieurs
/// rubriques dues sur la même période. Ce document n'est jamais un reçu.
class StudentNoticeData {
  StudentNoticeData({
    required this.studentId,
    required this.studentName,
    required this.registrationNumber,
    required this.cycle,
    required this.classroom,
    required this.family,
    required this.guardianName,
    required this.guardianPhone,
    required this.periodKey,
  });

  final String studentId;
  final String studentName;
  final String registrationNumber;
  final String cycle;
  final String classroom;
  final String family;
  final String guardianName;
  final String guardianPhone;
  final String periodKey;
  final List<({String fee, int amountDue, int amountPaid, String? dueDate})> lines = [];

  int get totalDue => lines.fold(0, (s, l) => s + l.amountDue);
  int get totalPaid => lines.fold(0, (s, l) => s + l.amountPaid);
  int get totalBalance => totalDue - totalPaid;
  String? get paymentDeadline {
    final dates = lines.map((l) => l.dueDate).whereType<String>().toList()..sort();
    return dates.isEmpty ? null : dates.first;
  }
}

/// Regroupe les lignes d'échéances (issues de ReportRepository.billingDues)
/// par élève, afin de produire un avis unique par élève même si celui-ci a
/// plusieurs rubriques dues sur la période choisie.
List<StudentNoticeData> groupDuesByStudent(List<Map<String, Object?>> rows) {
  final byStudent = <String, StudentNoticeData>{};
  for (final r in rows) {
    final amountDue = (r['amount_due'] as num?)?.toInt() ?? 0;
    final amountPaid = (r['amount_paid'] as num?)?.toInt() ?? 0;
    if (amountDue - amountPaid <= 0) continue;
    final id = '${r['student_id']}';
    final entry = byStudent.putIfAbsent(
      id,
      () => StudentNoticeData(
        studentId: id,
        studentName: '${r['student'] ?? ''}',
        registrationNumber: '${r['registration_number'] ?? ''}',
        cycle: '${r['cycle'] ?? ''}',
        classroom: '${r['classroom'] ?? ''}',
        family: '${r['family'] ?? ''}',
        guardianName: '${r['guardian_name'] ?? ''}',
        guardianPhone: '${r['guardian_phone'] ?? ''}',
        periodKey: '${r['period_key'] ?? ''}',
      ),
    );
    entry.lines.add((
      fee: '${r['fee'] ?? ''}',
      amountDue: amountDue,
      amountPaid: amountPaid,
      dueDate: r['due_date'] == null ? null : '${r['due_date']}'.split('T').first,
    ));
  }
  final list = byStudent.values.toList()
    ..sort((a, b) => a.studentName.compareTo(b.studentName));
  return list;
}

class PaymentNoticeBatchPdfService {
  Future<Uint8List> build({
    required List<StudentNoticeData> students,
    required String periodLabel,
    String? establishmentName,
    String? establishmentAddress,
    String? establishmentPhone,
    String? establishmentEmail,
    String? approvalNumber,
    String? schoolYearLabel,
    String? batchReference,
    String? cycleLabel,
    String? classroomLabel,
    Uint8List? logoBytes,
  }) async {
    final pdf = pw.Document();
    final logo = (logoBytes != null && logoBytes.isNotEmpty) ? pw.MemoryImage(logoBytes) : null;
    const perPage = 8;
    for (var i = 0; i < students.length; i += perPage) {
      final pageStudents = students.skip(i).take(perPage).toList();
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(10),
          build: (_) => pw.Column(
            children: List.generate(4, (row) => [
              _cellRow([
                pageStudents.length > row * 2 ? pageStudents[row * 2] : null,
                pageStudents.length > row * 2 + 1 ? pageStudents[row * 2 + 1] : null,
              ], establishmentName, establishmentAddress, establishmentPhone, establishmentEmail, approvalNumber, schoolYearLabel, batchReference, cycleLabel, classroomLabel, periodLabel, logo),
              if (row < 3) pw.SizedBox(height: 4),
            ]).expand((widgets) => widgets).toList(),
          ),
        ),
      );
    }
    return pdf.save();
  }

  pw.Widget _cellRow(
    List<StudentNoticeData?> pair,
    String? establishmentName,
    String? establishmentAddress,
    String? establishmentPhone,
    String? establishmentEmail,
    String? approvalNumber,
    String? schoolYearLabel,
    String? batchReference,
    String? cycleLabel,
    String? classroomLabel,
    String periodLabel,
    pw.MemoryImage? logo,
  ) {
    return pw.Expanded(
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pair[0] == null
                ? pw.Container()
                : _noticeCell(pair[0]!, establishmentName, establishmentAddress, establishmentPhone, establishmentEmail, approvalNumber, schoolYearLabel, batchReference, cycleLabel, classroomLabel, periodLabel, logo),
          ),
          pw.SizedBox(width: 4),
          pw.Expanded(
            child: pair[1] == null
                ? pw.Container()
                : _noticeCell(pair[1]!, establishmentName, establishmentAddress, establishmentPhone, establishmentEmail, approvalNumber, schoolYearLabel, batchReference, cycleLabel, classroomLabel, periodLabel, logo),
          ),
        ],
      ),
    );
  }

  pw.Widget _noticeCell(
    StudentNoticeData s,
    String? establishmentName,
    String? establishmentAddress,
    String? establishmentPhone,
    String? establishmentEmail,
    String? approvalNumber,
    String? schoolYearLabel,
    String? batchReference,
    String? cycleLabel,
    String? classroomLabel,
    String periodLabel,
    pw.MemoryImage? logo,
  ) {
    String fmt(int v) => '$v FCFA';
    String displayDate(String? value) {
      if (value == null || value.isEmpty) return 'Non renseignée';
      final parts = value.split('-');
      return parts.length == 3 ? '${parts[2]}/${parts[1]}/${parts[0]}' : value;
    }
    final fees = s.lines.map((line) => line.fee).where((name) => name.isNotEmpty).toSet().join(', ');
    return pw.Container(
      padding: const pw.EdgeInsets.all(4),
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.7, color: PdfColors.grey700)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logo != null) ...[
                pw.Container(width: 18, height: 18, child: pw.Image(logo, fit: pw.BoxFit.contain)),
                pw.SizedBox(width: 4),
              ],
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      (establishmentName == null || establishmentName.isEmpty) ? 'Établissement scolaire' : establishmentName,
                      style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
                    ),
                    if ((establishmentPhone ?? '').isNotEmpty) pw.Text('Tél. $establishmentPhone', style: const pw.TextStyle(fontSize: 5.5)),
                    if ((establishmentEmail ?? '').isNotEmpty) pw.Text(establishmentEmail!, style: const pw.TextStyle(fontSize: 5.2)),
                    if ((approvalNumber ?? '').isNotEmpty) pw.Text('Agrément : $approvalNumber', style: const pw.TextStyle(fontSize: 5.2)),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text('APPEL À PAIEMENT', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Text('Période : $periodLabel${(schoolYearLabel ?? '').isEmpty ? '' : ' · $schoolYearLabel'}', style: const pw.TextStyle(fontSize: 5.8)),
          pw.Divider(height: 4, thickness: 0.4),
          pw.Text('À l’attention du parent / tuteur de :', style: const pw.TextStyle(fontSize: 5.8)),
          pw.Text(s.studentName, style: pw.TextStyle(fontSize: 7.2, fontWeight: pw.FontWeight.bold)),
          pw.Text('${s.registrationNumber} · ${cycleLabel ?? s.cycle} / ${classroomLabel ?? s.classroom}', style: const pw.TextStyle(fontSize: 5.8)),
          if (s.guardianName.isNotEmpty) pw.Text('Parent / tuteur : ${s.guardianName}', style: const pw.TextStyle(fontSize: 5.8)),
          pw.SizedBox(height: 2),
          pw.Text('Frais concernés : ${fees.isEmpty ? 'Frais scolaires' : fees}', maxLines: 2, style: const pw.TextStyle(fontSize: 5.8)),
          pw.Text(
            'MONTANT À PAYER : ${fmt(s.totalBalance)}',
            style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text('DATE LIMITE DE PAIEMENT : ${displayDate(s.paymentDeadline)}', style: pw.TextStyle(fontSize: 6.8, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
          pw.SizedBox(height: 2),
          pw.Text('Cher parent / tuteur, nous vous prions de régler les frais indiqués au plus tard à cette date.', style: const pw.TextStyle(fontSize: 5.5)),
          pw.Text('Document d’appel à paiement — ceci n’est pas un reçu de paiement.', style: pw.TextStyle(fontSize: 5.2, fontStyle: pw.FontStyle.italic)),
          if ((batchReference ?? '').isNotEmpty) pw.Text('Réf. lot : $batchReference', style: const pw.TextStyle(fontSize: 4.8, color: PdfColors.grey700)),
        ],
      ),
    );
  }
}
