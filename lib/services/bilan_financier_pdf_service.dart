import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/utils/formatters.dart';
import '../data/repositories/report_repository.dart';
import 'document_identity.dart';

/// Génère le "Bilan financier global" en PDF : indicateurs clés (dont le
/// bénéfice net de l'établissement), évolution mensuelle des recettes et
/// dépenses, répartition des dépenses par catégorie et taux de recouvrement
/// par cycle — avec des graphiques dessinés directement dans le PDF (aucune
/// dépendance externe requise) pour rester facilement compréhensible.
class BilanFinancierPdfService {
  static const _revenueColor = PdfColor.fromInt(0xFF2E7D32);
  static const _expenseColor = PdfColor.fromInt(0xFFC62828);
  static const _balanceColor = PdfColor.fromInt(0xFF1565C0);
  static const _accentColor = PdfColor.fromInt(0xFF37474F);

  Future<Uint8List> build({
    required FinancialReportSummary global,
    required List<Map<String, Object?>> monthlyTrend,
    required List<Map<String, Object?>> expensesByCategory,
    required List<Map<String, Object?>> recoveryByCycle,
    String? establishmentName,
    String? establishmentAddress,
    String? establishmentPhone,
    String? schoolYearLabel,
    String? periodLabel,
    DocumentIdentity? identity,
    String? reference,
  }) async {
    final pdf = pw.Document();
    final generatedAt = DateTime.now();
    final generatedAtLabel = _formatDateTime(generatedAt);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 24),
        header: (context) => identity == null
            ? _header(
                establishmentName: establishmentName,
                establishmentAddress: establishmentAddress,
                establishmentPhone: establishmentPhone,
                schoolYearLabel: schoolYearLabel,
              )
            : DocumentPdfChrome.header(identity!),
        footer: (context) => identity == null
            ? pw.Container(
                alignment: pw.Alignment.centerRight,
                margin: const pw.EdgeInsets.only(top: 6),
                child: pw.Text(
                  'Généré le $generatedAtLabel · Page ${context.pageNumber}/${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
                ),
              )
            : DocumentPdfChrome.footer(context, identity!, reference: reference),
        build: (context) => [
          pw.Text('Bilan financier global',
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: _accentColor)),
          if ((reference ?? '').isNotEmpty) pw.Text('Référence : $reference', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
          pw.SizedBox(height: 3),
          pw.Text(
            periodLabel ?? 'Situation des recettes, dépenses et du solde des flux présentés.',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 16),
          _sectionTitle('Indicateurs clés'),
          _kpiGrid(global),
          pw.SizedBox(height: 20),
          _sectionTitle('Évolution des recettes, dépenses et du solde (${monthlyTrend.length} mois dans la période)'),
          pw.SizedBox(height: 8),
          _trendChart(monthlyTrend),
          pw.SizedBox(height: 10),
          _trendTable(monthlyTrend),
          pw.SizedBox(height: 20),
          _sectionTitle('Répartition des dépenses par catégorie'),
          pw.SizedBox(height: 8),
          if (expensesByCategory.isEmpty)
            pw.Text('Aucune dépense enregistrée sur la période.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600))
          else ...[
            _categoryBarChart(expensesByCategory),
            pw.SizedBox(height: 10),
            _categoryTable(expensesByCategory),
          ],
          pw.SizedBox(height: 20),
          _sectionTitle('Taux de recouvrement par cycle'),
          pw.SizedBox(height: 8),
          if (recoveryByCycle.isEmpty)
            pw.Text('Aucune donnée de recouvrement disponible.',
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600))
          else ...[
            _recoveryBarChart(recoveryByCycle),
            pw.SizedBox(height: 10),
            _recoveryTable(recoveryByCycle),
          ],
          pw.SizedBox(height: 18),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(
              'Le solde présenté correspond aux recettes comptées par ce rapport moins les dépenses comptées sur la période ; '
              'il ne constitue pas à lui seul un résultat net comptable ou un solde de caisse certifié. Document généré depuis GesApp.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
          ),
        ],
      ),
    );
    return pdf.save();
  }

  String _formatDateTime(DateTime value) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${twoDigits(value.day)}/${twoDigits(value.month)}/${value.year} '
        'à ${twoDigits(value.hour)}:${twoDigits(value.minute)}';
  }

  // ---------------------------------------------------------------------
  // En-tête
  // ---------------------------------------------------------------------
  pw.Widget _header({
    String? establishmentName,
    String? establishmentAddress,
    String? establishmentPhone,
    String? schoolYearLabel,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              (establishmentName == null || establishmentName.isEmpty) ? 'Établissement scolaire' : establishmentName,
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
            if (schoolYearLabel != null && schoolYearLabel.isNotEmpty)
              pw.Text('Année scolaire : $schoolYearLabel', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          ],
        ),
        if ((establishmentAddress ?? '').isNotEmpty || (establishmentPhone ?? '').isNotEmpty)
          pw.Text(
            [
              if ((establishmentAddress ?? '').isNotEmpty) establishmentAddress,
              if ((establishmentPhone ?? '').isNotEmpty) 'Tél. $establishmentPhone',
            ].join(' · '),
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        pw.Divider(color: PdfColors.grey400, height: 12),
      ],
    );
  }

  pw.Widget _sectionTitle(String title) => pw.Text(
        title,
        style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold, color: _accentColor),
      );

  // ---------------------------------------------------------------------
  // Indicateurs clés
  // ---------------------------------------------------------------------
  pw.Widget _kpiGrid(FinancialReportSummary s) {
    final cards = [
      _kpiCard('Attendu', formatXaf(s.expected), PdfColors.blueGrey700),
      _kpiCard('Encaissé', formatXaf(s.allocated), _revenueColor),
      _kpiCard('Reste à recouvrer', formatXaf(s.outstanding), PdfColors.orange800),
      _kpiCard('Taux de recouvrement', '${(s.recoveryRate * 100).toStringAsFixed(1)} %', _balanceColor),
      _kpiCard('Recettes encaissées', formatXaf(s.revenue), _revenueColor),
      _kpiCard('Dépenses', formatXaf(s.expenses), _expenseColor),
      _kpiCard(
        'Solde net des flux présentés',
        formatXaf(s.cashBalance),
        s.cashBalance >= 0 ? _revenueColor : _expenseColor,
        emphasize: true,
      ),
    ];
    return pw.Wrap(
      spacing: 8,
      runSpacing: 8,
      children: cards,
    );
  }

  pw.Widget _kpiCard(String label, String value, PdfColor color, {bool emphasize = false}) {
    return pw.Container(
      width: 158,
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: emphasize ? PdfColor.fromInt(0xFFF1F8F4) : PdfColors.white,
        border: pw.Border.all(color: emphasize ? color : PdfColors.grey300, width: emphasize ? 1.2 : 0.6),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(value, style: pw.TextStyle(fontSize: emphasize ? 13 : 11.5, fontWeight: pw.FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Graphique d'évolution mensuelle (barres groupées recettes/dépenses)
  // ---------------------------------------------------------------------
  pw.Widget _trendChart(List<Map<String, Object?>> rows) {
    if (rows.isEmpty) return pw.SizedBox();
    final maxValue = rows.fold<num>(1, (max, r) {
      final rev = (r['revenue'] as num?) ?? 0;
      final exp = (r['expenses'] as num?) ?? 0;
      return [max, rev, exp].reduce((a, b) => a > b ? a : b);
    });
    const chartHeight = 130.0;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(children: [
          _legendDot(_revenueColor, 'Recettes'),
          pw.SizedBox(width: 14),
          _legendDot(_expenseColor, 'Dépenses'),
        ]),
        pw.SizedBox(height: 6),
        pw.Container(
          height: chartHeight,
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.7)),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: rows.map((r) {
              final rev = ((r['revenue'] as num?) ?? 0).toDouble();
              final exp = ((r['expenses'] as num?) ?? 0).toDouble();
              final revH = maxValue <= 0 ? 0.0 : (rev / maxValue) * (chartHeight - 18);
              final expH = maxValue <= 0 ? 0.0 : (exp / maxValue) * (chartHeight - 18);
              return pw.Expanded(
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Container(width: 9, height: revH < 1 ? 1 : revH, color: _revenueColor),
                        pw.SizedBox(width: 2),
                        pw.Container(width: 9, height: expH < 1 ? 1 : expH, color: _expenseColor),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text('${r['label']}', style: const pw.TextStyle(fontSize: 6.5), textAlign: pw.TextAlign.center),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  pw.Widget _legendDot(PdfColor color, String label) => pw.Row(children: [
        pw.Container(width: 8, height: 8, color: color),
        pw.SizedBox(width: 4),
        pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
      ]);

  pw.Widget _trendTable(List<Map<String, Object?>> rows) {
    return pw.TableHelper.fromTextArray(
      headers: const ['Mois', 'Recettes', 'Dépenses', 'Solde'],
      data: rows
          .map((r) => [
                '${r['label']}',
                formatXaf((r['revenue'] as num?) ?? 0),
                formatXaf((r['expenses'] as num?) ?? 0),
                formatXaf((r['balance'] as num?) ?? 0),
              ])
          .toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8.5),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
      cellAlignments: const {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
    );
  }

  // ---------------------------------------------------------------------
  // Répartition des dépenses par catégorie (barres horizontales)
  // ---------------------------------------------------------------------
  pw.Widget _categoryBarChart(List<Map<String, Object?>> rows) {
    final top = rows.take(8).toList();
    final maxValue = top.fold<num>(1, (max, r) => (r['total'] as num? ?? 0) > max ? (r['total'] as num) : max);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: top.map((r) {
        final total = (r['total'] as num?) ?? 0;
        final ratio = maxValue <= 0 ? 0.0 : total / maxValue;
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
          child: pw.Row(
            children: [
              pw.SizedBox(width: 110, child: pw.Text('${r['category']}', style: const pw.TextStyle(fontSize: 8))),
              pw.Expanded(
                child: pw.Stack(
                  children: [
                    pw.Container(height: 10, color: PdfColors.grey200),
                    pw.LayoutBuilder(
                      builder: (context, constraints) => pw.Container(
                        width: (constraints?.maxWidth ?? 0) * ratio.clamp(0.0, 1.0),
                        height: 10,
                        color: _expenseColor,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 6),
              pw.SizedBox(width: 68, child: pw.Text(formatXaf(total), style: const pw.TextStyle(fontSize: 7.5), textAlign: pw.TextAlign.right)),
            ],
          ),
        );
      }).toList(),
    );
  }

  pw.Widget _categoryTable(List<Map<String, Object?>> rows) {
    return pw.TableHelper.fromTextArray(
      headers: const ['Catégorie', 'Opérations', 'Total'],
      data: rows
          .map((r) => ['${r['category']}', '${r['operations']}', formatXaf((r['total'] as num?) ?? 0)])
          .toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8.5),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
      cellAlignments: const {1: pw.Alignment.center, 2: pw.Alignment.centerRight},
    );
  }

  // ---------------------------------------------------------------------
  // Taux de recouvrement par cycle (barres horizontales en %)
  // ---------------------------------------------------------------------
  pw.Widget _recoveryBarChart(List<Map<String, Object?>> rows) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: rows.map((r) {
        final rawRate = r['rate'];
        final rate = rawRate is num ? rawRate.toDouble() : double.tryParse('$rawRate') ?? 0;
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
          child: pw.Row(
            children: [
              pw.SizedBox(width: 110, child: pw.Text('${r['label']}', style: const pw.TextStyle(fontSize: 8))),
              pw.Expanded(
                child: pw.Stack(
                  children: [
                    pw.Container(height: 10, color: PdfColors.grey200),
                    pw.LayoutBuilder(
                      builder: (context, constraints) => pw.Container(
                        width: (constraints?.maxWidth ?? 0) * (rate / 100).clamp(0.0, 1.0),
                        height: 10,
                        color: _balanceColor,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 6),
              pw.SizedBox(width: 40, child: pw.Text('${rate.toStringAsFixed(1)} %', style: const pw.TextStyle(fontSize: 7.5), textAlign: pw.TextAlign.right)),
            ],
          ),
        );
      }).toList(),
    );
  }

  pw.Widget _recoveryTable(List<Map<String, Object?>> rows) {
    return pw.TableHelper.fromTextArray(
      headers: const ['Cycle', 'Élèves', 'Attendu', 'Payé', 'Reste', 'Taux'],
      data: rows.map((r) {
        final rawRate = r['rate'];
        final rate = rawRate is num ? rawRate.toDouble() : double.tryParse('$rawRate') ?? 0;
        return [
          '${r['label']}',
          '${r['students_count']}',
          formatXaf((r['expected'] as num?) ?? 0),
          formatXaf((r['collected'] as num?) ?? 0),
          formatXaf((r['outstanding'] as num?) ?? 0),
          '${rate.toStringAsFixed(1)} %',
        ];
      }).toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 8.5),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
      cellAlignments: const {
        1: pw.Alignment.center,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
        5: pw.Alignment.centerRight,
      },
    );
  }
}
