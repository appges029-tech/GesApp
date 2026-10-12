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


class _NoticeSlice {
  const _NoticeSlice(this.student, this.from, this.to);
  final StudentNoticeData student;
  final int from, to;
  bool get continued => from > 0;
  bool get hasMore => to < student.lines.length;
}

/// Deux appels lisibles par feuille A4. Les nombreux frais sont répartis sur
/// des pages dédiées, jamais tronqués par la mise en page.
class PaymentNoticeBatchPdfService {
  static const int regularPerPage = 2;
  static const int compactLineLimit = 4;
  static const int extendedLineLimit = 10;

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
    final logo = (logoBytes == null || logoBytes.isEmpty)
        ? null : pw.MemoryImage(logoBytes);
    final pages = <List<_NoticeSlice>>[];
    var paired = <_NoticeSlice>[];
    void flushPair() {
      if (paired.isEmpty) return;
      pages.add(paired);
      paired = <_NoticeSlice>[];
    }
    for (final student in students.where((s) => s.totalBalance > 0)) {
      final count = student.lines.length;
      if (count <= compactLineLimit) {
        paired.add(_NoticeSlice(student, 0, count));
        if (paired.length == regularPerPage) flushPair();
      } else {
        flushPair();
        for (var from = 0; from < count; from += extendedLineLimit) {
          final to = (from + extendedLineLimit < count)
              ? from + extendedLineLimit : count;
          pages.add([_NoticeSlice(student, from, to)]);
        }
      }
    }
    flushPair();

    for (var index = 0; index < pages.length; index++) {
      final notices = pages[index];
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(24, 22, 24, 22),
        build: (_) => pw.Column(children: [
          for (var position = 0; position < notices.length; position++) ...[
            pw.Expanded(child: _notice(
              notices[position], periodLabel: periodLabel,
              establishmentName: establishmentName,
              establishmentAddress: establishmentAddress,
              establishmentPhone: establishmentPhone,
              establishmentEmail: establishmentEmail,
              approvalNumber: approvalNumber,
              schoolYearLabel: schoolYearLabel,
              batchReference: batchReference,
              cycleLabel: cycleLabel,
              classroomLabel: classroomLabel,
              logo: logo,
            )),
            if (position + 1 < notices.length) pw.SizedBox(height: 14),
          ],
          pw.SizedBox(height: 5),
          pw.Text(
            'Lot ${batchReference ?? '—'} · Page ${index + 1}/${pages.length} '
            '· Document à remettre au responsable légal',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ]),
      ));
    }
    return pdf.save();
  }

  String _amount(int value) {
    final original = value.abs().toString();
    final parts = <String>[];
    for (var end = original.length; end > 0; end -= 3) {
      final start = end - 3 < 0 ? 0 : end - 3;
      parts.insert(0, original.substring(start, end));
    }
    return "${value < 0 ? '-' : ''}${parts.join(' ')} FCFA";
  }

  String _date(String? value) {
    if (value == null || value.isEmpty) return 'Non renseignée';
    final date = value.split('-');
    return date.length == 3 ? '${date[2]}/${date[1]}/${date[0]}' : value;
  }

  pw.Widget _notice(
    _NoticeSlice slice, {
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
    pw.MemoryImage? logo,
  }) {
    final s = slice.student;
    final items = s.lines.sublist(slice.from, slice.to);
    final noticeReference = '${batchReference ?? 'APP'} / ${s.registrationNumber}';
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blueGrey600, width: 0.8),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
            if (logo != null) ...[
              pw.SizedBox(width: 38, height: 38,
                  child: pw.Image(logo, fit: pw.BoxFit.contain)),
              pw.SizedBox(width: 10),
            ],
            pw.Expanded(child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  (establishmentName ?? '').trim().isEmpty
                      ? 'Établissement scolaire' : establishmentName!,
                  style: pw.TextStyle(fontSize: 12,
                      fontWeight: pw.FontWeight.bold),
                ),
                if ((establishmentAddress ?? '').isNotEmpty)
                  pw.Text(establishmentAddress!,
                      style: const pw.TextStyle(fontSize: 8.5)),
                if ((establishmentPhone ?? '').isNotEmpty ||
                    (establishmentEmail ?? '').isNotEmpty)
                  pw.Text([
                    if ((establishmentPhone ?? '').isNotEmpty)
                      'Tél. $establishmentPhone',
                    if ((establishmentEmail ?? '').isNotEmpty)
                      establishmentEmail!,
                  ].join(' · '), style: const pw.TextStyle(fontSize: 8.5)),
                if ((approvalNumber ?? '').isNotEmpty)
                  pw.Text('Agrément : $approvalNumber',
                      style: const pw.TextStyle(fontSize: 8)),
              ],
            )),
          ]),
          pw.SizedBox(height: 6),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 5),
            decoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
            child: pw.Text(
              slice.continued ? 'APPEL À PAIEMENT — SUITE' : 'APPEL À PAIEMENT',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(color: PdfColors.white, fontSize: 13,
                  fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 7),
          pw.Text('Période : $periodLabel · Année : ${schoolYearLabel ?? '—'}',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.Text('Élève : ${s.studentName} · Matricule : ${s.registrationNumber}',
              style: pw.TextStyle(fontSize: 9.5,
                  fontWeight: pw.FontWeight.bold)),
          pw.Text('Classe : ${cycleLabel ?? s.cycle} / ${classroomLabel ?? s.classroom}',
              style: const pw.TextStyle(fontSize: 9)),
          if (s.guardianName.isNotEmpty)
            pw.Text('Parent / tuteur : ${s.guardianName}',
                style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const ['Rubrique', 'Dû', 'Payé', 'Reste'],
            data: [
              for (final item in items) [
                item.fee, _amount(item.amountDue),
                _amount(item.amountPaid),
                _amount(item.amountDue - item.amountPaid),
              ],
            ],
            columnWidths: {
              0: const pw.FlexColumnWidth(2.3),
              1: const pw.FlexColumnWidth(1.1),
              2: const pw.FlexColumnWidth(1.1),
              3: const pw.FlexColumnWidth(1.1),
            },
            headerStyle: pw.TextStyle(fontSize: 9,
                fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.blueGrey700),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 5, vertical: 5),
            border: pw.TableBorder.all(
                color: PdfColors.grey400, width: 0.4),
          ),
          pw.SizedBox(height: 7),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: const pw.BoxDecoration(color: PdfColors.grey100),
            child: pw.Row(children: [
              pw.Expanded(child: pw.Text('TOTAL RESTANT À RÉGLER',
                  style: pw.TextStyle(fontSize: 10,
                      fontWeight: pw.FontWeight.bold))),
              pw.Text(_amount(s.totalBalance), style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blueGrey900)),
            ]),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Date limite : ${_date(s.paymentDeadline)}',
              style: pw.TextStyle(fontSize: 9.5,
                  fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
          if (slice.hasMore)
            pw.Text('Autres rubriques sur la page suivante.',
                style: const pw.TextStyle(fontSize: 8.5)),
          pw.Spacer(),
          pw.Divider(color: PdfColors.grey500, height: 6),
          pw.Text('Réf. $noticeReference · Ceci est un appel à paiement, '
              'pas un reçu de règlement.',
              style: const pw.TextStyle(
                  fontSize: 8, color: PdfColors.grey700)),
        ],
      ),
    );
  }
}
