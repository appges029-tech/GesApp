import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/session/operator_session.dart';
import '../data/repositories/settings_repository.dart';
import 'student_media_service.dart';

class DocumentIdentity {
  const DocumentIdentity({
    required this.name,
    this.address = '',
    this.phone = '',
    this.email = '',
    this.approvalNumber = '',
    this.schoolYear = '',
    this.logoBytes,
    this.generatedBy = '',
  });

  final String name;
  final String address;
  final String phone;
  final String email;
  final String approvalNumber;
  final String schoolYear;
  final Uint8List? logoBytes;
  final String generatedBy;

  static Future<DocumentIdentity> fromEstablishment(EstablishmentData? data) async {
    Uint8List? logo;
    final path = data?.logoPath.trim() ?? '';
    if (path.isNotEmpty) {
      try {
        logo = await StudentMediaService().readStoredFileBytes(path);
      } catch (_) {
        logo = null;
      }
    }
    return DocumentIdentity(
      name: (data?.name.trim().isNotEmpty ?? false) ? data!.name.trim() : 'Établissement scolaire',
      address: data?.address.trim() ?? '',
      phone: data?.phone.trim() ?? '',
      email: data?.email.trim() ?? '',
      approvalNumber: data?.approvalNumber.trim() ?? '',
      schoolYear: data?.schoolYearLabel.trim() ?? '',
      logoBytes: logo,
      generatedBy: OperatorSession.current,
    );
  }
}

abstract final class DocumentPdfChrome {
  static pw.Widget header(DocumentIdentity identity, {String? documentTitle}) {
    final logo = identity.logoBytes == null || identity.logoBytes!.isEmpty
        ? null
        : pw.MemoryImage(identity.logoBytes!);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logo != null) ...[
              pw.Container(width: 42, height: 42, child: pw.Image(logo, fit: pw.BoxFit.contain)),
              pw.SizedBox(width: 10),
            ],
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(identity.name, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  if (identity.address.isNotEmpty) pw.Text(identity.address, style: const pw.TextStyle(fontSize: 8)),
                  if (identity.phone.isNotEmpty || identity.email.isNotEmpty)
                    pw.Text([
                      if (identity.phone.isNotEmpty) 'Tél. ${identity.phone}',
                      if (identity.email.isNotEmpty) identity.email,
                    ].join(' · '), style: const pw.TextStyle(fontSize: 8)),
                  if (identity.approvalNumber.isNotEmpty)
                    pw.Text('Agrément : ${identity.approvalNumber}', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
            ),
            if (identity.schoolYear.isNotEmpty)
              pw.Text('Année scolaire\n${identity.schoolYear}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8)),
          ],
        ),
        if (documentTitle != null && documentTitle.trim().isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Divider(color: PdfColors.grey500, height: 6),
          pw.Center(child: pw.Text(documentTitle, style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold))),
        ],
      ],
    );
  }

  static pw.Widget footer(pw.Context context, DocumentIdentity identity, {String? reference}) {
    final generated = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp = '${two(generated.day)}/${two(generated.month)}/${generated.year} ${two(generated.hour)}:${two(generated.minute)}';
    final left = <String>[
      if ((reference ?? '').trim().isNotEmpty) 'Réf. ${reference!.trim()}',
      if (identity.generatedBy.trim().isNotEmpty) 'Généré par ${identity.generatedBy.trim()}',
      'le $stamp',
    ].join(' · ');
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      padding: const pw.EdgeInsets.only(top: 5),
      decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400, width: .5))),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(child: pw.Text(left, style: const pw.TextStyle(fontSize: 6.8, color: PdfColors.grey600))),
          pw.Text('Page ${context.pageNumber}/${context.pagesCount}', style: const pw.TextStyle(fontSize: 6.8, color: PdfColors.grey600)),
        ],
      ),
    );
  }
}
